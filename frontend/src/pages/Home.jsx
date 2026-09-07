import { useState, useEffect, useMemo } from 'react';
import { Link } from 'react-router-dom';
import api, { apiError } from '../api/client';
import { ConcertStatus, CONCERT_STATUS_LABEL, canPurchase } from '../domain/enums';
import { CONCERT_TONE, coverGradient } from '../domain/tone';
import { formatDateTime } from '../lib/format';
import { Badge, Card, Skeleton, EmptyState, Alert, Input, Tabs } from '../components/ui';
import { IconCalendar, IconPin, IconSearch, IconInbox } from '../components/ui/icons';

/**
 * Trang chủ — danh sách sự kiện.
 *
 * Danh sách này đến từ `GET /concerts`, đã lọc bỏ concert Draft ở tầng
 * repository (`ConcertStatus <> 'Draft'`). Nghĩa là bản nháp của ban tổ chức
 * không bao giờ lọt ra ngoài, và việc đó được bảo đảm ở máy chủ chứ không phải
 * bằng cách giao diện tự giấu đi.
 *
 * Lọc và tìm kiếm làm ở phía client vì API chưa có tham số tương ứng — với quy
 * mô một trang (100 sự kiện) thì đây là lựa chọn đúng; lớn hơn thì phải đẩy
 * xuống máy chủ chứ không tải hết về rồi lọc.
 */
export default function Home() {
  const [concerts, setConcerts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [q, setQ] = useState('');
  const [filter, setFilter] = useState('all');

  useEffect(() => {
    let alive = true;
    api.get('/concerts', { params: { page: 1, pageSize: 50 } })
      .then((res) => { if (alive) setConcerts(Array.isArray(res.data) ? res.data : []); })
      .catch((err) => { if (alive) setError(apiError(err, 'Không tải được danh sách sự kiện.')); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, []);

  const visible = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return concerts.filter((c) => {
      if (filter === 'onsale' && !canPurchase(c)) return false;
      if (filter === 'upcoming' && c.concertStatus !== ConcertStatus.Published) return false;
      if (!needle) return true;
      return [c.concertName, c.artistName, c.venueName]
        .some((v) => (v ?? '').toLowerCase().includes(needle));
    });
  }, [concerts, q, filter]);

  const onSaleCount = concerts.filter(canPurchase).length;

  return (
    <div className="container">
      {/* ── Hero ─────────────────────────────────────────────────────────── */}
      <section style={{ padding: 'var(--space-6) 0 var(--space-10)' }}>
        <h1 style={{ fontSize: 'clamp(2rem, 5vw, var(--text-5xl))', lineHeight: 'var(--leading-5xl)', maxWidth: '16ch' }}>
          Đặt vé cho đêm nhạc bạn không muốn bỏ lỡ.
        </h1>
        <p
          className="text-secondary"
          style={{ marginTop: 'var(--space-4)', fontSize: 'var(--text-md)', maxWidth: '54ch' }}
        >
          Chọn ghế theo thời gian thực, giữ chỗ có thời hạn, thanh toán an toàn.
          {onSaleCount > 0 && (
            <> Hiện có <strong style={{ color: 'var(--text)' }}>{onSaleCount} sự kiện</strong> đang mở bán.</>
          )}
        </p>
      </section>

      {/* ── Bộ lọc ───────────────────────────────────────────────────────── */}
      <div
        className="row wrap gap-4"
        style={{ justifyContent: 'space-between', marginBottom: 'var(--space-6)' }}
      >
        <Tabs
          value={filter}
          onChange={setFilter}
          items={[
            { value: 'all', label: `Tất cả (${concerts.length})` },
            { value: 'onsale', label: `Đang mở bán (${onSaleCount})` },
            { value: 'upcoming', label: 'Sắp mở bán' },
          ]}
        />
        <div style={{ position: 'relative', width: 'min(280px, 100%)' }}>
          <span
            style={{
              position: 'absolute', left: 'var(--space-3)', top: '50%',
              transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none',
            }}
          >
            <IconSearch size={15} />
          </span>
          <Input
            type="search"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Tìm sự kiện, nghệ sĩ, địa điểm…"
            aria-label="Tìm sự kiện"
            style={{ paddingLeft: 'var(--space-8)' }}
          />
        </div>
      </div>

      {error && <Alert tone="danger">{error}</Alert>}

      {/* ── Danh sách ────────────────────────────────────────────────────── */}
      {loading ? (
        <div className="event-grid">
          {Array.from({ length: 6 }, (_, i) => <ConcertCardSkeleton key={i} />)}
        </div>
      ) : visible.length === 0 ? (
        <Card>
          <EmptyState
            icon={<IconInbox size={20} />}
            title={concerts.length === 0 ? 'Chưa có sự kiện nào' : 'Không tìm thấy sự kiện phù hợp'}
          >
            {concerts.length === 0
              ? 'Khi ban tổ chức công bố sự kiện, chúng sẽ xuất hiện ở đây.'
              : 'Thử từ khoá khác hoặc bỏ bớt bộ lọc.'}
          </EmptyState>
        </Card>
      ) : (
        <div className="event-grid">
          {visible.map((c) => <ConcertCard key={c.concertID} concert={c} />)}
        </div>
      )}
    </div>
  );
}

function ConcertCard({ concert: c }) {
  const purchasable = canPurchase(c);

  return (
    <Link to={`/concert/${c.concertID}`} className="card card--link" style={{ overflow: 'hidden' }}>
      <div className="event-cover" style={{ background: coverGradient(c.concertID) }}>
        <span className="event-cover__glyph">{(c.artistName ?? c.concertName ?? '?').charAt(0).toUpperCase()}</span>
      </div>

      <div className="card__body stack gap-3">
        <div className="row wrap gap-2" style={{ justifyContent: 'space-between' }}>
          <Badge tone={CONCERT_TONE[c.concertStatus] ?? 'neutral'}>
            {CONCERT_STATUS_LABEL[c.concertStatus] ?? c.concertStatus}
          </Badge>
          {/* SalesPaused là cờ riêng, độc lập với trạng thái concert: sự kiện vẫn
              OnSale nhưng tạm ngừng nhận đơn. Không hiện ra thì người dùng không
              hiểu vì sao bấm vào lại không đặt được. */}
          {c.salesPaused && <Badge tone="amber">Tạm dừng bán</Badge>}
        </div>

        <div>
          <h3 style={{ marginBottom: 'var(--space-1)' }}>{c.concertName}</h3>
          <div className="text-sm text-secondary">{c.artistName}</div>
        </div>

        <div className="stack gap-2 text-sm text-secondary">
          <span className="row gap-2">
            <IconCalendar size={14} /> {formatDateTime(c.startDatetime)}
          </span>
          <span className="row gap-2">
            <IconPin size={14} />
            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {c.venueName}{c.address ? ` · ${c.address}` : ''}
            </span>
          </span>
        </div>

        {!purchasable && (
          <div className="text-xs text-muted" style={{ paddingTop: 'var(--space-1)' }}>
            Hiện không nhận đặt vé
          </div>
        )}
      </div>
    </Link>
  );
}

/**
 * Khung xương khi đang tải.
 *
 * Có cùng chiều cao và bố cục với thẻ thật, nên khi dữ liệu về, nội dung không
 * làm trang giật nhảy — đúng thứ Cumulative Layout Shift đo và phạt.
 */
function ConcertCardSkeleton() {
  return (
    <Card style={{ overflow: 'hidden' }}>
      <Skeleton h={108} r="var(--radius-xl) var(--radius-xl) 0 0" />
      <div className="card__body stack gap-3">
        <Skeleton w={92} h={22} r="var(--radius-sm)" />
        <div className="stack gap-2">
          <Skeleton w="80%" h={18} />
          <Skeleton w="45%" h={13} />
        </div>
        <div className="stack gap-2">
          <Skeleton w="65%" h={13} />
          <Skeleton w="55%" h={13} />
        </div>
      </div>
    </Card>
  );
}
