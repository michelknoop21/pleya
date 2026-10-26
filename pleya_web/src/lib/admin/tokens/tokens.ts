/**
 * De gegevens en rekenregels van Agents en API-tokens (scherm 34).
 *
 * Een token is een sessie met `kind: api` (RB-20). Het overzicht is dat van
 * alle gebruikers: `GET /users`, dan per gebruiker `GET /auth/api-tokens`, zoals
 * Beveiliging (31) dat voor toestellen doet. Een gebruiker wiens tokens niet te
 * lezen waren laat alleen zijn eigen rijen weg en wordt genoemd.
 *
 * Niet gebouwd omdat het contract het niet levert (de northstar toont het wel):
 * - het tokenvoorbeeld `plt_7f3a…c91e` (de server geeft nergens een voorvoegsel
 *   of id van het geheim terug, en het geheim zelf is na het aanmaken weg);
 * - "aanroepen vandaag" (geen teller);
 * - ingetrokken tokens in de lijst (de lijst bevat alleen levende tokens);
 * - de bereikomschrijving "scans en bibliotheken": `maintenance` is gereserveerd
 *   en onderscheidt zich vandaag in geen enkele operatie van `read`;
 * - MCP-transport, tooloverzicht, "Configuratie kopiëren" en uitzetten:
 *   `ServerDetail.mcp` kent alleen `enabled`, `url` en `tool_count`;
 * - de toolnaam en een leesbare omschrijving per beheeractie: `AuditEntry` heeft
 *   de `operation` (operationId), het `target` en de uitkomst, verder niets;
 * - een eigenaar kiezen bij het aanmaken: dat kan (`user_id`), maar de
 *   northstar tekent het veld niet, dus een token gaat altijd over jezelf.
 */
import type { AdminApi } from '../../api/admin';
import type { AdminTokensApi, ApiToken, ApiTokenScope, AuditEntry } from '../../api/adminTokens';
import type { PleyaClient } from '../../api/client';
import type { Role, ServerDetail, User } from '../../api/types';
import { plural, t, type MessageKey } from '../../i18n';
import { roleLabel } from '../users';

export interface TokenRow {
  token: ApiToken;
  owner: User;
}

export type McpStatus = NonNullable<ServerDetail['mcp']>;

export interface TokensData {
  rows: TokenRow[];
  users: User[];
  /** Gebruikers van wie de tokens niet te lezen waren. */
  unreadable: User[];
  /** Null als `GET /server` niet te lezen was; `undefined`-veld = server kent het object niet. */
  mcp: McpStatus | null;
  /** Null als `GET /audit` niet te lezen was. */
  audit: AuditEntry[] | null;
}

/** De bereiken van laag naar hoog; de volgorde van de keuzelijst. */
export const SCOPES: readonly ApiTokenScope[] = ['read', 'maintenance', 'admin'];

/** De geldigheden in de keuzelijst. Er is geen "nooit": het contract kent het niet. */
export const EXPIRY_DAYS: readonly number[] = [30, 90, 180, 365];
export const DEFAULT_EXPIRY_DAYS = 90;
export const AUDIT_LIMIT = 10;
export const NAME_MAX = 64;

export async function loadTokens(
  client: PleyaClient,
  api: AdminApi,
  tokensApi: AdminTokensApi,
  signal?: AbortSignal
): Promise<TokensData> {
  const [users, mcp, audit] = await Promise.all([
    api.users(signal),
    client.server(signal).then((s) => s.mcp ?? null).catch(() => null),
    tokensApi.audit('mcp', AUDIT_LIMIT, signal).catch(() => null)
  ]);
  // Eén aanvraag per gebruiker: het contract kent geen lijst over iedereen.
  const lists = await Promise.all(users.map((u) => tokensApi.tokensOf(u.id, signal).catch(() => null)));
  return {
    rows: sortRows(users.flatMap((owner, i) => (lists[i] ?? []).map((token) => ({ token, owner })))),
    users,
    unreadable: users.filter((_, i) => lists[i] === null),
    mcp,
    audit
  };
}

/** Het laatst gebruikte token eerst. */
export function sortRows(rows: TokenRow[]): TokenRow[] {
  return [...rows].sort((a, b) => Date.parse(b.token.last_seen_at) - Date.parse(a.token.last_seen_at));
}

export function scopeLabel(scope: string): string {
  return (SCOPES as readonly string[]).includes(scope) ? t(`admin.tok.scope.${scope}` as MessageKey) : scope;
}

export function scopeHint(scope: ApiTokenScope): string {
  return t(`admin.tok.scope.${scope}Hint` as MessageKey);
}

/** Een bereik dat de adminklasse haalt vraagt om een bevestiging met uitleg. */
export function isBroadScope(scope: string): boolean {
  return scope === 'admin';
}

export function ownerText(owner: User): string {
  return t('admin.tok.owner', { user: owner.username, role: roleLabel(owner.role as Role) });
}

const DAY = 86_400_000;

/** "over 89 dagen", of "verlopen" als de datum voorbij is. */
export function expiresText(iso: string, now = Date.now()): string {
  const left = Date.parse(iso) - now;
  if (Number.isNaN(left) || left <= 0) return t('admin.tok.expires.past');
  return plural('admin.tok.expires.days', Math.ceil(left / DAY));
}

export function nameProblem(name: string): MessageKey | null {
  return name.trim() === '' ? 'admin.tok.form.nameRequired' : null;
}

/** Wie of wat een auditregel deed: de naam van het token als dat nog leeft, anders de gebruiker. */
export function actorText(entry: AuditEntry, data: Pick<TokensData, 'rows' | 'users'>): string | null {
  const token = entry.session_id ? data.rows.find((r) => r.token.id === entry.session_id) : undefined;
  if (token) return token.token.name;
  const user = entry.user_id ? data.users.find((u) => u.id === entry.user_id) : undefined;
  return user?.username ?? null;
}
