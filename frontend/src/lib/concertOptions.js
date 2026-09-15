import { useAdminCatalog, invalidateCatalog } from './adminCatalog';

export function invalidateConcerts() {
  return invalidateCatalog('concert');
}

export function useConcertOptions() {
  const catalog = useAdminCatalog('concert');
  return { ...catalog, options: catalog.items };
}
