import type { LibraryItemsQuery } from '../api/types';

export type CatalogFilters = Pick<LibraryItemsQuery, 'genre' | 'year' | 'watch' | 'resolution'>;
const KEYS = ['genre', 'year', 'watch', 'resolution'] as const;
const WATCH = ['unwatched', 'in_progress', 'watched'] as const;
const RESOLUTIONS = ['sd', 'hd', 'fhd', 'uhd'] as const;

export function parseCatalogFilters(params: Pick<URLSearchParams, 'get' | 'getAll'>): CatalogFilters {
  const values = (key: string) => [...new Set(params.getAll(key).map(value => value.trim()).filter(Boolean))];
  const genre = values('genre');
  const year = values('year');
  const watch = params.get('watch') || undefined;
  const resolution = values('resolution');
  if (year.some(value => !/^\d{4}$/.test(value) || Number(value) < 1800 || Number(value) > 2200)) throw new Error('Invalid catalog year');
  if (watch && !(WATCH as readonly string[]).includes(watch)) throw new Error('Invalid catalog watch state');
  if (resolution.some(value => !(RESOLUTIONS as readonly string[]).includes(value))) throw new Error('Invalid catalog resolution');
  return {
    ...(genre.length ? { genre } : {}),
    ...(year.length ? { year } : {}),
    ...(watch ? { watch: watch as CatalogFilters['watch'] } : {}),
    ...(resolution.length ? { resolution: resolution as CatalogFilters['resolution'] } : {})
  };
}

export function writeCatalogFilters(url: Pick<URL, 'href'>, filters: CatalogFilters): URL {
  const next = new URL(url.href);
  for (const key of KEYS) {
    next.searchParams.delete(key);
    const selected = filters[key];
    if (Array.isArray(selected)) {
      for (const value of selected) next.searchParams.append(key, value);
    } else if (selected) next.searchParams.set(key, selected);
  }
  return next;
}

export function catalogFilterCount(filters: CatalogFilters): number {
  return (filters.genre?.length ?? 0) + (filters.year?.length ?? 0) + (filters.resolution?.length ?? 0) + (filters.watch ? 1 : 0);
}
