import { useState } from 'react';
import api from '../../api/client';
import { Field, Panel, useAction } from '../../components/form';
import { Button, PageHeader } from '../../components/ui';

/**
 * Khối thông báo TĨNH cho trang demo.
 *
 * Vì sao không dùng `Banner` của components/form.jsx: component đó có chữ ký
 * `{ state }` — nó chỉ hiển thị trạng thái của useAction (thành công/lỗi sau một
 * thao tác), không nhận `tone`/`title`/children. Trang này cần một khối giải thích
 * đứng yên, nên tự định nghĩa, chỉ dùng các biến màu có sẵn trong tokens.css.
 */
function Banner({ tone = 'info', title, children }) {
  const color = tone === 'danger' ? 'var(--error)' : tone === 'success' ? 'var(--success)' : 'var(--warning)';
  return (
    <div
      style={{
        marginTop: 'var(--space-3)',
        padding: 'var(--space-3)',
        borderRadius: 'var(--radius-lg)',
        background: 'var(--surface-sunken)',
        border: `1px solid ${color}`,
      }}
    >
      {title && (
        <div className="overline" style={{ color, marginBottom: 'var(--space-2)' }}>{title}</div>
      )}
      <div className="text-sm">{children}</div>
    </div>
  );
}

/**
 * CÔNG CỤ DEMO 5 LỖI TƯƠNG TRANH — chỉ Admin.
 *
 * Trang này không phải nghiệp vụ. Nó tồn tại vì hai loại thao tác KHÔNG THỂ làm
 * bằng click chuột:
 *   1. Giữ một giao dịch mở vài giây (để người thứ hai kịp thao tác).
 *   2. Đọc cùng một dòng hai lần trong MỘT giao dịch.
 * Mỗi request HTTP là một giao dịch riêng, nên nếu không có trang này thì các lỗi
 * #2, #3a, #4, #5 không bao giờ lộ ra trong trình duyệt.
 *
 * Nguyên tắc: mọi thao tác GHI vẫn gọi endpoint quản trị THẬT
 * (POST /admin/concerts/{id}/categories, PUT /admin/promotions/{id}/status,
 *  POST /admin/promotions/{id}/discount-codes, PATCH /admin/event-seats/{id}/availability).
 * Trang này chỉ thêm đường ĐỌC/GIỮ mà trình duyệt không có.
 *
 * Toàn bộ module demo nằm trong 2 file: DemoConcurrency.jsx + DemoConcurrencyController.cs.
 */

const DEFAULTS = {
  concertId: '1',
  ticketCategoryId: '1',
  categoryName: 'VIP',
  promotionId1: '1',
  promotionId2: '2',
  codeValue: 'DEMO-SALE10',
  targetUserId: '3',
  eventSeatId: '1',
  holdSeconds: '10',
  priceA: '1000000',
  priceB: '1200000',
};

export default function DemoConcurrency() {
  const act = useAction();
  const [f, setF] = useState(DEFAULTS);
  const setField = (k) => (e) => setF((s) => ({ ...s, [k]: e.target.value }));
  const num = (v) => Number(String(v).trim());

  // Kết quả từng ca
  const [cat, setCat] = useState(null);          // #1
  const [audit, setAudit] = useState(null);      // #2
  const [holding, setHolding] = useState('');    // #2 trạng thái "đang giữ"
  const [promo, setPromo] = useState(null);      // #3a
  const [seatState, setSeatState] = useState(null); // #3b
  const [codes, setCodes] = useState(null);      // #4
  const [deadlock, setDeadlock] = useState(null); // #5

  // ── Hàm dùng chung ───────────────────────────────────────────────
  // "Bắn rồi quên": KHÔNG await, vì request này phải giữ giao dịch mở ở server
  // trong lúc người dùng thao tác ở panel khác.
  const fireAndHold = (url, body, label) => {
    setHolding(label);
    api.post(url, body).catch(() => {}).finally(() => setHolding(''));
  };

  // ── #1 LOST UPDATE: ghi bằng endpoint quản trị THẬT ──────────────
  const savePrice = (price, label) => act.run(
    () => api.post(`/admin/concerts/${num(f.concertId)}/categories`, {
      categoryName: f.categoryName.trim(),
      categoryDescription: null,
      basePrice: num(price),
      ticketCategoryId: num(f.ticketCategoryId),
      categoryStatus: 'Active',
    }),
    `${label} đã lưu ${num(price).toLocaleString('vi-VN')} ₫ — hệ thống báo THÀNH CÔNG`,
  );

  const readCategory = () => act.run(async () => {
    const res = await api.get('/admin/demo/ticket-category-state', {
      params: { ticketCategoryId: num(f.ticketCategoryId) },
    });
    setCat(res.data);
  });

  // ── #2 DIRTY READ ────────────────────────────────────────────────
  const readAudit = (uncommitted) => act.run(async () => {
    const res = await api.get('/admin/demo/audit-read', {
      params: { uncommitted, limit: 10 },
    });
    setAudit(res.data);
  });

  return (
    <>
      <PageHeader
        title="Demo 5 lỗi tương tranh"
        subtitle="Công cụ trình diễn — chỉ Admin. Mọi thao tác ghi đều gọi endpoint quản trị thật."
      />

      <Banner tone="warning" title="Đây là công cụ demo, không phải nghiệp vụ">
        Trang này chỉ mở hai đường mà trình duyệt không có: <b>giữ một giao dịch mở vài giây</b> và
        <b> đọc cùng một dòng hai lần trong một giao dịch</b>.
      </Banner>

      <Panel title="Tham số dùng chung" tone="inventory"
        subtitle="Script scripts/demo-prep-anomalies.ps1 in ra đúng các ID cần điền ở đây.">
        <div className="field-grid">
          <Field label="ConcertID"><input value={f.concertId} onChange={setField('concertId')} /></Field>
          <Field label="TicketCategoryID (hạng vé)"><input value={f.ticketCategoryId} onChange={setField('ticketCategoryId')} /></Field>
          <Field label="Tên hạng vé"><input value={f.categoryName} onChange={setField('categoryName')} /></Field>
          <Field label="PromotionID #1"><input value={f.promotionId1} onChange={setField('promotionId1')} /></Field>
          <Field label="PromotionID #2"><input value={f.promotionId2} onChange={setField('promotionId2')} /></Field>
          <Field label="Mã giảm giá (ca 4)"><input value={f.codeValue} onChange={setField('codeValue')} /></Field>
          <Field label="UserID mục tiêu (ca 2)"><input value={f.targetUserId} onChange={setField('targetUserId')} /></Field>
          <Field label="EventSeatID (ca 3b)"><input value={f.eventSeatId} onChange={setField('eventSeatId')} /></Field>
          <Field label="Số giây giữ giao dịch" hint="1–60. Càng dài càng dễ thao tác kịp.">
            <input value={f.holdSeconds} onChange={setField('holdSeconds')} />
          </Field>
        </div>
      </Panel>

      {/* ═══ #1 LOST UPDATE ═══════════════════════════════════════ */}
      <Panel title="1. Lost update — hai admin lưu hai giá cho cùng một hạng vé"
        tone="create"
        subtitle="Cả hai lần lưu đều báo thành công nhưng chỉ một giá trị tồn tại. Không có kiểm tra phiên bản (ETag) nên hệ thống không phát hiện được.">
        <div className="field-grid">
          <Field label="Giá của admin A"><input value={f.priceA} onChange={setField('priceA')} /></Field>
          <Field label="Giá của admin B"><input value={f.priceB} onChange={setField('priceB')} /></Field>
        </div>
        <div className="panel__actions">
          <Button type="button" onClick={() => savePrice(f.priceA, 'Admin A')} loading={act.loading}>
            Admin A lưu giá
          </Button>
          <Button type="button" variant="secondary" onClick={() => savePrice(f.priceB, 'Admin B')} loading={act.loading}>
            Admin B lưu giá
          </Button>
          <Button type="button" variant="secondary" onClick={readCategory} loading={act.loading}>
            Đọc lại hạng vé + đếm nhật ký
          </Button>
        </div>
        {cat && (
          <table className="table">
            <thead>
              <tr>
                <th>Hạng vé</th><th>Giá hiện tại</th><th>Trạng thái</th>
                <th>Số dòng nhật ký TICKET_CATEGORY_UPDATED</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>#{cat.ticketCategoryID} — {cat.categoryName}</td>
                <td className="tabular">{Number(cat.basePrice).toLocaleString('vi-VN')} ₫</td>
                <td>{cat.categoryStatus}</td>
                <td className="tabular">{cat.updatedAuditRows}</td>
              </tr>
            </tbody>
          </table>
        )}
        {cat && cat.updatedAuditRows >= 2 && (
          <Banner tone="danger" title="Lỗi đã lộ ra">
            Có <b>{cat.updatedAuditRows} dòng</b> nhật ký cho cùng một hạng vé, nhưng bảng chỉ giữ
            <b> một giá trị</b> ({Number(cat.basePrice).toLocaleString('vi-VN')} ₫) — thay đổi của admin
            lưu trước đã bị mất mà không có cảnh báo nào.
          </Banner>
        )}
      </Panel>

      {/* ═══ #2 DIRTY READ ════════════════════════════════════════ */}
      <Panel title="2. Dirty read — nhật ký kiểm toán"
        tone="danger"
        subtitle="Giữ một thay đổi trạng thái tài khoản ở trạng thái CHƯA commit, rồi đọc nhật ký ở hai mức cô lập khác nhau.">
        <div className="panel__actions">
          <Button type="button" variant="secondary"
            onClick={() => fireAndHold('/admin/demo/hold-user-status',
              { targetUserId: num(f.targetUserId), newStatus: 'Locked', seconds: num(f.holdSeconds) },
              `Đang giữ thay đổi CHƯA commit trong ${f.holdSeconds} giây…`)}>
            Giữ một thay đổi CHƯA commit ({f.holdSeconds}s)
          </Button>
          <Button type="button" onClick={() => readAudit(false)} loading={act.loading}>
            Đọc ở READ COMMITTED (mức hệ thống)
          </Button>
          <Button type="button" variant="secondary" onClick={() => readAudit(true)} loading={act.loading}>
            Đọc ở READ UNCOMMITTED
          </Button>
        </div>
        {holding && (
          <Banner tone="warning" title="Đang giữ giao dịch">
            {holding} Hãy bấm nút đọc ngay bây giờ. Lưu ý: nút READ COMMITTED sẽ <b>đứng chờ</b> cho tới khi
            giao dịch kia kết thúc — đó chính là lớp bảo vệ đang hoạt động.
          </Banner>
        )}
        {audit && (
          <>
            <p className="field-hint">
              Mức cô lập của phiên đọc: <b>{audit.isolationLevel}</b> — thấy <b>{audit.rowCount}</b> dòng.
            </p>
            {audit.isolationLevel === 'READ UNCOMMITTED' && audit.rowCount > 0 && (
              <Banner tone="danger" title="Lỗi đã lộ ra">
                Phiên đọc đã thấy <b>{audit.rowCount} dòng</b> trong đó có thay đổi <b>chưa hề được commit</b>.
                Nếu giao dịch kia rollback, đây là một sự kiện chưa từng tồn tại — mà bảng AuditRecord
                là bất biến (BR50) nên nó sẽ nằm lại vĩnh viễn.
              </Banner>
            )}
            {audit.isolationLevel === 'READ COMMITTED' && audit.rowCount === 0 && (
              <Banner tone="success" title="Lớp bảo vệ đang hoạt động">
                Ở mức hệ thống đang chạy (READ COMMITTED), phiên đọc <b>không thấy</b> dòng chưa commit:
                nó bị chặn cho tới khi giao dịch kia kết thúc. Đây là điều sẽ mất nếu dùng NOLOCK.
              </Banner>
            )}
            {audit.rowCount > 0 && (
              <table className="table">
                <thead>
                  <tr><th>AuditID</th><th>Thời điểm</th><th>EventType</th><th>Đối tượng</th><th>Actor</th></tr>
                </thead>
                <tbody>
                  {audit.rows.map((r) => (
                    <tr key={r.auditID}>
                      <td className="tabular">{r.auditID}</td>
                      <td>{r.eventTimestamp}</td>
                      <td>{r.eventType}</td>
                      <td>{r.entityType} #{r.entityID}</td>
                      <td className="tabular">{r.actorUserID}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </>
        )}
      </Panel>

      {/* ═══ #3a NON-REPEATABLE READ ══════════════════════════════ */}
      <Panel title="3a. Non-repeatable read — cùng một dòng, đọc hai lần trong MỘT giao dịch"
        tone="inventory"
        subtitle="Bấm nút đọc (giữ giao dịch mở), rồi bấm nút đổi trạng thái chương trình trong lúc đó. Hai lần đọc là hai giá trị khác nhau.">
        <div className="panel__actions">
          <Button type="button" loading={act.loading}
            onClick={() => act.run(async () => {
              const res = await api.post('/admin/demo/read-promotion-twice', {
                promotionId: num(f.promotionId1),
                holdSeconds: num(f.holdSeconds),
              });
              setPromo(res.data);
            })}>
            Bắt đầu: đọc 2 lần (giữ {f.holdSeconds}s)
          </Button>
          <Button type="button" variant="secondary" loading={act.loading}
            onClick={() => act.run(() => api.put(`/admin/promotions/${num(f.promotionId1)}/status`, { status: 'Disabled' }),
              `Đã TẮT khuyến mãi #${f.promotionId1} (thao tác admin thật)`)}>
            Đổi trạng thái #1 → Disabled
          </Button>
          <Button type="button" variant="secondary" loading={act.loading}
            onClick={() => act.run(() => api.put(`/admin/promotions/${num(f.promotionId1)}/status`, { status: 'Active' }),
              `Đã BẬT LẠI khuyến mãi #${f.promotionId1}`)}>
            Bật lại #1 → Active
          </Button>
        </div>
        {promo && (
          <>
            <table className="table">
              <thead><tr><th>Lần đọc</th><th>PromotionStatus</th></tr></thead>
              <tbody>
                <tr><td>Lần 1 (đầu giao dịch)</td><td><b>{promo.read1}</b></td></tr>
                <tr><td>Lần 2 (sau {promo.holdSeconds}s, vẫn trong giao dịch đó)</td><td><b>{promo.read2}</b></td></tr>
              </tbody>
            </table>
            {promo.changed && (
              <Banner tone="danger" title="Lỗi đã lộ ra">
                Cùng một dòng, cùng một giao dịch, đọc hai lần ra hai giá trị: <b>{promo.read1}</b> rồi
                <b> {promo.read2}</b>. READ COMMITTED không bảo vệ được điều này, và các guard của hệ thống
                (sp_UpdateDiscountCodeStatus, sp_UpdatePromotionStatus) đọc chính những dòng như vậy mà
                không khoá.
              </Banner>
            )}
          </>
        )}
      </Panel>

      {/* ═══ #3b DỮ LIỆU CŨ 15 GIÂY ═══════════════════════════════ */}
      <Panel title="3b. Dữ liệu cũ 15 giây — cache không bị xoá khi tồn kho đổi"
        tone="inventory"
        subtitle="Danh sách ghế đi qua cache (màn hình quản trị đang đọc) và danh sách đọc thẳng database. Khoá một ghế rồi nạp lại ngay để thấy chênh lệch.">
        <div className="panel__actions">
          <Button type="button" variant="secondary" loading={act.loading}
            onClick={() => act.run(async () => {
              const res = await api.get('/admin/demo/seat-state', { params: { concertId: num(f.concertId) } });
              setSeatState(res.data);
            })}>
            Nạp: danh sách qua cache vs DB
          </Button>
          <Button type="button" loading={act.loading}
            onClick={() => act.run(() => api.patch(`/admin/event-seats/${num(f.eventSeatId)}/availability`,
              { unavailable: true, reason: 'DEMO - khoa ghe de demo cache' }),
              `Đã KHOÁ ghế #${f.eventSeatId} (thao tác admin thật)`)}>
            Khoá ghế #{f.eventSeatId}
          </Button>
          <Button type="button" variant="secondary" loading={act.loading}
            onClick={() => act.run(() => api.patch(`/admin/event-seats/${num(f.eventSeatId)}/availability`,
              { unavailable: false, reason: null }),
              `Đã MỞ LẠI ghế #${f.eventSeatId}`)}>
            Mở lại ghế #{f.eventSeatId}
          </Button>
        </div>
        {seatState && (
          <>
            <p className="field-hint">
              Cache TTL: <b>{seatState.cacheTtlSeconds} giây</b>. Số ghế lệch trạng thái giữa hai nguồn:{' '}
              <b>{seatState.differenceCount}</b>.
            </p>
            {seatState.differenceCount > 0 && (
              <Banner tone="danger" title="Lỗi đã lộ ra">
                Danh sách đi qua cache <b>vẫn hiện trạng thái cũ</b> sau khi ghế đã bị khoá trong database.
                Cache 15 giây không bao giờ bị xoá khi tồn kho thay đổi (0 lệnh xoá cache trong toàn hệ).
              </Banner>
            )}
            <div className="scroll-x">
              <table className="table">
                <thead>
                  <tr><th>EventSeatID</th><th>Ghế</th><th>Hạng</th>
                    <th>Trạng thái qua CACHE</th><th>Trạng thái trong DB</th><th>Lệch?</th></tr>
                </thead>
                <tbody>
                  {seatState.raw.map((r) => {
                    const c = seatState.cached.find((x) => x.seatID === r.seatID);
                    const diff = !c || c.inventoryStatus !== r.inventoryStatus;
                    return (
                      <tr key={r.seatID}>
                        <td className="tabular">{r.seatID}</td>
                        <td>{r.seatNumber} · {r.sectionName}</td>
                        <td>{r.categoryName}</td>
                        <td>{c ? c.inventoryStatus : '(không có trong cache)'}</td>
                        <td>{r.inventoryStatus}</td>
                        <td style={{ color: diff ? 'var(--error)' : 'var(--text-secondary)' }}>
                          {diff ? 'LỆCH' : '—'}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </>
        )}
      </Panel>

      {/* ═══ #4 PHANTOM READ ══════════════════════════════════════ */}
      <Panel title="4. Phantom read — hai mã giảm giá trùng nhau"
        tone="create"
        subtitle="Giữ một mã ở trạng thái CHƯA commit, rồi tạo cùng mã đó ở chương trình khác. Guard của sp_CreateDiscountCode không khoá khoảng nên không thấy dòng vừa được chèn.">
        <div className="panel__actions">
          <Button type="button" variant="secondary"
            onClick={() => fireAndHold('/admin/demo/hold-discount-code',
              { promotionId: num(f.promotionId1), codeValue: f.codeValue.trim(), seconds: num(f.holdSeconds) },
              `Đang giữ mã "${f.codeValue}" CHƯA commit trong ${f.holdSeconds} giây…`)}>
            Giữ mã CHƯA commit ({f.holdSeconds}s)
          </Button>
          <Button type="button" loading={act.loading}
            onClick={() => act.run(
              () => api.post(`/admin/promotions/${num(f.promotionId2)}/discount-codes`, {
                codeValue: f.codeValue.trim(),
                validFromDatetime: null,
                validToDatetime: null,
                globalUsageLimit: null,
                perCustomerUsageLimit: null,
              }),
              `Đã tạo mã "${f.codeValue}" ở chương trình #${f.promotionId2} (thao tác admin thật)`)}>
            Tạo cùng mã ở chương trình #{f.promotionId2}
          </Button>
          <Button type="button" variant="secondary" loading={act.loading}
            onClick={() => act.run(async () => {
              const res = await api.get('/admin/demo/discount-codes', {
                params: { codeValue: f.codeValue.trim(), concertId: num(f.concertId), limit: 50 },
              });
              setCodes(res.data);
            })}>
            Liệt kê mã này
          </Button>
        </div>
        {holding && <Banner tone="warning" title="Đang giữ giao dịch">{holding}</Banner>}
        {codes && (
          <>
            <p className="field-hint">
              Mã <b>{f.codeValue}</b>: <b>{codes.rowCount}</b> dòng, trong đó <b>{codes.duplicateRows}</b> dòng
              vượt quá số mã khác nhau.
            </p>
            {codes.duplicateRows > 0 && (
              <Banner tone="danger" title="Lỗi đã lộ ra">
                Hai dòng cùng mã ở hai chương trình khác nhau của cùng một concert. Khách gõ mã này ở trang
                thanh toán sẽ ra 2 kết quả → lỗi 500. Dọn mã demo bằng:{' '}
                <code>scripts\demo-prep-anomalies.ps1 -Cleanup</code>
              </Banner>
            )}
            <table className="table">
              <thead>
                <tr><th>DiscountCodeID</th><th>Mã</th><th>Chương trình</th>
                  <th>Mã: trạng thái</th><th>Chương trình: trạng thái</th></tr>
              </thead>
              <tbody>
                {codes.rows.map((r) => (
                  <tr key={r.discountCodeID}>
                    <td className="tabular">{r.discountCodeID}</td>
                    <td><b>{r.codeValue}</b></td>
                    <td className="tabular">#{r.promotionID}</td>
                    <td>{r.codeStatus}</td>
                    <td>{r.promotionStatus}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}
      </Panel>

      {/* ═══ #5 DEADLOCK ══════════════════════════════════════════ */}
      <Panel title="5. Deadlock — SQL Server trả về lỗi 1205"
        tone="danger"
        subtitle="Hai giao dịch song song giữ khoá hai bảng theo thứ tự ngược nhau để SQL Server thật sự phát hiện deadlock.">
        <div className="panel__actions">
          <Button type="button" loading={act.loading}
            onClick={() => act.run(async () => {
              const res = await api.post('/admin/demo/deadlock');
              setDeadlock(res.data);
            })}>
            Kích hoạt deadlock (chờ tối đa ~15 giây)
          </Button>
        </div>
        {deadlock && (
          <>
            <p className="field-hint">
              Kết quả: <b>{deadlock.deadlocked ? 'CÓ deadlock (mã 1205)' : 'lần này chưa hình thành vòng khoá — bấm lại'}</b>.
              {' '}{deadlock.waitNote}
            </p>
            <table className="table">
              <thead><tr><th>Phiên</th><th>Bị chọn làm nạn nhân?</th><th>Lỗi SQL Server trả về</th></tr></thead>
              <tbody>
                {deadlock.sessions.map((s, i) => (
                  <tr key={i}>
                    <td>Phiên {i === 0 ? 'A (Promotion → Role)' : 'B (Role → Promotion)'}</td>
                    <td>{s.deadlocked ? 'CÓ' : 'không'}</td>
                    <td>{s.error || '(hoàn tất bình thường)'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            {deadlock.deadlocked && (
              <Banner tone="danger" title="Lỗi đã lộ ra">
                {deadlock.note} Đây là <b>dàn dựng</b>: khu quản trị hiện không có cặp stored procedure nào
                tự tạo vòng khoá. Cặp deadlock thật của hệ thống nằm ở luồng hoàn tiền
                (sp_ProcessRefund ⇄ sp_ConfirmPayment) và cần một Booking thật.
              </Banner>
            )}
          </>
        )}
      </Panel>
    </>
  );
}





