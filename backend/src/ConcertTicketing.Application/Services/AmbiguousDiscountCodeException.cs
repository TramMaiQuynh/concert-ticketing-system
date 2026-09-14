namespace ConcertTicketing.Application.Services;

/// <summary>
/// Một chuỗi mã giảm giá khớp với NHIỀU Promotion Active của cùng một Concert, nên
/// không xác định được khách muốn dùng ưu đãi nào.
///
/// Vì sao là một loại exception riêng chứ không phải ArgumentException: lỗi này KHÔNG
/// phải do người gọi nhập sai - mã họ gõ là mã có thật và đang hiệu lực. Vấn đề nằm ở
/// dữ liệu cấu hình của sự kiện, nên nó phải ra HTTP 409 (Conflict) kèm lời giải thích
/// đúng, thay vì 400 đổ lỗi cho khách hay 500 không nói gì.
///
/// Ràng buộc chặn từ gốc nằm ở database (sp_CreateDiscountCode 58604,
/// sp_UpdateDiscountCodeStatus 59614, sp_UpdatePromotionStatus 59605); lớp này chỉ
/// còn phải xử lý dữ liệu đã tồn tại từ trước khi các luật đó có hiệu lực.
/// </summary>
public class AmbiguousDiscountCodeException(string message) : InvalidOperationException(message);
