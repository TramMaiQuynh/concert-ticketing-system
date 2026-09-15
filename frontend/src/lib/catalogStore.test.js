import test from 'node:test';
import assert from 'node:assert/strict';
import { createCatalogStore, fetchCatalogPages } from './catalogStore.js';

const tick = () => new Promise((resolve) => setImmediate(resolve));

test('concurrent readers share a request and all receive updates', async () => {
  let calls = 0;
  const store = createCatalogStore(async () => [{ id: ++calls }]);
  let notifications = 0;
  const offA = store.subscribe(() => { notifications += 1; });
  const offB = store.subscribe(() => { notifications += 1; });
  await tick();
  assert.equal(calls, 1);
  assert.deepEqual(store.getSnapshot().raw, [{ id: 1 }]);
  await store.reload();
  assert.equal(calls, 2);
  assert.ok(notifications >= 4);
  offA(); offB();
});

test('late responses cannot restore data from an earlier session', async () => {
  const requests = [];
  const store = createCatalogStore((signal) => new Promise((resolve) => requests.push({ signal, resolve })));
  const off = store.subscribe(() => {});
  await tick();
  const next = store.reload();
  await tick();
  assert.equal(requests[0].signal.aborted, true);
  requests[1].resolve([{ id: 'new owner' }]);
  await next;
  requests[0].resolve([{ id: 'old owner secret' }]);
  await tick();
  assert.deepEqual(store.getSnapshot().raw, [{ id: 'new owner' }]);
  off();
  assert.deepEqual(store.getSnapshot().raw, []);
});

test('failed reads are visible and retryable, not cached as empty success', async () => {
  let fail = true;
  const store = createCatalogStore(async () => {
    if (fail) throw new Error('offline');
    return [{ id: 1 }];
  });
  const off = store.subscribe(() => {});
  await tick();
  assert.equal(store.getSnapshot().error.message, 'offline');
  fail = false;
  await store.reload();
  assert.equal(store.getSnapshot().error, null);
  assert.deepEqual(store.getSnapshot().raw, [{ id: 1 }]);
  off();
});

test('keyset pagination retrieves every row beyond the old 50/100 item limits', async () => {
  const rows = Array.from({ length: 451 }, (_, i) => ({ seatID: i + 1 }));
  const cursors = [];
  const result = await fetchCatalogPages(async ({ afterId, limit }) => {
    cursors.push(afterId);
    return rows.filter((r) => r.seatID > afterId).slice(0, limit);
  }, 'seatID', new AbortController().signal);
  assert.deepEqual(result, rows);
  assert.deepEqual(cursors, [0, 200, 400]);
});

test('malformed or repeated pages fail instead of looping or hiding missing data', async () => {
  const signal = new AbortController().signal;
  await assert.rejects(fetchCatalogPages(async () => ({}), 'id', signal));
  await assert.rejects(fetchCatalogPages(async () => [{ id: 2 }, { id: 1 }], 'id', signal));
});
