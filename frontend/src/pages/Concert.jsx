import { useState, useEffect, useCallback, useMemo } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import api, { apiError } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import {
  QueueEntryStatus, WaitlistEntryStatus,
  CONCERT_STATUS_LABEL, QUEUE_STATUS_LABEL, WAITLIST_STATUS_LABEL,
  SEAT_LEGEND, SELECTED_PSEUDO_STATUS, canPurchase, isSeatSelectable, Role,
} from '../domain/enums';
import { CONCERT_TONE, QUEUE_TONE, WAITLIST_TONE, coverGradient, seatShortLabel } from '../domain/tone';
import { formatMoney, formatDateTime, formatCountdown, msUntil } from '../lib/format';
import {
  Badge, Button, Card, Alert, Skeleton, EmptyState, Panel,
} from '../components/ui';
import { useToast } from '../components/ui/Toast';
import { IconCalendar, IconPin, IconTicket, IconClock, IconArrowRight } from '../components/ui/icons';
import SeatMap from '../components/SeatMap';

/**
 * Trang sự kiện: thông tin, hàng đợi truy cập công bằng, danh sách chờ, và sơ đồ ghế.
 *
 * Trình tự trên trang đi theo đúng trình tự mà database bắt buộc: nếu sự kiện bật
 * Fair Access thì phải được cấp lượt TRƯỚC, chọn ghế sau. Đặt khối hàng đợi lên
 * trên sơ đồ ghế để người dùng thấy rào chắn trước khi đâm vào nó — chứ không
 * phải chọn xong ghế rồi mới nhận lỗi 51007.
 */
export default function Concert() {
  const { id } = useParams();
  const concertId = Number(id);
  const navigate = useNavigate();
  const toast = useToast();
  const { isAuthenticated, hasRole } = useAuth();

  const [concert, setConcert] = useState(null);
  const [seats, setSeats] = useState([]);
  const [selected, setSelected] = useState([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const [queueEntry, setQueueEntry] = useState(null);
  const [waitlistEntry, setWaitlistEntry] = useState(null);

  /**
   * So do hinh hoc cua dia diem.
   *
   * Tach khoi /seats vi day la hai tai lieu khac ban chat: /seats la danh sach
   * phang (dung cho gio hang, tinh tien), con /seatmap la tai liec hinh hoc long
   * nhau (dia diem -> khu -> ghe) va con chua ca khu ve dung — loai khu KHONG co
   * ghe nao nen khong the xuat hien trong mot danh sach ghe.
   *
   * null = dia diem chua khai bao toa do. Khi do giao dien rot ve che do liet ke
   * theo khu, van dat ve duoc binh thuong.
   */
  const [seatMap, setSeatMap] = useState(null);

  const isCustomer = isAuthenticated && hasRole(Role.Customer);

  const loadSeats = useCallback(async () => {
    // Hai loi goi chay song song: chung doc cung mot nguon va khong phu thuoc
    // nhau, nen goi tuan tu chi lam trang lau hien hon ma khong duoc gi.
    const [flat, geo] = await Promise.all([
      api.get(`/concerts/${concertId}/seats`),
      api.get(`/concerts/${concertId}/seatmap`).catch(() => null),
    ]);
    setSeats(Array.isArray(flat.data) ? flat.data : []);
    // Chi dung so do hinh hoc khi dia diem THUC SU da khai bao mat phang.
    // Thieu kiem tra nay se ve ra mot khung rong khong co gi ben trong.
    const m = geo?.data;
    setSeatMap(m?.mapWidth && m?.mapHeight ? m : null);
  }, [concertId]);

  /**
   * GET .../me trả HTTP 404 khi khách chưa có entry đang hoạt động — đó là câu trả lời
   * HỢP LỆ ("bạn không ở trong hàng đợi"), không phải lỗi. Phải quy về null một cách
   * tường minh: nếu chỉ nuốt exception, giá trị cũ sẽ được giữ nguyên và giao diện vẫn
   * hiển thị "đang xếp hàng" sau khi người dùng đã rời hàng đợi.
   */
  const loadQueue = useCallback(async () => {
    try {
      const res = await api.get(`/queue/concerts/${concertId}/me`);
      setQueueEntry(res.data ?? null);
    } catch (err) {
      if (err?.response?.status === 404) setQueueEntry(null);
      else throw err;
    }
  }, [concertId]);

  const loadWaitlist = useCallback(async () => {
    try {
      const res = await api.get(`/waitlist/concerts/${concertId}/me`);
      setWaitlistEntry(res.data ?? null);
    } catch (err) {
      if (err?.response?.status === 404) setWaitlistEntry(null);
      else throw err;
    }
  }, [concertId]);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    (async () => {
      try {
        const detail = await api.get(`/concerts/${concertId}`);
        if (!alive) return;
        setConcert(detail.data);
        await loadSeats();
      } catch (err) {
        if (alive) setError(apiError(err, 'Không tải được thông tin sự kiện.'));
      } finally {
        if (alive) setLoading(false);
      }
    })();
    return () => { alive = false; };
  }, [concertId, loadSeats]);

  // Chỉ hỏi trạng thái hàng đợi / danh sách chờ khi concert thực sự bật tính năng đó
  // và người dùng là Customer — hai endpoint này đều [Authorize(Roles = "Customer")].
  useEffect(() => {
    if (!concert || !isCustomer) return;
    if (concert.fairAccessEnabled) loadQueue().catch(() => {});
    if (concert.waitlistEnabled) loadWaitlist().catch(() => {});
  }, [concert, isCustomer, loadQueue, loadWaitlist]);

  // Đang xếp hàng thì hỏi lại định kỳ: tiến trình nền SIP3 chạy mỗi 15 giây, nên
  // 10 giây là đủ nhanh để thấy tới lượt mà không dội request.
  useEffect(() => {
    if (queueEntry?.queueStatus !== QueueEntryStatus.Waiting) return undefined;
    const t = setInterval(() => loadQueue().catch(() => {}), 10_000);
    return () => clearInterval(t);
  }, [queueEntry?.queueStatus, loadQueue]);

  // Đồng hồ đếm ngược lượt được vào mua (booking_ttl, BR47b).
  const [admissionLeft, setAdmissionLeft] = useState(0);
  useEffect(() => {
    if (queueEntry?.queueStatus !== QueueEntryStatus.Admitted) return undefined;
    const tick = () => setAdmissionLeft(msUntil(queueEntry.admissionExpiryTimestamp));
    tick();
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
  }, [queueEntry]);

  const purchasable = canPurchase(concert);
  const purchaseLimit = concert?.purchaseLimit ?? 0;
  const needsAdmission = !!concert?.fairAccessEnabled;
  const admitted =
    queueEntry?.queueStatus === QueueEntryStatus.Admitted &&
    msUntil(queueEntry.admissionExpiryTimestamp) > 0;
  const canSelectSeats = purchasable && (!needsAdmission || admitted);

  const totalAmount = useMemo(
    () => seats.filter((s) => selected.includes(s.seatID)).reduce((sum, s) => sum + Number(s.price), 0),
    [seats, selected],
  );

  const availableCount = seats.filter(isSeatSelectable).length;
  const soldOut = seats.length > 0 && availableCount === 0;
  const categories = useMemo(
    () => [...new Map(seats.map((s) => [s.ticketCategoryID, s])).values()],
    [seats],
  );

  /**
   * Gom ghe theo KHU (Zone).
   *
   * Du lieu tra ve la mot mang phang, va bay ca mang do ra thanh mot luoi lien
   * tuc thi nguoi mua khong doc duoc gi: khong biet ghe nao thuoc khu nao, gia
   * bao nhieu, cho ngoi o dau. Moi so do ve that deu chia theo khu.
   *
   * Giu nguyen thu tu xuat hien dau tien cua tung khu — may chu da ORDER BY
   * ZoneName, SeatCode, nen thu tu do la co chu dich, khong nen sap lai.
   */
  const zones = useMemo(() => {
    const map = new Map();
    seats.forEach((s) => {
      const key = s.sectionName ?? 'Khac';
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(s);
    });
    return [...map.entries()].map(([name, list]) => ({
      name,
      seats: list,
      available: list.filter(isSeatSelectable).length,
      // Gia trong mot khu co the khac nhau neu khu duoc chia nhieu hang ve.
      minPrice: Math.min(...list.map((x) => Number(x.price))),
      maxPrice: Math.max(...list.map((x) => Number(x.price))),
    }));
  }, [seats]);

  const toggleSeat = (seat) => {
    setError('');
    if (!canSelectSeats || !isSeatSelectable(seat)) return;
    if (selected.includes(seat.seatID)) {
      setSelected(selected.filter((x) => x !== seat.seatID));
      return;
    }
    // Giới hạn lấy từ chính Concert.PurchaseLimit (BR20) chứ không phải hằng số —
    // mỗi sự kiện cấu hình khác nhau, và sp_CreateBooking sẽ từ chối bằng 51003.
    if (purchaseLimit > 0 && selected.length >= purchaseLimit) {
      toast(`Mỗi khách chỉ được mua tối đa ${purchaseLimit} vé cho sự kiện này.`, { type: 'warning' });
      return;
    }
    setSelected([...selected, seat.seatID]);
  };

  const handleHold = async () => {
    if (!selected.length) return;
    if (!isAuthenticated) {
      navigate('/login', { state: { from: { pathname: `/concert/${concertId}` } } });
      return;
    }
    setBusy(true);
    setError('');
    try {
      const res = await api.post('/bookings', { concertId, seatIds: selected });
      navigate(`/checkout/${res.data.bookingId}`, { state: { booking: res.data } });
    } catch (err) {
      setError(apiError(err, 'Không giữ được ghế. Có thể ghế vừa được người khác đặt.'));
      setSelected([]);
      // Nạp lại sơ đồ để phản ánh trạng thái mới nhất.
      try { await loadSeats(); } catch { /* giữ nguyên sơ đồ cũ */ }
      if (needsAdmission) { try { await loadQueue(); } catch { /* bỏ qua */ } }
    } finally {
      setBusy(false);
    }
  };

  const runQueueAction = async (fn, okMessage) => {
    setBusy(true); setError('');
    try {
      await fn();
      await loadQueue();
      if (okMessage) toast(okMessage, { type: 'success' });
    } catch (err) {
      setError(apiError(err, 'Không thực hiện được thao tác hàng đợi.'));
    } finally { setBusy(false); }
  };

  if (loading) return <ConcertSkeleton />;

  if (!concert) {
    return (
      <div className="container">
        <Card>
          <EmptyState title="Không tìm thấy sự kiện">
            {error || 'Sự kiện không tồn tại hoặc chưa được công bố.'}
          </EmptyState>
        </Card>
      </div>
    );
  }

  return (
    <div className="container" style={{ paddingBottom: selected.length ? 'var(--space-24)' : 0 }}>
      {/* ── Đầu trang ────────────────────────────────────────────────────── */}
      <Card style={{ overflow: 'hidden', marginBottom: 'var(--space-6)' }}>
        <div className="event-cover" style={{ background: coverGradient(concert.concertID), height: 132 }}>
          <span className="event-cover__glyph" style={{ fontSize: 'var(--text-4xl)' }}>
            {(concert.artistName ?? concert.concertName ?? '?').charAt(0).toUpperCase()}
          </span>
        </div>

        <div className="card__body stack gap-4">
          <div className="row wrap gap-2">
            <Badge tone={CONCERT_TONE[concert.concertStatus] ?? 'neutral'} size="lg">
              {CONCERT_STATUS_LABEL[concert.concertStatus] ?? concert.concertStatus}
            </Badge>
            {concert.salesPaused && <Badge tone="amber" size="lg">Tạm dừng bán</Badge>}
          </div>

          <div>
            <h1 style={{ fontSize: 'clamp(1.5rem, 4vw, var(--text-4xl))' }}>{concert.concertName}</h1>
            <p className="text-secondary" style={{ marginTop: 'var(--space-1)', fontSize: 'var(--text-md)' }}>
              {concert.artistName}
            </p>
          </div>

          <div className="row wrap gap-6 text-sm text-secondary">
            <span className="row gap-2"><IconCalendar size={15} /> {formatDateTime(concert.startDatetime)}</span>
            <span className="row gap-2"><IconPin size={15} /> {concert.venueName}{concert.address ? ` · ${concert.address}` : ''}</span>
            <span className="row gap-2"><IconTicket size={15} /> Tối đa {concert.purchaseLimit ?? '—'} vé / khách</span>
          </div>

          {!purchasable && (
            <Alert tone="warning">
              {concert.salesPaused
                ? 'Sự kiện đang tạm dừng bán vé. Vui lòng quay lại sau.'
                : `Sự kiện đang ở trạng thái “${CONCERT_STATUS_LABEL[concert.concertStatus] ?? concert.concertStatus}”. Hiện không thể đặt vé.`}
            </Alert>
          )}
        </div>
      </Card>

      {error && <div style={{ marginBottom: 'var(--space-5)' }}><Alert tone="danger">{error}</Alert></div>}

      {/* ── Hàng đợi truy cập công bằng ──────────────────────────────────── */}
      {purchasable && needsAdmission && (
        <Panel
          title="Hàng đợi truy cập công bằng"
          subtitle="Sự kiện này giới hạn số người vào chọn ghế cùng lúc. Bạn cần vào hàng đợi và chờ tới lượt trước khi đặt vé."
          aside={queueEntry && (
            <Badge tone={QUEUE_TONE[queueEntry.queueStatus] ?? 'neutral'} size="lg">
              {QUEUE_STATUS_LABEL[queueEntry.queueStatus] ?? queueEntry.queueStatus}
            </Badge>
          )}
        >
          {!isCustomer ? (
            <Button
              variant="primary"
              onClick={() => navigate('/login', { state: { from: { pathname: `/concert/${concertId}` } } })}
            >
              Đăng nhập để vào hàng đợi
            </Button>
          ) : !queueEntry ? (
            <Button
              variant="primary" loading={busy}
              onClick={() => runQueueAction(
                () => api.post(`/queue/concerts/${concertId}/join`),
                'Bạn đã vào hàng đợi. Trang sẽ tự cập nhật khi tới lượt.',
              )}
            >
              Vào hàng đợi
            </Button>
          ) : queueEntry.queueStatus === QueueEntryStatus.Waiting ? (
            <div className="row wrap gap-4" style={{ justifyContent: 'space-between' }}>
              <div>
                <div className="overline">Vị trí của bạn</div>
                <div style={{ fontSize: 'var(--text-2xl)', fontWeight: 'var(--weight-semibold)' }}>
                  {queueEntry.admissionPosition != null ? `#${queueEntry.admissionPosition}` : 'Đang xếp hàng'}
                </div>
                <div className="text-xs text-muted" style={{ marginTop: 'var(--space-1)' }}>
                  Trang tự kiểm tra lại mỗi 10 giây
                </div>
              </div>
              <Button
                loading={busy}
                onClick={() => runQueueAction(
                  () => api.post(`/queue/entries/${queueEntry.queueEntryId}/exit`),
                  'Đã rời hàng đợi.',
                )}
              >
                Rời hàng đợi
              </Button>
            </div>
          ) : admitted ? (
            <div className="row wrap gap-4" style={{ justifyContent: 'space-between' }}>
              <div className="stack gap-1">
                <span style={{ color: 'var(--green-text)', fontWeight: 'var(--weight-semibold)' }}>
                  Đã tới lượt bạn — mời chọn ghế bên dưới.
                </span>
                <span className="text-xs text-muted">
                  Hết thời gian thì lượt sẽ được nhường cho người kế tiếp.
                </span>
              </div>
              <span
                className="countdown"
                data-urgent={admissionLeft > 0 && admissionLeft < 120_000 ? 'true' : undefined}
                data-expired={admissionLeft <= 0 ? 'true' : undefined}
              >
                <IconClock size={14} />
                {formatCountdown(admissionLeft)}
              </span>
            </div>
          ) : (
            <div className="row wrap gap-4" style={{ justifyContent: 'space-between' }}>
              <span className="text-sm text-secondary">
                Lượt trước của bạn đã kết thúc. Bạn có thể xếp hàng lại.
              </span>
              <Button
                variant="primary" loading={busy}
                onClick={() => runQueueAction(
                  () => api.post(`/queue/concerts/${concertId}/join`),
                  'Bạn đã vào lại hàng đợi.',
                )}
              >
                Vào lại hàng đợi
              </Button>
            </div>
          )}
        </Panel>
      )}

      {/* ── Danh sách chờ ────────────────────────────────────────────────── */}
      {purchasable && concert.waitlistEnabled && isCustomer && soldOut && (
        <Panel
          title="Danh sách chờ"
          subtitle="Hết ghế trống. Đăng ký chờ theo hạng vé — bạn được ưu tiên khi có ghế được trả lại."
          aside={waitlistEntry && (
            <Badge tone={WAITLIST_TONE[waitlistEntry.entryStatus] ?? 'neutral'} size="lg">
              {WAITLIST_STATUS_LABEL[waitlistEntry.entryStatus] ?? waitlistEntry.entryStatus}
            </Badge>
          )}
        >
          {waitlistEntry ? (
            <div className="stack gap-2 text-sm">
              {waitlistEntry.entryStatus === WaitlistEntryStatus.Active && (
                <span className="text-secondary">
                  Bạn đang ở vị trí <strong style={{ color: 'var(--text)' }}>#{waitlistEntry.queuePosition}</strong> trong danh sách chờ.
                </span>
              )}
              {waitlistEntry.entryStatus === WaitlistEntryStatus.Granted && waitlistEntry.opportunityExpiryTimestamp && (
                <Alert tone="success">
                  Bạn đã được cấp cơ hội mua. Hoàn tất trước{' '}
                  <strong>{formatDateTime(waitlistEntry.opportunityExpiryTimestamp)}</strong>.
                </Alert>
              )}
            </div>
          ) : (
            <div className="row wrap gap-2">
              {categories.map((c) => (
                <Button
                  key={c.ticketCategoryID}
                  loading={busy}
                  onClick={async () => {
                    setBusy(true);
                    try {
                      await api.post(`/waitlist/concerts/${concertId}/join`, {
                        ticketCategoryId: c.ticketCategoryID,
                        requestedQuantity: 1,
                      });
                      await loadWaitlist();
                      toast('Đã đăng ký danh sách chờ.', { type: 'success' });
                    } catch (err) {
                      setError(apiError(err, 'Không đăng ký được danh sách chờ.'));
                    } finally { setBusy(false); }
                  }}
                >
                  Chờ hạng {c.categoryName}
                </Button>
              ))}
            </div>
          )}
        </Panel>
      )}

      {/* ── Sơ đồ ghế ────────────────────────────────────────────────────── */}
      <section aria-labelledby="seatmap-title" style={{ marginTop: 'var(--space-10)' }}>
        <div className="stack gap-2" style={{ alignItems: 'center', marginBottom: 'var(--space-8)' }}>
          <h2 id="seatmap-title">Chọn ghế</h2>
          <p className="text-sm text-secondary">
            {seats.length === 0
              ? 'Sự kiện chưa mở sơ đồ ghế.'
              : `${availableCount} / ${seats.length} ghế còn trống`}
          </p>
        </div>

        {seats.length > 0 && (
          <>
            {!seatMap && <div className="stage"><span>Sân khấu</span></div>}

            {/* Chú giải màu GHẾ chỉ có nghĩa ở nơi thực sự vẽ ghế. Ở sơ đồ hai
                mức, mức tổng quan không có ghế nào — chú giải ở đó là nhiễu, nên
                nó được đặt vào đúng mức chi tiết bên trong SeatMap. */}
            {!seatMap && (
            <div className="legend">
              {SEAT_LEGEND.map((item) => (
                <span className="legend__item" key={item.status}>
                  <span
                    className="legend__swatch"
                    data-status={item.status}
                    style={item.status === SELECTED_PSEUDO_STATUS
                      ? { background: 'var(--accent)', borderColor: 'var(--accent)' }
                      : undefined}
                  />
                  {item.label}
                </span>
              ))}
            </div>
            )}

            {needsAdmission && !admitted && (
              <div style={{ maxWidth: 620, margin: '0 auto var(--space-6)' }}>
                <Alert tone="info">
                  Sơ đồ chỉ để tham khảo cho tới khi bạn được cấp lượt từ hàng đợi.
                </Alert>
              </div>
            )}

            {/* Địa điểm đã khai báo toạ độ thì vẽ sơ đồ thật — khách thấy được
                chỗ ngồi nằm ở đâu so với sân khấu. Chưa khai báo thì rơi về danh
                sách theo khu bên dưới: vẫn đặt vé được, chỉ là không định vị được.
                Vẽ một sơ đồ từ vị trí bịa ra còn tệ hơn không vẽ. */}
            {seatMap ? (
              <SeatMap
                map={seatMap}
                concertId={concertId}
                selected={selected}
                canSelect={canSelectSeats}
                onToggleSeat={toggleSeat}
              />
            ) : (
            <div className="zones">
              {zones.map((zone) => (
                <section
                  className="zone"
                  key={zone.name}
                  role="group"
                  aria-label={`Khu ${zone.name}, còn ${zone.available} trên ${zone.seats.length} ghế`}
                >
                  <header className="zone__head">
                    <div className="row gap-2 wrap">
                      <span className="zone__name">{zone.name}</span>
                      <span className="text-xs text-muted">
                        {zone.available}/{zone.seats.length} còn trống
                      </span>
                    </div>
                    <span className="zone__price tabular">
                      {zone.minPrice === zone.maxPrice
                        ? formatMoney(zone.minPrice)
                        : `${formatMoney(zone.minPrice)} – ${formatMoney(zone.maxPrice)}`}
                    </span>
                  </header>

                  <div className="seatmap">
                    {zone.seats.map((seat) => {
                      const isSelected = selected.includes(seat.seatID);
                      const selectable = canSelectSeats && isSeatSelectable(seat);
                      return (
                        <button
                          key={seat.seatID}
                          type="button"
                          className="seat"
                          data-status={seat.inventoryStatus}
                          data-selected={isSelected || undefined}
                          data-selectable={selectable || undefined}
                          disabled={!selectable && !isSelected}
                          aria-pressed={isSelected}
                          /* Nhãn đầy đủ dùng MÃ GHẾ THẬT, không phải nhãn rút gọn
                             hiển thị trong ô: người dùng trình đọc màn hình không
                             thấy được màu lẫn vị trí, nên mã đầy đủ, hạng vé, giá
                             và trạng thái đều phải nằm trong chữ. */
                          aria-label={
                            `Ghế ${seat.seatNumber}, khu ${seat.sectionName ?? '—'}, `
                            + `hạng ${seat.categoryName}, ${formatMoney(seat.price)}, `
                            + `${isSeatSelectable(seat) ? 'còn trống' : 'không chọn được'}`
                          }
                          title={`${seat.seatNumber} · ${seat.categoryName} · ${formatMoney(seat.price)}`}
                          onClick={() => toggleSeat(seat)}
                        >
                          {seatShortLabel(seat.seatNumber)}
                        </button>
                      );
                    })}
                  </div>
                </section>
              ))}
            </div>
            )}
          </>
        )}

        {seats.length === 0 && (
          <Card><EmptyState title="Chưa có sơ đồ ghế">
            Ban tổ chức chưa đưa ghế vào kho vé cho sự kiện này.
          </EmptyState></Card>
        )}
      </section>

      {/* ── Thanh tóm tắt cố định ────────────────────────────────────────── */}
      {selected.length > 0 && (
        <div className="actionbar" role="region" aria-label="Tóm tắt lựa chọn">
          <div>
            <div className="overline">{selected.length} ghế đã chọn</div>
            <div style={{ fontSize: 'var(--text-xl)', fontWeight: 'var(--weight-bold)' }}>
              {formatMoney(totalAmount)}
            </div>
          </div>
          <Button
            variant="primary" size="lg" loading={busy}
            onClick={handleHold}
            iconEnd={<IconArrowRight size={16} />}
            style={{ borderRadius: 'var(--radius-full)' }}
          >
            Giữ chỗ
          </Button>
        </div>
      )}

      {!isAuthenticated && purchasable && seats.length > 0 && (
        <p className="text-sm text-secondary" style={{ textAlign: 'center', marginTop: 'var(--space-8)' }}>
          <Link to="/login" style={{ textDecoration: 'underline' }}>Đăng nhập</Link> để giữ chỗ và thanh toán.
        </p>
      )}
    </div>
  );
}

function ConcertSkeleton() {
  return (
    <div className="container">
      <Card style={{ overflow: 'hidden', marginBottom: 'var(--space-6)' }}>
        <Skeleton h={132} r="var(--radius-xl) var(--radius-xl) 0 0" />
        <div className="card__body stack gap-4">
          <Skeleton w={110} h={26} />
          <Skeleton w="60%" h={34} />
          <Skeleton w="40%" h={16} />
          <div className="row gap-6"><Skeleton w={160} h={14} /><Skeleton w={200} h={14} /></div>
        </div>
      </Card>
      <div className="stack gap-4" style={{ alignItems: 'center' }}>
        <Skeleton w={140} h={26} />
        <Skeleton w="min(620px, 100%)" h={220} r="var(--radius-lg)" />
      </div>
    </div>
  );
}
