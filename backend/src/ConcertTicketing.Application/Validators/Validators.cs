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
    public RefundRequestValidator() =>
        // Chỉ ràng buộc độ dài, khớp NVARCHAR(500) của tham số @RefundReason.
        // KHÔNG kiểm tra số tiền: số tiền hoàn do sp_ProcessRefund tự tính theo
        // Concert.RefundPercentage, caller không được phép chỉ định (BR32a).
        RuleFor(x => x.Reason)
            .MaximumLength(500).WithMessage("Lý do hủy không được dài quá 500 ký tự.");
}

public class CreateConcertValidator : AbstractValidator<CreateConcertRequest>
{
    public CreateConcertValidator()
    {
        RuleFor(x => x.ArtistIds).NotNull().NotEmpty();
        RuleForEach(x => x.ArtistIds).GreaterThan(0);
        RuleFor(x => x.VenueId).GreaterThan(0);
        RuleFor(x => x.ConcertName).NotEmpty().MaximumLength(255);
        RuleFor(x => x.StartDatetime).NotEmpty();
        RuleFor(x => x.EndDatetime).GreaterThan(x => x.StartDatetime)
            .WithMessage("EndDatetime phải sau StartDatetime.");
        RuleFor(x => x.PurchaseLimit).GreaterThan(0);
        // Không nhận ConcertStatus: Concert luôn được tạo ở trạng thái Draft,
        // mọi chuyển trạng thái phải qua sp_UpdateConcertStatus (BR49).
        RuleFor(x => x.CancellationDeadlineHours).GreaterThan(0)
            .When(x => x.CancellationDeadlineHours.HasValue)
            .WithMessage("CancellationDeadlineHours phải lớn hơn 0.");
        RuleFor(x => x.RefundPercentage).InclusiveBetween(0, 100)
            .When(x => x.RefundPercentage.HasValue)
            .WithMessage("RefundPercentage phải nằm trong khoảng 0-100.");
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
        RuleFor(x => x.ArtistIds)
            .NotEmpty()
            .Must(ids => ids is null || ids.Distinct().Count() == ids.Count)
            .When(x => x.ArtistIds is not null)
            .WithMessage("ArtistIds phải không rỗng và không được trùng.");
        RuleForEach(x => x.ArtistIds!).GreaterThan(0)
            .When(x => x.ArtistIds is not null);
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
    public CreateZoneValidator()
    {
        RuleFor(x => x.ZoneCode).NotEmpty().MaximumLength(64);
        RuleFor(x => x.ZoneType)
            .Must(type => type is null or "Seated")
            .WithMessage("ZoneType hiện chỉ hỗ trợ 'Seated'.");
        RuleFor(x => x.ZoneLevel).GreaterThan(0).When(x => x.ZoneLevel is not null);
        RuleFor(x => x.ZoneCapacity).Null()
            .WithMessage("Sức chứa khu được tính từ số ghế, không nhập trực tiếp.");
    }
}

public class UpdateZoneValidator : AbstractValidator<UpdateZoneRequest>
{
    public UpdateZoneValidator()
    {
        RuleFor(x => x.ZoneType)
            .Must(type => type is null or "Seated")
            .WithMessage("ZoneType hiện chỉ hỗ trợ 'Seated'.");
        RuleFor(x => x.ZoneLevel).GreaterThan(0).When(x => x.ZoneLevel is not null);
        RuleFor(x => x.ZoneCapacity).Null()
            .WithMessage("Sức chứa khu được tính từ số ghế, không nhập trực tiếp.");
    }
}

public class CreateSeatValidator : AbstractValidator<CreateSeatRequest>
{
    public CreateSeatValidator()
    {
        RuleFor(x => x.SeatCode).NotEmpty().MaximumLength(64);
        RuleFor(x => x.SeatRowLabel).NotEmpty().MaximumLength(16);
        RuleFor(x => x.SeatColumnNumber).NotNull().GreaterThan(0);
    }
}

public class CreateSeatsBatchValidator : AbstractValidator<CreateSeatsBatchRequest>
{
    public CreateSeatsBatchValidator()
    {
        RuleFor(x => x.Seats).NotNull().NotEmpty().Must(seats => seats.Count <= 3600)
            .WithMessage("Một lần chỉ tạo tối đa 3.600 ghế.");
        RuleForEach(x => x.Seats).SetValidator(new CreateSeatValidator());
    }
}

public class ConfigureTicketCategoryValidator : AbstractValidator<ConfigureTicketCategoryRequest>
{
    public ConfigureTicketCategoryValidator()
    {
        RuleFor(x => x.CategoryName).NotEmpty().MaximumLength(255);
        // BasePrice là nguồn sự thật của giá vé (BR10a), cascade xuống EventSeat.SalePrice.
        RuleFor(x => x.BasePrice).GreaterThanOrEqualTo(0);
    }
}

public class AddEventSeatsValidator : AbstractValidator<AddEventSeatsRequest>
{
    public AddEventSeatsValidator()
    {
        RuleFor(x => x.TicketCategoryId).GreaterThan(0);
        RuleFor(x => x.SeatIds).NotEmpty()
            .Must(ids => ids.Distinct().Count() == ids.Count)
            .WithMessage("Danh sách ghế không được trùng.");
        RuleForEach(x => x.SeatIds).GreaterThan(0);
    }
}

public class CreatePromotionValidator : AbstractValidator<CreatePromotionRequest>
{
    /// <summary>
    /// Tập giá trị được chấp nhận, khớp đúng phép chuẩn hoá trong sp_CreatePromotion:
    /// hai giá trị chính thức, cộng các dạng viết tắt cũ được SP tự quy đổi.
    /// So sánh không phân biệt hoa thường vì SP cũng dùng UPPER() khi quy đổi.
    /// </summary>
    private static readonly HashSet<string> AcceptedDiscountTypes =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "Percentage", "Fixed Amount",   // chính thức (§12.16.1)
            "PERCENT", "FIXED",             // dạng cũ, sp_CreatePromotion tự quy đổi
        };

    public CreatePromotionValidator()
    {
        RuleFor(x => x.PromotionName).NotEmpty().MaximumLength(255);
        // Miền giá trị CHÍNH THỨC là 'Percentage' và 'Fixed Amount' — đúng theo
        // CHK_Promotion_DiscountType của bảng Promotion và §12.16.1.
        //
        // Trước đây validator chỉ chấp nhận 'PERCENTAGE'/'FIXED', tức là nó TỪ CHỐI
        // đúng hai giá trị mà database cho phép, và chỉ nhận dạng viết tắt cũ mà
        // sp_CreatePromotion phải tự chuẩn hoá lại. Hậu quả: client gửi giá trị đúng
        // theo đặc tả thì nhận HTTP 400. Nay validator chấp nhận đúng tập mà
        // sp_CreatePromotion chấp nhận, để hai tầng nói cùng một ngôn ngữ.
        RuleFor(x => x.DiscountType)
            .Must(t => t is not null && AcceptedDiscountTypes.Contains(t))
            .WithMessage("DiscountType phải là 'Percentage' hoặc 'Fixed Amount'.");
        RuleFor(x => x.DiscountValue).GreaterThan(0);
        RuleFor(x => x.EndDatetime).GreaterThan(x => x.StartDatetime)
            .WithMessage("EndDatetime phải sau StartDatetime.");
        RuleFor(x => x.UsageLimit).GreaterThan(0).When(x => x.UsageLimit is not null);
    }
}

public class UpdateRefundStatusValidator : AbstractValidator<UpdateRefundStatusRequest>
{
    public UpdateRefundStatusValidator()
    {
        RuleFor(x => x.Status)
            .Must(x => x is "Failed" or "Cancelled")
            .WithMessage("Status phải là Failed hoặc Cancelled. Muốn xác nhận đã hoàn tiền xong thì dùng refunds/{id}/confirm.");
        // Bắt buộc có lý do: đây là thao tác đóng một yêu cầu hoàn tiền mà khách
        // không nhận được tiền, nên phải để lại dấu vết vì sao.
        RuleFor(x => x.Reason).NotEmpty().MaximumLength(500);
    }
}

public class UpdateRoleStatusValidator : AbstractValidator<UpdateRoleStatusRequest>
{
    public UpdateRoleStatusValidator()
    {
        RuleFor(x => x.RoleName).NotEmpty().MaximumLength(255);
        RuleFor(x => x.Status)
            .Must(x => x is "Active" or "Inactive")
            .WithMessage("Status phải là Active hoặc Inactive.");
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
