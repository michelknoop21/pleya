/**
 * Weergaveregels die op meer dan één scherm gelden.
 *
 * Duur komt in milliseconden binnen en nooit in seconden; het contract is daar
 * stellig over. Tijden zijn RFC 3339 in UTC en worden in de tijdzone van de
 * lezer getoond.
 */
import type { Item } from '../api/types';
import { intlLocale, plural, t } from '../i18n';

/**
 * De eenheden komen uit de catalogus (`duration.*`), zodat een derde taal geen
 * code raakt. "u 46m" in het Nederlands is hier dus geen uitzondering in de
 * logica maar een andere tekst in dezelfde vorm.
 */
export function formatDuration(ms: number | null | undefined): string | null {
  if (typeof ms !== 'number' || !Number.isFinite(ms) || ms <= 0) return null;
  // Onder de minuut in seconden, want naar minuten afronden maakt van een
  // fragment van twee seconden "0m", en dat leest als "duur onbekend".
  if (ms < 60_000) return t('duration.s', { s: Math.max(1, Math.round(ms / 1000)) });
  const totalMinutes = Math.round(ms / 60000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours === 0) return t('duration.m', { m: minutes });
  // "3h 0m" leest als een meting tot op de minuut; een rond uur is "3h".
  if (minutes === 0) return t('duration.h', { h: hours });
  return t('duration.hm', { h: hours, m: minutes });
}

// De taal komt uit de actieve locale en wordt bij de aanroep gelezen, niet bij
// het laden van de module: een vaste Engelse standaard liet de datum Engels
// terwijl de rest van de pagina Nederlands was.
export function formatDate(iso: string | null | undefined, locale = intlLocale()): string | null {
  if (!iso) return null;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  // Nederlands in de lange vorm ("12 augustus 2026", de northstar); Engels
  // houdt de korte ("Aug 12, 2026").
  const dateStyle = locale.startsWith('nl') ? 'long' : 'medium';
  return new Intl.DateTimeFormat(locale, { dateStyle }).format(date);
}

export function formatCount(count: number, locale = intlLocale()): string {
  return new Intl.NumberFormat(locale).format(count);
}

const BYTE_UNITS = ['B', 'kB', 'MB', 'GB', 'TB', 'PB'] as const;

/**
 * Decimaal (1000), zoals de northstar "42,1 GB" voor een bestand toont en
 * zoals schijfleveranciers en de server rekenen. Hele bytes zonder decimaal,
 * vanaf kB hooguit één: "8,3 GB", "120 GB". Ongeldig of negatief telt als
 * "0 B", omdat deze functie als `format` in een meter staat en een string moet
 * teruggeven.
 */
export function formatBytes(bytes: number, locale = intlLocale()): string {
  const value = Number.isFinite(bytes) && bytes > 0 ? bytes : 0;
  let unit = 0;
  let scaled = value;
  while (scaled >= 1000 && unit < BYTE_UNITS.length - 1) {
    scaled /= 1000;
    unit += 1;
  }
  const number = new Intl.NumberFormat(locale, {
    maximumFractionDigits: unit === 0 ? 0 : 1
  }).format(scaled);
  return `${number} ${BYTE_UNITS[unit]}`;
}

// De server levert ISO 639-2-codes (`eng`); `Intl.DisplayNames` kent die niet
// altijd. De codes die een mediabestand in de praktijk draagt, naar twee letters.
const LANGUAGE_ALIASES: Record<string, string> = {
  eng: 'en', nld: 'nl', dut: 'nl', deu: 'de', ger: 'de', fra: 'fr', fre: 'fr',
  spa: 'es', ita: 'it', por: 'pt', rus: 'ru', jpn: 'ja', kor: 'ko', zho: 'zh',
  chi: 'zh', ara: 'ar', hin: 'hi', swe: 'sv', nor: 'no', dan: 'da', fin: 'fi',
  pol: 'pl', tur: 'tr', ces: 'cs', cze: 'cs', ell: 'el', gre: 'el', heb: 'he',
  hun: 'hu', ukr: 'uk', tha: 'th', vie: 'vi', ind: 'id', ron: 'ro', rum: 'ro'
};

/** "eng" wordt "English" of "Engels"; een onbekende code komt ongewijzigd terug. */
export function formatLanguage(code: string | null | undefined, locale = intlLocale()): string | null {
  if (!code) return null;
  const lower = code.trim().toLowerCase();
  if (!lower) return null;
  try {
    const names = new Intl.DisplayNames(locale, { type: 'language', fallback: 'code' });
    return names.of(LANGUAGE_ALIASES[lower] ?? lower) ?? code;
  } catch {
    // Structureel ongeldige code: de code zelf, geen kapotte pagina.
    return code;
  }
}

/**
 * De tweede regel onder een kaart: wat het item op zichzelf zegt.
 *
 * Alleen velden die `Item` vandaag werkelijk draagt. Samenvatting, genres,
 * cast en beoordelingen bestaan in PS-2 niet en horen bij PS-7; een
 * plaatshouder ervoor zou beloven wat er niet is.
 */
export function itemSubtitle(item: Item): string | null {
  switch (item.kind) {
    case 'episode': {
      if (typeof item.index === 'number') return t('item.episode', { index: item.index });
      return null;
    }
    case 'season': {
      if (typeof item.child_count === 'number') {
        return plural('item.episodesCount', item.child_count);
      }
      if (typeof item.index === 'number') return t('item.season', { index: item.index });
      return null;
    }
    case 'show': {
      if (typeof item.child_count === 'number') {
        return plural('item.seasonsCount', item.child_count);
      }
      return item.year ? String(item.year) : null;
    }
    default:
      return item.year ? String(item.year) : null;
  }
}

/** Films en series krijgen een poster, afleveringen een 16:9-beeld. */
export function artworkAspect(kind: Item['kind']): 'poster' | 'wide' {
  return kind === 'episode' ? 'wide' : 'poster';
}

/**
 * Hoe ver iemand in een item zit, voor de voortgangsbalk op de kaart en
 * straks op de detailpagina. Eén regel op één plek, zodat raster, rail en
 * detail hetzelfde zeggen.
 *
 * Geen voortgang als het item gezien is (dan wint het vinkje), als de positie
 * nul is, of als de duur ontbreekt: een balk zonder noemer is een gok.
 */
export function itemProgress(
  item: Item
): { fraction: number; remainingMs: number } | null {
  const state = item.user_state;
  const duration = item.duration_ms;
  if (!state || state.watched) return null;
  if (typeof duration !== 'number' || duration <= 0) return null;
  const position = state.position_ms;
  if (typeof position !== 'number' || position <= 0) return null;
  const clamped = Math.min(position, duration);
  return { fraction: clamped / duration, remainingMs: duration - clamped };
}

/**
 * De onderregel van een kaart. Wie halverwege is wil weten hoeveel er nog
 * over is, niet het jaartal; zonder voortgang de gewone onderregel.
 */
export function cardSubtitle(item: Item): string | null {
  const progress = itemProgress(item);
  const left = progress ? formatDuration(progress.remainingMs) : null;
  if (left) return t('card.remaining', { duration: left });
  return itemSubtitle(item);
}

/**
 * Het beeld van een kaart: een brede kaart neemt de backdrop en valt terug op
 * de poster, een posterkaart alleen de poster.
 */
export function cardArtworkId(item: Item, shape: 'poster' | 'wide'): string | null | undefined {
  return shape === 'wide'
    ? (item.artwork?.backdrop_id ?? item.artwork?.poster_id)
    : item.artwork?.poster_id;
}

/**
 * Gezien. Een film of aflevering draagt het in `user_state`; een serie of
 * seizoen is gezien als elke aflevering het is. Nul afleveringen is niet
 * gezien: een lege serie zou anders een vinkje krijgen.
 */
export function isWatched(item: Item): boolean {
  if (item.user_state?.watched) return true;
  const total = item.episode_count;
  return (
    typeof total === 'number' &&
    total > 0 &&
    item.watched_episode_count === total
  );
}
