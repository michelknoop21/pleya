/**
 * De gegevens en rekenregels van Media en streaming (scherm 28).
 *
 * Instelbaar zijn precies drie sleutels van `PATCH /settings`:
 * `max_stream_sessions`, `stream_session_ttl` en `stream_token_ttl`. Wat de
 * northstar verder tekent (hardwarekeuze, kwaliteitsladder, ondertitels bij
 * transcoderen, transcodemap met quotum, wie mag downloaden, kwaliteit van een
 * omgezette download) is geen instelling in deze server en staat hier dus niet:
 * het aantal gelijktijdige transcodes en de timeouts zijn omgevingsvariabelen en
 * worden alleen-lezen getoond.
 */
import type { AdminSettingsApi } from '../../api/adminSettings';
import type { AdminApi } from '../../api/admin';
import type { PleyaClient } from '../../api/client';
import type { ServerDetail, Settings, SettingsPatch, TranscodeSessionList, User } from '../../api/types';
import type { SelectOption } from '../../components/Select.svelte';
import { t } from '../../i18n';
import { MAX_STREAMS, parseMaxStreams, settingSeconds, toWireDuration } from './settings';

export const ENV_MAX_TRANSCODES = 'PLEYA_SERVER_TRANSCODE_MAX_SESSIONS';
export const ENV_FFPROBE_TIMEOUT = 'PLEYA_SERVER_FFPROBE_TIMEOUT';
export const ENV_JOB_WORKERS = 'PLEYA_SERVER_JOB_WORKERS';

export interface EnvEntry {
  key: string;
  value: string;
  redacted: boolean;
}

export interface MediaData {
  settings: Settings;
  server: ServerDetail;
  transcode: TranscodeSessionList;
  /** Null als de omgeving niet te lezen was; dan staat er "onbekend" en geen gok. */
  environment: EnvEntry[] | null;
  users: User[] | null;
}

export async function loadMedia(
  client: PleyaClient,
  settingsApi: AdminSettingsApi,
  api: AdminApi,
  signal?: AbortSignal
): Promise<MediaData> {
  const [settings, server, transcode, environment, users] = await Promise.all([
    settingsApi.settings(signal),
    client.server(signal),
    api.transcodeSessions(signal),
    settingsApi.environment(signal).catch(() => null),
    api.users(signal).catch(() => null)
  ]);
  return { settings, server, transcode, environment, users };
}

/** De waarde van een variabele; null als hij niet gezet is of de server hem maskeert. */
export function envValue(entries: EnvEntry[] | null, key: string): string | null {
  const hit = entries?.find((e) => e.key === key);
  return hit && !hit.redacted ? hit.value : null;
}

export interface MediaDraft {
  /** Seconden als tekst, de waarde van de keuzelijst. */
  sessionTtl: string;
  tokenTtl: string;
  maxStreams: string;
}

export function draftFrom(settings: Settings): MediaDraft {
  return {
    sessionTtl: String(settingSeconds(settings, 'stream_session_ttl') ?? ''),
    tokenTtl: String(settingSeconds(settings, 'stream_token_ttl') ?? ''),
    maxStreams: String(settings.max_stream_sessions.value)
  };
}

/** Alleen wat veranderd is; een ongewijzigd scherm geeft een lege patch. */
export function mediaPatch(settings: Settings, draft: MediaDraft): SettingsPatch {
  const patch: SettingsPatch = {};
  const session = Number(draft.sessionTtl);
  if (session > 0 && session !== settingSeconds(settings, 'stream_session_ttl')) {
    patch.stream_session_ttl = toWireDuration(session);
  }
  const token = Number(draft.tokenTtl);
  if (token > 0 && token !== settingSeconds(settings, 'stream_token_ttl')) {
    patch.stream_token_ttl = toWireDuration(token);
  }
  const max = parseMaxStreams(draft.maxStreams);
  if (max !== null && max !== settings.max_stream_sessions.value) patch.max_stream_sessions = max;
  return patch;
}

const MAX_PRESETS = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32];

export function maxStreamOptions(current: number): SelectOption[] {
  const values = new Set([...MAX_PRESETS.filter((n) => n >= MAX_STREAMS.min && n <= MAX_STREAMS.max), current]);
  return [...values]
    .sort((a, b) => a - b)
    .map((n) => ({ value: String(n), label: t('admin.media.streams.maxValue', { count: n }) }));
}

export function modeLabel(mode: string): string {
  switch (mode) {
    case 'remux':
      return t('admin.media.mode.remux');
    case 'direct_stream':
      return t('admin.media.mode.direct_stream');
    case 'transcode':
      return t('admin.media.mode.transcode');
    default:
      return mode;
  }
}

export function userName(users: User[] | null, id: string): string {
  return users?.find((u) => u.id === id)?.username ?? t('admin.media.transcode.unknownUser');
}
