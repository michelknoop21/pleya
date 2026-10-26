/**
 * De beheerroutes (klasse `admin`) die het beheeroppervlak leest.
 *
 * Los van `client.ts`, zodat de consumentenkant er niets van ziet en een test
 * aan één bestand kan zien welke paden beheerpaden zijn. Elke functie gaat via
 * `PleyaClient.request`, dus dezelfde token- en foutafhandeling als de rest.
 *
 * Een lid krijgt op al deze routes `404` (hoofdstuk 16.4 van de specificatie).
 * Dat is geen reden om ze dan maar te proberen: de schil vraagt ze alleen voor
 * een eigenaar of beheerder (`session.canAdminister`, S10.7).
 */
import type { PleyaClient } from './client';
import type {
  Job,
  Scan,
  StorageRoot,
  StreamSessionSummary,
  TranscodeSessionList,
  User
} from './types';

/** De paden hieronder, voor de test die bewijst dat een lid ze nooit raakt. */
export const ADMIN_PATHS = [
  '/users',
  '/scans',
  '/jobs',
  '/storage/roots',
  '/stream-sessions',
  '/transcode-sessions'
] as const;

export function adminApi(client: PleyaClient) {
  return {
    users: async (signal?: AbortSignal): Promise<User[]> =>
      (await client.request((raw) => raw.GET('/users', { signal }))).items,

    scans: async (limit: number, signal?: AbortSignal): Promise<Scan[]> =>
      (await client.request((raw) => raw.GET('/scans', { params: { query: { limit } }, signal })))
        .items,

    jobs: async (limit: number, signal?: AbortSignal): Promise<Job[]> =>
      (await client.request((raw) => raw.GET('/jobs', { params: { query: { limit } }, signal })))
        .items,

    storageRoots: async (signal?: AbortSignal): Promise<StorageRoot[]> =>
      (await client.request((raw) => raw.GET('/storage/roots', { signal }))).roots,

    streamSessions: async (signal?: AbortSignal): Promise<StreamSessionSummary[]> =>
      (await client.request((raw) => raw.GET('/stream-sessions', { signal }))).items,

    transcodeSessions: (signal?: AbortSignal): Promise<TranscodeSessionList> =>
      client.request((raw) => raw.GET('/transcode-sessions', { signal }))
  };
}

export type AdminApi = ReturnType<typeof adminApi>;
