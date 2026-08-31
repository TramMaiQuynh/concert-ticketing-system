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

        RuleFor(x => x.DisplayName)
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

public class RefundRequestValidator : AbstractValidator<RefundRequest>
{
    public RefundRequestValidator()
    {
        RuleFor(x => x.RefundAmount)
            .GreaterThan(0).WithMessage("Số tiền hoàn phải lớn hơn 0.");

        RuleFor(x => x.Reason)
            .MaximumLength(500);
    }
}

public class CreateConcertValidator : AbstractValidator<CreateConcertRequest>
{
    public CreateConcertValidator()
    {
        RuleFor(x => x.ArtistId).GreaterThan(0);
        RuleFor(x => x.VenueId).GreaterThan(0);
        RuleFor(x => x.ConcertName).NotEmpty().MaximumLength(255);
        RuleFor(x => x.StartDatetime).NotEmpty();
        RuleFor(x => x.EndDatetime).GreaterThan(x => x.StartDatetime)
            .WithMessage("EndDatetime phải sau StartDatetime.");
        RuleFor(x => x.PurchaseLimit).GreaterThan(0);
        RuleFor(x => x.ConcertStatus)
            .Must(s => s is "Draft" or "Published" or "OnSale" or "SaleClosed" or "Completed" or "Cancelled")
            .When(x => x.ConcertStatus is not null)
            .WithMessage("ConcertStatus không hợp lệ.");
    }
}

public class UpdateConcertValidator : AbstractValidator<UpdateConcertRequest>
{
    public UpdateConcertValidator()
    {
        RuleFor(x => x.ConcertName).MaximumLength(255).When(x => x.ConcertName is not null);
        RuleFor(x => x.EndDatetime).GreaterThan(x => x.StartDatetime)
            .When(x => x.EndDatetime is not null && x.StartDatetime is not null)
            .WithMessage("EndDatetime phải sau StartDatetime.");
        RuleFor(x => x.PurchaseLimit)
            .GreaterThan(0).When(x => x.PurchaseLimit is not null);
    }
}

public class UpdateConcertStatusValidator : AbstractValidator<UpdateConcertStatusRequest>
{
    public UpdateConcertStatusValidator()
    {
        RuleFor(x => x.Status)
            .NotEmpty()
            .Must(s => s is "Draft" or "Published" or "OnSale" or "SaleClosed" or "Completed" or "Cancelled")
            .WithMessage("ConcertStatus không hợp lệ.");
    }
}

public class CreateVenueValidator : AbstractValidator<CreateVenueRequest>
{
    public CreateVenueValidator() =>
        RuleFor(x => x.VenueName).NotEmpty().MaximumLength(255);
}

public class CreateZoneValidator : AbstractValidator<CreateZoneRequest>
{
    public CreateZoneValidator() =>
        RuleFor(x => x.ZoneCode).NotEmpty().MaximumLength(64);
}

public class CreateSeatValidator : AbstractValidator<CreateSeatRequest>
{
    public CreateSeatValidator() =>
        RuleFor(x => x.SeatCode).NotEmpty().MaximumLength(64);
}

public class ConfigureTicketCategoryValidator : AbstractValidator<ConfigureTicketCategoryRequest>
{
    public ConfigureTicketCategoryValidator() =>
        RuleFor(x => x.CategoryName).NotEmpty().MaximumLength(255);
}

public class AddEventSeatsValidator : AbstractValidator<AddEventSeatsRequest>
{
    public AddEventSeatsValidator()
    {
        RuleFor(x => x.TicketCategoryId).GreaterThan(0);
        RuleFor(x => x.SalePrice).GreaterThanOrEqualTo(0);
        RuleFor(x => x.SeatIds).NotEmpty()
            .Must(ids => ids.Distinct().Count() == ids.Count)
            .WithMessage("Danh sách ghế không được trùng.");
        RuleForEach(x => x.SeatIds).GreaterThan(0);
    }
}

public class CreatePromotionValidator : AbstractValidator<CreatePromotionRequest>
{
    public CreatePromotionValidator()
    {
        RuleFor(x => x.PromotionName).NotEmpty().MaximumLength(255);
        RuleFor(x => x.DiscountType)
            .Must(t => t is "PERCENTAGE" or "FIXED")
            .WithMessage("DiscountType phải là PERCENTAGE hoặc FIXED.");
        RuleFor(x => x.DiscountValue).GreaterThan(0);
        RuleFor(x => x.EndDatetime).GreaterThan(x => x.StartDatetime)
            .WithMessage("EndDatetime phải sau StartDatetime.");
        RuleFor(x => x.UsageLimit).GreaterThan(0).When(x => x.UsageLimit is not null);
    }
}

public class AssignRoleValidator : AbstractValidator<AssignRoleRequest>
{
    public AssignRoleValidator()
    {
        RuleFor(x => x.TargetUserId).GreaterThan(0);
        RuleFor(x => x.RoleName).NotEmpty().MaximumLength(255);
        RuleFor(x => x.GrantOrRevoke)
            .Must(x => x is "Grant" or "Revoke")
            .WithMessage("GrantOrRevoke phải là Grant hoặc Revoke.");
    }
}
public class CreateDiscountCodeValidator : AbstractValidator<CreateDiscountCodeRequest>
{
    public CreateDiscountCodeValidator() =>
        RuleFor(x => x.CodeValue).NotEmpty().MaximumLength(64);
}

public class SetEventSeatUnavailableValidator : AbstractValidator<SetEventSeatUnavailableRequest>
{
    public SetEventSeatUnavailableValidator() =>
        RuleFor(x => x.Reason)
            .NotEmpty().MaximumLength(500)
            .When(x => x.Unavailable);
}

public class UpdateUserStatusValidator : AbstractValidator<UpdateUserStatusRequest>
{
    public UpdateUserStatusValidator() =>
        RuleFor(x => x.Status)
            .NotEmpty()
            .Must(s => s is "Active" or "Locked" or "Disabled")
            .WithMessage("UserStatus không hợp lệ.");
}

public class AddCheckinStaffAssignmentValidator : AbstractValidator<AddCheckinStaffAssignmentRequest>
{
    public AddCheckinStaffAssignmentValidator()
    {
        RuleFor(x => x.StaffUserId).GreaterThan(0);
        RuleFor(x => x.ConcertIds)
            .NotEmpty()
            .Must(ids => ids.Distinct().Count() == ids.Count)
            .WithMessage("Danh sách Concert không được trùng.");
        RuleForEach(x => x.ConcertIds).GreaterThan(0);
    }
}
