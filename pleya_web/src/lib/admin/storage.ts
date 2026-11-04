/**
 * De gegevens en rekenregels van Opslag (scherm 24).
 *
 * Alles komt uit `GET /storage/roots`; alleen "scan bezig" leest daarnaast
 * `GET /scans`. Wat de northstar toont en het contract niet draagt staat hier
 * niet: sinds wanneer een root weg is, wanneer hij voor het laatst gezien
 * werd, en een vrije-ruimteverloop. De tijd "gezien 14:31" is dus weggelaten
 * en niet geschat.
 */
import type { AdminApi } from '../api/admin';
import type { Scan, StorageRoot } from '../api/types';
import type { PillTone } from '../components/StatusPill.svelte';
import { t, type MessageKey } from '../i18n';
import { formatBytes } from '../util/format';
import { scanActive } from './libraries';
import { countLabel, storageSummary } from './overview';

/** Onder dit aandeel vrij kleurt de balk amber. Een eigen keuze, geen contractwaarde. */
export const LOW_FREE_SHARE = 0.1;

/** Zoveel scans volstaan om te zien welke bibliotheek nu scant. */
const SCAN_WINDOW = 20;

/** Wachttijd voor de herlaadronde na `recheck`: de meting loopt via de jobwachtrij. */
export const RECHECK_REFRESH_MS = 3000;

export interface StorageData {
  roots: StorageRoot[];
  /** Ids van bibliotheken met een wachtende of lopende scan. */
  scanning: Set<string>;
}

export async function loadStorage(api: AdminApi, signal?: AbortSignal): Promise<StorageData> {
  const [roots, scans] = await Promise.all([api.storageRoots(signal), api.scans(SCAN_WINDOW, signal)]);
  return { roots, scanning: activeLibraryIds(scans) };
}

export function activeLibraryIds(scans: Scan[]): Set<string> {
  return new Set(scans.filter((s) => scanActive(s)).map((s) => s.library_id));
}

/** De regel onder de titel: "3 roots gemount · 1 niet bereikbaar · 3,2 TB vrij". */
export function storageHeadline(roots: StorageRoot[]): string {
  const summary = storageSummary(roots);
  const mounted = roots.filter((r) => r.mounted).length;
  const parts = [countLabel('admin.sto.summary.mounted', mounted)];
  if (summary.unmounted.length > 0) {
    parts.push(t('admin.sto.summary.unreachable', { count: summary.unmounted.length }));
  }
  parts.push(t('admin.sto.summary.free', { size: formatBytes(summary.free) }));
  return parts.join(' · ');
}

export interface RootSpace {
  /** False als de root niet gemount is of de server geen totaal meldt. */
  known: boolean;
  usedShare: number;
  low: boolean;
  text: string;
  /** Voor een schermlezer op de balk. */
  label: string;
}

export function rootSpace(root: StorageRoot): RootSpace {
  if (!root.mounted || root.total_bytes <= 0) {
    return {
      known: false,
      usedShare: 0,
      low: false,
      text: t('admin.sto.space.unknown'),
      label: t('admin.sto.space.unknown')
    };
  }
  const free = Math.min(root.free_bytes, root.total_bytes);
  const used = root.total_bytes - free;
  const freeBytes = formatBytes(free);
  const totalBytes = formatBytes(root.total_bytes);
  return {
    known: true,
    usedShare: Math.round((used / root.total_bytes) * 1000) / 10,
    low: free / root.total_bytes < LOW_FREE_SHARE,
    text: t('admin.sto.space.of', { free: freeBytes, total: totalBytes }),
    label: t('admin.sto.space.used', { used: formatBytes(used), total: totalBytes })
  };
}

export interface RootTrust {
  tone: PillTone;
  label: string;
  /** Waar het oordeel vandaan komt, plus wat de scanner dan doet. */
  detail: string;
}

const SOURCE_KEY: Record<string, MessageKey> = {
  measured: 'admin.sto.inode.measured',
  config_override: 'admin.sto.inode.config',
  fstype_default: 'admin.sto.inode.default'
};

export function rootTrust(root: StorageRoot): RootTrust {
  const source = t(SOURCE_KEY[root.inode_trust_source] ?? 'admin.sto.inode.unknown');
  if (root.inode_trusted) {
    return { tone: 'ok', label: t('admin.sto.inode.trusted'), detail: source };
  }
  return {
    tone: 'warn',
    label: t('admin.sto.inode.untrusted'),
    detail: `${source} · ${t('admin.sto.inode.signature')}`
  };
}

export function rootNotes(root: StorageRoot, scanning: Set<string>): string[] {
  const notes: string[] = [];
  if (root.libraries.length === 0) notes.push(t('admin.sto.root.unused'));
  if (root.libraries.some((l) => scanning.has(l.id))) notes.push(t('admin.sto.root.scanning'));
  return notes;
}

export function unmountedRoots(roots: StorageRoot[]): StorageRoot[] {
  return roots.filter((r) => !r.mounted);
}

/** Titels van de bibliotheken op deze roots, zonder dubbelen. */
export function libraryNames(roots: StorageRoot[]): string[] {
  return [...new Set(roots.flatMap((r) => r.libraries.map((l) => l.title)))];
}
