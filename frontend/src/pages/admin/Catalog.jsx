import { useState } from 'react';
import api from '../../api/client';
import { useCatalog } from '../../lib/localCatalog';
import { useArtists, useVenues } from '../../lib/adminCatalog';
import { Field, Select, Panel, Banner, IdPicker, IdPill, useAction } from '../../components/form';
import {
  ArtistStatus, VenueStatus, ZoneStatus, SeatStatus, ADMIN_STATUS_LABEL,
} from '../../domain/enums';

/**
 * Danh mục nền: Nghệ sĩ · Địa điểm · Khu vực · Ghế.
 *
 * Thứ tự trên trang cố tình đi theo đúng thứ tự phụ thuộc của database:
 * Venue → Zone → Seat. Không thể tạo Zone khi chưa có Venue, và Seat luôn thuộc về
 * một Zone (khoá ngoại, không phải quy ước). Đặt đúng thứ tự thì người dùng khỏi
 * phải đoán nên bắt đầu từ đâu.
 *
 * Sửa danh mục chỉ dành cho Admin — đúng như `[Authorize(Roles = "Admin")]` trên
 * các endpoint PUT. Organizer vẫn tạo được (endpoint POST mở cho cả hai vai trò).
 */
export default function Catalog({ isAdmin }) {
  return (
    <>
      <ArtistSection isAdmin={isAdmin} />
      <VenueSection isAdmin={isAdmin} />
      <ZoneSection isAdmin={isAdmin} />
      <SeatSection isAdmin={isAdmin} />
    </>
  );
}

/* ── Nghệ sĩ ─────────────────────────────────────────────────────────────── */

function ArtistSection({ isAdmin }) {
  // Đọc thật từ CSDL (GET /admin/artists), không phải sổ tay localStorage: trước đây
  // trang này tự tạo nghệ sĩ xong lại KHÔNG hiện nó ra sau khi tải lại trang hay xoá
  // sổ tay — trong khi Concerts.jsx đã dùng đúng nguồn này để chọn nghệ sĩ khi tạo
  // concert. Cùng một dữ liệu, hai nguồn khác nhau là lỗi, không phải lựa chọn.
  const artists = useArtists();
  const items = artists.items;
  const create = useAction();
  const update = useAction();

  const [name, setName] = useState('');
  const [desc, setDesc] = useState('');

  const [editId, setEditId] = useState('');
  const [editName, setEditName] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [editStatus, setEditStatus] = useState('');

  const submitCreate = (e) => {
    e.preventDefault();
    create.run(async () => {
      const res = await api.post('/admin/artists', {
        artistName: name.trim(),
        artistDescription: desc.trim() || null,
      });
      // Nạp lại ngay từ máy chủ thay vì tự chèn vào state cục bộ: nguồn sự thật duy
      // nhất bây giờ là CSDL, và POST đã commit xong trước khi trả response.
      artists.reload();
      setName(''); setDesc('');
      return res.data.id;
    }, (id) => `Đã tạo nghệ sĩ. ID = ${id} — đã có trong danh mục để chọn khi tạo concert.`);
  };

  const submitUpdate = (e) => {
    e.preventDefault();
    update.run(async () => {
      // NULL nghĩa là "giữ nguyên" (UpdateArtistRequest), nên chỉ gửi trường có nhập.
      await api.put(`/admin/artists/${Number(editId)}`, {
        artistName: editName.trim() || null,
        artistDescription: editDesc.trim() || null,
        artistStatus: editStatus || null,
      });
      artists.reload();
      return Number(editId);
    }, (id) => `Đã cập nhật nghệ sĩ #${id}.`);
  };

  return (
    <>
      <Panel
        title="Nghệ sĩ"
        subtitle="Concert bắt buộc trỏ tới một nghệ sĩ, nên đây thường là bước đầu tiên khi dựng dữ liệu."
      >
        <form onSubmit={submitCreate}>
          <div className="field-grid">
            <Field label="Tên nghệ sĩ" required>
              <input value={name} onChange={(e) => setName(e.target.value)} maxLength={255} required />
            </Field>
            <Field label="Mô tả">
              <input value={desc} onChange={(e) => setDesc(e.target.value)} />
            </Field>
          </div>
          <button className="btn-primary" style={{ marginTop: '16px' }} disabled={create.busy || !name.trim()}>
            {create.busy ? 'Đang tạo…' : 'Tạo nghệ sĩ'}
          </button>
          <Banner state={create.state} />
        </form>
        {items.length > 0 && (
          <Recent items={items} label="nghệ sĩ"
                  caption={`${items.length} nghệ sĩ trong hệ thống (đọc từ CSDL)`} />
        )}
      </Panel>

      {isAdmin && (
        <Panel
          title="Cập nhật nghệ sĩ"
          subtitle="Bỏ trống ô nào thì trường đó giữ nguyên. Đặt trạng thái Retired để ngừng dùng nghệ sĩ trong concert mới (BR50e)."
        >
          <form onSubmit={submitUpdate}>
            <IdPicker label="Nghệ sĩ cần sửa" items={items} value={editId} onChange={setEditId} />
            <div className="field-grid" style={{ marginTop: '16px' }}>
              <Field label="Tên mới"><input value={editName} onChange={(e) => setEditName(e.target.value)} /></Field>
              <Field label="Mô tả mới"><input value={editDesc} onChange={(e) => setEditDesc(e.target.value)} /></Field>
              <Field label="Trạng thái">
                <Select
                  value={editStatus} onChange={setEditStatus} allowEmpty
                  options={Object.values(ArtistStatus)} labels={ADMIN_STATUS_LABEL}
                />
              </Field>
            </div>
            <button className="btn-primary" style={{ marginTop: '16px' }} disabled={update.busy || !editId}>
              {update.busy ? 'Đang lưu…' : 'Lưu thay đổi'}
            </button>
            <Banner state={update.state} />
          </form>
        </Panel>
      )}
    </>
  );
}

/* ── Địa điểm ────────────────────────────────────────────────────────────── */

function VenueSection({ isAdmin }) {
  // Đọc thật từ CSDL — cùng lý do như ArtistSection ở trên.
  const venuesDb = useVenues();
  const items = venuesDb.items;
  const create = useAction();
  const update = useAction();

  const [name, setName] = useState('');
  const [address, setAddress] = useState('');

  const [editId, setEditId] = useState('');
  const [editName, setEditName] = useState('');
  const [editAddress, setEditAddress] = useState('');
  const [editStatus, setEditStatus] = useState('');

  return (
    <>
      <Panel title="Địa điểm" subtitle="Địa điểm chứa các khu vực (Zone), khu vực chứa ghế. Concert trỏ tới một địa điểm.">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            create.run(async () => {
              const res = await api.post('/admin/venues', {
                venueName: name.trim(),
                address: address.trim() || null,
              });
              venuesDb.reload();
              setName(''); setAddress('');
              return res.data.id;
            }, (id) => `Đã tạo địa điểm. ID = ${id}. Bước tiếp theo: tạo khu, tạo ghế, `
                     + `rồi khai báo sơ đồ — chưa có sơ đồ thì khách chỉ thấy danh sách khu.`);
          }}
        >
          <div className="field-grid">
            <Field label="Tên địa điểm" required>
              <input value={name} onChange={(e) => setName(e.target.value)} maxLength={255} required />
            </Field>
            <Field label="Địa chỉ">
              <input value={address} onChange={(e) => setAddress(e.target.value)} />
            </Field>
          </div>
          <button className="btn-primary" style={{ marginTop: '16px' }} disabled={create.busy || !name.trim()}>
            {create.busy ? 'Đang tạo…' : 'Tạo địa điểm'}
          </button>
          <Banner state={create.state} />
        </form>
        {items.length > 0 && (
          <Recent items={items} label="địa điểm"
                  caption={`${items.length} địa điểm trong hệ thống (đọc từ CSDL)`} />
        )}
      </Panel>

      {isAdmin && (
        <Panel
          title="Cập nhật địa điểm"
          subtitle="Đổi địa điểm bị chặn nếu concert đã có ghế trong kho vé — trigger TRG_ConcertVenueChangeGuard sẽ từ chối."
        >
          <form
            onSubmit={(e) => {
              e.preventDefault();
              update.run(async () => {
                await api.put(`/admin/venues/${Number(editId)}`, {
                  venueName: editName.trim() || null,
                  address: editAddress.trim() || null,
                  venueStatus: editStatus || null,
                });
                venuesDb.reload();
                return Number(editId);
              }, (id) => `Đã cập nhật địa điểm #${id}.`);
            }}
          >
            <IdPicker label="Địa điểm cần sửa" items={items} value={editId} onChange={setEditId} />
            <div className="field-grid" style={{ marginTop: '16px' }}>
              <Field label="Tên mới"><input value={editName} onChange={(e) => setEditName(e.target.value)} /></Field>
              <Field label="Địa chỉ mới"><input value={editAddress} onChange={(e) => setEditAddress(e.target.value)} /></Field>
              <Field label="Trạng thái">
                <Select value={editStatus} onChange={setEditStatus} allowEmpty
                        options={Object.values(VenueStatus)} labels={ADMIN_STATUS_LABEL} />
              </Field>
            </div>
            <button className="btn-primary" style={{ marginTop: '16px' }} disabled={update.busy || !editId}>
              {update.busy ? 'Đang lưu…' : 'Lưu thay đổi'}
            </button>
            <Banner state={update.state} />
          </form>
        </Panel>
      )}
    </>
  );
}

/* ── Khu vực ─────────────────────────────────────────────────────────────── */

function ZoneSection({ isAdmin }) {
  // Ô "Thuộc địa điểm" đọc CSDL — cùng lý do như ArtistSection/VenueSection.
  // Bản thân Zone thì CHƯA có đường đọc phẳng (chỉ có GET theo từng địa điểm), nên
  // danh mục Khu vực để sửa/chọn tiếp ở đây vẫn phải dùng sổ tay — xem ghi chú ở
  // đầu file localCatalog.js.
  const venues = useVenues();
  const { items, remember } = useCatalog('zone');
  const create = useAction();
  const update = useAction();

  const [venueId, setVenueId] = useState('');
  const [code, setCode] = useState('');
  const [name, setName] = useState('');

  const [editId, setEditId] = useState('');
  const [editName, setEditName] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [editStatus, setEditStatus] = useState('');

  return (
    <>
      <Panel title="Khu vực (Zone)" subtitle="Mỗi khu vực thuộc về một địa điểm. Ghế được tạo bên trong khu vực.">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            create.run(async () => {
              const res = await api.post(`/admin/venues/${Number(venueId)}/zones`, {
                zoneCode: code.trim(),
                zoneName: name.trim() || null,
              });
              // Ghi kèm ĐỊA ĐIỂM vào nhãn: hai địa điểm khác nhau đều có thể có khu mã
              // 'A', và khi đó danh sách chọn ở phần tạo ghế hiện hai dòng giống hệt
              // nhau — người dùng không có cách nào biết mình đang đổ ghế vào khu nào.
              const venueName = venues.items.find((v) => String(v.id) === String(venueId))?.name;
              remember({
                id: res.data.id,
                name: `${code.trim()}${name.trim() ? ` — ${name.trim()}` : ''}`
                    + ` · ${venueName ?? `địa điểm #${venueId}`}`,
              });
              setCode(''); setName('');
              return res.data.id;
            }, (id) => `Đã tạo khu vực. ID = ${id} — dùng ID này để tạo ghế bên dưới.`);
          }}
        >
          <IdPicker label="Thuộc địa điểm" items={venues.items} value={venueId} onChange={setVenueId} />
          <div className="field-grid" style={{ marginTop: '16px' }}>
            <Field label="Mã khu vực" hint="Ví dụ: VIP, A, STAND-B" required>
              <input value={code} onChange={(e) => setCode(e.target.value)} maxLength={64} required />
            </Field>
            <Field label="Tên hiển thị"><input value={name} onChange={(e) => setName(e.target.value)} /></Field>
          </div>
          <button className="btn-primary" style={{ marginTop: '16px' }} disabled={create.busy || !venueId || !code.trim()}>
            {create.busy ? 'Đang tạo…' : 'Tạo khu vực'}
          </button>
          <Banner state={create.state} />
        </form>
        {items.length > 0 && <Recent items={items} label="khu vực" />}
      </Panel>

      {isAdmin && (
        <Panel title="Cập nhật khu vực" subtitle="Trạng thái Retired để ngừng dùng khu vực.">
          <form
            onSubmit={(e) => {
              e.preventDefault();
              update.run(async () => {
                await api.put(`/admin/zones/${Number(editId)}`, {
                  zoneName: editName.trim() || null,
                  zoneDescription: editDesc.trim() || null,
                  zoneStatus: editStatus || null,
                });
                return Number(editId);
              }, (id) => `Đã cập nhật khu vực #${id}.`);
            }}
          >
            <IdPicker label="Khu vực cần sửa" items={items} value={editId} onChange={setEditId} />
            <div className="field-grid" style={{ marginTop: '16px' }}>
              <Field label="Tên mới"><input value={editName} onChange={(e) => setEditName(e.target.value)} /></Field>
              <Field label="Mô tả"><input value={editDesc} onChange={(e) => setEditDesc(e.target.value)} /></Field>
              <Field label="Trạng thái">
                <Select value={editStatus} onChange={setEditStatus} allowEmpty
                        options={Object.values(ZoneStatus)} labels={ADMIN_STATUS_LABEL} />
              </Field>
            </div>
            <button className="btn-primary" style={{ marginTop: '16px' }} disabled={update.busy || !editId}>
              {update.busy ? 'Đang lưu…' : 'Lưu thay đổi'}
            </button>
            <Banner state={update.state} />
          </form>
        </Panel>
      )}
    </>
  );
}

/* ── Ghế ─────────────────────────────────────────────────────────────────── */

function SeatSection({ isAdmin }) {
  const zones = useCatalog('zone');
  const { items, remember } = useCatalog('seat');
  const create = useAction();
  const bulk = useAction();
  const update = useAction();

  const [zoneId, setZoneId] = useState('');
  const [code, setCode] = useState('');
  const [label, setLabel] = useState('');
  // Ghế trong khu có ghế BẮT BUỘC có vị trí trên lưới (sp_CreateSeat, 59825): thiếu
  // vị trí thì sơ đồ dồn mọi ghế về cùng một ô và chúng chồng khít lên nhau.
  const [row, setRow] = useState('A');
  const [col, setCol] = useState('1');

  const [bulkPrefix, setBulkPrefix] = useState('');
  const [bulkRow, setBulkRow] = useState('A');
  const [bulkFrom, setBulkFrom] = useState('1');
  const [bulkTo, setBulkTo] = useState('12');

  const [editId, setEditId] = useState('');
  const [editLabel, setEditLabel] = useState('');
  const [editStatus, setEditStatus] = useState('');

  /**
   * Tạo hàng loạt: API chỉ có endpoint tạo MỘT ghế, nên phần lặp nằm ở đây.
   * Gọi tuần tự chứ không song song — mỗi lời gọi là một transaction riêng, bắn
   * song song hàng chục request chỉ làm tăng tranh chấp khoá mà không nhanh hơn
   * đáng kể, và khi lỗi giữa chừng thì khó nói được đã tạo tới đâu.
   */
  const submitBulk = (e) => {
    e.preventDefault();
    const from = Number(bulkFrom);
    const to = Number(bulkTo);
    bulk.run(async () => {
      const created = [];
      for (let i = from; i <= to; i += 1) {
        const seatCode = `${bulkPrefix.trim()}${i}`;
        const res = await api.post(`/admin/zones/${Number(zoneId)}/seats`, {
          seatCode,
          seatLabel: seatCode,
          // Cả loạt nằm trên CÙNG một hàng; số chạy của loạt chính là số thứ tự
          // trong hàng, nên sơ đồ vẽ ra đúng một dãy ghế liền nhau.
          seatRowLabel: bulkRow.trim(),
          seatColumnNumber: i,
        });
        remember({ id: res.data.id, name: seatCode });
        created.push(res.data.id);
      }
      return created;
    }, (ids) => `Đã tạo ${ids.length} ghế (ID ${ids[0]}–${ids[ids.length - 1]}).`);
  };

  const rangeValid = Number(bulkTo) >= Number(bulkFrom) && Number(bulkTo) - Number(bulkFrom) < 200;
  // Gương lại luật 59821 của sp_CreateSeat: hàng và cột đi thành cặp. Chặn ở đây để
  // người dùng thấy ngay khi đang gõ, chứ không phải sau một vòng gọi API hỏng.
  const positionHalfFilled = !row.trim() !== !col.trim();

  return (
    <>
      <Panel title="Ghế" subtitle="Ghế là tài sản của địa điểm, chưa gắn giá. Giá chỉ xuất hiện khi ghế được đưa vào một concert (EventSeat).">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            create.run(async () => {
              const res = await api.post(`/admin/zones/${Number(zoneId)}/seats`, {
                seatCode: code.trim(),
                seatLabel: label.trim() || null,
                // Bỏ trống cả hai = ghế không có vị trí, chỉ hợp lệ với khu vé đứng.
                seatRowLabel: row.trim() || null,
                seatColumnNumber: col.trim() ? Number(col) : null,
              });
              remember({ id: res.data.id, name: code.trim() });
              setCode(''); setLabel('');
              // Giữ nguyên hàng, tăng cột: tạo liên tiếp A1, A2, A3… không phải gõ lại.
              if (col.trim()) setCol(String(Number(col) + 1));
              return res.data.id;
            }, (id) => `Đã tạo ghế. ID = ${id}.`);
          }}
        >
          <IdPicker label="Thuộc khu vực" items={zones.items} value={zoneId} onChange={setZoneId} />
          <div className="field-grid" style={{ marginTop: '16px' }}>
            <Field label="Mã ghế" required>
              <input value={code} onChange={(e) => setCode(e.target.value)} maxLength={64} required />
            </Field>
            <Field label="Nhãn hiển thị"><input value={label} onChange={(e) => setLabel(e.target.value)} /></Field>
            <Field label="Hàng" hint="Vị trí trên sơ đồ. Khu vé đứng: để trống cả hai ô.">
              <input value={row} onChange={(e) => setRow(e.target.value)} maxLength={8} />
            </Field>
            <Field label="Số thứ tự trong hàng">
              <input type="number" min="1" value={col} onChange={(e) => setCol(e.target.value)} />
            </Field>
          </div>
          <button className="btn-primary" style={{ marginTop: '16px' }} disabled={create.busy || !zoneId || !code.trim() || positionHalfFilled}>
            {create.busy ? 'Đang tạo…' : 'Tạo một ghế'}
          </button>
          {positionHalfFilled && (
            <div className="field-hint" style={{ color: 'var(--warning)' }}>
              Hàng và số thứ tự đi thành cặp: điền cả hai, hoặc bỏ trống cả hai.
            </div>
          )}
          <Banner state={create.state} />
        </form>

        <hr style={{ border: 'none', borderTop: '1px dashed var(--border-focus)', margin: '24px 0' }} />

        <form onSubmit={submitBulk}>
          <h4 style={{ marginBottom: '6px', fontSize: '0.9375rem' }}>Tạo hàng loạt</h4>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.8125rem', marginBottom: '16px' }}>
            API chỉ tạo được từng ghế một, nên phần lặp do giao diện làm và gọi tuần tự.
            Dựng một khu 12 ghế bằng tay là 12 lần điền form — đây là chỗ đáng tự động.
          </p>

          {/* Cùng một biến zoneId với form bên trên, cố ý. Trước đây ô chọn khu chỉ có ở
              form "Tạo một ghế", còn phần tạo hàng loạt dùng ké mà không hiện gì — nhìn
              vào đây không biết ghế sẽ vào khu nào, và chưa chọn khu thì nút chỉ bị mờ
              đi không kèm lý do. Hiện lại ngay tại chỗ đang thao tác; sửa ở một trong
              hai nơi thì nơi kia đổi theo, nên không thể lệch nhau. */}
          <IdPicker label="Thuộc khu vực" items={zones.items} value={zoneId} onChange={setZoneId} />

          <div className="field-grid" style={{ marginTop: '16px' }}>
            <Field label="Tiền tố mã ghế" hint="Ví dụ 'A' sẽ ra A1, A2, A3…" required>
              <input value={bulkPrefix} onChange={(e) => setBulkPrefix(e.target.value)} maxLength={32} required />
            </Field>
            <Field label="Hàng" hint="Cả loạt nằm trên cùng một hàng của sơ đồ." required>
              <input value={bulkRow} onChange={(e) => setBulkRow(e.target.value)} maxLength={8} required />
            </Field>
            <Field label="Từ số"><input type="number" min="1" value={bulkFrom} onChange={(e) => setBulkFrom(e.target.value)} /></Field>
            <Field label="Đến số"><input type="number" min="1" value={bulkTo} onChange={(e) => setBulkTo(e.target.value)} /></Field>
          </div>
          <button
            className="btn-outline"
            style={{ marginTop: '16px' }}
            disabled={bulk.busy || !zoneId || !bulkPrefix.trim() || !bulkRow.trim() || !rangeValid}
          >
            {bulk.busy ? 'Đang tạo hàng loạt…' : `Tạo ${Math.max(0, Number(bulkTo) - Number(bulkFrom) + 1)} ghế`}
          </button>
          {!zoneId && (
            <div className="field-hint" style={{ color: 'var(--warning)' }}>
              Chọn khu vực ở trên trước — ghế phải nằm trong một khu cụ thể.
            </div>
          )}
          {!rangeValid && (
            <div className="field-hint" style={{ color: 'var(--warning)' }}>
              Khoảng số không hợp lệ (tối đa 200 ghế mỗi lần).
            </div>
          )}
          <Banner state={bulk.state} />
        </form>

        {items.length > 0 && <Recent items={items} label="ghế" />}
      </Panel>

      {isAdmin && (
        <Panel title="Cập nhật ghế" subtitle="Trạng thái Retired dành cho ghế đã tháo dỡ khỏi địa điểm (FR11).">
          <form
            onSubmit={(e) => {
              e.preventDefault();
              update.run(async () => {
                await api.put(`/admin/seats/${Number(editId)}`, {
                  seatLabel: editLabel.trim() || null,
                  seatStatus: editStatus || null,
                });
                return Number(editId);
              }, (id) => `Đã cập nhật ghế #${id}.`);
            }}
          >
            <IdPicker label="Ghế cần sửa" items={items} value={editId} onChange={setEditId} />
            <div className="field-grid" style={{ marginTop: '16px' }}>
              <Field label="Nhãn mới"><input value={editLabel} onChange={(e) => setEditLabel(e.target.value)} /></Field>
              <Field label="Trạng thái">
                <Select value={editStatus} onChange={setEditStatus} allowEmpty
                        options={Object.values(SeatStatus)} labels={ADMIN_STATUS_LABEL} />
              </Field>
            </div>
            <button className="btn-primary" style={{ marginTop: '16px' }} disabled={update.busy || !editId}>
              {update.busy ? 'Đang lưu…' : 'Lưu thay đổi'}
            </button>
            <Banner state={update.state} />
          </form>
        </Panel>
      )}
    </>
  );
}

/* ── Danh sách vừa tạo ───────────────────────────────────────────────────── */

function Recent({ items, label, caption }) {
  return (
    <div style={{ marginTop: '20px', paddingTop: '16px', borderTop: '1px solid var(--border-subtle)' }}>
      <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginBottom: '8px' }}>
        {caption ?? `${items.length} ${label} đã tạo từ trình duyệt này`}
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
        {items.slice(0, 24).map((it) => (
          <IdPill key={it.id}>#{it.id} · {it.name}</IdPill>
        ))}
      </div>
    </div>
  );
}
