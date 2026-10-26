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
  CreateLibraryRequest,
  Job,
  Library,
  MetadataCoverage,
  Scan,
  StorageRoot,
  StreamSessionSummary,
  TranscodeSessionList,
  UpdateLibraryRequest,
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
      client.request((raw) => raw.GET('/transcode-sessions', { signal })),

    // --- Bibliotheken beheren (S10.2, schermen 21 tot 23) ----------------

    /** De laatste scan van één bibliotheek, of null als hij nooit gescand is. */
    lastScan: async (libraryId: string, signal?: AbortSignal): Promise<Scan | null> =>
      (
        await client.request((raw) =>
          raw.GET('/scans', { params: { query: { library_id: libraryId, limit: 1 } }, signal })
        )
      ).items[0] ?? null,

    startScan: (libraryId: string): Promise<Scan> =>
      client.request((raw) =>
        raw.POST('/libraries/{library_id}/scan', { params: { path: { library_id: libraryId } } })
      ),

    createLibrary: (body: CreateLibraryRequest): Promise<Library> =>
      client.request((raw) => raw.POST('/libraries', { body })),

    updateLibrary: (libraryId: string, body: UpdateLibraryRequest): Promise<Library> =>
      client.request((raw) =>
        raw.PATCH('/libraries/{library_id}', { params: { path: { library_id: libraryId } }, body })
      ),

    adoptLibrary: (libraryId: string): Promise<Library> =>
      client.request((raw) =>
        raw.POST('/libraries/{library_id}/adopt', { params: { path: { library_id: libraryId } } })
      ),

    /**
     * `confirm` moet letterlijk de titel zijn (K rij 16); de server toetst dat
     * zelf ook. Een 204 heeft geen lichaam, en openapi-fetch geeft dan geen
     * `data`: zonder deze omweg zou `request` een geslaagde verwijdering als
     * onleesbaar antwoord melden.
     */
    deleteLibrary: (libraryId: string, confirm: string): Promise<true> =>
      client.request<true>(async (raw) => {
        const result = await raw.DELETE('/libraries/{library_id}', {
          params: { path: { library_id: libraryId } },
          body: { confirm }
        });
        return result.response.ok
          ? { data: true, response: result.response }
          : { error: result.error, response: result.response };
      }),

    metadataCoverage: (libraryId: string, signal?: AbortSignal): Promise<MetadataCoverage> =>
      client.request((raw) =>
        raw.GET('/libraries/{library_id}/metadata-coverage', {
          params: { path: { library_id: libraryId } },
          signal
        })
      )
  };
}

export type AdminApi = ReturnType<typeof adminApi>;
