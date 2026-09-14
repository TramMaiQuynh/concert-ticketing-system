/**
 * GeometryJson v1 — quy ước hình học dùng chung cho toàn bộ StagePass
 * (TemplateObject/TemplateSection/TemplateSeat và các bảng ConcertMapRevision*
 * tương ứng). Xem quy ước đầy đủ trong database/Tables/TemplateSection.sql.
 *
 * Tách khỏi VenueTemplates.jsx (nơi hai hàm này được viết lần đầu cho trình
 * soạn thảo Admin) để trang khách hàng (components/SeatMap.jsx) dùng LẠI đúng
 * một phép toán — hai bản triển khai riêng rẽ cho cùng một GeometryJson chắc
 * chắn sẽ trôi dạt và vẽ lệch nhau giữa Studio và trang mua vé.
 */

/** Danh sách đỉnh (theo chu vi) để vẽ SVG — dùng chung cho rect và polygon. */
export function geometryToPoints(json) {
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
  } catch { /* ignored — hinh hoc dang go do hoac chua hop le, xem truoc bo qua */ }
  return null;
}

export function pointsToSvgPath(points) {
  if (!points || points.length === 0) return '';
  return `M ${points.map((p) => `${p[0]},${p[1]}`).join(' L ')} Z`;
}

/**
 * Đa giác có lồi hay không — bản JS mirror CHÍNH XÁC của
 * fn_TemplateGeometryIsConvex.sql (cùng công thức: tích có hướng của từng cặp
 * cạnh liên tiếp quanh chu vi, lồi khi và chỉ khi tất cả cùng dấu). Dùng để
 * xem trước ngay lúc vẽ trong Studio — server vẫn là nơi thi hành thật
 * (sp_ConfigureTemplateSection từ chối hình lõm), bản JS này chỉ để báo sớm,
 * đúng nguyên tắc "client báo ngay, server thi hành thật" đã dùng cho
 * `polygonsOverlap` trong VenueTemplates.jsx.
 */
export function isConvexPolygon(points) {
  const n = points?.length ?? 0;
  if (n < 3) return false;
  let posCount = 0;
  let negCount = 0;
  for (let i = 0; i < n; i += 1) {
    const p1 = points[i];
    const p2 = points[(i + 1) % n];
    const p3 = points[(i + 2) % n];
    const e1x = p2[0] - p1[0];
    const e1y = p2[1] - p1[1];
    const e2x = p3[0] - p2[0];
    const e2y = p3[1] - p2[1];
    const cross = e1x * e2y - e1y * e2x;
    if (cross > 1e-9) posCount += 1;
    else if (cross < -1e-9) negCount += 1;
  }
  return (posCount > 0 && negCount === 0) || (negCount > 0 && posCount === 0);
}

/**
 * Va chạm SAT tổng quát cho hai đa giác LỒI — bản JS mirror CHÍNH XÁC của
 * fn_TemplateGeometryOverlaps.sql (trục ứng viên = pháp tuyến từng cạnh của
 * CẢ HAI hình; chạm biên — khoảng cách đúng 0 — KHÔNG tính là chồng lấn, cùng
 * epsilon 1e-6). Gọi hàm này SAU KHI đã xác nhận cả hai hình lồi bằng
 * isConvexPolygon — với hình lõm, SAT có thể báo "không chạm" sai (false
 * negative), y hệt giới hạn đã ghi trong comment SQL gốc.
 */
export function polygonsOverlap(pointsA, pointsB) {
  const na = pointsA?.length ?? 0;
  const nb = pointsB?.length ?? 0;
  if (na < 3 || nb < 3) return false;

  const axes = [];
  const collectAxes = (pts) => {
    const n = pts.length;
    for (let i = 0; i < n; i += 1) {
      const p1 = pts[i];
      const p2 = pts[(i + 1) % n];
      const ex = p2[0] - p1[0];
      const ey = p2[1] - p1[1];
      const nx = -ey;
      const ny = ex;
      if (nx !== 0 || ny !== 0) axes.push([nx, ny]);
    }
  };
  collectAxes(pointsA);
  collectAxes(pointsB);

  for (const [nx, ny] of axes) {
    let minA = Infinity, maxA = -Infinity;
    for (const p of pointsA) {
      const proj = p[0] * nx + p[1] * ny;
      if (proj < minA) minA = proj;
      if (proj > maxA) maxA = proj;
    }
    let minB = Infinity, maxB = -Infinity;
    for (const p of pointsB) {
      const proj = p[0] * nx + p[1] * ny;
      if (proj < minB) minB = proj;
      if (proj > maxB) maxB = proj;
    }
    if (maxA <= minB + 1e-6 || maxB <= minA + 1e-6) return false; // trục tách được -> khong cham
  }
  return true;
}

/** Mọi đỉnh nằm trong [0, canvasWidth] × [0, canvasHeight] hay không. */
export function pointsWithinCanvas(points, canvasWidth, canvasHeight) {
  return (points ?? []).every(([x, y]) => x >= 0 && x <= canvasWidth && y >= 0 && y <= canvasHeight);
}
