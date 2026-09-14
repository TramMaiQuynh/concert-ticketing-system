using System.Data;
using System.Security.Claims;
using Dapper;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.API.Controllers;

/// <summary>
/// Bộ công cụ DEMO 5 lỗi tương tranh — CHỈ Admin.
///
/// Đây KHÔNG phải nghiệp vụ, mà là công cụ trình diễn. Nguyên tắc:
///   - Mọi thao tác GHI vẫn đi qua stored procedure thật của hệ thống
///     (sp_AdminUpdateUserStatus, sp_CreateDiscountCode, sp_UpdatePromotionStatus,
///     sp_ConfigureTicketCategory) — không có đường ghi tắt nào.
///   - Các endpoint ở đây chỉ mở những thứ trình duyệt KHÔNG THỂ làm: giữ một
///     giao dịch mở vài giây (để người khác kịp thao tác), đọc ở mức
///     READ UNCOMMITTED, và chạy hai phiên khoá chéo nhau.
///
/// Vì sao cần: mỗi request HTTP là MỘT giao dịch, nên "đọc cùng một dòng hai lần
/// trong một giao dịch" hoặc "giữ giao dịch chưa commit" không thể tạo bằng click.
///
/// Toàn bộ module nằm trong MỘT file này (cộng một trang React
/// DemoConcurrency.jsx) để có thể xoá sạch khi không cần demo nữa.
/// </summary>
[ApiController]
[Route("api/admin/demo")]
[Authorize(Roles = "Admin")]
public sealed class DemoConcurrencyController : ControllerBase
{
    private readonly IDbConnectionFactory _factory;
    private readonly ISeatMapCache _seatMapCache;
    private readonly IConcertRepository _concerts;

    public DemoConcurrencyController(
        IDbConnectionFactory factory,
        ISeatMapCache seatMapCache,
        IConcertRepository concerts)
    {
        _factory      = factory;
        _seatMapCache = seatMapCache;
        _concerts     = concerts;
    }

    private int GetActorUserId()
    {
        var sub = User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirstValue("sub")
               ?? throw new UnauthorizedAccessException("Token không hợp lệ.");
        return int.Parse(sub);
    }

    // ═══════════════════════════════════════════════════════════════════
    // #1 LOST UPDATE — hai admin sửa cùng giá một hạng vé
    // Thao tác ghi KHÔNG có endpoint riêng: trang demo gọi thẳng endpoint thật
    // POST /api/admin/concerts/{id}/categories hai lần. Endpoint này chỉ ĐỌC.
    // ═══════════════════════════════════════════════════════════════════
    [HttpGet("ticket-category-state")]
    public async Task<IActionResult> TicketCategoryState([FromQuery] int ticketCategoryId)
    {
        using var conn = await _factory.OpenAsync();
        var row = await conn.QuerySingleOrDefaultAsync<TicketCategoryStateRow>(@"
            SELECT tc.TicketCategoryID, tc.ConcertID, tc.CategoryName, tc.BasePrice, tc.CategoryStatus,
                   (SELECT COUNT(*) FROM dbo.AuditRecord ar
                     WHERE ar.EntityType = 'TicketCategory'
                       AND ar.EntityID   = CAST(tc.TicketCategoryID AS VARCHAR(64))
                       AND ar.EventType  = 'TICKET_CATEGORY_UPDATED') AS UpdatedAuditRows
            FROM   dbo.TicketCategory tc
            WHERE  tc.TicketCategoryID = @Id;", new { Id = ticketCategoryId });

        return row is null ? NotFound(new { message = "Không tìm thấy hạng vé." }) : Ok(row);
    }

    // ═══════════════════════════════════════════════════════════════════
    // #2 DIRTY READ — nhật ký kiểm toán
    // ═══════════════════════════════════════════════════════════════════

    /// <summary>
    /// Giữ MỘT thay đổi trạng thái tài khoản ở trạng thái CHƯA COMMIT trong
    /// <paramref name="seconds"/> giây rồi ROLLBACK. Trình duyệt gọi kiểu
    /// "bắn rồi quên" (không chờ) để người dùng kịp đọc nhật ký ở tab khác.
    /// </summary>
    [HttpPost("hold-user-status")]
    public async Task<IActionResult> HoldUserStatus([FromBody] HoldUserStatusRequest request)
    {
        var actor   = GetActorUserId();
        var seconds = Math.Clamp(request.Seconds, 1, 60);

        using var conn = await _factory.OpenAsync();
        await conn.ExecuteAsync($@"
BEGIN TRANSACTION;
EXEC dbo.sp_AdminUpdateUserStatus @ActorUserID = @Actor, @TargetUserID = @Target, @NewStatus = @Status;
WAITFOR DELAY '00:00:{seconds:D2}';
ROLLBACK TRANSACTION;",
            new { Actor = actor, Target = request.TargetUserId, Status = request.NewStatus });

        return Ok(new
        {
            held          = true,
            seconds,
            rolledBack    = true,
            note          = "Giao dịch đã ROLLBACK: thay đổi này CHƯA BAO GIỜ tồn tại trong hệ thống."
        });
    }

    /// <summary>
    /// Đọc nhật ký kiểm toán ở mức cô lập chỉ định. Hệ thống luôn chạy
    /// READ COMMITTED (0 chỗ đặt NOLOCK); tham số này chỉ để CHỨNG MINH điều gì
    /// sẽ xảy ra nếu hạ mức xuống READ UNCOMMITTED.
    /// </summary>
    [HttpGet("audit-read")]
    public async Task<IActionResult> AuditRead([FromQuery] bool uncommitted = false, [FromQuery] int limit = 20)
    {
        var level = uncommitted ? "READ UNCOMMITTED" : "READ COMMITTED";
        using var conn = await _factory.OpenAsync();

        // Đặt mức cô lập cho PHIÊN đọc (không sửa đối tượng database nào).
        await conn.ExecuteAsync($"SET TRANSACTION ISOLATION LEVEL {level};");

        var rows = await conn.QueryAsync<DemoAuditRow>(@"
            SELECT TOP (@Limit)
                   AuditID, EventType, EntityType, EntityID, ActorUserID, Action,
                   CONVERT(varchar(23), EventTimestamp, 121) AS EventTimestamp
            FROM   dbo.VW_AuditTrail
            ORDER BY AuditID DESC;", new { Limit = Math.Clamp(limit, 1, 200) });

        return Ok(new { isolationLevel = level, rowCount = rows.Count(), rows });
    }

    // ═══════════════════════════════════════════════════════════════════
    // #3a NON-REPEATABLE READ — cùng một dòng, đọc hai lần trong MỘT giao dịch
    // ═══════════════════════════════════════════════════════════════════

    /// <summary>
    /// Đọc trạng thái một chương trình khuyến mãi HAI lần trong cùng một giao dịch,
    /// cách nhau <paramref name="HoldSeconds"/> giây. Trong khoảng đó người dùng bấm
    /// nút đổi trạng thái (endpoint thật PUT /api/admin/promotions/{id}/status) —
    /// nếu hai lần đọc ra hai giá trị thì đó là non-repeatable read.
    /// </summary>
    [HttpPost("read-promotion-twice")]
    public async Task<IActionResult> ReadPromotionTwice([FromBody] ReadPromotionTwiceRequest request)
    {
        var hold = Math.Clamp(request.HoldSeconds, 1, 30);

        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@PromotionID", request.PromotionId, DbType.Int32);
        p.Add("@First",  dbType: DbType.String, size: 32, direction: ParameterDirection.Output);
        p.Add("@Second", dbType: DbType.String, size: 32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync($@"
BEGIN TRANSACTION;
SELECT @First  = PromotionStatus FROM dbo.Promotion WHERE PromotionID = @PromotionID;
WAITFOR DELAY '00:00:{hold:D2}';
SELECT @Second = PromotionStatus FROM dbo.Promotion WHERE PromotionID = @PromotionID;
ROLLBACK TRANSACTION;", p);

        var first  = p.Get<string>("@First");
        var second = p.Get<string>("@Second");

        return Ok(new
        {
            promotionId = request.PromotionId,
            holdSeconds = hold,
            read1       = first,
            read2       = second,
            changed     = first != second
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    // #3b DỮ LIỆU CŨ 15 GIÂY — cache không bao giờ bị xoá khi tồn kho đổi
    // ═══════════════════════════════════════════════════════════════════

    /// <summary>
    /// Trả về HAI danh sách ghế của cùng một concert: danh sách đi qua cache
    /// (đúng cái màn hình quản trị đang đọc) và danh sách đọc thẳng database.
    /// Chênh lệch giữa hai danh sách chính là dữ liệu cũ do cache 15 giây.
    /// </summary>
    [HttpGet("seat-state")]
    public async Task<IActionResult> SeatState([FromQuery] int concertId)
    {
        var cached = (await _seatMapCache.GetSeatsAsync(concertId)).ToList();
        var raw    = (await _concerts.GetSeatsAsync(concertId)).ToList();

        var diff = raw.Count(r => cached.All(c => c.SeatID != r.SeatID || c.InventoryStatus != r.InventoryStatus));

        return Ok(new
        {
            concertId,
            cacheTtlSeconds = 15,   // khớp SeatMapCache(ttlSeconds: 15) đăng ký trong Program.cs
            cached,
            raw,
            differenceCount = diff
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    // #4 PHANTOM READ — hai mã giảm giá trùng nhau
    // ═══════════════════════════════════════════════════════════════════

    /// <summary>
    /// Giữ MỘT mã giảm giá ở trạng thái CHƯA COMMIT trong vài giây rồi ROLLBACK.
    /// Guard của sp_CreateDiscountCode không khoá khoảng (thiếu HOLDLOCK) nên
    /// người dùng ở tab khác vẫn tạo được CÙNG mã ấy ở chương trình khác.
    /// </summary>
    [HttpPost("hold-discount-code")]
    public async Task<IActionResult> HoldDiscountCode([FromBody] HoldDiscountCodeRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.CodeValue))
            return BadRequest(new { message = "Thiếu CodeValue." });

        var actor   = GetActorUserId();
        var seconds = Math.Clamp(request.Seconds, 1, 60);

        using var conn = await _factory.OpenAsync();
        await conn.ExecuteAsync($@"
BEGIN TRANSACTION;
DECLARE @From DATETIME2(7), @To DATETIME2(7), @NewId INT;
SELECT @From = StartDatetime, @To = EndDatetime FROM dbo.Promotion WHERE PromotionID = @Promotion;
EXEC dbo.sp_CreateDiscountCode @ActorUserID = @Actor, @PromotionID = @Promotion, @CodeValue = @Code,
     @ValidFromDatetime = @From, @ValidToDatetime = @To,
     @GlobalUsageLimit = NULL, @PerCustomerUsageLimit = NULL, @NewDiscountCodeID = @NewId OUTPUT;
WAITFOR DELAY '00:00:{seconds:D2}';
ROLLBACK TRANSACTION;",
            new { Actor = actor, Promotion = request.PromotionId, Code = request.CodeValue });

        return Ok(new
        {
            held       = true,
            seconds,
            rolledBack = true,
            codeValue  = request.CodeValue,
            note       = "Mã này đã bị ROLLBACK — nhưng trong lúc giữ, guard của phiên khác KHÔNG nhìn thấy nó."
        });
    }

    /// <summary>Liệt kê mã giảm giá (lọc theo mã / concert) để thấy hai dòng trùng nhau.</summary>
    [HttpGet("discount-codes")]
    public async Task<IActionResult> DiscountCodes([FromQuery] string? codeValue = null,
                                                   [FromQuery] int? concertId = null,
                                                   [FromQuery] int limit = 20)
    {
        using var conn = await _factory.OpenAsync();
        var rows = (await conn.QueryAsync<DemoDiscountCodeRow>(@"
            SELECT TOP (@Limit)
                   dc.DiscountCodeID, dc.PromotionID, dc.CodeValue, dc.CodeStatus,
                   p.PromotionStatus, p.ConcertID
            FROM   dbo.DiscountCode dc
            JOIN   dbo.Promotion    p ON p.PromotionID = dc.PromotionID
            WHERE  (@Code IS NULL OR dc.CodeValue = @Code)
              AND  (@ConcertId IS NULL OR p.ConcertID = @ConcertId)
            ORDER BY dc.DiscountCodeID DESC;",
            new
            {
                Limit     = Math.Clamp(limit, 1, 200),
                Code      = string.IsNullOrWhiteSpace(codeValue) ? null : codeValue,
                ConcertId = concertId
            })).ToList();

        // Số dòng vượt quá số mã khác nhau: >0 nghĩa là đang có mã trùng.
        var duplicateRows = rows.Count - rows.Select(r => r.CodeValue).Distinct().Count();

        return Ok(new { rowCount = rows.Count, duplicateRows, rows });
    }

    // ═══════════════════════════════════════════════════════════════════
    // #5 DEADLOCK — hai phiên giữ khoá theo thứ tự ngược nhau
    // ═══════════════════════════════════════════════════════════════════

    /// <summary>
    /// Chạy hai giao dịch SONG SONG, mỗi giao dịch giữ khoá bảng này rồi xin khoá
    /// bảng kia theo thứ tự ngược nhau, để SQL Server trả về lỗi 1205 thật.
    ///
    /// Lưu ý trung thực: đây là DÀN DỰNG để hội đồng thấy mã 1205. Khu quản trị
    /// hiện KHÔNG có cặp stored procedure nào tự tạo vòng khoá (mọi SP chỉ giữ khoá
    /// trên một bảng nghiệp vụ, dòng đích được đọc bằng UPDLOCK nên hai phiên bị
    /// tuần tự hoá). Cặp deadlock thật của hệ thống nằm ở luồng hoàn tiền
    /// (sp_ProcessRefund ⇄ sp_ConfirmPayment) và cần một Booking thật.
    /// </summary>
    [HttpPost("deadlock")]
    public async Task<IActionResult> Deadlock()
    {
        int? promoId;
        using (var conn = await _factory.OpenAsync())
            promoId = await conn.ExecuteScalarAsync<int?>("SELECT MIN(PromotionID) FROM dbo.Promotion");

        if (promoId is null)
            return BadRequest(new { message = "Cần ít nhất một chương trình khuyến mãi để dàn dựng deadlock." });

        var sqlA = $@"SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE dbo.Promotion SET PromotionStatus = PromotionStatus WHERE PromotionID = {promoId};
WAITFOR DELAY '00:00:03';
UPDATE dbo.Role SET RoleStatus = RoleStatus WHERE RoleName = 'Customer';
ROLLBACK TRANSACTION;";

        var sqlB = $@"SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE dbo.Role SET RoleStatus = RoleStatus WHERE RoleName = 'Customer';
WAITFOR DELAY '00:00:03';
UPDATE dbo.Promotion SET PromotionStatus = PromotionStatus WHERE PromotionID = {promoId};
ROLLBACK TRANSACTION;";

        var taskA = RunSessionAsync(sqlA);
        await Task.Delay(500);              // để phiên A kịp giữ khoá thứ nhất
        var taskB    = RunSessionAsync(sqlB);
        var outcomes = await Task.WhenAll(taskA, taskB);

        return Ok(new
        {
            promotionId = promoId,
            deadlocked  = outcomes.Any(o => o.Deadlocked),
            waitNote    = "SQL Server dò deadlock theo chu kỳ ~5 giây nên có thể chờ tới ~15 giây.",
            sessions    = outcomes,
            note        = "Mã 1205 KHÔNG có trong bảng map của ErrorHandlingMiddleware: trên ứng dụng thật "
                        + "người dùng sẽ nhận HTTP 500, không phải một thông báo nghiệp vụ."
        });

        async Task<DeadlockSessionOutcome> RunSessionAsync(string sql)
        {
            using var c = await _factory.OpenAsync();
            try
            {
                await c.ExecuteAsync(sql);
                return new DeadlockSessionOutcome(false, null);
            }
            catch (SqlException ex)
            {
                return new DeadlockSessionOutcome(ex.Number == 1205, $"#{ex.Number}: {ex.Message}");
            }
        }
    }
}

// ── DTO của module demo (xoá cùng controller khi không cần nữa) ─────────
public sealed record HoldUserStatusRequest(int TargetUserId, string NewStatus, int Seconds);
public sealed record ReadPromotionTwiceRequest(int PromotionId, int HoldSeconds);
public sealed record HoldDiscountCodeRequest(int PromotionId, string CodeValue, int Seconds);

public sealed record TicketCategoryStateRow(
    int TicketCategoryID, int ConcertID, string CategoryName, decimal BasePrice,
    string CategoryStatus, int UpdatedAuditRows);

public sealed record DemoAuditRow(
    long AuditID, string EventType, string EntityType, string EntityID,
    int ActorUserID, string Action, string EventTimestamp);

public sealed record DemoDiscountCodeRow(
    int DiscountCodeID, int PromotionID, string CodeValue, string CodeStatus,
    string PromotionStatus, int ConcertID);

public sealed record DeadlockSessionOutcome(bool Deadlocked, string? Error);



