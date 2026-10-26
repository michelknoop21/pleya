/**
 * De gegevens van het beheeroverzicht (scherm 20) en de mobiele index (33).
 *
 * `loadOverview` haalt alles in één ronde op; de functies daaronder zijn puur
 * en rekenen er de tegels, de activiteit en de opslag uit. Er wordt niets
 * verzonnen: wat het contract niet levert (een scanpercentage, sinds wanneer
 * een root weg is, wat een app buiten de browser afspeelt) staat er niet.
 */
import type { AdminApi } from '../api/admin';
import { plural } from '../i18n';
import { formatCount } from '../util/format';
import type { PleyaClient } from '../api/client';
import type {
  Job,
  Library,
  Scan,
  ServerDetail,
  StorageRoot,
  StreamSessionSummary,
  TranscodeSessionList,
  User
} from '../api/types';

export interface OverviewData {
  server: ServerDetail;
  libraries: Library[];
  users: User[];
  scans: Scan[];
  jobs: Job[];
  roots: StorageRoot[];
  streams: StreamSessionSummary[];
  transcode: TranscodeSessionList;
}

/** Zoveel scans en jobs zijn genoeg voor de vijf regels activiteit. */
const SCAN_LIMIT = 5;
const JOB_LIMIT = 20;

export async function loadOverview(
  client: PleyaClient,
  api: AdminApi,
  signal?: AbortSignal
): Promise<OverviewData> {
  const [server, libraries, users, scans, jobs, roots, streams, transcode] = await Promise.all([
    client.server(signal),
    client.libraries(signal),
    api.users(signal),
    api.scans(SCAN_LIMIT, signal),
    api.jobs(JOB_LIMIT, signal),
    api.storageRoots(signal),
    api.streamSessions(signal),
    api.transcodeSessions(signal)
  ]);
  return { server, libraries, users, scans, jobs, roots, streams, transcode };
}

export interface StorageSummary {
  free: number;
  total: number;
  rootCount: number;
  unmounted: StorageRoot[];
}

/**
 * Vrije en totale ruimte over de gemounte roots.
 *
 * Meerdere roots kunnen op één bestandssysteem staan (op de NAS hangen Films,
 * Kids en Series onder één mount), en dan meldt elk dezelfde vrije ruimte.
 * Optellen zou die ruimte drie keer tellen. Het contract draagt geen id van
 * het bestandssysteem, dus roots met hetzelfde type en precies dezelfde vrije
 * en totale bytes tellen als één. Twee echt verschillende schijven die tot op
 * de byte gelijk zijn, is in de praktijk niet aan de orde.
 */
export function storageSummary(roots: StorageRoot[]): StorageSummary {
  const seen = new Set<string>();
  let free = 0;
  let total = 0;
  for (const root of roots) {
    if (!root.mounted) continue;
    const key = `${root.fs_type ?? ''}|${root.free_bytes}|${root.total_bytes}`;
    if (seen.has(key)) continue;
    seen.add(key);
    free += root.free_bytes;
    total += root.total_bytes;
  }
  return { free, total, rootCount: roots.length, unmounted: roots.filter((r) => !r.mounted) };
}

export function libraryTitle(libraries: Library[], id: string | undefined): string | null {
  if (!id) return null;
  return libraries.find((l) => l.id === id)?.title ?? null;
}

/** De scan die nu loopt of wacht; anders de laatste. Nieuwste eerst uit de server. */
export function currentScan(scans: Scan[]): { scan: Scan; active: boolean } | null {
  const active = scans.find((s) => s.state === 'running' || s.state === 'queued');
  if (active) return { scan: active, active: true };
  const last = scans[0];
  return last ? { scan: last, active: false } : null;
}

export type ActivityEntry =
  | { kind: 'scan'; at: string; scan: Scan; library: string | null }
  | { kind: 'job'; at: string; job: Job };

/**
 * De regels onder Activiteit: de laatste scans en de mislukte taken, nieuwste
 * eerst. Een geslaagde job staat er niet bij; dat is ruis naast de scans, en
 * een scanjob zou dezelfde gebeurtenis twee keer tonen.
 */
export function activity(data: OverviewData, limit = 5): ActivityEntry[] {
  const entries: ActivityEntry[] = [
    ...data.scans.map((scan) => ({
      kind: 'scan' as const,
      at: scan.started_at,
      scan,
      library: libraryTitle(data.libraries, scan.library_id)
    })),
    ...data.jobs
      .filter((job) => job.state === 'failed')
      .map((job) => ({ kind: 'job' as const, at: job.finished_at ?? job.created_at, job }))
  ];
  return entries.sort((a, b) => Date.parse(b.at) - Date.parse(a.at)).slice(0, limit);
}

/** Positie als percentage, alleen als de server beide waarden meldt. */
export function streamProgress(stream: StreamSessionSummary): number | null {
  const { position_ms: position, duration_ms: duration } = stream;
  if (typeof position !== 'number' || typeof duration !== 'number' || duration <= 0) return null;
  return Math.min(100, Math.max(0, Math.round((position / duration) * 100)));
}

/** Een meervoud met het getal in de notatie van de taal: "24.268 bestanden". */
export function countLabel(key: string, count: number): string {
  return plural(key, count, { count: formatCount(count) });
}
