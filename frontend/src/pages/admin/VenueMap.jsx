import { useState, useEffect, useCallback, useMemo } from 'react';
import api from '../../api/client';
import { useVenues, invalidateCatalog } from '../../lib/adminCatalog';
import { Field, Select, Panel, Banner, IdPicker, useAction } from '../../components/form';
import { ADMIN_STATUS_LABEL } from '../../domain/enums';

/**
 * DỰNG SƠ ĐỒ ĐỊA ĐIỂM — chỉ Admin.
 *
 * Đây là màn hình biến quyết định "Admin dựng sơ đồ một lần, các lần sau organizer
 * chỉ chọn lại" thành việc làm được bằng tay, không phải bằng script.
 *
 * Ba bước theo đúng thứ tự phụ thuộc của database:
 *   1. Mặt phẳng toạ độ + sân khấu  (sp_ConfigureVenueMap)
 *   2. Các khu, có vị trí và góc xoay (sp_CreateZone / sp_UpdateZone)
 *   3. Ghế trong khu, có hàng và cột  (sp_CreateSeat)
 *
 * BẢN XEM TRƯỚC LÀ BẮT BUỘC, không phải trang trí. Người dùng sắp đặt khán phòng
 * bằng cách gõ toạ độ; gõ số mà không thấy kết quả thì không thể làm được. Bản
 * xem trước vẽ đúng thứ khách sẽ thấy, cập nhật theo từng ký tự.
 */
export default function VenueMap() {
  const venues = useVenues();
  const [venueId, setVenueId] = useState('');
  const [zones, setZones] = useState([]);
  const [loadingZones, setLoadingZones] = useState(false);

  const venue = venues.raw.find((v) => String(v.venueID) === String(venueId));

  const loadZones = useCallback(async (id) => {
    if (!id) { setZones([]); return; }
    setLoadingZones(true);
    try {
      const res = await api.get(`/admin/venues/${Number(id)}/zones`);
      setZones(Array.isArray(res.data) ? res.data : []);
    } catch {
      setZones([]);
    } finally {
      setLoadingZones(false);
    }
  }, []);

  useEffect(() => { loadZones(venueId); }, [venueId, loadZones]);

  const refresh = useCallback(async () => {
    invalidateCatalog('venues');
    venues.reload();
    await loadZones(venueId);
  }, [venues, loadZones, venueId]);

  return (
    <>
      <Panel
        title="Chọn địa điểm cần dựng sơ đồ"
        subtitle="Sơ đồ thuộc về địa điểm và được mọi concert tổ chức tại đó dùng lại. Dựng một lần, các lần sau ban tổ chức chỉ việc chọn địa điểm."
      >
        <IdPicker
          label="Địa điểm"
          items={venues.items}
          value={venueId}
          onChange={setVenueId}
          hint={venues.loading ? 'Đang tải danh mục…' : `${venues.items.length} địa điểm trong danh mục.`}
        />
      </Panel>

      {venue && (
        <>
          <Preview venue={venue} zones={zones} loading={loadingZones} />
          {/*
            key theo venueID: doi dia diem thi ba form duoi day duoc DUNG LAI, nen
            chung khoi tao trang thai tu prop dung mot lan va khong can effect chep
            prop vao state. Nho vay mot lan refresh() o panel nay khong con xoa
            nhung gi admin dang go do o panel kia.
          */}
          <MapForm key={`map-${venue.venueID}`} venue={venue} onDone={refresh} />
          <ZoneForm key={`zone-${venue.venueID}`} venue={venue} zones={zones} onDone={refresh} />
          <SeatGridForm key={`seat-${venue.venueID}`} zones={zones} onDone={refresh} />
          <ZoneTable zones={zones} loading={loadingZones} />
        </>
      )}
    </>
  );
}

/* ══ BẢN XEM TRƯỚC ═════════════════════════════════════════════════════════ */

function Preview({ venue, zones, loading }) {
  const W = venue.mapWidth;
  const H = venue.mapHeight;

  if (!W || !H) {
    return (
      <Panel title="Xem trước">
        <div className="alert alert--warning">
          Địa điểm này chưa khai báo mặt phẳng toạ độ. Khai báo ở khối bên dưới thì
          bản xem trước mới vẽ được — và khách cũng chỉ thấy danh sách khu thay vì sơ đồ.
        </div>
      </Panel>
    );
  }

  const placed = zones.filter((z) => z.zoneX != null && z.zoneStatus === 'Active');

  return (
    <Panel
      title="Xem trước"
      subtitle={`Mặt phẳng ${W}×${H}. Đây đúng là hình khách sẽ thấy ở mức tổng quan.`}
    >
      <div className="seatmap-frame" style={{ maxWidth: 620 }}>
        <svg
          viewBox={`0 0 ${W} ${H}`}
          preserveAspectRatio="xMidYMid meet"
          role="img"
          aria-label={`Xem trước sơ đồ ${venue.venueName}`}
          style={{ width: '100%', height: 'auto', display: 'block' }}
        >
          {/* Khung mặt phẳng — cho thấy ranh giới mà khu không được vượt qua. */}
          <rect
            x={0.5} y={0.5} width={W - 1} height={H - 1}
            fill="none" stroke="var(--border-subtle)" strokeWidth={2} strokeDasharray="10 8"
          />

          {venue.stageX != null && (
            <g>
              <rect
                x={venue.stageX} y={venue.stageY}
                width={venue.stageWidth} height={venue.stageHeight}
                rx={Math.min(10, venue.stageHeight / 3)}
                fill="var(--surface-inverse)"
              />
              <text
                x={venue.stageX + venue.stageWidth / 2}
                y={venue.stageY + venue.stageHeight / 2}
                textAnchor="middle" dominantBaseline="central"
                fill="var(--text-inverse)"
                style={{ fontSize: 18, fontWeight: 600, letterSpacing: '0.14em' }}
              >
                SÂN KHẤU
              </text>
            </g>
          )}

          {placed.map((z) => {
            const cx = z.zoneX + z.zoneWidth / 2;
            const cy = z.zoneY + z.zoneHeight / 2;
            const rot = Number(z.zoneRotation ?? 0);
            const isGA = z.zoneType === 'GeneralAdmission';
            return (
              <g key={z.zoneID} transform={rot ? `rotate(${rot} ${cx} ${cy})` : undefined}>
                <rect
                  x={z.zoneX} y={z.zoneY} width={z.zoneWidth} height={z.zoneHeight}
                  rx={12}
                  fill={isGA ? 'var(--blue-bg)' : 'var(--surface-sunken)'}
                  stroke={isGA ? 'var(--blue-border)' : 'var(--border-strong)'}
                  strokeWidth={1.5}
                  strokeDasharray={isGA ? '7 5' : undefined}
                />
                <text
                  x={cx} y={cy - 8} textAnchor="middle" dominantBaseline="central"
                  fill="var(--text)" style={{ fontSize: 15, fontWeight: 600 }}
                >
                  {z.zoneName ?? z.zoneCode}
                </text>
                <text
                  x={cx} y={cy + 12} textAnchor="middle" dominantBaseline="central"
                  fill="var(--text-secondary)" style={{ fontSize: 12 }}
                >
                  {isGA ? `Vé đứng · ${z.zoneCapacity} chỗ` : `${z.seatCount} ghế`}
                  {z.zoneLevel > 1 ? ` · tầng ${z.zoneLevel}` : ''}
                </text>
              </g>
            );
          })}
        </svg>
      </div>

      <div className="field-hint" style={{ marginTop: 'var(--space-3)', textAlign: 'center' }}>
        {loading ? 'Đang tải khu…'
          : placed.length === 0 ? 'Chưa khu nào được đặt vị trí.'
          : `${placed.length} khu đã có vị trí${zones.length > placed.length
              ? ` · ${zones.length - placed.length} khu chưa đặt vị trí (không hiện trên sơ đồ)` : ''}`}
      </div>
    </Panel>
  );
}

/* ══ BƯỚC 1 — MẶT PHẲNG VÀ SÂN KHẤU ════════════════════════════════════════ */

/** Giá trị đang lưu trên máy chủ, đổ vào ô nhập để sửa chứ không bắt gõ lại. */
const venueToForm = (v) => ({
  mapWidth: v.mapWidth ?? '', mapHeight: v.mapHeight ?? '',
  stageX: v.stageX ?? '', stageY: v.stageY ?? '',
  stageWidth: v.stageWidth ?? '', stageHeight: v.stageHeight ?? '',
});

function MapForm({ venue, onDone }) {
  const act = useAction();
  // Khởi tạo THẲNG từ prop. Bản trước chép prop vào state trong một useEffect có
  // các giá trị của venue trong danh sách phụ thuộc; mỗi lần refresh() nạp lại
  // danh mục là ô nhập bị ghi đè. Cha đã gắn key={venue.venueID} nên việc đổi địa
  // điểm tự khắc dựng lại form — đúng cách React đặt lại trạng thái theo prop.
  const [f, setF] = useState(() => venueToForm(venue));
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  const num = (v) => (String(v).trim() === '' ? null : Number(v));

  /** Bố cục mẫu: đỡ phải gõ sáu số cho một khán phòng thông thường. */
  const applyPreset = () => setF({
    mapWidth: 1000, mapHeight: 720,
    stageX: 320, stageY: 24, stageWidth: 360, stageHeight: 56,
  });

  return (
    <Panel
      title="Bước 1 — Mặt phẳng và sân khấu"
      subtitle="Đơn vị là số nguyên trừu tượng, không phải mét hay pixel: giao diện co giãn toàn bộ sơ đồ vào khung hình đang có, nên không cần dữ liệu đo đạc thực địa. Sân khấu là điểm tiêu cự — không có nó thì không nói được chỗ ngồi nào gần sân khấu hơn chỗ nào."
      aside={<button type="button" className="btn-outline" onClick={applyPreset}>Dùng bố cục mẫu</button>}
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(async () => {
            await api.put(`/admin/venues/${venue.venueID}/map`, {
              mapWidth: num(f.mapWidth), mapHeight: num(f.mapHeight),
              stageX: num(f.stageX), stageY: num(f.stageY),
              stageWidth: num(f.stageWidth), stageHeight: num(f.stageHeight),
            });
            await onDone();
          }, 'Đã lưu mặt phẳng và sân khấu.');
        }}
      >
        <div className="field-grid">
          <Field label="Chiều rộng mặt phẳng" required>
            <input type="number" min="1" value={f.mapWidth} onChange={(e) => set('mapWidth')(e.target.value)} required />
          </Field>
          <Field label="Chiều cao mặt phẳng" required>
            <input type="number" min="1" value={f.mapHeight} onChange={(e) => set('mapHeight')(e.target.value)} required />
          </Field>
        </div>
        <div className="field-grid" style={{ marginTop: 'var(--space-4)' }}>
          <Field label="Sân khấu — X"><input type="number" min="0" value={f.stageX} onChange={(e) => set('stageX')(e.target.value)} /></Field>
          <Field label="Sân khấu — Y"><input type="number" min="0" value={f.stageY} onChange={(e) => set('stageY')(e.target.value)} /></Field>
          <Field label="Sân khấu — rộng"><input type="number" min="1" value={f.stageWidth} onChange={(e) => set('stageWidth')(e.target.value)} /></Field>
          <Field label="Sân khấu — cao"><input type="number" min="1" value={f.stageHeight} onChange={(e) => set('stageHeight')(e.target.value)} /></Field>
        </div>
        <div className="field-hint" style={{ marginTop: 'var(--space-3)' }}>
          Sân khấu phải nằm trọn trong mặt phẳng, và mặt phẳng không được thu nhỏ hơn
          vùng các khu đang chiếm — database sẽ từ chối kèm lý do cụ thể.
        </div>
        <button className="btn-primary" style={{ marginTop: 'var(--space-4)' }}
                disabled={act.busy || !f.mapWidth || !f.mapHeight}>
          {act.busy ? 'Đang lưu…' : 'Lưu sơ đồ'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ══ BƯỚC 2 — KHU ══════════════════════════════════════════════════════════ */

const EMPTY_ZONE = {
  zoneCode: '', zoneName: '', zoneType: 'Seated', zoneLevel: '1',
  zoneX: '', zoneY: '', zoneWidth: '', zoneHeight: '', zoneRotation: '', zoneCapacity: '',
};

/** Giá trị đang lưu của một khu, đổ vào ô nhập để sửa. */
const zoneToForm = (z) => (z ? {
  zoneCode: z.zoneCode, zoneName: z.zoneName ?? '',
  zoneType: z.zoneType, zoneLevel: z.zoneLevel ?? '1',
  zoneX: z.zoneX ?? '', zoneY: z.zoneY ?? '',
  zoneWidth: z.zoneWidth ?? '', zoneHeight: z.zoneHeight ?? '',
  zoneRotation: z.zoneRotation ?? '', zoneCapacity: z.zoneCapacity ?? '',
} : EMPTY_ZONE);

/**
 * Vỏ ngoài giữ việc CHỌN khu; phần ô nhập nằm trong ZoneFields và được dựng lại
 * mỗi khi đổi lựa chọn (key). Tách làm hai là cách React đặt lại trạng thái theo
 * prop mà không cần effect — và nó sửa một lỗi thật: bản trước có `zones` trong
 * danh sách phụ thuộc, nên chỉ cần một panel khác gọi refresh() là mảng zones đổi
 * danh tính, effect chạy lại và xoá sạch những gì admin vừa gõ mà chưa lưu.
 */
function ZoneForm({ venue, zones, onDone }) {
  const [editId, setEditId] = useState('');
  // Tạo xong một khu thì tăng số này để dựng lại form trống cho lần nhập kế tiếp.
  const [newSeq, setNewSeq] = useState(0);
  const editing = !!editId;
  const zone = editing ? zones.find((x) => String(x.zoneID) === String(editId)) : null;

  return (
    <Panel
      title={editing ? 'Bước 2 — Sửa khu' : 'Bước 2 — Thêm khu'}
      subtitle="Khu vé đứng bán theo sức chứa và KHÔNG có ghế nào — đó là cách đúng để mô hình hoá khu đứng trước sân khấu, thay vì tạo hàng trăm ghế giả. Góc xoay để hướng khu về phía sân khấu."
      aside={
        <Select
          value={editId} onChange={setEditId} allowEmpty emptyLabel="— tạo khu mới —"
          options={zones.map((z) => String(z.zoneID))}
          labels={Object.fromEntries(zones.map((z) => [String(z.zoneID), `#${z.zoneID} · ${z.zoneName ?? z.zoneCode}`]))}
          aria-label="Chọn khu để sửa"
        />
      }
    >
      <ZoneFields
        key={editId || `new-${newSeq}`}
        venue={venue}
        editId={editId}
        zone={zone}
        onDone={onDone}
        onCreated={() => setNewSeq((n) => n + 1)}
      />
    </Panel>
  );
}

function ZoneFields({ venue, editId, zone, onDone, onCreated }) {
  const act = useAction();
  const [f, setF] = useState(() => zoneToForm(zone));
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  const num = (v) => (String(v).trim() === '' ? null : Number(v));

  const isGA = f.zoneType === 'GeneralAdmission';
  const editing = !!editId;

  const submit = (e) => {
    e.preventDefault();
    const geo = {
      zoneType: f.zoneType,
      zoneLevel: num(f.zoneLevel),
      zoneX: num(f.zoneX), zoneY: num(f.zoneY),
      zoneWidth: num(f.zoneWidth), zoneHeight: num(f.zoneHeight),
      zoneRotation: num(f.zoneRotation),
      zoneCapacity: isGA ? num(f.zoneCapacity) : null,
    };
    act.run(async () => {
      if (editing) {
        await api.put(`/admin/zones/${Number(editId)}`, {
          zoneName: f.zoneName.trim() || null, ...geo,
        });
      } else {
        await api.post(`/admin/venues/${venue.venueID}/zones`, {
          zoneCode: f.zoneCode.trim(), zoneName: f.zoneName.trim() || null, ...geo,
        });
        onCreated();   // dựng lại form trống cho khu kế tiếp
      }
      await onDone();
    }, editing ? `Đã cập nhật khu #${editId}.` : 'Đã tạo khu.');
  };

  return (
    <form onSubmit={submit}>
      <div className="field-grid">
        {!editing && (
          <Field label="Mã khu" hint="Duy nhất trong địa điểm. Ví dụ: VIP, STD-L, BAL." required>
            <input value={f.zoneCode} onChange={(e) => set('zoneCode')(e.target.value)} maxLength={64} required />
          </Field>
        )}
        <Field label="Tên hiển thị" hint="Đây là tên khách nhìn thấy trên sơ đồ.">
          <input value={f.zoneName} onChange={(e) => set('zoneName')(e.target.value)} maxLength={255} />
        </Field>
        <Field label="Loại khu" required>
          <Select
            value={f.zoneType} onChange={set('zoneType')}
            options={['Seated', 'GeneralAdmission']}
            labels={{ Seated: 'Có ghế đánh số', GeneralAdmission: 'Vé đứng (theo sức chứa)' }}
          />
        </Field>
        <Field label="Tầng / khán đài" hint="1 = tầng trệt. Sơ đồ hiện từng tầng một.">
          <input type="number" min="1" value={f.zoneLevel} onChange={(e) => set('zoneLevel')(e.target.value)} />
        </Field>
      </div>

      <div className="field-grid" style={{ marginTop: 'var(--space-4)' }}>
        <Field label="X (góc trái)"><input type="number" min="0" value={f.zoneX} onChange={(e) => set('zoneX')(e.target.value)} /></Field>
        <Field label="Y (góc trên)"><input type="number" min="0" value={f.zoneY} onChange={(e) => set('zoneY')(e.target.value)} /></Field>
        <Field label="Chiều rộng"><input type="number" min="1" value={f.zoneWidth} onChange={(e) => set('zoneWidth')(e.target.value)} /></Field>
        <Field label="Chiều cao"><input type="number" min="1" value={f.zoneHeight} onChange={(e) => set('zoneHeight')(e.target.value)} /></Field>
        <Field label="Góc xoay (độ)" hint="Âm là xoay ngược chiều kim đồng hồ.">
          <input type="number" min="-359" max="359" step="0.5" value={f.zoneRotation} onChange={(e) => set('zoneRotation')(e.target.value)} />
        </Field>
        {isGA && (
          <Field label="Sức chứa" hint="Bắt buộc với khu vé đứng." required>
            <input type="number" min="1" value={f.zoneCapacity} onChange={(e) => set('zoneCapacity')(e.target.value)} required />
          </Field>
        )}
      </div>

      <div className="field-hint" style={{ marginTop: 'var(--space-3)' }}>
        Bốn giá trị X, Y, rộng, cao phải điền đủ hoặc bỏ trống cả bốn. Khu vượt ra
        ngoài mặt phẳng sẽ bị từ chối.
      </div>

      <button className="btn-primary" style={{ marginTop: 'var(--space-4)' }}
              disabled={act.busy || (!editing && !f.zoneCode.trim())}>
        {act.busy ? 'Đang lưu…' : editing ? 'Lưu thay đổi' : 'Tạo khu'}
      </button>
      <Banner state={act.state} />
    </form>
  );
}

/* ══ BƯỚC 3 — GHẾ THEO LƯỚI ════════════════════════════════════════════════ */

/** A, B, … Z, AA, AB … — đủ cho khán phòng lớn. */
function rowLabel(i) {
  let n = i;
  let out = '';
  do {
    out = String.fromCharCode(65 + (n % 26)) + out;
    n = Math.floor(n / 26) - 1;
  } while (n >= 0);
  return out;
}

function SeatGridForm({ zones, onDone }) {
  const act = useAction();
  const [zoneId, setZoneId] = useState('');
  const [rows, setRows] = useState('3');
  const [cols, setCols] = useState('8');
  const [startRow, setStartRow] = useState('A');
  const [progress, setProgress] = useState('');

  const seatedZones = zones.filter((z) => z.zoneType === 'Seated');
  const zone = zones.find((z) => String(z.zoneID) === String(zoneId));

  const plan = useMemo(() => {
    const r = Number(rows), c = Number(cols);
    if (!Number.isInteger(r) || !Number.isInteger(c) || r < 1 || c < 1) return null;
    const offset = Math.max(0, startRow.trim().toUpperCase().charCodeAt(0) - 65);
    return { r, c, total: r * c, first: rowLabel(offset), last: rowLabel(offset + r - 1), offset };
  }, [rows, cols, startRow]);

  const submit = (e) => {
    e.preventDefault();
    if (!plan || !zone) return;
    act.run(async () => {
      const made = [];
      // Gọi tuần tự: API chỉ tạo được từng ghế một, và bắn song song hàng trăm
      // request chỉ làm tăng tranh chấp khoá mà không nhanh hơn đáng kể — khi lỗi
      // giữa chừng lại khó nói đã tạo tới đâu.
      for (let ri = 0; ri < plan.r; ri += 1) {
        const label = rowLabel(plan.offset + ri);
        for (let ci = 1; ci <= plan.c; ci += 1) {
          setProgress(`Đang tạo ${label}${ci} — ${made.length + 1}/${plan.total}`);
          const res = await api.post(`/admin/zones/${zone.zoneID}/seats`, {
            seatCode: `${zone.zoneCode}-${label}${ci}`,
            seatLabel: `${label}${ci}`,
            seatRowLabel: label,
            seatColumnNumber: ci,
          });
          made.push(res.data.id);
        }
      }
      setProgress('');
      await onDone();
      return made;
    }, (made) => `Đã tạo ${made?.length ?? 0} ghế trong ${zone.zoneName ?? zone.zoneCode}.`);
  };

  return (
    <Panel
      title="Bước 3 — Tạo ghế theo lưới"
      subtitle="Mỗi ghế được gán HÀNG và SỐ THỨ TỰ TRONG HÀNG. Mã ghế chỉ là định danh; hai trường này mới là vị trí, và là thứ cho phép in ra địa chỉ chỗ ngồi mà người thường hiểu được — “Khu VIP, hàng C, ghế 12”."
    >
      <form onSubmit={submit}>
        <div className="field-grid">
          <Field label="Khu" hint="Chỉ khu có ghế; khu vé đứng bán theo sức chứa." required>
            <Select
              value={zoneId} onChange={setZoneId} allowEmpty emptyLabel="— chọn khu —"
              options={seatedZones.map((z) => String(z.zoneID))}
              labels={Object.fromEntries(seatedZones.map((z) =>
                [String(z.zoneID), `#${z.zoneID} · ${z.zoneName ?? z.zoneCode} (${z.seatCount} ghế)`]))}
            />
          </Field>
          <Field label="Số hàng" required>
            <input type="number" min="1" max="60" value={rows} onChange={(e) => setRows(e.target.value)} required />
          </Field>
          <Field label="Ghế mỗi hàng" required>
            <input type="number" min="1" max="60" value={cols} onChange={(e) => setCols(e.target.value)} required />
          </Field>
          <Field label="Hàng bắt đầu" hint="Để tiếp nối khu đã có, ví dụ bắt đầu từ D.">
            <input value={startRow} onChange={(e) => setStartRow(e.target.value)} maxLength={2} />
          </Field>
        </div>

        {plan && zone && (
          <div className="field-hint" style={{ marginTop: 'var(--space-3)' }}>
            Sẽ tạo <strong>{plan.total} ghế</strong>, hàng {plan.first}–{plan.last},
            mã từ <code>{zone.zoneCode}-{plan.first}1</code> đến <code>{zone.zoneCode}-{plan.last}{plan.c}</code>.
            Vị trí đã có ghế khác sẽ bị database từ chối, không ghi đè.
          </div>
        )}

        <button className="btn-primary" style={{ marginTop: 'var(--space-4)' }}
                disabled={act.busy || !zone || !plan}>
          {act.busy ? (progress || 'Đang tạo…') : `Tạo ${plan?.total ?? 0} ghế`}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ══ BẢNG KHU ══════════════════════════════════════════════════════════════ */

function ZoneTable({ zones, loading }) {
  if (loading) return null;
  if (!zones.length) {
    return <Panel title="Các khu"><div className="field-hint">Địa điểm này chưa có khu nào.</div></Panel>;
  }
  return (
    <Panel title={`Các khu (${zones.length})`}>
      <div className="table-wrap">
        <table className="data">
          <thead>
            <tr>
              <th>ID</th><th>Mã</th><th>Tên</th><th>Loại</th><th>Tầng</th>
              <th>Vị trí</th><th>Kích thước</th><th>Xoay</th><th>Ghế</th><th>Trạng thái</th>
            </tr>
          </thead>
          <tbody>
            {zones.map((z) => (
              <tr key={z.zoneID}>
                <td>{z.zoneID}</td>
                <td>{z.zoneCode}</td>
                <td>{z.zoneName ?? '—'}</td>
                <td>{z.zoneType === 'GeneralAdmission' ? 'Vé đứng' : 'Có ghế'}</td>
                <td>{z.zoneLevel ?? '—'}</td>
                <td>{z.zoneX != null ? `${z.zoneX}, ${z.zoneY}` : <span style={{ color: 'var(--amber-text)' }}>chưa đặt</span>}</td>
                <td>{z.zoneWidth != null ? `${z.zoneWidth}×${z.zoneHeight}` : '—'}</td>
                <td>{z.zoneRotation != null ? `${z.zoneRotation}°` : '—'}</td>
                <td>{z.zoneType === 'GeneralAdmission' ? `${z.zoneCapacity} chỗ` : z.seatCount}</td>
                <td>{ADMIN_STATUS_LABEL[z.zoneStatus] ?? z.zoneStatus}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Panel>
  );
}
