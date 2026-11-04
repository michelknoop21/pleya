import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { setLocale } from '../i18n';
import { library, root, scan } from './libraryFake';
import {
  activeLibraryIds,
  libraryNames,
  rootNotes,
  rootSpace,
  rootTrust,
  storageHeadline,
  unmountedRoots
} from './storage';

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

const films = library('l1', 'Films');
const boeken = library('l2', 'Boeken');

describe('opslag: samenvatting en ruimte', () => {
  it('telt gemounte en onbereikbare roots en geeft de vrije ruimte', () => {
    const roots = [
      root('/a', films, { free_bytes: 2_000_000_000_000, total_bytes: 6_000_000_000_000 }),
      root('/b', boeken, { mounted: false, fs_type: null, free_bytes: 0, total_bytes: 0 })
    ];
    expect(storageHeadline(roots)).toBe('1 root gemount · 1 niet bereikbaar · 2 TB vrij');
    expect(storageHeadline([roots[0]!])).toBe('1 root gemount · 2 TB vrij');
  });

  it('rekent het gebruikte deel en markeert weinig vrij als amber', () => {
    const ok = rootSpace(root('/a', films, { free_bytes: 1_100_000_000_000, total_bytes: 6_000_000_000_000 }));
    expect(ok).toMatchObject({ known: true, low: false, text: '1,1 TB vrij van 6 TB' });
    expect(ok.usedShare).toBeCloseTo(81.7, 1);

    const low = rootSpace(root('/s', films, { free_bytes: 240_000_000_000, total_bytes: 4_000_000_000_000 }));
    expect(low.low).toBe(true);
  });

  it('houdt de grens van tien procent: precies tien procent vrij is nog niet laag', () => {
    expect(rootSpace(root('/a', films, { free_bytes: 100, total_bytes: 1000 })).low).toBe(false);
    expect(rootSpace(root('/a', films, { free_bytes: 99, total_bytes: 1000 })).low).toBe(true);
  });

  it('toont een niet-gemounte root als onbekend, ook als de server oude maten meegeeft', () => {
    const space = rootSpace(root('/b', boeken, { mounted: false, free_bytes: 500, total_bytes: 1000 }));
    expect(space).toMatchObject({ known: false, text: 'onbekend', low: false });
  });

  it('klemt een vrije ruimte groter dan het totaal', () => {
    const space = rootSpace(root('/a', films, { free_bytes: 2000, total_bytes: 1000 }));
    expect(space.usedShare).toBe(0);
  });
});

describe('opslag: inodevertrouwen', () => {
  it('noemt betrouwbaar met zijn bron', () => {
    expect(rootTrust(root('/a', films, { inode_trust_source: 'measured' }))).toEqual({
      tone: 'ok',
      label: 'betrouwbaar',
      detail: 'gemeten'
    });
  });

  it('zegt bij onbetrouwbaar ook wat de scanner dan doet', () => {
    const trust = rootTrust(root('/u', null, { inode_trusted: false, inode_trust_source: 'fstype_default' }));
    expect(trust.tone).toBe('warn');
    expect(trust.label).toBe('niet betrouwbaar');
    expect(trust.detail).toBe('standaard · scanner gebruikt signatuur');
  });

  it('valt bij een bron die de client niet kent terug op een eerlijke zin', () => {
    const odd = root('/a', films, { inode_trust_source: 'iets_nieuws' as never });
    expect(rootTrust(odd).detail).toBe('bron onbekend');
  });
});

describe('opslag: notities en bibliotheken', () => {
  it('zegt niet in gebruik en scan bezig', () => {
    const free = root('/usb', null);
    expect(rootNotes(free, new Set())).toEqual(['niet in gebruik']);
    expect(rootNotes(root('/a', films), new Set(['l1']))).toEqual(['scan bezig']);
    expect(rootNotes(root('/a', films), new Set(['l9']))).toEqual([]);
  });

  it('leest uit de scans welke bibliotheken nu scannen', () => {
    const ids = activeLibraryIds([
      scan('l1', 'running', { id: 's1' }),
      scan('l2', 'done', { id: 's2' }),
      scan('l3', 'queued', { id: 's3' })
    ]);
    expect([...ids].sort()).toEqual(['l1', 'l3']);
  });

  it('geeft de niet-gemounte roots en hun bibliotheken zonder dubbelen', () => {
    const roots = [
      root('/a', films),
      root('/b', boeken, { mounted: false }),
      root('/c', boeken, { mounted: false })
    ];
    expect(unmountedRoots(roots).map((r) => r.path)).toEqual(['/b', '/c']);
    expect(libraryNames(unmountedRoots(roots))).toEqual(['Boeken']);
  });
});
