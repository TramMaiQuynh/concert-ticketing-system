import {
  useMemo, useState, useCallback, useEffect, useRef,
} from 'react';
import api, { apiError } from '../api/client';
import { formatMoney } from '../lib/format';
import { geometryToPoints, pointsToSvgPath } from '../lib/geometry';
import { InventoryStatus, isSeatSelectable, SEAT_LEGEND, SELECTED_PSEUDO_STATUS } from '../domain/enums';
import { Button, Alert, Skeleton } from './ui';
import { IconChevronLeft } from './ui/icons';

/**
 * SƠ ĐỒ CHỖ NGỒI — HAI MỨC, NHIỀU TẦNG.
 *
 * MỘT contract/MỘT renderer cho cả venue Zone/Seat cũ (mặt phẳng chữ nhật, nhiều
 * `ZoneLevel` trên cùng canvas) lẫn venue StagePass (nhiều tầng, mỗi tầng canvas
 * riêng, khu dạng đa giác tự do) — xem docs/stagepass-architecture.md D.3/D.6:
 * ConcertRepository.GetSeatMapAsync đã quy đổi cả hai nguồn về CÙNG một hình dạng
 * DTO (`Floors[].Zones[].GeometryJson`), nên component này không cần biết — và
 * không được phép biết — dữ liệu đến từ đâu. (Từng có hai component riêng: một
 * cho Zone hình chữ nhật, một cho polygon nhiều tầng của StagePass — gộp lại
 * đúng nguyên tắc "không viết renderer thứ hai" mà tài liệu kiến trúc đặt ra.)
 *
 * Mức 1 (tổng quan): toàn bộ MỘT tầng. Mỗi khu là một hình (chữ nhật hoặc đa
 *   giác — cùng một hàm vẽ `pointsToSvgPath`) có vị trí thật so với sân khấu, kèm
 *   số chỗ còn trống và khoảng giá. KHÔNG vẽ ghế.
 * Mức 2 (chi tiết):  bấm vào một khu → tải ghế của riêng khu đó và vẽ thành lưới
 *   lớn theo hàng/cột (vị trí ghế luôn suy từ `rowLabel`/`columnNumber`, đúng chủ
 *   ý thiết kế "ghế không lưu toạ độ tuyệt đối" — xem TemplateSeat.sql), kèm sơ đồ
 *   thu nhỏ đánh dấu khu đang xem đứng ở đâu trong tầng.
 *
 * VÌ SAO PHẢI CHIA HAI MỨC — không phải để đẹp, mà vì phép đo: hệ thống này tốn
 * 234 byte mỗi ghế. Trả hết ghế của một arena 20.000 chỗ là 4,5 MB mỗi lần mở
 * trang; sân vận động 60.000 chỗ là 13 MB. Chia hai mức giữ bước đầu ở vài KB dù
 * địa điểm lớn cỡ nào.
 *
 * TOẠ ĐỘ: SVG dùng `viewBox` đặt đúng bằng hệ toạ độ của tầng trong database, nên
 * số liệu được dùng thẳng làm toạ độ vẽ — không có bước quy đổi nào để sai — và
 * tự co giãn từ 390px tới 1400px mà không cần media query.
 */

const PAD_X = 16;
/* 46 (thay vì 30) để dải chỉ hướng sân khấu ở mức 2 — mũi tên + nhãn — nằm gọn
   trong phần đệm trên, không đè lên hàng ghế đầu. */
const PAD_TOP = 46;
const PAD_BOTTOM = 14;
const CELL = 44;

const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

function seatColors(status, selected) {
  if (selected) return { fill: 'var(--accent)', stroke: 'var(--accent)', text: 'var(--text-on-accent)' };
  switch (status) {
    case InventoryStatus.Available:
      return { fill: 'var(--surface-raised)', stroke: 'var(--border-strong)', text: 'var(--text-secondary)' };
    case InventoryStatus.OnHold:
      return { fill: 'var(--amber-bg)', stroke: 'var(--amber-border)', text: 'var(--amber-text)' };
    case InventoryStatus.OnHoldForWaitlist:
      return { fill: 'var(--violet-bg)', stroke: 'var(--violet-border)', text: 'var(--violet-text)' };
    case InventoryStatus.Booked:
      return { fill: 'var(--red-bg)', stroke: 'var(--red-border)', text: 'var(--red-text)' };
    default:
      return { fill: 'var(--surface-sunken)', stroke: 'var(--border-subtle)', text: 'var(--text-muted)' };
  }
}

/**
 * Khu hết chỗ luôn xám mờ bất kể giá — còn khu còn chỗ tô theo BẬC GIÁ
 * (priceScale, xem buildPriceScale) thay vì chỉ một màu "còn chỗ" duy nhất.
 * Ticketmaster/Eventbrite dùng đúng quy ước này: đậm nhạt theo tiền, không
 * theo còn/hết — còn/hết đã có chữ số lượng ghi ngay trong khu rồi, không cần
 * màu nhắc lại.
 */
function zoneColors(zone, priceScale) {
  if (zone.availableCount === 0) {
    return { fill: 'var(--surface-sunken)', stroke: 'var(--border-subtle)', text: 'var(--text-muted)' };
  }
  const tierPct = priceScale ? priceScale(zone) : 100;
  return {
    fill: `color-mix(in srgb, var(--accent) ${tierPct}%, var(--surface-raised))`,
    stroke: 'var(--border-strong)',
    text: tierPct >= 65 ? 'var(--text-on-accent)' : 'var(--text)',
  };
}

/**
 * Xây bậc giá từ TOÀN BỘ khu có ghế trong cả map (mọi tầng, không chỉ tầng
 * đang xem) — để đổi tầng không làm cùng một khoảng giá đổi màu khác đi.
 * 4 bậc (25/50/75/100% pha với --accent, xem zoneColors) là đủ phân biệt bằng
 * mắt mà không cần một palette màu mới ngoài --accent đã chọn cho toàn hệ
 * thống — nhiều màu hơn cho cùng MỘT tông biến hoá không phá vỡ quy ước "chỉ
 * một màu nhấn" đã lập ra khi thiết kế lại giao diện.
 */
function buildPriceScale(floors) {
  const prices = [];
  for (const f of floors) {
    for (const z of f.zones) {
      if (z.availableCount > 0 && z.minPrice != null) prices.push(Number(z.minPrice));
    }
  }
  if (prices.length === 0) return () => 100;
  const min = Math.min(...prices);
  const max = Math.max(...prices);
  if (min === max) return () => 100;
  const tiers = [25, 45, 70, 100];
  return (zone) => {
    const p = Number(zone.minPrice ?? min);
    const ratio = (p - min) / (max - min);
    const idx = Math.min(tiers.length - 1, Math.floor(ratio * tiers.length));
    return tiers[idx];
  };
}

/**
 * Trọng tâm DIỆN TÍCH (shoelace) — không phải trung bình cộng các đỉnh.
 *
 * Với đa giác không đều (khu StagePass vẽ tay), trung bình cộng đỉnh rơi ra
 * NGOÀI hình — nhãn khu và chữ "SÂN KHẤU" bị đẩy ra ngoài viền khu. Trọng tâm
 * diện tích luôn nằm trong hình. Đa giác suy biến (diện tích ~0) quay về trung
 * bình cộng đỉnh để không bao giờ trả NaN — NaN trong viewBox làm cả SVG trắng.
 */
function centroid(points) {
  const n = points?.length ?? 0;
  if (n === 0) return [0, 0];
  const meanX = points.reduce((s, p) => s + p[0], 0) / n;
  const meanY = points.reduce((s, p) => s + p[1], 0) / n;
  if (n < 3) return [meanX, meanY];

  let area = 0;
  let sx = 0;
  let sy = 0;
  for (let i = 0; i < n; i += 1) {
    const [x0, y0] = points[i];
    const [x1, y1] = points[(i + 1) % n];
    const cross = x0 * y1 - x1 * y0;
    area += cross;
    sx += (x0 + x1) * cross;
    sy += (y0 + y1) * cross;
  }
  if (Math.abs(area) < 1e-9) return [meanX, meanY];
  return [sx / (3 * area), sy / (3 * area)];
}

/** Hộp bao của một danh sách đỉnh; null khi rỗng. */
function bboxOfPoints(points) {
  if (!points?.length) return null;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (const [x, y] of points) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return { minX, minY, maxX, maxY, w: maxX - minX, h: maxY - minY };
}

/** Math.max(...arr) nổ stack khi mảng lớn (khu hợp nhất có thể vài nghìn ghế). */
function maxOf(list) {
  let m = -Infinity;
  for (const v of list) if (v > m) m = v;
  return m;
}
function minOf(list) {
  let m = Infinity;
  for (const v of list) if (v < m) m = v;
  return m;
}

/** Venue cũ đặt tên tầng bằng số (ZoneLevel); StagePass đặt tên thật (FloorName). */
function floorLabel(floor) {
  if (floor.floorName) return floor.floorName;
  if (/^\d+$/.test(floor.floorKey)) return floor.floorKey === '1' ? 'Tầng trệt' : `Tầng ${floor.floorKey}`;
  return floor.floorKey;
}

/**
 * PHƯƠNG THẬT của sân khấu so với khu đang xem — suy từ hình học đã lưu, không
 * phải một mũi tên in cứng.
 *
 * Bản trước in cứng "↑ HƯỚNG SÂN KHẤU" chỉ lên trên cho MỌI khu. Điều đó chỉ
 * đúng với khu chính diện. Một khối nằm BÊN TRÁI sân khấu — bố trí hai khối hai
 * bên trái/phải sân khấu, mỗi khối xoay một góc nhỏ hướng về sân khấu — sẽ được
 * chỉ lên trên, tức là chỉ sang khối bên cạnh.
 *
 * Trả về góc (độ, hệ màn hình: 0° = sang phải, dương = kim đồng hồ, khớp
 * `rotate()` của SVG) để mũi tên xoay đúng hướng thật, hoặc null khi tầng
 * KHÔNG có vật thể sân khấu — lúc đó không vẽ gì, thay vì bịa ra một hướng.
 *
 * `ObjectType` chỉ nhận 8 giá trị ('Stage','Aisle','Wall','Entrance','Restroom',
 * 'Bar','Text','Icon' — CHK_ConcertMapRevisionObject_ObjectType), nên 'Stage' là
 * giá trị DUY NHẤT đánh dấu sân khấu; không cần đoán theo Label.
 */
function stageBearing(zoneGeometryJson, floor) {
  const stage = (floor?.objects ?? []).find((o) => o.objectType === 'Stage');
  if (!stage) return null;
  const zonePts = geometryToPoints(zoneGeometryJson);
  const stagePts = geometryToPoints(stage.geometryJson);
  if (!zonePts || !stagePts) return null;
  const [zx, zy] = centroid(zonePts);
  const [sx, sy] = centroid(stagePts);
  const dx = sx - zx;
  const dy = sy - zy;
  if (Math.hypot(dx, dy) < 1e-6) return null;
  return (Math.atan2(dy, dx) * 180) / Math.PI;
}

/* ══════════════════════════════════════════════════════════════════════════
   MỨC 1 — TOÀN BỘ MỘT TẦNG
   `compact` dùng cho sơ đồ thu nhỏ ở mức chi tiết: bỏ chữ, bỏ tương tác.
   ══════════════════════════════════════════════════════════════════════════ */
function FloorOverview({
  floor, onPickZone, activeZoneId, compact, viewBox, priceScale, svgRef, children, ...svgProps
}) {
  const vb = viewBox ?? { x: 0, y: 0, w: floor.canvasWidth, h: floor.canvasHeight };
  return (
    <svg
      ref={svgRef}
      viewBox={`${vb.x} ${vb.y} ${vb.w} ${vb.h}`}
      preserveAspectRatio="xMidYMid meet"
      role={compact ? 'img' : 'group'}
      aria-label={compact ? 'Vị trí khu đang xem trong tầng' : `Sơ đồ ${floorLabel(floor)} — chọn một khu`}
      style={{ width: '100%', height: 'auto', display: 'block' }}
      {...svgProps}
    >
      {floor.objects.map((o, i) => {
        const pts = geometryToPoints(o.geometryJson);
        if (!pts) return null;
        const isStage = o.objectType === 'Stage';
        return (
          <g key={i}>
            <path d={pointsToSvgPath(pts)} fill={isStage ? 'var(--surface-inverse)' : 'var(--surface-sunken)'} />
            {!compact && isStage && (() => {
              const [cx, cy] = centroid(pts);
              return (
                <text x={cx} y={cy} textAnchor="middle" dominantBaseline="central" fill="var(--text-inverse)"
                      style={{ fontSize: 20, fontWeight: 600, letterSpacing: '0.14em' }}>
                  {(o.label || 'SÂN KHẤU').toUpperCase()}
                </text>
              );
            })()}
          </g>
        );
      })}

      {floor.zones.map((zone) => {
        const pts = geometryToPoints(zone.geometryJson);
        if (!pts) return null;
        const c = zoneColors(zone, priceScale);
        const isActive = zone.zoneID === activeZoneId;
        const clickable = !compact && zone.seatCount > 0;
        const [cx, cy] = centroid(pts);
        const priceLabel = zone.minPrice == null ? null
          : zone.minPrice === zone.maxPrice ? formatMoney(zone.minPrice)
          : `${formatMoney(zone.minPrice)} – ${formatMoney(zone.maxPrice)}`;

        return (
          <g
            key={zone.zoneID}
            className="seatmap-zone"
            role={clickable ? 'button' : undefined}
            tabIndex={clickable ? 0 : undefined}
            aria-label={clickable
              ? `${zone.zoneName ?? zone.zoneCode}, còn ${zone.availableCount} trên ${zone.seatCount} chỗ`
                + `${priceLabel ? `, ${priceLabel}` : ''}. Bấm để chọn ghế.`
              : undefined}
            style={{ cursor: clickable ? 'pointer' : 'default' }}
            onClick={() => clickable && onPickZone(zone)}
            onKeyDown={(e) => {
              if (clickable && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); onPickZone(zone); }
            }}
          >
            <path
              d={pointsToSvgPath(pts)}
              fill={c.fill}
              stroke={isActive ? 'var(--accent)' : c.stroke}
              strokeWidth={isActive ? 3 : 1.5}
              strokeLinejoin="round"
            />
            {!compact && (
              <>
                <text x={cx} y={cy - (priceLabel ? 12 : 0)} textAnchor="middle" dominantBaseline="central" fill={c.text}
                      style={{ fontSize: 16, fontWeight: 600 }}>
                  {zone.zoneName ?? zone.zoneCode}
                </text>
                <text x={cx} y={cy + 10} textAnchor="middle" dominantBaseline="central" fill={c.text}
                      style={{ fontSize: 12, opacity: 0.78 }}>
                  {zone.availableCount === 0 ? 'Hết chỗ' : `${zone.availableCount}/${zone.seatCount} chỗ · ${priceLabel ?? ''}`}
                </text>
              </>
            )}
          </g>
        );
      })}
      {children}
    </svg>
  );
}

/** Phóng to tối đa ~8 lần (12% chiều rộng gốc) — đủ để đọc số khu mà không rời hẳn bối cảnh toàn tầng. */
const MIN_ZOOM_RATIO = 0.12;

function clampView(next, fullW, fullH) {
  const w = clamp(next.w, fullW * MIN_ZOOM_RATIO, fullW);
  const h = w * (fullH / fullW); // khoá đúng tỉ lệ canvas gốc — zoom không bao giờ làm méo hình
  return {
    w, h,
    x: clamp(next.x, 0, Math.max(0, fullW - w)),
    y: clamp(next.y, 0, Math.max(0, fullH - h)),
  };
}

/**
 * Bọc FloorOverview bằng pan/zoom thật (cuộn chuột để phóng to đúng tại vị trí
 * con trỏ, kéo để lia) — thay cho việc chỉ hiện trọn tầng tĩnh. Khi đã phóng
 * to/lia ra khỏi khung nhìn gốc, một MINIMAP NỔI hiện ở góc, dùng lại chính
 * FloorOverview ở chế độ compact cộng một khung chữ nhật đánh dấu vùng đang
 * xem — đúng cách Ticketmaster/Eventbrite định hướng người xem trên một bản
 * đồ lớn. Bấm vào minimap để nhảy thẳng camera tới đó.
 *
 * Phân biệt "kéo để lia" với "bấm để chọn khu" bằng ngưỡng dịch chuyển: dưới
 * 4px kể từ pointerdown vẫn tính là một cú bấm, onClick của khu chạy bình
 * thường; vượt ngưỡng thì coi là lia, `justPanned` chặn onClick kế tiếp — nếu
 * không mọi lượt kéo nhẹ sẽ vô tình chọn nhầm khu ở điểm vừa buông chuột.
 */
function PannableFloorView({ floor, onPickZone, priceScale }) {
  const svgRef = useRef(null);
  const fullW = floor.canvasWidth;
  const fullH = floor.canvasHeight;
  const fullView = useMemo(() => ({ x: 0, y: 0, w: fullW, h: fullH }), [fullW, fullH]);

  const [view, setView] = useState(fullView);
  useEffect(() => { setView(fullView); }, [fullView]); // đổi tầng -> reset khung nhìn

  const dragRef = useRef(null);       // { startX, startY, startView, moved }
  const justPannedRef = useRef(false);
  const [isDragging, setIsDragging] = useState(false); // chi de doi con tro 'grabbing' — doc ref trong style se khong bao gio ve lai

  const zoomAt = useCallback((clientX, clientY, factor) => {
    const rect = svgRef.current?.getBoundingClientRect();
    if (!rect || rect.width === 0) return;
    const fx = (clientX - rect.left) / rect.width;
    const fy = (clientY - rect.top) / rect.height;
    setView((v) => {
      const worldX = v.x + fx * v.w;
      const worldY = v.y + fy * v.h;
      const newW = v.w * factor;
      const newH = v.h * factor;
      return clampView({ x: worldX - fx * newW, y: worldY - fy * newH, w: newW, h: newH }, fullW, fullH);
    });
  }, [fullW, fullH]);

  const onWheel = (e) => {
    e.preventDefault();
    zoomAt(e.clientX, e.clientY, e.deltaY < 0 ? 0.85 : 1 / 0.85);
  };

  const onPointerDown = (e) => {
    svgRef.current?.setPointerCapture?.(e.pointerId);
    dragRef.current = { startX: e.clientX, startY: e.clientY, startView: view, moved: false };
  };
  const onPointerMove = (e) => {
    if (!dragRef.current) return;
    const rect = svgRef.current?.getBoundingClientRect();
    if (!rect || rect.width === 0) return;
    const dxPx = e.clientX - dragRef.current.startX;
    const dyPx = e.clientY - dragRef.current.startY;
    if (!dragRef.current.moved && Math.hypot(dxPx, dyPx) < 4) return;
    if (!dragRef.current.moved) setIsDragging(true); // dong bo cursor 'grabbing' dung 1 lan, khong doc ref moi render
    dragRef.current.moved = true;
    const { startView } = dragRef.current;
    const dxWorld = (dxPx / rect.width) * startView.w;
    const dyWorld = (dyPx / rect.height) * startView.h;
    setView(clampView({ ...startView, x: startView.x - dxWorld, y: startView.y - dyWorld }, fullW, fullH));
  };
  const onPointerUp = (e) => {
    svgRef.current?.releasePointerCapture?.(e.pointerId);
    justPannedRef.current = !!dragRef.current?.moved;
    dragRef.current = null;
    setIsDragging(false);
  };

  const guardedPick = (zone) => {
    if (justPannedRef.current) { justPannedRef.current = false; return; }
    onPickZone(zone);
  };

  const isZoomedOrPanned = view.w < fullW - 0.5 || view.x > 0.5 || view.y > 0.5;
  const jumpTo = (worldX, worldY) => {
    setView((v) => clampView({ ...v, x: worldX - v.w / 2, y: worldY - v.h / 2 }, fullW, fullH));
  };

  return (
    <div style={{ position: 'relative' }}>
      <div
        onWheel={onWheel}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        style={{ touchAction: 'none', cursor: isDragging ? 'grabbing' : 'grab' }}
      >
        <FloorOverview floor={floor} onPickZone={guardedPick} viewBox={view} priceScale={priceScale} svgRef={svgRef} />
      </div>

      {isZoomedOrPanned && (
        <div
          className="seatmap-minimap-float"
          role="button" tabIndex={0}
          aria-label="Minimap — bấm để nhảy tới vị trí đó trên tầng"
          onClick={(e) => {
            const rect = e.currentTarget.getBoundingClientRect();
            jumpTo(((e.clientX - rect.left) / rect.width) * fullW, ((e.clientY - rect.top) / rect.height) * fullH);
          }}
        >
          <FloorOverview floor={floor} compact priceScale={priceScale} viewBox={fullView}>
            <rect x={view.x} y={view.y} width={view.w} height={view.h} fill="none" stroke="var(--accent)" strokeWidth={Math.max(fullW, fullH) * 0.008} />
          </FloorOverview>
        </div>
      )}

      {isZoomedOrPanned && (
        <button
          type="button"
          className="btn btn--sm btn--secondary seatmap-reset-btn"
          onClick={() => setView(fullView)}
        >
          Về toàn cảnh
        </button>
      )}
    </div>
  );
}

/* ═════════════════════════════════════════════════════════════════════════
   MC 2 — GHẾ TRONG MỘT KHU

   CÓ HAI chế độ vẽ, và chế độ được chọn theo DỮ LIỆU chứ không theo địa điểm:

   'geometry' — khi ghế có toạ độ thật. `ConcertMapRevisionSeat.GeometryJson`
     khác NULL đúng với ghế nằm trên hàng cong/bàn tròn (TemplateSeat.sql), và
     ConcertRepository.GetStagePassSectionAsync có SELECT cột đó. Ghế được vẽ
     ĐÚNG vị trí trong hệ toạ độ của tầng, kèm viền khu thật — nên một khu cong
     hiện ra cong, không bị bẻ thẳng.
   'grid' — khi khu không lưu toạ độ ghế. Lúc đó vị trí tuyệt đối của từng ghế
     KHÔNG tồn tại trong database; lưới hàng/cột suy từ rowLabel/columnNumber là
     cách duy nhất trung thực để vẽ, và ghế vẫn đủ lớn để chạm. Bịa ra một toạ
     độ giả còn tệ hơn. Bản trước vẽ lưới này cho CẢ HAI trường hợp — tức là ném
     đi toạ độ thật ở đúng những địa điểm đã có toạ độ.

   Cả hai chế độ dùng CHUNG một viewBox: hệ toạ độ của tầng. Không có bước quy
   đổi toạ độ nào ở giữa để sai.
   ══════════════════════════════════════════════════════════════════════════ */

/** Dựng hình cho mức 2 — xem khối chú thích ngay trên để biết vì sao có hai chế độ. */
function buildZoneLayout(zone) {
  const seats = zone.seats ?? [];

  const withGeometry = seats
    .map((seat) => ({ seat, pts: geometryToPoints(seat.geometryJson) }))
    .filter((e) => e.pts && e.pts.length >= 3);

  if (withGeometry.length > 0) {
    const zonePts = geometryToPoints(zone.geometryJson);
    const boxes = [
      ...(zonePts ? [bboxOfPoints(zonePts)] : []),
      ...withGeometry.map((e) => bboxOfPoints(e.pts)),
    ].filter(Boolean);
    const minX = minOf(boxes.map((b) => b.minX));
    const minY = minOf(boxes.map((b) => b.minY));
    const maxX = maxOf(boxes.map((b) => b.maxX));
    const maxY = maxOf(boxes.map((b) => b.maxY));
    const span = Math.max(maxX - minX, maxY - minY) || 1;
    const pad = span * 0.06 + 4;
    /* Chừa một dải ở TRÊN cho chỉ hướng sân khấu: chế độ lưới đã có PAD_TOP lo
       việc này, chế độ toạ độ thật phải tự chừa chỗ tương đương, nếu không mũi
       tên đè lên hàng ghế đầu. */
    const headRoom = span * 0.13;
    return {
      X: minX - pad,
      Y: minY - pad - headRoom,
      W: maxX - minX + pad * 2,
      H: maxY - minY + pad * 2 + headRoom,
      rows: [],
      outline: zonePts ? pointsToSvgPath(zonePts) : '',
      placed: withGeometry.map((e) => {
        const b = bboxOfPoints(e.pts);
        const [cx, cy] = centroid(e.pts);
        return { seat: e.seat, pts: e.pts, cx, cy, r: Math.max(b.w, b.h) / 2 };
      }),
    };
  }

  if (!seats.length) return { X: 0, Y: 0, W: 100, H: 100, rows: [], placed: [], outline: '' };

  const rowLabels = [...new Set(seats.map((s) => s.rowLabel ?? '·'))]
    .sort((a, b) => String(a).localeCompare(String(b), 'vi', { numeric: true }));
  const maxCol = maxOf(seats.map((s) => s.columnNumber ?? 1)) || 1;

  // Ô lưới cố định 44 đơn vị — ghế luôn đủ lớn để chạm bằng ngón tay, và khung
  // tự dài ra theo số hàng thay vì bóp ghế lại cho vừa một chiều cao cố định.
  const w = PAD_X * 2 + maxCol * CELL;
  const h = PAD_TOP + PAD_BOTTOM + rowLabels.length * CELL;
  const r = CELL * 0.36;

  return {
    X: 0,
    Y: 0,
    W: w,
    H: h,
    outline: '',
    rows: rowLabels.map((label, ri) => ({
      label,
      x: PAD_X * 0.55,
      y: PAD_TOP + (ri + 0.5) * CELL,
    })),
    placed: seats.map((s) => ({
      seat: s,
      pts: null,
      cx: PAD_X + ((s.columnNumber ?? 1) - 0.5) * CELL,
      cy: PAD_TOP + (rowLabels.indexOf(s.rowLabel ?? '·') + 0.5) * CELL,
      r,
    })),
  };
}
function ZoneSeats({ zone, floor, selected, onToggleSeat, canSelect, onHover }) {
  const { X, Y, W, H, rows, placed, outline } = useMemo(() => buildZoneLayout(zone), [zone]);
  /* Hướng sân khấu suy từ hình học đã lưu, không phải mũi tên in cứng — xem
     stageBearing. null = tầng không có vật thể 'Stage' -> không vẽ gì. */
  const bearing = useMemo(() => stageBearing(zone.geometryJson, floor), [zone.geometryJson, floor]);
  /* Đơn vị dài nhất của khung nhìn: mọi kích thước "phải nhìn thấy được" (độ dày
     nét, cỡ chữ, ngưỡng hiện số ghế) suy từ đây để hai chế độ vẽ co giãn giống
     nhau — chế độ lưới đo bằng ô lưới, chế độ toạ độ thật đo bằng toạ độ tầng. */
  const unit = Math.max(W, H) || 1;

  return (
    <svg
      viewBox={`${X} ${Y} ${W} ${H}`}
      preserveAspectRatio="xMidYMid meet"
      role="group"
      aria-label={`Ghế trong ${zone.zoneName ?? zone.zoneCode}`}
      style={{ width: '100%', height: 'auto', display: 'block' }}
    >
      {/* Viền khu THẬT — chỉ có ở chế độ toạ độ thật, nơi ghế và viền khu cùng
          nằm trong hệ toạ độ của tầng nên đặt cạnh nhau là đúng. */}
      {outline && (
        <path
          d={outline}
          fill="var(--surface-sunken)"
          stroke="var(--border-strong)"
          strokeWidth={unit * 0.002}
          strokeLinejoin="round"
        />
      )}

      {/* Chỉ hướng sân khấu THẬT: mũi tên xoay theo góc suy từ hình học, nên khu
          bên trái được chỉ đúng sang trái/phải chỗ sân khấu nằm. Nhãn để NGOÀI
          nhóm xoay — nếu xoay cả nhãn thì góc gần 180° sẽ thành chữ ngược. */}
      {bearing !== null && (
        <>
          <g
            transform={`translate(${X + W / 2} ${Y + unit * 0.04}) rotate(${bearing})`}
            aria-hidden="true"
          >
            <line
              x1={-unit * 0.05} y1={0} x2={unit * 0.05} y2={0}
              stroke="var(--text-muted)" strokeWidth={unit * 0.0025}
            />
            <path
              d={`M ${unit * 0.05} 0 L ${unit * 0.032} ${-unit * 0.009} L ${unit * 0.032} ${unit * 0.009} Z`}
              fill="var(--text-muted)"
            />
          </g>
          <text
            x={X + W / 2} y={Y + unit * 0.09}
            textAnchor="middle"
            fill="var(--text-muted)"
            style={{ fontSize: unit * 0.022, fontWeight: 600, letterSpacing: '0.1em' }}
          >
            HƯỚNG SÂN KHẤU
          </text>
        </>
      )}

      {rows.map((r) => (
        <text
          key={r.label}
          x={r.x} y={r.y}
          textAnchor="middle" dominantBaseline="central"
          fill="var(--text-muted)"
          style={{ fontSize: 12, fontWeight: 600 }}
        >
          {r.label}
        </text>
      ))}

      {placed.map(({ seat, cx, cy, r, pts }) => {
        const isSel = selected.includes(seat.seatID);
        const selectable = canSelect && isSeatSelectable(seat);
        const c = seatColors(seat.inventoryStatus, isSel);
        return (
          <g
            key={seat.seatID}
            className="seatmap-seat"
            role="button"
            tabIndex={selectable || isSel ? 0 : -1}
            aria-pressed={isSel}
            /* Nhãn đầy đủ: người dùng trình đọc màn hình không thấy vị trí lẫn màu,
               nên địa chỉ chỗ ngồi, giá và trạng thái đều phải nằm trong chữ. */
            aria-label={
              `${zone.zoneName ?? zone.zoneCode}`
              + `${seat.rowLabel ? `, hàng ${seat.rowLabel}` : ''}`
              + `${seat.columnNumber ? `, ghế ${seat.columnNumber}` : ''}`
              + `, ${seat.categoryName}, ${formatMoney(seat.price)}, `
              + `${isSeatSelectable(seat) ? 'còn trống' : 'không chọn được'}`
            }
            style={{ cursor: selectable || isSel ? 'pointer' : 'not-allowed' }}
            onClick={() => (selectable || isSel) && onToggleSeat(seat)}
            onKeyDown={(e) => {
              if ((e.key === 'Enter' || e.key === ' ') && (selectable || isSel)) {
                e.preventDefault();
                onToggleSeat(seat);
              }
            }}
            onMouseEnter={() => onHover({ seat, zone })}
            onMouseLeave={() => onHover(null)}
            onFocus={() => onHover({ seat, zone })}
            onBlur={() => onHover(null)}
          >
            {pts ? (
              /* Chế độ toạ độ thật: vẽ ĐÚNG hình ghế đã lưu (rect xoay hoặc đa
                 giác của hàng cong) thay vì một hình tròn ở vị trí bịa. */
              <path
                d={pointsToSvgPath(pts)}
                fill={c.fill} stroke={c.stroke} strokeWidth={1.4}
                style={{ transition: 'fill 140ms var(--ease), stroke 140ms var(--ease)' }}
              />
            ) : (
              <circle
                cx={cx} cy={cy} r={isSel ? r * 1.16 : r}
                fill={c.fill} stroke={c.stroke} strokeWidth={1.4}
                style={{ transition: 'r 140ms var(--ease), fill 140ms var(--ease)' }}
              />
            )}
            {/* Số ghế chỉ hiện khi nó ĐỌC ĐƯỢC: ngưỡng tính theo khung nhìn nên ở
                chế độ toạ độ thật, khi chưa phóng to, chữ không còn là một mảng
                chấm li ti đè lên nhau. */}
            {seat.columnNumber != null && r >= unit * 0.02 && (
              <text
                x={cx} y={cy}
                textAnchor="middle" dominantBaseline="central"
                fill={c.text}
                style={{ fontSize: r * 0.9, fontWeight: 500, pointerEvents: 'none' }}
              >
                {seat.columnNumber}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}

/* ══════════════════════════════════════════════════════════════════════════ */

export default function SeatMap({ map, concertId, selected, onToggleSeat, canSelect }) {
  // useMemo theo map.floors (khong phai theo bien `floors` tu suy ra o day):
  // `?? []` sinh mot mang RONG MOI moi lan render neu map.floors la nullish,
  // khien moi useMemo/useCallback phia duoi tuong no la du lieu moi va tinh
  // lai vo ich — khoa dependency vao chinh prop on dinh thay vi bien dan xuat.
  const floors = useMemo(() => map.floors ?? [], [map.floors]);
  const [floorKey, setFloorKey] = useState(floors[0]?.floorKey);
  const floor = floors.find((f) => f.floorKey === floorKey) ?? floors[0];
  // Bậc giá tính trên TOÀN BỘ map (mọi tầng), không chỉ tầng đang xem — đổi
  // tầng không được làm cùng một khoảng giá đổi màu khác đi.
  const priceScale = useMemo(() => buildPriceScale(floors), [floors]);

  const [zone, setZone] = useState(null);       // khu đang xem chi tiết
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [hover, setHover] = useState(null);

  const openZone = useCallback(async (z) => {
    setLoading(true);
    setError('');
    setHover(null);
    try {
      const res = await api.get(`/concerts/${concertId}/seatmap/zones/${z.zoneID}`);
      setZone(res.data);
    } catch (err) {
      setError(apiError(err, 'Không tải được sơ đồ ghế của khu này.'));
    } finally {
      setLoading(false);
    }
  }, [concertId]);

  const backToOverview = () => { setZone(null); setError(''); setHover(null); };

  // Phím Escape quay lại tổng quan — người dùng bàn phím không phải đi tìm nút.
  useEffect(() => {
    if (!zone) return undefined;
    const onKey = (e) => { if (e.key === 'Escape') backToOverview(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [zone]);

  const selectedInZone = zone
    ? (zone.seats ?? []).filter((s) => selected.includes(s.seatID)).length
    : 0;

  if (!floor) return null;

  return (
    <div className="stack gap-4">
      {/* Chọn tầng — chỉ hiện khi địa điểm thực sự có nhiều tầng. */}
      {floors.length > 1 && !zone && (
        <div className="row gap-2 wrap" style={{ justifyContent: 'center' }}>
          {floors.map((f) => (
            <button
              key={f.floorKey}
              type="button"
              className={`btn btn--sm ${f.floorKey === floorKey ? 'btn--primary' : 'btn--secondary'}`}
              onClick={() => setFloorKey(f.floorKey)}
            >
              {floorLabel(f)}
            </button>
          ))}
        </div>
      )}

      {error && <Alert tone="danger">{error}</Alert>}

      {zone ? (
        /* ── MỨC 2 ──────────────────────────────────────────────────────── */
        <>
          <div className="row wrap gap-3" style={{ justifyContent: 'space-between' }}>
            <Button size="sm" onClick={backToOverview} icon={<IconChevronLeft size={15} />}>
              Toàn bộ tầng
            </Button>
            <div className="text-sm text-secondary">
              <strong style={{ color: 'var(--text)' }}>{zone.zoneName ?? zone.zoneCode}</strong>
              {selectedInZone > 0 && <> · đã chọn {selectedInZone}</>}
            </div>
          </div>

          {/* Chú giải đặt ở đây, không ở mức tổng quan: đây mới là nơi có ghế. */}
          <div className="legend">
            {SEAT_LEGEND.map((item) => {
              const c = item.status === SELECTED_PSEUDO_STATUS
                ? { fill: 'var(--accent)', stroke: 'var(--accent)' }
                : seatColors(item.status, false);
              return (
                <span className="legend__item" key={item.status}>
                  <span
                    className="legend__swatch"
                    style={{ background: c.fill, borderColor: c.stroke }}
                  />
                  {item.label}
                </span>
              );
            })}
          </div>

          <div className="seatmap-split">
            <div className="seatmap-frame">
              <ZoneSeats
                zone={zone}
                floor={floor}
                selected={selected}
                onToggleSeat={onToggleSeat}
                canSelect={canSelect}
                onHover={setHover}
              />
            </div>

            {/* Sơ đồ thu nhỏ: giữ phương hướng cho người dùng. Lưới chi tiết đã
                xoay thẳng để dễ bấm, nên nếu không có khối này thì khách mất
                thông tin "khu của tôi nằm ở đâu trong tầng". */}
            <aside className="seatmap-mini">
              <div className="overline" style={{ marginBottom: 'var(--space-2)' }}>Vị trí trong tầng</div>
              <FloorOverview floor={floor} activeZoneId={zone.zoneID} priceScale={priceScale} compact />
            </aside>
          </div>
        </>
      ) : (
        /* ── MỨC 1 ──────────────────────────────────────────────────────── */
        <>
          <div className="seatmap-frame">
            {loading
              ? <Skeleton h={340} r="var(--radius-lg)" />
              : <PannableFloorView floor={floor} onPickZone={openZone} priceScale={priceScale} />}
          </div>
          <p className="text-sm text-secondary" style={{ textAlign: 'center' }}>
            Bấm vào một khu để xem và chọn ghế bên trong — cuộn chuột để phóng to, kéo để lia.
          </p>
        </>
      )}

      {/* Dòng thông tin ghế đang trỏ tới. Đặt DƯỚI sơ đồ thay vì làm tooltip nổi:
          tooltip theo con trỏ không dùng được trên cảm ứng, và trên sơ đồ dày đặc
          thì nó che mất chính vùng người dùng đang xem. */}
      {zone && (
        <div className="seatmap-readout" aria-live="polite">
          {hover ? (
            <>
              <strong>{hover.zone.zoneName ?? hover.zone.zoneCode}</strong>
              {hover.seat.rowLabel && <> · Hàng {hover.seat.rowLabel}</>}
              {hover.seat.columnNumber && <> · Ghế {hover.seat.columnNumber}</>}
              <> · {hover.seat.categoryName}</>
              <> · <strong>{formatMoney(hover.seat.price)}</strong></>
            </>
          ) : (
            <span className="text-muted">Rê chuột hoặc dùng phím Tab qua từng ghế để xem chi tiết. Phím Esc để quay lại.</span>
          )}
        </div>
      )}
    </div>
  );
}
