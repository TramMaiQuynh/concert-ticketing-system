# Concert Ticketing System — Hướng dẫn chạy demo & kịch bản bảo vệ

Tài liệu này đủ để dựng hệ thống từ máy trắng và trình diễn toàn bộ nghiệp vụ.

---

## 1. Yêu cầu môi trường

| Thành phần | Bắt buộc | Ghi chú |
|---|---|---|
| SQL Server 2019+ (Express được) | Có | mặc định instance `.\SQLEXPRESS`, xác thực Windows |
| `sqlcmd` | Có | đi kèm SQL Server Client SDK |
| .NET SDK 9 | Có | |
| Node.js 20+ / npm | Có | |
| Redis | **Không** | có thì nhanh hơn; không có, sơ đồ ghế đọc thẳng từ database |

---

## 2. Cài đặt — một lệnh

```powershell
cd T:\coding\concert_ticketing_system
.\scripts\setup-demo.ps1
```

Script làm tuần tự:

1. Kiểm tra công cụ bắt buộc.
2. Deploy database sạch (28 bảng · 33 trigger · 3 function · 43 stored procedure · 12 view · RBAC · dữ liệu nền).
3. **Sinh mật khẩu ngẫu nhiên** cho 5 SQL login → ghi `.deploy/db-credentials.json`.
4. **Sinh JWT secret và Payment signature secret** (256-bit) → ghi `backend/.../appsettings.Local.json`.
5. Ghi `frontend/.env` trỏ tới API.
6. Build backend và frontend.

> **Không có bí mật nào nằm trong repository.** `appsettings.json` để trống các trường bí mật;
> `Program.cs` từ chối khởi động nếu thiếu. Thư mục `.deploy/` và `appsettings.Local.json`
> đều nằm trong `.gitignore`.

### Chạy hệ thống — hai cửa sổ terminal

```powershell
# [1] Backend
cd backend\src\ConcertTicketing.API
dotnet run

# [2] Frontend
cd frontend
npm run dev
```

### Nạp dữ liệu demo (sau khi backend đã chạy)

```powershell
.\scripts\seed-demo.ps1
```

> Mất khoảng **2 phút**: endpoint `/auth/*` bị giới hạn 5 request/phút mỗi IP để chống
> dò mật khẩu, và script **tôn trọng** giới hạn đó thay vì nới lỏng nó. Bản thân việc
> phải chờ là một điểm đáng nói khi bảo vệ.

Toàn bộ dữ liệu demo được tạo **qua API thật**, không INSERT thẳng vào bảng — nên mọi
stored procedure, trigger, ràng buộc và kiểm tra phân quyền đều được thực thi. Việc seed
chạy trót lọt tự nó đã là một bằng chứng.

Giao diện: **http://localhost:5173**

---

## 2b. Việc BẮT BUỘC làm ngay trước buổi bảo vệ

Diễn tập làm bẩn dữ liệu demo, và có những thứ **không tự phục hồi**. Chạy lại từ đầu:

```powershell
# 1. Dừng backend đang chạy, rồi:
.\scripts\setup-demo.ps1          # dựng lại database sạch (~2 phút)
# 2. Mở lại backend (dotnet run) và frontend (npm run dev)
.\scripts\seed-demo.ps1           # nạp dữ liệu demo (~2 phút, tôn trọng rate limit)
```

Vì sao không thể bỏ qua:

| Thứ bị tiêu hao | Hậu quả nếu không nạp lại |
|---|---|
| `DEMO200K` — **2 lượt / mỗi khách** | Diễn tập 2 lần là `demo_customer` hết lượt; đúng lúc trình diễn thì mã bị từ chối |
| `Concert.PurchaseLimit` = **4 vé / khách** | Giữ chỗ trong lúc tập vẫn tính; tập vài lần là không giữ chỗ được nữa |
| Ghế đã `Booked` | Sơ đồ ghế thưa dần, kém thuyết phục |
| Vé đã soát | Quét lại chỉ ra `ALREADY_USED`, không diễn được bước `SUCCESS` |

> `seed-demo.ps1` **không idempotent** — nó đăng ký `demo_admin`… nên chạy lần hai mà
> chưa dựng lại database sẽ lỗi trùng tài khoản. Luôn `setup-demo.ps1` trước.

---

## 3. Tài khoản demo

Mật khẩu chung: `Demo@12345`

| Tài khoản | Vai trò | Dùng để trình diễn |
|---|---|---|
| `demo_admin` | Admin | quản trị danh mục, phân quyền, vòng đời dữ liệu nền |
| `demo_organizer` | Organizer | tạo/cấu hình concert của chính mình |
| `demo_customer` | Customer | đặt vé, áp khuyến mãi, thanh toán |
| `demo_staff` | Check-in Staff | soát vé tại cổng |

Ba concert được tạo sẵn (số hiệu in ra ở cuối `seed-demo.ps1`, cũng lưu trong
`.deploy/demo-data.json`):

| Concert | Đặc điểm |
|---|---|
| #1 | bán vé thông thường + mã giảm giá `DEMO200K` (giảm 200.000₫) |
| #2 | bật **Fair Access** — sức chứa hàng đợi = 2, chính sách FIFO |
| #3 | bật **Waitlist** — danh sách chờ theo hạng vé |

---

## 4. Kịch bản bảo vệ (khoảng 12–15 phút)

### 4.1 Luồng mua vé cơ bản — 4 phút

1. Trang chủ: ba sự kiện với **trạng thái đúng** (`Đang mở bán`).
2. Vào concert #1 → **sơ đồ ghế hai mức**, đúng mô hình Ticketmaster/seats.io:
   - **Mức 1** vẽ cả khán phòng theo toạ độ thật của địa điểm — sân khấu là điểm
     tiêu cự, mỗi khu là một khối có vị trí và góc xoay, kèm số chỗ còn trống và
     khoảng giá. Khách nhìn thấy chỗ mình sắp mua **nằm ở đâu trong khán phòng**.
   - **Mức 2** chỉ tải khi bấm vào một khu, rồi mới vẽ từng ghế theo hàng/cột.
   - Vì sao tách hai mức: mỗi ghế tốn ~234 byte trong phản hồi; một sân 20.000 chỗ
     sẽ là gần 5 MB nếu trả hết một lần. Tách ra là quyết định về *khả năng mở rộng*,
     không phải về thẩm mỹ.
   - Màu sắc theo đúng năm giá trị `InventoryStatus` của database
     (`Available / OnHold / OnHoldForWaitlist / Booked / Unavailable`).
3. Chọn 2 ghế → nhấn **Giữ chỗ**. Chỉ ra:
   - giới hạn số vé lấy từ `Concert.PurchaseLimit`, không phải hằng số;
   - đồng hồ **đếm ngược giữ chỗ** — đây là Temporary Hold có thời hạn.
4. Nhập mã `DEMO200K` → tổng tiền giảm 200.000₫ (định dạng **VND**, đúng ràng buộc
   `CHK_Payment_Currency` của database).

### 4.2 Thanh toán — điểm nhấn kỹ thuật — 3 phút

5. Nhấn **Thanh toán** → mở trang *cổng thanh toán mô phỏng*.

   **Điều đáng nói ở đây:** frontend **không** tự xác nhận thanh toán. Nó chỉ khởi tạo
   giao dịch; chữ ký HMAC là bí mật dùng chung giữa backend và cổng thanh toán, không
   bao giờ xuống trình duyệt. Bộ mô phỏng đóng đúng vai cổng thanh toán và chạy **trong
   backend**: nó tự tính chữ ký rồi gọi vào cùng luồng xác nhận thật, nên toàn bộ mã
   kiểm tra chữ ký và kiểm tra số tiền vẫn được thực thi.

   Nếu trả chữ ký về cho trình duyệt, khách có thể tự cấp vé cho mình mà không trả tiền —
   đúng lỗ hổng đã tồn tại trong bản trước và đã được gỡ bỏ.

6. Chỉ vào ô **Mã giảm giá** ngay lúc đó: cả ô nhập lẫn nút *Áp dụng* đều **bị vô hiệu
   hoá** khi đơn đã có giao dịch chờ ở cổng. Giá đơn hàng bị **khóa** từ lúc khách bước
   vào cổng thanh toán, vì nếu không thì số tiền khách đang trả sẽ không còn khớp đơn.

   Giao diện **chặn trước** thay vì để người dùng bấm rồi mới báo lỗi — nhưng lớp bảo vệ
   thật nằm ở database, không ở nút bấm. Muốn chứng minh thì gọi thẳng API trong lúc
   đang chờ cổng: `POST /api/bookings/{id}/promotion` trả **409** (lỗi 54013 từ
   `sp_ApplyPromotion`). Tắt JavaScript cũng không lách được.
7. Bấm **Thanh toán thành công** → Booking chuyển `Confirmed`, ghế chuyển `Booked`,
   vé được phát hành.

### 4.3 Soát vé — 2 phút

> ⚠️ **Chuẩn bị trước bước này.** Mã vé là GUID trong bảng `Ticket`, và **hiện không
> có màn hình hay endpoint nào trả mã vé về cho chính người mua** — `BookingDetail`
> không mang trường này, `Ticket` không có SP đọc. Vì vậy phải lấy mã bằng SQL,
> **chuẩn bị sẵn trước khi vào phòng**:
>
> ```powershell
> sqlcmd -S .\SQLEXPRESS -E -d ConcertTicketingDB -I -h -1 -W -Q `
>   "SELECT TOP 1 t.TicketCode, b.ConcertID FROM Ticket t JOIN Booking b ON b.BookingID=t.BookingID
>    WHERE NOT EXISTS (SELECT 1 FROM CheckIn c WHERE c.TicketID=t.TicketID) ORDER BY t.TicketID DESC;"
> ```
>
> Đây là một **giới hạn đã biết**, nên nói thẳng nếu hội đồng hỏi: luồng soát vé ở
> phía nhân viên đã hoàn chỉnh, phần còn thiếu là đường đọc để khách xem vé của
> mình (`GET /bookings/{id}/tickets`). Nói ra một giới hạn có thật vẫn hơn để hội
> đồng tự phát hiện.

8. Đăng nhập `demo_staff` → **Soát vé** → nhập mã vé (lấy ở trên) → `SUCCESS`.
9. Quét lại đúng mã đó → `ALREADY_USED`. Vé chỉ dùng được một lần.
10. Đăng nhập `demo_customer` và thử vào trang Soát vé → không có lối vào; gọi thẳng API
    thì nhận **403**. Phân quyền được thi hành ở backend và trong stored procedure,
    giao diện chỉ phản ánh lại.

### 4.4 Fair Access — 3 phút

11. Vào concert #2 (bật Fair Access) → giao diện hiện khối **hàng đợi**, chưa cho chọn ghế.
12. Thử đặt vé khi chưa được vào hàng → **403 “Queue Admission Required”**.
13. Bấm **Vào hàng đợi** → trạng thái `Đang xếp hàng`, có vị trí.
14. Chờ tối đa 15 giây: tiến trình nền **SIP3** tự chuyển sang `Đã được vào mua vé`,
    kèm đồng hồ đếm ngược `booking_ttl`.
15. Đặt vé thành công → hàng đợi tự nhả suất cho người kế tiếp (BR47b).

### 4.4b Khu quản trị — 3 phút

16a. Đăng nhập `demo_admin` → **Quản trị** trên thanh điều hướng. **Sáu mục**: Concert,
    Danh mục, Sơ đồ địa điểm, Khuyến mãi, Hoàn tiền, Người dùng. Organizer chỉ thấy
    **bốn** (Concert, Danh mục, Khuyến mãi, Hoàn tiền); *Sơ đồ địa điểm* và *Người
    dùng* chỉ Admin thấy — đúng bằng những gì stored procedure cho phép, giao diện
    không tự nới rộng.
16b. Dựng một sự kiện **từ đầu ngay trên giao diện**: Danh mục → tạo nghệ sĩ, địa
    điểm, khu vực, rồi *tạo hàng loạt* 12 ghế. Sang Concert → tạo concert → hạng vé
    → đưa ghế vào kho vé → chuyển `Published` → `OnSale`. Sự kiện xuất hiện ở trang chủ.
16c. **Điểm đáng nói:** thử chuyển `OnSale` khi chưa có ghế trong kho hoặc chưa đặt
    cửa sổ bán → hệ thống từ chối (BR10). Giao diện nói trước điều kiện thay vì để
    người dùng đâm vào tường.
### 4.4c Dựng sơ đồ địa điểm — 3 phút *(chỉ Admin)*

16e. `demo_admin` → **Quản trị → Sơ đồ địa điểm**. Chọn địa điểm; nhãn ghi rõ địa
    điểm nào **đã có** sơ đồ, địa điểm nào **chưa**.

16f. Ba bước theo đúng thứ tự phụ thuộc của database, có **bản xem trước vẽ lại
    theo từng ký tự** — người dùng sắp đặt khán phòng bằng cách gõ toạ độ, gõ mà
    không thấy kết quả thì không làm được:
    - **Bước 1** mặt phẳng + sân khấu (`sp_ConfigureVenueMap`). Nút *Dùng bố cục
      mẫu* điền sẵn 1000×720, sân khấu 360×56.
    - **Bước 2** các khu, có toạ độ và **góc xoay** để hướng khu về phía sân khấu.
      Chọn *Vé đứng* thì khu bán theo **sức chứa và không có ghế nào** — đó mới là
      cách đúng để mô hình hoá khu đứng trước sân khấu, thay vì tạo hàng trăm ghế giả.
    - **Bước 3** tạo ghế theo lưới hàng × cột, tự sinh nhãn A/B/C và số ghế.

16g. **Điểm đáng nói — vì sao Admin dựng trước, organizer chỉ chọn:** hình dáng khán
    phòng thuộc về *địa điểm*, không thuộc về *concert*. Một địa điểm dựng một lần,
    mọi concert tổ chức ở đó về sau dùng lại. Nếu để mỗi organizer tự vẽ thì cùng một
    nhà hát sẽ có mười sơ đồ khác nhau, và khách quen ghế C12 sẽ thấy mỗi lần một khác.

16h. Thử nhập một khu **vượt ra ngoài mặt phẳng** → database từ chối kèm lý do cụ
    thể. Ràng buộc nằm ở tầng dữ liệu, không phải ở JavaScript.

16d. Khách hủy vé: đăng nhập `demo_customer` → **Vé của tôi** → *Hủy vé* trên một đơn
    đã xác nhận. Không có ô nhập số tiền hoàn — số tiền do database tự tính theo
    `Concert.RefundPercentage`. Quay lại `demo_organizer` → Quản trị → Hoàn tiền →
    xác nhận khoản hoàn.

### 4.5 Chiều sâu kỹ thuật — 3 phút

16. **Kiến trúc Thick Database**: mở `database/StoredProcedures/sp_CreateBooking.sql`,
    chỉ vào `UPDATE … WHERE InventoryStatus = 'Available'` + `@@ROWCOUNT` — chống bán
    trùng ghế bằng chính database, không phải bằng khóa ở tầng ứng dụng.
17. **Bộ kiểm thử**: `database/Tests/Run-All-Tests.ps1` → 159 test SQL, kèm test đồng
    thời chạy nhiều kết nối song song chứng minh chống oversell.
    `dotnet test` ở `backend/` → 191 unit + 72 integration.

    > ⚠️ **Chạy bộ test SQL sẽ XOÁ SẠCH dữ liệu demo** (xem §5). Hãy để bước này ở
    > CUỐI buổi, hoặc chạy `.\scripts\seed-demo.ps1` lại sau đó.
18. **Phân quyền ở tầng dữ liệu**: `api_service` bị `DENY INSERT/UPDATE/DELETE` trên các
    bảng lõi — mọi thao tác ghi buộc phải qua stored procedure.
19. **Row-Level Security**: `VW_CustomerBookingHistory` lọc theo
    `SESSION_CONTEXT(N'UserID')`, nên trang “Vé của tôi” không hề gửi lên `userId` nào cả.
20. **Giới hạn của API phản ánh thẳng lên giao diện**: API quản trị gần như toàn bộ là
    endpoint **ghi**. Về sau đã bổ sung **bốn** đường đọc — `GET /admin/venues`,
    `GET /admin/venues/{id}/zones`, `GET /admin/artists` — đủ để màn *Sơ đồ địa điểm*
    và các ô chọn địa điểm/nghệ sĩ hoạt động bằng dữ liệu thật. Những thứ còn lại
    (hạng vé, khuyến mãi, mã giảm giá, ghế) **vẫn chưa có đường đọc**. Vì vậy khu
    quản trị vẫn giữ một *sổ tay cục bộ* trong
    `localStorage` để nhớ ID vừa tạo — nếu không, tạo xong một khu vực là mất dấu ID và
    không tạo ghế trong khu đó được nữa. Sổ tay có nút dọn, và mọi ô chọn đều kèm ô nhập
    ID thủ công để không bao giờ bị kẹt. Đây là chỗ đáng nói khi bảo vệ: giao diện tốt
    nhất cũng không bù được một API thiếu đường đọc.

---

### 4.6 Trình diễn 5 hiện tượng tranh chấp đồng thời — 5 phút

Chạy **ở cuối buổi**, sau khi đã trình diễn xong tính năng (kịch bản tự dựng dữ liệu
riêng mang tiền tố `DEMO-CC`, không đụng vào 3 concert demo):

```powershell
cd T:\coding\concert_ticketing_system
.\scripts\demo-concurrency.ps1                      # chạy cả 5
.\scripts\demo-concurrency.ps1 -Scenario phantom    # hoặc chạy riêng từng cái
```

Mỗi hiện tượng diễn **hai vế** — chỉ một vế thì không chứng minh được gì:

| # | Hiện tượng | Vế 1: lỗi có thật | Vế 2: hệ thống chặn được |
|---|---|---|---|
| 1 | **Lost Update** | Đọc trạng thái rồi mới ghi → cả hai khách cùng "giữ được" ghế A01 | `sp_CreateBooking` cập nhật có điều kiện + kiểm `@@ROWCOUNT` → đúng một người thắng, người kia nhận *"ghế đã được người khác đặt"* |
| 2 | **Dirty Read** | Với `NOLOCK`, khách B thấy ghế `OnHold` từ giao dịch **sau đó bị hủy** → bị báo hết ghế oan | READ COMMITTED mặc định → B chờ rồi thấy đúng `Available` |
| 3 | **Non-repeatable Read** | Đọc trần hai lần trong một lượt xử lý → `Available` rồi `OnHold` | `WITH (UPDLOCK)` → hai lần đọc giống hệt nhau |
| 4 | **Phantom Read** | Đếm hàng đợi hai lần → 0 rồi 1, mọc thêm người | `WITH (UPDLOCK, HOLDLOCK)` như `sp_JoinQueue` → hai lần đếm bằng nhau |
| 5 | **Deadlock** | Hai giao dịch khoá hai ghế theo thứ tự ngược → SQL Server chọn nạn nhân, lỗi **1205** | Luồng đặt vé thật với ghế chồng nhau, thứ tự ngược → **không** deadlock |

**Điểm nhấn đáng nói ở mục 5:** `sp_CreateBooking` giữ ghế bằng **một câu lệnh tập hợp
duy nhất**, nên SQL Server luôn khoá theo thứ tự chỉ mục chứ không theo thứ tự khách
chọn ghế. Hai giao dịch vì thế luôn xin khoá cùng chiều và không thể tạo thành vòng
chờ — đây là tính chất thiết kế, không phải may mắn.

**Nói thẳng nếu hội đồng hỏi:** hệ thống **không** nâng mức cô lập toàn cục lên
REPEATABLE READ / SERIALIZABLE. Hiện tượng 3 và 4 **vẫn xảy ra được** ở những truy vấn
đọc trần không đặt khoá — đó là hành vi đúng của READ COMMITTED. Hệ thống chọn đặt khoá
đúng điểm nóng (`UPDLOCK` ở 25/43 thủ tục, `HOLDLOCK` ở các chỗ đếm phạm vi, thêm
`sp_getapplock` ở 4 thủ tục nặng) để đổi lấy thông lượng, thay vì khoá toàn cục.

Cửa sổ tranh chấp trong kịch bản được nới rộng bằng `WAITFOR`, nên kết quả **tái hiện
được mọi lần**, không phụ thuộc may rủi về thời điểm.

---

## 5. Lệnh chạy kiểm thử

```powershell
# Database — 159 test (chạy TỪ thư mục Tests)
cd database\Tests
.\Run-All-Tests.ps1

# Backend — 191 unit + 72 integration
cd backend
dotnet test
```

> ⚠️ **`Run-All-Tests.ps1` xoá toàn bộ dữ liệu nghiệp vụ trước khi chạy.**
> `01_SetupMockData.sql` `DELETE` 24 bảng (giữ lại mỗi tài khoản `system`) để mỗi lần
> chạy đều bắt đầu từ trạng thái đã biết — đúng với một bộ test, nhưng nó **xoá luôn 4
> tài khoản demo và 3 concert demo**. Sau khi chạy test SQL, phải nạp lại:
>
> ```powershell
> .\scripts\seed-demo.ps1
> ```
>
> `dotnet test` thì **không** xoá gì: test tích hợp tự tạo dữ liệu riêng, dữ liệu demo
> vẫn nguyên.
>
> Bộ test SQL cũng **để lại** dữ liệu mock của nó — sau khi chạy, trang chủ sẽ có thêm
> một sự kiện lạ `Test Concert Live 2025` đang mở bán. Muốn sạch hoàn toàn thì deploy
> lại từ đầu bằng `.\scripts\setup-demo.ps1`.

---

## 6. Giới hạn đã biết — nên chủ động trình bày

Nêu trước sẽ tốt hơn để hội đồng hỏi:

1. **Chưa tích hợp cổng thanh toán thật.** Demo dùng bộ mô phỏng chạy phía máy chủ.
   `Program.cs` **từ chối khởi động** nếu bật chế độ mô phỏng ở môi trường Production.
2. **Chưa kiểm thử tải và chưa phân tích deadlock.** Test đồng thời hiện chỉ vài kết
   nối. Với hệ bán vé, đây là rủi ro lớn nhất còn lại.
3. **Chưa có đường migration.** `deploy.ps1` chỉ deploy sạch; thay đổi lược đồ sau khi
   có dữ liệu thật sẽ mất dữ liệu.
4. **Một instance, không HA/backup** — phạm vi đã chốt tại §23.7 của đặc tả.
5. **Múi giờ**: mọi mốc thời gian dùng `SYSDATETIME()` (giờ máy chủ). Đúng khi trình
   duyệt và SQL Server cùng múi giờ; phục vụ đa múi giờ thì phải chuyển database sang UTC.
6. **Chưa kiểm chứng ở quy mô nhiều instance.** Toàn bộ khoá đồng thời (`sp_getapplock`,
   `UPDLOCK`/`READPAST`) nằm trong SQL Server nên đúng khi chạy nhiều instance API,
   nhưng điều đó chưa được kiểm chứng bằng thực nghiệm.

---

## 7. Bản đồ thư mục

```
database/     28 bảng, 33 trigger, 3 function, 40 SP, 11 view, RBAC, 159 test
backend/      .NET 9 · Clean Architecture · Dapper · JWT · 247 test
frontend/     React 19 · Vite · React Router · khu quản trị đủ 23 endpoint
scripts/      setup-demo.ps1 (cài đặt) · seed-demo.ps1 (dữ liệu demo)
docs/         database_plan.txt — đặc tả gốc, là nguồn tham chiếu của toàn hệ thống
.deploy/      bí mật sinh ra lúc triển khai (KHÔNG commit)
```
