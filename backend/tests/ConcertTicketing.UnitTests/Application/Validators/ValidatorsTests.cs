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
