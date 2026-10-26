/**
 * De tien secties van serverbeheer, in de volgorde van de northstar
 * (`ADMIN_NAV` in docs/assets/pleya-web-northstar/src/build.mjs).
 *
 * Eén lijst voor de zijbalk vanaf 900 (AdminNav) en de mobiele index onder 900
 * (scherm 33), zodat die twee nooit uit elkaar lopen. Een sectie die nog geen
 * eigen route heeft valt op `routes/admin/[section]` en toont daar dat hij in
 * een volgend deel komt: niemand krijgt een dode link.
 */
import type { MessageKey } from '../i18n';

export type AdminSectionId =
  | 'overview'
  | 'libraries'
  | 'storage'
  | 'activity'
  | 'users'
  | 'media'
  | 'metadata'
  | 'network'
  | 'security'
  | 'diagnostics';

export type AdminIconName =
  | 'chart'
  | 'folder'
  | 'drive'
  | 'activity'
  | 'people'
  | 'play'
  | 'image'
  | 'globe'
  | 'shield'
  | 'cpu';

export interface AdminSection {
  id: AdminSectionId;
  href: string;
  label: MessageKey;
  icon: AdminIconName;
  /** Scherm 33 deelt de index in tweeën: beheer en instellingen. */
  group: 'manage' | 'settings';
}

export const ADMIN_ROOT = '/admin';

export const ADMIN_SECTIONS: readonly AdminSection[] = [
  { id: 'overview', href: ADMIN_ROOT, label: 'admin.nav.overview', icon: 'chart', group: 'manage' },
  { id: 'libraries', href: '/admin/libraries', label: 'admin.nav.libraries', icon: 'folder', group: 'manage' },
  { id: 'storage', href: '/admin/storage', label: 'admin.nav.storage', icon: 'drive', group: 'manage' },
  { id: 'activity', href: '/admin/activity', label: 'admin.nav.activity', icon: 'activity', group: 'manage' },
  { id: 'users', href: '/admin/users', label: 'admin.nav.users', icon: 'people', group: 'manage' },
  { id: 'media', href: '/admin/media', label: 'admin.nav.media', icon: 'play', group: 'settings' },
  { id: 'metadata', href: '/admin/metadata', label: 'admin.nav.metadata', icon: 'image', group: 'settings' },
  { id: 'network', href: '/admin/network', label: 'admin.nav.network', icon: 'globe', group: 'settings' },
  { id: 'security', href: '/admin/security', label: 'admin.nav.security', icon: 'shield', group: 'settings' },
  { id: 'diagnostics', href: '/admin/diagnostics', label: 'admin.nav.diagnostics', icon: 'cpu', group: 'settings' }
];

/**
 * Onder 900 is `/admin` de index (33) en heeft het overzicht (20) een eigen
 * adres; vanaf 900 is `/admin` zelf het overzicht. Beide adressen markeren
 * Overzicht als actief.
 */
export const ADMIN_OVERVIEW_PATH = '/admin/overview';

export function isAdminPath(pathname: string): boolean {
  return pathname === ADMIN_ROOT || pathname.startsWith(`${ADMIN_ROOT}/`);
}

export function sectionById(id: string): AdminSection | undefined {
  return ADMIN_SECTIONS.find((s) => s.id === id);
}

/** Welke sectie bij dit pad hoort; het langste passende adres wint. */
export function activeSectionId(pathname: string): AdminSectionId | null {
  if (!isAdminPath(pathname)) return null;
  if (pathname === ADMIN_ROOT || pathname === ADMIN_OVERVIEW_PATH) return 'overview';
  const hit = ADMIN_SECTIONS.find(
    (s) => s.href !== ADMIN_ROOT && (pathname === s.href || pathname.startsWith(`${s.href}/`))
  );
  return hit?.id ?? null;
}

/**
 * Waar de terugpijl van de mobiele kop heen wijst: vanuit de index terug naar
 * Pleya, vanuit een sectie terug naar de index, en vanuit een scherm binnen
 * een sectie (`/admin/libraries/{id}`) terug naar die sectie. Buiten beheer is
 * er geen terugkop en blijft het merk staan.
 */
export function adminBackHref(pathname: string): string | null {
  if (!isAdminPath(pathname)) return null;
  if (pathname === ADMIN_ROOT) return '/';
  const parent = ADMIN_SECTIONS.find(
    (s) => s.href !== ADMIN_ROOT && pathname.startsWith(`${s.href}/`)
  );
  return parent?.href ?? ADMIN_ROOT;
}
