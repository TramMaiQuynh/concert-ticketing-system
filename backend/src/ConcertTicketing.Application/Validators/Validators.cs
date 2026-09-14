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
        // Cùng lớp lỗi đã đo ở CreateZoneValidator: cột Concert.CancellationPolicy /
        // RefundPolicy là nvarchar(500), repository gửi size: 500, và sp_CreateConcert
        // không có LEN() — không kiểm ở đây thì chính sách dài bị lưu cụt im lặng.
        RuleFor(x => x.CancellationPolicy).MaximumLength(500).When(x => x.CancellationPolicy is not null);
        RuleFor(x => x.RefundPolicy).MaximumLength(500).When(x => x.RefundPolicy is not null);
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
        // Xem CreateConcertValidator: sp_UpdateConcert cũng không kiểm LEN() trên hai
        // cột này, và repository cũng gửi size: 500 — nên đường sửa cũng mất chữ im lặng.
        RuleFor(x => x.CancellationPolicy).MaximumLength(500).When(x => x.CancellationPolicy is not null);
        RuleFor(x => x.RefundPolicy).MaximumLength(500).When(x => x.RefundPolicy is not null);
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

// Cùng lớp lỗi đã sửa cho Artist: repository gửi tham số với `size` khớp cột (255/500)
// và ADO.NET cắt chuỗi vượt `size` mà không báo lỗi. Không kiểm ở đây thì tên hoặc
// địa chỉ quá dài bị lưu cụt im lặng thay vì trả 400.
public class CreateVenueValidator : AbstractValidator<CreateVenueRequest>
{
    public CreateVenueValidator()
    {
        RuleFor(x => x.VenueName).NotEmpty().MaximumLength(255);
        RuleFor(x => x.Address)
            .MaximumLength(500).When(x => x.Address is not null);
    }
}

// Tham số NULL = "giữ nguyên giá trị hiện tại" (COALESCE trong sp_UpdateVenue), nên chỉ
// kiểm độ dài khi thực sự có giá trị được gửi lên.
//
// Trước đây UpdateVenueRequest KHÔNG có validator nào — đường cập nhật không kiểm gì cả,
// nên tên dài hơn 255 hay địa chỉ dài hơn 500 đi thẳng tới repository rồi bị cắt cụt
// im lặng. Không kiểm lại VenueStatus: CHECK constraint của bảng và 59403 của
// sp_UpdateVenue đã thi hành — cùng cách UpdateZoneValidator để tầng dữ liệu lo việc đó.
public class UpdateVenueValidator : AbstractValidator<UpdateVenueRequest>
{
    public UpdateVenueValidator()
    {
        RuleFor(x => x.VenueName)
            .NotEmpty().MaximumLength(255).When(x => x.VenueName is not null);
        RuleFor(x => x.Address)
            .MaximumLength(500).When(x => x.Address is not null);
    }
}

// Artist là danh mục dùng chung (chỉ Admin, §12.6.1) và trước đây là thực thể danh mục
// DUY NHẤT không có validator — Venue/Zone/Seat đều đã có.
//
// Hệ quả không phải lý thuyết: repository truyền tham số với `size` khớp cột (255/500),
// mà ADO.NET CẮT chuỗi vượt `size` một cách IM LẶNG (đo thực tế: gửi 300 ký tự với
// size=255 thì server nhận đúng 255, không có lỗi nào). Không kiểm ở đây thì tên hoặc
// mô tả dài hơn giới hạn bị lưu cụt và người dùng không biết vì sao.
//
// Không kiểm lại ArtistStatus: CHECK constraint của bảng và 59113 của sp_UpdateArtist
// đã thi hành, giống cách UpdateZoneValidator để tầng dữ liệu lo việc đó.
public class CreateArtistValidator : AbstractValidator<CreateArtistRequest>
{
    public CreateArtistValidator()
    {
        RuleFor(x => x.ArtistName).NotEmpty().MaximumLength(255);
        RuleFor(x => x.ArtistDescription)
            .MaximumLength(500).When(x => x.ArtistDescription is not null);
    }
}

// Tham số NULL = "giữ nguyên giá trị hiện tại" (COALESCE trong sp_UpdateArtist), nên
// chỉ kiểm độ dài khi thực sự có giá trị được gửi lên.
public class UpdateArtistValidator : AbstractValidator<UpdateArtistRequest>
{
    public UpdateArtistValidator()
    {
        RuleFor(x => x.ArtistName)
            .NotEmpty().MaximumLength(255).When(x => x.ArtistName is not null);
        RuleFor(x => x.ArtistDescription)
            .MaximumLength(500).When(x => x.ArtistDescription is not null);
    }
}

public class CreateZoneValidator : AbstractValidator<CreateZoneRequest>
{
    // ── LỚP LỖI ĐO ĐƯỢC: trường văn bản bị chặn bởi bề rộng cột nhưng KHÔNG được
    //    chặn ở tầng API ────────────────────────────────────────────────────────
    // Repository gửi các trường dưới đây bằng tham số có `size` ĐÚNG BẰNG bề rộng
    // cột (SeatLabel size: 255 cho cột nvarchar(255), ZoneName size: 255, ...).
    // `size` vừa là kích thước tham số vừa là độ dài bị CẮT trên đường truyền,
    // nên giá trị quá dài được lưu cụt MÀ KHÔNG sinh lỗi nào. Đo trực tiếp bằng
    // integration test trên database thật:
    //     tạo ghế với SeatLabel 300 ký tự -> lưu đúng 255 ký tự, không exception
    //     sửa ghế với SeatLabel 400 ký tự -> lưu đúng 255 ký tự, không exception
    //
    // Vì sao KHÔNG sửa bằng cách thêm LEN() vào stored procedure: lúc SP chạy thì
    // giá trị đã bị cắt còn 255 ký tự, nên `LEN(@SeatLabel) > 255` KHÔNG BAO GIỜ
    // đúng — đó sẽ là phép kiểm chỉ để trông có vẻ an toàn. (sp_CreateSeatsBatch
    // kiểm được LEN vì đường hàng loạt gửi nhãn trong JSON NVARCHAR(MAX), không
    // đi qua tham số có `size`.) Chốt duy nhất có hiệu lực là tầng API; mỗi con
    // số dưới đây lấy từ sys.columns, không phải ước lượng.
    public CreateZoneValidator()
    {
        RuleFor(x => x.ZoneCode).NotEmpty().MaximumLength(64);
        RuleFor(x => x.ZoneName).MaximumLength(255).When(x => x.ZoneName is not null);
    }
}

public class UpdateZoneValidator : AbstractValidator<UpdateZoneRequest>
{
    // Chỉ kiểm ĐỘ DÀI. ZoneStatus (59413), ZoneLevel (59833), hình học (59832) và
    // hai guard 59415/59416 để nguyên cho sp_UpdateZone quyết định — không lặp lại
    // luật của tầng dữ liệu ở đây.
    public UpdateZoneValidator()
    {
        RuleFor(x => x.ZoneName).MaximumLength(255).When(x => x.ZoneName is not null);
        RuleFor(x => x.ZoneDescription).MaximumLength(500).When(x => x.ZoneDescription is not null);
    }
}

public class CreateSeatValidator : AbstractValidator<CreateSeatRequest>
{
    public CreateSeatValidator()
    {
        RuleFor(x => x.SeatCode).NotEmpty().MaximumLength(64);
        // SeatLabel là trường duy nhất của ghế mà KHÔNG tầng nào kiểm: sp_CreateSeat
        // không có LEN(), DTO không có DataAnnotation, repository gửi size: 255.
        RuleFor(x => x.SeatLabel).MaximumLength(255).When(x => x.SeatLabel is not null);
        RuleFor(x => x.SeatRowLabel).NotEmpty().MaximumLength(16);
        RuleFor(x => x.SeatColumnNumber).NotNull().GreaterThan(0);
    }
}

// Trước bản sửa này KHÔNG có UpdateSeatValidator, nên PUT /admin/seats/{id}
// không được kiểm gì ở tầng API. Chỉ thêm luật ĐỘ DÀI cho đúng hai trường mà
// sp_UpdateSeat bỏ qua; SeatStatus (59423), SeatColumnNumber (59822), ô lưới
// (59824), vị trí bắt buộc (59825) và 59425/59426 vẫn do SP quyết định.
public class UpdateSeatValidator : AbstractValidator<UpdateSeatRequest>
{
    public UpdateSeatValidator()
    {
        RuleFor(x => x.SeatLabel).MaximumLength(255).When(x => x.SeatLabel is not null);
        RuleFor(x => x.SeatRowLabel).MaximumLength(16).When(x => x.SeatRowLabel is not null);
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
        // Xem CreateZoneValidator: TicketCategory.CategoryDescription là nvarchar(500),
        // repository gửi size: 500, sp_ConfigureTicketCategory không kiểm LEN().
        RuleFor(x => x.CategoryDescription).MaximumLength(500).When(x => x.CategoryDescription is not null);
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
        // Xem CreateZoneValidator: Promotion.PromotionDescription là nvarchar(500),
        // repository gửi size: 500, sp_CreatePromotion không kiểm LEN().
        RuleFor(x => x.PromotionDescription).MaximumLength(500).When(x => x.PromotionDescription is not null);
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

// ══ StagePass (Mẫu sơ đồ) — CHỈ kiểm ĐỘ DÀI ═══════════════════════════════════
//
// Vì sao chỉ độ dài: cả 6 SP StagePass (sp_CreateVenueTemplate, sp_UpdateVenueTemplate,
// sp_ConfigureTemplateFloor/Object/Section/Seat) ĐỀU KHÔNG kiểm độ dài — đã quét toàn
// bộ file xác nhận, không file nào có LEN()/DATALENGTH. Ràng buộc thật nằm ở KIỂU CỘT,
// mà tầng ADO lại CẮT theo `size` khai trong repository TRƯỚC khi gửi đi.
//
// Đo bằng integration test thật (không suy luận): gửi FloorKey 100 ký tự vào cột
// varchar(64) thì DB nhận ĐÚNG 64 ký tự và KHÔNG có lỗi nào — người dùng gõ dài bị mất
// chữ mà không được báo. Kiểm ở đây trả 400 trước khi dữ liệu kịp bị cắt.
//
// Các con số 64/255/32/16 lấy ĐÚNG bằng độ rộng cột trong database, đo bằng sys.columns
// (varchar tính theo byte, nvarchar chia hai), không phải con số ước lượng:
//   VenueTemplate.TemplateName  nvarchar(255)
//   TemplateFloor.FloorKey      varchar(64)   FloorName   nvarchar(255)
//   TemplateObject.ObjectType   varchar(32)   Label       nvarchar(255)
//   TemplateSection.SectionKey  varchar(64)   SectionName nvarchar(255)
//   TemplateSeat.SeatKey        varchar(64)   RowLabel    nvarchar(16)
//
// Kiểm luôn cho nhất quán với Artist/Venue: repository khai `size` KHỚP cột ở cả 79 chỗ
// (đã audit toàn bộ backend: không chỗ nào khai size LỚN HƠN tham số SP, nên không có
// nguy cơ lỗi 8152 "String or binary data would be truncated" — mà middleware cũng không
// map 8152, nó sẽ thành HTTP 500).
//
// KHÔNG kiểm lại tính hợp lệ/rỗng/trùng: sp_UpdateVenueTemplate đã kiểm TemplateStatus
// (60007), các SP còn lại đã kiểm rỗng (60044…), trùng (60047/60055/60064…), giới hạn
// hình học — cùng cách UpdateZoneValidator để tầng dữ liệu lo việc của nó.
// GeometryJson là NVARCHAR(MAX) nên không cần giới hạn.
public class CreateVenueTemplateValidator : AbstractValidator<CreateVenueTemplateRequest>
{
    public CreateVenueTemplateValidator() => RuleFor(x => x.TemplateName).MaximumLength(255);
}

// Tham số NULL = "giữ nguyên giá trị hiện tại" (COALESCE trong sp_UpdateVenueTemplate),
// nên chỉ kiểm khi thực sự có giá trị được gửi lên.
public class UpdateVenueTemplateValidator : AbstractValidator<UpdateVenueTemplateRequest>
{
    public UpdateVenueTemplateValidator() =>
        RuleFor(x => x.TemplateName).MaximumLength(255).When(x => x.TemplateName is not null);
}

public class ConfigureTemplateFloorValidator : AbstractValidator<ConfigureTemplateFloorRequest>
{
    public ConfigureTemplateFloorValidator()
    {
        RuleFor(x => x.FloorKey).MaximumLength(64);
        RuleFor(x => x.FloorName).MaximumLength(255).When(x => x.FloorName is not null);
    }
}

public class ConfigureTemplateObjectValidator : AbstractValidator<ConfigureTemplateObjectRequest>
{
    public ConfigureTemplateObjectValidator()
    {
        RuleFor(x => x.ObjectType).MaximumLength(32);
        RuleFor(x => x.Label).MaximumLength(255).When(x => x.Label is not null);
    }
}

public class ConfigureTemplateSectionValidator : AbstractValidator<ConfigureTemplateSectionRequest>
{
    public ConfigureTemplateSectionValidator()
    {
        RuleFor(x => x.SectionKey).MaximumLength(64);
        RuleFor(x => x.SectionName).MaximumLength(255).When(x => x.SectionName is not null);
    }
}

public class ConfigureTemplateSeatValidator : AbstractValidator<ConfigureTemplateSeatRequest>
{
    public ConfigureTemplateSeatValidator()
    {
        RuleFor(x => x.SeatKey).MaximumLength(64);
        RuleFor(x => x.RowLabel).MaximumLength(16).When(x => x.RowLabel is not null);
    }
}
