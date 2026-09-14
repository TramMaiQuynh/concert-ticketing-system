import { useState } from 'react';
import api from '../../api/client';
import { useConcertOptions } from '../../lib/concertOptions';
import { Panel, Banner, IdPicker, useAction } from '../../components/form';
import { Button, PageHeader, StatGrid, StatTile } from '../../components/ui';
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
      <PageHeader title="Báo cáo" subtitle="Doanh thu, tồn kho, tỷ lệ check-in và danh sách người giữ vé theo từng Concert." />
      <Panel
        title="Báo cáo Concert"
        tone="workflow"
        subtitle="Doanh thu, tồn kho, tỷ lệ check-in và danh sách người giữ vé — chỉ trong phạm vi Concert bạn sở hữu (Admin xem được mọi Concert)."
      >
        <form onSubmit={load}>
          <IdPicker label="Concert" items={concerts} value={concertId} onChange={setConcertId} />

          <Button type="submit" variant="primary" loading={act.busy} disabled={!concertId} style={{ marginTop: '16px' }}>
            Xem báo cáo
          </Button>
          <Banner state={act.state} />
        </form>
      </Panel>

      {summary && (
        <Panel title={`${summary.concertName} — Tóm tắt`} subtitle={`${summary.artistName ?? '—'} · ${summary.venueName ?? '—'}`}>
          <StatGrid>
            <StatTile label="Doanh thu (net)" value={formatMoney(summary.totalRevenue)} tone="accent" />
            <StatTile label="Tổng số ghế" value={summary.totalInventorySeats} />
            <StatTile label="Còn trống" value={summary.availableSeats} />
            <StatTile label="Đã đặt" value={summary.bookedSeats} />
            <StatTile label="Đang giữ" value={summary.onHoldSeats} />
            <StatTile label="Đơn đã xác nhận" value={summary.confirmedBookings} />
            <StatTile label="Đơn đã hủy" value={summary.cancelledBookings} />
            <StatTile label="Đơn hết hạn giữ chỗ" value={summary.expiredBookings} />
          </StatGrid>
        </Panel>
      )}

      {checkin && (
        <Panel title="Check-in">
          <StatGrid>
            <StatTile label="Vé đã phát hành" value={checkin.totalIssuedTickets} />
            <StatTile label="Đã vào cổng" value={checkin.totalCheckedIn} />
            <StatTile label="Chưa vào cổng" value={checkin.pendingEntry} />
            <StatTile label="Tỷ lệ vào cổng" value={`${checkin.checkInRatePct}%`} tone="accent" />
          </StatGrid>
        </Panel>
      )}

      {attendees && (
        <Panel title={`Danh sách người giữ vé (${attendees.length})`}>
          {attendees.length === 0 ? (
            <div className="field-hint">Concert này chưa phát hành vé nào (chưa có đơn được xác nhận).</div>
          ) : (
            <div className="scroll-x">
              <table className="table">
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
            <div className="scroll-x">
              <table className="table">
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
