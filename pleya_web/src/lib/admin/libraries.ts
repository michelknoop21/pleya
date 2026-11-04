/**
 * De gegevens en de rekenregels van bibliotheekbeheer (schermen 21 tot 23).
 *
 * `Library` draagt zelf geen roots: die staan aan de andere kant, in
 * `GET /storage/roots`, waar elke root zegt welke bibliotheek hem gebruikt.
 * Daar lezen de lijst en het formulier ze ook vandaan. Wat de northstar toont
 * en het contract niet levert (slug, versies, opslaggrootte, een
 * scanpercentage, toegang per gebruiker) staat hier niet en wordt ook niet
 * geraden.
 */
import type { AdminApi } from '../api/admin';
import type { PleyaClient } from '../api/client';
import type {
  CreateLibraryRequest,
  Library,
  LibraryKind,
  MetadataCoverage,
  Scan,
  StorageRoot,
  UpdateLibraryRequest
} from '../api/types';
import type { SelectOption } from '../components/Select.svelte';
import { t, type MessageKey } from '../i18n';
import { formatCount, formatRelative } from '../util/format';
import { countLabel } from './overview';

export const LIBRARY_KINDS: readonly LibraryKind[] = ['movies', 'shows'];

/** Zo vaak vraagt de lijst de stand van een wachtende of lopende scan op. */
export const SCAN_POLL_MS = 4000;

export interface LibrariesData {
  libraries: Library[];
  roots: StorageRoot[];
  /** De laatste scan per bibliotheek-id; null als hij nooit gescand is. */
  scans: Record<string, Scan | null>;
}

export async function loadLibraries(
  client: PleyaClient,
  api: AdminApi,
  signal?: AbortSignal
): Promise<LibrariesData> {
  const [libraries, roots] = await Promise.all([
    client.libraries(signal),
    api.storageRoots(signal)
  ]);
  const scans = await Promise.all(libraries.map((l) => api.lastScan(l.id, signal)));
  return {
    libraries,
    roots,
    scans: Object.fromEntries(libraries.map((l, i) => [l.id, scans[i] ?? null]))
  };
}

export interface LibraryDetail {
  /** Null bij een nieuwe bibliotheek, en als het id niet (meer) bestaat. */
  library: Library | null;
  missing: boolean;
  roots: StorageRoot[];
  scan: Scan | null;
  coverage: MetadataCoverage | null;
}

/**
 * Alles voor scherm 22. Er is geen `GET /libraries/{id}`, dus de bibliotheek
 * komt uit de lijst. De dekking is bijzaak: kent de server hem niet of faalt
 * hij, dan valt alleen de regel Sidecars weg en niet het hele scherm.
 */
export async function loadLibraryDetail(
  client: PleyaClient,
  api: AdminApi,
  id: string | null,
  signal?: AbortSignal
): Promise<LibraryDetail> {
  const [libraries, roots] = await Promise.all([
    id ? client.libraries(signal) : Promise.resolve([] as Library[]),
    api.storageRoots(signal)
  ]);
  const library = id ? (libraries.find((l) => l.id === id) ?? null) : null;
  if (!library) return { library: null, missing: id !== null, roots, scan: null, coverage: null };
  const [scan, coverage] = await Promise.all([
    api.lastScan(library.id, signal),
    api.metadataCoverage(library.id, signal).catch(() => null)
  ]);
  return { library, missing: false, roots, scan, coverage };
}

export function rootsOf(roots: StorageRoot[], libraryId: string): StorageRoot[] {
  return roots.filter((r) => r.libraries.some((l) => l.id === libraryId));
}

export function isConfigManaged(library: Library): boolean {
  return library.managed === 'config';
}

export function scanActive(scan: Scan | null | undefined): boolean {
  return scan?.state === 'queued' || scan?.state === 'running';
}

export function kindLabel(kind: string): string {
  if (kind === 'movies') return t('nav.films');
  if (kind === 'shows') return t('nav.series');
  return t('admin.lib.kind.unknown');
}

export interface ScanSummary {
  tone: 'ok' | 'warn' | 'err' | 'run' | 'idle';
  text: string;
}

/** De cel "Laatste scan": een stip in de toon en een korte regel. */
export function scanSummary(scan: Scan | null | undefined, now = Date.now()): ScanSummary {
  if (!scan) return { tone: 'idle', text: t('admin.lib.scan.never') };
  const when = formatRelative(scan.finished_at ?? scan.started_at, now) ?? '';
  switch (scan.state) {
    case 'queued':
      return { tone: 'run', text: t('admin.lib.scan.queued') };
    case 'running':
      return {
        tone: 'run',
        text: t('admin.lib.scan.running', { files: countLabel('admin.files', scan.files_seen) })
      };
    case 'done':
      return {
        tone: 'ok',
        text:
          scan.items_created > 0
            ? t('admin.lib.scan.doneNew', { when, count: formatCount(scan.items_created) })
            : when
      };
    case 'failed':
      return { tone: 'err', text: t('admin.lib.scan.failed', { when }) };
    default:
      return { tone: 'idle', text: t('admin.lib.scan.cancelled', { when }) };
  }
}

// --- Scaninterval -------------------------------------------------------

/** De vaste keuzes; een andere waarde van de server krijgt een eigen regel. */
export const INTERVAL_PRESETS = [3600, 21600, 43200, 86400, 604800] as const;

/** Leeg betekent: de globale scaninterval van de server (`null` op de lijn). */
export const INTERVAL_DEFAULT = '';

export function intervalLabel(seconds: number): string {
  if (seconds === 86400) return t('admin.lib.interval.day');
  if (seconds === 604800) return t('admin.lib.interval.week');
  if (seconds % 3600 === 0) return countLabel('admin.lib.interval.hours', seconds / 3600);
  if (seconds % 60 === 0) return countLabel('admin.lib.interval.minutes', seconds / 60);
  return countLabel('admin.lib.interval.seconds', seconds);
}

export function intervalOptions(current: string): SelectOption[] {
  const values: number[] = [...INTERVAL_PRESETS];
  const own = Number(current);
  if (current !== INTERVAL_DEFAULT && !values.includes(own)) values.push(own);
  return [
    { value: INTERVAL_DEFAULT, label: t('admin.lib.interval.default') },
    ...values.sort((a, b) => a - b).map((s) => ({ value: String(s), label: intervalLabel(s) }))
  ];
}

// --- Opslagroots in het formulier ---------------------------------------

export interface RootChoice {
  root: StorageRoot;
  /** Titel van de andere bibliotheek die deze root al gebruikt. */
  takenBy: string | null;
}

/**
 * Elke root uit de opsomming van de server, met wie hem al heeft. Een root
 * van een andere bibliotheek is niet te kiezen: de server weigert overlap
 * (`storage.root_not_offered`), en dat hoort niemand pas na Opslaan te horen.
 */
export function rootChoices(roots: StorageRoot[], libraryId: string | null): RootChoice[] {
  return roots.map((root) => {
    const other = root.libraries.find((l) => l.id !== libraryId);
    return { root, takenBy: other?.title ?? null };
  });
}

/** Waarom een zelf ingetypte map niet wordt toegevoegd, vóór er iets naar de server gaat. */
export type NewRootProblem = 'empty' | 'relative' | 'trailing' | 'dots' | 'double' | 'nul' | 'duplicate';

/**
 * Dezelfde regels als de server voor `invalid_path` (genormaliseerd en
 * absoluut), plus dubbel. De server blijft de bron van waarheid voor overlap
 * en voor wat onder een aangeboden mount valt; dat weet de client niet.
 */
export function newRootProblem(raw: string, selected: string[]): NewRootProblem | null {
  const path = raw.trim();
  if (path === '') return 'empty';
  if (path.includes('\0')) return 'nul';
  if (!path.startsWith('/')) return 'relative';
  if (path.includes('//')) return 'double';
  if (path.split('/').some((part) => part === '..' || part === '.')) return 'dots';
  if (path.length > 1 && path.endsWith('/')) return 'trailing';
  if (selected.includes(path)) return 'duplicate';
  return null;
}

/**
 * De ouder-map waar de getoonde roots onder hangen, voor het voorbeeld in de
 * hint. De meest voorkomende ouder wint; zonder roots is er geen voorbeeld,
 * want een pad verzinnen is erger dan er geen noemen.
 */
export function rootParentExample(roots: StorageRoot[]): string | null {
  const counts = new Map<string, number>();
  for (const { path } of roots) {
    const at = path.lastIndexOf('/');
    if (at <= 0) continue;
    const parent = path.slice(0, at);
    counts.set(parent, (counts.get(parent) ?? 0) + 1);
  }
  let best: string | null = null;
  let bestCount = 0;
  for (const [parent, count] of counts) {
    if (count > bestCount) {
      best = parent;
      bestCount = count;
    }
  }
  return best;
}

/** Gekozen paden die de server niet in `roots` heeft: de zelf toegevoegde mappen. */
export function addedRoots(roots: StorageRoot[], selected: string[]): string[] {
  const known = new Set(roots.map((r) => r.path));
  return selected.filter((p) => !known.has(p));
}

// --- Formulier ----------------------------------------------------------

export interface LibraryForm {
  title: string;
  kind: string;
  roots: string[];
  /** Seconden als tekst, of INTERVAL_DEFAULT. */
  interval: string;
  scanOnStart: boolean;
}

export function emptyForm(): LibraryForm {
  return { title: '', kind: 'movies', roots: [], interval: INTERVAL_DEFAULT, scanOnStart: true };
}

export function formFromLibrary(library: Library, roots: StorageRoot[]): LibraryForm {
  const seconds = library.scan_interval_seconds;
  return {
    title: library.title,
    kind: library.kind,
    roots: rootsOf(roots, library.id)
      .map((r) => r.path)
      .sort(),
    interval: typeof seconds === 'number' ? String(seconds) : INTERVAL_DEFAULT,
    scanOnStart: library.scan_on_start ?? true
  };
}

export function formValid(form: LibraryForm): boolean {
  return form.title.trim() !== '' && form.roots.length > 0 && LIBRARY_KINDS.includes(form.kind as LibraryKind);
}

function sameRoots(a: string[], b: string[]): boolean {
  const left = [...a].sort();
  const right = [...b].sort();
  return left.length === right.length && left.every((p, i) => p === right[i]);
}

/** Alleen wat veranderd is: de PATCH laat de rest staan. */
export function updateBody(original: LibraryForm, form: LibraryForm): UpdateLibraryRequest {
  const body: UpdateLibraryRequest = {};
  const title = form.title.trim();
  if (title !== original.title) body.title = title;
  if (form.kind !== original.kind) body.kind = form.kind as LibraryKind;
  if (!sameRoots(form.roots, original.roots)) body.root_paths = [...form.roots].sort();
  if (form.interval !== original.interval) {
    body.scan_interval_seconds = form.interval === INTERVAL_DEFAULT ? null : Number(form.interval);
  }
  if (form.scanOnStart !== original.scanOnStart) body.scan_on_start = form.scanOnStart;
  return body;
}

export function createBody(form: LibraryForm): CreateLibraryRequest {
  const body: CreateLibraryRequest = {
    title: form.title.trim(),
    kind: form.kind as LibraryKind,
    root_paths: [...form.roots].sort(),
    scan_on_start: form.scanOnStart
  };
  if (form.interval !== INTERVAL_DEFAULT) body.scan_interval_seconds = Number(form.interval);
  return body;
}

/** De sleutel van het bijschrift onder de soort. */
export function kindHint(itemCount: number): MessageKey {
  return itemCount > 0 ? 'admin.lib.form.kindLocked' : 'admin.lib.form.kindFree';
}
