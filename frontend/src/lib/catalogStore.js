// A store belongs to one mounted catalogue. Requests from an earlier generation
// cannot repopulate it after invalidation, logout, or unmount.
export function createCatalogStore(fetchRows) {
  let snapshot = { raw: [], loading: true, error: null };
  let generation = 0;
  let controller;
  let pending;
  const listeners = new Set();
  const emit = () => listeners.forEach((listener) => listener());
  const load = () => {
    if (pending) return pending;
    const current = generation;
    controller = new AbortController();
    const signal = controller.signal;
    snapshot = { raw: [], loading: true, error: null };
    emit();
    pending = Promise.resolve().then(() => fetchRows(signal)).then(
      (raw) => {
        if (current === generation) {
          snapshot = { raw, loading: false, error: null };
          emit();
        }
      },
      (error) => {
        if (current === generation) {
          snapshot = { raw: [], loading: false, error };
          emit();
        }
      },
    ).finally(() => { if (current === generation) pending = null; });
    return pending;
  };
  const reset = (reload = true) => {
    generation += 1;
    controller?.abort();
    pending = null;
    snapshot = { raw: [], loading: true, error: null };
    emit();
    if (reload && listeners.size) return load();
    return Promise.resolve();
  };
  return {
    getSnapshot: () => snapshot,
    reload: () => reset(),
    reset,
    subscribe(listener) {
      listeners.add(listener);
      if (listeners.size === 1) load();
      return () => {
        listeners.delete(listener);
        if (!listeners.size) reset(false);
      };
    },
  };
}

export async function fetchCatalogPages(getPage, idField, signal) {
  const rows = [];
  let afterId = 0;
  const limit = 200;
  while (!signal.aborted) {
    const page = await getPage({ afterId, limit }, signal);
    if (!Array.isArray(page)) throw new Error('Dữ liệu danh mục không hợp lệ.');
    for (const row of page) {
      if (!Number.isInteger(row[idField]) || row[idField] <= afterId) {
        throw new Error('Thứ tự danh mục không hợp lệ.');
      }
      afterId = row[idField];
      rows.push(row);
    }
    if (page.length < limit) return rows;
  }
  throw new Error('Đã hủy tải danh mục.');
}
