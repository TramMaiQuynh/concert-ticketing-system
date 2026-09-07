import { useState, useRef, useEffect } from 'react';
import api, { apiError } from '../api/client';
import { CHECKIN_RESULT_LABEL } from '../domain/enums';
import { checkinTone } from '../domain/tone';
import { formatDateTime } from '../lib/format';
import { Badge, Button, Card, Alert, Field, Input, PageHeader } from '../components/ui';
import { IconScan, IconCheck, IconX } from '../components/ui/icons';

/**
 * Màn hình soát vé tại cổng.
 *
 * Bối cảnh sử dụng khác hẳn mọi trang khác: nhân viên đứng ở cửa, cầm điện thoại
 * hoặc máy quét, làm đi làm lại một thao tác duy nhất trong điều kiện ồn và vội.
 * Vì vậy màn này được thiết kế ngược với phần còn lại của ứng dụng:
 *
 *   • Kết quả chiếm gần hết màn hình, đọc được từ xa một tầm tay.
 *   • Ô nhập tự lấy lại focus sau mỗi lần quét, để máy quét mã vạch (vốn hoạt
 *     động như một bàn phím và tự gõ Enter) bắn liên tục mà không phải chạm.
 *   • Mã vé được xoá ngay sau khi gửi, ConcertID thì GIỮ LẠI — cả ca trực chỉ
 *     soát một sự kiện, bắt nhập lại số concert mỗi lượt là vô nghĩa.
 *
 * Quyết định thành công/thất bại đọc từ `validationResult`, KHÔNG phải từ việc
 * request có 200 hay không: sp_CheckInTicket trả HTTP 200 cho cả vé hợp lệ lẫn vé
 * đã dùng — khác biệt nằm trong nội dung phản hồi.
 */
export default function StaffCheckIn() {
  const [ticketCode, setTicketCode] = useState('');
  const [concertId, setConcertId] = useState('');
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [history, setHistory] = useState([]);
  const codeRef = useRef(null);

  useEffect(() => { codeRef.current?.focus(); }, []);

  const submit = async (e) => {
    e.preventDefault();
    const code = ticketCode.trim();
    const cid = Number(concertId);
    if (!code || !cid) return;

    setBusy(true);
    setError('');
    setResult(null);
    try {
      const res = await api.post('/checkin', { ticketCode: code, concertId: cid });
      setResult(res.data);
      setHistory((h) => [{ code, result: res.data.validationResult, at: Date.now() }, ...h].slice(0, 8));
      setTicketCode('');
    } catch (err) {
      setError(apiError(err, 'Không xác thực được vé.'));
    } finally {
      setBusy(false);
      // Trả focus về ô mã vé để lượt quét kế tiếp đi thẳng vào, không cần chạm.
      requestAnimationFrame(() => codeRef.current?.focus());
    }
  };

  const ok = result?.validationResult === 'SUCCESS';

  return (
    <div className="container" style={{ maxWidth: 640 }}>
      <PageHeader
        title="Soát vé"
        subtitle="Nhập hoặc quét mã vé. Máy quét mã vạch hoạt động như bàn phím — chỉ cần đặt con trỏ ở ô mã vé."
      />

      {/* ── Kết quả ──────────────────────────────────────────────────────── */}
      {result && (
        <Card
          style={{
            marginBottom: 'var(--space-5)',
            borderColor: ok ? 'var(--green-border)' : 'var(--red-border)',
            background: ok ? 'var(--green-bg)' : 'var(--red-bg)',
          }}
        >
          <div className="card__body stack gap-3" style={{ alignItems: 'center', textAlign: 'center' }}>
            <div
              style={{
                display: 'grid', placeItems: 'center',
                width: 56, height: 56, borderRadius: '50%',
                background: ok ? 'var(--green-solid)' : 'var(--red-solid)',
                color: '#FFFFFF',
              }}
              aria-hidden
            >
              {ok ? <IconCheck size={28} /> : <IconX size={28} />}
            </div>

            {/* aria-live: trình đọc màn hình đọc kết quả ngay khi nó xuất hiện,
                mà không cần người dùng phải đi tìm. */}
            <div aria-live="assertive">
              <div
                style={{
                  fontSize: 'var(--text-2xl)',
                  fontWeight: 'var(--weight-bold)',
                  color: ok ? 'var(--green-text)' : 'var(--red-text)',
                }}
              >
                {CHECKIN_RESULT_LABEL[result.validationResult] ?? result.validationResult}
              </div>
              <div className="text-sm" style={{ marginTop: 'var(--space-1)', color: ok ? 'var(--green-text)' : 'var(--red-text)', opacity: 0.85 }}>
                {result.validationInfo}
              </div>
            </div>

            {result.checkInTime && (
              <div className="text-xs" style={{ color: 'var(--green-text)', opacity: 0.8 }}>
                Vào cổng lúc {formatDateTime(result.checkInTime)}
              </div>
            )}
          </div>
        </Card>
      )}

      {error && <div style={{ marginBottom: 'var(--space-5)' }}><Alert tone="danger">{error}</Alert></div>}

      {/* ── Form quét ────────────────────────────────────────────────────── */}
      <Card>
        <form className="card__body stack gap-4" onSubmit={submit}>
          <Field label="Mã sự kiện" hint="Giữ nguyên suốt ca trực — không phải nhập lại sau mỗi lượt quét.">
            {(a) => (
              <Input
                {...a}
                type="number" min="1" inputMode="numeric"
                value={concertId}
                onChange={(e) => setConcertId(e.target.value)}
                placeholder="Ví dụ: 1"
                required
              />
            )}
          </Field>

          <Field label="Mã vé" required>
            {(a) => (
              <Input
                {...a}
                ref={codeRef}
                value={ticketCode}
                onChange={(e) => setTicketCode(e.target.value)}
                placeholder="Quét hoặc dán mã vé"
                autoComplete="off"
                spellCheck={false}
                required
                style={{ fontFamily: 'ui-monospace, monospace', fontSize: 'var(--text-md)' }}
              />
            )}
          </Field>

          <Button
            type="submit" variant="primary" size="lg" block
            loading={busy}
            disabled={!ticketCode.trim() || !concertId}
            icon={<IconScan size={17} />}
          >
            Xác thực vé
          </Button>
        </form>
      </Card>

      {/* ── Lịch sử phiên làm việc ───────────────────────────────────────── */}
      {history.length > 0 && (
        <div style={{ marginTop: 'var(--space-6)' }}>
          <div className="overline" style={{ marginBottom: 'var(--space-3)' }}>
            {history.length} lượt quét gần nhất
          </div>
          <Card>
            <div className="scroll-x">
              <table className="table">
                <thead>
                  <tr><th>Mã vé</th><th>Kết quả</th><th style={{ textAlign: 'right' }}>Lúc</th></tr>
                </thead>
                <tbody>
                  {history.map((h) => (
                    <tr key={`${h.code}-${h.at}`}>
                      <td style={{ fontFamily: 'ui-monospace, monospace', fontSize: 'var(--text-xs)' }}>
                        {h.code.length > 18 ? `${h.code.slice(0, 18)}…` : h.code}
                      </td>
                      <td>
                        <Badge tone={checkinTone(h.result)}>
                          {CHECKIN_RESULT_LABEL[h.result] ?? h.result}
                        </Badge>
                      </td>
                      <td className="num text-secondary">
                        {new Date(h.at).toLocaleTimeString('vi-VN')}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>
          <p className="text-xs text-muted" style={{ marginTop: 'var(--space-2)' }}>
            Lịch sử này chỉ nằm trong phiên làm việc hiện tại, không được lưu lại.
            Nhật ký soát vé đầy đủ nằm ở bảng CheckIn trong database.
          </p>
        </div>
      )}
    </div>
  );
}
