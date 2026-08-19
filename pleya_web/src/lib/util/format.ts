/**
 * Weergaveregels die op meer dan één scherm gelden.
 *
 * Duur komt in milliseconden binnen en nooit in seconden; het contract is daar
 * stellig over. Tijden zijn RFC 3339 in UTC en worden in de tijdzone van de
 * lezer getoond.
 */
import type { Item } from '../api/types';
import { plural, t } from '../i18n';

export function formatDuration(ms: number | null | undefined): string | null {
  if (typeof ms !== 'number' || ms <= 0) return null;
  // Onder de minuut in seconden, want naar minuten afronden maakt van een
  // fragment van twee seconden "0m", en dat leest als "duur onbekend".
  if (ms < 60_000) return `${Math.max(1, Math.round(ms / 1000))}s`;
  const totalMinutes = Math.round(ms / 60000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours === 0) return `${minutes}m`;
  return `${hours}h ${minutes}m`;
}

export function formatDate(iso: string | null | undefined, locale = 'en'): string | null {
  if (!iso) return null;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  return new Intl.DateTimeFormat(locale, { dateStyle: 'medium' }).format(date);
}

export function formatCount(count: number, locale = 'en'): string {
  return new Intl.NumberFormat(locale).format(count);
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
