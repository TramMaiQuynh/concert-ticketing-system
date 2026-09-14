import { useState, useEffect, useCallback } from 'react';
import api from '../../api/client';
import { useVenues } from '../../lib/adminCatalog';
import { Field, Select, Check, Panel, Banner, IdPicker, useAction } from '../../components/form';
import { Badge, Textarea, Input, Button } from '../../components/ui';
import { ADMIN_STATUS_LABEL } from '../../domain/enums';
import { TEMPLATE_STATUS_TONE, VERSION_STATUS_TONE } from '../../domain/tone';

/**
 * VENUE TEMPLATE STUDIO (StagePass D.2/D.4) — chỉ Admin.
 *
 * Lớp dữ liệu THÊM MỚI, không thay thế trang "Sơ đồ địa điểm" (VenueMap.jsx):
 * Zone/Seat hiện có vẫn hoạt động nguyên vẹn cho các Venue không cần mức độ
 * chi tiết này. Trang này phục vụ mô hình nhiều tầng + khu dạng đa giác tự do
 * kiểu Ticketmaster — VenueTemplate → VenueTemplateVersion (có phiên bản,
 * Published là BẤT BIẾN) → TemplateFloor → TemplateObject/TemplateSection →
 * TemplateSeat (ghế tham chiếu Seat thật, không tạo hệ định danh song song).
 *
 * PHẠM VI ĐÃ CHỌN CÓ CHỦ ĐÍCH cho lượt đầu này: chỉnh hình học bằng Ô NHẬP SỐ
 * (x/y/width/height/rotation) + xem trước SVG trực tiếp — KHÔNG kéo-thả bằng
 * chuột như ZoneLayoutEditor. Vẫn là một trình soạn thảo dùng được thật (gõ
 * số, thấy ngay kết quả, gửi lên được validate đầy đủ ở server), chỉ khác
 * cách nhập liệu. Khu dạng đa giác (không phải chữ nhật) nhập qua ô JSON thô
 * ở chế độ "nâng cao" — xem quy ước GeometryJson v1 trong TemplateSection.sql.
 */
export default function VenueTemplates() {
  const venues = useVenues();
  const [venueId, setVenueId] = useState('');
  const venue = venues.raw.find((v) => String(v.venueID) === String(venueId));

  return (
    <>
      <Panel
        title="Chọn địa điểm"
        tone="inventory"
        subtitle="Mỗi địa điểm có thể có nhiều Mẫu sơ đồ (VenueTemplate) — ví dụ 'Nhà hát' và 'Sân khấu cuối' cho cùng một venue."
      >
        <IdPicker
          label="Địa điểm"
          items={venues.items}
          value={venueId}
          onChange={setVenueId}
          hint={venues.loading ? 'Đang tải danh mục…' : `${venues.items.length} địa điểm trong danh mục.`}
        />
      </Panel>

      {venue && <TemplatesPanel key={venue.venueID} venue={venue} />}
    </>
  );
}

/* ══ GHI CHÚ HÌNH HỌC (GeometryJson v1) ═══════════════════════════════════ */

const RECT_DEFAULT = { x: 0, y: 0, width: 100, height: 100, rotation: 0 };

function rectToGeometryJson(r) {
  return JSON.stringify({
    version: 1, shape: 'rect',
    x: Number(r.x), y: Number(r.y), width: Number(r.width), height: Number(r.height),
    rotation: Number(r.rotation || 0),
  });
}

/** Trả về {x,y,width,height,rotation} nếu là rect, null nếu là polygon hoặc không đọc được. */
function geometryJsonToRect(json) {
  try {
    const g = JSON.parse(json);
    if (g?.shape !== 'rect') return null;
    return { x: g.x, y: g.y, width: g.width, height: g.height, rotation: g.rotation ?? 0 };
  } catch {
    return null;
  }
}

/** Danh sách đỉnh (theo chu vi) để vẽ SVG preview — dùng chung cho rect và polygon. */
function geometryToPoints(json) {
  try {
    const g = JSON.parse(json);
    if (g?.shape === 'rect') {
      const cx = Number(g.x) + Number(g.width) / 2, cy = Number(g.y) + Number(g.height) / 2;
      const hw = Number(g.width) / 2, hh = Number(g.height) / 2;
      const rad = (Number(g.rotation) || 0) * Math.PI / 180;
      const cos = Math.cos(rad), sin = Math.sin(rad);
      const local = [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]];
      return local.map(([lx, ly]) => [cx + lx * cos - ly * sin, cy + lx * sin + ly * cos]);
    }
    if (g?.shape === 'polygon' && Array.isArray(g.points)) return g.points;
  } catch { /* ignored — form đang gõ dở, xem trước bỏ qua đến khi hợp lệ */ }
  return null;
}

function pointsToSvgPath(points) {
  if (!points || points.length === 0) return '';
  return `M ${points.map((p) => `${p[0]},${p[1]}`).join(' L ')} Z`;
}

/* ══ Mẫu sơ đồ (VenueTemplate) ═════════════════════════════════════════════ */

function TemplatesPanel({ venue }) {
  const [templates, setTemplates] = useState([]);
  const [loading, setLoading] = useState(false);
  const [templateId, setTemplateId] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get(`/admin/venues/${venue.venueID}/templates`, { params: { includeArchived: true } });
      setTemplates(Array.isArray(res.data) ? res.data : []);
    } finally {
      setLoading(false);
    }
  }, [venue.venueID]);

  useEffect(() => { load(); }, [load]);

  const template = templates.find((t) => String(t.venueTemplateID) === String(templateId));

  return (
    <>
      <Panel
        title="Mẫu sơ đồ (VenueTemplate)"
        tone="create"
        subtitle="Identity ổn định cho một cách bố trí. Bản thân template không chứa hình học — hình học nằm ở các phiên bản (version) bên dưới."
      >
        <CreateTemplateForm venue={venue} onDone={load} />

        <div className="stack gap-2" style={{ marginTop: 'var(--space-5)' }}>
          {loading ? (
            <p className="text-sm text-muted">Đang tải…</p>
          ) : templates.length === 0 ? (
            <p className="text-sm text-muted">Địa điểm này chưa có Mẫu sơ đồ nào.</p>
          ) : (
            <table className="data">
              <thead><tr><th>Tên</th><th>Trạng thái</th><th /></tr></thead>
              <tbody>
                {templates.map((t) => (
                  <tr key={t.venueTemplateID} className={String(t.venueTemplateID) === String(templateId) ? 'is-selected' : ''}>
                    <td>
                      <button type="button" className="btn btn--link" onClick={() => setTemplateId(String(t.venueTemplateID))}>
                        {t.templateName}
                      </button>
                    </td>
                    <td><Badge tone={TEMPLATE_STATUS_TONE[t.templateStatus] ?? 'neutral'}>{ADMIN_STATUS_LABEL[t.templateStatus] ?? t.templateStatus}</Badge></td>
                    <td><RenameArchiveTemplate template={t} onDone={load} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </Panel>

      {template && <VersionsPanel key={template.venueTemplateID} template={template} />}
    </>
  );
}

function CreateTemplateForm({ venue, onDone }) {
  const act = useAction();
  const [name, setName] = useState('');

  return (
    <form
      className="row gap-2 wrap"
      onSubmit={(e) => {
        e.preventDefault();
        act.run(async () => {
          await api.post(`/admin/venues/${venue.venueID}/templates`, { templateName: name });
          setName('');
          await onDone();
        }, 'Đã tạo Mẫu sơ đồ.');
      }}
    >
      <Field label="Tên mẫu mới" hint="Ví dụ: 'Nhà hát', 'Sân khấu cuối'.">
        {(a) => <Input {...a} value={name} onChange={(e) => setName(e.target.value)} placeholder="Nhà hát" required style={{ width: 260 }} />}
      </Field>
      <Button type="submit" variant="primary" loading={act.busy} style={{ alignSelf: 'flex-end' }}>Tạo mẫu</Button>
      <Banner state={act.state} />
    </form>
  );
}

function RenameArchiveTemplate({ template, onDone }) {
  const act = useAction();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(template.templateName);

  if (!editing) {
    const isActive = template.templateStatus === 'Active';
    return (
      <div className="row gap-2">
        <Button size="sm" onClick={() => setEditing(true)}>Đổi tên</Button>
        <Button
          size="sm"
          variant={isActive ? 'secondary' : 'primary'}
          loading={act.busy}
          onClick={() => act.run(async () => {
            await api.put(`/admin/templates/${template.venueTemplateID}`, { templateStatus: isActive ? 'Archived' : 'Active' });
            await onDone();
          }, isActive ? 'Đã lưu trữ.' : 'Đã kích hoạt lại.')}
        >
          {isActive ? 'Lưu trữ' : 'Kích hoạt lại'}
        </Button>
      </div>
    );
  }

  return (
    <form
      className="row gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        act.run(async () => {
          await api.put(`/admin/templates/${template.venueTemplateID}`, { templateName: name });
          setEditing(false);
          await onDone();
        }, 'Đã đổi tên.');
      }}
    >
      <Input value={name} onChange={(e) => setName(e.target.value)} autoFocus style={{ width: 180 }} />
      <Button type="submit" size="sm" variant="primary" loading={act.busy}>Lưu</Button>
      <Button size="sm" onClick={() => { setEditing(false); setName(template.templateName); }}>Huỷ</Button>
    </form>
  );
}

/* ══ Phiên bản (VenueTemplateVersion) ═════════════════════════════════════ */

function VersionsPanel({ template }) {
  const [versions, setVersions] = useState([]);
  const [loading, setLoading] = useState(false);
  const [versionId, setVersionId] = useState('');
  const act = useAction();
  const [copyFrom, setCopyFrom] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get(`/admin/templates/${template.venueTemplateID}/versions`);
      setVersions(Array.isArray(res.data) ? res.data : []);
    } finally {
      setLoading(false);
    }
  }, [template.venueTemplateID]);

  useEffect(() => { load(); }, [load]);

  const hasDraft = versions.some((v) => v.versionStatus === 'Draft');
  const version = versions.find((v) => String(v.venueTemplateVersionID) === String(versionId));

  return (
    <>
      <Panel
        title={`Phiên bản — ${template.templateName}`}
        subtitle="Draft sửa được tự do. Published là BẤT BIẾN — muốn sửa thì tạo version kế tiếp (có thể sao chép từ version cũ)."
      >
        <form
          className="row gap-2 wrap"
          onSubmit={(e) => {
            e.preventDefault();
            act.run(async () => {
              await api.post(`/admin/templates/${template.venueTemplateID}/versions`, {
                copyFromVersionID: copyFrom ? Number(copyFrom) : null,
              });
              setCopyFrom('');
              await load();
            }, 'Đã tạo Draft mới.');
          }}
        >
          <Field label="Sao chép từ version (tuỳ chọn)" hint="Để trống để bắt đầu từ một mặt bằng rỗng.">
            <Select
              value={copyFrom}
              onChange={setCopyFrom}
              options={versions.map((v) => String(v.venueTemplateVersionID))}
              labels={Object.fromEntries(versions.map((v) => [String(v.venueTemplateVersionID), `v${v.versionNumber} (${ADMIN_STATUS_LABEL[v.versionStatus] ?? v.versionStatus})`]))}
              allowEmpty emptyLabel="— không sao chép —"
            />
          </Field>
          <Button type="submit" variant="primary" loading={act.busy} disabled={hasDraft} style={{ alignSelf: 'flex-end' }}>
            {hasDraft ? 'Đã có Draft mở' : 'Tạo Draft mới'}
          </Button>
          <Banner state={act.state} />
        </form>

        <div className="stack gap-2" style={{ marginTop: 'var(--space-5)' }}>
          {loading ? (
            <p className="text-sm text-muted">Đang tải…</p>
          ) : versions.length === 0 ? (
            <p className="text-sm text-muted">Mẫu này chưa có version nào.</p>
          ) : (
            <table className="data">
              <thead><tr><th>Version</th><th>Trạng thái</th><th>Tạo lúc</th><th>Công bố lúc</th></tr></thead>
              <tbody>
                {versions.map((v) => (
                  <tr key={v.venueTemplateVersionID} className={String(v.venueTemplateVersionID) === String(versionId) ? 'is-selected' : ''}>
                    <td>
                      <button type="button" className="btn btn--link" onClick={() => setVersionId(String(v.venueTemplateVersionID))}>
                        v{v.versionNumber}
                      </button>
                    </td>
                    <td><Badge tone={VERSION_STATUS_TONE[v.versionStatus] ?? 'neutral'}>{ADMIN_STATUS_LABEL[v.versionStatus] ?? v.versionStatus}</Badge></td>
                    <td className="text-sm text-muted">{new Date(v.createdTimestamp).toLocaleString('vi-VN')}</td>
                    <td className="text-sm text-muted">{v.publishedTimestamp ? new Date(v.publishedTimestamp).toLocaleString('vi-VN') : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </Panel>

      {version && version.versionStatus === 'Draft' && (
        <StudioPanel key={version.venueTemplateVersionID} version={version} onVersionListChanged={load} />
      )}
      {version && version.versionStatus !== 'Draft' && (
        <ReadOnlyVersionPanel key={version.venueTemplateVersionID} version={version} />
      )}
    </>
  );
}

/* ══ Studio — chỉnh Draft ═══════════════════════════════════════════════════ */

function StudioPanel({ version, onVersionListChanged }) {
  const [detail, setDetail] = useState(null);
  const [loading, setLoading] = useState(false);
  const [floorId, setFloorId] = useState('');
  const act = useAction();

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get(`/admin/template-versions/${version.venueTemplateVersionID}`);
      setDetail(res.data);
    } finally {
      setLoading(false);
    }
  }, [version.venueTemplateVersionID]);

  useEffect(() => { load(); }, [load]);

  const floors = detail?.floors ?? [];
  const floor = floors.find((f) => String(f.templateFloorID) === String(floorId)) ?? floors[0];
  const seatCount = floors.reduce((n, f) => n + f.sections.reduce((m, s) => m + s.seats.length, 0), 0);

  return (
    <Panel
      title={`Studio — v${version.versionNumber} (Draft)`}
      tone="create"
      subtitle="Dựng tầng, khu, vật thể tham chiếu và ghế. Chỉ Section/Object dạng hình lồi mới lưu được — hệ thống chỉ hỗ trợ va chạm chính xác cho hình lồi."
      aside={
        <div className="row gap-2">
          <Button
            variant="danger-quiet"
            loading={act.busy}
            onClick={() => act.run(async () => {
              if (!window.confirm('Huỷ toàn bộ Draft này? Không thể hoàn tác.')) return;
              await api.delete(`/admin/template-versions/${version.venueTemplateVersionID}`);
              await onVersionListChanged();
            })}
          >
            Huỷ Draft
          </Button>
          <Button
            variant="primary"
            loading={act.busy}
            disabled={seatCount === 0}
            onClick={() => act.run(async () => {
              await api.post(`/admin/template-versions/${version.venueTemplateVersionID}/publish`);
              await onVersionListChanged();
            }, 'Đã công bố. Version này giờ là bất biến.')}
          >
            Công bố (Publish)
          </Button>
        </div>
      }
    >
      <Banner state={act.state} />
      {loading && !detail ? <p className="text-sm text-muted">Đang tải…</p> : (
        <>
          <CreateFloorForm version={version} existingOrders={floors.map((f) => f.floorOrder)} onDone={load} />

          {floors.length > 0 && (
            <div className="row gap-2 wrap" style={{ margin: 'var(--space-4) 0' }}>
              {floors.map((f) => (
                <button
                  key={f.templateFloorID}
                  type="button"
                  className={`btn btn--sm ${String(f.templateFloorID) === String(floor?.templateFloorID) ? 'btn--primary' : 'btn--secondary'}`}
                  onClick={() => setFloorId(String(f.templateFloorID))}
                >
                  {f.floorName || f.floorKey}
                </button>
              ))}
            </div>
          )}

          {floor && (
            <FloorEditor
              key={floor.templateFloorID}
              version={version}
              floor={floor}
              onDone={load}
            />
          )}

          <p className="text-sm text-muted" style={{ marginTop: 'var(--space-4)' }}>
            Tổng {floors.length} tầng, {seatCount} ghế đã gán.
            {seatCount === 0 && ' Cần ít nhất một ghế mới công bố được.'}
          </p>
        </>
      )}
    </Panel>
  );
}

function CreateFloorForm({ version, existingOrders, onDone }) {
  const act = useAction();
  const [f, setF] = useState({ floorKey: '', floorName: '', floorOrder: (existingOrders.length ? Math.max(...existingOrders) + 1 : 1), canvasWidth: 1000, canvasHeight: 800 });
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));

  return (
    <form
      className="row gap-2 wrap"
      onSubmit={(e) => {
        e.preventDefault();
        act.run(async () => {
          await api.post(`/admin/template-versions/${version.venueTemplateVersionID}/floors`, {
            floorKey: f.floorKey, floorName: f.floorName || null,
            floorOrder: Number(f.floorOrder), canvasWidth: Number(f.canvasWidth), canvasHeight: Number(f.canvasHeight),
          });
          setF({ floorKey: '', floorName: '', floorOrder: Number(f.floorOrder) + 1, canvasWidth: 1000, canvasHeight: 800 });
          await onDone();
        }, 'Đã thêm tầng.');
      }}
    >
      <Field label="Mã tầng (FloorKey)" hint="vd. ground, balcony"><Input value={f.floorKey} onChange={(e) => set('floorKey')(e.target.value)} required style={{ width: 140 }} /></Field>
      <Field label="Tên tầng"><Input value={f.floorName} onChange={(e) => set('floorName')(e.target.value)} placeholder="Tầng trệt" style={{ width: 160 }} /></Field>
      <Field label="Thứ tự"><Input type="number" min="1" value={f.floorOrder} onChange={(e) => set('floorOrder')(e.target.value)} style={{ width: 90 }} /></Field>
      <Field label="Rộng"><Input type="number" min="1" value={f.canvasWidth} onChange={(e) => set('canvasWidth')(e.target.value)} style={{ width: 100 }} /></Field>
      <Field label="Cao"><Input type="number" min="1" value={f.canvasHeight} onChange={(e) => set('canvasHeight')(e.target.value)} style={{ width: 100 }} /></Field>
      <Button type="submit" variant="primary" loading={act.busy} style={{ alignSelf: 'flex-end' }}>Thêm tầng</Button>
      <Banner state={act.state} />
    </form>
  );
}

function FloorEditor({ version, floor, onDone }) {
  const act = useAction();
  const [f, setF] = useState({ floorKey: floor.floorKey, floorName: floor.floorName ?? '', floorOrder: floor.floorOrder, canvasWidth: floor.canvasWidth, canvasHeight: floor.canvasHeight });
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));

  return (
    <div className="stagepass-floor">
      <form
        className="row gap-2 wrap"
        onSubmit={(e) => {
          e.preventDefault();
          act.run(async () => {
            await api.put(`/admin/template-versions/${version.venueTemplateVersionID}/floors/${floor.templateFloorID}`, {
              floorKey: f.floorKey, floorName: f.floorName || null,
              floorOrder: Number(f.floorOrder), canvasWidth: Number(f.canvasWidth), canvasHeight: Number(f.canvasHeight),
            });
            await onDone();
          }, 'Đã lưu tầng.');
        }}
      >
        <Field label="Mã tầng"><Input value={f.floorKey} onChange={(e) => set('floorKey')(e.target.value)} required style={{ width: 140 }} /></Field>
        <Field label="Tên tầng"><Input value={f.floorName} onChange={(e) => set('floorName')(e.target.value)} style={{ width: 160 }} /></Field>
        <Field label="Thứ tự"><Input type="number" min="1" value={f.floorOrder} onChange={(e) => set('floorOrder')(e.target.value)} style={{ width: 90 }} /></Field>
        <Field label="Rộng"><Input type="number" min="1" value={f.canvasWidth} onChange={(e) => set('canvasWidth')(e.target.value)} style={{ width: 100 }} /></Field>
        <Field label="Cao"><Input type="number" min="1" value={f.canvasHeight} onChange={(e) => set('canvasHeight')(e.target.value)} style={{ width: 100 }} /></Field>
        <Button type="submit" variant="primary" size="sm" loading={act.busy}>Lưu tầng</Button>
        <Button
          type="button" size="sm" variant="danger-quiet" loading={act.busy}
          onClick={() => act.run(async () => {
            if (!window.confirm(`Xoá tầng "${floor.floorName || floor.floorKey}" và toàn bộ vật thể/khu/ghế bên trong?`)) return;
            await api.delete(`/admin/template-floors/${floor.templateFloorID}`);
            await onDone();
          })}
        >
          Xoá tầng
        </Button>
        <Banner state={act.state} />
      </form>

      <FloorCanvasPreview floor={floor} />

      <div className="grid-2" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 'var(--space-4)', alignItems: 'start' }}>
        <ObjectsEditor floor={floor} onDone={onDone} />
        <SectionsEditor floor={floor} onDone={onDone} />
      </div>
    </div>
  );
}

/** Xem trước TOÀN BỘ tầng (Object + Section) — chỉ để định hướng, không tương tác. */
function FloorCanvasPreview({ floor }) {
  return (
    <div className="seatmap-frame" style={{ maxWidth: 520, margin: 'var(--space-3) 0' }}>
      <svg viewBox={`0 0 ${floor.canvasWidth} ${floor.canvasHeight}`} preserveAspectRatio="xMidYMid meet"
           role="img" aria-label={`Xem trước tầng ${floor.floorName || floor.floorKey}`}
           style={{ width: '100%', height: 'auto', display: 'block' }}>
        <rect x={0.5} y={0.5} width={floor.canvasWidth - 1} height={floor.canvasHeight - 1}
              fill="none" stroke="var(--border-subtle)" strokeWidth={2} strokeDasharray="10 8" />
        {floor.objects.map((o) => {
          const pts = geometryToPoints(o.geometryJson);
          if (!pts) return null;
          return (
            <g key={o.templateObjectID}>
              <path d={pointsToSvgPath(pts)} fill={o.objectType === 'Stage' ? 'var(--surface-inverse)' : 'var(--surface-sunken)'} stroke="var(--border-strong)" strokeWidth={1} />
              <text x={pts.reduce((s, p) => s + p[0], 0) / pts.length} y={pts.reduce((s, p) => s + p[1], 0) / pts.length}
                    textAnchor="middle" dominantBaseline="central" fill={o.objectType === 'Stage' ? 'var(--text-inverse)' : 'var(--text-secondary)'} style={{ fontSize: 12 }}>
                {o.label || o.objectType}
              </text>
            </g>
          );
        })}
        {floor.sections.map((s) => {
          const pts = geometryToPoints(s.geometryJson);
          if (!pts) return null;
          const cx = pts.reduce((sum, p) => sum + p[0], 0) / pts.length;
          const cy = pts.reduce((sum, p) => sum + p[1], 0) / pts.length;
          return (
            <g key={s.templateSectionID}>
              <path d={pointsToSvgPath(pts)} fill="var(--accent-soft, rgba(99,102,241,0.15))" stroke="var(--accent, #6366f1)" strokeWidth={1.5} />
              <text x={cx} y={cy} textAnchor="middle" dominantBaseline="central" fill="var(--text)" style={{ fontSize: 13, fontWeight: 600 }}>
                {s.sectionName || s.sectionKey} ({s.seats.length})
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}

/* ══ Vật thể (TemplateObject) ═══════════════════════════════════════════════ */

const OBJECT_TYPES = ['Stage', 'Aisle', 'Wall', 'Entrance', 'Restroom', 'Bar', 'Text', 'Icon'];
const OBJECT_TYPE_LABEL = { Stage: 'Sân khấu', Aisle: 'Lối đi', Wall: 'Tường', Entrance: 'Cửa vào', Restroom: 'Nhà vệ sinh', Bar: 'Quầy bar', Text: 'Nhãn chữ', Icon: 'Biểu tượng' };

function ObjectsEditor({ floor, onDone }) {
  const [editingId, setEditingId] = useState(null);
  return (
    <Panel title="Vật thể (sân khấu, lối đi…)" subtitle="Không bán được — chỉ tham chiếu/trang trí.">
      <div className="stack gap-2">
        {floor.objects.map((o) => (
          <div key={o.templateObjectID} className="stagepass-item">
            {editingId === o.templateObjectID ? (
              <ObjectForm floor={floor} existing={o} onDone={() => { setEditingId(null); onDone(); }} onCancel={() => setEditingId(null)} />
            ) : (
              <div className="row gap-2" style={{ justifyContent: 'space-between' }}>
                <span>{OBJECT_TYPE_LABEL[o.objectType] ?? o.objectType}{o.label ? ` — ${o.label}` : ''}</span>
                <span className="row gap-1">
                  <Button size="sm" onClick={() => setEditingId(o.templateObjectID)}>Sửa</Button>
                  <DeleteButton onDelete={async () => { await api.delete(`/admin/template-objects/${o.templateObjectID}`); await onDone(); }} />
                </span>
              </div>
            )}
          </div>
        ))}
        {editingId === 'new' ? (
          <ObjectForm floor={floor} onDone={() => { setEditingId(null); onDone(); }} onCancel={() => setEditingId(null)} />
        ) : (
          <Button size="sm" onClick={() => setEditingId('new')}>+ Thêm vật thể</Button>
        )}
      </div>
    </Panel>
  );
}

function ObjectForm({ floor, existing, onDone, onCancel }) {
  const act = useAction();
  const isEdit = !!existing;
  const initialRect = existing ? (geometryJsonToRect(existing.geometryJson) ?? RECT_DEFAULT) : RECT_DEFAULT;
  const [objectType, setObjectType] = useState(existing?.objectType ?? 'Stage');
  const [label, setLabel] = useState(existing?.label ?? '');
  const [advanced, setAdvanced] = useState(existing ? geometryJsonToRect(existing.geometryJson) === null : false);
  const [rect, setRect] = useState(initialRect);
  const [rawJson, setRawJson] = useState(existing?.geometryJson ?? rectToGeometryJson(RECT_DEFAULT));

  const geometryJson = advanced ? rawJson : rectToGeometryJson(rect);
  const previewPoints = geometryToPoints(geometryJson);

  return (
    <form
      className="stack gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        act.run(async () => {
          const body = { objectType, label: label || null, geometryJson, zIndex: 0 };
          if (isEdit) await api.put(`/admin/template-floors/${floor.templateFloorID}/objects/${existing.templateObjectID}`, body);
          else await api.post(`/admin/template-floors/${floor.templateFloorID}/objects`, body);
          onDone();
        }, isEdit ? 'Đã lưu vật thể.' : 'Đã thêm vật thể.');
      }}
    >
      <div className="row gap-2 wrap">
        <Field label="Loại"><Select value={objectType} onChange={setObjectType} options={OBJECT_TYPES} labels={OBJECT_TYPE_LABEL} /></Field>
        <Field label="Nhãn (tuỳ chọn)"><Input value={label} onChange={(e) => setLabel(e.target.value)} style={{ width: 160 }} /></Field>
        <Check label="Nhập JSON thô (đa giác)" checked={advanced} onChange={setAdvanced} />
      </div>
      {advanced ? (
        <Field label="GeometryJson" hint='vd. {"version":1,"shape":"polygon","points":[[0,0],[100,0],[100,100]]}'>
          <Textarea value={rawJson} onChange={(e) => setRawJson(e.target.value)} rows={3} style={{ fontFamily: 'monospace', fontSize: 12 }} />
        </Field>
      ) : (
        <RectFields rect={rect} onChange={setRect} />
      )}
      <MiniPreview canvasWidth={floor.canvasWidth} canvasHeight={floor.canvasHeight} points={previewPoints} tone="object" />
      <div className="row gap-2">
        <Button type="submit" variant="primary" size="sm" loading={act.busy}>{isEdit ? 'Lưu' : 'Thêm'}</Button>
        <Button type="button" size="sm" onClick={onCancel}>Huỷ</Button>
      </div>
      <Banner state={act.state} />
    </form>
  );
}

/* ══ Khu ghế (TemplateSection) + Ghế (TemplateSeat) ═══════════════════════ */

function SectionsEditor({ floor, onDone }) {
  const [editingId, setEditingId] = useState(null);
  return (
    <Panel title="Khu ghế (Section)" subtitle="Không được chồng Sân khấu hoặc Section khác cùng tầng — máy chủ kiểm tra va chạm thật (SAT).">
      <div className="stack gap-2">
        {floor.sections.map((s) => (
          <div key={s.templateSectionID} className="stagepass-item">
            {editingId === s.templateSectionID ? (
              <SectionForm floor={floor} existing={s} onDone={() => { setEditingId(null); onDone(); }} onCancel={() => setEditingId(null)} />
            ) : (
              <>
                <div className="row gap-2" style={{ justifyContent: 'space-between' }}>
                  <span>{s.sectionName || s.sectionKey} — {s.seats.length} ghế</span>
                  <span className="row gap-1">
                    <Button size="sm" onClick={() => setEditingId(s.templateSectionID)}>Sửa</Button>
                    <DeleteButton onDelete={async () => { await api.delete(`/admin/template-sections/${s.templateSectionID}`); await onDone(); }} />
                  </span>
                </div>
                <SeatsEditor section={s} onDone={onDone} />
              </>
            )}
          </div>
        ))}
        {editingId === 'new' ? (
          <SectionForm floor={floor} onDone={() => { setEditingId(null); onDone(); }} onCancel={() => setEditingId(null)} />
        ) : (
          <Button size="sm" onClick={() => setEditingId('new')}>+ Thêm khu</Button>
        )}
      </div>
    </Panel>
  );
}

function SectionForm({ floor, existing, onDone, onCancel }) {
  const act = useAction();
  const isEdit = !!existing;
  const initialRect = existing ? (geometryJsonToRect(existing.geometryJson) ?? RECT_DEFAULT) : RECT_DEFAULT;
  const [sectionKey, setSectionKey] = useState(existing?.sectionKey ?? '');
  const [sectionName, setSectionName] = useState(existing?.sectionName ?? '');
  const [advanced, setAdvanced] = useState(existing ? geometryJsonToRect(existing.geometryJson) === null : false);
  const [rect, setRect] = useState(initialRect);
  const [rawJson, setRawJson] = useState(existing?.geometryJson ?? rectToGeometryJson(RECT_DEFAULT));

  const geometryJson = advanced ? rawJson : rectToGeometryJson(rect);
  const previewPoints = geometryToPoints(geometryJson);

  return (
    <form
      className="stack gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        act.run(async () => {
          const body = { sectionKey, sectionName: sectionName || null, geometryJson };
          if (isEdit) await api.put(`/admin/template-floors/${floor.templateFloorID}/sections/${existing.templateSectionID}`, body);
          else await api.post(`/admin/template-floors/${floor.templateFloorID}/sections`, body);
          onDone();
        }, isEdit ? 'Đã lưu khu.' : 'Đã thêm khu.');
      }}
    >
      <div className="row gap-2 wrap">
        <Field label="Mã khu (SectionKey)"><Input value={sectionKey} onChange={(e) => setSectionKey(e.target.value)} required style={{ width: 140 }} /></Field>
        <Field label="Tên khu"><Input value={sectionName} onChange={(e) => setSectionName(e.target.value)} placeholder="Khu VIP" style={{ width: 160 }} /></Field>
        <Check label="Nhập JSON thô (đa giác)" checked={advanced} onChange={setAdvanced} />
      </div>
      {advanced ? (
        <Field label="GeometryJson" hint="Đa giác phải LỒI — hệ thống từ chối hình lõm để đảm bảo va chạm chính xác.">
          <Textarea value={rawJson} onChange={(e) => setRawJson(e.target.value)} rows={3} style={{ fontFamily: 'monospace', fontSize: 12 }} />
        </Field>
      ) : (
        <RectFields rect={rect} onChange={setRect} />
      )}
      <MiniPreview canvasWidth={floor.canvasWidth} canvasHeight={floor.canvasHeight} points={previewPoints} tone="section" others={floor.sections.filter((s) => s.templateSectionID !== existing?.templateSectionID)} objects={floor.objects} />
      <div className="row gap-2">
        <Button type="submit" variant="primary" size="sm" loading={act.busy}>{isEdit ? 'Lưu' : 'Thêm'}</Button>
        <Button type="button" size="sm" onClick={onCancel}>Huỷ</Button>
      </div>
      <Banner state={act.state} />
    </form>
  );
}

function SeatsEditor({ section, onDone }) {
  const [adding, setAdding] = useState(false);
  return (
    <div className="stack gap-1" style={{ marginTop: 'var(--space-2)', marginLeft: 'var(--space-4)' }}>
      {section.seats.map((seat) => (
        <div key={seat.templateSeatID} className="row gap-2 text-sm" style={{ justifyContent: 'space-between' }}>
          <span>
            {seat.seatKey} — hàng {seat.rowLabel ?? '—'} số {seat.seatNumber ?? '—'} (SeatID #{seat.seatID})
            {seat.isAccessible ? ' · ♿' : ''}
          </span>
          <DeleteButton onDelete={async () => { await api.delete(`/admin/template-seats/${seat.templateSeatID}`); await onDone(); }} />
        </div>
      ))}
      {adding ? (
        <SeatForm section={section} onDone={() => { setAdding(false); onDone(); }} onCancel={() => setAdding(false)} />
      ) : (
        <Button size="sm" onClick={() => setAdding(true)}>+ Thêm ghế</Button>
      )}
    </div>
  );
}

function SeatForm({ section, onDone, onCancel }) {
  const act = useAction();
  const [seats, setSeats] = useState([]);
  const [seatId, setSeatId] = useState('');
  const [seatKey, setSeatKey] = useState('');
  const [rowLabel, setRowLabel] = useState('');
  const [seatNumber, setSeatNumber] = useState('');
  const [isAccessible, setIsAccessible] = useState(false);

  useEffect(() => {
    api.get('/admin/seats', { params: { limit: 200 } }).then((res) => setSeats(Array.isArray(res.data) ? res.data : []));
  }, []);

  const items = seats.map((s) => ({ id: s.seatID, name: `${s.seatCode} · ${s.venueName}/${s.zoneName ?? '—'}` }));

  return (
    <form
      className="row gap-2 wrap"
      onSubmit={(e) => {
        e.preventDefault();
        act.run(async () => {
          await api.post(`/admin/template-sections/${section.templateSectionID}/seats`, {
            seatID: Number(seatId), seatKey, rowLabel: rowLabel || null, seatNumber: seatNumber ? Number(seatNumber) : null, isAccessible,
          });
          onDone();
        }, 'Đã thêm ghế.');
      }}
    >
      <IdPicker label="Seat" items={items} value={seatId} onChange={setSeatId} />
      <Field label="SeatKey"><Input value={seatKey} onChange={(e) => setSeatKey(e.target.value)} required style={{ width: 100 }} /></Field>
      <Field label="Hàng"><Input value={rowLabel} onChange={(e) => setRowLabel(e.target.value)} style={{ width: 70 }} /></Field>
      <Field label="Số"><Input type="number" value={seatNumber} onChange={(e) => setSeatNumber(e.target.value)} style={{ width: 70 }} /></Field>
      <Check label="Accessible" checked={isAccessible} onChange={setIsAccessible} />
      <Button type="submit" variant="primary" size="sm" loading={act.busy} style={{ alignSelf: 'flex-end' }}>Thêm</Button>
      <Button type="button" size="sm" onClick={onCancel} style={{ alignSelf: 'flex-end' }}>Huỷ</Button>
      <Banner state={act.state} />
    </form>
  );
}

/* ══ Thành phần dùng chung ══════════════════════════════════════════════════ */

function RectFields({ rect, onChange }) {
  const set = (k) => (v) => onChange({ ...rect, [k]: v });
  return (
    <div className="row gap-2 wrap">
      <Field label="X"><Input type="number" value={rect.x} onChange={(e) => set('x')(e.target.value)} style={{ width: 90 }} /></Field>
      <Field label="Y"><Input type="number" value={rect.y} onChange={(e) => set('y')(e.target.value)} style={{ width: 90 }} /></Field>
      <Field label="Rộng"><Input type="number" min="1" value={rect.width} onChange={(e) => set('width')(e.target.value)} style={{ width: 90 }} /></Field>
      <Field label="Cao"><Input type="number" min="1" value={rect.height} onChange={(e) => set('height')(e.target.value)} style={{ width: 90 }} /></Field>
      <Field label="Xoay (độ)"><Input type="number" value={rect.rotation} onChange={(e) => set('rotation')(e.target.value)} style={{ width: 90 }} /></Field>
    </div>
  );
}

/** Xem trước một hình đơn lẻ (đang chỉnh) trong bối cảnh canvas của tầng, cùng các Section/Object khác để dễ căn vị trí bằng mắt. */
function MiniPreview({ canvasWidth, canvasHeight, points, tone, others = [], objects = [] }) {
  return (
    <div className="seatmap-frame" style={{ maxWidth: 420 }}>
      <svg viewBox={`0 0 ${canvasWidth} ${canvasHeight}`} preserveAspectRatio="xMidYMid meet" style={{ width: '100%', height: 'auto', display: 'block' }}>
        <rect x={0.5} y={0.5} width={canvasWidth - 1} height={canvasHeight - 1} fill="none" stroke="var(--border-subtle)" strokeWidth={2} strokeDasharray="10 8" />
        {objects.map((o) => {
          const p = geometryToPoints(o.geometryJson);
          return p ? <path key={o.templateObjectID} d={pointsToSvgPath(p)} fill="var(--surface-inverse)" opacity={0.6} /> : null;
        })}
        {others.map((s) => {
          const p = geometryToPoints(s.geometryJson);
          return p ? <path key={s.templateSectionID} d={pointsToSvgPath(p)} fill="var(--surface-sunken)" stroke="var(--border-subtle)" /> : null;
        })}
        {points && (
          <path d={pointsToSvgPath(points)}
                fill={tone === 'object' ? 'var(--surface-inverse)' : 'rgba(99,102,241,0.35)'}
                stroke={tone === 'object' ? 'var(--text)' : 'var(--accent, #6366f1)'} strokeWidth={2} />
        )}
        {!points && <text x={canvasWidth / 2} y={canvasHeight / 2} textAnchor="middle" fill="var(--text-muted)" style={{ fontSize: 14 }}>JSON chưa hợp lệ</text>}
      </svg>
    </div>
  );
}

function DeleteButton({ onDelete }) {
  const act = useAction();
  return (
    <Button
      size="sm" variant="danger-quiet" loading={act.busy}
      onClick={() => act.run(async () => {
        if (!window.confirm('Xoá mục này?')) return;
        await onDelete();
      })}
    >
      Xoá
    </Button>
  );
}

/* ══ Version đã Published/Retired — chỉ xem ═════════════════════════════════ */

function ReadOnlyVersionPanel({ version }) {
  const [detail, setDetail] = useState(null);
  useEffect(() => {
    api.get(`/admin/template-versions/${version.venueTemplateVersionID}`).then((res) => setDetail(res.data));
  }, [version.venueTemplateVersionID]);

  if (!detail) return null;
  return (
    <Panel title={`v${version.versionNumber} — ${ADMIN_STATUS_LABEL[version.versionStatus] ?? version.versionStatus}`}
           subtitle="Bất biến — không sửa được. Muốn thay đổi, tạo Draft mới (có thể sao chép từ version này) ở khối phía trên.">
      {detail.floors.map((f) => (
        <div key={f.templateFloorID} style={{ marginBottom: 'var(--space-4)' }}>
          <h4>{f.floorName || f.floorKey}</h4>
          <FloorCanvasPreview floor={f} />
        </div>
      ))}
    </Panel>
  );
}
