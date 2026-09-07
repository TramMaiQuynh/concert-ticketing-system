import { useState, useEffect, useCallback, useRef } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import api, { apiError } from '../api/client';
import { BookingStatus, BOOKING_STATUS_LABEL } from '../domain/enums';
import { BOOKING_TONE } from '../domain/tone';
import { formatMoney, formatCountdown, msUntil } from '../lib/format';
import {
  Badge, Button, Card, Alert, Input, Skeleton, EmptyState, ConfirmDialog,
} from '../components/ui';
import { useToast } from '../components/ui/Toast';
import { IconClock, IconArrowRight, IconChevronLeft, IconCheck } from '../components/ui/icons';

/**
 * Trang thanh toán.
 *
 * ĐIỂM QUAN TRỌNG NHẤT — vì sao trang này KHÔNG tự gọi /payments/confirm:
 *
 * Bản trước đọc `initRes.data.paymentSignature` rồi tự gọi
 * `/payments/confirm?...&signature=...`. Trường đó KHÔNG còn tồn tại trong
 * InitiatePaymentResponse, và việc nó bị gỡ là có chủ đích: chữ ký là bí mật dùng
 * chung giữa backend và cổng thanh toán. Nếu trả về cho trình duyệt thì bất kỳ khách
 * nào cũng tự xác nhận được đơn hàng của mình và nhận vé mà không trả tiền.
 *
 * Luồng đúng: client chỉ khởi tạo giao dịch rồi chuyển người dùng sang cổng thanh
 * toán. Cổng gọi webhook `/payments/confirm` theo kênh server-to-server (kèm chữ ký
 * hợp lệ). Trang này chỉ theo dõi trạng thái Booking cho tới khi đơn được xác nhận.
 */
export default function Checkout() {
  const { bookingId } = useParams();
  const navigate = useNavigate();
  const toast = useToast();

  const [booking, setBooking] = useState(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [discountCode, setDiscountCode] = useState('');
  const [message, setMessage] = useState({ text: '', type: '' });
  const [timeLeft, setTimeLeft] = useState(0);
  const [awaitingGateway, setAwaitingGateway] = useState(false);
  const [confirmRefund, setConfirmRefund] = useState(false);
  const [refundReason, setRefundReason] = useState('');

  const pollRef = useRef(null);

  const loadBooking = useCallback(async () => {
    const res = await api.get(`/bookings/${bookingId}`);
    setBooking(res.data);
    return res.data;
  }, [bookingId]);

  useEffect(() => {
    let alive = true;
    loadBooking()
      .catch((err) => { if (alive) setMessage({ text: apiError(err, 'Không tải được đơn hàng.'), type: 'error' }); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [loadBooking]);

  // Đồng hồ giữ chỗ. HoldExpiryDatetime do database sinh bằng SYSDATETIME() — GIỜ MÁY
  // CHỦ, không phải UTC — và DATETIME2 tuần tự hóa KHÔNG kèm hậu tố múi giờ. JavaScript
  // đọc chuỗi không hậu tố theo giờ địa phương, đúng với ý nghĩa dữ liệu. Vì vậy toDate()
  // trong lib/format CỐ Ý không gắn thêm 'Z'; gắn vào sẽ lệch đúng bằng offset trình
  // duyệt (ở Việt Nam là 7 tiếng) và làm đồng hồ đếm ngược sai hoàn toàn.
  const isPending = booking?.bookingStatus === BookingStatus.Pending;
  useEffect(() => {
    if (!isPending || !booking?.holdExpiryDatetime) return undefined;
    const tick = () => setTimeLeft(msUntil(booking.holdExpiryDatetime));
    tick();
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
  }, [isPending, booking?.holdExpiryDatetime]);

  const expired = isPending && timeLeft <= 0 && !!booking?.holdExpiryDatetime;
  const confirmed = booking?.bookingStatus === BookingStatus.Confirmed;

  useEffect(() => () => { if (pollRef.current) clearInterval(pollRef.current); }, []);

  const startPolling = useCallback(() => {
    if (pollRef.current) clearInterval(pollRef.current);
    pollRef.current = setInterval(async () => {
      try {
        const b = await loadBooking();
        if (b.bookingStatus !== BookingStatus.Pending) {
          clearInterval(pollRef.current);
          pollRef.current = null;
          setAwaitingGateway(false);
          if (b.bookingStatus === BookingStatus.Confirmed) {
            setMessage({ text: 'Thanh toán thành công. Vé của bạn đã được phát hành.', type: 'success' });
            toast('Thanh toán thành công — vé đã được phát hành.', { type: 'success' });
          } else {
            setMessage({
              text: `Đơn hàng kết thúc ở trạng thái: ${BOOKING_STATUS_LABEL[b.bookingStatus] ?? b.bookingStatus}.`,
              type: 'error',
            });
          }
        }
      } catch { /* lỗi mạng tạm thời — lần sau thử lại */ }
    }, 3000);
  }, [loadBooking, toast]);

  const handleApplyDiscount = async () => {
    const code = discountCode.trim();
    if (!code) return;
    setBusy(true);
    setMessage({ text: '', type: '' });
    try {
      await api.post(`/bookings/${bookingId}/promotion`, { discountCode: code });
      await loadBooking();
      setDiscountCode('');
      setMessage({ text: 'Đã áp dụng mã giảm giá.', type: 'success' });
    } catch (err) {
      // Backend có thể trả 54013: đơn đang có giao dịch thanh toán chờ xử lý nên GIÁ BỊ
      // KHÓA. Thông điệp từ ErrorHandlingMiddleware đã nói rõ, chỉ cần hiển thị lại.
      setMessage({ text: apiError(err, 'Mã giảm giá không hợp lệ hoặc đã hết hiệu lực.'), type: 'error' });
    } finally { setBusy(false); }
  };

  const handlePay = async () => {
    setBusy(true);
    setMessage({ text: '', type: '' });
    try {
      const res = await api.post(`/bookings/${bookingId}/payment`, {});
      const { paymentUrl } = res.data;
      // Chuyển người dùng sang cổng thanh toán. Việc xác nhận do cổng gọi ngược về
      // backend, KHÔNG do trình duyệt thực hiện.
      if (paymentUrl) window.open(paymentUrl, '_blank', 'noopener,noreferrer');
      setAwaitingGateway(true);
      setMessage({
        text: 'Đã tạo giao dịch. Hoàn tất ở cổng thanh toán vừa mở; trang này tự cập nhật khi có kết quả.',
        type: 'success',
      });
      startPolling();
    } catch (err) {
      setMessage({ text: apiError(err, 'Không khởi tạo được giao dịch thanh toán.'), type: 'error' });
    } finally { setBusy(false); }
  };

  /** Hủy GIỮ CHỖ (đơn còn Pending) — chỉ nhả ghế, không phát sinh tiền nong. */
  const handleReleaseHold = async () => {
    setBusy(true);
    setMessage({ text: '', type: '' });
    try {
      await api.delete(`/bookings/${bookingId}`);
      await loadBooking();
      toast('Đã hủy giữ chỗ. Ghế được trả lại cho người khác.', { type: 'success' });
    } catch (err) {
      setMessage({ text: apiError(err, 'Không hủy được đơn hàng.'), type: 'error' });
    } finally { setBusy(false); }
  };

  /**
   * Hủy đơn ĐÃ XÁC NHẬN và yêu cầu hoàn tiền (BR18a / BR31).
   *
   * Khác hẳn hủy giữ chỗ ở trên: đơn đã thanh toán phải đi qua sp_ProcessRefund —
   * nó tính tiền hoàn theo Concert.RefundPercentage và tôn trọng hạn hủy (CI10).
   * Giao diện không hỏi số tiền: để khách gõ số tiền là mở đường vượt mặt chính
   * sách của sự kiện.
   */
  const handleRefund = async () => {
    setBusy(true);
    setMessage({ text: '', type: '' });
    try {
      const res = await api.post(`/bookings/${bookingId}/cancel`, { reason: refundReason.trim() || null });
      setConfirmRefund(false);
      setRefundReason('');
      await loadBooking();
      toast(
        res.data?.refundId
          ? `Đã hủy vé. Yêu cầu hoàn tiền #${res.data.refundId} đang chờ ban tổ chức xác nhận.`
          : (res.data?.message ?? 'Đã hủy vé.'),
        { type: 'success' },
      );
    } catch (err) {
      setConfirmRefund(false);
      setMessage({ text: apiError(err, 'Không hủy được vé.'), type: 'error' });
    } finally { setBusy(false); }
  };

  if (loading) return <CheckoutSkeleton />;

  if (!booking) {
    return (
      <div className="container">
        <Card>
          <EmptyState title="Không tìm thấy đơn hàng">
            {message.text || 'Đơn hàng không tồn tại hoặc không thuộc về bạn.'}
          </EmptyState>
        </Card>
      </div>
    );
  }

  return (
    <div className="container" style={{ maxWidth: 'var(--container-narrow)' }}>
      <Link to="/my-bookings" className="row gap-2 text-sm text-secondary" style={{ marginBottom: 'var(--space-4)' }}>
        <IconChevronLeft size={14} /> Vé của tôi
      </Link>

      <Card>
        {/* ── Đầu đơn: trạng thái + đồng hồ ─────────────────────────────── */}
        <div className="card__header row wrap gap-3" style={{ justifyContent: 'space-between' }}>
          <div className="grow">
            <div className="overline">Đơn hàng {booking.bookingReference}</div>
            <h2 style={{ marginTop: 'var(--space-1)' }}>{booking.concertName}</h2>
          </div>
          <div className="row gap-2">
            <Badge tone={BOOKING_TONE[booking.bookingStatus] ?? 'neutral'} size="lg">
              {BOOKING_STATUS_LABEL[booking.bookingStatus] ?? booking.bookingStatus}
            </Badge>
            {isPending && booking.holdExpiryDatetime && (
              <span
                className="countdown"
                data-urgent={timeLeft > 0 && timeLeft < 120_000 ? 'true' : undefined}
                data-expired={expired ? 'true' : undefined}
                aria-label={expired ? 'Đã hết hạn giữ chỗ' : `Còn ${formatCountdown(timeLeft)} để thanh toán`}
              >
                <IconClock size={14} />
                {expired ? 'Hết hạn' : formatCountdown(timeLeft)}
              </span>
            )}
          </div>
        </div>

        <div className="card__body stack gap-6">
          {message.text && (
            <Alert tone={message.type === 'success' ? 'success' : 'danger'}>{message.text}</Alert>
          )}

          {/* ── Chi tiết ghế và giá ─────────────────────────────────────── */}
          <div>
            <div className="overline" style={{ marginBottom: 'var(--space-3)' }}>Chi tiết đơn hàng</div>
            <div className="stack gap-3">
              {booking.seats?.map((s) => (
                <div key={s.seatID} className="row gap-4" style={{ justifyContent: 'space-between' }}>
                  <span className="text-sm">
                    <strong>{s.seatNumber}</strong>
                    <span className="text-secondary">
                      {s.sectionName ? ` · ${s.sectionName}` : ''} · {s.categoryName}
                    </span>
                  </span>
                  <span className="text-sm tabular">{formatMoney(s.priceAtBooking)}</span>
                </div>
              ))}
            </div>

            <hr />

            <div className="stack gap-2">
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <span className="text-sm text-secondary">Tạm tính</span>
                <span className="text-sm tabular">{formatMoney(booking.subtotalAmount)}</span>
              </div>
              {Number(booking.discountAmount) > 0 && (
                <div className="row" style={{ justifyContent: 'space-between' }}>
                  <span className="text-sm text-secondary">Giảm giá</span>
                  <span className="text-sm tabular" style={{ color: 'var(--green-text)' }}>
                    − {formatMoney(booking.discountAmount)}
                  </span>
                </div>
              )}
            </div>

            <hr />

            <div className="row" style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
              <span style={{ fontWeight: 'var(--weight-semibold)' }}>Tổng cộng</span>
              <span className="tabular" style={{ fontSize: 'var(--text-2xl)', fontWeight: 'var(--weight-bold)' }}>
                {formatMoney(booking.finalAmount)}
              </span>
            </div>
          </div>

          {/* ── Hành động theo trạng thái ───────────────────────────────── */}
          {confirmed ? (
            <div className="stack gap-3">
              <Alert tone="success">
                Vé đã được phát hành. Xuất trình mã vé tại cổng vào để soát vé.
              </Alert>
              <Button variant="primary" size="lg" block onClick={() => navigate('/my-bookings')} icon={<IconCheck size={16} />}>
                Xem vé của tôi
              </Button>
              <Button variant="danger-quiet" block onClick={() => setConfirmRefund(true)}>
                Hủy vé và yêu cầu hoàn tiền
              </Button>
            </div>
          ) : !isPending ? (
            <Button size="lg" block onClick={() => navigate('/')}>Về trang sự kiện</Button>
          ) : (
            <div className="stack gap-4">
              <div>
                <div className="overline" style={{ marginBottom: 'var(--space-2)' }}>Mã giảm giá</div>
                <div className="row gap-2">
                  <Input
                    value={discountCode}
                    onChange={(e) => setDiscountCode(e.target.value.toUpperCase())}
                    placeholder="Nhập mã nếu có"
                    disabled={expired || busy || awaitingGateway}
                    aria-label="Mã giảm giá"
                  />
                  <Button
                    onClick={handleApplyDiscount}
                    disabled={expired || awaitingGateway || !discountCode.trim()}
                    loading={busy && !awaitingGateway}
                  >
                    Áp dụng
                  </Button>
                </div>
              </div>

              <Button
                variant="primary" size="lg" block
                onClick={handlePay}
                disabled={expired || awaitingGateway}
                loading={busy && !awaitingGateway}
                iconEnd={!expired && !awaitingGateway ? <IconArrowRight size={16} /> : undefined}
              >
                {expired ? 'Đã hết hạn giữ chỗ'
                  : awaitingGateway ? 'Đang chờ kết quả từ cổng thanh toán…'
                  : 'Thanh toán'}
              </Button>

              <Button variant="ghost" block onClick={handleReleaseHold} disabled={busy || awaitingGateway}>
                Hủy giữ chỗ
              </Button>
            </div>
          )}
        </div>
      </Card>

      <ConfirmDialog
        open={confirmRefund}
        onClose={() => setConfirmRefund(false)}
        onConfirm={handleRefund}
        title="Hủy vé và yêu cầu hoàn tiền?"
        confirmText="Xác nhận hủy vé"
        cancelText="Giữ lại vé"
        danger
        loading={busy}
      >
        <p>
          Ghế sẽ được trả lại ngay cho người khác và vé của bạn bị hủy. Số tiền hoàn
          tính theo chính sách của sự kiện, <strong>không phải toàn bộ số đã trả</strong>.
          Nếu đã quá hạn hủy, hệ thống sẽ từ chối.
        </p>
        <p style={{ marginTop: 'var(--space-3)', color: 'var(--red-text)' }}>
          Thao tác này không hoàn tác được.
        </p>
        <div style={{ marginTop: 'var(--space-4)' }}>
          <Input
            value={refundReason}
            onChange={(e) => setRefundReason(e.target.value)}
            placeholder="Lý do hủy (không bắt buộc)"
            maxLength={500}
            aria-label="Lý do hủy"
          />
        </div>
      </ConfirmDialog>
    </div>
  );
}

function CheckoutSkeleton() {
  return (
    <div className="container" style={{ maxWidth: 'var(--container-narrow)' }}>
      <Card>
        <div className="card__header stack gap-2">
          <Skeleton w={130} h={12} />
          <Skeleton w="55%" h={26} />
        </div>
        <div className="card__body stack gap-6">
          <div className="stack gap-3">
            <Skeleton w="100%" h={16} /><Skeleton w="100%" h={16} /><Skeleton w="70%" h={16} />
          </div>
          <Skeleton w="100%" h={46} r="var(--radius-md)" />
        </div>
      </Card>
    </div>
  );
}
