import { useRef, useState, useEffect, useMemo, useCallback } from 'react';
import api from '../../api/client';
import { useAdminCatalog } from '../../lib/adminCatalog';
import { useConcertOptions, invalidateConcerts } from '../../lib/concertOptions';
import { useVenues, useArtists } from '../../lib/adminCatalog';
import { Field, Select, Check, Panel, Banner, IdPicker, MultiIdPicker, IdPill, useAction } from '../../components/form';
import { Button, PageHeader } from '../../components/ui';
import { toApiDateTime } from '../../lib/format';
import {
  ConcertStatus, CONCERT_STATUS_LABEL, CategoryStatus, QueueStatus, WaitlistStatus,
  AccessPolicy, ADMIN_STATUS_LABEL, InventoryStatus,
} from '../../domain/enums';

/** Concert quản trị gồm cả Draft, được máy chủ lọc theo quyền sở hữu. */
export default function Concerts() {
  return (
    <>
      <PageHeader title="Concert" subtitle="Vòng đời, hạng vé và kho ghế của từng sự kiện." />
      <CreateConcert />
      <UpdateConcert />
      <ConcertStatusSection />
      <CategorySection />
      <ConcertMapSection />
      <QueueSection />
      <WaitlistSection />
      <SeatAvailabilitySection />
    </>
  );
}

/* ── Tạo concert ─────────────────────────────────────────────────────────── */

function CreateConcert() {
  // Danh mục lấy TỪ MÁY CHỦ, không phải sổ tay trình duyệt: địa điểm do Admin
  // dựng trên máy khác vẫn phải hiện ra ở đây — đó là toàn bộ ý nghĩa của việc
  // "dựng một lần, các lần sau chỉ chọn".
  const artists = useArtists();
  const venues = useVenues();
  const act = useAction();

  const [f, setF] = useState({
    artistIds: [], venueId: '', concertName: '',
    startDatetime: '', endDatetime: '', saleStartDatetime: '', saleEndDatetime: '',
    purchaseLimit: '4', temporaryHoldDuration: '',
    fairAccessEnabled: false, waitlistEnabled: false, salesPaused: false,
    cancellationPolicy: '', refundPolicy: '',
    cancellationDeadlineHours: '', refundPercentage: '',
  });
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));

  const num = (v) => (String(v).trim() === '' ? null : Number(v));

  const submit = (e) => {
    e.preventDefault();
    act.run(async () => {
      const res = await api.post('/admin/concerts', {
        artistIds: f.artistIds.map(Number),
        venueId: Number(f.venueId),
        concertName: f.concertName.trim(),
        startDatetime: toApiDateTime(f.startDatetime),
        endDatetime: toApiDateTime(f.endDatetime),
        saleStartDatetime: toApiDateTime(f.saleStartDatetime),
        saleEndDatetime: toApiDateTime(f.saleEndDatetime),
        purchaseLimit: Number(f.purchaseLimit),
        temporaryHoldDuration: num(f.temporaryHoldDuration),
        fairAccessEnabled: f.fairAccessEnabled,
        waitlistEnabled: f.waitlistEnabled,
        salesPaused: f.salesPaused,
        cancellationPolicy: f.cancellationPolicy.trim() || null,
        refundPolicy: f.refundPolicy.trim() || null,
        cancellationDeadlineHours: num(f.cancellationDeadlineHours),
        refundPercentage: num(f.refundPercentage),
      });
      return res.data.id;
    }, (id) => `Đã tạo concert #${id} ở trạng thái Draft. Concert Draft KHÔNG hiện ở trang chủ — `
             + `hãy cấu hình hạng vé và ghế rồi chuyển sang Published ở khối bên dưới.`);
  };

  const ready = f.artistIds.length > 0 && f.venueId && f.concertName.trim() && f.startDatetime && f.endDatetime;

  return (
    <Panel
      title="Tạo concert"
      tone="create"
      subtitle="Concert luôn sinh ra ở trạng thái Draft — không nhận trường trạng thái lúc tạo, mọi chuyển trạng thái phải đi qua máy trạng thái (BR49)."
    >
      <form onSubmit={submit}>
        <div className="field-grid">
          <MultiIdPicker label="Nghệ sĩ biểu diễn" hint="Thứ tự này sẽ được hiển thị cùng concert."
                         items={artists.items} values={f.artistIds} onChange={set('artistIds')} />
          <IdPicker label="Địa điểm" items={venues.items} value={f.venueId} onChange={set('venueId')} />
        </div>

        <div style={{ marginTop: '16px' }}>
          <Field label="Tên concert" required>
            <input value={f.concertName} onChange={(e) => set('concertName')(e.target.value)} maxLength={255} required />
          </Field>
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Bắt đầu diễn" required>
            <input type="datetime-local" value={f.startDatetime} onChange={(e) => set('startDatetime')(e.target.value)} required />
          </Field>
          <Field label="Kết thúc diễn" required>
            <input type="datetime-local" value={f.endDatetime} onChange={(e) => set('endDatetime')(e.target.value)} required />
          </Field>
          <Field
            label="Mở bán từ"
            hint="CẦN CÓ trước khi mở bán: thiếu mốc này thì không chuyển sang OnSale được (BR10)."
          >
            <input type="datetime-local" value={f.saleStartDatetime} onChange={(e) => set('saleStartDatetime')(e.target.value)} />
          </Field>
          <Field label="Đóng bán lúc" hint="Cũng bắt buộc trước khi mở bán.">
            <input type="datetime-local" value={f.saleEndDatetime} onChange={(e) => set('saleEndDatetime')(e.target.value)} />
          </Field>
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Giới hạn vé / khách" hint="sp_CreateBooking từ chối bằng lỗi 51003 khi vượt (BR20).">
            <input type="number" min="1" value={f.purchaseLimit} onChange={(e) => set('purchaseLimit')(e.target.value)} />
          </Field>
          <Field label="Thời gian giữ chỗ (phút)" hint="Để trống thì dùng cấu hình chung của hệ thống.">
            <input type="number" min="1" value={f.temporaryHoldDuration} onChange={(e) => set('temporaryHoldDuration')(e.target.value)} />
          </Field>
          <Field label="Hạn hủy trước giờ diễn (giờ)" hint="Quá hạn này thì sp_ProcessRefund từ chối hoàn tiền (CI10).">
            <input type="number" min="0" value={f.cancellationDeadlineHours} onChange={(e) => set('cancellationDeadlineHours')(e.target.value)} />
          </Field>
          <Field label="Tỷ lệ hoàn tiền (%)" hint="0–100. Đây là căn cứ DUY NHẤT để tính số tiền hoàn (BR32a).">
            <input type="number" min="0" max="100" value={f.refundPercentage} onChange={(e) => set('refundPercentage')(e.target.value)} />
          </Field>
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Check
            label="Bật hàng đợi truy cập công bằng (Fair Access)"
            checked={f.fairAccessEnabled} onChange={set('fairAccessEnabled')}
            hint="Khách phải xếp hàng và được cấp lượt mới đặt được vé."
          />
          <Check
            label="Bật danh sách chờ (Waitlist)"
            checked={f.waitlistEnabled} onChange={set('waitlistEnabled')}
            hint="Khi hết ghế, khách đăng ký chờ theo hạng vé."
          />
          <Check
            label="Tạm dừng bán ngay"
            checked={f.salesPaused} onChange={set('salesPaused')}
            hint="Chặn đặt vé mà không đổi trạng thái concert."
          />
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Chính sách hủy (mô tả)">
            <textarea value={f.cancellationPolicy} onChange={(e) => set('cancellationPolicy')(e.target.value)} maxLength={500} />
          </Field>
          <Field label="Chính sách hoàn tiền (mô tả)">
            <textarea value={f.refundPolicy} onChange={(e) => set('refundPolicy')(e.target.value)} maxLength={500} />
          </Field>
        </div>

        <Button type="submit" variant="primary" loading={act.busy} disabled={!ready} style={{ marginTop: '20px' }}>
          Tạo concert
        </Button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Sửa concert ─────────────────────────────────────────────────────────── */

function UpdateConcert() {
  const { options } = useConcertOptions();
  const artists = useArtists();
  const venues = useVenues();
  const act = useAction();

  const [id, setId] = useState('');
  const [artistLoadState, setArtistLoadState] = useState('idle');
  const [artistListChanged, setArtistListChanged] = useState(false);
  const [currentArtistItems, setCurrentArtistItems] = useState([]);
  const artistRequest = useRef(0);
  const [f, setF] = useState({
    concertName: '', artistIds: [], venueId: '',
    startDatetime: '', endDatetime: '', saleStartDatetime: '', saleEndDatetime: '',
    purchaseLimit: '', temporaryHoldDuration: '',
    cancellationPolicy: '', refundPolicy: '',
    cancellationDeadlineHours: '', refundPercentage: '',
    fairAccessEnabled: '', waitlistEnabled: '', salesPaused: '',
  });
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  const num = (v) => (String(v).trim() === '' ? null : Number(v));
  const tri = (v) => (v === '' ? null : v === 'true');

  const selectConcert = async (value) => {
    setId(value);
    setArtistListChanged(false);
    setCurrentArtistItems([]);
    setF((current) => ({ ...current, artistIds: [] }));

    const request = ++artistRequest.current;
    if (!value) {
      setArtistLoadState('idle');
      return;
    }

    setArtistLoadState('loading');
    try {
      const response = await api.get(`/admin/concerts/${Number(value)}/artists`);
      if (artistRequest.current !== request) return;
      const selected = Array.isArray(response.data) ? response.data : [];
      setCurrentArtistItems(selected.map((artist) => ({
        id: artist.artistID,
        name: artist.artistName,
      })));
      setF((current) => ({ ...current, artistIds: selected
        .sort((a, b) => a.artistOrder - b.artistOrder)
        .map((artist) => String(artist.artistID)) }));
      setArtistLoadState('ready');
    } catch {
      if (artistRequest.current === request) setArtistLoadState('error');
    }
  };

  const setArtists = (artistIds) => {
    setArtistListChanged(true);
    setF((current) => ({ ...current, artistIds }));
  };
  const artistItems = [
    ...artists.items,
    ...currentArtistItems.filter((current) => !artists.items.some((artist) => artist.id === current.id)),
  ];

  return (
    <Panel
      title="Sửa concert"
      tone="edit"
      subtitle="Chọn concert để nạp danh sách nghệ sĩ hiện có. Các trường khác để trống sẽ được giữ nguyên."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(async () => {
            await api.put(`/admin/concerts/${Number(id)}`, {
              concertName: f.concertName.trim() || null,
              artistIds: artistListChanged ? f.artistIds.map(Number) : null,
              venueId: num(f.venueId),
              startDatetime: toApiDateTime(f.startDatetime),
              endDatetime: toApiDateTime(f.endDatetime),
              saleStartDatetime: toApiDateTime(f.saleStartDatetime),
              saleEndDatetime: toApiDateTime(f.saleEndDatetime),
              purchaseLimit: num(f.purchaseLimit),
              temporaryHoldDuration: num(f.temporaryHoldDuration),
              fairAccessEnabled: tri(f.fairAccessEnabled),
              waitlistEnabled: tri(f.waitlistEnabled),
              salesPaused: tri(f.salesPaused),
              cancellationPolicy: f.cancellationPolicy.trim() || null,
              refundPolicy: f.refundPolicy.trim() || null,
              cancellationDeadlineHours: num(f.cancellationDeadlineHours),
              refundPercentage: num(f.refundPercentage),
            });
            return Number(id);
          }, (cid) => `Đã cập nhật concert #${cid}.`);
        }}
      >
        <IdPicker label="Concert cần sửa" items={options} value={id} onChange={selectConcert} />

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Tên mới"><input value={f.concertName} onChange={(e) => set('concertName')(e.target.value)} /></Field>
          <MultiIdPicker
            label="Nghệ sĩ biểu diễn"
            hint={artistLoadState === 'loading' ? 'Đang nạp danh sách hiện có…'
              : artistLoadState === 'error' ? 'Không tải được danh sách hiện có. Hãy chọn lại concert.'
              : 'Chỉ gửi thay đổi khi bạn thêm, bỏ hoặc đổi thứ tự nghệ sĩ.'}
            items={artistItems}
            values={f.artistIds}
            onChange={setArtists}
            disabled={!id || artistLoadState === 'loading' || artistLoadState === 'error'}
          />
          <IdPicker label="Đổi địa điểm" items={venues.items} value={f.venueId} onChange={set('venueId')} />
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Bắt đầu diễn"><input type="datetime-local" value={f.startDatetime} onChange={(e) => set('startDatetime')(e.target.value)} /></Field>
          <Field label="Kết thúc diễn"><input type="datetime-local" value={f.endDatetime} onChange={(e) => set('endDatetime')(e.target.value)} /></Field>
          <Field label="Mở bán từ"><input type="datetime-local" value={f.saleStartDatetime} onChange={(e) => set('saleStartDatetime')(e.target.value)} /></Field>
          <Field label="Đóng bán lúc"><input type="datetime-local" value={f.saleEndDatetime} onChange={(e) => set('saleEndDatetime')(e.target.value)} /></Field>
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Giới hạn vé / khách"><input type="number" min="1" value={f.purchaseLimit} onChange={(e) => set('purchaseLimit')(e.target.value)} /></Field>
          <Field label="Giữ chỗ (phút)"><input type="number" min="1" value={f.temporaryHoldDuration} onChange={(e) => set('temporaryHoldDuration')(e.target.value)} /></Field>
          <Field label="Hạn hủy (giờ)"><input type="number" min="0" value={f.cancellationDeadlineHours} onChange={(e) => set('cancellationDeadlineHours')(e.target.value)} /></Field>
          <Field label="Tỷ lệ hoàn (%)"><input type="number" min="0" max="100" value={f.refundPercentage} onChange={(e) => set('refundPercentage')(e.target.value)} /></Field>
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Fair Access">
            <Select value={f.fairAccessEnabled} onChange={set('fairAccessEnabled')} allowEmpty
                    options={['true', 'false']} labels={{ true: 'Bật', false: 'Tắt' }} />
          </Field>
          <Field label="Waitlist">
            <Select value={f.waitlistEnabled} onChange={set('waitlistEnabled')} allowEmpty
                    options={['true', 'false']} labels={{ true: 'Bật', false: 'Tắt' }} />
          </Field>
          <Field label="Tạm dừng bán" hint="Chặn đặt vé mà không đổi trạng thái concert.">
            <Select value={f.salesPaused} onChange={set('salesPaused')} allowEmpty
                    options={['true', 'false']} labels={{ true: 'Đang tạm dừng', false: 'Đang bán' }} />
          </Field>
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Chính sách hủy"><textarea value={f.cancellationPolicy} onChange={(e) => set('cancellationPolicy')(e.target.value)} maxLength={500} /></Field>
          <Field label="Chính sách hoàn tiền"><textarea value={f.refundPolicy} onChange={(e) => set('refundPolicy')(e.target.value)} maxLength={500} /></Field>
        </div>

        <Button
          type="submit" variant="primary" loading={act.busy}
          disabled={!id || artistLoadState === 'loading' || artistLoadState === 'error' || (artistListChanged && f.artistIds.length === 0)}
          style={{ marginTop: '20px' }}
        >
          Lưu thay đổi
        </Button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Chuyển trạng thái ───────────────────────────────────────────────────── */

function ConcertStatusSection() {
  const { options } = useConcertOptions();
  const act = useAction();
  const [id, setId] = useState('');
  const [status, setStatus] = useState(ConcertStatus.Published);

  return (
    <Panel
      title="Chuyển trạng thái concert"
      tone="workflow"
      subtitle="Máy trạng thái ở database quyết định phép chuyển nào hợp lệ; bước sai sẽ bị từ chối kèm lý do. Đường thường dùng: Draft → Published → OnSale → SaleClosed → Completed."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(async () => {
            await api.patch(`/admin/concerts/${Number(id)}/status`, { status });
            // Đổi trạng thái làm thay đổi danh sách công khai (Draft ẩn, OnSale hiện),
            // nên bỏ bộ nhớ đệm để các ô chọn phản ánh đúng ở lần hỏi sau.
            invalidateConcerts();
          }, `Đã chuyển concert #${id} sang ${CONCERT_STATUS_LABEL[status]}.`);
        }}
      >
        <div className="field-grid">
          <IdPicker label="Concert" items={options} value={id} onChange={setId} />
          <Field label="Trạng thái mới" required>
            <Select value={status} onChange={setStatus}
                    options={Object.values(ConcertStatus)} labels={CONCERT_STATUS_LABEL} />
          </Field>
        </div>
        {status === ConcertStatus.OnSale && (
          <div
            style={{
              marginTop: '14px', padding: '12px 16px', borderRadius: '8px',
              background: 'var(--bg-hover)', border: '1px solid var(--border-subtle)',
              fontSize: '0.8125rem', lineHeight: 1.7, color: 'var(--text-secondary)',
            }}
          >
            <strong style={{ color: 'var(--text-primary)' }}>Trước khi mở bán, concert phải có đủ (BR10):</strong>
            <ol style={{ margin: '8px 0 0 18px', padding: 0 }}>
              <li>Ít nhất một ghế đã được đưa vào kho vé — xem khối “Đưa ghế vào kho vé”.</li>
              <li>Đã điền cả mốc <em>mở bán từ</em> và <em>đóng bán lúc</em> — sửa ở khối “Sửa concert”.</li>
            </ol>
            Thiếu một trong hai thì database từ chối và trả về lý do tương ứng.
          </div>
        )}

        {status === ConcertStatus.Cancelled && (
          <div className="field-hint" style={{ marginTop: '10px', color: 'var(--warning)' }}>
            Hủy concert sẽ kéo theo hủy toàn bộ Booking, phát sinh yêu cầu hoàn tiền và
            đóng hàng đợi — thao tác này không đảo ngược được.
          </div>
        )}
        <Button
          type="submit" variant={status === ConcertStatus.Cancelled ? 'danger' : 'primary'}
          loading={act.busy} disabled={!id} style={{ marginTop: '16px' }}
        >
          Chuyển trạng thái
        </Button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Hạng vé ─────────────────────────────────────────────────────────────── */

function CategorySection() {
  const { options } = useConcertOptions();
  const { items } = useAdminCatalog('category');
  const act = useAction();

  const [concertId, setConcertId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [name, setName] = useState('');
  const [desc, setDesc] = useState('');
  const [price, setPrice] = useState('');
  const [status, setStatus] = useState('');

  const concertCategories = items.filter((item) => item.raw.concertID === Number(concertId));
  const selectCategory = (id) => {
    setCategoryId(id);
    const category = concertCategories.find((item) => String(item.id) === String(id))?.raw;
    setName(category?.categoryName ?? '');
    setDesc(category?.categoryDescription ?? '');
    setPrice(category ? String(category.basePrice) : '');
    setStatus(category?.categoryStatus ?? '');
  };

  return (
    <Panel
      title="Hạng vé"
      tone="inventory"
      subtitle="Một endpoint làm cả hai việc: bỏ trống ô ID hạng vé thì TẠO MỚI, điền vào thì CẬP NHẬT. Giá gốc ở đây là nguồn sự thật của giá vé và sẽ lan xuống các ghế trong kho (BR10a)."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(async () => {
            const res = await api.post(`/admin/concerts/${Number(concertId)}/categories`, {
              categoryName: name.trim(),
              categoryDescription: desc.trim() || null,
              basePrice: Number(price),
              ticketCategoryId: categoryId ? Number(categoryId) : null,
              categoryStatus: status || null,
            });
            return res.data.id;
          }, (id) => (categoryId
            ? `Đã cập nhật hạng vé #${id}.`
            : `Đã tạo hạng vé. ID = ${id} — dùng ID này để đưa ghế vào kho vé bên dưới.`));
        }}
      >
        <div className="field-grid">
          <IdPicker label="Concert" items={options} value={concertId} onChange={(id) => { setConcertId(id); selectCategory(''); }} />
          <Field label="Hạng vé" hint="Chọn hạng vé để sửa hoặc chọn tạo mới.">
            <Select value={categoryId} onChange={selectCategory} allowEmpty
                    emptyLabel="— Tạo hạng vé mới —"
                    options={concertCategories.map((item) => String(item.id))}
                    labels={Object.fromEntries(concertCategories.map((item) => [String(item.id), item.name]))} />
          </Field>
        </div>
        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Tên hạng vé" required>
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={255} required />
          </Field>
          <Field label="Giá gốc (₫)" hint="Số nguyên, không có phần lẻ — cột tiền là DECIMAL(18,0)." required>
            <input type="number" min="0" step="1" value={price} onChange={(e) => setPrice(e.target.value)} required />
          </Field>
          <Field label="Trạng thái">
            <Select value={status} onChange={setStatus} allowEmpty emptyLabel="— mặc định Active —"
                    options={Object.values(CategoryStatus)} labels={ADMIN_STATUS_LABEL} />
          </Field>
        </div>
        <div style={{ marginTop: '16px' }}>
          <Field label="Mô tả"><input value={desc} onChange={(e) => setDesc(e.target.value)} maxLength={500} /></Field>
        </div>
        <Button type="submit" variant="primary" loading={act.busy} disabled={!concertId || !name.trim() || price === ''} style={{ marginTop: '16px' }}>
          {categoryId ? 'Cập nhật hạng vé' : 'Tạo hạng vé'}
        </Button>
        <Banner state={act.state} />
      </form>
      {concertCategories.length > 0 && (
        <div style={{ marginTop: '20px', paddingTop: '16px', borderTop: '1px solid var(--border-subtle)', display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
          {concertCategories.map((it) => <IdPill key={it.id}>#{it.id} · {it.name}</IdPill>)}
        </div>
      )}
    </Panel>
  );
}

/* ── Sơ đồ ghế StagePass (ConcertMap) ────────────────────────────────────── */

/**
 * Lớp hình học StagePass (VenueTemplate → snapshot bất biến theo Concert) —
 * TÁCH BIỆT với "Đưa ghế vào kho vé" ở trên (EventSeat vẫn là nguồn sự thật
 * duy nhất về giá/tồn kho). Panel này quản lý vòng đời ConcertMap: tạo → chụp
 * snapshot từ một VenueTemplateVersion đã Công bố → khoá để dùng bán vé — và,
 * khi revision đã Khoá, gán ghế thật vào từng ô của sơ đồ
 * (sp_AddEventSeatsFromMapRevision, cầu nối ConcertMapRevisionSeat <-> EventSeat)
 * qua <LockedRevisionEventSeats/> bên dưới.
 */
function ConcertMapSection() {
  const { options } = useConcertOptions();
  const act = useAction();
  const [concertId, setConcertId] = useState('');
  const [map, setMap] = useState(null);
  const [loadingMap, setLoadingMap] = useState(false);
  const [revisions, setRevisions] = useState([]);
  const [versions, setVersions] = useState([]);
  const [sourceVersionId, setSourceVersionId] = useState('');

  const loadMap = async (cid) => {
    if (!cid) { setMap(null); setRevisions([]); return; }
    setLoadingMap(true);
    try {
      let mapData = null;
      try {
        const res = await api.get(`/admin/concerts/${cid}/map`);
        mapData = res.data;
      } catch (err) {
        if (err.response?.status !== 404) throw err;
      }
      setMap(mapData);
      if (mapData) {
        const rev = await api.get(`/admin/concert-maps/${mapData.concertMapID}/revisions`);
        setRevisions(Array.isArray(rev.data) ? rev.data : []);
      } else {
        setRevisions([]);
      }
    } finally {
      setLoadingMap(false);
    }
  };

  useEffect(() => { loadMap(concertId); /* eslint-disable-line react-hooks/exhaustive-deps */ }, [concertId]);

  useEffect(() => {
    setVersions([]); setSourceVersionId('');
    if (!concertId) return;
    api.get(`/admin/concerts/${concertId}/published-template-versions`)
      .then((res) => setVersions(Array.isArray(res.data) ? res.data : []));
  }, [concertId]);

  const hasOpenDraft = revisions.some((r) => r.revisionStatus === 'Draft');
  const lockedRevision = revisions.find((r) => r.revisionStatus === 'Locked');

  return (
    <Panel
      title="Sơ đồ ghế StagePass (ConcertMap)"
      tone="inventory"
      subtitle="Chụp snapshot BẤT BIẾN từ một Mẫu sơ đồ (VenueTemplate) đã Công bố — quản trị mẫu sơ đồ ở trang 'Mẫu sơ đồ (Studio)'."
    >
      <IdPicker label="Concert" items={options} value={concertId} onChange={setConcertId} />

      {concertId && (loadingMap ? <p className="field-hint">Đang tải…</p> : (
        <div style={{ marginTop: '16px' }}>
          {!map ? (
            <Button
              type="button" variant="primary" loading={act.busy}
              onClick={() => act.run(async () => {
                await api.post(`/admin/concerts/${Number(concertId)}/map`);
                await loadMap(concertId);
              }, 'Đã tạo ConcertMap.')}
            >
              Tạo ConcertMap cho Concert này
            </Button>
          ) : (
            <>
              <p className="field-hint">ConcertMap #{map.concertMapID}.</p>

              {revisions.length > 0 && (
                <table className="table" style={{ marginTop: '8px', marginBottom: '12px' }}>
                  <thead><tr><th>Revision</th><th>Trạng thái</th><th /></tr></thead>
                  <tbody>
                    {revisions.map((r) => (
                      <tr key={r.concertMapRevisionID}>
                        <td>#{r.revisionNumber}</td>
                        <td>{ADMIN_STATUS_LABEL[r.revisionStatus] ?? r.revisionStatus}</td>
                        <td>
                          {r.revisionStatus === 'Draft' && (
                            <div className="row gap-1">
                              <Button
                                type="button" variant="secondary" size="sm" loading={act.busy}
                                onClick={() => act.run(async () => {
                                  await api.post(`/admin/concert-map-revisions/${r.concertMapRevisionID}/lock`);
                                  await loadMap(concertId);
                                }, 'Đã khoá — sẵn sàng dùng sơ đồ này.')}
                              >
                                Khoá (Lock)
                              </Button>
                              {/* Huỷ nháp = xoá hẳn revision nháp, không đánh dấu trạng thái
                                  (xem sp_CancelConcertMapRevisionDraft.sql). Thiếu nút này thì
                                  một lần chụp snapshot nhầm sẽ bị 60217 chặn vĩnh viễn: không huỷ
                                  được Draft, không tạo được Draft mới, mà Lock thì không thay thế
                                  được revision đã Locked. */}
                              <Button
                                type="button" variant="danger-quiet" size="sm" loading={act.busy}
                                onClick={() => act.run(async () => {
                                  if (!window.confirm('Huỷ bản nháp sơ đồ này? Không thể hoàn tác.')) return;
                                  await api.delete(`/admin/concert-map-revisions/${r.concertMapRevisionID}`);
                                  await loadMap(concertId);
                                }, 'Đã huỷ bản nháp — có thể chụp lại snapshot.')}
                              >
                                Huỷ nháp
                              </Button>
                            </div>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}

              {lockedRevision && (
                <LockedRevisionEventSeats key={lockedRevision.concertMapRevisionID} concertId={concertId} revision={lockedRevision} />
              )}

              {!hasOpenDraft && (
                <div className="field-grid">
                  <Field label="Mẫu sơ đồ / Version đã công bố" hint={versions.length === 0 ? 'Venue này chưa có mẫu đang hoạt động với version đã công bố.' : undefined}>
                    <Select
                      value={sourceVersionId} onChange={setSourceVersionId}
                      options={versions.map((v) => String(v.venueTemplateVersionID))}
                      labels={Object.fromEntries(versions.map((v) => [String(v.venueTemplateVersionID), `${v.templateName} · v${v.versionNumber}`]))}
                      allowEmpty emptyLabel="— chọn mẫu/version —"
                    />
                  </Field>
                  <Button
                    type="button" variant="primary" loading={act.busy} style={{ marginTop: '20px' }}
                    disabled={!sourceVersionId}
                    onClick={() => act.run(async () => {
                      await api.post(`/admin/concert-maps/${map.concertMapID}/revisions`, { sourceVenueTemplateVersionID: Number(sourceVersionId) });
                      await loadMap(concertId);
                    }, 'Đã chụp snapshot — kiểm tra rồi bấm Khoá để dùng cho việc bán vé.')}
                  >
                    Chụp snapshot (tạo Revision)
                  </Button>
                </div>
              )}
            </>
          )}
        </div>
      ))}
      <Banner state={act.state} />
    </Panel>
  );
}

/**
 * Đưa ghế của MỘT revision đã Khoá vào kho vé (sp_AddEventSeatsFromMapRevision).
 *
 * Chỉ hiện ghế CHƯA có EventSeatID — ghế đã vào kho vé rồi thì SP sẽ từ chối
 * (lỗi 60248, trùng), nên lọc trước ở giao diện để danh sách chọn luôn hợp lệ.
 * Cùng khuôn UX với "Đưa ghế vào kho vé (EventSeat)" ở trên (textarea CSV +
 * multi-select + nút "Chọn tất cả"), chỉ khác nguồn ghế là ConcertMapRevisionSeatID
 * của MỘT revision thay vì SeatID thô theo Zone.
 */
function LockedRevisionEventSeats({ concertId, revision }) {
  const categories = useAdminCatalog('category');
  const availableCategories = categories.items.filter((item) =>
    item.raw.concertID === Number(concertId) && item.raw.categoryStatus === CategoryStatus.Active);
  const act = useAction();
  const [detail, setDetail] = useState(null);
  const [categoryId, setCategoryId] = useState('');
  const [seatIds, setSeatIds] = useState('');

  const load = useCallback(async () => {
    const res = await api.get(`/admin/concert-map-revisions/${revision.concertMapRevisionID}`);
    setDetail(res.data);
  }, [revision.concertMapRevisionID]);

  useEffect(() => { load(); }, [load]);

  const allSeats = useMemo(() => {
    if (!detail) return [];
    return detail.floors.flatMap((f) => f.sections.flatMap((s) => s.seats.map((seat) => ({ ...seat, sectionLabel: s.sectionName ?? s.sectionKey }))));
  }, [detail]);
  const unlinkedSeats = useMemo(
    () => allSeats.filter((s) => s.eventSeatID == null)
      .map((s) => ({ id: s.concertMapRevisionSeatID, name: `${s.sectionLabel} · ${s.seatKey}` })),
    [allSeats],
  );

  const unique = useMemo(() => [...new Set(
    seatIds.split(/[,\s]+/).map((s) => Number(s.trim())).filter((n) => Number.isInteger(n) && n > 0),
  )], [seatIds]);

  if (!detail) return <p className="field-hint" style={{ marginTop: '16px' }}>Đang tải danh sách ghế của revision…</p>;

  return (
    <div style={{ marginTop: '8px', paddingTop: '16px', borderTop: '1px solid var(--border-subtle)' }}>
      <div className="field-hint" style={{ marginBottom: '12px' }}>
        Revision #{revision.revisionNumber} (đã khoá) — {allSeats.length - unlinkedSeats.length}/{allSeats.length} ghế đã vào kho vé.
      </div>

      {unlinkedSeats.length === 0 ? (
        <p className="field-hint">Toàn bộ ghế của revision này đã ở trong kho vé.</p>
      ) : (
        <form
          onSubmit={(e) => {
            e.preventDefault();
            act.run(async () => {
              await api.post(`/admin/concert-map-revisions/${revision.concertMapRevisionID}/event-seats`, {
                ticketCategoryId: Number(categoryId),
                concertMapRevisionSeatIds: unique,
              });
              setSeatIds('');
              await load();
            }, `Đã đưa ${unique.length} ghế vào kho vé.`);
          }}
        >
          <IdPicker label="Hạng vé" items={availableCategories} value={categoryId} onChange={setCategoryId} />

          <div style={{ marginTop: '16px' }}>
            <Field label="Danh sách ghế cần đưa vào kho vé" hint="Ngăn cách bằng dấu phẩy hoặc khoảng trắng. Trùng lặp sẽ tự động bị loại." required>
              <textarea value={seatIds} onChange={(e) => setSeatIds(e.target.value)} placeholder="12, 13, 14…" />
            </Field>
          </div>

          <div style={{ marginTop: '12px' }}>
            <div className="field-hint" style={{ marginBottom: '8px' }}>
              Ghế chưa vào kho vé của revision này — bấm để thêm vào danh sách:
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
              <Button
                type="button" variant="secondary" size="sm"
                onClick={() => setSeatIds(unlinkedSeats.map((s) => s.id).join(', '))}
              >
                Chọn tất cả ({unlinkedSeats.length})
              </Button>
              <Field label="Chọn ghế" hint="Giữ Ctrl hoặc Shift để chọn nhiều ghế.">
                <select multiple size={8} value={unique.map(String)}
                  onChange={(event) => setSeatIds(Array.from(event.target.selectedOptions, (option) => option.value).join(', '))}>
                  {unlinkedSeats.map((seat) => <option key={seat.id} value={String(seat.id)}>#{seat.id} · {seat.name}</option>)}
                </select>
              </Field>
            </div>
          </div>

          <div className="field-hint" style={{ marginTop: '12px' }}>
            {unique.length > 0 ? `Sẽ gửi ${unique.length} ghế.` : 'Chưa chọn ghế nào.'}
          </div>

          <Button type="submit" variant="primary" loading={act.busy} disabled={!categoryId || unique.length === 0} style={{ marginTop: '16px' }}>
            Đưa ghế vào kho vé
          </Button>
          <Banner state={act.state} />
        </form>
      )}
    </div>
  );
}

/* ── Hàng đợi truy cập công bằng ─────────────────────────────────────────── */

function QueueSection() {
  const { options } = useConcertOptions();
  const act = useAction();
  const [id, setId] = useState('');
  const [capacity, setCapacity] = useState('');
  const [policy, setPolicy] = useState('');
  const [validity, setValidity] = useState('');
  const [inherit, setInherit] = useState(false);
  const [status, setStatus] = useState('');

  return (
    <Panel
      title="Cấu hình hàng đợi (Fair Access)"
      tone="workflow"
      subtitle="Sức chứa là số khách được vào chọn ghế cùng lúc. Thời hạn lượt mua chính là booking_ttl: hết hạn thì lượt tự thu hồi và nhường cho người kế tiếp (BR47b)."
    >
      <div
        style={{
          marginBottom: '18px', padding: '12px 16px', borderRadius: '8px',
          background: 'var(--bg-hover)', border: '1px solid var(--border-subtle)',
          fontSize: '0.8125rem', lineHeight: 1.7, color: 'var(--text-secondary)',
        }}
      >
        <strong style={{ color: 'var(--text-primary)' }}>Điều kiện:</strong> chỉ mở được
        hàng đợi khi concert đã bật <em>Fair Access</em>. Chưa bật thì hệ thống trả lỗi
        “Fair Access Disabled” — hãy bật ở khối <em>Sửa concert</em> phía trên trước.
      </div>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.put(`/admin/concerts/${Number(id)}/queue`, {
              admissionCapacity: capacity === '' ? null : Number(capacity),
              fairAccessPolicy: policy || null,
              admissionValiditySeconds: validity === '' ? null : Number(validity),
              inheritGlobalAdmissionValidity: inherit,
              queueStatus: status || null,
            }),
            `Đã cập nhật hàng đợi của concert #${id}.`,
          );
        }}
      >
        <IdPicker label="Concert" items={options} value={id} onChange={setId} />
        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Sức chứa hàng đợi" hint="Số khách được cấp lượt mua cùng lúc.">
            <input type="number" min="1" value={capacity} onChange={(e) => setCapacity(e.target.value)} />
          </Field>
          <Field label="Chính sách chọn lượt">
            <Select value={policy} onChange={setPolicy} allowEmpty
                    options={Object.values(AccessPolicy)} labels={ADMIN_STATUS_LABEL} />
          </Field>
          <Field label="Thời hạn lượt mua (giây)" hint="Bỏ trống nếu dùng cấu hình chung.">
            <input type="number" min="1" value={validity} onChange={(e) => setValidity(e.target.value)} disabled={inherit} />
          </Field>
          <Field label="Trạng thái hàng đợi">
            <Select value={status} onChange={setStatus} allowEmpty
                    options={Object.values(QueueStatus)} labels={ADMIN_STATUS_LABEL} />
          </Field>
        </div>
        <div style={{ marginTop: '16px' }}>
          <Check
            label="Dùng thời hạn chung của hệ thống"
            checked={inherit}
            onChange={(v) => { setInherit(v); if (v) setValidity(''); }}
            hint="Bật thì bỏ qua giá trị riêng ở trên và lấy theo cấu hình toàn hệ thống."
          />
        </div>
        <Button type="submit" variant="primary" loading={act.busy} disabled={!id} style={{ marginTop: '16px' }}>
          Lưu cấu hình hàng đợi
        </Button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Danh sách chờ ───────────────────────────────────────────────────────── */

function WaitlistSection() {
  const { options } = useConcertOptions();
  const act = useAction();
  const [id, setId] = useState('');
  const [policy, setPolicy] = useState('');
  const [status, setStatus] = useState('');

  return (
    <Panel
      title="Cấu hình danh sách chờ (Waitlist)"
      tone="workflow"
      subtitle="Khi có ghế được trả lại, tiến trình nền cấp cơ hội mua cho người trong danh sách chờ theo chính sách này (BR43)."
    >
      <div
        style={{
          marginBottom: '18px', padding: '12px 16px', borderRadius: '8px',
          background: 'var(--bg-hover)', border: '1px solid var(--border-subtle)',
          fontSize: '0.8125rem', lineHeight: 1.7, color: 'var(--text-secondary)',
        }}
      >
        <strong style={{ color: 'var(--text-primary)' }}>Điều kiện:</strong> chỉ mở được
        danh sách chờ khi concert đã bật <em>Waitlist</em>. Bật ở khối <em>Sửa concert</em>
        phía trên trước.
      </div>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.put(`/admin/concerts/${Number(id)}/waitlist`, {
              allocationPolicy: policy || null,
              waitlistStatus: status || null,
            }),
            `Đã cập nhật danh sách chờ của concert #${id}.`,
          );
        }}
      >
        <div className="field-grid">
          <IdPicker label="Concert" items={options} value={id} onChange={setId} />
          <Field label="Chính sách cấp cơ hội">
            <Select value={policy} onChange={setPolicy} allowEmpty
                    options={Object.values(AccessPolicy)} labels={ADMIN_STATUS_LABEL} />
          </Field>
          <Field label="Trạng thái danh sách chờ">
            <Select value={status} onChange={setStatus} allowEmpty
                    options={Object.values(WaitlistStatus)} labels={ADMIN_STATUS_LABEL} />
          </Field>
        </div>
        <Button type="submit" variant="primary" loading={act.busy} disabled={!id} style={{ marginTop: '16px' }}>
          Lưu cấu hình danh sách chờ
        </Button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Khoá / mở ghế ───────────────────────────────────────────────────────── */

function SeatAvailabilitySection() {
  const { options } = useConcertOptions();
  const act = useAction();
  const [concertId, setConcertId] = useState('');
  const [seats, setSeats] = useState([]);
  const [loading, setLoading] = useState(false);
  const [eventSeatId, setEventSeatId] = useState('');
  const [unavailable, setUnavailable] = useState(true);
  const [reason, setReason] = useState('');

  /**
   * Đây là khối DUY NHẤT trong khu quản trị đọc được dữ liệu thật, nhờ endpoint
   * công khai `GET /concerts/{id}/seats`. Lưu ý nó lọc bỏ concert Draft và Cancelled,
   * nên concert chưa công bố sẽ không nạp được sơ đồ.
   */
  const load = async () => {
    setLoading(true);
    try {
      const res = await api.get(`/concerts/${Number(concertId)}/seats`);
      setSeats(Array.isArray(res.data) ? res.data : []);
    } catch {
      setSeats([]);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Panel
      title="Khoá / mở một ghế"
      tone="inventory"
      subtitle="Dùng cho ghế hỏng, ghế bị che tầm nhìn hoặc ghế giữ cho ban tổ chức. Chỉ tác động tới ghế đang trống — ghế đã bán hoặc đang được giữ sẽ bị từ chối."
    >
      <div className="field-grid">
        <IdPicker label="Concert" items={options} value={concertId} onChange={setConcertId} />
        <div style={{ display: 'flex', alignItems: 'flex-end' }}>
          <Button type="button" variant="secondary" loading={loading} onClick={load} disabled={!concertId}>
            Nạp sơ đồ ghế
          </Button>
        </div>
      </div>

      {seats.length > 0 && (
        <div className="scroll-x" style={{ marginTop: '20px', maxHeight: '300px', overflowY: 'auto' }}>
          <table className="table">
            <thead>
              <tr><th>ID</th><th>Ghế</th><th>Khu</th><th>Hạng</th><th>Trạng thái</th><th /></tr>
            </thead>
            <tbody>
              {seats.map((s) => (
                <tr key={s.seatID}>
                  <td className="tabular">{s.seatID}</td>
                  <td>{s.seatNumber}</td>
                  <td>{s.sectionName}</td>
                  <td>{s.categoryName}</td>
                  <td style={{ color: s.inventoryStatus === InventoryStatus.Available ? 'var(--success)' : 'var(--text-secondary)' }}>
                    {s.inventoryStatus}
                  </td>
                  <td>
                    <Button
                      type="button" variant="secondary" size="sm"
                      onClick={() => {
                        setEventSeatId(String(s.seatID));
                        setUnavailable(s.inventoryStatus === InventoryStatus.Available);
                      }}
                    >
                      Chọn
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <form
        style={{ marginTop: '20px' }}
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.patch(`/admin/event-seats/${Number(eventSeatId)}/availability`, {
              unavailable,
              reason: unavailable ? reason.trim() : null,
            }),
            unavailable ? `Đã khoá ghế #${eventSeatId}.` : `Đã mở lại ghế #${eventSeatId}.`,
          );
        }}
      >
        <div className="field-grid">
          <Field label="ID ghế trong kho vé (EventSeatID)" required>
            <input type="number" min="1" value={eventSeatId} onChange={(e) => setEventSeatId(e.target.value)} required />
          </Field>
          <Field label="Hành động">
            <Select value={String(unavailable)} onChange={(v) => setUnavailable(v === 'true')}
                    options={['true', 'false']} labels={{ true: 'Khoá ghế', false: 'Mở lại ghế' }} />
          </Field>
        </div>
        {unavailable && (
          <div style={{ marginTop: '16px' }}>
            <Field label="Lý do khoá" hint="Bắt buộc khi khoá ghế — sẽ được ghi vào nhật ký kiểm toán." required>
              <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} required />
            </Field>
          </div>
        )}
        <Button
          type="submit" variant={unavailable ? 'danger' : 'primary'}
          loading={act.busy} disabled={!eventSeatId || (unavailable && !reason.trim())} style={{ marginTop: '16px' }}
        >
          {unavailable ? 'Khoá ghế' : 'Mở lại ghế'}
        </Button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}
