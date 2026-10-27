/**
 * De gegevens en rekenregels van Scans en taken (scherm 25).
 *
 * Bron: `GET /scans`, `GET /jobs`, `GET /libraries` en `GET /storage/roots`.
 * Wat het contract niet draagt staat er niet: een totaal aantal bestanden (dus
 * geen percentage en geen voortgangsbalk), het aantal werkers, wie een scan
 * afbrak en hoe ver die was, en een manier om een fout weg te zetten
 * (Overslaan). Afbreken bestaat wel, maar via de job van de scan:
 * `POST /jobs/{id}/cancel`, gevonden met `job.scan_id`.
 */
import type { AdminApi } from '../api/admin';
import type { PleyaClient } from '../api/client';
import type { Job, Library, Scan, StorageRoot } from '../api/types';
import type { PillTone } from '../components/StatusPill.svelte';
import { t, type MessageKey } from '../i18n';
import { formatBytes, formatClock, formatCount, formatDayClock, formatDuration } from '../util/format';
import { rootsOf, scanActive } from './libraries';
import { countLabel, libraryTitle } from './overview';

/** Zo vaak ververst de pagina zolang er iets loopt of wacht. */
export const ACTIVITY_POLL_MS = 5000;

const FIRST_PAGE = 20;
const JOB_WINDOW = 50;

export interface ActivityData {
  libraries: Library[];
  roots: StorageRoot[];
  scans: Scan[];
  /**
   * De laatste scan van elke bibliotheek, op id van de bibliotheek; null als hij
   * nooit gescand is. Apart gelezen en niet uit `scans` gehaald: dat zijn de
   * nieuwste twintig rondes van alle bibliotheken samen, en die kunnen de laatste
   * van één bibliotheek niet meer bevatten.
   */
  lastScans: Record<string, Scan | null>;
  /** Cursor voor de volgende pagina scans; null als dit de laatste was. */
  next: string | null;
  jobs: Job[];
}

export async function loadActivity(
  client: PleyaClient,
  api: AdminApi,
  signal?: AbortSignal
): Promise<ActivityData> {
  const [libraries, roots, page, jobs] = await Promise.all([
    client.libraries(signal),
    api.storageRoots(signal),
    api.scansPage(FIRST_PAGE, null, signal),
    api.jobs(JOB_WINDOW, signal)
  ]);
  const last = await Promise.all(libraries.map((l) => api.lastScan(l.id, signal)));
  const lastScans = Object.fromEntries(libraries.map((l, i) => [l.id, last[i] ?? null]));
  return { libraries, roots, scans: page.items, next: page.nextCursor, lastScans, jobs };
}

// --- Wat er nu loopt ------------------------------------------------------

export const SCAN_JOB_KIND = 'scan_library';

function jobActive(job: Job): boolean {
  return job.state === 'pending' || job.state === 'running';
}

/** De job achter een scan, zolang hij nog af te breken is. */
export function scanJob(jobs: Job[], scan: Scan): Job | null {
  return jobs.find((j) => j.scan_id === scan.id && jobActive(j)) ?? null;
}

export type RunningItem =
  | { kind: 'scan'; scan: Scan; library: string | null; job: Job | null }
  | { kind: 'job'; job: Job };

/**
 * Wachtende en lopende scans, en lopende taken van een andere soort. Een
 * scanjob komt er niet nog eens bij: de scan zelf is dezelfde gebeurtenis. Een
 * `pending` job staat er niet bij, want dat is ook een taak die pas morgen
 * draait; alleen wat nu loopt telt als bezig.
 */
export function runningItems(data: ActivityData): RunningItem[] {
  const scans: RunningItem[] = data.scans
    .filter((s) => scanActive(s))
    .map((scan) => ({
      kind: 'scan' as const,
      scan,
      library: libraryTitle(data.libraries, scan.library_id),
      job: scanJob(data.jobs, scan)
    }));
  const others: RunningItem[] = data.jobs
    .filter((j) => j.state === 'running' && j.kind !== SCAN_JOB_KIND)
    .map((job) => ({ kind: 'job' as const, job }));
  return [...scans, ...others];
}

/** Moet de pagina blijven verversen? Alleen als er echt iets loopt of nu aan de beurt is. */
export function isLive(data: ActivityData, now = Date.now()): boolean {
  return (
    data.scans.some((s) => scanActive(s)) ||
    data.jobs.some(
      (j) => j.state === 'running' || (j.state === 'pending' && Date.parse(j.run_at) <= now)
    )
  );
}

export function scanStats(scan: Scan): string[] {
  const parts = [
    t('admin.act.stat.seen', { files: countLabel('admin.files', scan.files_seen) }),
    t('admin.act.stat.new', { count: formatCount(scan.files_new) }),
    t('admin.act.stat.probed', { count: formatCount(scan.files_probed) }),
    t('admin.act.stat.renamed', { count: formatCount(scan.files_renamed) }),
    t('admin.act.stat.missing', { count: formatCount(scan.files_missing) }),
    t('admin.act.stat.hashed', { size: formatBytes(scan.bytes_hashed) })
  ];
  if (scan.error_count > 0) parts.push(countLabel('admin.act.stat.errors', scan.error_count));
  return parts;
}

export function startedLine(scan: Scan, now = Date.now()): string {
  const at = formatClock(scan.started_at) ?? '';
  if (scan.state === 'queued') return t('admin.act.running.waiting', { at });
  const elapsed = formatDuration(Math.max(0, now - Date.parse(scan.started_at))) ?? '';
  return t('admin.act.running.started', { at, elapsed });
}

// --- Fouten ---------------------------------------------------------------

export type FailureItem =
  | { kind: 'job'; job: Job; library: string | null }
  | { kind: 'scan'; library: Library; scan: Scan }
  | { kind: 'root'; root: StorageRoot };

/**
 * Bibliotheken waarvan de laatste scanronde `failed` is, nieuwste eerst.
 *
 * Alleen de laatste: een mislukte ronde met een nieuwere erachter (de server
 * herstartte tijdens een scan, de volgende start deed hem over) is geen werk voor
 * de beheerder, en een lijst met elke herstart erin zou dat zeggen. Daarom ook
 * geen vergelijking op de tekst van `last_error`. Een bibliotheek met een
 * mislukte scanjob staat er al als job (met Nu opnieuw) en komt hier niet nog
 * eens bij, en een bibliotheek met een root die niet gemount is staat er al als
 * root (met Opslag): scannen helpt dan niet en de oorzaak staat er al.
 */
export function failedScanItems(data: ActivityData): FailureItem[] {
  const items: Extract<FailureItem, { kind: 'scan' }>[] = [];
  for (const library of data.libraries) {
    const scan = data.lastScans[library.id];
    if (!scan || scan.state !== 'failed') continue;
    if (data.jobs.some((j) => j.kind === SCAN_JOB_KIND && j.state === 'failed' && j.library_id === library.id))
      continue;
    if (rootsOf(data.roots, library.id).some((r) => !r.mounted)) continue;
    items.push({ kind: 'scan', library, scan });
  }
  return items.sort(
    (a, b) =>
      Date.parse(b.scan.finished_at ?? b.scan.started_at) -
      Date.parse(a.scan.finished_at ?? a.scan.started_at)
  );
}

/**
 * Mislukte taken, nieuwste eerst, dan bibliotheken met een mislukte laatste scan,
 * en daarna de roots die niet gemount zijn.
 * De server kent geen "afgehandeld": een mislukte job blijft staan tot hij
 * opnieuw is geprobeerd, binnen de laatste vijftig jobs die de lijst toont.
 */
export function failureItems(data: ActivityData): FailureItem[] {
  const jobs = data.jobs
    .filter((j) => j.state === 'failed')
    .sort(
      (a, b) =>
        Date.parse(b.finished_at ?? b.created_at) - Date.parse(a.finished_at ?? a.created_at)
    )
    .map((job) => ({ kind: 'job' as const, job, library: libraryTitle(data.libraries, job.library_id) }));
  const roots = data.roots
    .filter((r) => !r.mounted)
    .map((root) => ({ kind: 'root' as const, root }));
  return [...jobs, ...failedScanItems(data), ...roots];
}

/** Het tijdstip van een mislukte ronde: wanneer hij stopte, anders wanneer hij begon. */
export function failedScanWhen(scan: Scan, now = Date.now()): string {
  return formatDayClock(scan.finished_at ?? scan.started_at, now) ?? '';
}

/** Wat de server over de mislukte ronde zei, of dat hij niets zei. */
export function failedScanDetail(scan: Scan): string {
  return scan.last_error?.trim() || t('admin.act.failures.noMessage');
}

const JOB_FAILED: Record<string, MessageKey> = {
  storage_recheck_roots: 'admin.act.job.recheck',
  download_digest: 'admin.act.job.digest',
  backup_create: 'admin.act.job.backupCreate',
  backup_verify: 'admin.act.job.backupVerify'
};

const JOB_RUNNING: Record<string, MessageKey> = {
  storage_recheck_roots: 'admin.act.job.runningTitle.recheck',
  download_digest: 'admin.act.job.runningTitle.digest',
  backup_create: 'admin.act.job.runningTitle.backupCreate',
  backup_verify: 'admin.act.job.runningTitle.backupVerify'
};

/** De naam van een mislukte job; een soort die we niet kennen komt als `kind` mee. */
export function failedJobTitle(job: Job, library: string | null): string {
  if (job.kind === SCAN_JOB_KIND) {
    return library ? t('admin.act.job.scan', { library }) : t('admin.act.job.scanUnknown');
  }
  return t(JOB_FAILED[job.kind] ?? 'admin.act.job.generic');
}

export function runningJobTitle(job: Job): string {
  const key = JOB_RUNNING[job.kind];
  return key ? t(key) : job.kind;
}

export function failureDetail(job: Job): string {
  return job.last_error?.trim() || t('admin.act.failures.noMessage');
}

export function attemptsLine(job: Job): string {
  return t('admin.act.failures.attempts', { attempts: job.attempts, max: job.max_attempts });
}

// --- Alles scannen --------------------------------------------------------

export interface ScanPlan {
  start: Library[];
  /** Bibliotheken met een root die niet gemount is: scannen heeft dan geen zin. */
  skipped: Library[];
  /** Bibliotheken waarvan we al weten dat er een scan wacht of loopt. */
  running: Library[];
}

export function planScanAll(data: ActivityData): ScanPlan {
  const plan: ScanPlan = { start: [], skipped: [], running: [] };
  for (const library of data.libraries) {
    const roots = rootsOf(data.roots, library.id);
    const latest = data.scans.find((s) => s.library_id === library.id);
    if (roots.some((r) => !r.mounted)) plan.skipped.push(library);
    else if (scanActive(latest)) plan.running.push(library);
    else plan.start.push(library);
  }
  return plan;
}

// --- Geschiedenis ---------------------------------------------------------

export interface HistoryRow {
  id: string;
  title: string;
  trigger: string;
  started: string;
  duration: string;
  result: string;
  tone: PillTone;
  state: string;
}

const STATE: Record<string, { tone: PillTone; label: MessageKey }> = {
  queued: { tone: 'idle', label: 'admin.act.state.queued' },
  running: { tone: 'run', label: 'admin.act.state.running' },
  done: { tone: 'ok', label: 'admin.act.state.done' },
  failed: { tone: 'err', label: 'admin.act.state.failed' },
  cancelled: { tone: 'idle', label: 'admin.act.state.cancelled' }
};

const TRIGGER: Record<string, MessageKey> = {
  manual: 'admin.act.history.manual',
  schedule: 'admin.act.history.schedule',
  startup: 'admin.act.history.startup'
};

export function scanResult(scan: Scan): string {
  const counts = [
    t('admin.act.stat.seen', { files: countLabel('admin.files', scan.files_seen) }),
    t('admin.act.stat.new', { count: formatCount(scan.files_new) }),
    t('admin.act.stat.missing', { count: formatCount(scan.files_missing) })
  ];
  if (scan.error_count > 0) counts.push(countLabel('admin.act.stat.errors', scan.error_count));
  if (scan.state === 'failed' && scan.last_error) return `${scan.last_error} · ${counts[0]}`;
  return counts.join(' · ');
}

export function historyRows(scans: Scan[], libraries: Library[], now = Date.now()): HistoryRow[] {
  const seen = new Set<string>();
  const rows: HistoryRow[] = [];
  for (const scan of scans) {
    // Een wachtende of lopende scan staat onder Bezig, zoals in de northstar.
    if (scanActive(scan)) continue;
    // Een volgende pagina kan een scan herhalen als de lijst intussen schoof.
    if (seen.has(scan.id)) continue;
    seen.add(scan.id);
    const library = libraryTitle(libraries, scan.library_id);
    const state = STATE[scan.state] ?? STATE['queued']!;
    const finished = scan.finished_at ? Date.parse(scan.finished_at) : null;
    const duration =
      finished === null
        ? t('admin.act.history.notFinished')
        : (formatDuration(Math.max(0, finished - Date.parse(scan.started_at))) ?? '');
    rows.push({
      id: scan.id,
      title: library ? t('admin.act.history.scan', { library }) : t('admin.act.history.scanUnknown'),
      trigger: TRIGGER[scan.trigger] ? t(TRIGGER[scan.trigger]!) : scan.trigger,
      started: formatDayClock(scan.started_at, now) ?? '',
      duration,
      result: scanResult(scan),
      tone: state.tone,
      state: t(state.label)
    });
  }
  return rows;
}
