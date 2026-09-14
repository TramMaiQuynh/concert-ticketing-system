import { useState } from 'react';
import api from '../../api/client';
import { useAdminCatalog } from '../../lib/adminCatalog';
import { useArtists, useVenues } from '../../lib/adminCatalog';
import { findSameNameArtists } from '../../lib/artistName';
import { seatBatchPlan } from '../../lib/seatCode';
import { Field, Select, Panel, Banner, IdPicker, IdPill, useAction } from '../../components/form';
import { Alert, Button, PageHeader } from '../../components/ui';
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
 * Toàn bộ trang này chỉ dành cho Admin: các endpoint PUT đều mang
 * `[Authorize(Roles = "Admin")]`, và POST cũng không đồng nhất — `artists` cùng
 * `zones/{id}/seats/batch` yêu cầu Admin, số còn lại mở cho cả Organizer ở tầng
 * controller rồi được stored procedure kiểm quyền lại lần nữa.
 * Organizer không vào được trang này; họ chọn nghệ sĩ và địa điểm có sẵn ngay trong
 * biểu mẫu tạo concert.
 */
export default function Catalog({ isAdmin }) {
  if (!isAdmin) {
    return (
      <>
        <PageHeader title="Danh mục" subtitle="Dữ liệu nền của venue do Admin quản lý một lần và được chọn lại khi tạo concert." />
        <Panel tone="workflow" title="Danh mục dùng chung">
          <p className="field-hint">Organizer chọn nghệ sĩ và địa điểm có sẵn trong biểu mẫu tạo concert. Tạo hoặc sửa venue, khu vật lý và ghế vật lý là quyền Admin.</p>
        </Panel>
      </>
    );
  }
  return (
    <>
      <PageHeader title="Danh mục" subtitle="Nghệ sĩ, địa điểm, khu vực và ghế — theo đúng thứ tự phụ thuộc: Venue → Zone → Seat." />
      <ArtistSection isAdmin={isAdmin} />
      <VenueSection isAdmin={isAdmin} />
      <ZoneSection isAdmin={isAdmin} />
      <SeatSection isAdmin={isAdmin} />
    </>
  );
}

/* ── Nghệ sĩ ─────────────────────────────────────────────────────────────── */

function ArtistSection({ isAdmin }) {
  // Đọc thật từ CSDL (GET /admin/artists) — cùng nguồn mà Concerts.jsx dùng để chọn
  // nghệ sĩ khi tạo concert. Một dữ liệu chỉ có MỘT nguồn: lưu tạm ở localStorage sẽ
  // tạo ra nguồn thứ hai lệch nhau, và đó là lỗi chứ không phải lựa chọn.
  const artists = useArtists({ includeInactive: true });
  const items = artists.items;
  const create = useAction();
  const update = useAction();

  const [name, setName] = useState('');
  const [desc, setDesc] = useState('');

  const [editId, setEditId] = useState('');
  const [editName, setEditName] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [editStatus, setEditStatus] = useState('');

  // "Tìm trước khi tạo" — PHẢI nằm sau khai báo `name` ở trên: biến `const` không đọc
  // được trước dòng khai báo của chính nó.
  // Dùng bản ghi thô từ máy chủ (artists.raw) chứ không dùng items đã gắn nhãn, vì
  // nhãn có kèm trạng thái ("Sơn Tùng · Active") và sẽ làm so tên sai.
  // Cảnh báo MỀM: tên trùng vẫn tạo được, vì chặn cứng sẽ chặn nhầm hai nghệ sĩ thật
  // sự khác nhau — đúng lý do sp_CreateArtist không đặt UNIQUE.
  const sameNameArtists = findSameNameArtists(name, artists.raw);

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
        tone="create"
        subtitle="Concert có thể gắn nhiều nghệ sĩ. Tạo danh mục trước để chọn đầy đủ dàn nghệ sĩ khi lập concert."
      >
        <form onSubmit={submitCreate}>
          <div className="field-grid">
            <Field label="Tên nghệ sĩ" required>
              <input value={name} onChange={(e) => setName(e.target.value)} maxLength={255} required />
            </Field>
            <Field label="Mô tả">
              <input value={desc} onChange={(e) => setDesc(e.target.value)} maxLength={500} />
            </Field>
          </div>
          <Button type="submit" variant="primary" loading={create.busy} disabled={!name.trim()} style={{ marginTop: '16px' }}>
            Tạo nghệ sĩ
          </Button>
          <Banner state={create.state} />
          {sameNameArtists.length > 0 && (
            <Alert tone="warning" style={{ marginTop: 'var(--space-4)' }}>
              Đã có {sameNameArtists.length} nghệ sĩ cùng tên trong danh mục:{' '}
              {sameNameArtists.map((a) => `#${a.artistID} ${a.artistName}`).join(', ')}.
              {' '}Vẫn tạo được, nhưng hai bản ghi cùng một nghệ sĩ sẽ làm báo cáo theo
              nghệ sĩ tách thành nhiều dòng.
            </Alert>
          )}
        </form>
        {items.length > 0 && (
          <Recent items={items} label="nghệ sĩ"
                  caption={`${items.length} nghệ sĩ trong hệ thống (đọc từ CSDL)`} />
        )}
      </Panel>

      {isAdmin && (
        <Panel
          title="Cập nhật nghệ sĩ"
          tone="edit"
          subtitle="Bỏ trống ô nào thì trường đó giữ nguyên. Đặt trạng thái Retired để ngừng dùng nghệ sĩ trong concert mới (BR50e)."
        >
          <form onSubmit={submitUpdate}>
            <IdPicker label="Nghệ sĩ cần sửa" items={items} value={editId} onChange={setEditId} />
            <div className="field-grid" style={{ marginTop: '16px' }}>
              <Field label="Tên mới"><input value={editName} onChange={(e) => setEditName(e.target.value)} maxLength={255} /></Field>
              <Field label="Mô tả mới"><input value={editDesc} onChange={(e) => setEditDesc(e.target.value)} maxLength={500} /></Field>
              <Field label="Trạng thái">
                <Select
                  value={editStatus} onChange={setEditStatus} allowEmpty
                  options={Object.values(ArtistStatus)} labels={ADMIN_STATUS_LABEL}
                />
              </Field>
            </div>
            <Button type="submit" variant="primary" loading={update.busy} disabled={!editId} style={{ marginTop: '16px' }}>
              Lưu thay đổi
            </Button>
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
  const venuesDb = useVenues({ includeInactive: true });
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
      <Panel tone="create" title="Địa điểm" subtitle="Địa điểm chứa các khu vực (Zone), khu vực chứa ghế. Concert trỏ tới một địa điểm.">
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
              <input value={address} onChange={(e) => setAddress(e.target.value)} maxLength={500} />
            </Field>
          </div>
          <Button type="submit" variant="primary" loading={create.busy} disabled={!name.trim()} style={{ marginTop: '16px' }}>
            Tạo địa điểm
          </Button>
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
          tone="edit"
          subtitle="Bỏ trống ô nào thì trường đó giữ nguyên. Đặt trạng thái Inactive để ngừng dùng địa điểm cho concert mới (BR50e) — không ngưng được địa điểm đang có concert chưa kết thúc."
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
              <Field label="Tên mới"><input value={editName} onChange={(e) => setEditName(e.target.value)} maxLength={255} /></Field>
              <Field label="Địa chỉ mới"><input value={editAddress} onChange={(e) => setEditAddress(e.target.value)} maxLength={500} /></Field>
              <Field label="Trạng thái">
                <Select value={editStatus} onChange={setEditStatus} allowEmpty
                        options={Object.values(VenueStatus)} labels={ADMIN_STATUS_LABEL} />
              </Field>
            </div>
            <Button type="submit" variant="primary" loading={update.busy} disabled={!editId} style={{ marginTop: '16px' }}>
              Lưu thay đổi
            </Button>
            <Banner state={update.state} />
          </form>
        </Panel>
      )}
    </>
  );
}

/* ── Khu vực ─────────────────────────────────────────────────────────────── */

function ZoneSection({ isAdmin }) {
  const zones = useAdminCatalog('zone');
  const { items } = zones;
  const venues = useVenues();
  const create = useAction();
  const update = useAction();

  const [venueId, setVenueId] = useState('');
  const [zoneCode, setZoneCode] = useState('');
  const [zoneName, setZoneName] = useState('');
  const [editId, setEditId] = useState('');
  const [editName, setEditName] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [editStatus, setEditStatus] = useState('');

  return (
    <>
      <Panel tone="create" title="Khu vật lý" subtitle="Tạo khu thuộc venue. Hình dạng và tầng của khu chỉ được đặt trong Bản vẽ địa điểm.">
        <form onSubmit={(e) => {
          e.preventDefault();
          create.run(async () => {
            const res = await api.post(`/admin/venues/${Number(venueId)}/zones`, {
              zoneCode: zoneCode.trim(), zoneName: zoneName.trim() || null,
            });
            await zones.reload();
            setZoneCode(''); setZoneName('');
            return res.data.id;
          }, (id) => `Đã tạo khu vật lý #${id}. Tiếp theo, tạo ghế cho khu này rồi đặt khu lên Bản vẽ địa điểm.`);
        }}>
          <div className="field-grid">
            <IdPicker label="Địa điểm" items={venues.items} value={venueId} onChange={setVenueId} />
            <Field label="Mã khu" required><input value={zoneCode} onChange={(e) => setZoneCode(e.target.value)} maxLength={64} required /></Field>
            <Field label="Tên khu"><input value={zoneName} onChange={(e) => setZoneName(e.target.value)} maxLength={255} /></Field>
          </div>
          <Button type="submit" variant="primary" loading={create.busy} disabled={!venueId || !zoneCode.trim()} style={{ marginTop: '16px' }}>Tạo khu</Button>
          <Banner state={create.state} />
        </form>
        {items.length > 0 ? (
          <Recent items={items} label="khu vật lý" />
        ) : (
          <p className="field-hint">Chưa có khu vật lý nào.</p>
        )}
      </Panel>

      {isAdmin && (
        <Panel tone="edit" title="Cập nhật khu vực" subtitle="Trạng thái Retired để ngừng dùng khu vực.">
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
              <Field label="Tên mới"><input value={editName} onChange={(e) => setEditName(e.target.value)} maxLength={255} /></Field>
              <Field label="Mô tả"><input value={editDesc} onChange={(e) => setEditDesc(e.target.value)} maxLength={500} /></Field>
              <Field label="Trạng thái">
                <Select value={editStatus} onChange={setEditStatus} allowEmpty
                        options={Object.values(ZoneStatus)} labels={ADMIN_STATUS_LABEL} />
              </Field>
            </div>
            <Button type="submit" variant="primary" loading={update.busy} disabled={!editId} style={{ marginTop: '16px' }}>
              Lưu thay đổi
            </Button>
            <Banner state={update.state} />
          </form>
        </Panel>
      )}
    </>
  );
}

/* ── Ghế ─────────────────────────────────────────────────────────────────── */

function SeatSection({ isAdmin }) {
  const seats = useAdminCatalog('seat');
  const { items } = seats;
  const zones = useAdminCatalog('zone');
  const create = useAction();
  const batch = useAction();
  const update = useAction();

  const [zoneId, setZoneId] = useState('');
  const [prefix, setPrefix] = useState('');
  const [row, setRow] = useState('');
  const [column, setColumn] = useState('');
  const [batchRow, setBatchRow] = useState('');
  const [batchStart, setBatchStart] = useState('1');
  const [batchEnd, setBatchEnd] = useState('');
  const [editId, setEditId] = useState('');
  const [editLabel, setEditLabel] = useState('');
  const [editStatus, setEditStatus] = useState('');

  // Kế hoạch cho CẢ HAI form, tính bằng CÙNG một hàm (lib/seatCode.js): form đơn lẻ
  // chỉ là trường hợp một hàng × một số. Nhờ vậy hai form không thể sinh ra hai kiểu
  // mã khác nhau. `blocked` cũng chính là câu hiện ra cho người dùng, nên nút không
  // bao giờ xám mà không nói vì sao.
  // Hai form không có ô "Nhãn ghế": nhãn do lib/seatCode.js đặt bằng CHÍNH mã ghế, nên
  // ghế luôn có tên hiển thị; muốn nhãn khác mã thì sửa ở khối "Cập nhật ghế".
  // Cùng một câu giải thích cho ô "Tiền tố mã ghế" ở CẢ HAI form: hai form dùng chung
  // một bộ trường thì cũng phải giải thích giống nhau.
  const prefixHint = 'Ví dụ Vip. Hệ thống tự thêm dấu gạch rồi hàng và số → Vip-A1';
  const singlePlan = seatBatchPlan({ zoneId, prefix, rows: row, start: column, end: column, singleSeat: true });
  const batchPlan = seatBatchPlan({
    zoneId, prefix, rows: batchRow, start: batchStart, end: batchEnd,
  });

  return (
    <>
      <Panel tone="create" title="Ghế vật lý" subtitle="Ghế thuộc một khu vật lý, có hàng và số ghế. Giá chỉ xuất hiện khi ghế được đưa vào một concert.">
        <form onSubmit={(e) => {
          e.preventDefault();
          create.run(async () => {
            const res = await api.post(`/admin/zones/${Number(zoneId)}/seats`, {
              ...singlePlan.entries[0],
            });
            await seats.reload();
            setRow(''); setColumn('');
            return res.data.id;
          }, (id) => `Đã tạo ghế vật lý #${id}.`);
        }}>
          <div className="field-grid">
            <IdPicker label="Khu vật lý" items={zones.items} value={zoneId} onChange={setZoneId} />
            <Field label="Tiền tố mã ghế" required hint={prefixHint}><input value={prefix} onChange={(e) => setPrefix(e.target.value)} maxLength={64} required /></Field>
            <Field label="Hàng" required hint="Một hàng duy nhất, ví dụ A. Muốn nhiều hàng thì dùng khối bên dưới."><input value={row} onChange={(e) => setRow(e.target.value)} maxLength={16} required /></Field>
            <Field label="Số ghế" required><input type="number" min="1" value={column} onChange={(e) => setColumn(e.target.value)} required /></Field>
          </div>
          <Button type="submit" variant="primary" loading={create.busy} disabled={singlePlan.blocked !== null} style={{ marginTop: '16px' }}>Tạo ghế</Button>
          {singlePlan.blocked
            ? <p className="field-hint">{singlePlan.blocked}</p>
            : <p className="field-hint">{singlePlan.preview}</p>}
          <Banner state={create.state} />
        </form>
        <form onSubmit={(e) => {
          e.preventDefault();
          // Kế hoạch đã tính ở trên, bằng CÙNG hàm với form đơn lẻ (lib/seatCode.js).
          batch.run(async () => {
            // Dùng CHÍNH kế hoạch đã quyết định nút có bấm được hay không: nếu dựng
            // payload ở một chỗ khác thì có ngày nút cho bấm mà gửi lên danh sách khác.
            const entries = batchPlan.entries;
            await api.post(`/admin/zones/${Number(zoneId)}/seats/batch`, { seats: entries });
            await seats.reload();
            setBatchEnd('');
            return entries.length;
          }, (count) => `Đã tạo nguyên tử ${count} ghế trong khu đã chọn.`);
        }} style={{ marginTop: '24px' }}>
          <div className="overline" style={{ marginBottom: '12px' }}>Tạo nhiều hàng ghế một lúc</div>
          <IdPicker label="Khu vật lý" items={zones.items} value={zoneId} onChange={setZoneId} />
          <div className="field-grid">
            <Field label="Tiền tố mã ghế" required hint={prefixHint}><input value={prefix} onChange={(e) => setPrefix(e.target.value)} placeholder="Vip" maxLength={64} required /></Field>
            <Field label="Danh sách hàng" required hint="Một hàng (A), một khoảng (A-H), hoặc nhiều mục (A,B,D-H)."><input value={batchRow} onChange={(e) => setBatchRow(e.target.value)} placeholder="A-H" required /></Field>
            <Field label="Từ số ghế" required><input type="number" min="1" value={batchStart} onChange={(e) => setBatchStart(e.target.value)} required /></Field>
            <Field label="Đến số ghế" required><input type="number" min="1" value={batchEnd} onChange={(e) => setBatchEnd(e.target.value)} required /></Field>
          </div>
          <Button type="submit" variant="secondary" loading={batch.busy} disabled={batchPlan.blocked !== null} style={{ marginTop: '16px' }}>Tạo hàng loạt</Button>
          {batchPlan.blocked
            ? <p className="field-hint">{batchPlan.blocked}</p>
            : <p className="field-hint">{batchPlan.preview}</p>}
          <Banner state={batch.state} />
        </form>
        {items.length > 0 ? (
          <Recent items={items} label="ghế vật lý" />
        ) : (
          <p className="field-hint">Chưa có ghế vật lý nào.</p>
        )}
      </Panel>

      {isAdmin && (
        <Panel tone="edit" title="Cập nhật ghế" subtitle="Trạng thái Retired dành cho ghế đã tháo dỡ khỏi địa điểm (FR11).">
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
              <Field label="Nhãn mới"><input value={editLabel} onChange={(e) => setEditLabel(e.target.value)} maxLength={255} /></Field>
              <Field label="Trạng thái">
                <Select value={editStatus} onChange={setEditStatus} allowEmpty
                        options={Object.values(SeatStatus)} labels={ADMIN_STATUS_LABEL} />
              </Field>
            </div>
            <Button type="submit" variant="primary" loading={update.busy} disabled={!editId} style={{ marginTop: '16px' }}>
              Lưu thay đổi
            </Button>
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
        {caption ?? `${items.length} ${label} trong hệ thống`}
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
        {items.slice(0, 24).map((it) => (
          <IdPill key={it.id}>#{it.id} · {it.name}</IdPill>
        ))}
      </div>
    </div>
  );
}
