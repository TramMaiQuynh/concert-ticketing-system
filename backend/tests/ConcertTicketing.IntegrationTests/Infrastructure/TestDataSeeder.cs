using Dapper;

namespace ConcertTicketing.IntegrationTests.Infrastructure;

/// <summary>
/// Seeder tạo dữ liệu nền cho integration test (qua connection admin, theo đúng schema DB).
/// Mọi object dùng suffix duy nhất của fixture để không trùng và dễ cleanup.
/// </summary>
public sealed class TestDataSeeder
{
    private readonly DbFixture _fixture;
    private readonly string _suffix;
    private readonly string _testId;

    public TestDataSeeder(DbFixture fixture)
    {
        _fixture = fixture;
        _suffix = fixture.Suffix;
        _testId = Guid.NewGuid().ToString("N")[..4];
    }

    public string Username(string role, int instance = 0) => $"it_{role}_{instance}_{_testId}_{_suffix}";
    public string ConcertName => $"IT-Concert-{_testId}-{_suffix}";

    /// <summary>Tên duy nhất cho các object tạo qua repository (SP) trong test.</summary>
    public string VenueName => $"IT-Venue-{_testId}-{_suffix}";
    public string ZoneCode => $"Z{_testId}{_suffix}";
    public string SeatCode => $"S{_testId}{_suffix}";
    public string CategoryName => $"IT-Cat-{_testId}-{_suffix}";
    public string PromotionName => $"IT-Promo-{_testId}-{_suffix}";
    public string DiscountCodeValue => $"DC-{_testId}-{_suffix}";

    /// <summary>Tạo user + gán role (Admin/Organizer/Customer/Check-in Staff).</summary>
    /// <param name="instance">Lần tạo thứ mấy (0,1,2,...) — để tạo NHIỀU user cùng role.</param>
    public async Task<int> CreateUserAsync(string role, string passwordHash = "x", int instance = 0)
    {
        var username = Username(role, instance);
        var existing = await _fixture.QueryAdminAsync<int?>(
            "SELECT UserID FROM UserAccount WHERE Username = @u", new { u = username });
        if (existing.HasValue) return existing.Value;

        await _fixture.ExecAdminAsync(@"
            INSERT INTO UserAccount (Username, AccountStatus, Email, DisplayName, PasswordHash, CreatedTimestamp)
            VALUES (@u, 'Active', @email, @u, @ph, SYSUTCDATETIME());",
            new { u = username, email = $"{username}@it.test", ph = passwordHash });

        var userId = (await _fixture.QueryAdminAsync<int?>(
            "SELECT UserID FROM UserAccount WHERE Username = @u", new { u = username }))!.Value;

        await _fixture.ExecAdminAsync(@"
            INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus, AssignedTimestamp)
            SELECT @uid, RoleID, 'Active', SYSUTCDATETIME() FROM Role WHERE RoleName = @role;",
            new { uid = userId, role = role });

        return userId;
    }

    public async Task<int> CreateArtistAsync()
    {
        var name = $"IT-Artist-{_testId}-{_suffix}";
        await _fixture.ExecAdminAsync(
            "INSERT INTO Artist (ArtistName) VALUES (@n);", new { n = name });
        return (await _fixture.QueryAdminAsync<int?>(
            "SELECT ArtistID FROM Artist WHERE ArtistName = @n", new { n = name }))!.Value;
    }

    public async Task<int> CreateVenueAsync()
    {
        var name = $"IT-Venue-{_testId}-{_suffix}";
        await _fixture.ExecAdminAsync(
            "INSERT INTO Venue (VenueName, Address, VenueStatus, CreatedTimestamp, UpdatedTimestamp) " +
            "VALUES (@n, 'IT Address', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME());", new { n = name });
        return (await _fixture.QueryAdminAsync<int?>(
            "SELECT VenueID FROM Venue WHERE VenueName = @n", new { n = name }))!.Value;
    }

    public async Task<int> CreateZoneAsync(int venueId)
    {
        var code = $"Z{_testId}{_suffix}";
        await _fixture.ExecAdminAsync(
            "INSERT INTO Zone (VenueID, ZoneCode, ZoneName) VALUES (@vid, @code, @code);",
            new { vid = venueId, code = code });
        return (await _fixture.QueryAdminAsync<int?>(
            "SELECT ZoneID FROM Zone WHERE VenueID = @vid AND ZoneCode = @code",
            new { vid = venueId, code = code }))!.Value;
    }

    public async Task<int> CreateSeatAsync(int venueId, int zoneId, int index = 0)
    {
        var code = $"{index}S{_testId}{_suffix}";
        await _fixture.ExecAdminAsync(
            "INSERT INTO Seat (ZoneID, VenueID, SeatCode, SeatLabel) VALUES (@zid, @vid, @code, @code);",
            new { zid = zoneId, vid = venueId, code = code });
        return (await _fixture.QueryAdminAsync<int?>(
            "SELECT SeatID FROM Seat WHERE VenueID = @vid AND SeatCode = @code",
            new { vid = venueId, code = code }))!.Value;
    }

    /// <summary>Tạo Concert ở trạng thái Draft (chưa OnSale).</summary>
    /// <param name="concertName">Tên tùy chọn (mặc định dùng tên cố định của seeder).</param>
    public async Task<int> CreateConcertDraftAsync(int organizerId, int artistId, int venueId,
        bool waitlistEnabled = false, bool fairAccess = false, int purchaseLimit = 4,
        string? concertName = null)
    {
        var name = concertName ?? ConcertName;
        await _fixture.ExecAdminAsync(@"
            INSERT INTO Concert (OrganizerUserID, ArtistID, VenueID, ConcertName,
                StartDatetime, EndDatetime, ConcertStatus,
                SaleStartDatetime, SaleEndDatetime, PurchaseLimit,
                FairAccessEnabled, WaitlistEnabled, SalesPaused)
            VALUES (@org, @art, @vid, @name,
                DATEADD(day,1,SYSUTCDATETIME()), DATEADD(day,2,SYSUTCDATETIME()), 'Draft',
                DATEADD(day,-1,SYSUTCDATETIME()), DATEADD(day,30,SYSUTCDATETIME()), @pl,
                @fair, @wl, 0);",
            new { org = organizerId, art = artistId, vid = venueId, name = name,
                  fair = fairAccess, wl = waitlistEnabled, pl = purchaseLimit });
        return (await _fixture.QueryAdminAsync<int?>(
            "SELECT ConcertID FROM Concert WHERE ConcertName = @n", new { n = name }))!.Value;
    }

    public async Task<int> CreateTicketCategoryAsync(int concertId)
    {
        var name = $"IT-Cat-{_testId}-{_suffix}";
        await _fixture.ExecAdminAsync(@"
            INSERT INTO TicketCategory (ConcertID, CategoryName, CategoryDescription, CategoryStatus)
            VALUES (@cid, @name, 'IT', 'Active');",
            new { cid = concertId, name = name });
        return (await _fixture.QueryAdminAsync<int?>(
            "SELECT TicketCategoryID FROM TicketCategory WHERE ConcertID = @cid AND CategoryName = @name",
            new { cid = concertId, name = name }))!.Value;
    }

    public async Task<int> CreateEventSeatAsync(int concertId, int seatId, int categoryId, decimal price = 100000)
    {
        await _fixture.ExecAdminAsync(@"
            INSERT INTO EventSeat (ConcertID, SeatID, TicketCategoryID, SalePrice, InventoryStatus, AddedTimestamp)
            VALUES (@cid, @sid, @cat, @price, 'Available', SYSUTCDATETIME());",
            new { cid = concertId, sid = seatId, cat = categoryId, price = price });
        return (await _fixture.QueryAdminAsync<int?>(
            "SELECT EventSeatID FROM EventSeat WHERE ConcertID = @cid AND SeatID = @sid",
            new { cid = concertId, sid = seatId }))!.Value;
    }

    /// <summary>Đưa Concert lên OnSale theo đúng state machine (Draft→Published→OnSale) — trigger cho phép.</summary>
    public async Task SetConcertOnSaleAsync(int concertId)
    {
        // Đi qua Published trước — trigger TRG_Concert_StateTransition chặn Draft→OnSale trực tiếp.
        await _fixture.ExecAdminAsync(
            "UPDATE Concert SET ConcertStatus = 'Published' WHERE ConcertID = @id;", new { id = concertId });
        await _fixture.ExecAdminAsync(
            "UPDATE Concert SET ConcertStatus = 'OnSale' WHERE ConcertID = @id;", new { id = concertId });
    }

    public async Task<string> GetTicketCodeAsync(int bookingId)
        => (await _fixture.QueryAdminAsync<string?>(
            "SELECT TOP 1 TicketCode FROM Ticket WHERE BookingID = @id", new { id = bookingId }))!;
}