/**
 * Rekenregels voor de toestellenlijsten van scherm 27 en 31 (DEC-164).
 *
 * Drie dingen, allemaal zonder eigen route: het contract kent alleen
 * `DELETE /sessions/{id}`, dus opruimen en "Overal uitloggen" zijn een rij
 * losse intrekkingen.
 *
 * - `deviceLabel`: de naam van een toestel, met "Onbekend toestel" voor de
 *   Engelse plaatshouder die de server geeft als een client geen naam stuurde.
 * - `staleSessions`: welke sessies langer dan N dagen niet gezien zijn. Nooit
 *   het toestel waarmee je nu kijkt, nooit een API-token.
 * - `revokeEach`: trekt een lijst één voor één in, gaat door na een fout, en
 *   zegt achteraf wat lukte en wat niet.
 */
import { ApiError } from '../api/errors';
import type { UserSession } from '../api/adminUsers';
import { t } from '../i18n';
import { formatDate } from '../util/format';

/** De plaatshouder uit `handlers_auth.go` voor een sessie zonder toestelnaam. */
export const UNKNOWN_DEVICE_NAME = 'Unknown device';

export const CLEANUP_PERIODS = [30, 60, 90] as const;
export type CleanupPeriod = (typeof CLEANUP_PERIODS)[number];
export const DEFAULT_CLEANUP_PERIOD: CleanupPeriod = 30;

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * De naam zoals een beheerder hem leest. Zonder naam van de client staat er
 * "Onbekend toestel", en met `withDate` de dag van aanmelden erbij, want dat is
 * dan het enige dat twee zulke rijen uit elkaar houdt.
 */
export function isUnnamed(session: Pick<UserSession, 'device_name'>): boolean {
  const name = session.device_name.trim();
  return name === '' || name === UNKNOWN_DEVICE_NAME;
}

export function deviceLabel(session: Pick<UserSession, 'device_name' | 'created_at'>, withDate = false): string {
  if (!isUnnamed(session)) return session.device_name.trim();
  const date = formatDate(session.created_at);
  return withDate && date ? t('admin.devices.unknownSince', { date }) : t('admin.devices.unknown');
}

/** Valt deze sessie onder het opruimen? Een onleesbare datum telt als recent. */
export function isStale(session: UserSession, days: number, now = Date.now()): boolean {
  if (session.current || session.kind === 'api') return false;
  const seen = Date.parse(session.last_seen_at);
  if (Number.isNaN(seen)) return false;
  return now - seen > days * DAY_MS;
}

export function staleSessions<T>(
  items: readonly T[],
  sessionOf: (item: T) => UserSession,
  days: number,
  now = Date.now()
): T[] {
  return items.filter((item) => isStale(sessionOf(item), days, now));
}

export interface RevokeOutcome<T> {
  done: T[];
  failed: { item: T; error: unknown }[];
}

/**
 * Trekt de lijst één voor één in en stopt niet bij de eerste fout.
 *
 * Een sessie die al weg is (`auth.session_not_found`) telt als gelukt: wie
 * hem wilde uitloggen krijgt wat hij vroeg, en hem als mislukt melden zou om
 * een herhaling vragen die niets kan doen.
 */
export async function revokeEach<T>(
  items: readonly T[],
  revoke: (item: T) => Promise<unknown>,
  onprogress?: (settled: number, total: number) => void
): Promise<RevokeOutcome<T>> {
  const outcome: RevokeOutcome<T> = { done: [], failed: [] };
  for (const item of items) {
    try {
      await revoke(item);
      outcome.done.push(item);
    } catch (error) {
      if (error instanceof ApiError && error.code === 'auth.session_not_found') outcome.done.push(item);
      else outcome.failed.push({ item, error });
    }
    onprogress?.(outcome.done.length + outcome.failed.length, items.length);
  }
  return outcome;
}
