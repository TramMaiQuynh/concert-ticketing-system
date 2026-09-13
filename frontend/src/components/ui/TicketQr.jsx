import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';

/**
 * Vẽ QR code từ ticket_code (FR31: QR là định dạng biểu diễn DUY NHẤT hệ thống hỗ
 * trợ cho Ticket Validation tại cổng).
 *
 * Dùng thư viện 'qrcode' để encode — không tự viết lại thuật toán QR (mode
 * selection, Reed-Solomon error correction...): đó là việc đã có chuẩn hoá
 * (ISO/IEC 18004) và thư viện chuẩn để làm, tự viết lại là tái phát minh bánh xe
 * và rất dễ sai ở đúng chỗ khó kiểm tra bằng mắt nhất.
 *
 * Vẽ ở CLIENT, không sinh ảnh ở server: QR chỉ là một cách BIỂU DIỄN của chuỗi
 * ticket_code, không phải một lớp mã hoá bảo mật — ai cầm ảnh QR cũng đọc ngược ra
 * được đúng chuỗi đó bằng bất kỳ camera nào. Sinh ảnh ở server không thêm bảo vệ
 * nào (client đã có sẵn chuỗi gốc qua API), chỉ thêm dependency và chi phí tính
 * toán phía server một cách vô ích.
 */
export default function TicketQr({ value, size = 96 }) {
  const canvasRef = useRef(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!value || !canvasRef.current) return undefined;
    let cancelled = false;
    setFailed(false);
    QRCode.toCanvas(canvasRef.current, value, { width: size, margin: 1 })
      .catch(() => { if (!cancelled) setFailed(true); });
    return () => { cancelled = true; };
  }, [value, size]);

  if (!value) return null;

  if (failed) {
    return (
      <span className="text-xs text-muted" style={{ width: size, display: 'inline-block' }}>
        Không vẽ được QR — dùng mã chữ bên cạnh để soát vé.
      </span>
    );
  }

  return (
    <canvas
      ref={canvasRef}
      width={size}
      height={size}
      role="img"
      aria-label="Mã QR của vé — xuất trình tại cổng để soát vé"
      style={{ borderRadius: 'var(--radius-md)' }}
    />
  );
}
