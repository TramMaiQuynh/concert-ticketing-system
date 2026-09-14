using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration tests cho CheckInRepository (connection API thật):
/// - Ticket hợp lệ + staff được phân công → ValidationResult = SUCCESS
/// - Check-in lặp → ALREADY_USED (hoặc DUPLICATE_CHECKIN)
/// - Ticket của concert khác → WRONG_EVENT
/// - Staff chưa được phân công → UNAUTHORIZED
/// </summary>
public sealed class CheckInRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public CheckInRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private CheckInRepository CheckInRepo() => new(_fx.ApiFactory);
    private BookingRepository BookingRepo() => new(_fx.ApiFactory);
    private PaymentRepository PaymentRepo() => new(_fx.ApiFactory, _fx.PaymentSignatureSecret, DbFixture.TestGateway);

    /// <summary>Dựng concert + booking + payment confirmed + staff được assign concert.</summary>
    private async Task<(ConcertBaseline baseline, string ticketCode, int staffUserId)>
        SetupCheckedInTicketAsync(bool assignStaff)
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await BookingRepo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var payment = PaymentRepo();
        var init = await payment.InitiateAsync(booking.BookingId, baseline.CustomerUserId);
        await payment.ConfirmAsync(booking.BookingId, init.PaymentId, _fx.ComputePaymentSignature(booking.BookingId, init.PaymentId, init.Amount), "PROVIDER");

        var ticketCode = await s.GetTicketCodeAsync(booking.BookingId);
        ticketCode.Should().NotBeNullOrEmpty();

        var staff = await s.CreateUserAsync("Check-in Staff");
        if (assignStaff)
        {
            var adminRepo = new AdminRepository(_fx.ApiFactory);
            await adminRepo.AddCheckinStaffAssignmentAsync(baseline.AdminUserId,
                new AddCheckinStaffAssignmentRequest(staff, new List<int> { baseline.ConcertId }));
        }

        return (baseline, ticketCode, staff);
    }

    [Fact(DisplayName = "CheckIn: ticket hợp lệ + staff được phân công → SUCCESS")]
    public async Task CheckIn_ValidTicket_ReturnsSuccess()
    {
        var (baseline, ticketCode, staff) = await SetupCheckedInTicketAsync(assignStaff: true);

        var result = await CheckInRepo().CheckInAsync(staff,
            new CheckInRequest(ticketCode, baseline.ConcertId));

        result.ValidationResult.Should().Be("SUCCESS");
    }

    [Fact(DisplayName = "CheckIn: check-in lặp → ALREADY_USED")]
    public async Task CheckIn_Duplicate_ReturnsAlreadyUsed()
    {
        var (baseline, ticketCode, staff) = await SetupCheckedInTicketAsync(assignStaff: true);

        var repo = CheckInRepo();
        var first = await repo.CheckInAsync(staff, new CheckInRequest(ticketCode, baseline.ConcertId));
        first.ValidationResult.Should().Be("SUCCESS");

        var second = await repo.CheckInAsync(staff, new CheckInRequest(ticketCode, baseline.ConcertId));
        second.ValidationResult.Should().BeOneOf("ALREADY_USED", "DUPLICATE_CHECKIN");
    }

    [Fact(DisplayName = "CheckIn: concert khác với ticket → WRONG_EVENT")]
    public async Task CheckIn_WrongConcert_ReturnsWrongEvent()
    {
        var (baseline, ticketCode, staff) = await SetupCheckedInTicketAsync(assignStaff: true);

        var s = NewSeeder();
        var organizer2 = await s.CreateUserAsync("Organizer");
        var artist2 = await s.CreateArtistAsync();
        var venue2 = await s.CreateVenueAsync();
        var concert2 = await s.CreateConcertDraftAsync(organizer2, artist2, venue2);

        var result = await CheckInRepo().CheckInAsync(staff,
            new CheckInRequest(ticketCode, concert2));

        result.ValidationResult.Should().Be("WRONG_EVENT");
    }

    [Fact(DisplayName = "CheckIn: staff chưa được phân công concert → UNAUTHORIZED")]
    public async Task CheckIn_StaffNotAssigned_ReturnsUnauthorized()
    {
        var (baseline, ticketCode, staff) = await SetupCheckedInTicketAsync(assignStaff: false);

        var result = await CheckInRepo().CheckInAsync(staff,
            new CheckInRequest(ticketCode, baseline.ConcertId));

        result.ValidationResult.Should().Be("UNAUTHORIZED");
    }

    [Fact(DisplayName = "Preview: staff được phân công thấy tên khách, vé chưa đổi trạng thái")]
    public async Task Preview_StaffAssigned_ReturnsAttendeeName_WithoutMutatingTicket()
    {
        var (baseline, ticketCode, staff) = await SetupCheckedInTicketAsync(assignStaff: true);

        // VW_CheckInStaffUserAccount lọc theo SESSION_CONTEXT — repo phải mở connection
        // đóng vai đúng staff đó, y hệt IDbConnectionFactory thật làm theo JWT.
        var previewRepo = new CheckInRepository(_fx.ApiFactory.AsUser(staff));
        var preview = await previewRepo.PreviewAsync(new CheckInRequest(ticketCode, baseline.ConcertId));

        preview.Should().NotBeNull();
        preview!.TicketStatus.Should().Be("Issued", "preview chỉ đọc, không được đổi trạng thái vé");
        preview.SeatCode.Should().NotBeNullOrEmpty();
        preview.CategoryName.Should().NotBeNullOrEmpty();
        preview.DisplayName.Should().NotBeNullOrEmpty();

        // Xác nhận thật sự không mutate: check-in thật ngay sau đó vẫn phải SUCCESS
        // (nếu Preview lỡ dùng nhầm sp_CheckInTicket, vé đã Used và bước này sẽ ALREADY_USED).
        var real = await CheckInRepo().CheckInAsync(staff, new CheckInRequest(ticketCode, baseline.ConcertId));
        real.ValidationResult.Should().Be("SUCCESS");
    }

    [Fact(DisplayName = "Preview: staff chưa được phân công concert → null (không lộ vé có tồn tại hay không)")]
    public async Task Preview_StaffNotAssigned_ReturnsNull()
    {
        var (baseline, ticketCode, staff) = await SetupCheckedInTicketAsync(assignStaff: false);

        var previewRepo = new CheckInRepository(_fx.ApiFactory.AsUser(staff));
        var preview = await previewRepo.PreviewAsync(new CheckInRequest(ticketCode, baseline.ConcertId));

        preview.Should().BeNull("nhân viên chưa được phân công không được thấy vé của concert này tồn tại hay không");
    }

    [Fact(DisplayName = "Preview: mã vé không tồn tại → null")]
    public async Task Preview_UnknownTicketCode_ReturnsNull()
    {
        var (baseline, _, staff) = await SetupCheckedInTicketAsync(assignStaff: true);

        var previewRepo = new CheckInRepository(_fx.ApiFactory.AsUser(staff));
        var preview = await previewRepo.PreviewAsync(new CheckInRequest("NOPE-DOES-NOT-EXIST", baseline.ConcertId));

        preview.Should().BeNull();
    }
}