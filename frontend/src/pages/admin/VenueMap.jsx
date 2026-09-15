import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import api from '../../api/client';
import { useVenues, invalidateCatalog } from '../../lib/adminCatalog';
import { Field, Select, Check, Panel, Banner, IdPicker, useAction } from '../../components/form';
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
 * xem trước và trình biên tập trực quan vẽ đúng thứ khách sẽ thấy; tọa độ chỉ là
 * dữ liệu nội bộ sinh từ thao tác kéo-thả, không phải việc Admin phải tự tính.
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
        tone="inventory"
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
  const levels = [...new Set(zones.filter((z) => z.zoneStatus === 'Active').map((z) => z.zoneLevel ?? 1))]
    .sort((a, b) => a - b);
  const [chosenLevel, setChosenLevel] = useState(1);
  const level = levels.includes(chosenLevel) ? chosenLevel : (levels[0] ?? 1);

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

  const placed = zones.filter((z) => z.zoneX != null && z.zoneStatus === 'Active'
    && (z.zoneLevel ?? 1) === level);

  return (
    <Panel
      title="Xem trước"
      subtitle={`Mặt phẳng ${W}×${H}. Đây đúng là hình khách sẽ thấy ở mức tổng quan.`}
    >
      {levels.length > 1 && (
        <div className="row gap-2 wrap" style={{ justifyContent: 'center', marginBottom: 'var(--space-4)' }}>
          {levels.map((item) => (
            <button
              key={item}
              type="button"
              className={`btn btn--sm ${item === level ? 'btn--primary' : 'btn--secondary'}`}
              onClick={() => setChosenLevel(item)}
            >
              {item === 1 ? 'Tầng trệt' : `Tầng ${item}`}
            </button>
          ))}
        </div>
      )}
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
            return (
              <g key={z.zoneID} transform={rot ? `rotate(${rot} ${cx} ${cy})` : undefined}>
                <rect
                  x={z.zoneX} y={z.zoneY} width={z.zoneWidth} height={z.zoneHeight}
                  rx={12}
                  fill="var(--surface-sunken)"
                  stroke="var(--border-strong)"
                  strokeWidth={1.5}
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
                  {`${z.seatCount} ghế`}
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
          : `${placed.length} khu đã có vị trí ở ${level === 1 ? 'tầng trệt' : `tầng ${level}`}${zones.filter((z) => z.zoneStatus === 'Active' && (z.zoneLevel ?? 1) === level).length > placed.length
              ? ` · ${zones.filter((z) => z.zoneStatus === 'Active' && (z.zoneLevel ?? 1) === level).length - placed.length} khu chưa đặt vị trí` : ''}`}
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
  const [clearStage, setClearStage] = useState(false);
  const [clearMap, setClearMap] = useState(false);
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  const num = (v) => (String(v).trim() === '' ? null : Number(v));

  const layouts = [
    {
      name: 'Sân khấu phía trước',
      hint: 'Phù hợp nhà hát, khán phòng và concert trong nhà.',
      values: { mapWidth: 1200, mapHeight: 800, stageX: 360, stageY: 40, stageWidth: 480, stageHeight: 70 },
    },
    {
      name: 'Sân khấu trung tâm',
      hint: 'Phù hợp arena hoặc sân vận động bố trí 360°.',
      values: { mapWidth: 1000, mapHeight: 1000, stageX: 400, stageY: 430, stageWidth: 200, stageHeight: 140 },
    },
    {
      name: 'Mặt bằng không sân khấu',
      hint: 'Phù hợp hội nghị, comedy club hoặc địa điểm linh hoạt.',
      values: { mapWidth: 1200, mapHeight: 800, stageX: '', stageY: '', stageWidth: '', stageHeight: '' },
    },
  ];

  const applyLayout = (layout) => {
    setClearMap(false);
    setClearStage(layout.values.stageX === '');
    setF(layout.values);
  };

  return (
    <Panel
      title="Bước 1 — Mặt phẳng và sân khấu"
      tone="create"
      subtitle="Bắt đầu bằng kiểu mặt bằng gần nhất với venue; các số là dữ liệu nội bộ. Sau đó vẽ và kéo-thả khu trực tiếp trên mặt bằng ở Bước 2."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(async () => {
            const payload = { clearMap, clearStage: clearMap ? false : clearStage };
            if (!clearMap) {
              payload.mapWidth = num(f.mapWidth); payload.mapHeight = num(f.mapHeight);
            }
            if (!clearMap && !clearStage) {
              payload.stageX = num(f.stageX); payload.stageY = num(f.stageY);
              payload.stageWidth = num(f.stageWidth); payload.stageHeight = num(f.stageHeight);
            }
            await api.put(`/admin/venues/${venue.venueID}/map`, payload);
            await onDone();
          }, 'Đã lưu mặt phẳng và sân khấu.');
        }}
      >
        <div className="map-layout-templates" aria-label="Chọn kiểu mặt bằng">
          {layouts.map((layout) => (
            <button key={layout.name} type="button" className="map-layout-templates__item" onClick={() => applyLayout(layout)}>
              <strong>{layout.name}</strong>
              <span>{layout.hint}</span>
            </button>
          ))}
        </div>
        <details className="map-layout-details">
          <summary>Tinh chỉnh kích thước kỹ thuật</summary>
          <div className="field-grid" style={{ marginTop: 'var(--space-4)' }}>
            <Field label="Chiều rộng mặt phẳng" required={!clearMap}>
              <input type="number" min="1" disabled={clearMap} value={f.mapWidth} onChange={(e) => set('mapWidth')(e.target.value)} required={!clearMap} />
            </Field>
            <Field label="Chiều cao mặt phẳng" required={!clearMap}>
              <input type="number" min="1" disabled={clearMap} value={f.mapHeight} onChange={(e) => set('mapHeight')(e.target.value)} required={!clearMap} />
            </Field>
          </div>
        </details>
        <div style={{ marginTop: 'var(--space-4)' }}>
          <Check
            label="Dùng danh sách ghế thay cho sơ đồ tại địa điểm này"
            checked={clearMap}
            onChange={(checked) => { setClearMap(checked); if (checked) setClearStage(false); }}
            hint="Xóa toàn bộ mặt phẳng và sân khấu đang lưu; trang bán vé sẽ trở về danh sách ghế."
          />
          <Check
            label="Địa điểm này không có sân khấu cố định trên sơ đồ"
            checked={clearStage && !clearMap}
            onChange={setClearStage}
            disabled={clearMap}
            hint="Chọn mục này để xóa toàn bộ vị trí sân khấu đang lưu."
          />
        </div>
        <div className="field-grid" style={{ marginTop: 'var(--space-4)' }}>
          <Field label="Sân khấu — X"><input type="number" min="0" disabled={clearStage || clearMap} value={f.stageX} onChange={(e) => set('stageX')(e.target.value)} /></Field>
          <Field label="Sân khấu — Y"><input type="number" min="0" disabled={clearStage || clearMap} value={f.stageY} onChange={(e) => set('stageY')(e.target.value)} /></Field>
          <Field label="Sân khấu — rộng"><input type="number" min="1" disabled={clearStage || clearMap} value={f.stageWidth} onChange={(e) => set('stageWidth')(e.target.value)} /></Field>
          <Field label="Sân khấu — cao"><input type="number" min="1" disabled={clearStage || clearMap} value={f.stageHeight} onChange={(e) => set('stageHeight')(e.target.value)} /></Field>
        </div>
        <div className="field-hint" style={{ marginTop: 'var(--space-3)' }}>
          Sân khấu phải nằm trọn trong mặt phẳng, và mặt phẳng không được thu nhỏ hơn
          vùng các khu đang chiếm — database sẽ từ chối kèm lý do cụ thể.
        </div>
        <button className="btn-primary" style={{ marginTop: 'var(--space-4)' }}
                disabled={act.busy || (!clearMap && (!f.mapWidth || !f.mapHeight))}>
          {act.busy ? 'Đang lưu…' : 'Lưu sơ đồ'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ══ BƯỚC 2 — KHU ══════════════════════════════════════════════════════════ */

const EMPTY_ZONE = {
  zoneCode: '', zoneName: '', zoneLevel: '1',
  zoneX: '', zoneY: '', zoneWidth: '', zoneHeight: '', zoneRotation: '',
};

/** Giá trị đang lưu của một khu, đổ vào ô nhập để sửa. */
const zoneToForm = (z) => (z ? {
  zoneCode: z.zoneCode, zoneName: z.zoneName ?? '',
  zoneLevel: z.zoneLevel ?? '1',
  zoneX: z.zoneX ?? '', zoneY: z.zoneY ?? '',
  zoneWidth: z.zoneWidth ?? '', zoneHeight: z.zoneHeight ?? '',
  zoneRotation: z.zoneRotation ?? '',
} : EMPTY_ZONE);

const asNumber = (value) => (String(value).trim() === '' ? null : Number(value));
const snap = (value) => Math.round(value / 10) * 10;
const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

function geometryFromForm(form) {
  const x = asNumber(form.zoneX);
  const y = asNumber(form.zoneY);
  const width = asNumber(form.zoneWidth);
  const height = asNumber(form.zoneHeight);
  const rotation = asNumber(form.zoneRotation) ?? 0;
  return [x, y, width, height].every(Number.isFinite) && width > 0 && height > 0
    ? { x, y, width, height, rotation }
    : null;
}

function fitGeometry(raw, mapWidth, mapHeight) {
  const minSize = Math.max(24, Math.min(mapWidth, mapHeight) * 0.04);
  const width = clamp(snap(raw.width), minSize, mapWidth);
  const height = clamp(snap(raw.height), minSize, mapHeight);
  const rotation = ((Number(raw.rotation) % 360) + 360) % 360;
  const radians = rotation * Math.PI / 180;
  const extentX = Math.abs(width / 2 * Math.cos(radians)) + Math.abs(height / 2 * Math.sin(radians));
  const extentY = Math.abs(width / 2 * Math.sin(radians)) + Math.abs(height / 2 * Math.cos(radians));
  if (extentX * 2 > mapWidth || extentY * 2 > mapHeight) return null;

  const centerX = clamp(raw.x + width / 2, extentX, mapWidth - extentX);
  const centerY = clamp(raw.y + height / 2, extentY, mapHeight - extentY);
  // Snap x/y sau khi canh giua co the day mot hinh xoay vuot bien 1–5 don vi.
  // Canh theo mien an toan nguyen truoc khi viet ra form de client va database
  // cung dong y ve mot hinh hop le.
  const minX = Math.ceil(extentX - width / 2);
  const maxX = Math.floor(mapWidth - extentX - width / 2);
  const minY = Math.ceil(extentY - height / 2);
  const maxY = Math.floor(mapHeight - extentY - height / 2);
  return {
    x: clamp(snap(centerX - width / 2), minX, maxX),
    y: clamp(snap(centerY - height / 2), minY, maxY),
    width,
    height,
    rotation: rotation > 180 ? rotation - 360 : rotation,
  };
}

function overlapsGeometry(first, second) {
  const a = { ...first, rotation: Number(first.rotation ?? 0) };
  const b = { ...second, rotation: Number(second.rotation ?? 0) };
  const aRadians = a.rotation * Math.PI / 180;
  const bRadians = b.rotation * Math.PI / 180;
  const aCos = Math.cos(aRadians); const aSin = Math.sin(aRadians);
  const bCos = Math.cos(bRadians); const bSin = Math.sin(bRadians);
  const aHalfW = a.width / 2; const aHalfH = a.height / 2;
  const bHalfW = b.width / 2; const bHalfH = b.height / 2;
  const dx = (a.x + aHalfW) - (b.x + bHalfW);
  const dy = (a.y + aHalfH) - (b.y + bHalfH);
  const dot = Math.abs(aCos * bCos + aSin * bSin);
  const cross = Math.abs(aSin * bCos - aCos * bSin);
  return Math.abs(dx * aCos + dy * aSin) < aHalfW + bHalfW * dot + bHalfH * cross
    && Math.abs(-dx * aSin + dy * aCos) < aHalfH + bHalfW * cross + bHalfH * dot
    && Math.abs(dx * bCos + dy * bSin) < bHalfW + aHalfW * dot + aHalfH * cross
    && Math.abs(-dx * bSin + dy * bCos) < bHalfH + aHalfW * cross + aHalfH * dot;
}

function zoneGeometry(zone) {
  return {
    x: Number(zone.zoneX), y: Number(zone.zoneY),
    width: Number(zone.zoneWidth), height: Number(zone.zoneHeight),
    rotation: Number(zone.zoneRotation ?? 0),
  };
}

function overlapsStage(geometry, venue) {
  return venue.stageX != null && overlapsGeometry(geometry, {
    x: Number(venue.stageX), y: Number(venue.stageY),
    width: Number(venue.stageWidth), height: Number(venue.stageHeight), rotation: 0,
  });
}

/**
 * Trinh bien tap dung toa do noi bo nhung khong bat nguoi van hanh phai biet
 * toa do. Cac gia tri chi duoc sinh tu thao tac ve, keo, doi kich thuoc va xoay.
 */
function ZoneLayoutEditor({ venue, zones, editingZoneId, form, onGeometryChange, onClear }) {
  const svgRef = useRef(null);
  const previewRef = useRef(null);
  const [interaction, setInteraction] = useState(null);
  const [drawMode, setDrawMode] = useState(false);
  const [preview, setPreview] = useState(null);
  const [notice, setNotice] = useState('');
  const mapWidth = Number(venue.mapWidth);
  const mapHeight = Number(venue.mapHeight);
  const geometry = geometryFromForm(form);
  const canDraw = Number.isFinite(mapWidth) && mapWidth > 0 && Number.isFinite(mapHeight) && mapHeight > 0;
  const level = Number(form.zoneLevel) || 1;
  const existingZones = zones.filter((z) => String(z.zoneID) !== String(editingZoneId)
    && z.zoneStatus === 'Active' && (z.zoneLevel ?? 1) === level
    && z.zoneX != null && z.zoneY != null && z.zoneWidth != null && z.zoneHeight != null);

  const violationFor = useCallback((next) => {
    if (overlapsStage(next, venue)) return 'Khu chồng lên sân khấu. Hãy kéo vùng ra ngoài sân khấu.';
    if (existingZones.some((zone) => overlapsGeometry(next, zoneGeometry(zone)))) {
      return `Khu chồng lên khu khác ở tầng ${level}. Hãy kéo hoặc thu nhỏ vùng.`;
    }
    return null;
  }, [existingZones, level, venue]);

  const setPreviewGeometry = useCallback((next) => {
    const nextPreview = { geometry: next, violation: violationFor(next) };
    previewRef.current = nextPreview;
    setPreview(nextPreview);
    setNotice(nextPreview.violation ?? '');
  }, [violationFor]);

  const clearPreview = () => {
    previewRef.current = null;
    setPreview(null);
  };

  const commitGeometry = useCallback((next) => {
    onGeometryChange({
      zoneX: String(Math.round(next.x)),
      zoneY: String(Math.round(next.y)),
      zoneWidth: String(Math.round(next.width)),
      zoneHeight: String(Math.round(next.height)),
      zoneRotation: String(Math.round(next.rotation * 10) / 10),
    });
  }, [onGeometryChange]);

  const pointAt = useCallback((event) => {
    const rect = svgRef.current?.getBoundingClientRect();
    if (!rect) return null;
    return {
      x: clamp(snap((event.clientX - rect.left) / rect.width * mapWidth), 0, mapWidth),
      y: clamp(snap((event.clientY - rect.top) / rect.height * mapHeight), 0, mapHeight),
    };
  }, [mapWidth, mapHeight]);

  const capture = (event) => svgRef.current?.setPointerCapture?.(event.pointerId);

  const startDrawing = (event) => {
    if (!canDraw || (geometry && !drawMode)) return;
    const point = pointAt(event);
    if (!point) return;
    capture(event);
    clearPreview();
    setNotice('');
    setInteraction({ type: 'draw', origin: point, rotation: 0 });
    const initial = fitGeometry({ x: point.x, y: point.y, width: 24, height: 24, rotation: 0 }, mapWidth, mapHeight);
    if (initial) setPreviewGeometry(initial);
  };

  const startMove = (event) => {
    if (!geometry) return;
    event.stopPropagation();
    const point = pointAt(event);
    if (!point) return;
    capture(event);
    clearPreview();
    setNotice('');
    setInteraction({ type: 'move', origin: point, base: geometry });
  };

  const startResize = (event) => {
    if (!geometry) return;
    event.stopPropagation();
    const point = pointAt(event);
    if (!point) return;
    capture(event);
    clearPreview();
    setNotice('');
    setInteraction({ type: 'resize', origin: point, base: geometry });
  };

  const movePointer = (event) => {
    if (!interaction) return;
    const point = pointAt(event);
    if (!point) return;
    let candidate;
    if (interaction.type === 'draw') {
      candidate = {
        x: Math.min(interaction.origin.x, point.x),
        y: Math.min(interaction.origin.y, point.y),
        width: Math.abs(point.x - interaction.origin.x),
        height: Math.abs(point.y - interaction.origin.y),
        rotation: interaction.rotation,
      };
    } else if (interaction.type === 'move') {
      candidate = {
        ...interaction.base,
        x: interaction.base.x + point.x - interaction.origin.x,
        y: interaction.base.y + point.y - interaction.origin.y,
      };
    } else {
      candidate = {
        ...interaction.base,
        width: interaction.base.width + point.x - interaction.origin.x,
        height: interaction.base.height + point.y - interaction.origin.y,
      };
    }
    const next = fitGeometry(candidate, mapWidth, mapHeight);
    if (next) setPreviewGeometry(next);
  };

  const endPointer = (event) => {
    if (!interaction) return;
    svgRef.current?.releasePointerCapture?.(event.pointerId);
    const completedPreview = previewRef.current;
    const cancelled = event.type === 'pointercancel';
    clearPreview();
    setInteraction(null);
    if (drawMode) setDrawMode(false);
    if (!cancelled && completedPreview?.geometry && !completedPreview.violation) {
      commitGeometry(completedPreview.geometry);
    } else if (!cancelled && completedPreview?.violation) {
      setNotice('Vùng vừa thả không được lưu vì chồng lên đối tượng khác.');
    }
  };

  const rotate = (delta) => {
    if (!geometry) return;
    const next = fitGeometry({ ...geometry, rotation: geometry.rotation + delta }, mapWidth, mapHeight);
    if (!next) {
      setNotice('Khu này sẽ vượt khỏi mặt bằng nếu xoay thêm. Hãy thu nhỏ hoặc di chuyển khu trước.');
      return;
    }
    const violation = violationFor(next);
    if (violation) {
      setNotice(violation);
      return;
    }
    setNotice('');
    commitGeometry(next);
  };

  if (!canDraw) {
    return <div className="alert alert--warning">Hãy tạo mặt bằng ở Bước 1 trước khi vẽ khu.</div>;
  }

  const displayedGeometry = preview?.geometry ?? geometry;
  const hasInvalidPreview = !!preview?.violation;
  const centerX = displayedGeometry ? displayedGeometry.x + displayedGeometry.width / 2 : 0;
  const centerY = displayedGeometry ? displayedGeometry.y + displayedGeometry.height / 2 : 0;

  return (
    <div className="venue-layout-editor">
      <div className="venue-layout-editor__floor" aria-live="polite">
        <span>Đang bố trí</span>
        <strong>{level === 1 ? 'Tầng trệt' : `Tầng ${level}`}</strong>
        <span>· {existingZones.length} khu tham chiếu trên tầng này</span>
      </div>
      <div className="venue-layout-editor__toolbar" aria-label="Công cụ bố trí khu">
        <button type="button" className="btn-outline" onClick={() => { clearPreview(); setNotice(''); setDrawMode(true); }}>
          {geometry ? 'Vẽ lại vùng khu' : 'Vẽ vùng khu'}
        </button>
        <button type="button" className="btn-outline" disabled={!geometry} onClick={() => rotate(-5)}>Xoay trái</button>
        <button type="button" className="btn-outline" disabled={!geometry} onClick={() => rotate(5)}>Xoay phải</button>
        {geometry && <button type="button" className="btn-outline" onClick={onClear}>Bỏ vị trí khỏi sơ đồ</button>}
      </div>

      <svg
        ref={svgRef}
        className={`venue-layout-editor__canvas${drawMode || !geometry ? ' is-drawing' : ''}`}
        viewBox={`0 0 ${mapWidth} ${mapHeight}`}
        role="application"
        aria-label="Mặt bằng để vẽ và sắp xếp khu ghế"
        onPointerDown={startDrawing}
        onPointerMove={movePointer}
        onPointerUp={endPointer}
        onPointerCancel={endPointer}
      >
        <defs>
          <pattern id="venue-layout-grid" width="20" height="20" patternUnits="userSpaceOnUse">
            <path d="M 20 0 L 0 0 0 20" fill="none" stroke="var(--border-subtle)" strokeWidth="1" />
          </pattern>
        </defs>
        <rect width={mapWidth} height={mapHeight} fill="url(#venue-layout-grid)" />
        <rect x={0.5} y={0.5} width={mapWidth - 1} height={mapHeight - 1}
          fill="none" stroke="var(--border-strong)" strokeWidth="1" />
        {venue.stageX != null && (
          <g>
            <rect x={venue.stageX} y={venue.stageY} width={venue.stageWidth} height={venue.stageHeight}
              rx={8} fill="var(--surface-inverse)" />
            <text x={venue.stageX + venue.stageWidth / 2} y={venue.stageY + venue.stageHeight / 2}
              textAnchor="middle" dominantBaseline="central" fill="var(--text-inverse)"
              style={{ fontSize: 18, fontWeight: 600, letterSpacing: '0.12em', pointerEvents: 'none' }}>SÂN KHẤU</text>
          </g>
        )}
        {existingZones.map((zone) => {
          const x = zone.zoneX; const y = zone.zoneY;
          const width = zone.zoneWidth; const height = zone.zoneHeight;
          const cx = x + width / 2; const cy = y + height / 2;
          return (
            <g key={zone.zoneID} transform={zone.zoneRotation ? `rotate(${zone.zoneRotation} ${cx} ${cy})` : undefined}>
              <rect x={x} y={y} width={width} height={height} rx={10}
                fill="var(--surface-sunken)" stroke="var(--border)" strokeWidth="1.5" />
              <text x={cx} y={cy} textAnchor="middle" dominantBaseline="central" fill="var(--text-muted)"
                style={{ fontSize: 14, fontWeight: 600, pointerEvents: 'none' }}>{zone.zoneName ?? zone.zoneCode}</text>
            </g>
          );
        })}
        {displayedGeometry && (
          <g transform={displayedGeometry.rotation ? `rotate(${displayedGeometry.rotation} ${centerX} ${centerY})` : undefined}>
            <rect x={displayedGeometry.x} y={displayedGeometry.y} width={displayedGeometry.width} height={displayedGeometry.height} rx={10}
              fill={hasInvalidPreview ? 'var(--red-bg)' : 'var(--accent-subtle)'}
              stroke={hasInvalidPreview ? 'var(--red-border)' : 'var(--accent)'}
              strokeWidth="2.5" onPointerDown={hasInvalidPreview ? undefined : startMove}
              style={{ cursor: hasInvalidPreview ? 'not-allowed' : 'grab' }} />
            <text x={centerX} y={centerY} textAnchor="middle" dominantBaseline="central" fill={hasInvalidPreview ? 'var(--red-text)' : 'var(--accent)'}
              style={{ fontSize: 15, fontWeight: 700, pointerEvents: 'none' }}>{hasInvalidPreview ? 'VỊ TRÍ KHÔNG HỢP LỆ' : (form.zoneName || form.zoneCode || 'Khu mới')}</text>
            {!hasInvalidPreview && (
              <rect x={displayedGeometry.x + displayedGeometry.width - 10} y={displayedGeometry.y + displayedGeometry.height - 10} width={20} height={20}
                rx={3} fill="var(--accent)" stroke="var(--surface-raised)" strokeWidth="2" onPointerDown={startResize}
                style={{ cursor: 'nwse-resize' }} />
            )}
          </g>
        )}
      </svg>
      <p className="venue-layout-editor__hint">
        {preview?.violation
          ? 'Vùng đỏ không hợp lệ và sẽ không được ghi khi thả chuột.'
          : drawMode || !geometry
          ? 'Kéo trên mặt bằng để vẽ vùng của khu. Hệ thống tự căn theo lưới và giữ khu trong khung.'
          : 'Kéo vùng để di chuyển; kéo ô vuông ở góc để đổi kích thước. Sân khấu và các khu hiện có là mốc tham chiếu.'}
      </p>
      {notice && <div className="alert alert--warning">{notice}</div>}
    </div>
  );
}

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
      tone={editing ? 'edit' : 'create'}
      subtitle="Mỗi khu là một vùng ghế có vị trí, kích thước và hướng trên mặt bằng. Góc xoay dùng cho các khán đài hướng về sân khấu."
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
        zones={zones}
        editId={editId}
        zone={zone}
        onDone={onDone}
        onCreated={() => setNewSeq((n) => n + 1)}
      />
    </Panel>
  );
}

function ZoneFields({ venue, zones, editId, zone, onDone, onCreated }) {
  const act = useAction();
  const [f, setF] = useState(() => zoneToForm(zone));
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  const patch = (changes) => setF((s) => ({ ...s, ...changes }));
  const num = (v) => (String(v).trim() === '' ? null : Number(v));

  const editing = !!editId;
  const geometry = geometryFromForm(f);
  const mapConfigured = Number(venue.mapWidth) > 0 && Number(venue.mapHeight) > 0;

  const submit = (e) => {
    e.preventDefault();
    const clearGeometry = editing && [f.zoneX, f.zoneY, f.zoneWidth, f.zoneHeight]
      .every((value) => String(value).trim() === '');
    const geo = clearGeometry ? {
      zoneType: 'Seated',
      zoneLevel: num(f.zoneLevel),
      clearGeometry: true,
    } : {
      zoneType: 'Seated',
      zoneLevel: num(f.zoneLevel),
      zoneX: num(f.zoneX), zoneY: num(f.zoneY),
      zoneWidth: num(f.zoneWidth), zoneHeight: num(f.zoneHeight),
      zoneRotation: num(f.zoneRotation),
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
        <Field label="Tầng / khán đài" hint="1 = tầng trệt. Sơ đồ hiện từng tầng một.">
          <input type="number" min="1" value={f.zoneLevel} onChange={(e) => set('zoneLevel')(e.target.value)} />
        </Field>
      </div>

      <div style={{ marginTop: 'var(--space-5)' }}>
        <ZoneLayoutEditor
          venue={venue}
          zones={zones}
          editingZoneId={editId}
          form={f}
          onGeometryChange={patch}
          onClear={() => patch({ zoneX: '', zoneY: '', zoneWidth: '', zoneHeight: '', zoneRotation: '' })}
        />
      </div>

      <div className="field-hint" style={{ marginTop: 'var(--space-3)' }}>
        Toạ độ chỉ là dữ liệu nội bộ do trình biên tập tạo ra. Bạn chỉ cần vẽ, kéo,
        đổi kích thước hoặc xoay khu theo mặt bằng thực tế; database vẫn kiểm tra
        ranh giới và không cho khu chồng lên sân khấu.
      </div>

      <button className="btn-primary" style={{ marginTop: 'var(--space-4)' }}
              disabled={act.busy || (!editing && !f.zoneCode.trim()) || (mapConfigured && !geometry)}>
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

/** Đảo của rowLabel: A = 0, Z = 25, AA = 26. */
function rowIndex(label) {
  const normalized = label.trim().toUpperCase();
  if (!/^[A-Z]{1,3}$/.test(normalized)) return null;
  return [...normalized].reduce((value, char) => value * 26 + char.charCodeAt(0) - 64, 0) - 1;
}

function SeatGridForm({ zones, onDone }) {
  const act = useAction();
  const [zoneId, setZoneId] = useState('');
  const [rows, setRows] = useState('3');
  const [cols, setCols] = useState('8');
  const [startRow, setStartRow] = useState('A');
  const [progress, setProgress] = useState('');

  const seatedZones = zones.filter((z) => z.zoneType === 'Seated'
    && z.zoneStatus === 'Active'
    && z.zoneX != null && z.zoneY != null && z.zoneWidth != null && z.zoneHeight != null);
  const zone = zones.find((z) => String(z.zoneID) === String(zoneId));

  const plan = useMemo(() => {
    const r = Number(rows), c = Number(cols);
    if (!Number.isInteger(r) || !Number.isInteger(c) || r < 1 || c < 1) return null;
    const offset = rowIndex(startRow);
    if (offset == null) return null;
    return { r, c, total: r * c, first: rowLabel(offset), last: rowLabel(offset + r - 1), offset };
  }, [rows, cols, startRow]);

  const submit = (e) => {
    e.preventDefault();
    if (!plan || !zone) return;
    act.run(async () => {
      const seats = [];
      for (let ri = 0; ri < plan.r; ri += 1) {
        const label = rowLabel(plan.offset + ri);
        for (let ci = 1; ci <= plan.c; ci += 1) {
          seats.push({
            seatCode: `${zone.zoneCode}-${label}${ci}`,
            seatLabel: `${label}${ci}`,
            seatRowLabel: label,
            seatColumnNumber: ci,
          });
        }
      }
      setProgress(`Đang tạo trọn bộ ${plan.total} ghế…`);
      try {
        await api.post(`/admin/zones/${zone.zoneID}/seats/batch`, { seats });
        await onDone();
        return plan.total;
      } finally {
        setProgress('');
      }
    }, (made) => `Đã tạo ${made ?? 0} ghế trong ${zone.zoneName ?? zone.zoneCode}.`);
  };

  return (
    <Panel
      title="Bước 3 — Tạo ghế theo lưới"
      tone="create"
      subtitle="Mỗi ghế được gán HÀNG và SỐ THỨ TỰ TRONG HÀNG. Mã ghế chỉ là định danh; hai trường này mới là vị trí, và là thứ cho phép in ra địa chỉ chỗ ngồi mà người thường hiểu được — “Khu VIP, hàng C, ghế 12”."
    >
      <form onSubmit={submit}>
        <div className="field-grid">
          <Field label="Khu" hint="Chỉ hiện khu đang hoạt động đã được đặt trên mặt phẳng." required>
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
          <Field label="Hàng bắt đầu" hint="Để tiếp nối khu đã có, ví dụ bắt đầu từ D hoặc AA.">
            <input value={startRow} onChange={(e) => setStartRow(e.target.value)} maxLength={3} />
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
                <td>Có ghế</td>
                <td>{z.zoneLevel ?? '—'}</td>
                <td>{z.zoneX != null ? `${z.zoneX}, ${z.zoneY}` : <span style={{ color: 'var(--amber-text)' }}>chưa đặt</span>}</td>
                <td>{z.zoneWidth != null ? `${z.zoneWidth}×${z.zoneHeight}` : '—'}</td>
                <td>{z.zoneRotation != null ? `${z.zoneRotation}°` : '—'}</td>
                <td>{z.seatCount}</td>
                <td>{ADMIN_STATUS_LABEL[z.zoneStatus] ?? z.zoneStatus}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Panel>
  );
}
