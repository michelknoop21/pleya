import { describe, expect, it } from 'vitest';
import { catalogFilterCount, parseCatalogFilters, writeCatalogFilters } from './catalogFilters';

describe('catalog filter URL ownership', () => {
  it('reads repeated filters and rejects closed values instead of silently changing intent', () => {
    const filters = parseCatalogFilters(new URLSearchParams('genre=Drama&genre=Science+fiction&year=2025&watch=in_progress&resolution=uhd'));
    expect(filters).toEqual({ genre: ['Drama','Science fiction'], year: ['2025'], watch: 'in_progress', resolution: ['uhd'] });
    expect(catalogFilterCount(filters)).toBe(5);
    expect(() => parseCatalogFilters(new URLSearchParams('watch=other'))).toThrow();
    expect(() => parseCatalogFilters(new URLSearchParams('resolution=unknown'))).toThrow();
    expect(() => parseCatalogFilters(new URLSearchParams('year=2000oops'))).toThrow();
  });
  it('roundtrips special characters, removes old values and preserves unrelated query parameters', () => {
    const original = new URL('http://client.test/libraries/lib?genre=Old&watch=watched&sort=-year&keep=1');
    const changed = writeCatalogFilters(original, {genre:['Science fiction & fantasy'],year:['2024','2025'],watch:'unwatched',resolution:['fhd']});
    expect(parseCatalogFilters(changed.searchParams)).toEqual({genre:['Science fiction & fantasy'],year:['2024','2025'],watch:'unwatched',resolution:['fhd']});
    expect(changed.searchParams.get('sort')).toBe('-year');
    expect(changed.searchParams.get('keep')).toBe('1');
    expect(original.searchParams.get('genre')).toBe('Old');
    const clear = writeCatalogFilters(changed, {});
    expect(catalogFilterCount(parseCatalogFilters(clear.searchParams))).toBe(0);
    expect(clear.searchParams.get('sort')).toBe('-year');
  });
  it('carries audio language and content rating through the URL like the other groups', () => {
    const url = writeCatalogFilters(new URL('http://client.test/libraries/lib'), {audio_language:['nld','eng'],content_rating:['16']});
    const filters = parseCatalogFilters(url.searchParams);
    expect(filters).toEqual({audio_language:['nld','eng'],content_rating:['16']});
    expect(catalogFilterCount(filters)).toBe(3);
  });
});
