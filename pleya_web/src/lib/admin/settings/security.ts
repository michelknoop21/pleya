/**
 * De gegevens en rekenregels van Beveiliging (scherm 31).
 *
 * Instelbaar zijn `access_token_ttl` en `refresh_token_ttl`. De ingelogde
 * toestellen komen uit `GET /sessions?user_id=` per gebruiker (hetzelfde als
 * scherm 26 en 27 doen) en gaan één voor één weg met `DELETE /sessions/{id}`.
 * De ondertekensleutel roteert met `POST /server/rotate-signing-key`.
 *
 * Niet gebouwd omdat het contract het niet levert: de paneelregels over het
 * wachtwoordalgoritme, het afremmen van pogingen en de setupcode (geen route
 * meldt dat), de app en het besturingssysteem per toestel (`Session` heeft
 * alleen `device_name`), en "streamt nu" (daarvoor is `GET /stream-sessions`
 * er, maar die koppelt niet aan een sessie-id).
 */
import type { AdminApi } from '../../api/admin';
import type { AdminSettingsApi } from '../../api/adminSettings';
import type { AdminUsersApi, UserSession } from '../../api/adminUsers';
import type { Settings, SettingsPatch, User } from '../../api/types';
import { deviceSessions, loadUsers } from '../users';
import { settingSeconds, toWireDuration } from './settings';

export interface DeviceRow {
  session: UserSession;
  user: User;
}

export interface SecurityData {
  settings: Settings;
  devices: DeviceRow[];
  /** Gebruikers van wie de sessies niet te lezen waren. */
  unreadable: User[];
}

export async function loadSecurity(
  api: AdminApi,
  usersApi: AdminUsersApi,
  settingsApi: AdminSettingsApi,
  signal?: AbortSignal
): Promise<SecurityData> {
  const [settings, devices] = await Promise.all([
    settingsApi.settings(signal),
    loadDevices(api, usersApi, signal)
  ]);
  return { settings, ...devices };
}

/**
 * Alleen de toestellen, voor na een intrekking. Een ingetypte tokenduur die nog
 * niet is opgeslagen blijft zo staan, wat een volledige herlaadbeurt niet doet.
 */
export async function loadDevices(
  api: AdminApi,
  usersApi: AdminUsersApi,
  signal?: AbortSignal
): Promise<Pick<SecurityData, 'devices' | 'unreadable'>> {
  const users = await loadUsers(api, usersApi, signal);
  return {
    devices: deviceRows(users.entries),
    unreadable: users.entries.filter((e) => e.sessions === null).map((e) => e.user)
  };
}

/** Elk toestel van elke gebruiker, het laatst gezien eerst. API-tokens horen er niet bij. */
export function deviceRows(entries: { user: User; sessions: UserSession[] | null }[]): DeviceRow[] {
  return entries
    .flatMap((e) => deviceSessions(e.sessions ?? []).map((session) => ({ session, user: e.user })))
    .sort((a, b) => Date.parse(b.session.last_seen_at) - Date.parse(a.session.last_seen_at));
}

export interface SecurityDraft {
  access: string;
  refresh: string;
}

export function draftFrom(settings: Settings): SecurityDraft {
  return {
    access: String(settingSeconds(settings, 'access_token_ttl') ?? ''),
    refresh: String(settingSeconds(settings, 'refresh_token_ttl') ?? '')
  };
}

export function securityPatch(settings: Settings, draft: SecurityDraft): SettingsPatch {
  const patch: SettingsPatch = {};
  const access = Number(draft.access);
  if (access > 0 && access !== settingSeconds(settings, 'access_token_ttl')) {
    patch.access_token_ttl = toWireDuration(access);
  }
  const refresh = Number(draft.refresh);
  if (refresh > 0 && refresh !== settingSeconds(settings, 'refresh_token_ttl')) {
    patch.refresh_token_ttl = toWireDuration(refresh);
  }
  return patch;
}
