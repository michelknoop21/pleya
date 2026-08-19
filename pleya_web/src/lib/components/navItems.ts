/**
 * Welke navigatie-items er bestaan.
 *
 * Capabilities bepalen de lijst, niet een vaste tabel. Zegt `GET /info` dat
 * zoeken er niet is, dan bestaat het item niet — er komt geen uitgegrijsd
 * item en geen scherm dat bij aankomst uitlegt dat het niet kan.
 */
import type { Capabilities } from '../api/types';
import { t } from '../i18n';

export interface NavItem {
  id: string;
  href: string;
  label: string;
  icon: 'home' | 'search' | 'library' | 'settings';
}

export function navItems(capabilities: Capabilities | null, libraryCount: number): NavItem[] {
  const items: NavItem[] = [];
  if (capabilities?.browse) {
    items.push({ id: 'home', href: '/', label: t('nav.home'), icon: 'home' });
  }
  if (capabilities?.search) {
    items.push({ id: 'search', href: '/search', label: t('nav.search'), icon: 'search' });
  }
  if (capabilities?.browse && libraryCount > 0) {
    items.push({ id: 'libraries', href: '/libraries', label: t('nav.libraries'), icon: 'library' });
  }
  // Het serveroverzicht leunt op GET /server en GET /info, en die zijn er
  // altijd zodra er een sessie is. Er zit geen capability onder omdat er geen
  // capability voor bestaat.
  items.push({ id: 'server', href: '/server', label: t('nav.server'), icon: 'settings' });
  return items;
}

/** Welk item hoort bij dit pad. De langste treffer wint. */
export function activeItemId(items: NavItem[], pathname: string): string | null {
  let best: NavItem | null = null;
  for (const item of items) {
    const matches = item.href === '/' ? pathname === '/' : pathname.startsWith(item.href);
    if (matches && (!best || item.href.length > best.href.length)) best = item;
  }
  return best?.id ?? null;
}
