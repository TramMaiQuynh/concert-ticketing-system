# Venue template có phiên bản cho StagePass

## Quyết định kiến trúc

StagePass nên dùng **venue template có phiên bản bất biến**. Một venue có thể có nhiều template, như \`End stage\`, \`Theatre\` hoặc \`In-the-round\`; mỗi template có nhiều version. Admin dựng Draft từ floor plan và publish version. Organizer chỉ chọn version Published của đúng venue. Khi chọn template, concert tạo map revision Draft; revision được snapshot và khóa khi concert OnSale.

Giá, ticket category, hold, availability và thay đổi riêng của show nằm ở snapshot concert. Template gốc không bị sửa. Đây là năng lực vận hành tương đương các hệ thống lớn, không sao chép giao diện, nhãn hiệu, hình minh họa hay tài sản độc quyền của Ticketmaster/Eventbrite.

## Kết quả nghiên cứu

Ticketmaster mô tả event template là nơi lưu seat map, giá, offer và attraction để tái sử dụng; công cụ của họ cho chỉnh floor layout, section và inventory trực quan. Eventbrite tách venue map/reserved seating khỏi event: organizer chọn hoặc tạo venue map trước, rồi gắn ticket type vào tier/section.

Nguồn chính thức: [Ticketmaster: template và floor editing](https://business.ticketmaster.com/3-key-features-for-simple-event-creation/), [Ticketmaster: event template](https://business.ticketmaster.com/improve-your-day-to-day-with-ticketmasters-event-creation-tool/), [Eventbrite: reserved seating](https://www.eventbrite.com/features/reserved-seating/), và [Eventbrite: tạo reserved-seating event](https://www.eventbrite.com/help/en-us/articles/454462/how-to-create-a-reserved-seating-event-on-eventbrite-music/).

Do đó phải tách ba lớp:

1. Bản vẽ venue: tài sản vận hành, tái sử dụng được.
2. Cấu hình concert: giá, hold, availability và thay đổi chỉ của show đó.
3. Giao diện khách mua vé: chỉ đọc snapshot đã khóa, không đọc template đang sửa.

## Khoảng cách với hệ thống hiện tại

Chuỗi hiện có \`Venue → Zone → Seat → EventSeat\` là đúng: \`EventSeat\` là inventory theo concert. Tuy nhiên map public đang đọc geometry trực tiếp từ \`Venue\`, \`Zone\`, \`Seat\`. Model hiện chỉ biểu đạt rectangle/rotation; đổi stage, zone hoặc cải tạo venue có thể làm concert cũ hiển thị theo layout mới. Nó cũng không biểu đạt được lối đi, shape vòng cung, bàn, ban công, khu khuyết hay shape theo bản vẽ. Không giải quyết bằng cách thêm thêm tọa độ vào \`Zone\`.

## Mô hình dữ liệu đích

\`Venue\`, \`Zone\`, \`Seat\`, \`Concert\`, \`EventSeat\` tiếp tục là dữ liệu nghiệp vụ. Các bảng mới là lớp đồ họa và snapshot; \`EventSeat\` vẫn là nguồn sự thật về giá và availability.

\`\`\`mermaid
erDiagram
    Venue ||--o{ VenueTemplate : owns
    VenueTemplate ||--o{ VenueTemplateVersion : versions
    VenueTemplateVersion ||--|{ TemplateFloor : contains
    TemplateFloor ||--o{ TemplateObject : draws
    TemplateFloor ||--|{ TemplateSection : contains
    TemplateSection ||--o{ TemplateSeat : contains
    Concert }o--|| VenueTemplateVersion : selected_version
    Concert ||--|| ConcertMap : owns
    ConcertMap ||--o{ ConcertMapRevision : versions
    ConcertMapRevision ||--|{ ConcertMapSection : contains
    ConcertMapSection ||--o{ ConcertMapSeat : contains
    ConcertMapSeat ||--o| EventSeat : represents
\`\`\`

| Bảng | Nội dung và quy tắc |
| --- | --- |
| \`VenueTemplate\` | Identity ổn định: venue, tên template, trạng thái \`Active/Archived\`. Một venue có nhiều template. |
| \`VenueTemplateVersion\` | \`VersionNumber\`, status \`Draft/Published/Retired\`, author, publish time, \`rowversion\`. Chỉ Draft sửa được; Published là bất biến. |
| \`TemplateFloor\` | \`FloorKey\`, tên, thứ tự, canvas riêng, background asset. Các tầng không chồng lên nhau trên một canvas. |
| \`TemplateObject\` | Stage, aisle, wall, entrance, restroom, bar, text/icon; geometry và z-index. |
| \`TemplateSection\` | Section có polygon/path, mã và tên ổn định; không giới hạn rectangle. |
| \`TemplateSeat\` | \`SeatKey\`, \`SeatID\` là identity inventory hiện có, row, number, geometry chính xác, accessible/companion flags. SeatID có thể biểu diễn ghế cố định hoặc một vị trí ghế trong cấu hình production; không được coi mặc định là chiếc ghế vật lý cố định. Row generator phải materialize thành ghế khi publish. |
| \`ConcertMap\` | Root một-một với Concert; giữ identity của map concert. |
| \`ConcertMapRevision\` | Nguồn template version, revision number, trạng thái \`Draft/Locked/Replaced\`, thời điểm snapshot. Chỉ một revision có thể được dùng để bán. |
| \`ConcertMapRevisionFloor/Object/Section/Seat\` | Bản sao map khách thấy; có source ID để truy vết nhưng không phụ thuộc source sau khi snapshot. |

\`ConcertMapSeat\` chứa \`SeatID\` và map đến một \`EventSeat\` chỉ khi ghế được đưa vào bán. Mỗi \`SeatID\` chỉ được xuất hiện một lần trong một template version và một lần trong một concert-map revision. Không để \`Concert\` trỏ thẳng template rồi đọc template lúc checkout. Điều này bảo toàn ticket PDF, refund, check-in và báo cáo nếu venue phát hành version mới.

\`GeometryJson\` dùng format nội bộ có version: rectangle, polygon, path, circle. Backend validate geometry. Không render SVG upload tùy ý: phải sanitize và loại script/external reference; an toàn hơn là rasterize floor plan thành PNG/WebP nền, còn lớp tương tác do StagePass tạo.

### Ràng buộc tích hợp với schema hiện tại

Trong database hiện tại, \`EventSeat\` có foreign key đến \`Seat\`; \`Seat\` lại thuộc \`Zone\` và \`Venue\`. Vì vậy không thể chỉ thêm bảng đồ họa rồi coi \`TemplateSeat\` là một ghế mới độc lập. Với lộ trình chuyển đổi an toàn, \`TemplateSeat.SeatID\` phải tham chiếu identity inventory hiện có, còn \`ConcertMapSeat\` sao chép chính \`SeatID\`, nhãn và geometry tại thời điểm tạo revision. Các ghế production tạm thời cũng phải được materialize thành SeatID trước khi bán; không tạo SeatID lúc khách checkout.

Stored procedure thay thế \`sp_AddEventSeats\` sẽ nhận \`ConcertMapSeatID\` thay vì SeatID thô, sau đó trong **cùng transaction** kiểm tra map revision thuộc concert, map cùng venue, SeatID cùng venue và chưa có EventSeat trước khi insert. Điều này giữ nguyên quy tắc EventSeat hiện có, đồng thời chặn organizer gắn một SeatID ngoài map hoặc từ venue khác vào concert. Zone/Seat geometry hiện tại được coi là legacy trong giai đoạn cutover; public map phải đọc revision, không đọc geometry legacy.

## Luồng vận hành

### Dựng template một lần

1. Admin chọn venue, tạo template và Draft \`v1\`.
2. Upload bản vẽ mặt bằng cho từng tầng. Hệ thống tạo asset bất biến, preview, thumbnail và content hash.
3. Studio hiển thị bản vẽ làm background; admin kéo-thả stage, aisle, section, nhãn và POI. Không bắt admin nhập X/Y.
4. Ghế tạo bằng row tool, curved row tool, table tool, import CSV, duplicate/mirror/rotate, sau đó gán row/seat label.
5. Client báo ngay khi thao tác tạo overlap cấm; server kiểm tra lại khi save để chống bypass và race condition.
6. Validate kiểm tra: ngoài canvas, polygon tự cắt, overlap, seat key trùng, seat ngoài section, aisle bị che, section rỗng và capacity không khớp.
7. Chỉ template không có lỗi mới Publish. Sửa tiếp tạo \`v2\` từ \`v1\`, không sửa trực tiếp bản đã publish.

### Tạo concert và cấu hình inventory

1. Organizer tạo concert, API chỉ trả template Published của đúng venue.
2. Chọn version sẽ tạo ConcertMapRevision ở trạng thái Draft. Organizer tạo ticket category và chọn section/ghế trên map để thêm inventory trong transaction.
3. Giá, hold và offer hiện bằng legend/màu. Capacity và doanh thu dự kiến cập nhật ngay khi chọn.
4. Trước OnSale, validate mọi \`EventSeat\` có map-seat hợp lệ, category active, price và sale window đầy đủ. Concert có thể Published trong lúc cấu hình; chỉ khi OnSale mới khóa ConcertMapRevision đang chọn.
5. Khi OnSale, API public chỉ đọc revision Locked và trạng thái \`EventSeat\`; tải overview theo floor/section trước, chỉ tải ghế khi khách mở section.

Không thay đổi vị trí một \`EventSeat\` đã Booked. Thay đổi hình học sau khi revision đã Locked phải tạo event-map revision Draft kế tiếp và cần audit/lifecycle riêng; revision mới không thay thế revision đang OnSale khi còn vé, hold hoặc booking hiệu lực. Sau OnSale chỉ nên cho phép block/unblock theo chính sách rõ ràng.

## Onboard một venue mới

Venue mới không cần có sẵn trong thư viện. Quy trình vận hành là:

1. Admin tạo record Venue ở trạng thái setup và thu nhận bản vẽ được venue cho phép sử dụng: một file cho mỗi tầng, kèm tên section, hàng/ghế, stage, aisle, lối vào và khu accessible nếu có.
2. Admin tạo VenueTemplate, ví dụ Theatre layout, rồi tạo Draft v1. Bản vẽ là nền để dựng object, section shape, hàng và ghế trực quan.

### Bản vẽ mặt bằng lấy từ đâu

Nguồn ưu tiên là **venue owner hoặc đội vận hành venue**: hồ sơ kiến trúc/CAD, PDF mặt bằng, bản seating manifest, sơ đồ thoát hiểm và layout vận hành hiện hành. Với một show có stage hoặc sàn ghế thay đổi, promoter/production manager cung cấp thêm **event production layout**; đây là đầu vào cho một template khác hoặc event-map revision.

Thứ tự nguồn nên dùng:

1. Bản vẽ được phê duyệt của venue/kiến trúc sư: DWG/DXF, Revit export, PDF vector hoặc SVG.
2. Seating chart/manifest vận hành đang dùng tại venue, đối chiếu lại với thực địa.
3. Sơ đồ production của tour hoặc đơn vị dựng sân khấu cho từng cấu hình event.
4. Khảo sát hiện trường có đo đạc, ảnh và xác nhận bằng văn bản của venue cho venue nhỏ chưa có hồ sơ số.
5. Đơn vị map/CAD được thuê để số hóa bản vẽ đã được venue phê duyệt.

Không dùng ảnh Google, screenshot trang bán vé khác, ảnh quảng cáo hoặc AI sinh ảnh làm nguồn layout. Chúng có thể sai, không có quyền sử dụng và không đủ độ chính xác để bán ghế.

StagePass tiếp nhận một asset cho mỗi tầng, kèm metadata: nguồn/cơ quan cung cấp, ngày hiệu lực, revision, đơn vị tỉ lệ, người xác nhận và quyền sử dụng. DWG/DXF không đưa thẳng vào browser; backend chuyển đổi có kiểm soát sang PDF/SVG an toàn hoặc PNG/WebP để làm background. Layer section/seat tương tác vẫn do StagePass lưu riêng và validate; bản vẽ chỉ là reference layer.

Nếu venue không có bất cứ sơ đồ nào, đội vận hành phải khảo sát rồi ký xác nhận sơ đồ v1 trước khi Publish. Độ chân thật khách mua vé nhận được không thể cao hơn độ tin cậy của dữ liệu venue cung cấp.

Sau khi bản vẽ đã được xác nhận:

1. Chạy validate, người thứ hai review nếu venue lớn, sau đó publish v1. Từ đây template có thể được tái sử dụng cho mọi concert ở venue đó.
2. Organizer tạo concert và chọn v1. Nếu tour diễn có stage khác hoặc bố cục khác, admin tạo một template khác, như End-stage v1; không sửa ngược Theatre v1.
3. Khi venue cải tạo, copy version mới nhất sang v2, chỉnh và publish. Concert đã publish vẫn giữ snapshot cũ.

Không nên mở bán reserved seating tại một venue chưa có Published template. Có thể cho phép concert tồn tại ở Draft hoặc Published để nhập thông tin chương trình, nhưng chặn OnSale đến khi concert có map revision hợp lệ. Khi bổ sung General Admission, venue chưa có sơ đồ ghế vẫn có thể bán GA qua một GA template đã publish có area/capacity được xác nhận; không dùng layout giả.

Ở hệ thống hiện tại chỉ có Admin và Organizer. Vì vậy Admin chịu trách nhiệm dựng/publish template; Organizer chỉ chọn template Published của venue concert mình sở hữu. Nếu sau này có role Venue Manager, role đó chỉ được quản lý template của những venue được phân công, còn Organizer vẫn không sửa layout dùng chung.


## Hợp đồng trải nghiệm bản đồ khách mua vé

Luồng bạn mô tả là đúng mục tiêu cho StagePass. Đây là **progressive drill-down**, không phải một sơ đồ duy nhất được phóng to:

1. **Overview — chọn khu:** khách thấy toàn bộ venue/floor với stage, section label và màu availability. Mỗi section là hotspot vector. Nhấn một section mở detail của chính section đó; map không tải hàng nghìn ghế ở bước này.
2. **Detail — chọn ghế:** chỉ tải geometry của khu đã chọn và seat status theo thời gian thực. Khách pan/zoom, chọn ghế, xem row/seat/price/category và thêm vào giỏ.
3. **Minimap:** cùng hệ tọa độ với overview; nó hiển thị viewport hiện tại bằng một khung chữ nhật. Nút Home quay về map tổng quan để chọn khu khác. Minimap là control đồng bộ của camera, không phải ảnh trang trí hay nguồn dữ liệu thứ hai.
4. **Quay lại:** Home giữ floor và filter trước đó trên overview, để khách không bị mất ngữ cảnh. Không có nút phóng to/thu nhỏ riêng.

### Dữ liệu phục vụ đúng hai cấp

| API | Dữ liệu trả về | Không được trả về |
| --- | --- | --- |
| GET /concerts/{id}/seat-map | snapshot version, floor, stage/object, section path/hotspot, label, availability summary, price range, state | toàn bộ ghế của venue |
| GET /concerts/{id}/seat-map/floors/{floorKey}/sections/{sectionKey} | section geometry, rows/aisles, ghế, accessibility flag, trạng thái, price/category và canonical viewport | ghế ở section/floor khác |
| POST /bookings | nhận public identity của ConcertMapSeat; server resolve EventSeat đúng concert rồi gọi transaction tạo Booking/hold đang có | không tin trạng thái/mức giá do browser gửi |

Overview bắt buộc dùng TemplateSection.GeometryJson/ConcertMapSection.GeometryJson; detail dùng ConcertMapSeat.GeometryJson. Một section có thể là vòng cung, hình quạt hoặc shape theo bản vẽ, nên không được suy luận sơ đồ ghế từ rectangle hiện có. Client chỉ nhận public map-seat identity; Booking API resolve nó về EventSeat trong transaction hiện có, không để browser chọn EventSeatID tùy ý.

Màu là trạng thái có ý nghĩa, không phải màu trang trí: available, selected, held/sold/unavailable, accessible và companion phải có legend, tooltip/text thay thế và độ tương phản đủ dùng. Ghế accessible không chỉ đổi màu mà có shape/icon cùng nhãn đọc được bằng screen reader. Seat map phải có keyboard/list alternative cho người không thể thao tác trên canvas; các control chạm cần target đủ lớn. Click vào seat chỉ là chọn cục bộ; khi gửi Booking backend mới tạo hold atomically, nên màu xanh trên client không phải xác nhận mua vé.

### Sơ đồ không tự tạo ra “view from seat”

Floor plan chính xác cho biết vị trí tương đối, không tự chứng minh góc nhìn thật, độ che khuất, âm thanh hay khoảng cách cảm nhận. Nếu StagePass hiển thị “view from seat”, mỗi Section/ConcertMapSeat phải có media ảnh/video/360 hoặc render được venue/production xác nhận, version, ngày chụp/render và disclosure rõ ràng. Không được nội suy bằng AI rồi quảng bá là góc nhìn thật.

Các thay đổi production như camera platform, mix position, che khuất hoặc giảm tầm nhìn là thuộc ConcertMapRevision, không thuộc VenueTemplate chung. Chúng phải có cờ RestrictedView/ObstructedView, mô tả mua vé, audit và quy tắc không tự di chuyển các Booking hiện có. Khách phải thấy disclosure trước checkout; pricing/offer có thể phản ánh restriction đó.

### Collaboration, kiểm thử và release gate

Template editor cần autosave optimistic concurrency ở mức revision, nhưng save một batch geometry phải all-or-nothing. Khi hai người chỉnh cùng phần tử, server trả conflict với revision mới nhất; không merge tọa độ tự động. Presence/comment/live cursor chỉ là giai đoạn sau khi dữ liệu và conflict handling đã ổn định.

Release gate cho mỗi venue-template version gồm: validation topology; kiểm tra liên kết SeatID; visual-regression với floor plan đã duyệt; test booking cạnh tranh; test authorization giữa hai organizer; kiểm tra asset độc hại/không được phép; và kiểm thử keyboard, screen-reader, mobile. Việc chỉ render được map chưa đủ để publish một venue.


### General admission là luồng riêng

Ảnh có vùng GENERAL ADMISSION LAWN. Hệ thống hiện chỉ hỗ trợ ZoneType = Seated, vì vậy không được giả vờ rằng lawn là một tập ghế. Để hỗ trợ đúng thực tế, cần thêm EventAdmissionArea/EventAdmissionInventory theo concert: area shape ở overview, capacity, sold/held/available counter, ticket category và quantity picker. Nhấn một area GA không đi vào seat-detail mà mở quantity flow. Reserved seating và GA dùng chung overview, nhưng inventory/hold khác nhau.

### Hiệu năng và tính nhất quán

- Overview trả summary theo section, cache được lâu hơn; status ghế detail có TTL ngắn và invalidation sau hold/release/book.
- Detail chỉ render ghế trong viewport; canvas/WebGL hoặc virtualized renderer được dùng khi section lớn.
- Viewport là transform client-side trên canonical geometry; minimap không cần endpoint thứ hai.
- Khi trạng thái ghế thay đổi trong lúc khách đang chọn, backend trả xung đột/hold failure rõ ràng và client làm mới đúng section, không xác nhận theo state cũ.


## API và bảo mật

| Nhóm endpoint | Kiểm tra bắt buộc |
| --- | --- |
| \`/admin/venues/{venueId}/templates\` | Admin; venue tồn tại. |
| \`/admin/template-versions/{id}/validate\` và \`/publish\` | Admin; chỉ Draft; publish transaction và audit. |
| \`/admin/template-assets\` | Admin; MIME/size limit, virus scan, sanitize/rasterize. |
| \`/organizer/venues/{venueId}/published-templates\` | Organizer chỉ đọc template Published để chọn. |
| \`/organizer/concerts/{id}/map-revisions\` | Organizer sở hữu concert; template cùng \`Concert.VenueID\`. |
| \`/organizer/concerts/{id}/map-revisions/{revisionId}/*\` | Organizer sở hữu concert; revision còn Draft. |
| \`/concerts/{id}/seat-map\` | Public, concert sellable; trả overview của revision Locked. |

Mọi lệnh ghi dùng ETag/\`rowversion\`; xung đột trả \`409\`, không ghi đè im lặng. Stored procedure nhận \`@ActorUserID\`, khóa row concert/template khi publish hay snapshot (\`UPDLOCK, HOLDLOCK\`), kiểm tra ownership trong transaction và ghi \`AuditRecord\`. Chỉ lọc React hoặc tin \`venueId\` trên URL là không đủ an toàn.

## Thứ tự triển khai

### Giai đoạn 0 — Chốt hợp đồng

- Chọn format asset/geometry, giới hạn canvas/số object/số ghế, policy upload, role và quy tắc thay đổi sau OnSale.
- Lấy bản vẽ thật của ít nhất ba loại: nhà hát nhiều tầng, arena end-stage, ballroom/table. Không thiết kế chỉ từ mock rectangle.
- Viết fixture và acceptance criteria từ các bản vẽ này.

### Giai đoạn 1 — Database và API lõi

- Thêm bảng template/version/floor/object/section/seat/concert-map-revision, foreign key, unique key, \`rowversion\`, soft archive và index truy vấn map.
- Viết stored procedure create draft, save batch, validate, publish, khóa concert revision và assign inventory theo section/seat selection.
- Đổi public seat-map query sang revision Locked, giữ contract cũ trong một API version để frontend chuyển đổi dần.

### Giai đoạn 2 — Venue Template Studio

- Floor navigator, layer panel, inspector, zoom/pan, snap/ruler, undo/redo, autosave debounce và conflict banner.
- Canvas/WebGL cho venue lớn; SVG phù hợp overview/map nhỏ. Culling và virtualization tránh tạo hàng chục nghìn DOM node.
- Validation trực tiếp khi kéo thả và validation authoritative ở server.

### Giai đoạn 3 — Concert map

- Chọn template trong concert wizard; preview version; tạo map revision Draft.
- Assign ticket category bằng lasso/brush, section/row selection, bulk action, legend/hold, revenue/capacity view và undo transaction.
- Lock lifecycle \`Draft → Published → OnSale\`; test concurrent assignment/hold.

### Giai đoạn 4 — Customer map và vận hành

- Floor-first overview, section hotspot, lazy seat detail, accessible list alternative, mobile pan/zoom và legend rõ ràng.
- Asset CDN/cache theo content hash; inventory status cache ngắn hạn và invalidate khi \`EventSeat\` đổi trạng thái.
- Event-specific blocks, production kills, audit, report theo section.

## Tiêu chí hoàn thành

1. Admin dựng theatre hai tầng từ floor plan mà không nhập tọa độ.
2. Section shape tự do, aisle, stage, tầng, ghế vòng cung/bàn hiển thị đúng và không có overlap trái quy tắc.
3. Hai concert dùng cùng \`v1\`; concert mới dùng \`v2\`; concert cũ giữ nguyên map lúc publish.
4. Organizer A không thể đọc/sửa template draft hoặc concert map của Organizer B.
5. Hai khách giữ cùng một ghế: chỉ một transaction thắng.
6. Map 10.000 ghế vẫn mở nhanh nhờ overview và lazy-load section.
7. Ticket, email, check-in, refund, report luôn trả floor/section/row/seat của snapshot, kể cả sau khi venue có version mới.
