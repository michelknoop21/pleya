/**
 * De gegevens en rekenregels van gebruikersbeheer (schermen 26 en 27).
 *
 * Wat het contract niet draagt staat hier niet en wordt niet geraden:
 * - Een `User` heeft geen aanmaakdatum, dus er staat geen "aangemaakt op".
 * - Er is geen leesroute voor de bibliotheekrechten van een gebruiker, alleen
 *   `PUT /users/{id}/permissions`. Het scherm kent de huidige rechten dus niet
 *   en vervangt ze alleen na een expliciete bevestiging.
 * - Laatst actief en toestellen komen uit `GET /sessions?user_id=`: de
 *   nieuwste `last_seen_at`, en het aantal sessies dat geen API-token is.
 */
import type { AdminApi } from '../api/admin';
import type { PleyaClient } from '../api/client';
import type { AdminUsersApi, LibraryPermission, UserSession } from '../api/adminUsers';
import type { Library, Role, User } from '../api/types';
import type { PillTone } from '../components/StatusPill.svelte';
import { t, type MessageKey } from '../i18n';
import { formatRelative } from '../util/format';

export const PASSWORD_MIN = 8;

/** De rollen die een beheerder mag toekennen; `owner` ontstaat alleen via setup. */
export const ASSIGNABLE_ROLES: readonly Role[] = ['admin', 'member', 'restricted'];

const RANK: Record<Role, number> = { restricted: 0, member: 1, admin: 2, owner: 3 };

export function roleLabel(role: Role): string {
  return t(`admin.users.role.${role}` as MessageKey);
}

export function roleHint(role: Role): string {
  return t(`admin.users.roleHint.${role}` as MessageKey);
}

export function roleTone(role: Role): PillTone {
  if (role === 'restricted') return 'warn';
  if (role === 'admin') return 'ok';
  return 'idle';
}

/** Staat de toegang van deze rol los van rechtenrijen (eigenaar en beheerder)? */
export function seesEverything(role: Role): boolean {
  return role === 'owner' || role === 'admin';
}

/** Een wijziging die rechten afneemt vraagt om een bevestiging. */
export function isLowering(from: Role, to: Role): boolean {
  return RANK[to] < RANK[from];
}

export function usernameProblem(username: string): MessageKey | null {
  return username.trim() === '' ? 'admin.users.form.usernameRequired' : null;
}

export function passwordProblem(password: string): MessageKey | null {
  return password.length < PASSWORD_MIN ? 'admin.users.form.passwordShort' : null;
}

// --- De lijst -----------------------------------------------------------

export interface UserEntry {
  user: User;
  /** Null als de sessies van deze gebruiker niet te lezen waren. */
  sessions: UserSession[] | null;
}

export interface UsersData {
  entries: UserEntry[];
}

export async function loadUsers(
  api: AdminApi,
  usersApi: AdminUsersApi,
  signal?: AbortSignal
): Promise<UsersData> {
  const users = await api.users(signal);
  // Eén aanvraag per gebruiker: het contract kent geen telling. Een mislukte
  // aanvraag laat alleen die rij "onbekend" zijn, niet de hele lijst.
  const sessions = await Promise.all(
    users.map((u) => usersApi.sessionsOf(u.id, signal).catch(() => null))
  );
  return { entries: users.map((user, i) => ({ user, sessions: sessions[i] ?? null })) };
}

export interface UserDetail {
  /** Null als het id niet (meer) bestaat: er is geen `GET /users/{id}`, dus de lijst beslist. */
  user: User | null;
  libraries: Library[];
  /** Null als de sessies van deze gebruiker niet te lezen waren. */
  sessions: UserSession[] | null;
}

export async function loadUserDetail(
  client: PleyaClient,
  api: AdminApi,
  usersApi: AdminUsersApi,
  id: string,
  signal?: AbortSignal
): Promise<UserDetail> {
  const [users, libraries] = await Promise.all([api.users(signal), client.libraries(signal)]);
  const user = users.find((u) => u.id === id) ?? null;
  if (!user) return { user: null, libraries, sessions: null };
  const sessions = await usersApi.sessionsOf(user.id, signal).catch(() => null);
  return { user, libraries, sessions };
}

export function deviceSessions(sessions: UserSession[]): UserSession[] {
  return sessions.filter((s) => s.kind !== 'api');
}

/** De nieuwste sessie, of null als er geen is. */
export function latestSession(sessions: UserSession[] | null): UserSession | null {
  if (!sessions || sessions.length === 0) return null;
  return sessions.reduce((a, b) => (Date.parse(b.last_seen_at) > Date.parse(a.last_seen_at) ? b : a));
}

/** "nu · Apple TV woonkamer", "nog nooit", of "onbekend". */
export function lastActiveText(sessions: UserSession[] | null, now = Date.now()): string {
  if (sessions === null) return t('admin.users.lastActive.unknown');
  const latest = latestSession(sessions);
  if (!latest) return t('admin.users.lastActive.never');
  const when = formatRelative(latest.last_seen_at, now) ?? '';
  return t('admin.users.lastActive.value', { when, device: latest.device_name });
}

/** Wat de kolom Bibliotheken zegt: de rol dekt alles, anders staat het per gebruiker. */
export function librariesText(role: Role): string {
  return seesEverything(role) ? t('admin.users.libs.all') : t('admin.users.libs.perUser');
}

// --- Bibliotheekrechten --------------------------------------------------

export type Rung = 'view' | 'download' | 'manage';
export const RUNGS: readonly Rung[] = ['view', 'download', 'manage'];
const LADDER: Record<Rung, number> = { view: 1, download: 2, manage: 3 };

/** Bibliotheek-id naar de hoogste trede; een bibliotheek zonder sleutel heeft niets. */
export type Grants = Record<string, Rung>;

export function grantsFrom(items: LibraryPermission[]): Grants {
  return Object.fromEntries(items.map((p) => [p.library_id, p.permission]));
}

/** Een trede is aangevinkt als de toegekende trede er minstens zo hoog is (de ladder). */
export function isGranted(grants: Grants, libraryId: string, rung: Rung): boolean {
  const have = grants[libraryId];
  return have !== undefined && LADDER[have] >= LADDER[rung];
}

/**
 * Een vinkje zetten of weghalen volgens de ladder uit DEC-119: downloaden
 * impliceert kijken, beheren impliceert beide. Wie een lagere trede weghaalt
 * haalt de hogere ook weg.
 */
export function toggleGrant(grants: Grants, libraryId: string, rung: Rung, checked: boolean): Grants {
  const next = { ...grants };
  if (checked) {
    next[libraryId] = rung;
    return next;
  }
  const below = RUNGS.filter((r) => LADDER[r] < LADDER[rung]).pop();
  if (below) next[libraryId] = below;
  else delete next[libraryId];
  return next;
}

/** Een beperkte gebruiker krijgt nooit beheren (DEC-119): terug naar downloaden. */
export function clampForRole(grants: Grants, role: Role): Grants {
  // Dezelfde verwijzing terug als er niets te klemmen valt: een effect dat dit
  // aanroept en het resultaat toewijst mag zichzelf niet opnieuw starten.
  if (role !== 'restricted' || !Object.values(grants).includes('manage')) return grants;
  return Object.fromEntries(
    Object.entries(grants).map(([id, rung]) => [id, rung === 'manage' ? 'download' : rung])
  ) as Grants;
}

/** De body van `PUT /users/{id}/permissions`: alleen bibliotheken die nog bestaan en een vinkje hebben. */
export function permissionsBody(grants: Grants, libraries: Library[]): LibraryPermission[] {
  return libraries.flatMap((l) => {
    const rung = grants[l.id];
    return rung ? [{ library_id: l.id, permission: rung }] : [];
  });
}

export function rungLabel(rung: Rung): string {
  return t(`admin.users.perm.${rung}` as MessageKey);
}

/** "Films: kijken en downloaden", voor de bevestiging voor het vervangen. */
export function grantLines(grants: Grants, libraries: Library[]): string[] {
  return permissionsBody(grants, libraries).map((p) => {
    const title = libraries.find((l) => l.id === p.library_id)?.title ?? p.library_id;
    const parts = RUNGS.filter((r) => LADDER[r] <= LADDER[p.permission]).map(rungLabel);
    return `${title}: ${parts.join(', ').toLowerCase()}`;
  });
}

// --- Opslaan van het scherm 27 ---------------------------------------------

export interface SavePlan {
  /** De nieuwe rol, of null als hij gelijk blijft. */
  role: Role | null;
  /** De lijst om te schrijven, of null als de rechten onaangeroerd blijven. */
  permissions: LibraryPermission[] | null;
  /** Neemt deze wijziging rechten af? */
  lowering: boolean;
  /** Vraagt dit plan om een bevestiging? */
  needsConfirm: boolean;
}

export function savePlan(input: {
  current: Role;
  chosen: Role;
  grants: Grants;
  touched: boolean;
  libraries: Library[];
}): SavePlan {
  const role = input.chosen !== input.current ? input.chosen : null;
  const finalRole = role ?? input.current;
  // Een eigenaar of beheerder heeft geen rechtenrijen; wat er ligt blijft dan
  // onaangeroerd en wordt ook niet geschreven.
  const permissions =
    input.touched && !seesEverything(finalRole)
      ? permissionsBody(clampForRole(input.grants, finalRole), input.libraries)
      : null;
  const lowering = role !== null && isLowering(input.current, role);
  return { role, permissions, lowering, needsConfirm: lowering || permissions !== null };
}

export function hasChanges(plan: SavePlan): boolean {
  return plan.role !== null || plan.permissions !== null;
}
