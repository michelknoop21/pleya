/**
 * Welke navigatie-slots er bestaan.
 *
 * De northstar kent vijf slots in de volgorde Home, Series, Films, Boeken en Mijn Pleya.
 * Capabilities en de bibliotheken van de gebruiker bepalen welke er zijn, niet
 * een vaste tabel. Zegt `GET /info` dat bladeren er niet is, of heeft de
 * gebruiker geen boekenbibliotheek, dan bestaat het slot niet: er komt geen
 * uitgegrijsd item en geen scherm dat bij aankomst uitlegt dat het niet kan.
 *
 * Zoeken is geen slot maar een actie in de kop (TopNav en MobileHeader).
 * Films, Series en Boeken wijzen naar de enige bibliotheek van die soort, en
 * bij meer dan één naar het bibliotheekoverzicht. Dat zijn de routes die er
 * vandaag zijn; S8 en S9 geven ze eigen landingen zonder dat de schil
 * verandert.
 */
import type { Capabilities, Library } from '../api/types';
import { t } from '../i18n';

export type NavSlot = 'home' | 'films' | 'series' | 'books' | 'my';

export interface NavItem {
  id: NavSlot;
  href: string;
  label: string;
  icon: 'home' | 'movie' | 'show' | 'book' | 'person';
}

type LibraryRef = Pick<Library, 'id'> & { kind: string };

const KIND_SLOT: Record<string, NavSlot> = { movies: 'films', shows: 'series', books: 'books' };

function slotHref(libraries: LibraryRef[], kind: string): string {
  const matching = libraries.filter((l) => l.kind === kind);
  return matching.length === 1 ? `/libraries/${matching[0]!.id}` : '/libraries';
}

export function navItems(capabilities: Capabilities | null, libraries: LibraryRef[]): NavItem[] {
  const items: NavItem[] = [];
  const browse = capabilities?.browse === true;
  const has = (kind: string) => libraries.some((l) => l.kind === kind);

  if (browse) items.push({ id: 'home', href: '/', label: t('nav.home'), icon: 'home' });
  if (browse && has('shows')) {
    items.push({ id: 'series', href: slotHref(libraries, 'shows'), label: t('nav.series'), icon: 'show' });
  }
  if (browse && has('movies')) {
    items.push({ id: 'films', href: slotHref(libraries, 'movies'), label: t('nav.films'), icon: 'movie' });
  }
  if (browse && has('books')) {
    items.push({ id: 'books', href: slotHref(libraries, 'books'), label: t('nav.books'), icon: 'book' });
  }
  // Mijn Pleya leunt op GET /server en GET /info, en die zijn er altijd zodra
  // er een sessie is. Er zit geen capability onder omdat er geen capability
  // voor bestaat.
  items.push({ id: 'my', href: '/server', label: t('nav.my'), icon: 'person' });
  return items;
}

/**
 * Welk slot hoort bij dit pad. De langste treffer wint; een bibliotheekpagina
 * hoort bij het slot van haar soort, ook als dat slot naar het overzicht wijst.
 */
export function activeItemId(
  items: NavItem[],
  pathname: string,
  libraries: LibraryRef[] = []
): NavSlot | null {
  const libraryId = /^\/libraries\/([^/]+)/.exec(pathname)?.[1];
  if (libraryId) {
    const kind = libraries.find((l) => l.id === libraryId)?.kind;
    const slot = kind ? KIND_SLOT[kind] : undefined;
    if (slot && items.some((i) => i.id === slot)) return slot;
  }

  let best: NavItem | null = null;
  for (const item of items) {
    const matches = item.href === '/' ? pathname === '/' : pathname.startsWith(item.href);
    if (matches && (!best || item.href.length > best.href.length)) best = item;
  }
  return best?.id ?? null;
}
