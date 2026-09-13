import { useState } from 'react';
import api from '../../api/client';
import { useConcertOptions } from '../../lib/concertOptions';
import { Panel, Banner, IdPicker, useAction } from '../../components/form';
import { TICKET_STATUS_LABEL, WAITLIST_STATUS_LABEL } from '../../domain/enums';
import { formatMoney, formatDateTime } from '../../lib/format';

/**
 * Báo cáo Organizer (FR55/FR56/BP14) — doanh thu/tồn kho, tỷ lệ check-in, danh
 * sách người giữ vé của một Concert. Cả ba đọc qua VW_ConcertSalesSummary/
 * VW_CheckInReport/VW_ConcertAttendeeList — ba view tự lọc theo Concert.OrganizerUserID
 * (RLS qua SESSION_CONTEXT), nên trang này không cần biết ai đang đăng nhập: gọi sai
 * Concert của người khác chỉ nhận 404, không lộ Concert đó có tồn tại hay không.
 *
 * KHÔNG có mã vé (ticket_code/QR) trong danh sách người giữ vé — đó là bearer
 * credential dùng để qua cổng, chỉ giao cho chính khách hàng (trang Vé của tôi)
 * và Check-in Staff tại cổng (BP9), không phải cho báo cáo vận hành.
 */
export default function Reports() {
  const { options: concerts } = useConcertOptions();
  const act = useAction();
  const [concertId, setConcertId] = useState('');
  const [summary, setSummary] = useState(null);
  const [checkin, setCheckin] = useState(null);
  const [attendees, setAttendees] = useState(null);
  const [waitlist, setWaitlist] = useState(null);

  const load = (e) => {
    e.preventDefault();
    setSummary(null);
    setCheckin(null);
    setAttendees(null);
    setWaitlist(null);
    act.run(async () => {
      const id = Number(concertId);
      const [s, c, a, w] = await Promise.all([
        api.get(`/admin/concerts/${id}/summary`),
        api.get(`/admin/concerts/${id}/checkin-report`),
        api.get(`/admin/concerts/${id}/attendees`),
        api.get(`/admin/concerts/${id}/waitlist`),
      ]);
      setSummary(s.data);
      setCheckin(c.data);
      setAttendees(a.data);
      setWaitlist(w.data);
    });
  };

  return (
    <>
      <Panel
        title="Báo cáo Concert"
        subtitle="Doanh thu, tồn kho, tỷ lệ check-in và danh sách người giữ vé — chỉ trong phạm vi Concert bạn sở hữu (Admin xem được mọi Concert)."
      >
        <form onSubmit={load}>
          <IdPicker label="Concert" items={concerts} value={concertId} onChange={setConcertId} />

          <button className="btn-primary" style={{ marginTop: '16px' }} disabled={act.busy || !concertId}>
            {act.busy ? 'Đang tải…' : 'Xem báo cáo'}
          </button>
          <Banner state={act.state} />
        </form>
      </Panel>

      {summary && (
        <Panel title={`${summary.concertName} — Tóm tắt`} subtitle={`${summary.artistName ?? '—'} · ${summary.venueName ?? '—'}`}>
          <div className="field-grid">
            <SummaryStat label="Doanh thu (net)" value={formatMoney(summary.totalRevenue)} />
            <SummaryStat label="Tổng số ghế" value={summary.totalInventorySeats} />
            <SummaryStat label="Còn trống" value={summary.availableSeats} />
            <SummaryStat label="Đã đặt" value={summary.bookedSeats} />
            <SummaryStat label="Đang giữ" value={summary.onHoldSeats} />
            <SummaryStat label="Đơn đã xác nhận" value={summary.confirmedBookings} />
            <SummaryStat label="Đơn đã hủy" value={summary.cancelledBookings} />
            <SummaryStat label="Đơn hết hạn giữ chỗ" value={summary.expiredBookings} />
          </div>
        </Panel>
      )}

      {checkin && (
        <Panel title="Check-in">
          <div className="field-grid">
            <SummaryStat label="Vé đã phát hành" value={checkin.totalIssuedTickets} />
            <SummaryStat label="Đã vào cổng" value={checkin.totalCheckedIn} />
            <SummaryStat label="Chưa vào cổng" value={checkin.pendingEntry} />
            <SummaryStat label="Tỷ lệ vào cổng" value={`${checkin.checkInRatePct}%`} />
          </div>
        </Panel>
      )}

      {attendees && (
        <Panel title={`Danh sách người giữ vé (${attendees.length})`}>
          {attendees.length === 0 ? (
            <div className="field-hint">Concert này chưa phát hành vé nào (chưa có đơn được xác nhận).</div>
          ) : (
            <div className="table-wrap">
              <table className="data">
                <thead>
                  <tr>
                    <th>Ghế</th><th>Khu</th><th>Hạng vé</th>
                    <th>Khách</th><th>Trạng thái vé</th><th>Vào cổng lúc</th>
                  </tr>
                </thead>
                <tbody>
                  {attendees.map((a) => (
                    <tr key={a.ticketID}>
                      <td>{a.seatCode}</td>
                      <td>{a.zoneName}</td>
                      <td>{a.categoryName}</td>
                      <td>{a.displayName} <span className="text-muted">({a.username})</span></td>
                      <td>{TICKET_STATUS_LABEL[a.ticketStatus] ?? a.ticketStatus}</td>
                      <td>{a.usedTimestamp ? formatDateTime(a.usedTimestamp) : '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Panel>
      )}

      {waitlist && (
        <Panel
          title={`Danh sách chờ (${waitlist.length})`}
          subtitle="Ai đang xếp hàng cho hạng vé nào, ở vị trí thứ mấy, đã được cấp cơ hội mua hay chưa. Cơ hội hết hạn sẽ được hệ thống tự chuyển cho người kế tiếp."
        >
          {waitlist.length === 0 ? (
            <div className="field-hint">
              Chưa có ai đăng ký danh sách chờ cho Concert này (hoặc Concert chưa bật tính năng này).
            </div>
          ) : (
            <div className="table-wrap">
              <table className="data">
                <thead>
                  <tr>
                    <th>Vị trí</th><th>Khách</th><th>Hạng vé</th><th>Số ghế muốn</th>
                    <th>Trạng thái</th><th>Ghế đang giữ</th><th>Cơ hội hết hạn lúc</th>
                  </tr>
                </thead>
                <tbody>
                  {waitlist.map((w) => (
                    <tr key={w.waitlistEntryID}>
                      <td className="tabular">{w.queuePosition ?? '—'}</td>
                      <td>{w.displayName} <span className="text-muted">({w.username})</span></td>
                      <td>{w.categoryName}</td>
                      <td className="tabular">{w.requestedQuantity}</td>
                      <td>{WAITLIST_STATUS_LABEL[w.entryStatus] ?? w.entryStatus}</td>
                      <td className="tabular">{w.activeAllocationCount}</td>
                      <td>
                        {w.opportunityExpiryTimestamp
                          ? formatDateTime(w.opportunityExpiryTimestamp)
                          : '—'}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Panel>
      )}
    </>
  );
}

function SummaryStat({ label, value }) {
  return (
    <div>
      <div className="overline">{label}</div>
      <div className="tabular" style={{ fontSize: 'var(--text-lg)', fontWeight: 'var(--weight-semibold)' }}>
        {value}
      </div>
    </div>
  );
}
