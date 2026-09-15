using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests.Infrastructure;

/// <summary>
/// Kết nối DB thật (ConcertTicketingDB trên .\SQLEXPRESS).
/// - AdminConnectionString (Windows Auth): seed/cleanup/verify.
/// - ApiConnectionString (api_service): đúng principal backend sản phẩm
///   → mọi repository test với least-privilege thật (bắt lỗi thiếu GRANT).
/// Dữ liệu test dùng suffix duy nhất và được dọn sạch sau mỗi test-class.
/// </summary>
public sealed partial class DbFixture : IAsyncLifetime
{
    public const string DbName = "ConcertTicketingDB";

    public string AdminConnectionString { get; } =
        $"Server=.\\SQLEXPRESS;Database={DbName};Trusted_Connection=True;TrustServerCertificate=True;Connection Timeout=30;";

    /// <summary>
    /// Chuỗi kết nối dưới danh tính api_service — đúng principal mà backend sản phẩm dùng,
    /// nên test phát hiện được mọi GRANT còn thiếu.
    ///
    /// Mật khẩu KHÔNG còn viết cứng: database/deploy.ps1 sinh mật khẩu ngẫu nhiên cho mỗi
    /// lần triển khai và ghi ra .deploy/db-credentials.json (nằm trong .gitignore). Trước
    /// đây giá trị này trùng đúng mật khẩu bị commit trong CreateDBUsers.sql — chính là lỗ
    /// hổng đã được gỡ bỏ.
    /// </summary>
    public string ApiConnectionString { get; } = ResolveApiConnectionString();

    /// <summary>Bí mật chữ ký CHỈ dùng trong test — không liên quan tới bí mật thật.</summary>
    public string PaymentSignatureSecret { get; } = "integration-test-signing-secret-32ch";

    /// <summary>
    /// Cấu hình cổng thanh toán cho test: KHÔNG dùng bộ mô phỏng. Test gọi thẳng repository
    /// nên chỉ cần một giá trị hợp lệ để dựng PaymentRepository.
    /// </summary>
    public static ConcertTicketing.Application.Services.PaymentGatewaySettings TestGateway { get; } =
        new(IsSimulator: false, PaymentUrlBase: "https://example.invalid/pay");

    /// <summary>
    /// Tìm chuỗi kết nối api_service theo thứ tự:
    ///   1. Biến môi trường CONCERT_TEST_API_CONNECTION (dùng cho CI).
    ///   2. .deploy/db-credentials.json do deploy.ps1 sinh ra.
    /// Không tìm thấy thì DỪNG với thông báo chỉ rõ việc cần làm, thay vì để hàng loạt test
    /// thất bại bằng lỗi đăng nhập khó hiểu.
    /// </summary>
    private static string ResolveApiConnectionString()
    {
        var fromEnv = Environment.GetEnvironmentVariable("CONCERT_TEST_API_CONNECTION");
        if (!string.IsNullOrWhiteSpace(fromEnv)) return fromEnv;

        var dir = AppContext.BaseDirectory;
        for (var i = 0; i < 8 && !string.IsNullOrEmpty(dir); i++)
        {
            var candidate = Path.Combine(dir, ".deploy", "db-credentials.json");
            if (File.Exists(candidate))
            {
                using var doc = System.Text.Json.JsonDocument.Parse(File.ReadAllText(candidate));
                var conn = doc.RootElement.GetProperty("apiServiceConnection").GetString();
                if (!string.IsNullOrWhiteSpace(conn)) return conn;
            }
            dir = Path.GetDirectoryName(dir.TrimEnd(Path.DirectorySeparatorChar));
        }

        throw new InvalidOperationException(
            "Không tìm thấy chuỗi kết nối api_service. Chạy database/deploy.ps1 để sinh " +
            ".deploy/db-credentials.json, hoặc đặt biến môi trường CONCERT_TEST_API_CONNECTION.");
    }

    /// <summary>Factory ket noi cho repository trong test (khong co danh tinh nguoi dung).</summary>
    public TestConnectionFactory ApiFactory => new(ApiConnectionString);

    /// <summary>
    /// Tinh chu ky thanh toan giong het cong thanh toan that: test biet secret dung chung,
    /// CLIENT thi khong — day chinh la ly do InitiatePaymentResponse khong tra chu ky ve.
    /// </summary>
    public string ComputePaymentSignature(int bookingId, int paymentId, decimal amount)
        => ConcertTicketing.Application.Services.PaymentSignatureCalculator.Compute(
               PaymentSignatureSecret, bookingId, paymentId, amount);

    public string Suffix { get; } = Guid.NewGuid().ToString("N")[..8];

    public Task InitializeAsync()
    {
        using var admin = new SqlConnection(AdminConnectionString);
        admin.Open();
        var spCount = admin.QuerySingle<int>(
            "SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0;");
        if (spCount < 20)
            throw new InvalidOperationException(
                $"DB chưa deploy đầy đủ (chỉ có {spCount} stored procedure).");

        using var api = new SqlConnection(ApiConnectionString);
        api.Open();

        return Task.CompletedTask;
    }

    public async Task DisposeAsync() => await CleanupSuffixAsync();

    public async Task<int> ExecAdminAsync(string sql, object? param = null)
    {
        await using var conn = new SqlConnection(AdminConnectionString);
        return await conn.ExecuteAsync(sql, param);
    }

    public async Task<T?> QueryAdminAsync<T>(string sql, object? param = null)
    {
        await using var conn = new SqlConnection(AdminConnectionString);
        return await conn.QuerySingleOrDefaultAsync<T>(sql, param);
    }

    /// <summary>
    /// Chèn một dòng và trả về khoá do CHÍNH lệnh chèn đó sinh ra.
    ///
    /// Vì sao cần: seeder trước đây chèn xong rồi truy vấn lại theo khoá tự nhiên
    /// (tên nghệ sĩ, tên địa điểm, tên concert…). Cách đó chỉ đúng khi tên chắc chắn
    /// duy nhất ở MỌI lần gọi — một điều kiện không có gì bảo đảm, vì các bảng này
    /// không có UNIQUE trên tên. Gọi cùng một phương thức seeder hai lần trong một
    /// test là đủ để sinh hai dòng trùng tên, và truy vấn "lấy một dòng" khi đó ném
    /// "Sequence contains more than one element" ngay ở bước dựng dữ liệu — test chết
    /// trước khi kiểm tra được thứ nó định kiểm tra.
    ///
    /// SCOPE_IDENTITY() trả về đúng khoá vừa sinh trong phạm vi lệnh này, không phụ
    /// thuộc dữ liệu sẵn có, nên loại bỏ hẳn lớp lỗi đó thay vì né nó bằng cách đặt
    /// tên khác nhau ở từng chỗ gọi.
    /// </summary>
    public async Task<int> InsertAdminAsync(string sql, object? param = null)
    {
        await using var conn = new SqlConnection(AdminConnectionString);
        return await conn.QuerySingleAsync<int>(
            sql + "\nSELECT CAST(SCOPE_IDENTITY() AS INT);", param);
    }

    public async Task<List<T>> QueryAdminListAsync<T>(string sql, object? param = null)
    {
        await using var conn = new SqlConnection(AdminConnectionString);
        return (await conn.QueryAsync<T>(sql, param)).ToList();
    }
}