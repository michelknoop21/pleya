/**
 * De routes van scherm 34 (S10.6): API-tokens en het auditlog.
 *
 * Een API-token is een sessie met `kind: api` (RB-20). Aanmaken en lijsten
 * horen bij `/auth/api-tokens` (klasse `authenticated`, met `user_id` van een
 * ander `admin`), intrekken gaat via `DELETE /sessions/{id}` en staat in
 * `adminUsers.ts`. `GET /audit` is klasse `admin`.
 *
 * Het geheim staat alleen in het antwoord van `createToken`. Niets hier bewaart
 * het: de aanroeper krijgt het terug en is zelf verantwoordelijk het te wissen.
 */
import type { components } from './schema';
import type { PleyaClient } from './client';

type S = components['schemas'];

export type ApiToken = S['ApiToken'];
export type ApiTokenScope = S['ApiTokenScope'];
export type ApiTokenCreated = S['ApiTokenCreated'];
export type ApiTokenRequest = S['ApiTokenRequest'];
export type AuditEntry = S['AuditEntry'];

export function adminTokensApi(client: PleyaClient) {
  return {
    /** De levende tokens van één gebruiker, zonder geheimen. */
    tokensOf: async (userId: string, signal?: AbortSignal): Promise<ApiToken[]> =>
      (
        await client.request((raw) =>
          raw.GET('/auth/api-tokens', { params: { query: { user_id: userId } }, signal })
        )
      ).items,

    /** Geeft het geheim terug, één keer. De server bewaart alleen de hash. */
    createToken: (body: ApiTokenRequest): Promise<ApiTokenCreated> =>
      client.request((raw) => raw.POST('/auth/api-tokens', { body })),

    /** De nieuwste regels van één bron (`mcp` of `http`), nieuwste eerst. */
    audit: async (
      source: 'http' | 'mcp',
      limit: number,
      signal?: AbortSignal
    ): Promise<AuditEntry[]> =>
      (
        await client.request((raw) =>
          raw.GET('/audit', { params: { query: { source, limit } }, signal })
        )
      ).items
  };
}

export type AdminTokensApi = ReturnType<typeof adminTokensApi>;
