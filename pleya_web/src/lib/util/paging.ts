/**
 * Cursorpaginering, zoals hoofdstuk 8 van de specificatie hem beschrijft.
 *
 * De cursor is ondoorzichtig en hoort bij één sortering. Verandert de
 * sortering, dan begint de lijst opnieuw; een oude cursor meesturen levert
 * `library.cursor_invalid` op, en dat is geen fout van de gebruiker maar een
 * lijst die van vorm veranderde.
 */
import type { Item } from '../api/types';
import { ApiError } from '../api/errors';

/** De gemeenschappelijke vorm van een pagina; `HistoryPage` kent geen schatting. */
export interface Page<T> {
  items: T[];
  next_cursor?: string | null;
  total_estimate?: number | null;
}

export type PageLoader<T = Item> = (cursor: string | undefined, signal: AbortSignal) => Promise<Page<T>>;

export interface PagerState<T = Item> {
  items: T[];
  cursor: string | null;
  totalEstimate: number | null;
  loading: boolean;
  done: boolean;
  error: unknown;
}

export function emptyPager<T = Item>(): PagerState<T> {
  return { items: [], cursor: null, totalEstimate: null, loading: false, done: false, error: null };
}

/**
 * Haalt de volgende pagina op en voegt hem achteraan toe.
 *
 * Geeft een nieuw toestandsobject terug in plaats van het bestaande te
 * wijzigen, zodat een component het als één waarde kan vervangen.
 *
 * Een ongeldige cursor wordt hier opgevangen en niet doorgegeven: de juiste
 * reactie is opnieuw bij het begin beginnen, en dat is wat de aanroeper met
 * `restarted` te horen krijgt.
 */
export async function loadNext<T = Item>(
  state: PagerState<T>,
  load: PageLoader<T>,
  signal: AbortSignal
): Promise<{ next: PagerState<T>; restarted: boolean }> {
  if (state.loading || state.done) return { next: state, restarted: false };

  const working: PagerState<T> = { ...state, loading: true, error: null };
  try {
    const page = await load(state.cursor ?? undefined, signal);
    return {
      next: {
        items: [...state.items, ...page.items],
        cursor: page.next_cursor ?? null,
        totalEstimate: page.total_estimate ?? state.totalEstimate,
        loading: false,
        done: !page.next_cursor,
        error: null
      },
      restarted: false
    };
  } catch (err) {
    if (err instanceof ApiError && err.code === 'library.cursor_invalid' && state.cursor) {
      return { next: emptyPager<T>(), restarted: true };
    }
    return { next: { ...working, loading: false, error: err }, restarted: false };
  }
}
