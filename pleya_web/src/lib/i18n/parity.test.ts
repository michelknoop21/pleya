import { afterEach, describe, expect, it } from 'vitest';

import { ApiError, ERROR_CODES, TransportError, describeError } from '../api/errors';
import { plural, setLocale, t } from './index';
import { shared, sharedNl } from './shared';
import { web } from './web';
import { webNl } from './web.nl';

const en: Record<string, string> = { ...shared, ...web };
const nl: Record<string, string> = { ...sharedNl, ...webNl };

/**
 * Sleutels waarvan de Nederlandse tekst terecht gelijk is aan de Engelse:
 * eigennamen, leenwoorden en de dev-galerij. Een andere gelijke waarde is
 * vrijwel zeker een vergeten kopie.
 */
const SAME_ON_PURPOSE = [
  'admin.tok.list.title',
  'admin.tok.owner',
  'admin.tok.mcp.title',
  'admin.tok.mcp.tools',
  'admin.tok.mcp.toolCount.one',
  'admin.tok.mcp.toolCount.other',
  'admin.tok.audit.ok',
  'app.name',
  'nav.home',
  'nav.films',
  'nav.series',
  'nav.server',
  'home.title',
  'server.title',
  'server.protocol',
  'theme.oled',
  'item.video',
  'item.audio',
  'item.sdh',
  'common.home',
  'search.filters.shows',
  'admin.tile.scan',
  'admin.activity.scan',
  'admin.activity.scanUnknown',
  'admin.server.title',
  'admin.server.database',
  'admin.server.databaseValue',
  'admin.server.versionValue',
  'admin.lib.status.sidecars',
  'admin.sto.col.root',
  'admin.tc.tile.max',
  'admin.tc.tile.hardware',
  'admin.tc.tile.software',
  'admin.sto.col.inode',
  'admin.sto.col.status',
  'admin.sto.inodeInfo.after',
  'admin.act.failures.open',
  'admin.act.col.status',
  'admin.act.history.scan',
  'admin.act.history.scanUnknown',
  'admin.users.lastActive.value',
  'admin.users.account.title',
  // S10.5: leenwoorden en technische termen die in het Nederlands gelijk zijn.
  'admin.media.transcode.software',
  'admin.media.mode.remux',
  'admin.media.mode.direct_stream',
  'admin.meta.sidecars.title',
  'admin.meta.col.genres',
  'admin.net.conn.direct',
  'admin.sec.tokens.title',
  'admin.diag.versions.build',
  'admin.diag.versions.protocol',
  'admin.diag.versions.protocolValue',
  'admin.diag.versions.database',
  'admin.diag.versions.databaseValue',
  'admin.diag.caps.title',
  'admin.diag.health.ready',
  // S25.6: "ok" en "Status" zijn in het Nederlands hetzelfde woord.
  'admin.bak.status.ok',
  'admin.bak.col.status',
  // DEC-164: "Browser" is in het Nederlands hetzelfde woord.
  'device.browser'
];

function placeholders(text: string): string[] {
  return [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]!).sort();
}

afterEach(() => setLocale('en'));

describe('catalogus: pariteit tussen en en nl', () => {
  it('heeft in beide talen dezelfde sleutelset', () => {
    expect(Object.keys(nl).sort()).toEqual(Object.keys(en).sort());
  });

  it('heeft per sleutel dezelfde plaatshouders', () => {
    for (const key of Object.keys(en)) {
      expect(placeholders(nl[key] ?? ''), key).toEqual(placeholders(en[key]!));
    }
  });

  it('heeft voor elke meervoudssleutel .one en .other in beide talen', () => {
    const bases = new Set(
      Object.keys(en)
        .filter((k) => /\.(one|other)$/.test(k))
        .map((k) => k.replace(/\.(one|other)$/, ''))
    );
    expect(bases.size).toBeGreaterThan(0);
    for (const base of bases) {
      for (const catalogue of [en, nl]) {
        expect(catalogue[`${base}.one`], `${base}.one`).toBeTruthy();
        expect(catalogue[`${base}.other`], `${base}.other`).toBeTruthy();
      }
    }
  });

  it('heeft geen lege Nederlandse waarde', () => {
    for (const [key, value] of Object.entries(nl)) {
      expect(value.trim(), key).not.toBe('');
    }
  });

  it('heeft geen vergeten Engelse kopie', () => {
    const copies = Object.keys(nl).filter(
      (k) => nl[k] === en[k] && !SAME_ON_PURPOSE.includes(k) && !k.startsWith('dev.')
    );
    expect(copies).toEqual([]);
  });
});

describe('foutcodes', () => {
  it('heeft voor elke code een error.<code>-sleutel in beide talen', () => {
    for (const code of ERROR_CODES) {
      expect(en[`error.${code}`], `en ${code}`).toBeTruthy();
      expect(nl[`error.${code}`], `nl ${code}`).toBeTruthy();
    }
  });

  it('geeft een onbekende code de generieke tekst met de code erin', () => {
    const err = new ApiError({ code: 'library.brand_new', message: 'x', status: 409, retryable: false });
    expect(describeError(err)).toBe('Something went wrong (library.brand_new).');
    setLocale('nl');
    expect(describeError(err)).toBe('Er ging iets mis (library.brand_new).');
  });

  it('vertaalt een bekende code en een transportfout in het Nederlands', () => {
    setLocale('nl');
    const err = new ApiError({
      code: 'auth.invalid_credentials',
      message: 'x',
      status: 401,
      retryable: false
    });
    expect(describeError(err)).toBe('Die gebruikersnaam en dat wachtwoord komen niet overeen.');
    expect(describeError(new TransportError(new Error('x')))).toContain('niet bereikbaar');
    expect(describeError(new Error('x'))).toBe('Er ging iets mis.');
  });
});

describe('met de taal op nl', () => {
  it('geeft de vaste termen uit de northstar', () => {
    setLocale('nl');
    expect(t('hero.play')).toBe('Afspelen');
    expect(t('hero.moreInfo')).toBe('Meer info');
    expect(t('rail.viewAll')).toBe('Alles bekijken');
    expect(t('card.remaining', { duration: '1u 12m' })).toBe('nog 1u 12m');
    expect(plural('item.seasonsCount', 1)).toBe('1 seizoen');
    expect(plural('item.seasonsCount', 3)).toBe('3 seizoenen');
  });
});
