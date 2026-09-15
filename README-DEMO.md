# Concert Ticketing System — Hướng dẫn chạy demo & kịch bản bảo vệ

Tài liệu này đủ để dựng hệ thống từ máy trắng và trình diễn toàn bộ nghiệp vụ.  
Database khởi động **hoàn toàn trống** — không có dữ liệu nào cài sẵn ngoài đúng
một tài khoản `admin`. Mọi thứ trong buổi bảo vệ được tạo **live trên giao diện**.

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

## 2. Cài đặt — ba bước, lần đầu

### Bước 1 — Deploy database + build (một lệnh, ~3 phút)

```powershell
cd T:\coding\concert_ticketing_system
.\scripts\setup-demo.ps1
```

Script làm tuần tự:

1. Kiểm tra `sqlcmd`, `dotnet`, `npm`.
2. Deploy database sạch (`deploy.ps1 -DropExisting $true`) — 29 bảng · 33 trigger · 3 function · 44 stored procedure · 17 view · RBAC.
3. **Sinh mật khẩu ngẫu nhiên** cho 5 SQL login → ghi `.deploy/db-credentials.json`.
4. **Sinh JWT secret + Payment signature secret** (256-bit) → ghi `backend/.../appsettings.Local.json`.
5. Ghi `frontend/.env` để Vite proxy `/api` tới API.
6. Build backend và frontend.

> **Không có bí mật nào trong repository.** `appsettings.json` để trống các trường bí mật;
> `Program.cs` từ chối khởi động nếu thiếu. `.deploy/` và `appsettings.Local.json` đều
> trong `.gitignore`.

### Bước 2 — Chạy hệ thống (hai cửa sổ terminal)

```powershell
# [1] Backend
cd backend\src\ConcertTicketing.API
dotnet run

# [2] Frontend
cd frontend
npm run dev
```

### Bước 3 — Bootstrap tài khoản admin (một lần, sau khi backend đã chạy)

```powershell
.\scripts\bootstrap-admin.ps1
```

Script này làm duy nhất một việc:

1. Gọi `POST /api/auth/register` — tạo tài khoản `admin / Demo@12345` qua API thật (BCrypt hash, rate limit, trigger audit đều chạy).
2. Dùng `sqlcmd` gán role Admin cho user vừa tạo — đây là bước **không thể tránh**: `sp_AssignRole` yêu cầu người gọi đã là Admin, nhưng Admin đầu tiên chưa tồn tại. INSERT trực tiếp vào `UserRoleAssignment` là giải pháp duy nhất, và đây là lần duy nhất trong toàn hệ thống phải làm vậy.
3. Xác nhận bằng cách login lại và gọi `GET /admin/artists` — nếu 200 OK thì bootstrap thành công.

Sau bước này, database có đúng **hai** bản ghi trong `UserAccount`:

| Username | Ghi chú |
|---|---|
| `system` | Tài khoản nội bộ cho các tiến trình nền, `PasswordHash = NULL`, không đăng nhập được |
| `admin` | Tài khoản quản trị bootstrap, mật khẩu `Demo@12345` |

Giao diện: **http://localhost:5173**

---

## 2b. Reset nhanh chỉ database (không cần build lại)

Dùng khi muốn trở về trạng thái trắng giữa các lần diễn tập mà không cần build lại:

```powershell
# Bước A — Dừng backend đang chạy (Ctrl+C ở cửa sổ dotnet run)

# Bước B — Deploy lại database sạch
cd database
.\deploy.ps1 -ServerInstance ".\SQLEXPRESS" -DropExisting $true
cd ..

# Bước C — Ghi lại cấu hình theo mật khẩu SQL mới (BẮT BUỘC, xem ghi chú dưới)
.\scripts\setup-demo.ps1 -SkipDatabase

# Bước D — Chạy lại backend (dotnet run), rồi bootstrap admin
.\scripts\bootstrap-admin.ps1
```

**Bước C không được bỏ.** `deploy.ps1` sinh mật khẩu SQL mới mỗi lần, nên
`appsettings.Local.json` cũ trỏ tới mật khẩu không còn tồn tại — backend sẽ khởi động
rồi chết ở lời gọi database đầu tiên. `-SkipDatabase` bảo script bỏ qua phần deploy và
chỉ làm lại cấu hình + build.

### Xác nhận database thật sự trống

Bước nhỏ nhưng đừng bỏ: nó phân biệt "script báo thành công" với "database đúng là
trạng thái mình nghĩ".

```powershell
sqlcmd -S .\SQLEXPRESS -E -d ConcertTicketingDB -I -h -1 -W -Q `
  "SELECT 'UserAccount', COUNT(*) FROM UserAccount
   UNION ALL SELECT 'Role',    COUNT(*) FROM Role
   UNION ALL SELECT 'Concert', COUNT(*) FROM Concert
   UNION ALL SELECT 'Venue',   COUNT(*) FROM Venue
   UNION ALL SELECT 'Booking', COUNT(*) FROM Booking;"
```

Ngay sau deploy (trước `bootstrap-admin.ps1`) kết quả phải đúng như sau:

```
UserAccount 1     <- duy nhất 'system', PasswordHash NULL, không đăng nhập được
Role        4     <- Admin / Organizer / Customer / Check-in Staff
Concert     0
Venue       0
Booking     0
```

Đó là toàn bộ dữ liệu nền: 4 vai trò, 1 tài khoản kỹ thuật cho các tiến trình nền, và
5 khoá cấu hình hệ thống. **Không một dòng dữ liệu nghiệp vụ nào.** Nếu `UserAccount`
khác 1, database chưa sạch — đừng bắt đầu buổi demo cho tới khi nó bằng 1.

> **Tại sao `deploy.ps1` sinh mật khẩu mới mỗi lần?** Đây là quyết định bảo mật có chủ đích:
> nếu `.deploy/db-credentials.json` bị lộ, kẻ tấn công chỉ dùng được đến lần deploy kế tiếp.
> Hệ quả thực tế: sau mỗi lần deploy lại, phải cập nhật `appsettings.Local.json` — chạy
> `setup-demo.ps1` sẽ làm điều này tự động.

---

## 3. Tài khoản demo

Mật khẩu chung cho mọi tài khoản được tạo trong buổi demo: `Demo@12345`

| Tài khoản | Vai trò | Khi nào tạo |
|---|---|---|
| `admin` | Admin | Bootstrap sẵn trước buổi demo |
| Các tài khoản khác | Customer / Organizer / Check-in Staff | Tạo **live** trên giao diện trong buổi demo |

> **Không có dữ liệu nào cài sẵn ngoài admin.** Không có concert, nghệ sĩ, địa điểm, hay
> tài khoản nào khác. Mọi thứ được xây dựng trực tiếp trên giao diện — đây chính là
> điểm mạnh của buổi trình diễn: hội đồng thấy hệ thống hoạt động từ trang trắng.

---

## 4. Kịch bản bảo vệ — xây dựng từ đầu (~18 phút)

### 4.1 Dựng hạ tầng — Danh mục (3 phút)

Đăng nhập `admin` → **Quản trị → Danh mục**.

**a. Tạo nghệ sĩ**
- Điền tên, thể loại, quốc gia → Lưu.

**b. Tạo địa điểm**
- Điền tên, địa chỉ, thành phố, sức chứa → Lưu.
- Ghi lại ID hiển thị trong giao diện — dùng ở bước tạo Zone.

**c. Tạo khu vực (Zone)**
- Chọn địa điểm vừa tạo → nhập Mã khu vực (`A`) + Tên hiển thị → Lưu. Hạng vé xuất hiện trong danh mục để chọn.
- Khu tạo ở trang này **luôn là khu có ghế** (`Seated`) — đó là mặc định của
  `sp_CreateZone`, và form ở đây cố ý không hỏi loại khu.
- Bản hiện tại chỉ bán theo ghế đánh số. Vé đứng cần một kho capacity, giữ chỗ, hoàn vé
  và thanh toán riêng; hệ thống không hiển thị lựa chọn đó để tránh tạo khu không thể bán.

**d. Tạo ghế (khu có ghế)**
- Tạo một ghế: **Mã ghế** (`A1`) + Hàng (`A`) + Số thứ tự trong hàng (`1`) → Lưu.
  Sau mỗi lần tạo, ô số thứ tự tự tăng để gõ tiếp `A2`, `A3`… nhanh hơn.
- Mã ghế chỉ cần duy nhất trong **Zone** đã chọn. Vì vậy cùng một Venue có thể có ghế
  `A1` ở Zone A và `A1` ở Zone B; trùng `A1` trong cùng Zone sẽ bị từ chối.
- Tạo hàng loạt: **Tiền tố mã ghế** (`A`) + Hàng (`A`) + Từ (`1`) đến (`12`).
  Một lệnh tạo 12 ghế `A1`–`A12`, banner trả về dải ID — **cần dải này ở §4.3**.

**Điểm kỹ thuật đáng nói:** mã ghế là **định danh**, hàng và số thứ tự mới là **vị trí**
— hai thứ khác nhau, nên form hỏi cả hai. Thử tạo ghế mà bỏ trống Hàng/Số thứ tự trong
một khu có ghế → hệ thống từ chối (`sp_CreateSeat` lỗi 59825). Không phải luật hình
thức: thiếu vị trí thì sơ đồ dồn mọi ghế về cùng một ô và chúng chồng khít lên nhau,
người dùng chỉ thấy đúng một ghế còn những ghế kia biến mất không một thông báo nào.
Các ràng buộc này nằm ở stored procedure, không phải JavaScript — tắt JavaScript cũng
không lách được.

---

### 4.2 Dựng sơ đồ địa điểm (3 phút) *(chỉ Admin thấy mục này)*

**Quản trị → Sơ đồ địa điểm** → chọn địa điểm vừa tạo.

Giao diện chia ba bước theo đúng thứ tự phụ thuộc của database — bỏ qua thứ tự sẽ bị từ chối:

**Bước 1 — Mặt phẳng + sân khấu** (`sp_ConfigureVenueMap`)
- Chọn mẫu gần nhất: *Sân khấu phía trước*, *Sân khấu trung tâm* hoặc *Mặt bằng không sân khấu*.
- Kích thước kỹ thuật chỉ dành cho trường hợp cần hiệu chỉnh; đây là hệ tọa độ nội bộ, không phải mét hay pixel.

**Bước 2 — Các khu trên canvas**
- Nhập mã, tên và tầng; sau đó **vẽ trực tiếp** vùng khu trên mặt bằng, kéo để di chuyển, kéo tay nắm ở góc để đổi kích thước và dùng nút xoay khi cần.
- Không cần đoán hoặc gõ `X/Y/Width/Height`: trình biên tập tự sinh các giá trị này, tự căn lưới và giữ khu trong mặt bằng.
- Khu không được đè lên sân khấu hoặc khu khác cùng tầng. Hai tầng có thể dùng cùng hình chiếu, và màn hình bán vé cho khách chọn từng tầng.

**Bước 3 — Ghế theo lưới hàng × cột**
- Chọn khu, nhập số hàng, số cột, nhãn hàng bắt đầu → hệ thống tự sinh nhãn `A/B/C…` và số ghế `1/2/3…` trong **một giao dịch**. Nếu có một mã hoặc vị trí trùng, cả lưới được rollback.

**Điểm đáng nói:** hình dáng khán phòng thuộc về *địa điểm*, không thuộc về *concert*. Một địa điểm cấu hình một lần, mọi concert tổ chức ở đó về sau dùng lại. Nếu để mỗi organizer tự vẽ, cùng một nhà hát sẽ có mười sơ đồ khác nhau và khách quen ghế C12 sẽ thấy mỗi lần một khác.

---

### 4.3 Tạo concert + vòng đời → OnSale (3 phút)

> ⚠️ **Làm bước này TRƯỚC, nếu không sẽ kẹt ngay ở dòng đầu tiên.**
>
> **Quản trị → Người dùng → Cấp và thu hồi vai trò**: UserID `2` (tài khoản `admin`
> do `bootstrap-admin.ps1` tạo — số hiệu ghi sẵn trong `.deploy/bootstrap-info.json`),
> vai trò **Organizer**, hành động **Cấp**. Rồi **đăng xuất và đăng nhập lại**.
>
> **Vì sao:** một concert phải **thuộc về một Organizer** — `sp_CreateConcert` kiểm tra
> rằng người đứng tên concert đang giữ vai trò Organizer, và từ chối nếu không (lỗi
> 58006). Vai trò Admin **không** bao hàm Organizer: Admin quản trị hệ thống, Organizer
> sở hữu sự kiện, và hai việc đó tách nhau có chủ đích. Tài khoản `admin` vừa bootstrap
> chỉ có Admin (+ Customer mặc định), nên chưa đứng tên concert nào được.
>
> Đây cũng là một **điểm đáng nói**: một người giữ được nhiều vai trò cùng lúc, và hệ
> thống phân quyền theo *vai trò* chứ không theo *cấp bậc* — Admin không tự động làm
> được mọi việc của Organizer.
>
> *Muốn trình diễn rõ sự tách vai hơn:* đăng ký thêm tài khoản `organizer` trên form
> đăng ký, cấp cho nó vai trò Organizer, rồi làm §4.3 bằng tài khoản đó. Có thể dùng
> trình duyệt hoặc máy khác: danh mục đọc từ database. Organizer chỉ thấy concert,
> hạng vé, khuyến mãi, mã giảm giá và hoàn tiền trong phạm vi mình sở hữu.

**Quản trị → Concert → Tạo concert mới**

1. Điền thông tin: **một hoặc nhiều nghệ sĩ** (chọn theo thứ tự hiển thị), địa điểm, tên,
   thời gian diễn, cửa sổ bán vé, giới hạn
   vé/khách (`PurchaseLimit` — để `4`).

   > **Đặt *Mở bán từ* ở một mốc trong QUÁ KHỨ** (ví dụ 5 phút trước). Để ở tương lai
   > thì concert chưa tới giờ bán, và toàn bộ phần mua vé ở §4.4 sẽ kẹt.

   Concert sinh ra ở trạng thái **Draft** và **không hiện ở trang chủ** — đúng như
   banner nói.
2. **Tạo hạng vé**: tên hạng, giá gốc (`BasePrice`) → Lưu. Hạng vé xuất hiện trong danh mục để chọn.
3. **Đưa ghế vào kho**: chọn concert + hạng vé, rồi bấm *Chọn tất cả* trong danh sách
   ghế của địa điểm đã chọn (hoặc gõ dải ID từ §4.1d). Đây là bước biến ghế của **địa điểm**
   thành vé bán được: ghế không có giá, giá chỉ xuất hiện khi ghế được đưa vào một
   concert cụ thể.
4. Thử **nhảy thẳng** từ `Draft` sang `OnSale` → hệ thống từ chối (**409**). Phải đi
   đúng `Draft` → `Published` → `OnSale`.
5. Ngay cả khi đi đúng thứ tự, `OnSale` vẫn bị chặn nếu concert **chưa có ghế nào trong
   kho vé** (58023) hoặc **chưa đặt cửa sổ bán** (58024) — đó là BR10, và là lý do bước
   3 không thể bỏ. Giao diện nói trước điều kiện còn thiếu thay vì để người dùng đâm
   vào tường.
6. Sau khi đủ điều kiện: `Draft` → `Published` → `OnSale`. Concert xuất hiện ở trang chủ
   với trạng thái *Đang mở bán*.

---

### 4.3b Khuyến mãi (2 phút) *(tuỳ chọn, nhưng §4.4 có dùng tới mã)*

**Quản trị → Khuyến mãi:**

1. **Chương trình** → chọn concert vừa tạo, tên "Giảm 200k", loại **Fixed**, giá trị
   `200000`, hiệu lực từ hôm qua đến vài ngày tới, **bật *Yêu cầu mã***.
2. **Mã giảm giá** → `DEMO200K`, giới hạn 2 lượt/khách.

**Điểm đáng nói:** tạo thêm **một chương trình thứ hai của cùng concert** rồi đặt cho nó
**cũng mã `DEMO200K`** → hệ thống từ chối (**409**). Ràng buộc
`UNIQUE(PromotionID, CodeValue)` chỉ bảo đảm mã duy nhất *trong một chương trình*; nếu
để hai chương trình của cùng một concert cùng đặt một mã thì lúc khách gõ mã đó,
**không ai xác định được họ định dùng ưu đãi nào**. Luật nằm ở `sp_CreateDiscountCode`
(58604), và hai đường vòng — bật lại một mã đã tắt (59614), bật lại một chương trình đã
tắt (59605) — cũng bị chặn bằng đúng lý do đó.

---

### 4.4 Luồng mua vé (4 phút)

Mở tab trình duyệt riêng (hoặc cửa sổ ẩn danh). **Đăng ký** tài khoản mới ngay trên giao diện → `Demo@12345`.

1. Trang chủ → vào concert vừa tạo → **sơ đồ ghế hai mức**:
   - **Mức 1**: toàn bộ khán phòng theo toạ độ thật — sân khấu là điểm tiêu cự, mỗi khu là khối có vị trí và góc xoay, kèm số chỗ còn và khoảng giá. Khách thấy chỗ mình sắp mua nằm ở đâu trong khán phòng.
   - **Mức 2**: chỉ tải khi bấm vào khu, rồi mới vẽ từng ghế theo hàng/cột.
   - Tại sao tách hai mức: mỗi ghế tốn ~234 byte; sân 20.000 chỗ sẽ là ~5 MB nếu trả hết một lần — đây là quyết định về *khả năng mở rộng*, không phải thẩm mỹ.

2. Chọn 2 ghế → **Giữ chỗ**. Chỉ ra:
   - Giới hạn số vé lấy từ `Concert.PurchaseLimit`, không phải hằng số cứng.
   - Đồng hồ **đếm ngược giữ chỗ** — đây là Temporary Hold có thời hạn (`TemporaryHoldDuration`).

3. Nhập mã khuyến mãi (nếu đã tạo ở bước trên) → tổng tiền giảm. **Điểm kỹ thuật:** chỉ vào ô nhập mã ngay lúc bấm Thanh toán — cả ô nhập lẫn nút *Áp dụng* đều **bị vô hiệu hoá** khi đơn đã có giao dịch chờ ở cổng. Giá đơn hàng bị khoá từ lúc khách bước vào cổng thanh toán. Muốn chứng minh lớp bảo vệ thật nằm ở database: gọi thẳng `POST /api/bookings/{id}/promotion` trong lúc đang chờ cổng → **409** (lỗi 54013 từ `sp_ApplyPromotion`). Tắt JavaScript cũng không lách được.

4. **Thanh toán** → trang *cổng thanh toán mô phỏng*.
   - Frontend **không** tự xác nhận thanh toán — nó chỉ khởi tạo giao dịch. Chữ ký HMAC là bí mật dùng chung giữa backend và cổng thanh toán, không bao giờ xuống trình duyệt. Bộ mô phỏng chạy trong backend: tự tính chữ ký rồi gọi vào cùng luồng xác nhận thật — toàn bộ mã kiểm tra chữ ký và kiểm tra số tiền vẫn được thực thi.
   - Nếu trả chữ ký về cho trình duyệt, khách có thể tự cấp vé mà không trả tiền — đây là lỗ hổng đã tồn tại trong bản trước và đã được gỡ.

5. Bấm **Thanh toán thành công** → Booking chuyển `Confirmed`, ghế chuyển `Booked`, vé được phát hành. Mã vé (GUID) hiển thị ngay trên trang Checkout kèm QR code.

---

### 4.5 Soát vé (2 phút)

Ba việc, đúng thứ tự:

1. **Đăng ký tài khoản nhân viên** trên chính form đăng ký của giao diện (ví dụ
   `staff` / `Demo@12345`). **Trang *Người dùng* không tạo được tài khoản** — nó chỉ
   cấp vai trò và phân công; mọi tài khoản đều sinh ra từ form đăng ký công khai, qua
   `sp_RegisterUser`.

2. Quay lại tab admin → **Quản trị → Người dùng → Cấp và thu hồi vai trò**: nhập
   **UserID** của nhân viên, vai trò **Check-in Staff**, hành động **Cấp**.

   > **Lấy UserID ở đâu:** API quản trị chưa có đường đọc danh sách người dùng (xem
   > §6), nên ô này nhận số hiệu chứ không nhận tên đăng nhập. Trên database trống,
   > `UserID` chạy tuần tự: `system` = 1, `admin` = 2, rồi lần lượt theo thứ tự đăng
   > ký. Không chắc thì tra:
   > ```powershell
   > sqlcmd -S .\SQLEXPRESS -E -d ConcertTicketingDB -I -h -1 -W -Q `
   >   "SELECT UserID, Username FROM UserAccount ORDER BY UserID;"
   > ```

3. **Quản trị → Người dùng → Phân công nhân viên soát vé**: nhân viên đó + concert vừa
   tạo, trạng thái *Active* (`sp_AddCheckinStaffAssignment`).

   > **Đừng bỏ bước này.** Không có phân công thì `sp_CheckInTicket` trả `UNAUTHORIZED`
   > (BR39) — vé hợp lệ nhưng nhân viên không có quyền ở cổng này. Bỏ qua ở đây thì cả
   > phần soát vé hỏng ngay trước mặt hội đồng.

Đăng nhập bằng tài khoản nhân viên → **Soát vé** → chọn concert → nhập mã vé (copy từ
trang Checkout của khách). Bấm *Xem trước* để thấy vé thuộc về ai mà **không** ghi nhận
lượt vào, rồi mới soát thật:

- `SUCCESS` — vé hợp lệ, lần đầu soát.
- Quét lại đúng mã → `ALREADY_USED`. Vé chỉ dùng một lần.
- Đăng nhập tài khoản customer → thử truy cập trang Soát vé → không có lối vào. Gọi thẳng `POST /api/checkin` → **403**. Phân quyền thi hành ở backend và trong stored procedure — giao diện chỉ phản ánh lại.

---

### 4.5b Báo cáo và nhật ký kiểm toán (2 phút)

**Quản trị → Báo cáo** → chọn concert. Ba khối, đúng ba khối mà box-office của
Eventbrite/Ticketmaster có:

| Khối | Nội dung |
|---|---|
| Doanh thu & tồn kho | tổng ghế, còn trống, đang giữ, đã bán, doanh thu, số đơn theo trạng thái |
| Tỷ lệ vào cổng | vé đã phát hành, đã soát, còn chờ, tỷ lệ % |
| Người giữ vé | từng ghế · hạng vé · khách · trạng thái vé |

**Điểm đáng nói — hai thứ bảng này KHÔNG có:**

- **Không có mã vé.** Ai đọc được báo cáo cũng đọc được mã vé thì báo cáo trở thành
  kênh rò rỉ thứ hai cho đúng loại bearer-credential ở §4.4. Mã quét chỉ đi qua thiết
  bị check-in tại cổng.
- **Không có tham số "xem báo cáo của ai".** Cả ba khối đọc qua view tự lọc bằng
  `SESSION_CONTEXT(N'UserID')`: Organizer chỉ thấy concert của chính mình, Admin thấy
  tất cả, phiên không danh tính thấy **0 dòng**. Phạm vi dữ liệu do database quyết
  định, không do tham số người gọi truyền lên.

**Quản trị → Nhật ký** *(chỉ Admin)* → tra theo loại thực thể / khoảng thời gian. Toàn
bộ những gì vừa làm trong buổi demo đều nằm ở đây, kèm đúng tác nhân đã thực hiện.

**Điểm đáng nói:** bảng `AuditRecord` được `TRG_AuditRecord_SecurityGuard` canh giữ —
**không ai sửa hay xoá được một dòng nhật ký nào**, kể cả `app_admin` (BR50).

---

### 4.6 Chiều sâu kỹ thuật (2 phút)

16. **Kiến trúc Thick Database**: mở `database/StoredProcedures/sp_CreateBooking.sql`, chỉ vào `UPDATE … WHERE InventoryStatus = 'Available'` + `@@ROWCOUNT` — chống bán trùng ghế bằng chính database, không phải khoá ở tầng ứng dụng.

17. **Phân quyền ở tầng dữ liệu**: `api_service` bị `DENY INSERT/UPDATE/DELETE` trực tiếp trên các bảng lõi — mọi thao tác ghi buộc phải qua stored procedure. Khai thác được API cũng không ghi thẳng vào bảng.

18. **Row-Level Security**: `VW_CustomerBookingHistory` lọc theo `SESSION_CONTEXT(N'UserID')`, nên trang "Vé của tôi" không hề gửi `userId` nào lên — database tự giới hạn kết quả trả về đúng chủ sở hữu.

19. **Hai đường vào database, cố ý**: ứng dụng web luôn kết nối bằng `api_service`; các login theo vai trò (`app_admin`, `app_organizer`, `app_customer`, `app_checkinstaff`) phục vụ đường truy cập trực tiếp vào database. Các view `VW_Organizer*` tồn tại cho đường thứ hai đó (BR37/FR48/BO9/FR15) — chứng minh được: `app_organizer` bị `DENY` trên bảng `Booking` (lỗi 229) nhưng đọc qua view thì đúng, và chỉ thấy concert của chính mình.

20. **Danh mục quản trị từ database**: Zone, Seat, hạng vé, khuyến mãi, mã giảm giá, hoàn tiền và concert (kể cả Draft) có API GET. UI tải đủ các trang và cập nhật sau thao tác ghi; đổi tài khoản sẽ xóa cache cũ. SQL lọc dữ liệu theo quyền sở hữu concert, còn địa điểm/khu/ghế là danh mục dùng chung. Xem [API và kiểm thử](docs/admin-catalog.md). Trang cấp vai trò vẫn nhập UserID.

---

### 4.7 Trình diễn 5 hiện tượng tranh chấp đồng thời (~5 phút)

Script tự dựng dữ liệu riêng (tiền tố `DEMO-CC`) — **không đụng vào bất kỳ dữ liệu nào vừa tạo ở trên**, chạy được ở bất kỳ thời điểm nào trong buổi:

```powershell
cd T:\coding\concert_ticketing_system

.\scripts\demo-concurrency.ps1                       # chạy cả 5 hiện tượng
.\scripts\demo-concurrency.ps1 -Scenario lost-update # hoặc chạy riêng từng cái
# Các giá trị: lost-update | dirty-read | non-repeatable | phantom | deadlock
```

Mỗi hiện tượng diễn **hai vế** — chỉ một vế thì không chứng minh được gì.  
Cửa sổ tranh chấp được nới rộng bằng `WAITFOR` nên kết quả **tái hiện được mọi lần**, không phụ thuộc may rủi về thời điểm.

---

#### Hiện tượng 1 — Lost Update (bán vượt ghế)

**Bối cảnh người dùng:** Khách A và khách B cùng bấm "Giữ chỗ" ghế A01 đúng một lúc.

**Vế 1 — Lỗi CÓ THẬT** (đọc trạng thái rồi mới ghi — cách ngây thơ):
```
[Người dùng thấy]  A: he thong bao ghe dang [Available] -> cho phep A giu cho
[Người dùng thấy]  B: he thong bao ghe dang [Available] -> cho phep B giu cho
[Người dùng thấy]  A: da giu cho THANH CONG
[Người dùng thấy]  B: da giu cho THANH CONG
>>> CẢ HAI khách đều tin mình đã giữ được ghế A01. Một ghế bán cho hai người.
```

**Vế 2 — Hệ thống CHẶN được** (`sp_CreateBooking`: cập nhật có điều kiện + `@@ROWCOUNT`):
```
[Người dùng thấy]  Khach A: Giu cho thanh cong, ma don BKG-1
[Người dùng thấy]  Khach B: sp_CreateBooking: Ghe ... da duoc dat boi nguoi khac.
>>> Đúng MỘT khách giữ được ghế; người kia bị từ chối ngay. Số đơn đang giữ ghế A01 = 1
```

**Cơ chế:** `UPDATE EventSeat SET InventoryStatus='OnHold' WHERE EventSeatID=? AND InventoryStatus='Available'` — cập nhật có điều kiện. Kiểm tra `@@ROWCOUNT = 0` → biết ngay ghế đã bị lấy mất. Không có khóa ứng dụng, không có check-then-act — một câu lệnh atomique.

---

#### Hiện tượng 2 — Dirty Read (nhìn thấy thứ chưa hề xảy ra)

**Bối cảnh người dùng:** Khách A bấm giữ chỗ nhưng thanh toán thất bại → giao dịch bị hủy. Đúng lúc đó khách B mở sơ đồ ghế.

**Hai kết quả song song trên màn hình:**
```
[Người dùng thấy]  A: dang giu cho (CHUA xac nhan)
[Người dùng thấy]  B [neu he thong dung NOLOCK]: so do bao ghe dang [OnHold]
[Người dùng thấy]  B [he thong that - READ COMMITTED]: so do bao ghe dang [Available]
[Người dùng thấy]  A: giao dich BI HUY -> thuc te ghe VAN CON TRONG
>>> Với NOLOCK: khách B bị báo ghế đã có người giữ, nên bỏ đi — trong khi ghế thật sự vẫn trống.
>>> Hệ thống thật: khách B phải chờ tới khi A dứt khoát, rồi thấy đúng trạng thái [Available].
```

**Cơ chế:** READ COMMITTED (mức cách ly mặc định của SQL Server) — chỉ đọc dữ liệu đã được `COMMIT`. Khách B thấy `OnHold` của A là dữ liệu *dirty* — chưa `COMMIT`, có thể `ROLLBACK` bất kỳ lúc nào. Hệ thống **không dùng `NOLOCK`** ở bất kỳ đâu trong luồng nghiệp vụ.

---

#### Hiện tượng 3 — Non-repeatable Read (đọc hai lần ra hai kết quả)

**Bối cảnh người dùng:** Trong MỘT lượt xử lý, hệ thống đọc trạng thái ghế hai lần — lần đầu để kiểm tra, lần sau để ghi nhận. Giữa hai lần đó có người khác chen vào.

**Vế 1 — Lỗi CÓ THẬT** (đọc trần, không đặt khoá):
```
[Người dùng thấy]  Nguoi khac vua giu mat ghe do va da xac nhan xong
[Người dùng thấy]  Lan doc 1: ghe dang [Available]
[Người dùng thấy]  Lan doc 2: ghe dang [OnHold]
[Người dùng thấy]  >>> HAI LAN DOC KHAC NHAU
>>> Dữ liệu đổi ngay giữa lượt xử lý: quyết định dựa trên lần đọc 1 đã sai.
```

**Vế 2 — Hệ thống CHẶN được** (`WITH (UPDLOCK)`, như `sp_CreateBooking` / `sp_CheckInTicket`):
```
[Người dùng thấy]  Lan doc 1: ghe dang [Available]
[Người dùng thấy]  Lan doc 2: ghe dang [Available]
[Người dùng thấy]  >>> Hai lan doc GIONG NHAU
[Người dùng thấy]  Nguoi khac vua giu mat ghe do va da xac nhan xong   ← chạy SAU khi lượt xử lý xong
>>> Người khác bị giữ lại tới khi lượt xử lý xong; hai lần đọc giống hệt nhau.
```

**Cơ chế:** `SELECT ... FROM EventSeat WITH (UPDLOCK)` — khoá cập nhật ngay lúc đọc, ngăn ghi đồng thời trong suốt transaction. Hệ thống dùng `UPDLOCK` ở 30/44 stored procedure để đổi lấy tính nhất quán mà không phải nâng mức cô lập toàn cục.

---

#### Hiện tượng 4 — Phantom Read (đếm lại thì tự nhiên mọc thêm người)

**Bối cảnh người dùng:** Hệ thống đếm số người trong hàng đợi để cấp suất vào mua. Giữa hai lần đếm, có người mới xếp hàng.

**Vế 1 — Lỗi CÓ THẬT** (đếm trần, không đặt khoá phạm vi):
```
[Người dùng thấy]  Mot khach vua xep hang xong
[Người dùng thấy]  Dem lan 1: hang doi co 0 nguoi
[Người dùng thấy]  Dem lan 2: hang doi co 1 nguoi
[Người dùng thấy]  >>> XUAT HIEN NGUOI MOI giua hai lan dem
>>> Suất vào mua có thể bị cấp vượt, vì con số dùng để quyết định đã cũ.
```

**Vế 2 — Hệ thống CHẶN được** (`WITH (UPDLOCK, HOLDLOCK)`, như `sp_JoinQueue` / `sp_JoinWaitlist`):
```
[Người dùng thấy]  Dem lan 1: hang doi co 0 nguoi
[Người dùng thấy]  Dem lan 2: hang doi co 0 nguoi
[Người dùng thấy]  >>> Hai lan dem GIONG NHAU
[Người dùng thấy]  Mot khach vua xep hang xong   ← chạy SAU khi lượt xử lý xong
>>> Khoá phạm vi giữ cả khoảng trống, người mới phải chờ; hai lần đếm bằng nhau.
```

**Cơ chế:** `HOLDLOCK` (tương đương `SERIALIZABLE` cục bộ) — giữ khoá phạm vi trong suốt transaction, không cho INSERT mới vào khoảng đã đếm. Kết hợp với `UPDLOCK` để tránh deadlock giữa hai phiên cùng đếm.

---

#### Hiện tượng 5 — Deadlock (hai giao dịch chờ khoá của nhau)

**Bối cảnh người dùng:** Hai khách cùng lúc giữ hai ghế theo thứ tự ngược nhau — A giữ A01 trước rồi xin A02; B giữ A02 trước rồi xin A01.

**Vế 1 — Deadlock CÓ THẬT** (giao dịch thủ công, thứ tự khoá ngược nhau):
```
[Người dùng thấy]  A: da khoa ghe A01, dang xin them ghe A02...
[Người dùng thấy]  B: da khoa ghe A02, dang xin them ghe A01...
[Người dùng thấy]  A: bi huy - loi 1205
[Người dùng thấy]  B: hoan tat
>>> SQL Server phát hiện vòng chờ, chọn một bên làm nạn nhân (lỗi 1205) và hủy giao dịch đó.
    Bên còn lại đi tiếp bình thường; bên bị hủy được rollback trọn vẹn, không mất dữ liệu.
```

**Vế 2 — Hệ thống KHÔNG deadlock** (hai khách chọn ghế theo thứ tự NGƯỢC, nhưng gọi `sp_CreateBooking`):
```
[Người dùng thấy]  Khach A (chon A01 roi A02): dat thanh cong
[Người dùng thấy]  Khach B (chon A02 roi A01): sp_CreateBooking: Ghe da duoc dat...
>>> KHÔNG deadlock. sp_CreateBooking giữ ghế bằng MỘT câu lệnh tập hợp duy nhất,
    nên SQL Server luôn khoá theo thứ tự chỉ mục, không theo thứ tự khách chọn.
    Hai giao dịch xin khoá cùng chiều thì không thể tạo thành vòng chờ.
```

**Cơ chế:** `UPDATE EventSeat SET InventoryStatus='OnHold' WHERE EventSeatID IN (...)` — một câu lệnh tập hợp duy nhất trên toàn bộ danh sách ghế. SQL Server tự quyết định thứ tự khoá theo chỉ mục, bất kể khách chọn ghế theo thứ tự nào. Đây là tính chất thiết kế, không phải may mắn.

---

**Nói thẳng nếu hội đồng hỏi:** hệ thống **không** nâng mức cô lập toàn cục lên REPEATABLE READ / SERIALIZABLE. Hiện tượng 3 và 4 **vẫn xảy ra được** ở các truy vấn đọc trần không đặt khoá — đó là hành vi đúng của READ COMMITTED. Hệ thống chọn đặt khoá đúng điểm nóng (`UPDLOCK` ở 30/44 thủ tục, `HOLDLOCK` ở các chỗ đếm phạm vi, thêm `sp_getapplock` ở 4 thủ tục nặng) để đổi lấy thông lượng, thay vì khoá toàn cục.

---

## 4b. Chạy hai máy để tranh chấp thật (tuỳ chọn — hotspot điện thoại)

Kịch bản `demo-concurrency.ps1` ở §4.7 chứng minh cơ chế ở **tầng database** (hai tiến
trình `sqlcmd` song song). Nếu muốn hội đồng thấy **hai người thật bấm trên hai máy**,
dựng như sau. Toàn bộ đã được chạy thử end-to-end, kể cả màn giành ghế.

**Mạng:** phát hotspot từ điện thoại, cả hai laptop nối vào đó. Không dùng WiFi trường —
mạng tổ chức thường bật *client isolation*, khiến hai máy không thấy nhau.

> **Chỉ frontend cần mở ra mạng, backend thì không.** Vite nhận `/api` trên cổng 5173
> rồi chuyển tiếp sang backend **từ chính máy chủ**, nên backend vẫn nghe `localhost`
> như bình thường. Hệ quả: chỉ mở đúng **một** cổng, không còn vướng CORS (trình duyệt
> thấy cùng origin) lẫn `AllowedHosts` (proxy đặt lại `Host` thành `localhost:5295`).

### Chuẩn bị một lần trên laptop-server

```powershell
# PowerShell chay quyen Administrator
New-NetFirewallRule -DisplayName "ConcertTicketing Frontend LAN" -Direction Inbound -Protocol TCP -LocalPort 5173 -Action Allow -Profile Private
```

Khi Windows hỏi mạng hotspot là loại gì → chọn **Private**. Kiểm tra bằng
`Get-NetConnectionProfile`; nếu ra `Public` thì
`Set-NetConnectionProfile -InterfaceAlias "Wi-Fi" -NetworkCategory Private`
(cũng cần quyền Administrator).

### Mỗi lần chạy

```powershell
# 1. Lay IP cua laptop-server TRONG mang hotspot (doi moi lan noi lai)
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^127\.|^169\.254\.' } | Select IPAddress, InterfaceAlias

# 2. Deploy + build. CHI truyen -FrontendUrl; -ApiUrl giu mac dinh localhost.
.\scripts\setup-demo.ps1 -FrontendUrl "http://<IP>:5173"

# 3. Cua so [1] - backend, chay binh thuong (chi nghe localhost)
cd backend\src\ConcertTicketing.API
dotnet run

# 4. Cua so [2] - frontend, PHAI la dev:lan
cd frontend
npm run dev:lan

# 5. Cua so [3] - bootstrap admin
.\scripts\bootstrap-admin.ps1
```

**Cả hai máy** (kể cả laptop-server) mở `http://<IP>:5173`.

> **Chỗ duy nhất bắt buộc đổi so với chạy một máy:** `npm run dev:lan` thay cho
> `npm run dev`, vì lệnh mặc định chỉ lắng nghe `127.0.0.1`. Backend giữ nguyên
> `dotnet run`. `setup-demo.ps1` tự in lại lưu ý này khi thấy `-FrontendUrl` không phải
> localhost.

### Kiểm tra trước khi vào phòng — từ laptop teammate

```powershell
Test-NetConnection -ComputerName <IP> -Port 5173
```

`TcpTestSucceeded : True` là đủ — cổng 5295 **không** cần và **không nên** mở.

### Diễn màn tranh chấp

Hai người đăng nhập hai tài khoản khách khác nhau, cùng mở sơ đồ ghế của một concert,
cùng chọn **đúng một ghế**, rồi đếm 1-2-3 cùng bấm **Giữ chỗ**. Một người vào được
trang thanh toán; người kia nhận thông báo *"ghế đã được người khác đặt"* (HTTP 409 từ
`sp_CreateBooking`).

> **Nói thẳng điểm khác biệt:** cách này thuyết phục về mặt thị giác nhưng **không tái
> hiện được 100%** — nếu hai người bấm lệch nhau vài trăm mili-giây thì người sau chỉ
> đơn giản thấy ghế đã bị chiếm, không còn là tranh chấp đồng thời thật. Script ở §4.7
> mới là thứ chứng minh chặt chẽ, vì nó nới cửa sổ tranh chấp bằng `WAITFOR`. Dùng cả
> hai: máy đôi để hội đồng *thấy*, script để *chứng minh*.

---

## 5. Lệnh chạy kiểm thử

```powershell
# Database — 226 test (chạy TỪ thư mục Tests)
cd database\Tests
.\Run-All-Tests.ps1

# Backend — 222 unit + 79 integration
cd backend
dotnet test
```

> ⚠️ **`Run-All-Tests.ps1` xoá toàn bộ dữ liệu nghiệp vụ trước khi chạy.**
> `01_SetupMockData.sql` `DELETE` 24 bảng (giữ lại mỗi tài khoản `system`) để mỗi lần
> chạy đều bắt đầu từ trạng thái đã biết. Sau khi chạy test SQL, phải bootstrap lại:
>
> ```powershell
> .\scripts\bootstrap-admin.ps1
> ```
>
> `dotnet test` thì **không** xoá gì: test tích hợp tự tạo dữ liệu riêng.
>
> Bộ test SQL **để lại** dữ liệu mock của nó — sau khi chạy, trang chủ sẽ có thêm
> sự kiện `Test Concert Live 2025`. Muốn sạch hoàn toàn: deploy lại bằng `database\deploy.ps1`.

---

## 6. Giới hạn đã biết — nên chủ động trình bày

Nêu trước sẽ tốt hơn để hội đồng hỏi:

1. **Chưa tích hợp cổng thanh toán thật.** Demo dùng bộ mô phỏng chạy phía máy chủ.
   `Program.cs` **từ chối khởi động** nếu bật chế độ mô phỏng ở môi trường Production.
2. **Chưa kiểm thử tải và chưa phân tích deadlock đầy đủ.** Test đồng thời hiện chỉ vài kết
   nối. Với hệ bán vé, đây là rủi ro lớn nhất còn lại.
3. **Deploy hiện là deploy sạch.** `deploy.ps1` tạo lược đồ từ các file nguồn; dự án không giữ script migration tăng dần.
4. **Một instance, không HA/backup** — phạm vi đã chốt tại §23.7 của đặc tả.
5. **Múi giờ**: mọi mốc thời gian dùng `SYSDATETIME()` (giờ máy chủ). Đúng khi trình
   duyệt và SQL Server cùng múi giờ; phục vụ đa múi giờ thì phải chuyển database sang UTC.
6. **Chưa kiểm chứng ở quy mô nhiều instance.** Toàn bộ khoá đồng thời (`sp_getapplock`,
   `UPDLOCK`/`READPAST`) nằm trong SQL Server nên đúng khi chạy nhiều instance API,
   nhưng điều đó chưa được kiểm chứng bằng thực nghiệm.
7. **Chưa có màn hình "vé của tôi" đúng nghĩa.** Mã vé và QR hiện ở trang đơn hàng
   (`/checkout/{id}`), và khách mở lại được bất cứ lúc nào từ **Vé của tôi** — nên vé
   không bị mất sau khi rời trang. Thứ còn thiếu là một màn hình vé riêng (ví
   `GET /bookings/{id}/tickets`) với vé rời từng ghế, tải về được. Luồng soát vé phía
   nhân viên thì đã hoàn chỉnh.
8. **API quản trị thiếu đường đọc**, rõ nhất là danh sách người dùng. Hệ quả trực tiếp
   thấy ngay trong chính tài liệu này: §4.5 phải làm việc với UserID thay vì tên đăng
   nhập, và khu quản trị phải tự nhớ ID trong `localStorage` (§4.6 mục 19).

---

## 7. Bản đồ thư mục

```
database/     29 bảng, 33 trigger, 3 function, 44 SP, 17 view, RBAC, 226 test
backend/      .NET 9 · Clean Architecture · Dapper · JWT · 301 test
frontend/     React 19 · Vite · React Router · khu quản trị 8 mục (Admin) / 6 (Organizer)
scripts/      setup-demo.ps1  · bootstrap-admin.ps1  · demo-concurrency.ps1
              seed-demo.ps1   (tùy chọn — nạp nhanh dữ liệu sẵn, không dùng trong luồng bảo vệ chính)
docs/         database_plan.txt — đặc tả gốc, nguồn tham chiếu của toàn hệ thống
.deploy/      bí mật sinh ra lúc triển khai (KHÔNG commit)
```
