# Hướng dẫn sử dụng — vai trò Admin

Tài liệu này mô tả **toàn bộ** những gì một tài khoản Admin làm được, theo đúng
hành vi đang có trong source: từng trang, từng trường, từng ràng buộc, và từng
thông báo lỗi sẽ gặp. Mọi giá trị trạng thái dưới đây được đọc trực tiếp từ
`sys.check_constraints` của database và từ `frontend/src/domain/enums.js` —
không chép từ tài liệu thiết kế.

Vai trò Admin khác Organizer ở chỗ: Admin quản trị **hạ tầng dùng chung**
(địa điểm, khu, ghế, mẫu sơ đồ, người dùng, audit) và **xem được mọi concert**;
Organizer chỉ vận hành concert mình sở hữu.

---

## 1. Phạm vi vai trò

### 1.1. Menu quản trị (`/admin`)

| Mục | Đường dẫn | Ai thấy | Nội dung |
|---|---|---|---|
| Concert | `/admin/concerts` | Admin + Organizer | Vòng đời concert, hạng vé, kho ghế, sơ đồ, hàng đợi, waitlist, khoá ghế |
| Danh mục | `/admin/catalog` | Admin + Organizer | Nghệ sĩ, địa điểm, khu vực, ghế |
| **Mẫu sơ đồ** | `/admin/venue-templates` | **Chỉ Admin** | StagePass Studio — dựng floor plan nhiều tầng |
| Khuyến mãi | `/admin/promotions` | Admin + Organizer | Chương trình giảm giá và mã giảm giá |
| Hoàn tiền | `/admin/refunds` | Admin + Organizer | Huỷ đơn, xác nhận hoàn tiền |
| Báo cáo | `/admin/reports` | Admin + Organizer | Doanh thu, tồn kho, check-in, người giữ vé, danh sách chờ |
| **Nhật ký** | `/admin/audit` | **Chỉ Admin** | Tra cứu lịch sử thay đổi |
| **Người dùng** | `/admin/users` | Admin (đầy đủ) / Organizer (chỉ phân công soát vé) | Vai trò, khoá tài khoản, phân công soát vé |

> Ẩn một mục trên menu **chỉ là trải nghiệm**, không phải bảo mật. Quyết định thật
> nằm ở `[Authorize]` của backend **và** ở kiểm tra `@ActorUserID` bên trong từng
> stored procedure. Ví dụ: mục "Người dùng" gọi `sp_AssignRole`, và procedure đó
> tự chặn bằng lỗi `58401` nếu người gọi không phải Admin — kể cả khi thuộc tính
> `[Authorize]` ở controller có rộng hơn.

### 1.2. Chỉ Admin làm được

- Tạo / sửa **Nghệ sĩ** (`sp_CreateArtist`, `sp_UpdateArtist`)
- Tạo / sửa **Địa điểm** (`sp_CreateVenue`, `sp_UpdateVenue`)
- Sửa **Khu**, sửa **Ghế**, tạo **ghế hàng loạt**
- Toàn bộ **StagePass Studio**: template, version, floor, object, section, seat,
  publish, xoá draft
- **Gán / thu hồi vai trò** (`sp_AssignRole`) và **bật/tắt vai trò** (`sp_UpdateRoleStatus`)
- **Khoá / mở tài khoản** người dùng (`sp_AdminUpdateUserStatus`)
- **Tra cứu nhật ký kiểm toán** (`/admin/audit`)

### 1.3. Admin và Organizer cùng làm được

Tạo/sửa concert, chuyển trạng thái concert, hạng vé, thêm ghế vào kho vé, tạo
concert map + revision (Admin làm được cho **mọi** concert), khoá/mở ghế, khuyến
mãi, mã giảm giá, hàng đợi, danh sách chờ, báo cáo, phân công nhân viên soát vé,
tạo zone/seat đơn lẻ (hai thao tác này controller mở cho cả hai, nhưng
`sp_CreateZone` và `sp_CreateSeat` vẫn kiểm quyền ở tầng database).

---

## 2. Bắt đầu

### 2.1. Tạo tài khoản Admin đầu tiên

Database sau khi deploy **trống hoàn toàn**: chỉ có 4 Role, tài khoản `system`
(không đăng nhập được) và 4 khoá cấu hình. Chưa có Admin nào.

```powershell
# Bước 1 — deploy database trống + sinh cấu hình + build
.\scripts\setup.ps1

# Bước 2 — chạy hai tiến trình (hai cửa sổ terminal)
cd backend\src\ConcertTicketing.API ; dotnet run
cd frontend ; npm run dev

# Bước 3 — tạo Admin đầu tiên (API phải đang chạy)
.\scripts\bootstrap-admin.ps1
```

`bootstrap-admin.ps1` sẽ **hỏi email** và **hỏi mật khẩu** (nhập ẩn). Không có
giá trị mặc định: mật khẩu mặc định nghĩa là mọi bản sao repository dùng chung một
mật khẩu cho tài khoản quyền cao nhất; còn email bịa sẽ tồn tại vĩnh viễn trong
`UserAccount` vì **hệ thống không có đường sửa email**.

Ràng buộc mật khẩu (khớp `RegisterValidator`, script kiểm tra ngay tại chỗ):
≥ 8 ký tự, có ít nhất 1 chữ hoa, có ít nhất 1 chữ số.

Script **không ghi và không in mật khẩu**; `.deploy/bootstrap-info.json` chỉ lưu
username, email, UserID và thời điểm.

### 2.2. Đăng nhập

Vào `http://localhost:5173/login`, đăng nhập bằng tài khoản vừa tạo. Sau khi đăng
nhập, menu **Quản trị** xuất hiện trên thanh điều hướng.

---

## 3. Danh mục hạ tầng — `/admin/catalog`

Trang có 4 khối: **Nghệ sĩ**, **Địa điểm**, **Khu vực**, **Ghế**.

### Đọc trước — cùng một cái ghế, ba nghĩa khác nhau

Mục 3 và mục 4 **trông như làm trùng một việc**: cả hai đều khai báo khu và ghế.
Thực ra chúng trả lời **hai câu hỏi hoàn toàn khác nhau**:

| Câu hỏi | Trả lời ở | Kết quả nhận được |
|---|---|---|
| Nhà hát X **CÓ** những ghế nào? | **Mục 3.3 / 3.4** | Một **danh sách tên**: `A1`, `A2`, … `A200` |
| Nhà hát X **TRÔNG** như thế nào? | **Mục 4** | Một **hình vẽ** để khách bấm vào từng ghế |

Danh sách tên ghế không nói được ghế nằm ở đâu. Hình vẽ không tự biết cái ghế nào
tồn tại. Phải có **cả hai**, và vì vậy dữ liệu chia thành **ba lớp**:

| Lớp | Bảng thật trong DB | Tạo ở | Nghĩa | Ví dụ |
|---|---|---|---|---|
| 1 · Ghế **vật lý** | `Seat` (thuộc `Zone`) | mục 3.3 / 3.4 | Cái ghế có thật, đã gắn số. Tồn tại vĩnh viễn, kể cả khi chưa có show nào | "Khu VIP của Nhà hát X **có** một ghế tên `A1`" |
| 2 · Ghế **trên bản vẽ** | `TemplateSeat` (thuộc `TemplateSection`) | mục 4, bước 7 | Vị trí của ghế `A1` **trên một mặt bằng cụ thể** | "Trong bản vẽ *Sân khấu cuối*, `A1` ở hàng 1 số 1, toạ độ (x, y)" |
| 3 · Ghế **để bán** | `EventSeat` | mục 6.4 / 7 | Hàng bán cho **một show**: giá, còn hay hết | "Show 20/12: `A1`, hạng VIP, 1.000.000₫, còn trống" |

"Khu" cũng có hai nghĩa: `Zone` = **khu vật lý** (khu VIP gồm 200 ghế);
`TemplateSection` = **hình của khu đó trên bản vẽ** (chữ nhật hay đa giác, xoay bao
nhiêu độ, nằm ở đâu trên tầng).

#### Cách nhớ: danh sách học sinh ≠ sơ đồ chỗ ngồi

Lớp học có **30 học sinh** — danh sách tên cố định, năm nào cũng vậy. Nhưng mỗi kỳ
thi giáo viên lại xếp **một sơ đồ chỗ ngồi khác**. Học sinh vẫn là những người đó,
chỗ ngồi thì đổi. Và chính **kỳ thi** mới là thứ có lệ phí.

Ánh xạ thẳng sang hệ thống:

| Trong lớp học | Trong hệ thống | Tạo ở |
|---|---|---|
| Danh sách 30 học sinh | `Seat` — tạo một lần, dùng mãi | mục 3.4 |
| Sơ đồ chỗ ngồi của kỳ thi tháng 6 | `TemplateSeat` — hình học thuộc về **sơ đồ**, không thuộc về học sinh | mục 4 |
| Kỳ thi tháng 6 (có lệ phí) | `EventSeat` — một concert cụ thể | mục 7 |

#### Vì sao không gộp hai lớp làm một

**Vì hình học thuộc về BẢN VẼ, không thuộc về cái ghế.** Vẫn ghế `A1`, vẫn khu VIP:

- bản vẽ *"Sân khấu cuối"* đặt khu VIP thành hình chữ nhật giữa nhà;
- bản vẽ *"Sân khấu trung tâm"* đặt nó thành vành khuyên bao quanh — `A1` nằm ở
  chỗ hoàn toàn khác.

Nếu toạ độ nằm trên `Seat`/`Zone` thì chỉ vẽ được **một** cách bố trí, và mỗi lần
đổi bố trí phải tạo lại toàn bộ ghế — **đứt liên kết với vé đã bán**. Đó chính là
lý do các cột `ZoneX/ZoneY/ZoneWidth/ZoneHeight/ZoneRotation/ZoneLevel` của `Zone`
cùng `sp_ConfigureVenueMap` **tồn tại mà không có đường ghi nào từ ứng dụng**: dấu
vết của thiết kế cũ, đã bị `TemplateSection` thay thế.

#### Vì sao ở mục 4 phải "gắn ghế" lần thứ hai

`TemplateSeat` **buộc trỏ tới một `Seat` có thật** (`@SeatID`), không tự sinh ghế
mới. Nếu mỗi bản vẽ tự đặt tên ghế riêng thì không ai đối chiếu được "ghế A1" giữa
**sơ đồ** → **kho vé** → **vé đã phát hành**. Vì vậy bước 7 **không phải** "tạo
ghế", mà là **"đặt ghế `A1` vào một chỗ trên bản vẽ này"**.

#### Mục 3.4 một mình KHÔNG bán được vé

Đây là điều quan trọng nhất của cả tài liệu. Mục 4 **là bắt buộc để bán vé
online**, không phải trang trí:

- `GetSeatMapAsync` trả về **`null`** khi concert chưa có revision `Locked`, và
  **cố ý không có đường dự phòng** đọc từ `Zone`/`Seat` cũ.
- Giao diện khách **chỉ cho chọn ghế qua sơ đồ**: trang concert gọi
  `<SeatMap onToggleSeat={…}>`; danh sách ghế phẳng chỉ dùng để đếm và tính tiền,
  **không bấm chọn được**.

⇒ Chưa có revision `Locked` ⇒ khách thấy *"Sơ đồ ghế đang được hoàn thiện"* và
**không chọn được ghế nào** ⇒ **không ai mua được**, dù kho vé đầy ghế.

### 3.1. Nghệ sĩ

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Tên nghệ sĩ | ✔ | Tối đa 255 ký tự |
| Mô tả | | Tối đa 500 ký tự |
| Trạng thái (khi sửa) | | `Active` (Đang hoạt động) hoặc `Retired` (Đã ngừng) |

Nghệ sĩ `Retired` **không dùng được cho concert mới** (`58004` nghệ sĩ không tồn
tại / `58025` danh sách nghệ sĩ không hợp lệ).

> **Ô "Mô tả" khi sửa là trường một chiều:** bỏ trống nghĩa là *giữ nguyên* giá trị cũ
> (`COALESCE` trong `sp_UpdateArtist`), nên từ giao diện **không xoá trắng** được mô tả
> — chỉ thay được bằng nội dung mới.

> **Tên nghệ sĩ có thể trùng một cách hợp lệ** — database cố ý **không** đặt `UNIQUE`
> trên `ArtistName`, vì hai nghệ sĩ khác nhau có thể trùng tên và `UNIQUE` không chặn
> được biến thể dấu/khoảng trắng. Khi bạn gõ một tên đã có, giao diện **cảnh báo** và
> liệt kê bản ghi trùng, nhưng **vẫn cho tạo**. Hãy kiểm tra trước: hai bản ghi cho cùng
> một nghệ sĩ sẽ làm báo cáo theo nghệ sĩ tách thành nhiều dòng.

### 3.2. Địa điểm (Venue)

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Tên địa điểm | ✔ | Tối đa 255 ký tự |
| Địa chỉ | | Tối đa 500 ký tự |
| Trạng thái (khi sửa) | | `Active` hoặc `Inactive` |

Tên địa điểm **được cắt khoảng trắng** đầu/cuối khi lưu (cả lúc tạo và lúc sửa), nên
`"  Nhà hát A  "` và `"Nhà hát A"` là **một** địa điểm, không phải hai.

Địa điểm `Inactive` **không tạo được concert mới** (`58009`) và **không tạo được
mẫu sơ đồ mới** (`60097`). Chiều ngược lại cũng bị chặn: **không ngưng sử dụng được**
địa điểm đang có concert chưa kết thúc (`59405`) — nếu không, concert đó sẽ trỏ tới
một địa điểm đã ngừng hoạt động cho tới ngày diễn.

> **Ô "Địa chỉ mới" khi sửa là trường một chiều:** bỏ trống nghĩa là *giữ nguyên* địa
> chỉ cũ (`COALESCE` trong `sp_UpdateVenue`), nên từ giao diện **không xoá trắng** được
> địa chỉ — chỉ thay được bằng nội dung mới. Cùng quy ước với ô "Mô tả" của nghệ sĩ.

> **Tên địa điểm có thể trùng một cách hợp lệ** — database **không** đặt `UNIQUE` trên
> `VenueName` (hai địa điểm khác nhau ở hai thành phố có thể trùng tên). Khác với nghệ
> sĩ, giao diện **không** cảnh báo trùng tên khi tạo địa điểm: hãy chọn theo `#ID`
> trong danh sách khi phân vân.

> **Đổi địa điểm của một CONCERT là thao tác khác** — thực hiện ở mục 6 (Concert), không
> phải ở đây. Thao tác đó bị chặn bởi `TRG_ConcertVenueChangeGuard` khi concert đã có
> ghế trong kho vé hoặc đã có sơ đồ.

### 3.3. Khu vực (Zone) — *"địa điểm này có những khu nào"*

Tạo **khu vật lý**: một cái tên để gom ghế lại, ví dụ `Khu VIP`, `Khu A`. Khu chưa
có hình dạng và chưa nằm ở đâu trên sơ đồ — đó là việc của mục 4.

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Mã khu (`ZoneCode`) | ✔ | Tối đa 64 ký tự — duy nhất trong địa điểm |
| Tên khu (`ZoneName`) | | Tối đa 255 ký tự |
| Mô tả (khi sửa) | | |
| Trạng thái (khi sửa) | | `Active` hoặc `Retired` |

**Chỉ mô hình hoá khu có ghế ngồi.** Hệ thống **không có** khu đứng / General
Admission: `CHK_Zone_Type` chỉ nhận `'Seated'`, tạo khu GA bị từ chối bằng lỗi
`59831`. Đây là giới hạn có chủ đích, không phải thiếu sót.

**Biểu mẫu tạo khu KHÔNG có trường hình học.** Các cột hình học của `Zone`
(`ZoneX/ZoneY/ZoneWidth/ZoneHeight/ZoneRotation/ZoneLevel`) cùng stored procedure
`sp_ConfigureVenueMap` **không có đường ghi nào từ ứng dụng**. Hình học thật của
sơ đồ đi qua **Mẫu sơ đồ** (mục 4). Đừng đi tìm nút kéo-thả ở đây.

**Việc tiếp theo:** mục 3.4 — tạo các ghế thuộc khu này.

### 3.4. Ghế — *"khu VIP gồm những ghế nào"*

Tạo **ghế vật lý**: cái ghế có thật, đã gắn số (hàng + số). Cũng như khu, ghế chưa
có toạ độ — đó là việc của mục 4.

**Hai khối, MỘT bộ trường, MỘT quy tắc sinh mã.** Khối *Tạo ghế* và khối *Tạo hàng loạt*
dùng chung đúng các ô nhập dưới đây; khối sau chỉ nhận nhiều hàng và một khoảng số thay vì
một hàng và một số.

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Khu vật lý | ✔ | Có ở **cả hai** khối, cùng trỏ về một giá trị |
| Tiền tố mã ghế | ✔ | Ví dụ `Vip`, `VIP` — giữ nguyên hoa/thường như bạn gõ |
| Hàng | ✔ | *Tạo ghế*: một hàng (`A`). *Tạo hàng loạt*: danh sách — `A`, `A-H`, `A,B,D-H` |
| Số ghế | ✔ | *Tạo ghế*: một số. *Tạo hàng loạt*: *Từ số ghế* → *Đến số ghế* (≥ 1) |

Hai khối dùng chung **Khu vật lý** và **Tiền tố mã ghế**: sửa ở khối này thì khối kia
cũng đổi theo, vì đó là cùng một giá trị chứ không phải hai ô riêng. Riêng ô **Hàng** của
khối *Tạo ghế* chỉ nhận **đúng một hàng** — gõ `A-H` vào đó sẽ bị từ chối kèm lời nhắc
dùng khối *Tạo hàng loạt*.

**Mã ghế do hệ thống sinh — không gõ tay:**

```
tiền tố  +  '-'  +  hàng  +  số
  Vip    +   -   +   A    +  1   =  Vip-A1
  VIP    +   -   +   A    +  1   =  VIP-A1
```

- **Hoa/thường giữ nguyên như bạn gõ** — hệ thống không tự viết hoa.
- Hệ thống **tự thêm dấu gạch** sau tiền tố. Tiền tố đã kết thúc bằng `-`, `_` hoặc `.`
  thì không thêm nữa, nên gõ `VIP-` cũng ra `VIP-A1`.
- **Hàng nằm trong mã, và đó là điều kiện bắt buộc, không phải lựa chọn.** Mã ghế là
  **duy nhất trong một khu** (BR05): nếu mã chỉ gồm tiền tố + số thì `Vip1` ở hàng A và
  `Vip1` ở hàng B **trùng nhau**, và lô bị từ chối **nguyên lô** (`59827`). Đó cũng chính
  là lý do mã **bắt buộc** phải chứa hàng thì mới tạo được nhiều hàng một lúc.
- Mã tối đa **64 ký tự**. Giao diện tự kiểm vì mã do hệ thống sinh; nếu vượt, dòng nhắc
  dưới nút nói rõ mã dài nhất là gì.
- **Danh sách hàng** nhận một hàng (`A`), một khoảng (`A-H`), hoặc nhiều mục cách nhau
  bằng dấu phẩy/khoảng trắng (`A,B,D-H`). Khoảng chỉ hỗ trợ chữ cái cùng độ dài (`A-H`,
  `AA-AD`) hoặc số (`1-10`). Sân thật thường **bỏ hàng `I` và `O`** để khỏi lẫn với số 1
  và 0 — khi đó ghi `A-H,J-N`.

Dòng **xem trước** ngay dưới mỗi nút cho biết chính xác sẽ tạo ra gì: `Mã ghế sẽ tạo:
Vip-A1`, hoặc `Sẽ tạo 64 ghế = 8 hàng (A…H) × 8 số · mã: Vip-A1 … Vip-H8`. Nút bị vô hiệu
hoá thì **chính dòng đó nói vì sao** — không bao giờ im lặng.

- Cả lô là **một transaction**: một ghế lỗi thì **rollback toàn lô**, không để lại nửa lưới.
- **Tối đa 3.600 ghế mỗi lần** (`59826`) — cùng một con số ở giao diện và ở stored procedure.
- `(Hàng, Số)` và mã ghế đều không được trùng trong cùng khu.
- **Nhãn ghế** được đặt **tự động bằng chính mã ghế** (`Vip-A1`), nên ghế sinh ra luôn có
  tên hiển thị — không còn để trống. Không có ô nhập nhãn ở khối tạo vì hai khối dùng
  chung bộ trường; muốn đặt nhãn khác mã thì sửa ở khối **Cập nhật ghế**.

**Ngừng dùng ghế:** đặt trạng thái `Retired`. Ghế hoặc khu `Retired` **không đưa
được vào kho vé** (`58219`).

**Việc tiếp theo — và đây là chỗ hầu hết người mới dừng lại rồi tưởng đã xong:**

Danh mục mới chỉ tạo ra **ghế vật lý**, tức là *"Nhà hát X có một ghế tên A1"*.
Ghế này **chưa có vị trí, chưa có giá, và chưa bán được**:

1. Sang **Mẫu sơ đồ** (mục 4) để vẽ vị trí các ghế đó trên mặt bằng.
2. Chụp mẫu sơ đồ vào **concert** (mục 7) để sinh kho vé kèm giá.
3. Chỉ khi đó ghế mới **bán được**.

Làm bước 1 một lần cho mỗi địa điểm rồi dùng lại cho mọi concert sau — không phải
vẽ lại.

---

## 4. Mẫu sơ đồ — StagePass Studio (`/admin/venue-templates`) — **chỉ Admin**

Trả lời câu hỏi: *"Nhà hát X **trông** như thế nào?"* — vẽ **hình học thật** của sơ
đồ: các tầng, sân khấu, lối đi, khu ghế nằm ở đâu, và ghế nào ở chỗ nào. Một mẫu sơ
đồ = *một cách bố trí* của một địa điểm, dùng lại được cho nhiều concert.

**Nếu bỏ qua mục này thì sao:** khách hàng **không chọn được ghế nào** và không mua
được vé — dù kho vé đã đầy ghế (xem cảnh báo cuối phần "Đọc trước" ở mục 3).

Ba bước của toàn hệ thống, mỗi bước ở một trang:

```
① KHAI BÁO VẬT LÝ           ② VẼ                         ③ BÁN
   /admin/catalog               /admin/venue-templates       /admin/concerts
   Địa điểm → Khu → Ghế   →     Mẫu sơ đồ → Version     →     ConcertMap → Revision Locked
   (Zone, Seat)                 Tầng → Vật thể → Khu          → EventSeat (giá + tồn kho)
                                → Ghế (gắn Seat ở trên)
   "có những ghế nào"           "ghế nằm ở đâu"               "bán ghế nào, giá bao nhiêu"
   tồn tại vĩnh viễn            bất biến khi Publish          riêng cho từng show
   KHÔNG bán được                                             BÁN ĐƯỢC
```

Bước ② **bắt buộc** nếu muốn khách mua vé online (xem cảnh báo ở mục 3). Bước ①
làm một lần cho mỗi địa điểm rồi dùng lại cho mọi concert sau.

Trang có 4 khối theo thứ tự: **Chọn địa điểm** → **Mẫu sơ đồ** → **Phiên bản** →
**Dựng hình học**.

### Bước 1 — Chọn địa điểm
Chọn Venue. Mỗi địa điểm có thể có nhiều mẫu, ví dụ "Nhà hát" và "Sân khấu cuối"
cho cùng một venue.

### Bước 2 — Tạo Mẫu sơ đồ (VenueTemplate)
- Trường **"Tên mẫu mới"** (ví dụ `Nhà hát`, `Sân khấu cuối`) → nút **Tạo mẫu**.
- Nút **Đổi tên** để sửa tên về sau.
- Tên template phải **duy nhất trong địa điểm** (`60004` / `60009` nếu trùng).
- Bản thân template **không chứa hình học** — hình học nằm ở các phiên bản.

### Bước 3 — Tạo phiên bản (VenueTemplateVersion)
- Chọn **"Sao chép từ version (tuỳ chọn)"**: để trống = bắt đầu từ **mặt bằng rỗng**;
  chọn một version cũ = sao chép toàn bộ tầng/khu/vật thể/ghế.
- **Mỗi template chỉ có MỘT Draft mở.** Tạo Draft thứ hai khi Draft cũ còn đó bị
  từ chối bằng `60014`. Kết thúc Draft bằng cách **Publish** hoặc **huỷ Draft**.
- Template đã `Archived` không tạo được version mới (`60013`).
- Version nguồn để sao chép phải thuộc **cùng template** (`60015`).

### Bước 4 — Khai báo tầng (Floor) — mỗi tầng một hệ toạ độ riêng

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Mã tầng (`FloorKey`) | ✔ | Ví dụ `ground`, `balcony` — không trùng trong version (`60047`) |
| Tên tầng | | Ví dụ `Tầng trệt` |
| Thứ tự | ✔ | Số nguyên ≥ 1, **không trùng** giữa các tầng (`60048`) |
| Rộng / Cao (canvas) | ✔ | Số nguyên > 0 (`60045`) |

Mỗi tầng có **canvas riêng** — không vẽ chồng các tầng lên một mặt phẳng. Thu nhỏ
canvas bị từ chối nếu còn vật thể hoặc khu nằm ngoài biên mới.

### Bước 5 — Đặt vật thể định hướng

Khối **"Vật thể (sân khấu, lối đi…)"** — *"Không bán được — chỉ tham chiếu/trang trí."*

| Trường | Ghi chú |
|---|---|
| Loại | 8 giá trị, xem bảng dưới |
| Nhãn | Tuỳ chọn |
| GeometryJson | Hình học, phải **lồi** và **nằm trong canvas** |

| Giá trị `ObjectType` | Nhãn tiếng Việt |
|---|---|
| `Stage` | Sân khấu |
| `Aisle` | Lối đi |
| `Wall` | Tường |
| `Entrance` | Cửa vào |
| `Restroom` | Nhà vệ sinh |
| `Bar` | Quầy bar |
| `Text` | Nhãn chữ |
| `Icon` | Biểu tượng |

`Stage` là **giá trị duy nhất** đánh dấu sân khấu — nhờ vậy sơ đồ của khách suy
được **hướng sân khấu thật** từ hình học, không cần mũi tên viết cứng.
### Bước 6 — Vẽ khu ghế (Section)

Khối **"Khu ghế (Section)"** — *"Không được chồng Sân khấu hoặc Section khác cùng
tầng — máy chủ kiểm tra va chạm thật (SAT)."*

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Mã khu (`SectionKey`) | ✔ | Không trùng trong tầng |
| Tên khu | | Ví dụ `Khu VIP` |
| **Khu vật lý (Zone)** | ✔ | Chỉ hiện Zone đang `Active` của **đúng venue**. Mỗi Zone chỉ được gán cho **một** Section trong cùng version (`60096`) |
| GeometryJson | ✔ | Đa giác **phải LỒI** — hệ thống từ chối hình lõm để đảm bảo va chạm chính xác |

Ba kiểm tra chạy trên **giá trị sau khi hợp nhất**: nằm trong canvas, không chồng
Section khác cùng tầng, không chồng sân khấu.

### Bước 7 — Gắn ghế vào khu

Chọn **Seat** từ danh sách ghế thuộc Zone của khu đó, rồi nhập `SeatKey`, `Hàng`,
`Số`. Chỉ cần nhập `GeometryJson` cho ghế nằm trên **hàng cong hoặc bàn tròn** —
các ghế còn lại vị trí được suy từ hàng/số.

Ràng buộc: một `Seat` không được xuất hiện ở **hai khu khác nhau** trong cùng
version; `SeatKey` không trùng trong khu; ô lưới `(Hàng, Số)` không trùng; `Hàng`
và `Số` phải **cùng có hoặc cùng không**.

### Bước 8 — Công bố (Publish)

Nút Publish chuyển version từ `Draft` → `Published`. Từ đây version **bất biến
hoàn toàn** — không sửa được bất kỳ tầng, khu, vật thể hay ghế nào. Muốn thay đổi
thì tạo Draft mới (có thể sao chép từ version vừa publish).

- Chỉ publish được version đang `Draft` (`60023`).
- Version **phải có ít nhất một ghế** (`60024` — "Version chưa có ghế nào").
- Nút Publish bị **vô hiệu hoá** khi template còn Draft khác đang mở.
- Version đã publish **không xoá được**; chỉ xoá được Draft (`60033`).

### Giới hạn độ dài các trường

Nhập quá giới hạn bị **từ chối bằng lỗi 400** — không lưu cụt im lặng. Con số dưới đây
là **độ rộng cột thật trong database**, không phải ước lượng:

| Trường | Tối đa |
|---|---|
| Tên mẫu sơ đồ (`TemplateName`) | 255 ký tự |
| Mã tầng (`FloorKey`) | 64 ký tự |
| Tên tầng (`FloorName`) | 255 ký tự |
| Loại vật thể (`ObjectType`) | 32 ký tự |
| Nhãn vật thể (`Label`) | 255 ký tự |
| Mã khu (`SectionKey`) | 64 ký tự |
| Tên khu (`SectionName`) | 255 ký tự |
| `SeatKey` | 64 ký tự |
| `Hàng` (`RowLabel`) | 16 ký tự |
| `GeometryJson` | không giới hạn (`NVARCHAR(MAX)`) |

> **Vì sao cần bảng này:** tầng truy cập dữ liệu gửi chuỗi bằng tham số có `size` đúng
> bằng độ rộng cột, mà `size` cũng chính là độ dài bị **cắt trước khi gửi đi** — nên giá
> trị dài hơn bị mất phần dư **im lặng**, không có thông báo nào (đã đo: nhập `FloorKey`
> 100 ký tự thì database nhận đúng 64 ký tự, không lỗi). Sáu stored procedure của
> StagePass đều không kiểm độ dài, nên tầng API là chốt duy nhất.

### Công cụ vẽ hình học

Mỗi hình học có **3 chế độ**:

| Chế độ | Dùng khi |
|---|---|
| **Hình chữ nhật** | Nhập `X`, `Y`, `Rộng`, `Cao`, `Xoay (độ)` |
| **Vẽ đa giác (chuột)** | Bấm từng đỉnh trên canvas. Nút: **Xong (n đỉnh)**, **Xoá điểm cuối**, **Vẽ lại**, **Vẽ thêm đỉnh** |
| **JSON thô** | Dán trực tiếp, ví dụ `{"version":1,"shape":"polygon","points":[[0,0],[100,0],[100,100]]}` |

Định dạng v1 dùng chung cho cả vật thể, khu và ghế:

```json
{"version":1,"shape":"rect","x":100,"y":50,"width":200,"height":80,"rotation":-10}
{"version":1,"shape":"polygon","points":[[0,0],[200,0],[180,90],[20,90]]}
```

`rect` được quy về 4 đỉnh theo ma trận xoay chuẩn. `polygon` giữ nguyên thứ tự
đỉnh và **chỉ nhận đa giác lồi**. Quy ước "chạm biên = KHÔNG chồng" áp dụng nhất
quán ở cả trình duyệt (cảnh báo sớm) và SQL Server (thi hành thật).

> **Ghi chú thao tác:** khi gắn ghế, danh sách ghế của Zone được tải tối đa **200
> ghế mỗi lần**. Khu có nhiều hơn 200 ghế vật lý cần gắn thành nhiều lượt.

---

## 5. Người dùng — `/admin/users` (khối quản trị **chỉ Admin**)

Trang có 4 khối. Organizer chỉ thấy khối cuối (phân công soát vé).

### 5.1. Cấp và thu hồi vai trò

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| UserID | ✔ | **Số** hiệu người dùng trong database |
| Vai trò | ✔ | `Admin` · `Organizer` · `Customer` · `Check-in Staff` |
| Hành động | ✔ | `Grant` (Cấp quyền) hoặc `Revoke` (Thu hồi quyền) |

- Một người giữ được **nhiều vai trò cùng lúc**.
- Database **từ chối** thu hồi vai trò Admin của **Admin đang hoạt động cuối cùng**
  (`58406` — "Không thể thu hồi Role Admin của Admin đang hoạt động cuối cùng").
  Nhờ vậy hệ thống không bao giờ rơi vào trạng thái không còn quản trị viên nào.
  Giao diện đã cảnh báo trước khi bạn bấm.
- **Không gán được vai trò cho tài khoản hệ thống** `system` (`58404`).
- Chỉ Admin gọi được thao tác này (`58401`).
- Vai trò phải đang `Active` (`58403`).

### 5.2. Mở / đóng việc phân công một vai trò

| Trường | Giá trị |
|---|---|
| Vai trò | 4 vai trò như trên |
| Trạng thái | `Active` (Đang hoạt động) hoặc `Inactive` (Ngừng dùng) |

> Đóng một vai trò **chỉ CHẶN VIỆC CẤP MỚI**. Người đang giữ vai trò đó **vẫn giữ
> nguyên quyền**. Muốn thu hồi quyền của một người cụ thể thì dùng khối 5.1.

### 5.3. Trạng thái tài khoản

| Trường | Bắt buộc | Giá trị |
|---|---|---|
| UserID | ✔ | Số hiệu người dùng |
| Trạng thái mới | ✔ | `Active` · `Locked` (Bị khóa) · `Disabled` (Đã tắt) |

Tài khoản không ở trạng thái `Active` **không đăng nhập được**, và mọi phiên làm
việc hiện có **mất hiệu lực ngay**.

### 5.4. Phân công nhân viên soát vé

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| UserID của nhân viên | ✔ | Người này **phải đã có vai trò `Check-in Staff`** |
| Trạng thái phân công | ✔ | `Active` hoặc `Revoked` |
| Danh sách ID concert | ✔ | Ngăn cách bằng dấu phẩy hoặc khoảng trắng; **trùng lặp sẽ bị từ chối** |

Nhân viên soát vé chỉ soát được **concert được phân công** (`sp_CheckInTicket`
kiểm tra phân công trước khi cho qua cổng). Admin và Organizer sở hữu concert đều
phân công được.

> **Giới hạn thật cần biết: hệ thống KHÔNG có danh bạ người dùng.** Không có
> endpoint liệt kê hay tìm kiếm tài khoản, nên cả 4 khối trên đều **yêu cầu bạn
> gõ UserID bằng số**. Cách lấy UserID:
> - Sau khi `bootstrap-admin.ps1` chạy xong, UserID của Admin đầu tiên được in ra
>   và ghi trong `.deploy/bootstrap-info.json`.
> - Với người dùng khác, tra trong database:
>   `SELECT UserID, Username FROM UserAccount;`
>   hoặc dùng Nhật ký kiểm toán với Loại đối tượng = *Phân quyền người dùng*.
>
> Ngoài ra **không có đường sửa email hay tên hiển thị** của người dùng, và
> **không có đường đặt lại mật khẩu** cho người dùng. Chọn email cẩn thận ngay từ
> đầu.

---

## 6. Concert — `/admin/concerts`

Trang có 7 khối: **Tạo concert** · **Sửa concert** · **Chuyển trạng thái** ·
**Hạng vé** · **Sơ đồ ghế StagePass** · **Cấu hình hàng đợi** · **Cấu hình danh
sách chờ** · **Khoá / mở một ghế**.

### 6.1. Tạo concert

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Nghệ sĩ biểu diễn | | Chọn nhiều; **thứ tự chọn là thứ tự hiển thị** |
| Địa điểm | | |
| Tên concert | ✔ | Tối đa 255 ký tự |
| Bắt đầu diễn | ✔ | |
| Kết thúc diễn | ✔ | Phải **sau** giờ bắt đầu (`58002` / `58013`) |
| Mở bán từ | | **Cần có trước khi mở bán** — thiếu mốc này không chuyển sang `OnSale` được (`58024`) |
| Đóng bán lúc | | Cũng bắt buộc trước khi mở bán; phải **sau hoặc bằng** "Mở bán từ" (`58007`) |
| Giới hạn vé / khách | | Số nguyên > 0 (`58003`); vượt thì `sp_CreateBooking` từ chối bằng `51003` |
| Thời gian giữ chỗ (phút) | | Bỏ trống = dùng cấu hình chung `Default_Temporary_Hold_Duration` (900 giây) |
| Hạn hủy trước giờ diễn (giờ) | | Quá hạn này `sp_ProcessRefund` từ chối hoàn tiền (CI10) |
| **Tỷ lệ hoàn tiền (%)** | | 0–100. Đây là **căn cứ DUY NHẤT** để tính số tiền hoàn (BR32a) |
| Bật Fair Access | | Khách phải xếp hàng và được cấp lượt mới đặt được vé |
| Bật Waitlist | | Khi hết ghế, khách đăng ký chờ theo hạng vé |
| Tạm dừng bán ngay | | Chặn đặt vé **mà không đổi trạng thái** concert |
| Chính sách hủy / hoàn tiền (mô tả) | | Văn bản tự do |

> Concert **luôn sinh ra ở trạng thái `Draft`** — biểu mẫu không nhận trường trạng
> thái lúc tạo, mọi chuyển trạng thái phải đi qua máy trạng thái (BR49).

### 6.2. Chuyển trạng thái concert

Đường thường dùng:

```
Draft → Published → OnSale → SaleClosed → Completed
                  ↘ Cancelled
```

Máy trạng thái ở database quyết định phép chuyển nào hợp lệ; bước sai bị từ chối
kèm lý do. Hai cổng quan trọng nhất **trước khi mở bán**:

| Cổng | Lỗi | Ý nghĩa |
|---|---|---|
| Phải có kho vé | `58023` | Concert chưa có ghế nào trong kho vé |
| Phải có cửa sổ bán | `58024` | Chưa đặt "Mở bán từ" / "Đóng bán lúc" |
| Sơ đồ phải khoá | `58061` | Concert có ConcertMap nhưng revision chưa `Locked` |
| Kho vé phải khớp sơ đồ | `58062` / `58063` | Mọi ghế trong kho vé phải gắn với sơ đồ đã khoá — còn ghế chưa gắn thì chưa mở bán được |

Chỉ sửa được concert ở `Draft` hoặc `Published` (`58011`). Admin sửa được **mọi**
concert; Organizer chỉ concert mình sở hữu (`58012` / `58022`).

### 6.3. Hạng vé

Một endpoint làm **cả hai việc**: bỏ trống ô ID hạng vé thì **TẠO MỚI**, điền vào
thì **CẬP NHẬT**.

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Hạng vé | | Chọn hạng có sẵn để sửa, hoặc để trống để tạo mới |
| Tên hạng vé | ✔ | Tối đa 255 ký tự |
| Giá gốc (₫) | ✔ | **Số nguyên** — cột tiền là `DECIMAL(18,0)`; ≥ 0 |
| Trạng thái | | `Active` hoặc `Inactive` (`58207`) |
| Mô tả | | |

> **Giá gốc ở hạng vé là NGUỒN SỰ THẬT của giá vé** và sẽ **lan xuống mọi ghế**
> trong kho (BR10a) — sửa giá ở đây là sửa giá của tất cả ghế thuộc hạng đó.
> Không sửa giá từng ghế riêng lẻ.

Hạng vé đang được dùng bởi ghế trong kho **không xoá được** (`58208`).

### 6.4. Đưa ghế vào kho vé

Chỉ thêm được khi concert ở `Draft` hoặc `Published` (`58218`). Có **hai đường**
và chỉ một đường dùng được cho mỗi concert:

| Đường | Khi nào | Lỗi chặn |
|---|---|---|
| **Theo danh sách SeatID** (đường cũ) | Concert **chưa** có ConcertMap | Nếu đã có ConcertMap: `58221` — "Concert đã dùng sơ đồ StagePass, hãy thêm ghế từ revision" |
| **Từ revision đã khoá** (StagePass, mục 7) | Concert **đã** có ConcertMap | Nếu đã có kho vé kiểu cũ: `60205` |

> ### Đường cũ tạo ra kho vé KHÔNG bán được cho khách
>
> Hai đường không tương đương nhau về kết quả kinh doanh:
>
> - **Đường cũ** (`sp_AddEventSeats` theo SeatID): ghế **có** trong kho vé, **có**
>   giá, **có** trạng thái — nhưng concert vẫn chưa có revision `Locked`, nên
>   `GetSeatMapAsync` trả `null` và giao diện khách hiển thị *"Sơ đồ ghế đang được
>   hoàn thiện"*. Khách **không chọn được ghế nào** ⇒ **không mua được**.
> - **Đường StagePass** (mục 7): ghế vào kho vé **kèm vị trí trên sơ đồ đã khoá** ⇒
>   khách bấm chọn được ⇒ bán được.
>
> Vì vậy: dùng đường StagePass cho mọi concert bán vé online. Đường cũ chỉ còn phù
> hợp cho dữ liệu cũ/mục đích kỹ thuật, không phải để vận hành bán vé.

Các ràng buộc khác:

- Danh sách rỗng bị từ chối (`58215`).
- `SeatID` không tồn tại (`58216`), đã có trong kho vé (`58217` / `60250`), hoặc
  thuộc Seat/Zone `Retired` (`58219` / `60249`).
- Hạng vé phải thuộc **đúng concert** và đang `Active` (`58213`).
- Danh sách chứa giá trị không phải số nguyên bị từ chối (`58222`).
- Chỉ gắn được ghế từ revision **đang `Locked`** (`60242`).

### 6.5. Khoá / mở một ghế

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| ID ghế trong kho vé (EventSeatID) | ✔ | |
| Hành động | | Đặt `Unavailable` hoặc trả về `Available` |
| Lý do khoá | ✔ | Bắt buộc khi khoá; tối đa 500 ký tự; **được ghi vào nhật ký kiểm toán** |

Dùng cho **ghế hỏng, ghế bị che tầm nhìn, hoặc ghế giữ cho ban tổ chức**. Chỉ tác
động tới ghế đang **trống** — ghế đã bán hoặc đang được giữ sẽ bị từ chối.

> Đây **không phải** công cụ giữ ghế theo danh tính: hệ thống không lưu ai đang giữ
> và không có hạn giữ. Muốn giữ ghế cho sponsor/nghệ sĩ thì ghế đó phải được đặt ở
> trạng thái `Unavailable` **trước khi** mở bán, kèm lý do.

---

## 7. Sơ đồ ghế cho concert (ConcertMap) — khối trong `/admin/concerts`

> *"Chụp snapshot BẤT BIẾN từ một Mẫu sơ đồ (VenueTemplate) đã Công bố — quản trị
> mẫu sơ đồ ở trang 'Mẫu sơ đồ (Studio)'."*

Đây là cầu nối giữa **bản vẽ** (mục 4) và **kho vé**. Quy trình 4 bước:

### Bước 1 — Bật sơ đồ cho concert
Tạo `ConcertMap`. Ràng buộc:
- Concert phải đã gán **địa điểm** (`60213`).
- **Mỗi concert chỉ có MỘT** ConcertMap (`60203`).
- Concert **đã có kho vé kiểu cũ** thì không bật được (`60205`) — và ngược lại, đã
  có sơ đồ thì không thêm được ghế kiểu cũ (`58221`).
- Concert phải ở `Draft` hoặc `Published` (`60204`).

### Bước 2 — Tạo bản nháp revision (snapshot)
Chọn **"Mẫu sơ đồ / Version đã công bố"**. Nếu địa điểm chưa có mẫu nào đang hoạt
động với version đã công bố, danh sách sẽ trống — quay lại mục 4 để publish trước.

Hệ thống **sao chép thật** (không tham chiếu) toàn bộ tầng, vật thể, khu và ghế
sang các bảng `ConcertMapRevision*`. Đây là lý do **vé đã bán không bao giờ đổi
hình**: nếu sau này Admin publish một version mới của mẫu sơ đồ, concert đã bán vé
vẫn giữ nguyên bản đã chụp.

Ràng buộc:

| Lỗi | Ý nghĩa |
|---|---|
| `60215` | Version nguồn **chưa Published** |
| `60216` | Mẫu sơ đồ nguồn **không thuộc đúng địa điểm** của concert |
| `60214` | Version nguồn không tồn tại |
| `60217` | Map **đang có một Draft mở** — phải khoá hoặc huỷ Draft cũ trước |
| `60234` | Revision **chưa có ghế nào** (không khoá được) |

**Hình học của revision là bất biến từ lúc chụp** — Draft revision **không sửa
được** tầng/khu/vật thể/ghế. Muốn đổi bố trí thì tạo Draft mới từ version khác.

### Bước 3 — Khoá revision (Lock)
Khoá chuyển `Draft` → `Locked`. Chỉ `Locked` mới được khách nhìn thấy và mới đưa
được ghế vào bán.

- Chỉ khoá được revision đang `Draft` (`60233`).
- **Mỗi map chỉ có một revision `Locked`** (`60236` nếu đã có).
- Revision `Locked` là **bản duy nhất được công khai** — trang khách **không** có
  đường dự phòng nào đọc từ `Zone`/`Seat` cũ. Concert chưa có revision `Locked`
  thì khách thấy thông báo "sơ đồ đang được hoàn thiện", **không** thấy danh sách
  ghế thay thế.

### Bước 4 — Đưa ghế từ sơ đồ vào kho vé
Chọn **hạng vé**, rồi chọn ghế bằng **"Danh sách ghế cần đưa vào kho vé"**
(ngăn cách bằng dấu phẩy hoặc khoảng trắng; **trùng lặp tự động bị loại**) hoặc
**"Chọn ghế"** (giữ Ctrl hoặc Shift để chọn nhiều).

Hệ thống tạo `EventSeat` và gán ngược `EventSeatID` trong **cùng một transaction**.

| Lỗi | Ý nghĩa |
|---|---|
| `60242` | Chỉ thêm được từ revision đang **`Locked`** |
| `60244` | Concert phải ở `Draft` hoặc `Published` |
| `60245` | Hạng vé không thuộc concert hoặc không `Active` |
| `60246` | Danh sách ghế rỗng |
| `60247` | Có ghế không thuộc revision này |
| `60248` | Có ghế **đã được đưa vào kho từ trước** |
| `60249` | Có Seat hoặc Zone đã `Retired` |
| `60250` | Có ghế đã có trong kho vé của concert |
| `60251` | Danh sách chứa giá trị không phải số nguyên |

Ghế vẫn vẽ trên sơ đồ nhưng **chưa bán** là ghế có `EventSeatID = NULL`. Không có
`EventSeat` thì dù sơ đồ có ghế, khách **không thấy để chọn**.

### Huỷ bản nháp (khi chụp nhầm)

Nếu bạn chọn nhầm version nguồn, dùng nút **Huỷ nháp** để bỏ revision `Draft` đó
rồi chụp lại. Revision Draft chưa từng phục vụ ai nên bị **xoá thật**, không giữ
lại trạng thái "đã huỷ"; dấu vết nằm ở Nhật ký kiểm toán.

| Lỗi | Ý nghĩa |
|---|---|
| `60231` | Revision không tồn tại |
| `60232` | Bạn không phải Organizer của concert này và cũng không phải Admin |
| `60237` | **Chỉ huỷ được revision đang `Draft`** — revision đã khoá không huỷ được |
| `60238` | **Revision đã có ghế trong kho vé** — phải xử lý kho vé trước (không có `ON DELETE CASCADE`, nên xoá sẽ làm `EventSeat` mồ côi và mất vị trí trên sơ đồ) |

> **Điều không thể làm:** một khi đã `Locked`, revision **không sửa, không huỷ,
> không thay thế**. Bạn cũng không tạo được revision `Locked` thứ hai cho cùng map.
> Muốn bố trí khác thì phải làm concert mới. Hãy kiểm tra kỹ sơ đồ **trước khi**
> bấm Lock.

---

## 8. Khuyến mãi — `/admin/promotions`

### 8.1. Tạo chương trình khuyến mãi

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Tên khuyến mãi | ✔ | Tối đa 255 ký tự (`58306`) |
| **Kiểu giảm giá** | ✔ | `Percentage` hoặc **`Fixed Amount`** — xem cảnh báo dưới |
| Giá trị giảm | ✔ | Phải > 0 (`58304`) |
| Hiệu lực từ | ✔ | |
| Hiệu lực đến | ✔ | Phải **sau** "Hiệu lực từ" (`58305`) |
| Tổng lượt dùng tối đa | | Bỏ trống = **không giới hạn** |
| Số ghế tối đa được giảm / đơn | | Bỏ trống = áp cho **toàn bộ** ghế trong đơn (BR36b) |
| Mức giảm tối đa / đơn (₫) | | Trần an toàn khi giảm theo phần trăm |
| Trạng thái | | `Draft` · `Active` · `Disabled` |

> ⚠ **`Fixed Amount` viết ĐÚNG như vậy — CÓ dấu cách.** Đây là giá trị database
> lưu, không phải nhãn hiển thị. Gửi `FIXED` hay `FixedAmount` đều bị `CHECK`
> constraint từ chối. Giao diện đã đặt đúng, chỉ cần biết khi gọi API trực tiếp.

Promotion phải ở trạng thái **`Active` mới được áp dụng** (`sp_ApplyPromotion` từ
chối mọi trạng thái khác). `sp_CreatePromotion` yêu cầu concert ở `Draft` hoặc
`Published`.

### 8.2. Áp nhiều khuyến mãi — thứ tự có ý nghĩa

Khi một đơn áp nhiều chương trình, hệ thống đánh số lại
`BookingPromotionApplication.ApplicationOrder` theo kiểu **set-based** và tính
từng bước trên **phần tiền còn lại** sau bước trước (BR36d). Nghĩa là giảm 20% rồi
giảm 200.000₫ **khác** với giảm 200.000₫ rồi giảm 20%.

### 8.3. Mã giảm giá

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| Mã giảm giá (`CodeValue`) | ✔ | Tối đa 64 ký tự; **đây là chuỗi khách gõ ở trang thanh toán** (`58602`) |
| Hiệu lực từ | | Bỏ trống = **theo thời hạn của khuyến mãi** |
| Hiệu lực đến | | Phải **sau** "Hiệu lực từ" (`58603`) |
| Tổng lượt dùng tối đa | | |
| Lượt dùng tối đa / khách | | |
| Trạng thái | | `Active` hoặc `Disabled` |

Mã giảm giá thuộc một promotion và **không được trùng** (`58604`). Có thể **tắt
riêng một mã bị lộ** mà không cần tắt cả chương trình — đây là lý do mã tách khỏi
promotion.

---

## 9. Hoàn tiền — `/admin/refunds`

### 9.1. Huỷ một đơn

| Trường | Bắt buộc | Ghi chú |
|---|---|---|
| BookingID | ✔ | |
| Lý do hủy | | Không bắt buộc; **được ghi vào nhật ký kiểm toán** |

Huỷ đơn giải phóng ghế và tạo yêu cầu hoàn tiền ở trạng thái `Pending`.

### 9.2. Xác nhận hoàn tiền

Xác nhận hoàn tiền là **bước riêng**, sau khi khoản tiền **đã được hoàn thực tế**
qua phương thức thanh toán. **Không đánh dấu đã hoàn chỉ vì yêu cầu vừa được tạo.**

Trạng thái `Refund` có 4 giá trị: `Pending` · `Confirmed` · `Failed` · `Cancelled`.

| Thao tác | Giá trị nhận |
|---|---|
| Cập nhật trạng thái | **Chỉ** `Failed` hoặc `Cancelled` — muốn xác nhận đã hoàn xong thì dùng nút xác nhận riêng |
| Lý do | **Bắt buộc**, tối đa 500 ký tự, **không ghi đè lý do hoàn tiền gốc** |

Số tiền hoàn được tính từ **"Tỷ lệ hoàn tiền (%)" của concert** — đây là căn cứ
duy nhất (BR32a). Quá **"Hạn hủy trước giờ diễn"** thì `sp_ProcessRefund` từ chối.

---

## 10. Fair Access và danh sách chờ — khối trong `/admin/concerts`

Hai luồng **riêng biệt**, đừng nhầm:

| | Fair Access (Queue) | Waitlist |
|---|---|---|
| Kiểm soát | **Quyền truy cập** trang chọn ghế | **Cơ hội mua** khi có ghế trả lại |
| Khi nào | Trước khi chọn ghế | Sau khi hết chỗ |

### 10.1. Cấu hình hàng đợi (Fair Access)

| Trường | Ghi chú |
|---|---|
| Sức chứa hàng đợi | Số khách được cấp lượt mua **cùng lúc** |
| Chính sách chọn lượt | `FIFO` (ai vào trước phục vụ trước) hoặc `RANDOM` (bốc ngẫu nhiên) |
| Thời hạn lượt mua (giây) | Chính là `booking_ttl`; bỏ trống = dùng `Queue_Admission_Validity` (600 giây). Hết hạn thì lượt tự thu hồi và nhường cho người kế tiếp (BR47b) |
| Trạng thái hàng đợi | `Open` hoặc `Closed` |

> Fair Access chỉ có tác dụng nếu **concert đã bật Fair Access**. Nếu không bật,
> `sp_CreateBooking` **không** kiểm tra hàng đợi, và mọi cấu hình ở đây chỉ là
> trang trí. Ngược lại, khi bật, khách **chưa được cấp lượt** bị chốt ngay ở
> `sp_CreateBooking` bằng lỗi `51007` — hiệu lực thật, không phải gợi ý.

### 10.2. Cấu hình danh sách chờ (Waitlist)

| Trường | Ghi chú |
|---|---|
| Chính sách cấp cơ hội | `FIFO` hoặc `RANDOM` |
| Trạng thái danh sách chờ | `Open` hoặc `Closed` |

Khi có ghế được trả lại, **tiến trình nền** cấp cơ hội mua cho người trong danh
sách chờ theo chính sách này (BR43). Cơ hội có **hạn** (`Waitlist_Opportunity_Duration`
= 900 giây); hết hạn thì hệ thống **tự chuyển cho người kế tiếp** — bạn không phải
làm gì thủ công. Trạng thái entry: `Active` · `Granted` · `Fulfilled` · `Expired` · `Cancelled`.

### 10.3. Công việc nền (không cần bấm)

Bốn tiến trình chạy tự động, đăng ký sẵn khi khởi động backend:

| Tiến trình | Việc |
|---|---|
| `HoldReleaseWorker` | Nhả ghế hết hạn giữ chỗ và cấp cơ hội waitlist |
| SIP3 | Xử lý cấp lượt hàng đợi (`sp_ProcessQueueAdmission`) |
| SIP5 | Tự mở/đóng bán theo lịch (`sp_ProcessSaleWindowTransitions`) |

Vì có SIP5, **"Mở bán từ" / "Đóng bán lúc" được thi hành tự động** — bạn không cần
quay lại bấm chuyển trạng thái đúng giờ.

---

## 11. Báo cáo — `/admin/reports`

Chọn một **Concert** rồi bấm **Xem báo cáo**. Trang nạp **4 báo cáo cùng lúc**:

### 11.1. Tóm tắt concert

| Chỉ số | Ý nghĩa |
|---|---|
| Doanh thu (net) | Doanh thu thực nhận |
| Tổng số ghế | Tổng tồn kho |
| Còn trống | Ghế `Available` |
| Đã đặt | Ghế `Booked` |
| Đang giữ | Ghế `OnHold` |
| Đơn đã xác nhận / Đơn đã hủy | Theo trạng thái booking |

### 11.2. Check-in

Vé đã phát hành · Đã vào cổng · Chưa vào cổng · **Tỷ lệ vào cổng (%)**.

### 11.3. Danh sách người giữ vé

Bảng: Ghế · Khu · Hạng vé · Khách (tên hiển thị + username) · Trạng thái vé ·
Vào cổng lúc.

> **Không có mã vé (QR) trong báo cáo này** — đó là *bearer credential* dùng để
> qua cổng, chỉ giao cho chính khách hàng (trang "Vé của tôi") và nhân viên soát
> vé tại cổng. Đây là quyết định có chủ đích, không phải thiếu sót.

### 11.4. Danh sách chờ

Vị trí · Khách · Hạng vé · Số ghế muốn · Trạng thái · Ghế đang giữ · **Cơ hội hết
hạn lúc**.

Phạm vi dữ liệu: Organizer chỉ thấy concert **mình sở hữu**; **Admin thấy mọi
concert**. Gọi sai concert của người khác chỉ nhận **404** — không lộ concert đó
có tồn tại hay không.

---

## 12. Nhật ký kiểm toán — `/admin/audit` — **chỉ Admin**

*"Mọi thay đổi nghiệp vụ đều để lại dấu vết không sửa được."*

| Trường | Ghi chú |
|---|---|
| Loại đối tượng | Bỏ trống = tra cứu mọi loại |
| ID đối tượng | Ví dụ số hiệu Booking. Bỏ trống = không lọc |
| Từ thời điểm | |
| Đến thời điểm | **Không bao gồm** mốc này (nửa mở) |

Câu hỏi chính là *"lịch sử thay đổi của MỘT đối tượng"* — nên điền **Loại đối
tượng + ID** để lấy toàn bộ lịch sử của riêng đối tượng đó; khoảng thời gian là bộ
lọc phụ. Bỏ trống tất cả để xem các sự kiện gần nhất.

**10 loại đối tượng tra được** — đúng các giá trị mà stored procedure ghi vào
`AuditRecord`:

| Giá trị | Nghĩa |
|---|---|
| `Booking` | Đơn đặt vé |
| `Payment` | Giao dịch thanh toán |
| `Refund` | Khoản hoàn tiền |
| `Ticket` | Vé |
| `Concert` | Sự kiện |
| `EventSeat` | Ghế trong kho vé |
| `WaitlistEntry` | Đăng ký danh sách chờ |
| `QueueEntry` | Lượt xếp hàng đợi |
| `UserRoleAssignment` | Phân quyền người dùng |
| `CheckinStaffAssignment` | Phân công soát vé |

**Ba lớp bảo vệ độc lập:**

1. Endpoint mang `[Authorize(Roles = "Admin")]`.
2. `VW_AuditTrail` tự trả **0 dòng** cho phiên không giữ vai trò Admin (RLS qua
   `SESSION_CONTEXT`) — kể cả khi lớp 1 bị gỡ nhầm, dữ liệu vẫn không rò ra.
3. Bảng `AuditRecord` gốc bị **`DENY`** với mọi kết nối ứng dụng.

Bản thân `AuditRecord` là **bất biến**: trigger `TRG_AuditLog` chặn mọi `UPDATE` và
`DELETE`. Không có đường sửa hay xoá vết audit từ ứng dụng.

---

## 13. Bảng mã lỗi theo thao tác

Backend dịch mọi lỗi từ stored procedure thành HTTP kèm thông báo tiếng Việt. Dưới
đây là những mã Admin **sẽ thực sự gặp**, kèm nguyên văn thông báo.

### 13.1. Danh mục

| Mã | HTTP | Thông báo |
|---|---|---|
| `58124` | 409 | Mã ghế đã tồn tại trong khu vực này. |
| `58219` | 400 | Có Seat hoặc Zone đã ngừng sử dụng, không thể đưa vào kho vé. |
| `59831` | 409 | Hệ thống hiện chỉ hỗ trợ khu có ghế đánh số; vé đứng cần mô hình kho vé riêng. |
| `58009` | 409 | Địa điểm này đã ngừng sử dụng, không thể tạo Concert mới tại đây. |
| `58028` | 409 | Không thể đổi địa điểm khi Concert đã tạo sơ đồ StagePass (ConcertMap). |

### 13.2. Mẫu sơ đồ (StagePass Studio)

| Mã | Thông báo |
|---|---|
| `60004` / `60009` | Tên template đã tồn tại trong Venue này. |
| `60014` | Template đang có một Draft mở. Publish hoặc huỷ Draft hiện tại trước khi tạo Draft mới. |
| `60023` | Chỉ publish được version đang Draft. |
| `60024` | Version chưa có ghế nào (cần ít nhất một Floor/Section/Seat). |
| `60033` | Chỉ huỷ được version đang Draft (Published là bất biến). |
| `60045` | CanvasWidth/CanvasHeight phải lớn hơn 0. |
| `60047` | FloorKey đã tồn tại trong version này. |
| `60048` | FloorOrder đã được dùng bởi Floor khác trong version này. |
| `60054` | Chỉ xoá được Floor của version đang Draft. |
| `60063` | Chỉ sửa được Object của version đang Draft. |
| `60064` | ObjectType không hợp lệ. |
| `60065` | GeometryJson không đúng cấu trúc. |
| `60066` | Hình không lồi — StagePass chỉ hỗ trợ va chạm chính xác cho hình lồi. |
| `60067` | Object nằm ngoài canvas của Floor. |
| `60069` / `60092` / `60121` | Chỉ Admin được xoá TemplateObject / TemplateSection / TemplateSeat. |
| `60096` | Mỗi khu vật lý chỉ được gán cho một Section trong cùng một phiên bản mẫu sơ đồ. |
| `60108` | SeatKey đã tồn tại trong Section này. |
| `60109` | Ô lưới (RowLabel, SeatNumber) này đã có ghế khác trong Section. |

### 13.3. Sơ đồ của concert (ConcertMap)

| Mã | Thông báo |
|---|---|
| `60203` | Concert này đã có ConcertMap. |
| `60204` | Chỉ tạo được sơ đồ cho Concert đang ở trạng thái Draft hoặc Published. |
| `60205` | Concert đã có ghế trong kho vé theo đường Zone/Seat — không thể bật StagePass cho cùng Concert. |
| `60213` | Concert chưa được gán Venue. |
| `60215` | Chỉ được snapshot từ VenueTemplateVersion đang Published. |
| `60216` | VenueTemplate nguồn không thuộc đúng Venue của Concert. |
| `60217` | Map đang có một Draft mở. Khoá (Lock) hoặc huỷ Draft hiện tại trước khi tạo Draft mới. |
| `60233` | Chỉ Lock được revision đang Draft. |
| `60234` | Revision chưa có ghế nào (cần ít nhất một Floor/Section/Seat). |
| `60235` / `60236` | Mỗi sơ đồ chỉ khoá được đúng một bản, và phải khoá khi Concert còn ở trạng thái Draft hoặc Published. |
| `60237` | Chỉ huỷ được bản sơ đồ đang ở trạng thái nháp; bản đã khoá là sơ đồ đang bán của sự kiện. |
| `60238` | Bản sơ đồ này đã có ghế được đưa vào kho vé nên không thể huỷ. |
| `60242` | Chỉ được đưa ghế vào kho vé từ revision đang Locked. |
| `60244` | Chỉ thêm EventSeat khi Concert ở trạng thái Draft hoặc Published. |
| `60245` | TicketCategory không thuộc Concert hoặc không Active. |
| `60248` | Có ghế đã được đưa vào kho vé từ trước. |
| `60249` | Có Seat hoặc Zone đã Retired, không thể đưa vào kho vé. |
| `58221` | Concert này dùng StagePass — hãy đưa ghế vào kho vé từ sơ đồ đã khoá, không thêm trực tiếp theo Zone. |

### 13.4. Vòng đời concert

| Mã | Thông báo |
|---|---|
| `58002` / `58013` | EndDatetime phải sau StartDatetime. |
| `58007` | SaleEndDatetime phải sau hoặc bằng SaleStartDatetime. |
| `58011` | Chỉ sửa được Concert ở trạng thái Draft hoặc Published. |
| `58012` / `58022` | Bạn không có quyền cập nhật Concert này. |
| `58023` | Chưa thể mở bán: Concert chưa có kho vé (EventSeat) nào. |
| `58024` | Chưa thể mở bán: Concert chưa cấu hình thời gian bắt đầu/kết thúc bán vé. |
| `58061` | Sơ đồ StagePass phải được khoá (Lock) trước khi mở bán. |
| `58062` / `58063` | Mọi ghế trong kho vé phải được gắn với sơ đồ StagePass đã khoá trước khi mở bán. |
| `58208` | Không thể ngừng bán hạng vé khi còn ghế đang được giữ hoặc đã bán. |
| `58213` | TicketCategory không thuộc Concert hoặc không Active. |
| `58218` | Chỉ thêm ghế vào kho vé khi Concert ở trạng thái Draft hoặc Published. |
| `58222` | Danh sách SeatID chứa giá trị không phải số nguyên. |

### 13.5. Người dùng

| Mã | Thông báo |
|---|---|
| `58401` | Chỉ Admin được gán/thu hồi Role. |
| `58403` | Role không tồn tại hoặc không Active. |
| `58404` | Không được gán Role cho tài khoản hệ thống. |
| `58406` | Không thể thu hồi Role Admin của Admin đang hoạt động cuối cùng. |

### 13.6. Khuyến mãi

| Mã | Thông báo |
|---|---|
| `58303` | DiscountType phải là 'Percentage' hoặc 'Fixed Amount'. |
| `58304` | DiscountValue phải lớn hơn 0. |
| `58305` | EndDatetime phải sau StartDatetime. |
| `58601` | Bạn không có quyền với Promotion này. |
| `58603` | ValidToDatetime phải sau ValidFromDatetime. |
| `58604` | Mã giảm giá đã tồn tại. |

---

## 14. Những việc Admin KHÔNG làm được (và vì sao)

Các mục dưới đây **không phải lỗi** — chúng là giới hạn có chủ đích hoặc phần chưa
được xây. Biết trước để không mất thời gian đi tìm.

### 14.1. Giới hạn có chủ đích (sẽ không có)

| Không có | Lý do |
|---|---|
| **Khu đứng / General Admission** | Hệ thống chỉ mô hình hoá khu có ghế đánh số (`59831`). Vé đứng cần mô hình kho vé riêng, chưa được xây |
| **Xoá địa điểm / nghệ sĩ / khu / ghế** | Chỉ có "ngừng dùng" (`Inactive` / `Retired`). Xoá sẽ phá vỡ dữ liệu lịch sử của các concert đã bán |
| **Sửa hoặc khôi phục revision đã `Locked`** | Bản đã khoá chính là sơ đồ đang bán — sửa nó là làm vé đã phát hành hiển thị sai vị trí |
| **Tạo revision `Locked` thứ hai cho cùng map** | `UIX_CMR_OneLockedPerMap` bảo đảm mỗi map chỉ một bản công khai |
| **Mã vé (QR) trong báo cáo** | Mã vé là *bearer credential*; chỉ giao cho khách và nhân viên soát vé tại cổng |
| **Sửa giá từng ghế** | Giá ở hạng vé là nguồn sự thật duy nhất và lan xuống mọi ghế (BR10a) |
| **Hình học ở trang Danh mục** | Cột hình học của `Zone` và `sp_ConfigureVenueMap` không còn đường ghi từ ứng dụng. Hình học thật đi qua Mẫu sơ đồ |

### 14.2. Chưa được xây (có thể bổ sung sau)

| Chưa có | Thực trạng |
|---|---|
| **Danh bạ người dùng** | Không có endpoint liệt kê/tìm kiếm tài khoản → phải gõ UserID bằng số (mục 5.4) |
| **Sửa email / tên hiển thị của người dùng** | Không có đường nào. Chọn email cẩn thận ngay từ đầu |
| **Đặt lại mật khẩu cho người dùng** | Không có. Người dùng tự đổi qua luồng của họ |
| **Giá theo hàng ghế** | Chỉ theo hạng vé / khu |
| **Gắn ghế hàng loạt vào khu của mẫu sơ đồ** | Hiện gắn từng ghế; danh sách tải tối đa 200 ghế/lượt |
| **Hold nội bộ theo danh tính** | Chỉ có `Unavailable` + lý do. Không lưu ai đang giữ, không có hạn giữ |
| **Cửa sổ presale riêng theo mã** | Có `DiscountCode` + cờ yêu cầu mã, nhưng không có mở-bán-sớm theo thời gian |
| **Chuyển nhượng / bán lại vé** | Chưa có, và tài liệu thiết kế nói rõ **không nên làm** trước khi hold/payment/ticket vững |
| **Upload floor plan (ảnh)** | Sơ đồ được **vẽ** bằng hình học, không phải tải ảnh lên |
| **Migration lược đồ** | `deploy.ps1` chỉ đúng cho database **trống**. Lên DB đang chạy phải viết migration riêng |

---

## 15. Trình tự một concert mới — checklist

### Giai đoạn 1: Chuẩn bị hạ tầng (làm một lần, dùng lại nhiều concert)

- [ ] Tạo **Nghệ sĩ** (`/admin/catalog`)
- [ ] Tạo **Địa điểm** (`/admin/catalog`)
- [ ] Tạo **Khu** cho địa điểm đó — đủ khu theo bố trí thật
- [ ] Tạo **Ghế** cho từng khu (dùng khối **Tạo hàng loạt**: tiền tố + danh sách hàng `A-H` + khoảng số — tối đa 3.600 ghế mỗi lần)
- [ ] Vào `/admin/venue-templates`: tạo **Mẫu sơ đồ** → **Version Draft** →
      **Tầng** (canvas) → **Vật thể** (sân khấu, lối đi…) → **Khu** gắn đúng Zone
      → **Ghế** vào khu
- [ ] Kiểm tra sơ đồ trong trình duyệt trước khi công bố
- [ ] **Publish** version

### Giai đoạn 2: Tạo và chuẩn bị concert

- [ ] **Tạo concert** — chọn nghệ sĩ, địa điểm, thời lượng, giá, chính sách
- [ ] Đặt **"Mở bán từ"** và **"Đóng bán lúc"** (thiếu là không mở bán được —
      `58024`)
- [ ] Đặt **"Tỷ lệ hoàn tiền (%)"** và **"Hạn hủy trước giờ diễn"** — đây là căn cứ
      duy nhất để tính tiền hoàn
- [ ] Tạo **hạng vé** với giá gốc
- [ ] Tạo **ConcertMap** → **revision từ version đã Published** → **Lock**
- [ ] **Đưa ghế từ revision vào kho vé** theo từng hạng vé
- [ ] Xác nhận **mọi ghế trong kho vé đều đã gắn với ghế trên sơ đồ đã khoá** (còn ghế chưa gắn thì chưa mở bán được — `58062`/`58063`)
- [ ] Khoá ghế giữ cho ban tổ chức / ghế hỏng **bằng `Unavailable` + lý do**
      (làm trước khi mở bán)
- [ ] Cấu hình hàng đợi / danh sách chờ (nếu bật)
- [ ] Tạo **khuyến mãi** và **mã giảm giá** (nếu có)
- [ ] Kiểm tra trạng thái khuyến mãi là `Active`

### Giai đoạn 3: Mở bán và vận hành

- [ ] Chuyển trạng thái `Draft → Published` (đây là lúc mọi cổng được kiểm tra)
- [ ] Chuyển `Published → OnSale`. Nếu đã đặt "Mở bán từ", tiến trình nền SIP5
      cũng có thể tự mở đúng giờ
- [ ] Cấp vai trò **Check-in Staff** cho nhân viên (`/admin/users`)
- [ ] **Phân công** nhân viên cho concert — nhân viên không được phân công sẽ bị
      cổng từ chối
- [ ] Theo dõi **Báo cáo** và **Nhật ký kiểm toán**

### Giai đoạn 4: Sau khi hết chỗ

- [ ] Bật **Waitlist** để xử lý ghế trả lại (cơ hội có hạn 15 phút, tự chuyển tiếp)
- [ ] Xử lý **yêu cầu hoàn tiền** ở `/admin/refunds`
- [ ] Sau khi diễn ra: chuyển `OnSale → SaleClosed → Completed`
- [ ] Đối chiếu **báo cáo check-in** với số vé đã phát hành

---

## 16. Những điều dễ sai nhất

| Tình huống | Điều xảy ra | Cách tránh |
|---|---|---|
| Tạo khu đứng (/GA) | Bị từ chối `59831` | Dùng khu có ghế đánh số |
| Tạo khu + ghế ở Danh mục rồi tưởng bán được | Kho vé đầy ghế nhưng khách **thấy "sơ đồ đang hoàn thiện" và không chọn được gì** | Phải vẽ sơ đồ ở **Mẫu sơ đồ** rồi chụp vào concert (mục 4 và 7) |
| Tự hỏi vì sao phải "gắn ghế" lần thứ hai | Đó là **hai thứ khác nhau**: ghế vật lý vs vị trí ghế trên bản vẽ | Xem bảng ba lớp ở đầu mục 3 |
| Vào Danh mục tìm chỗ kéo-thả sơ đồ | Biểu mẫu không có trường hình học | Hình học nằm ở **Mẫu sơ đồ** |
| Mở bán quên đặt "Mở bán từ" | Bị từ chối `58024` | Đặt cả hai mốc ngay khi tạo concert |
| Mở bán khi còn ghế chưa vào kho | Bị từ chối `58062`/`58063` | Nạp hết ghế từ revision trước khi mở bán |
| Chụp nhầm version nguồn rồi bấm Lock | **Không sửa, không huỷ được** — phải làm concert mới | Kiểm tra sơ đồ **trước** khi Lock |
| Chụp nhầm nhưng **chưa** Lock | Huỷ nháp (`60237`/`60238`) rồi chụp lại | Xử lý trước khi thêm ghế vào kho |
| Đã thêm ghế kiểu cũ rồi muốn bật StagePass | Bị từ chối `60205` | Chọn một đường ngay từ đầu |
| Sửa giá mong muốn chỉ đổi một ghế | Giá lan xuống **toàn bộ** ghế của hạng đó | Tạo hạng vé riêng cho nhóm ghế có giá khác |
| Thu hồi vai trò Admin của chính mình | Nếu là Admin cuối cùng → `58406` | Cấp Admin cho người thứ hai trước |
| Gõ `FIXED` / `FixedAmount` cho kiểu giảm giá | Bị `CHECK` constraint từ chối | Dùng đúng `Fixed Amount` (có dấu cách) |
| Muốn cấp quyền cho người dùng nhưng không biết UserID | Không có danh bạ | Tra `SELECT UserID, Username FROM UserAccount;` |
| Chạy `setup.ps1` lên DB đang có dữ liệu | **Dừng lại**, không tự xoá | Muốn xoá sạch: thêm `-ResetDatabase` |

---

## 17. Tài liệu liên quan

| Tài liệu | Khi cần xem |
|---|---|
| [README](../README.md) | Cài đặt, mô hình nghiệp vụ, ràng buộc vận hành |
| [Kiến trúc StagePass](stagepass-architecture.md) | Thiết kế sâu của venue template, revision và sơ đồ phía khách |
| [Hướng dẫn thiết lập phát triển](developer_setup_guide.md) | Môi trường phát triển và kiểm tra cục bộ |
