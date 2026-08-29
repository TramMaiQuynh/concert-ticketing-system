using FluentValidation;
using ConcertTicketing.Application.DTOs;

namespace ConcertTicketing.Application.Validators;

public class CreateBookingValidator : AbstractValidator<CreateBookingRequest>
{
    public CreateBookingValidator()
    {
        RuleFor(x => x.ConcertId)
            .GreaterThan(0).WithMessage("ConcertId phải lớn hơn 0.");

        RuleFor(x => x.SeatIds)
            .NotEmpty().WithMessage("Phải chọn ít nhất 1 ghế.")
            .Must(ids => ids.Count <= 10).WithMessage("Không được chọn quá 10 ghế cùng lúc.")
            .Must(ids => ids.Distinct().Count() == ids.Count)
            .WithMessage("Danh sách ghế không được có ghế trùng lặp.");

        RuleForEach(x => x.SeatIds)
            .GreaterThan(0).WithMessage("SeatId không hợp lệ.");
    }
}

public class LoginValidator : AbstractValidator<LoginRequest>
{
    public LoginValidator()
    {
        RuleFor(x => x.Username)
            .NotEmpty().WithMessage("Username không được để trống.")
            .MaximumLength(100);

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("Password không được để trống.")
            .MinimumLength(6).WithMessage("Password phải có ít nhất 6 ký tự.");
    }
}

public class RegisterValidator : AbstractValidator<RegisterRequest>
{
    public RegisterValidator()
    {
        RuleFor(x => x.Username)
            .NotEmpty()
            .MinimumLength(3).WithMessage("Username phải có ít nhất 3 ký tự.")
            .MaximumLength(50)
            .Matches("^[a-zA-Z0-9_]+$").WithMessage("Username chỉ được chứa chữ, số và dấu gạch dưới.");

        RuleFor(x => x.Email)
            .NotEmpty()
            .EmailAddress().WithMessage("Email không đúng định dạng.");

        RuleFor(x => x.Password)
            .NotEmpty()
            .MinimumLength(8).WithMessage("Password phải có ít nhất 8 ký tự.")
            .Matches("[A-Z]").WithMessage("Password phải có ít nhất 1 chữ hoa.")
            .Matches("[0-9]").WithMessage("Password phải có ít nhất 1 chữ số.");

        RuleFor(x => x.FullName)
            .NotEmpty()
            .MaximumLength(200);
    }
}

public class CheckInValidator : AbstractValidator<CheckInRequest>
{
    public CheckInValidator()
    {
        RuleFor(x => x.TicketCode)
            .NotEmpty().WithMessage("TicketCode không được để trống.")
            .MaximumLength(100);

        RuleFor(x => x.ConcertId)
            .GreaterThan(0).WithMessage("ConcertId không hợp lệ.");
    }
}

public class ApplyPromotionValidator : AbstractValidator<ApplyPromotionRequest>
{
    public ApplyPromotionValidator()
    {
        RuleFor(x => x.DiscountCode)
            .NotEmpty().WithMessage("Mã khuyến mãi không được để trống.")
            .MaximumLength(50);
    }
}
