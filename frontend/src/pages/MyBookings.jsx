import { useEffect, useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import api, { apiError } from '../api/client';
import { BookingStatus, BOOKING_STATUS_LABEL } from '../domain/enums';
import { BOOKING_TONE } from '../domain/tone';
import { formatMoney, formatDateTime, bookingReference } from '../lib/format';
import {
  Badge, Button, Card, Alert, Skeleton, EmptyState, PageHeader, ConfirmDialog, Input,
} from '../components/ui';
import { useToast } from '../components/ui/Toast';
import { IconTicket, IconArrowRight } from '../components/ui/icons';

/**
 * Lịch sử đặt vé của chính khách hàng (FR50).
 *
 * Dữ liệu đến từ VW_CustomerBookingHistory — view tự lọc theo
 * SESSION_CONTEXT(N'UserID'), nên phạm vi dữ liệu do tầng database quyết định chứ
 * không phải do tham số client gửi lên. Không có tham số userId nào trong lời gọi
 * này, và đó là điều đúng: client không được phép chỉ định mình đang xem dữ liệu
 * của ai.
 */
export default function MyBookings() {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [target, setTarget] = useState(null);   // booking đang chờ xác nhận hủy
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const toast = useToast();

  const load = useCallback(async () => {
    const res = await api.get('/bookings');
    setItems(Array.isArray(res.data) ? res.data : []);
  }, []);

  useEffect(() => {
    let alive = true;
    load()
      .catch((err) => { if (alive) setError(apiError(err, 'Không tải được lịch sử đặt vé.')); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [load]);

  /**
   * Hủy vé đã xác nhận và yêu cầu hoàn tiền (BR18a / BR31).
   *
   * Đây KHÔNG phải endpoint dùng cho đơn đang giữ chỗ. Đơn còn Pending thì hủy bằng
   * DELETE /bookings/{id} ở trang thanh toán — chỉ nhả ghế, không phát sinh tiền nong.
   * Đơn đã thanh toán thì phải qua sp_ProcessRefund để tính tiền hoàn theo chính sách
   * của concert và tôn trọng hạn hủy (CI10).
   *
   * Giao diện KHÔNG hỏi số tiền hoàn — số tiền do database tự tính. Cho khách gõ số
   * tiền là mở đường vượt mặt chính sách của chính sự kiện đó.
   */
  const doCancel = async () => {
    if (!target) return;
    setBusy(true);
    try {
      const res = await api.post(`/bookings/${target.bookingID}/cancel`, {
        reason: reason.trim() || null,
      });
      setTarget(null);
      setReason('');
      setError('');
      await load();
      toast(
        res.data?.refundId
          ? `Đã hủy đơn #${target.bookingID}. Yêu cầu hoàn tiền #${res.data.refundId} đang chờ ban tổ chức xác nhận.`
          : (res.data?.message ?? `Đã hủy đơn #${target.bookingID}.`),
        { type: 'success' },
      );
    } catch (err) {
      setTarget(null);
      setError(apiError(err, 'Không hủy được đơn hàng.'));
    } finally { setBusy(false); }
  };

  return (
    <div className="container" style={{ maxWidth: 900 }}>
      <PageHeader
        title="Vé của tôi"
        subtitle="Toàn bộ đơn đặt vé của bạn. Đơn đang chờ thanh toán có thể tiếp tục; đơn đã xác nhận có thể hủy theo chính sách hoàn tiền của sự kiện."
      />

      {error && <div style={{ marginBottom: 'var(--space-5)' }}><Alert tone="danger">{error}</Alert></div>}

      {loading ? (
        <div className="stack gap-4">
          {Array.from({ length: 3 }, (_, i) => (
            <Card key={i}><div className="card__body row gap-4" style={{ justifyContent: 'space-between' }}>
              <div className="stack gap-2 grow">
                <Skeleton w="45%" h={18} /><Skeleton w="30%" h={13} /><Skeleton w={90} h={22} />
              </div>
              <Skeleton w={120} h={38} r="var(--radius-md)" />
            </div></Card>
          ))}
        </div>
      ) : items.length === 0 ? (
        <Card>
          <EmptyState
            icon={<IconTicket size={20} />}
            title="Bạn chưa có đơn đặt vé nào"
            action={<Link to="/" className="btn btn--primary">Xem sự kiện đang mở bán</Link>}
          >
            Khi bạn giữ chỗ hoặc mua vé, đơn hàng sẽ xuất hiện tại đây.
          </EmptyState>
        </Card>
      ) : (
        <div className="stack gap-4">
          {items.map((b) => (
            <BookingRow key={b.bookingID} booking={b} onCancel={() => { setTarget(b); setReason(''); }} />
          ))}
        </div>
      )}

      <ConfirmDialog
        open={!!target}
        onClose={() => setTarget(null)}
        onConfirm={doCancel}
        title="Hủy vé và yêu cầu hoàn tiền?"
        confirmText="Xác nhận hủy vé"
        cancelText="Giữ lại vé"
        danger
        loading={busy}
      >
        <p>
          Đơn <strong>{bookingReference(target?.bookingID)}</strong> — {target?.concertName}.
        </p>
        <p style={{ marginTop: 'var(--space-3)' }}>
          Ghế sẽ được trả lại ngay cho người khác và vé của bạn bị hủy. Số tiền hoàn
          tính theo chính sách của sự kiện, <strong>không phải toàn bộ số đã trả</strong>.
          Nếu đã quá hạn hủy, hệ thống sẽ từ chối.
        </p>
        <p style={{ marginTop: 'var(--space-3)', color: 'var(--red-text)' }}>
          Thao tác này không hoàn tác được.
        </p>
        <div style={{ marginTop: 'var(--space-4)' }}>
          <Input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="Lý do hủy (không bắt buộc)"
            maxLength={500}
            aria-label="Lý do hủy"
          />
        </div>
      </ConfirmDialog>
    </div>
  );
}

function BookingRow({ booking: b, onCancel }) {
  const canCancel = b.bookingStatus === BookingStatus.Confirmed;
  const isPending = b.bookingStatus === BookingStatus.Pending;

  return (
    <Card>
      <div className="card__body row wrap gap-4" style={{ justifyContent: 'space-between' }}>
        <div className="grow stack gap-2" style={{ minWidth: 200 }}>
          <div className="row wrap gap-2">
            <Badge tone={BOOKING_TONE[b.bookingStatus] ?? 'neutral'}>
              {BOOKING_STATUS_LABEL[b.bookingStatus] ?? b.bookingStatus}
            </Badge>
            <span className="pill tabular">{bookingReference(b.bookingID)}</span>
          </div>
          <h3>{b.concertName}</h3>
          <div className="text-sm text-secondary">
            Đặt lúc {formatDateTime(b.createdTimestamp)} · {b.seatCount} ghế
          </div>
        </div>

        <div className="stack gap-3" style={{ alignItems: 'flex-end' }}>
          <div className="tabular" style={{ fontSize: 'var(--text-xl)', fontWeight: 'var(--weight-bold)' }}>
            {formatMoney(b.finalAmount)}
          </div>
          <div className="row wrap gap-2" style={{ justifyContent: 'flex-end' }}>
            {canCancel && (
              <Button size="sm" variant="danger-quiet" onClick={onCancel}>Hủy vé</Button>
            )}
            <Link
              to={`/checkout/${b.bookingID}`}
              className={`btn btn--sm ${isPending ? 'btn--primary' : 'btn--secondary'}`}
            >
              {isPending ? 'Tiếp tục thanh toán' : 'Xem chi tiết'}
              <IconArrowRight size={14} />
            </Link>
          </div>
        </div>
      </div>
    </Card>
  );
}
