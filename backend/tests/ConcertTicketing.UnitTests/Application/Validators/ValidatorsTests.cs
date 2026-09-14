using System.Linq;
using Xunit;
using FluentAssertions;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Validators;

namespace ConcertTicketing.UnitTests.Application.Validators;

public class LoginValidatorTests
{
    private readonly LoginValidator _validator = new();

    [Fact]
    public void Username_Empty_ShouldFail()
    {
        var request = new LoginRequest("", "123456");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Username");
    }

    [Fact]
    public void Username_TooLong_ShouldFail()
    {
        var request = new LoginRequest(new string('a', 101), "123456");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Username");
    }

    [Fact]
    public void Password_Empty_ShouldFail()
    {
        var request = new LoginRequest("user1", "");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Password");
    }

    [Fact]
    public void Password_TooShort_ShouldFail()
    {
        var request = new LoginRequest("user1", "12345");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Password");
    }

    [Fact]
    public void ValidInput_ShouldPass()
    {
        var request = new LoginRequest("user1", "123456");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeTrue();
    }
}

public class RegisterValidatorTests
{
    private readonly RegisterValidator _validator = new();

    [Fact]
    public void Username_Empty_ShouldFail()
    {
        var request = new RegisterRequest("", "test@example.com", "Password123", "Test User");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Username");
    }

    [Fact]
    public void Username_TooShort_ShouldFail()
    {
        var request = new RegisterRequest("ab", "test@example.com", "Password123", "Test User");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Username");
    }

    [Fact]
    public void Username_TooLong_ShouldFail()
    {
        var request = new RegisterRequest(new string('a', 51), "test@example.com", "Password123", "Test User");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Username");
    }

    [Fact]
    public void Username_SpecialChars_ShouldFail()
    {
        var request = new RegisterRequest("user@name", "test@example.com", "Password123", "Test User");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Username");
    }

    [Fact]
    public void Username_ValidUnderscore_ShouldPass()
    {
        var request = new RegisterRequest("user_name", "test@example.com", "Password123", "Test User");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Email_Invalid_ShouldFail()
    {
        var request = new RegisterRequest("username", "not-email", "Password123", "Test User");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Email");
    }

    [Fact]
    public void Password_TooShort_ShouldFail()
    {
        var request = new RegisterRequest("username", "test@example.com", "Abc1", "Test User"); // 4 chars
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Password");
    }

    [Fact]
    public void Password_NoUppercase_ShouldFail()
    {
        var request = new RegisterRequest("username", "test@example.com", "abcdefg1", "Test User");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Password");
    }

    [Fact]
    public void Password_NoDigit_ShouldFail()
    {
        var request = new RegisterRequest("username", "test@example.com", "Abcdefgh", "Test User");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Password");
    }

    [Fact]
    public void DisplayName_Empty_ShouldFail()
    {
        var request = new RegisterRequest("username", "test@example.com", "Password123", "");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "DisplayName");
    }

    [Fact]
    public void DisplayName_TooLong_ShouldFail()
    {
        var request = new RegisterRequest("username", "test@example.com", "Password123", new string('a', 201));
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "DisplayName");
    }

    [Fact]
    public void ValidInput_ShouldPass()
    {
        var request = new RegisterRequest("user_123", "test@example.com", "Password123", "Display Name");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeTrue();
    }
}

public class CreateBookingValidatorTests
{
    private readonly CreateBookingValidator _validator = new();

    [Fact]
    public void ConcertId_Zero_ShouldFail()
    {
        var request = new CreateBookingRequest(0, new System.Collections.Generic.List<int> { 1 });
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "ConcertId");
    }

    [Fact]
    public void ConcertId_Negative_ShouldFail()
    {
        var request = new CreateBookingRequest(-1, new System.Collections.Generic.List<int> { 1 });
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "ConcertId");
    }

    [Fact]
    public void SeatIds_Empty_ShouldFail()
    {
        var request = new CreateBookingRequest(1, new System.Collections.Generic.List<int>());
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "SeatIds");
    }

    [Fact]
    public void SeatIds_OverLimit_ShouldFail()
    {
        var request = new CreateBookingRequest(1, Enumerable.Range(1, 11).ToList());
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "SeatIds");
    }

    [Fact]
    public void SeatIds_Duplicate_ShouldFail()
    {
        var request = new CreateBookingRequest(1, new System.Collections.Generic.List<int> { 1, 1, 2 });
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "SeatIds");
    }

    [Fact]
    public void SeatIds_ContainsZero_ShouldFail()
    {
        var request = new CreateBookingRequest(1, new System.Collections.Generic.List<int> { 0, 1 });
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        // Element index might be used in PropertyName, e.g. SeatIds[0]
        result.Errors.Should().Contain(e => e.PropertyName.StartsWith("SeatIds"));
    }

    [Fact]
    public void ValidInput_ShouldPass()
    {
        var request = new CreateBookingRequest(1, new System.Collections.Generic.List<int> { 1, 2, 3 });
        var result = _validator.Validate(request);
        result.IsValid.Should().BeTrue();
    }
}

public class CheckInValidatorTests
{
    private readonly CheckInValidator _validator = new();

    [Fact]
    public void TicketCode_Empty_ShouldFail()
    {
        var request = new CheckInRequest("", 1);
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "TicketCode");
    }

    [Fact]
    public void TicketCode_TooLong_ShouldFail()
    {
        var request = new CheckInRequest(new string('a', 101), 1);
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "TicketCode");
    }

    [Fact]
    public void ConcertId_Zero_ShouldFail()
    {
        var request = new CheckInRequest("TKT-001", 0);
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "ConcertId");
    }

    [Fact]
    public void ValidInput_ShouldPass()
    {
        var request = new CheckInRequest("TKT-001", 1);
        var result = _validator.Validate(request);
        result.IsValid.Should().BeTrue();
    }
}

public class ApplyPromotionValidatorTests
{
    private readonly ApplyPromotionValidator _validator = new();

    [Fact]
    public void DiscountCode_Empty_ShouldFail()
    {
        var request = new ApplyPromotionRequest("");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "DiscountCode");
    }

    [Fact]
    public void DiscountCode_TooLong_ShouldFail()
    {
        var request = new ApplyPromotionRequest(new string('a', 51));
        var result = _validator.Validate(request);
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "DiscountCode");
    }

    [Fact]
    public void ValidInput_ShouldPass()
    {
        var request = new ApplyPromotionRequest("SUMMER2026");
        var result = _validator.Validate(request);
        result.IsValid.Should().BeTrue();
    }
}

/// <summary>
/// Hồi quy cho một lỗi CHẶN HẲN quy trình hoàn tiền.
///
/// RefundRequest từng có trường `decimal RefundAmount` và validator bắt buộc nó > 0,
/// trong khi cả hai endpoint (`POST /bookings/{id}/refund` và `POST /bookings/{id}/cancel`)
/// chỉ đọc `Reason`, còn `sp_ProcessRefund` KHÔNG hề có tham số số tiền — nó tự tính
/// `@PaymentAmount * Concert.RefundPercentage / 100` (BR32a).
///
/// Hậu quả: mọi request đúng theo tài liệu đều nhận HTTP 400
/// `{"errors":{"RefundAmount":["Số tiền hoàn phải lớn hơn 0."]}}`, tức là không ai
/// hủy vé và hoàn tiền được — cả một quy trình nghiệp vụ không gọi được.
///
/// Các test dưới đây khóa hợp đồng lại: thân yêu cầu chỉ gồm lý do, và lý do là tùy chọn.
/// </summary>
public class RefundRequestValidatorTests
{
    private readonly RefundRequestValidator _validator = new();

    [Fact]
    public void ReasonOnly_ShouldPass()
    {
        var result = _validator.Validate(new RefundRequest("Khách đổi lịch"));
        result.IsValid.Should().BeTrue(
            "số tiền hoàn do sp_ProcessRefund tự tính, caller không được chỉ định");
    }

    [Fact]
    public void NullReason_ShouldPass()
    {
        // Hủy vé không bắt buộc nêu lý do; @RefundReason của SP nhận NULL.
        var result = _validator.Validate(new RefundRequest(null));
        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Reason_TooLong_ShouldFail()
    {
        // Khớp NVARCHAR(500) của tham số @RefundReason.
        var result = _validator.Validate(new RefundRequest(new string('x', 501)));
        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Reason");
    }
}

public class ZoneValidatorTests
{
    // Zone không còn mang hình học (ZoneType/ZoneLevel/ZoneX.../ZoneCapacity) từ khi
    // trang "Sơ đồ địa điểm" (VenueMap.jsx) bị xoá — hình học giờ chỉ còn ở
    // TemplateSection (StagePass), Zone chỉ còn là container định danh. Test cũ ở
    // đây kiểm tra các trường đã không còn tồn tại trong CreateZoneRequest/
    // UpdateZoneRequest; thay bằng test khớp đúng validator hiện có.
    [Fact]
    public void CreateZone_ValidCode_ShouldPass()
    {
        var result = new CreateZoneValidator().Validate(new CreateZoneRequest("VIP", "VIP"));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void CreateZone_EmptyOrTooLongCode_ShouldFailBeforeDatabase()
    {
        var empty = new CreateZoneValidator().Validate(new CreateZoneRequest("", "Standing"));
        empty.IsValid.Should().BeFalse();
        empty.Errors.Should().Contain(e => e.PropertyName == "ZoneCode");

        var tooLong = new CreateZoneValidator().Validate(new CreateZoneRequest(new string('x', 65), "Standing"));
        tooLong.IsValid.Should().BeFalse();
        tooLong.Errors.Should().Contain(e => e.PropertyName == "ZoneCode");
    }

    // Trước bản sửa này UpdateZoneValidator RỖNG, và test cũ ở đây khẳng định nó
    // "luôn cho qua". Khẳng định đó không còn đúng — và nó cũng che mất một lỗi:
    // cột Zone.ZoneName là nvarchar(255), ZoneDescription là nvarchar(500),
    // repository gửi size: 255 / 500, còn sp_UpdateZone KHÔNG có LEN() nào. Nên
    // tên/mô tả dài bị lưu cụt im lặng (cùng cơ chế đã đo được ở SeatLabel).
    [Theory]
    [InlineData(255, false)]
    [InlineData(256, true)]
    public void UpdateZone_Name_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new UpdateZoneValidator()
            .Validate(new UpdateZoneRequest(ZoneName: new string('a', length)));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "ZoneName");
    }

    [Theory]
    [InlineData(500, false)]
    [InlineData(501, true)]
    public void UpdateZone_Description_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new UpdateZoneValidator()
            .Validate(new UpdateZoneRequest(ZoneDescription: new string('a', length)));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "ZoneDescription");
    }

    [Fact]
    public void UpdateZone_AllNull_MeansKeepCurrent_ShouldPass()
    {
        // NULL = giữ nguyên (COALESCE trong sp_UpdateZone), không được báo lỗi.
        var result = new UpdateZoneValidator().Validate(new UpdateZoneRequest());

        result.IsValid.Should().BeTrue();
    }

    [Theory]
    [InlineData(255, false)]
    [InlineData(256, true)]
    public void CreateZone_Name_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new CreateZoneValidator()
            .Validate(new CreateZoneRequest("VIP", new string('a', length)));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "ZoneName");
    }

    [Fact]
    public void CreateZone_NullName_ShouldPass()
    {
        var result = new CreateZoneValidator().Validate(new CreateZoneRequest("VIP", null));

        result.IsValid.Should().BeTrue();
    }
}

public class ArtistValidatorTests
{
    // Vì sao cần lớp kiểm này: repository gửi tham số với `size` khớp cột (255/500), và
    // ADO.NET cắt chuỗi vượt `size` mà KHÔNG báo lỗi. Thiếu MaximumLength ở tầng API
    // nghĩa là tên/mô tả quá dài bị lưu cụt im lặng thay vì trả 400.
    [Fact]
    public void CreateArtist_ValidNameWithoutDescription_ShouldPass()
    {
        var result = new CreateArtistValidator().Validate(new CreateArtistRequest("Sơn Tùng M-TP"));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void CreateArtist_EmptyName_ShouldFailBeforeDatabase()
    {
        var result = new CreateArtistValidator().Validate(new CreateArtistRequest("   "));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "ArtistName");
    }

    [Fact]
    public void CreateArtist_NameTooLong_ShouldFailBeforeSilentTruncation()
    {
        var tooLong = new CreateArtistValidator().Validate(new CreateArtistRequest(new string('a', 256)));

        tooLong.IsValid.Should().BeFalse();
        tooLong.Errors.Should().Contain(e => e.PropertyName == "ArtistName");
    }

    [Fact]
    public void CreateArtist_DescriptionTooLong_ShouldFailBeforeSilentTruncation()
    {
        var tooLong = new CreateArtistValidator()
            .Validate(new CreateArtistRequest("Nghệ sĩ hợp lệ", new string('a', 501)));

        tooLong.IsValid.Should().BeFalse();
        tooLong.Errors.Should().Contain(e => e.PropertyName == "ArtistDescription");
    }

    [Fact]
    public void UpdateArtist_AllNull_MeansKeepCurrent_ShouldPass()
    {
        // NULL = giữ nguyên (COALESCE trong sp_UpdateArtist), nên không được báo lỗi.
        var result = new UpdateArtistValidator().Validate(new UpdateArtistRequest());

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void UpdateArtist_FieldTooLong_ShouldFail()
    {
        var result = new UpdateArtistValidator()
            .Validate(new UpdateArtistRequest(ArtistDescription: new string('a', 501)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "ArtistDescription");
    }
}

public class VenueValidatorTests
{
    // Cùng lý do như ArtistValidatorTests: repository gửi tham số với `size` khớp cột
    // (VenueName 255, Address 500) và ADO.NET cắt chuỗi vượt `size` mà KHÔNG báo lỗi.
    // Trước đây CreateVenueValidator chỉ kiểm mỗi VenueName, còn UpdateVenueRequest
    // KHÔNG có validator nào — đường cập nhật địa điểm hoàn toàn không được kiểm.
    [Fact]
    public void CreateVenue_ValidNameWithoutAddress_ShouldPass()
    {
        var result = new CreateVenueValidator().Validate(new CreateVenueRequest("Nhà hát Hoà Bình", null));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void CreateVenue_EmptyName_ShouldFailBeforeDatabase()
    {
        var result = new CreateVenueValidator().Validate(new CreateVenueRequest("   ", null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "VenueName");
    }

    [Fact]
    public void CreateVenue_NameTooLong_ShouldFailBeforeSilentTruncation()
    {
        var result = new CreateVenueValidator()
            .Validate(new CreateVenueRequest(new string('a', 256), null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "VenueName");
    }

    [Fact]
    public void CreateVenue_AddressTooLong_ShouldFailBeforeSilentTruncation()
    {
        var result = new CreateVenueValidator()
            .Validate(new CreateVenueRequest("Địa điểm hợp lệ", new string('a', 501)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Address");
    }

    [Fact]
    public void UpdateVenue_AllNull_MeansKeepCurrent_ShouldPass()
    {
        // NULL = giữ nguyên (COALESCE trong sp_UpdateVenue), nên không được báo lỗi.
        var result = new UpdateVenueValidator().Validate(new UpdateVenueRequest());

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void UpdateVenue_NameTooLong_ShouldFail()
    {
        var result = new UpdateVenueValidator()
            .Validate(new UpdateVenueRequest(VenueName: new string('a', 256)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "VenueName");
    }

    [Fact]
    public void UpdateVenue_AddressTooLong_ShouldFail()
    {
        var result = new UpdateVenueValidator()
            .Validate(new UpdateVenueRequest(Address: new string('a', 501)));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Address");
    }
}

public class StagePassValidatorTests
{
    // Cùng lớp lỗi như Artist/Venue, nhưng KHÁC cơ chế — đo bằng integration test thật:
    // cột TemplateFloor.FloorKey là varchar(64) và repository khai `size: 64` (khớp nhau),
    // mà `size` cũng chính là độ dài ADO.NET CẮT giá trị trước khi gửi. Gửi FloorKey 100
    // ký tự → DB nhận đúng 64 ký tự, KHÔNG có lỗi nào. Sáu SP StagePass đều không kiểm
    // độ dài, nên nếu API không kiểm thì người dùng mất chữ mà không được báo.
    //
    // Con số ở đây là ĐỘ RỘNG CỘT THẬT (sys.columns), không phải ước lượng.
    [Theory]
    [InlineData(255, false)]
    [InlineData(256, true)]
    public void CreateVenueTemplate_TemplateName_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new CreateVenueTemplateValidator()
            .Validate(new CreateVenueTemplateRequest(new string('a', length)));

        result.IsValid.Should().Be(!shouldFail);
    }

    [Fact]
    public void UpdateVenueTemplate_NullName_MeansKeepCurrent_ShouldPass()
    {
        // NULL = giữ nguyên (COALESCE trong sp_UpdateVenueTemplate), không được báo lỗi.
        var result = new UpdateVenueTemplateValidator()
            .Validate(new UpdateVenueTemplateRequest(null, null));

        result.IsValid.Should().BeTrue();
    }

    [Fact]
    public void UpdateVenueTemplate_NameTooLong_ShouldFail()
    {
        var result = new UpdateVenueTemplateValidator()
            .Validate(new UpdateVenueTemplateRequest(new string('a', 256), null));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "TemplateName");
    }

    [Theory]
    [InlineData(64, false)]
    [InlineData(65, true)]
    public void ConfigureTemplateFloor_FloorKey_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new ConfigureTemplateFloorValidator()
            .Validate(new ConfigureTemplateFloorRequest(null, new string('a', length), null, 1, 100, 100));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "FloorKey");
    }

    [Fact]
    public void ConfigureTemplateFloor_FloorNameTooLong_ShouldFail()
    {
        var result = new ConfigureTemplateFloorValidator()
            .Validate(new ConfigureTemplateFloorRequest(null, "ground", new string('a', 256), 1, 100, 100));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "FloorName");
    }

    [Theory]
    [InlineData(32, false)]
    [InlineData(33, true)]
    public void ConfigureTemplateObject_ObjectType_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new ConfigureTemplateObjectValidator()
            .Validate(new ConfigureTemplateObjectRequest(null, new string('a', length), null, "{}"));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "ObjectType");
    }

    [Fact]
    public void ConfigureTemplateObject_LabelTooLong_ShouldFail()
    {
        var result = new ConfigureTemplateObjectValidator()
            .Validate(new ConfigureTemplateObjectRequest(null, "Stage", new string('a', 256), "{}"));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "Label");
    }

    [Theory]
    [InlineData(64, false)]
    [InlineData(65, true)]
    public void ConfigureTemplateSection_SectionKey_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new ConfigureTemplateSectionValidator()
            .Validate(new ConfigureTemplateSectionRequest(null, 1, new string('a', length), null, "{}"));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "SectionKey");
    }

    [Fact]
    public void ConfigureTemplateSection_SectionNameTooLong_ShouldFail()
    {
        var result = new ConfigureTemplateSectionValidator()
            .Validate(new ConfigureTemplateSectionRequest(null, 1, "VIP", new string('a', 256), "{}"));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName == "SectionName");
    }

    [Theory]
    [InlineData(64, false)]
    [InlineData(65, true)]
    public void ConfigureTemplateSeat_SeatKey_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new ConfigureTemplateSeatValidator()
            .Validate(new ConfigureTemplateSeatRequest(null, 1, new string('a', length), null, null, null));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "SeatKey");
    }

    [Theory]
    [InlineData(16, false)]
    [InlineData(17, true)]
    public void ConfigureTemplateSeat_RowLabel_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new ConfigureTemplateSeatValidator()
            .Validate(new ConfigureTemplateSeatRequest(null, 1, "A-1", new string('a', length), 1, null));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "RowLabel");
    }
}

// ── Ghế ──────────────────────────────────────────────────────────────────────
// Cùng lớp lỗi, nhưng cơ chế đã ĐO ĐƯỢC bằng integration test trên database thật
// (không phải suy luận từ việc đọc code):
//     tạo ghế (POST) với SeatLabel 300 ký tự -> DB lưu đúng 255 ký tự, không lỗi
//     sửa ghế (PUT) với SeatLabel 400 ký tự -> DB lưu đúng 255 ký tự, không lỗi
// 255 và 16 là bề rộng cột thật đọc từ sys.columns (SeatLabel nvarchar 510 byte
// = 255 ký tự; SeatRowLabel nvarchar 32 byte = 16 ký tự). sp_CreateSeat và
// sp_UpdateSeat đều KHÔNG có LEN(); và trước bản sửa này đường PUT còn không có
// validator nào cả — nên gọi API trực tiếp là mất chữ im lặng.
public class SeatValidatorTests
{
    [Theory]
    [InlineData(255, false)]
    [InlineData(256, true)]
    public void CreateSeat_Label_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new CreateSeatValidator()
            .Validate(new CreateSeatRequest("A-1", new string('a', length), "A", 1));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "SeatLabel");
    }

    [Fact]
    public void CreateSeat_NullLabel_ShouldPass()
    {
        var result = new CreateSeatValidator().Validate(new CreateSeatRequest("A-1", null, "A", 1));

        result.IsValid.Should().BeTrue();
    }

    // Đường hàng loạt áp CreateSeatValidator cho TỪNG ghế, nên hai đường (đơn lẻ và
    // hàng loạt) chặn ở cùng một ngưỡng — trước đây chỉ hàng loạt được chặn, vì
    // sp_CreateSeatsBatch có LEN() còn sp_CreateSeat thì không.
    [Fact]
    public void CreateSeatsBatch_AppliesSameLabelLimitPerSeat()
    {
        var result = new CreateSeatsBatchValidator().Validate(new CreateSeatsBatchRequest(
            [new CreateSeatRequest("A-1", new string('a', 256), "A", 1)]));

        result.IsValid.Should().BeFalse();
        result.Errors.Should().Contain(e => e.PropertyName.EndsWith("SeatLabel"));
    }

    [Theory]
    [InlineData(255, false)]
    [InlineData(256, true)]
    public void UpdateSeat_Label_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new UpdateSeatValidator()
            .Validate(new UpdateSeatRequest(SeatLabel: new string('a', length)));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "SeatLabel");
    }

    [Theory]
    [InlineData(16, false)]
    [InlineData(17, true)]
    public void UpdateSeat_RowLabel_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new UpdateSeatValidator()
            .Validate(new UpdateSeatRequest(SeatRowLabel: new string('a', length)));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "SeatRowLabel");
    }

    [Fact]
    public void UpdateSeat_AllNull_MeansKeepCurrent_ShouldPass()
    {
        // sp_UpdateSeat dùng COALESCE: NULL = giữ nguyên, không được báo lỗi.
        var result = new UpdateSeatValidator().Validate(new UpdateSeatRequest());

        result.IsValid.Should().BeTrue();
    }
}

// ── Concert / hạng vé / khuyến mãi: cùng lớp lỗi, cùng cách sửa ──────────────
// Bề rộng cột thật (sys.columns): Concert.CancellationPolicy 500,
// Concert.RefundPolicy 500, TicketCategory.CategoryDescription 500,
// Promotion.PromotionDescription 500. Đã quét toàn bộ thư mục StoredProcedures:
// KHÔNG SP nào trên bốn đường này có LEN() — chỉ sp_CreateSeatsBatch có, và chỉ
// vì đường đó gửi giá trị bên trong JSON NVARCHAR(MAX) nên không bị `size` cắt.
public class CatalogTextLengthValidatorTests
{
    private static CreateConcertRequest Concert(string? cancellationPolicy = null, string? refundPolicy = null) =>
        new([1], 1, "Show", DateTime.UtcNow, DateTime.UtcNow.AddHours(2),
            CancellationPolicy: cancellationPolicy, RefundPolicy: refundPolicy);

    [Theory]
    [InlineData(500, false)]
    [InlineData(501, true)]
    public void CreateConcert_Policies_RespectColumnWidth(int length, bool shouldFail)
    {
        var longText = new string('a', length);

        new CreateConcertValidator().Validate(Concert(cancellationPolicy: longText))
            .IsValid.Should().Be(!shouldFail);
        new CreateConcertValidator().Validate(Concert(refundPolicy: longText))
            .IsValid.Should().Be(!shouldFail);
    }

    [Theory]
    [InlineData(500, false)]
    [InlineData(501, true)]
    public void UpdateConcert_Policies_RespectColumnWidth(int length, bool shouldFail)
    {
        var longText = new string('a', length);

        var cancellation = new UpdateConcertValidator()
            .Validate(new UpdateConcertRequest(CancellationPolicy: longText));
        cancellation.IsValid.Should().Be(!shouldFail);
        if (shouldFail) cancellation.Errors.Should().Contain(e => e.PropertyName == "CancellationPolicy");

        var refund = new UpdateConcertValidator()
            .Validate(new UpdateConcertRequest(RefundPolicy: longText));
        refund.IsValid.Should().Be(!shouldFail);
        if (shouldFail) refund.Errors.Should().Contain(e => e.PropertyName == "RefundPolicy");
    }

    [Theory]
    [InlineData(500, false)]
    [InlineData(501, true)]
    public void ConfigureTicketCategory_Description_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new ConfigureTicketCategoryValidator()
            .Validate(new ConfigureTicketCategoryRequest("VIP", new string('a', length), 100000m));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "CategoryDescription");
    }

    [Theory]
    [InlineData(500, false)]
    [InlineData(501, true)]
    public void CreatePromotion_Description_RespectsColumnWidth(int length, bool shouldFail)
    {
        var result = new CreatePromotionValidator().Validate(new CreatePromotionRequest(
            "KM", new string('a', length), "Percentage", 10m,
            DateTime.UtcNow, DateTime.UtcNow.AddDays(1)));

        result.IsValid.Should().Be(!shouldFail);
        if (shouldFail) result.Errors.Should().Contain(e => e.PropertyName == "PromotionDescription");
    }
}
