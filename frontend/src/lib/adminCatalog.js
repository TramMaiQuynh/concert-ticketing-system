import { useSyncExternalStore } from 'react';
import api, { onAuthChange, getAccessToken } from '../api/client';
import { createCatalogStore, fetchCatalogPages } from './catalogStore';

const definitions = {
  venue: ['venues', 'venueID', (v) => v.venueName + ' · ' + v.venueStatus + (v.hasSeatMap ? ' · có sơ đồ' : ' · CHƯA có sơ đồ')],
  artist: ['artists', 'artistID', (a) => a.artistName + ' · ' + a.artistStatus],
  concert: ['concerts', 'concertID', (c) => c.concertName + ' · ' + c.concertStatus],
  zone: ['zones', 'zoneID', (z) => (z.zoneName || z.zoneCode) + ' · ' + z.venueName + ' · ' + z.zoneStatus],
  seat: ['seats', 'seatID', (s) => s.seatCode + ' · ' + s.venueName + ' / ' + (s.zoneName || s.zoneID) + ' · ' + s.seatStatus],
  category: ['categories', 'ticketCategoryID', (c) => c.categoryName + ' · ' + c.concertName + ' · ' + c.categoryStatus],
  promotion: ['promotions', 'promotionID', (p) => p.promotionName + ' · ' + p.concertName + ' · ' + p.promotionStatus],
  discountCode: ['discount-codes', 'discountCodeID', (d) => d.codeValue + ' · ' + d.promotionName + ' · ' + d.concertName + ' · ' + d.codeStatus],
  refund: ['refunds', 'refundID', (r) => 'Booking #' + r.bookingID + ' · ' + r.concertName + ' · ' + r.refundAmount.toLocaleString('vi-VN') + ' ₫ · ' + r.refundStatus],
};
const stores = new Map();

function getStore(kind, includeInactive = false) {
  const key = kind + ':' + includeInactive;
  if (!stores.has(key)) {
    const [path, idField] = definitions[kind];
    stores.set(key, createCatalogStore(async (signal) => {
      if (!getAccessToken()) return [];
      if (kind === 'venue' || kind === 'artist') {
        const res = await api.get('/admin/' + path, {
          signal, params: { includeInactive, includeRetired: includeInactive },
        });
        if (!Array.isArray(res.data)) throw new Error('Dữ liệu danh mục không hợp lệ.');
        return res.data;
      }
      return fetchCatalogPages(async (params, pageSignal) => {
        const res = await api.get('/admin/' + path, { params, signal: pageSignal });
        return res.data;
      }, idField, signal);
    }));
  }
  return stores.get(key);
}

export function invalidateCatalog(kind) {
  // Retain the plural names used by the venue map editor.
  const normalized = kind === 'venues' ? 'venue' : kind === 'artists' ? 'artist' : kind;
  return Promise.all([...stores].filter(([key]) => !normalized || key.startsWith(normalized + ':'))
    .map(([, store]) => store.reload()));
}

// Discard all data and in-flight responses whenever the authenticated token changes.
onAuthChange(() => { invalidateCatalog(); });

// All catalogue mutations, including the map editor and refund workflow, refresh
// mounted readers. Debouncing also handles sequential bulk seat creation.
let refreshTimer;
api.interceptors.response.use((response) => {
  const { method, url = '' } = response.config;
  if (method && !['get', 'head', 'options'].includes(method.toLowerCase())
      && (url.startsWith('/admin/') || url.startsWith('/refunds/') || /\/bookings\/\d+\/refund$/.test(url))) {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(() => { invalidateCatalog(); }, 100);
  }
  return response;
});

export function useAdminCatalog(kind, { includeInactive = false } = {}) {
  const store = getStore(kind, includeInactive);
  const snapshot = useSyncExternalStore(store.subscribe, store.getSnapshot);
  const [, idField, label] = definitions[kind];
  const items = snapshot.raw.map((raw) => ({ id: raw[idField], name: label(raw), raw }));
  return { ...snapshot, items, reload: store.reload };
}

export const useVenues = (options) => useAdminCatalog('venue', options);
export const useArtists = (options) => useAdminCatalog('artist', options);
