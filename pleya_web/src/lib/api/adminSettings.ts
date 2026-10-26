/**
 * De instellingen- en diagnoseroutes van het beheer (S10.5, schermen 28 tot
 * 32), in een eigen bestand zodat `admin.ts` er niet bij groeit.
 *
 * Alle routes zijn klasse `admin`; een lid krijgt 404 (hoofdstuk 7.1). Geheimen
 * komen in geen van de antwoorden voor: `Settings` kent geen geheim en
 * `GET /server/environment` maskeert wat de server zelf als geheim herkent.
 * De ondertekensleutel is nergens te lezen, ook niet gemaskeerd.
 */
import type { PleyaClient } from './client';
import type {
  ConnectivityCheck,
  LogLevel,
  MetadataAttentionList,
  MetadataMatch,
  ServerEnvironment,
  ServerLog,
  Settings,
  SettingsPatch
} from './types';

export function adminSettingsApi(client: PleyaClient) {
  return {
    settings: (signal?: AbortSignal): Promise<Settings> =>
      client.request((raw) => raw.GET('/settings', { signal })),

    /** Alleen de gewijzigde sleutels; de server wijst een onbekende sleutel af. */
    patchSettings: (body: SettingsPatch): Promise<Settings> =>
      client.request((raw) => raw.PATCH('/settings', { body })),

    environment: async (signal?: AbortSignal): Promise<ServerEnvironment['entries']> =>
      (await client.request((raw) => raw.GET('/server/environment', { signal }))).entries,

    log: async (
      level: LogLevel,
      limit: number,
      signal?: AbortSignal
    ): Promise<ServerLog['entries']> =>
      (
        await client.request((raw) =>
          raw.GET('/server/log', { params: { query: { level, limit } }, signal })
        )
      ).entries,

    /** Geen body: het doel is altijd het eigen publieke adres van de server. */
    checkConnectivity: (): Promise<ConnectivityCheck> =>
      client.request((raw) => raw.POST('/server/connectivity-check')),

    /** `confirm` is het vaste woord `rotate`; de server toetst dat zelf ook. */
    rotateSigningKey: (): Promise<true> =>
      client.request<true>(async (raw) => {
        const result = await raw.POST('/server/rotate-signing-key', { body: { confirm: 'rotate' } });
        return result.response.ok
          ? { data: true, response: result.response }
          : { error: result.error, response: result.response };
      }),

    metadataAttention: (limit: number, signal?: AbortSignal): Promise<MetadataAttentionList> =>
      client.request((raw) =>
        raw.GET('/metadata/attention', { params: { query: { limit } }, signal })
      ),

    /** Kiest de titel van de provider; 202, het ophalen gebeurt op de achtergrond. */
    setMetadataMatch: (itemId: string, externalId: string): Promise<MetadataMatch> =>
      client.request((raw) =>
        raw.PUT('/items/{item_id}/metadata-match', {
          params: { path: { item_id: itemId } },
          body: { external_id: externalId }
        })
      ),

    /** Wijst de match af; haalt weg wat de provider zette. Idempotent. */
    clearMetadataMatch: (itemId: string): Promise<MetadataMatch> =>
      client.request((raw) =>
        raw.DELETE('/items/{item_id}/metadata-match', { params: { path: { item_id: itemId } } })
      ),

    stopTranscodeSession: (sessionId: string): Promise<true> =>
      client.request<true>(async (raw) => {
        const result = await raw.DELETE('/transcode-sessions/{session_id}', {
          params: { path: { session_id: sessionId } }
        });
        return result.response.ok
          ? { data: true, response: result.response }
          : { error: result.error, response: result.response };
      })
  };
}

export type AdminSettingsApi = ReturnType<typeof adminSettingsApi>;
