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
  return { libraries, roots, scans: page.items, next: page.nextCursor, jobs };
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
  | { kind: 'root'; root: StorageRoot };

/**
 * Mislukte taken, nieuwste eerst, en daarna de roots die niet gemount zijn.
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
  return [...jobs, ...roots];
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
