import { afterEach, describe, expect, it } from 'vitest';

import {
  artworkAspect,
  cardArtworkId,
  cardSubtitle,
  formatBytes,
  formatCount,
  formatDate,
  formatDuration,
  formatLanguage,
  formatRelative,
  isWatched,
  itemProgress,
  itemSubtitle
} from './format';
import type { Item } from '../api/types';
import { setLocale, type Locale } from '../i18n';

// De actieve taal is moduletoestand; elke test begint weer in het Engels.
afterEach(() => setLocale('en'));

function inLocale<T>(locale: Locale, run: () => T): T {
  setLocale(locale);
  return run();
}

function item(patch: Partial<Item>): Item {
  return {
    id: 'x',
    kind: 'movie',
    title: 'T',
    added_at: '2026-01-01T00:00:00Z',
    ...patch
  } as Item;
}

describe('duur', () => {
  it('rekent milliseconden om en nooit seconden', () => {
    expect(formatDuration(5_400_000)).toBe('1h 30m');
    expect(formatDuration(2_700_000)).toBe('45m');
  });

  it('laat nul minuten weg bij een rond uur', () => {
    expect(formatDuration(10_800_000)).toBe('3h');
    expect(formatDuration(3_600_000)).toBe('1h');
    expect(formatDuration(3_660_000)).toBe('1h 1m');
  });

  it('toont seconden onder de minuut, want "0m" leest als onbekend', () => {
    expect(formatDuration(2_000)).toBe('2s');
    expect(formatDuration(59_000)).toBe('59s');
    expect(formatDuration(60_000)).toBe('1m');
  });

  it('geeft niets terug voor nul, negatief of ontbrekend', () => {
    expect(formatDuration(0)).toBeNull();
    expect(formatDuration(-1)).toBeNull();
    expect(formatDuration(null)).toBeNull();
    expect(formatDuration(undefined)).toBeNull();
  });
});

describe('datum', () => {
  it('leest RFC 3339 in UTC', () => {
    expect(formatDate('2026-08-19T12:00:00Z')).toContain('2026');
  });

  it('geeft niets terug voor onzin', () => {
    expect(formatDate('niet een datum')).toBeNull();
    expect(formatDate(null)).toBeNull();
  });
});

describe('de tweede regel onder een kaart', () => {
  it('toont het jaar bij een film', () => {
    expect(itemSubtitle(item({ kind: 'movie', year: 1978 }))).toBe('1978');
  });

  it('toont het aantal seizoenen bij een serie, met de juiste enkelvoudsvorm', () => {
    expect(itemSubtitle(item({ kind: 'show', child_count: 4 }))).toBe('4 seasons');
    expect(itemSubtitle(item({ kind: 'show', child_count: 1 }))).toBe('1 season');
  });

  it('doet hetzelfde voor afleveringen onder een seizoen', () => {
    expect(itemSubtitle(item({ kind: 'season', child_count: 1 }))).toBe('1 episode');
    expect(itemSubtitle(item({ kind: 'season', child_count: 12 }))).toBe('12 episodes');
  });

  it('toont het afleveringsnummer bij een aflevering', () => {
    expect(itemSubtitle(item({ kind: 'episode', index: 3 }))).toBe('Episode 3');
  });

  it('verzint niets wanneer het veld ontbreekt', () => {
    expect(itemSubtitle(item({ kind: 'movie' }))).toBeNull();
    expect(itemSubtitle(item({ kind: 'episode' }))).toBeNull();
  });
});

describe('verhouding van het beeld', () => {
  it('geeft een aflevering 16:9 en de rest een poster', () => {
    expect(artworkAspect('episode')).toBe('wide');
    expect(artworkAspect('movie')).toBe('poster');
    expect(artworkAspect('show')).toBe('poster');
    expect(artworkAspect('season')).toBe('poster');
  });
});

function state(position_ms: number, watched = false): Item['user_state'] {
  return { position_ms, watched, play_count: 0, updated_at: '2026-01-01T00:00:00Z' };
}

describe('voortgang', () => {
  it('geeft fractie en resterende tijd uit positie en duur', () => {
    const p = itemProgress(item({ duration_ms: 10_000_000, user_state: state(2_500_000) }));
    expect(p).toEqual({ fraction: 0.25, remainingMs: 7_500_000 });
  });

  it('heeft geen voortgang zonder positie, zonder duur of als het item gezien is', () => {
    expect(itemProgress(item({ duration_ms: 10_000 }))).toBeNull();
    expect(itemProgress(item({ duration_ms: 10_000, user_state: state(0) }))).toBeNull();
    expect(itemProgress(item({ user_state: state(5_000) }))).toBeNull();
    expect(itemProgress(item({ duration_ms: 10_000, user_state: state(5_000, true) }))).toBeNull();
  });

  it('klemt een positie voorbij het einde op de duur', () => {
    expect(itemProgress(item({ duration_ms: 1_000, user_state: state(5_000) }))?.fraction).toBe(1);
  });
});

describe('gezien', () => {
  it('leest user_state bij een film', () => {
    expect(isWatched(item({ user_state: state(0, true) }))).toBe(true);
    expect(isWatched(item({ user_state: state(100) }))).toBe(false);
  });

  it('noemt een serie gezien als elke aflevering gezien is, en een lege serie niet', () => {
    expect(isWatched(item({ kind: 'show', episode_count: 8, watched_episode_count: 8 }))).toBe(true);
    expect(isWatched(item({ kind: 'show', episode_count: 8, watched_episode_count: 7 }))).toBe(false);
    expect(isWatched(item({ kind: 'show', episode_count: 0, watched_episode_count: 0 }))).toBe(false);
  });
});

describe('cardSubtitle en cardArtworkId', () => {
  it('zet bij voortgang de resterende tijd onder de kaart, anders de onderregel', () => {
    const state = {
      position_ms: 600_000,
      watched: false,
      play_count: 0,
      updated_at: '2026-01-01T00:00:00Z'
    };
    expect(cardSubtitle(item({ year: 2021, duration_ms: 3_600_000, user_state: state }))).toBe(
      '50m left'
    );
    expect(cardSubtitle(item({ year: 2021 }))).toBe('2021');
  });

  it('kiest de backdrop voor wide en alleen de poster voor poster', () => {
    const art = item({ artwork: { poster_id: 'p', backdrop_id: 'b' } });
    expect(cardArtworkId(art, 'wide')).toBe('b');
    expect(cardArtworkId(art, 'poster')).toBe('p');
    expect(cardArtworkId(item({ artwork: { poster_id: 'p' } }), 'wide')).toBe('p');
  });
});

const MIN = 60_000;

describe('per taal: duur', () => {
  const cases: Array<[string, number, string, string]> = [
    ['2u 46m', 166 * MIN, '2h 46m', '2u 46m'],
    ['een rond uur', 180 * MIN, '3h', '3u'],
    ['31 minuten', 31 * MIN, '31m', '31 min'],
    ['12 seconden', 12_000, '12s', '12 s'],
    ['59 minuten (net onder het uur)', 59 * MIN, '59m', '59 min'],
    ['60 minuten (net een uur)', 60 * MIN, '1h', '1u'],
    ['1 minuut', 1 * MIN, '1m', '1 min']
  ];
  for (const [name, ms, en, nl] of cases) {
    it(`${name}: ${en} in het Engels, ${nl} in het Nederlands`, () => {
      expect(inLocale('en', () => formatDuration(ms))).toBe(en);
      expect(inLocale('nl', () => formatDuration(ms))).toBe(nl);
    });
  }

  it('geeft in beide talen niets voor nul, NaN en null', () => {
    for (const l of ['en', 'nl'] as const) {
      expect(inLocale(l, () => formatDuration(0))).toBeNull();
      expect(inLocale(l, () => formatDuration(Number.NaN))).toBeNull();
      expect(inLocale(l, () => formatDuration(null))).toBeNull();
      expect(inLocale(l, () => formatDuration(Number.POSITIVE_INFINITY))).toBeNull();
    }
  });
});

describe('per taal: datum, getal, grootte, taalnaam', () => {
  it('schrijft de datum in de taal van de pagina', () => {
    expect(inLocale('en', () => formatDate('2026-08-12T12:00:00Z'))).toBe('Aug 12, 2026');
    expect(inLocale('nl', () => formatDate('2026-08-12T12:00:00Z'))).toBe('12 augustus 2026');
  });

  it('zet het duizendtal volgens de taal', () => {
    expect(inLocale('en', () => formatCount(1200))).toBe('1,200');
    expect(inLocale('nl', () => formatCount(1200))).toBe('1.200');
  });

  it('rekent bytes decimaal en zet de komma volgens de taal', () => {
    expect(inLocale('en', () => formatBytes(8.3e9))).toBe('8.3 GB');
    expect(inLocale('nl', () => formatBytes(8.3e9))).toBe('8,3 GB');
    expect(inLocale('nl', () => formatBytes(42.1e9))).toBe('42,1 GB');
    setLocale('en');
    expect(formatBytes(0)).toBe('0 B');
    expect(formatBytes(999)).toBe('999 B');
    expect(formatBytes(1500)).toBe('1.5 kB');
    expect(formatBytes(Number.NaN)).toBe('0 B');
    expect(formatBytes(-5)).toBe('0 B');
  });

  it('rondt eerst af en promoveert daarna, zodat er nooit 1000 van een eenheid staat', () => {
    // Negatieve controle: met de eenheid vóór het afronden gekozen gaf dit "1,000 kB".
    expect(inLocale('en', () => formatBytes(999_950))).toBe('1.0 MB');
    expect(inLocale('nl', () => formatBytes(999_950))).toBe('1,0 MB');
    expect(inLocale('en', () => formatBytes(999_950))).not.toContain('kB');
    expect(inLocale('en', () => formatBytes(999_949))).toBe('999.9 kB');
    expect(inLocale('en', () => formatBytes(999.6))).toBe('1.0 kB');
    // Een rond totaal krijgt geen ",0": de northstar toont "van 6 TB".
    expect(inLocale('en', () => formatBytes(2000))).toBe('2 kB');
    expect(inLocale('nl', () => formatBytes(6e12))).toBe('6 TB');
    expect(inLocale('en', () => formatBytes(120e9))).toBe('120 GB');
  });

  it('vertaalt een taalcode, ook de driecijferige van de server', () => {
    expect(inLocale('en', () => formatLanguage('eng'))).toBe('English');
    expect(inLocale('nl', () => formatLanguage('eng'))).toBe('Engels');
    expect(inLocale('nl', () => formatLanguage('fre'))).toBe('Frans');
    expect(inLocale('nl', () => formatLanguage('nl'))).toBe('Nederlands');
    expect(inLocale('nl', () => formatLanguage('xx'))).toBe('xx');
  });

  it('laat een onbekende of ongeldige code ongewijzigd en ontbrekend leeg', () => {
    expect(formatLanguage('xx')).toBe('xx');
    expect(formatLanguage('e n!')).toBe('e n!');
    expect(formatLanguage(null)).toBeNull();
    expect(formatLanguage('')).toBeNull();
  });
});

describe('formatRelative', () => {
  const now = Date.parse('2026-10-11T12:00:00Z');

  it('kiest de grootste hele eenheid, in de gevraagde taal', () => {
    expect(formatRelative('2026-10-11T11:57:00Z', now, 'nl-NL')).toBe('3 minuten geleden');
    expect(formatRelative('2026-10-11T11:57:00Z', now, 'en')).toBe('3 minutes ago');
    expect(formatRelative('2026-10-11T11:59:15Z', now, 'en')).toBe('45 seconds ago');
    expect(formatRelative('2026-10-11T09:00:00Z', now, 'en')).toBe('3 hours ago');
    expect(formatRelative('2026-10-06T12:00:00Z', now, 'nl-NL')).toBe('5 dagen geleden');
  });

  it('noemt nul "nu" en een dag "gisteren", ook bij een klok die voorloopt', () => {
    expect(formatRelative('2026-10-11T12:00:00Z', now, 'nl-NL')).toBe('nu');
    expect(formatRelative('2026-10-11T12:05:00Z', now, 'en')).toBe('now');
    expect(formatRelative('2026-10-10T12:00:00Z', now, 'nl-NL')).toBe('gisteren');
  });

  it('geeft niets terug zonder geldige tijd', () => {
    expect(formatRelative(null, now)).toBeNull();
    expect(formatRelative('geen datum', now)).toBeNull();
  });
});
