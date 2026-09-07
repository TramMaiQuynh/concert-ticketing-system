import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import api, { apiError } from '../api/client';
import { formatMoney } from '../lib/format';
import { Button, Card, Alert, Skeleton } from '../components/ui';
import { IconCheck, IconX, IconAlert } from '../components/ui/icons';

/**
 * TRANG MÔ PHỎNG CỔNG THANH TOÁN — chỉ dùng cho demo.
 *
 * Đây là nơi người dùng "được chuyển tới cổng thanh toán". Nó đóng vai màn hình của PSP.
 *
 * Điều quan trọng: trang này KHÔNG tự xác nhận thanh toán. Nó chỉ gọi
 * POST /api/payment-simulator/{bookingId}/{paymentId}/succeed — và chính BACKEND mới là
 * bên tính chữ ký rồi gọi vào luồng xác nhận thật. Bí mật chữ ký không bao giờ xuống tới
 * trình duyệt, đúng như với cổng thanh toán thật.
 *
 * (Bản frontend trước đã làm ngược lại: nhận chữ ký từ API rồi tự gọi webhook. Đó là lỗ
 *  hổng cho phép khách tự cấp vé cho mình mà không trả tiền.)
 *
 * Về hình thức: trang này CỐ Ý trông khác phần còn lại của ứng dụng — viền cảnh báo,
 * nhãn "môi trường thử nghiệm" rõ ràng. Một màn hình giả lập thanh toán mà trông giống
 * hệt sản phẩm thật là thứ dễ gây nhầm lẫn tai hại, kể cả với chính người phát triển.
 */
export default function PaymentSimulator() {
  const { bookingId, paymentId } = useParams();
  const navigate = useNavigate();

  const [booking, setBooking] = useState(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState({ text: '', type: '' });

  useEffect(() => {
    let alive = true;
    api.get(`/bookings/${bookingId}`)
      .then((res) => alive && setBooking(res.data))
      .catch((err) => alive && setMessage({ text: apiError(err, 'Không tải được đơn hàng.'), type: 'error' }))
      .finally(() => alive && setLoading(false));
    return () => { alive = false; };
  }, [bookingId]);

  const act = async (outcome) => {
    setBusy(true);
    setMessage({ text: '', type: '' });
    try {
      const res = await api.post(`/payment-simulator/${bookingId}/${paymentId}/${outcome}`);

      if (outcome === 'succeed') {
        // Backend trả về KẾT QUẢ NGHIỆP VỤ, không chỉ "thành công".
        // BookingConfirmed = false nghĩa là tiền đã ghi nhận nhưng đơn không được xác
        // nhận (lệch số tiền, hết hạn giữ chỗ…) và một yêu cầu hoàn tiền đã được tạo.
        setMessage({
          text: res.data.bookingConfirmed
            ? 'Thanh toán thành công. Đang quay lại trang đơn hàng…'
            : `Giao dịch đã ghi nhận nhưng đơn KHÔNG được xác nhận: ${res.data.message}`,
          type: res.data.bookingConfirmed ? 'success' : 'error',
        });
      } else {
        setMessage({ text: 'Đã đánh dấu giao dịch thất bại. Bạn có thể thanh toán lại.', type: 'error' });
      }

      setTimeout(() => navigate(`/checkout/${bookingId}`), 2000);
    } catch (err) {
      setMessage({ text: apiError(err, 'Cổng thanh toán mô phỏng gặp lỗi.'), type: 'error' });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="container" style={{ maxWidth: 440 }}>
      <Card style={{ borderColor: 'var(--amber-border)' }}>
        <div
          className="card__header row gap-3"
          style={{ background: 'var(--amber-bg)', borderRadius: 'var(--radius-xl) var(--radius-xl) 0 0', borderBottomColor: 'var(--amber-border)' }}
        >
          <span style={{ color: 'var(--amber-text)', flex: 'none' }}><IconAlert size={17} /></span>
          <div className="text-sm" style={{ color: 'var(--amber-text)', lineHeight: 'var(--leading-sm)' }}>
            <strong>Cổng thanh toán mô phỏng</strong> — môi trường thử nghiệm. Không có
            giao dịch tiền thật. Backend vẫn ký và xác nhận đúng như cổng thật.
          </div>
        </div>

        <div className="card__body stack gap-5">
          <h2 style={{ textAlign: 'center' }}>Xác nhận thanh toán</h2>

          {message.text && (
            <Alert tone={message.type === 'success' ? 'success' : 'danger'}>{message.text}</Alert>
          )}

          {loading ? (
            <div className="stack gap-3">
              <Skeleton w="100%" h={16} /><Skeleton w="100%" h={16} /><Skeleton w="60%" h={26} />
            </div>
          ) : booking && (
            <div
              className="stack gap-3"
              style={{
                background: 'var(--surface-sunken)',
                border: '1px solid var(--border-subtle)',
                borderRadius: 'var(--radius-lg)',
                padding: 'var(--space-5)',
              }}
            >
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <span className="text-sm text-secondary">Sự kiện</span>
                <span className="text-sm" style={{ fontWeight: 'var(--weight-medium)' }}>{booking.concertName}</span>
              </div>
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <span className="text-sm text-secondary">Mã đơn</span>
                <span className="text-sm tabular" style={{ fontWeight: 'var(--weight-medium)' }}>{booking.bookingReference}</span>
              </div>
              <hr style={{ margin: 'var(--space-1) 0' }} />
              <div className="row" style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span style={{ fontWeight: 'var(--weight-semibold)' }}>Số tiền</span>
                <span className="tabular" style={{ fontSize: 'var(--text-2xl)', fontWeight: 'var(--weight-bold)' }}>
                  {formatMoney(booking.finalAmount)}
                </span>
              </div>
            </div>
          )}

          <div className="stack gap-2">
            <Button
              variant="primary" size="lg" block
              loading={busy} disabled={loading}
              onClick={() => act('succeed')}
              icon={<IconCheck size={17} />}
            >
              Thanh toán thành công
            </Button>
            <Button
              variant="danger-quiet" block
              disabled={busy || loading}
              onClick={() => act('fail')}
              icon={<IconX size={16} />}
            >
              Mô phỏng thanh toán thất bại
            </Button>
          </div>
        </div>
      </Card>
    </div>
  );
}
