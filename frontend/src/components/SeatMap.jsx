import { useMemo, useState, useCallback, useEffect } from 'react';
import api, { apiError } from '../api/client';
import { formatMoney } from '../lib/format';
import { InventoryStatus, isSeatSelectable, SEAT_LEGEND, SELECTED_PSEUDO_STATUS } from '../domain/enums';
import { Button, Alert, Skeleton } from './ui';
import { IconChevronLeft } from './ui/icons';

/**
 * SƠ ĐỒ CHỖ NGỒI — HAI MỨC
 *
 * Mức 1 (tổng quan): toàn khán phòng. Mỗi khu là một hình có vị trí thật so với
 *   sân khấu, kèm số chỗ còn trống và khoảng giá. KHÔNG vẽ ghế.
 * Mức 2 (chi tiết):  bấm vào một khu → tải ghế của riêng khu đó và vẽ thành lưới
 *   lớn, kèm sơ đồ thu nhỏ đánh dấu khu đang xem đứng ở đâu.
 *
 * VÌ SAO PHẢI CHIA HAI MỨC — không phải để đẹp, mà vì phép đo:
 * hệ thống này tốn 234 byte mỗi ghế. Trả hết ghế của một arena 20.000 chỗ là
 * 4,5 MB mỗi lần mở trang; sân vận động 60.000 chỗ là 13 MB. Chia hai mức giữ
 * bước đầu ở vài KB dù địa điểm lớn cỡ nào.
 *
 * Nó cũng khớp hành vi mua thật: người ta chọn KHU trước (theo giá và khoảng
 * cách tới sân khấu), rồi mới chọn ghế trong khu đó.
 *
 * TOẠ ĐỘ: SVG dùng `viewBox` đặt đúng bằng hệ toạ độ của địa điểm trong database,
 * nên số liệu được dùng thẳng làm toạ độ vẽ — không có bước quy đổi nào để sai —
 * và tự co giãn từ 390px tới 1400px mà không cần media query.
 */

/* Chừa lề trong khu ở lưới chi tiết. */
const PAD_X = 16;
const PAD_TOP = 30;
const PAD_BOTTOM = 14;

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

/** Mức khu: khu càng còn nhiều chỗ càng đậm — quét mắt là thấy chỗ nào còn vé. */
function zoneColors(zone) {
  if (zone.availableCount === 0) {
    return { fill: 'var(--surface-sunken)', stroke: 'var(--border-subtle)', text: 'var(--text-muted)' };
  }
  return { fill: 'var(--surface-raised)', stroke: 'var(--border-strong)', text: 'var(--text)' };
}

/* ══════════════════════════════════════════════════════════════════════════
   MỨC 1 — TOÀN KHÁN PHÒNG
   `compact` dùng cho sơ đồ thu nhỏ ở mức chi tiết: bỏ chữ, bỏ tương tác.
   ══════════════════════════════════════════════════════════════════════════ */
function VenueOverview({ map, zones, onPickZone, activeZoneId, compact }) {
  return (
    <svg
      viewBox={`0 0 ${map.mapWidth} ${map.mapHeight}`}
      preserveAspectRatio="xMidYMid meet"
      role={compact ? 'img' : 'group'}
      aria-label={compact
        ? 'Vị trí khu đang xem trong khán phòng'
        : `Sơ đồ khán phòng ${map.venueName} — chọn một khu`}
      style={{ width: '100%', height: 'auto', display: 'block' }}
    >
      {map.stageX != null && (
        <g>
          <rect
            x={map.stageX} y={map.stageY}
            width={map.stageWidth} height={map.stageHeight}
            rx={Math.min(10, map.stageHeight / 3)}
            fill="var(--surface-inverse)"
          />
          {!compact && (
            <text
              x={map.stageX + map.stageWidth / 2}
              y={map.stageY + map.stageHeight / 2}
              textAnchor="middle" dominantBaseline="central"
              fill="var(--text-inverse)"
              style={{ fontSize: 20, fontWeight: 600, letterSpacing: '0.14em' }}
            >
              SÂN KHẤU
            </text>
          )}
        </g>
      )}

      {zones.map((zone) => {
        if (zone.zoneX == null) return null;
        const cx = zone.zoneX + zone.zoneWidth / 2;
        const cy = zone.zoneY + zone.zoneHeight / 2;
        const rot = Number(zone.zoneRotation ?? 0);
        const c = zoneColors(zone);
        const isActive = zone.zoneID === activeZoneId;
        const clickable = !compact && zone.seatCount > 0;

        const priceLabel = zone.minPrice == null ? null
          : zone.minPrice === zone.maxPrice
            ? formatMoney(zone.minPrice)
            : `${formatMoney(zone.minPrice)} – ${formatMoney(zone.maxPrice)}`;

        return (
          <g
            key={zone.zoneID}
            transform={rot ? `rotate(${rot} ${cx} ${cy})` : undefined}
            role={clickable ? 'button' : undefined}
            tabIndex={clickable ? 0 : undefined}
            aria-label={clickable
              ? `${zone.zoneName ?? zone.zoneCode}, còn ${zone.availableCount} trên ${zone.seatCount} chỗ`
                + `${priceLabel ? `, ${priceLabel}` : ''}. Bấm để chọn ghế.`
              : undefined}
            style={{ cursor: clickable ? 'pointer' : 'default' }}
            onClick={() => clickable && onPickZone(zone)}
            onKeyDown={(e) => {
              if (clickable && (e.key === 'Enter' || e.key === ' ')) {
                e.preventDefault();
                onPickZone(zone);
              }
            }}
          >
            <rect
              x={zone.zoneX} y={zone.zoneY}
              width={zone.zoneWidth} height={zone.zoneHeight}
              rx={12}
              fill={c.fill}
              stroke={isActive ? 'var(--accent)' : c.stroke}
              strokeWidth={isActive ? 3 : 1.5}
              style={{ transition: 'stroke 160ms var(--ease)' }}
            />

            {!compact && (
              <>
                <text
                  x={cx} y={zone.zoneY + zone.zoneHeight / 2 - (priceLabel ? 12 : 0)}
                  textAnchor="middle" dominantBaseline="central"
                  fill={c.text}
                  style={{ fontSize: 16, fontWeight: 600 }}
                >
                  {zone.zoneName ?? zone.zoneCode}
                </text>

                <text
                  x={cx} y={zone.zoneY + zone.zoneHeight / 2 + 10}
                  textAnchor="middle" dominantBaseline="central"
                  fill={c.text}
                  style={{ fontSize: 12, opacity: 0.78 }}
                >
                  {zone.availableCount === 0
                    ? 'Hết chỗ'
                    : `${zone.availableCount}/${zone.seatCount} chỗ · ${priceLabel ?? ''}`}
                </text>
              </>
            )}
          </g>
        );
      })}
    </svg>
  );
}

/* ══════════════════════════════════════════════════════════════════════════
   MỨC 2 — GHẾ TRONG MỘT KHU
   Vẽ lưới trong hệ toạ độ RIÊNG của khu, không phải hệ của khán phòng: ở đây
   mục tiêu là bấm trúng ghế, nên ghế cần to và thẳng hàng. Khu nghiêng 10° thì
   vị trí thật đã được thể hiện ở sơ đồ thu nhỏ bên cạnh.
   ══════════════════════════════════════════════════════════════════════════ */
function ZoneSeats({ zone, selected, onToggleSeat, canSelect, onHover }) {
  const { rows, placed, W, H } = useMemo(() => {
    const seats = zone.seats ?? [];
    if (!seats.length) return { rows: [], placed: [], W: 100, H: 100 };

    const rowLabels = [...new Set(seats.map((s) => s.rowLabel ?? '·'))]
      .sort((a, b) => String(a).localeCompare(String(b), 'vi', { numeric: true }));
    const maxCol = Math.max(...seats.map((s) => s.columnNumber ?? 1), 1);

    // Ô lưới cố định 44 đơn vị — ghế luôn đủ lớn để chạm bằng ngón tay, và khung
    // tự dài ra theo số hàng thay vì bóp ghế lại cho vừa một chiều cao cố định.
    const CELL = 44;
    const w = PAD_X * 2 + maxCol * CELL;
    const h = PAD_TOP + PAD_BOTTOM + rowLabels.length * CELL;
    const r = CELL * 0.36;

    return {
      W: w,
      H: h,
      rows: rowLabels.map((label, ri) => ({
        label,
        x: PAD_X * 0.55,
        y: PAD_TOP + (ri + 0.5) * CELL,
      })),
      placed: seats.map((s) => ({
        seat: s,
        cx: PAD_X + ((s.columnNumber ?? 1) - 0.5) * CELL,
        cy: PAD_TOP + (rowLabels.indexOf(s.rowLabel ?? '·') + 0.5) * CELL,
        r,
      })),
    };
  }, [zone]);

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMid meet"
      role="group"
      aria-label={`Ghế trong ${zone.zoneName ?? zone.zoneCode}`}
      style={{ width: '100%', height: 'auto', display: 'block' }}
    >
      {/* Hướng sân khấu — trong lưới đã xoay thẳng thì đây là thứ giữ lại phương hướng. */}
      <text
        x={W / 2} y={14}
        textAnchor="middle"
        fill="var(--text-muted)"
        style={{ fontSize: 11, fontWeight: 600, letterSpacing: '0.12em' }}
      >
        ↑ HƯỚNG SÂN KHẤU
      </text>

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

      {placed.map(({ seat, cx, cy, r }) => {
        const isSel = selected.includes(seat.seatID);
        const selectable = canSelect && isSeatSelectable(seat);
        const c = seatColors(seat.inventoryStatus, isSel);
        return (
          <g
            key={seat.seatID}
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
            <circle
              cx={cx} cy={cy} r={isSel ? r * 1.16 : r}
              fill={c.fill} stroke={c.stroke} strokeWidth={1.4}
              style={{ transition: 'r 140ms var(--ease), fill 140ms var(--ease)' }}
            />
            {seat.columnNumber != null && (
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
  const levels = useMemo(() => {
    const set = [...new Set((map.zones ?? []).map((z) => z.zoneLevel ?? 1))];
    return set.sort((a, b) => a - b);
  }, [map.zones]);

  const [level, setLevel] = useState(levels[0] ?? 1);
  const [zone, setZone] = useState(null);       // khu đang xem chi tiết
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [hover, setHover] = useState(null);

  const zonesOnLevel = (map.zones ?? []).filter((z) => (z.zoneLevel ?? 1) === level);

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

  return (
    <div className="stack gap-4">
      {/* Chọn tầng — chỉ hiện khi địa điểm thực sự có nhiều tầng. */}
      {levels.length > 1 && !zone && (
        <div className="row gap-2 wrap" style={{ justifyContent: 'center' }}>
          {levels.map((lv) => (
            <button
              key={lv}
              type="button"
              className={`btn btn--sm ${lv === level ? 'btn--primary' : 'btn--secondary'}`}
              onClick={() => setLevel(lv)}
            >
              {lv === 1 ? 'Tầng trệt' : `Tầng ${lv}`}
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
              Toàn khán phòng
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
                selected={selected}
                onToggleSeat={onToggleSeat}
                canSelect={canSelect}
                onHover={setHover}
              />
            </div>

            {/* Sơ đồ thu nhỏ: giữ phương hướng cho người dùng. Lưới chi tiết đã
                xoay thẳng để dễ bấm, nên nếu không có khối này thì khách mất
                thông tin "khu của tôi nằm ở đâu trong khán phòng". */}
            <aside className="seatmap-mini">
              <div className="overline" style={{ marginBottom: 'var(--space-2)' }}>Vị trí trong khán phòng</div>
              <VenueOverview map={map} zones={zonesOnLevel} activeZoneId={zone.zoneID} compact />
            </aside>
          </div>
        </>
      ) : (
        /* ── MỨC 1 ──────────────────────────────────────────────────────── */
        <>
          <div className="seatmap-frame">
            {loading
              ? <Skeleton h={340} r="var(--radius-lg)" />
              : <VenueOverview map={map} zones={zonesOnLevel} onPickZone={openZone} />}
          </div>
          <p className="text-sm text-secondary" style={{ textAlign: 'center' }}>
            Bấm vào một khu để xem và chọn ghế bên trong.
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
