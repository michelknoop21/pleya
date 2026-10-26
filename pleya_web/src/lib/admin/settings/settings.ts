/**
 * De rekenregels achter de instellingenschermen (S10.5): duren lezen en tonen,
 * de grenzen uit `openapi.yaml` (SettingsPatch), een patch die alleen bevat wat
 * veranderde, en de risico's die een bevestiging moet noemen.
 *
 * De server levert een duur als `time.Duration.String()` ("15m0s",
 * "720h0m0s") en neemt hem als `time.ParseDuration` ("15m", "720h"). Hier
 * wordt alles in seconden gerekend en voor het versturen terug naar `<n>h`,
 * `<n>m` of `<n>s` gebracht.
 */
import type { SelectOption } from '../../components/Select.svelte';
import type { MessageKey } from '../../i18n';
import { intlLocale, t } from '../../i18n';
import type { Settings, SettingsPatch } from '../../api/types';

export type DurationKey =
  | 'access_token_ttl'
  | 'refresh_token_ttl'
  | 'stream_token_ttl'
  | 'stream_session_ttl';

interface DurationRule {
  min: number;
  max: number;
  /** De keuzes in de lijst; de huidige waarde komt er altijd bij. */
  presets: number[];
}

const MIN = 60;
const HOUR = 3600;
const DAY = 86_400;

/** De grenzen uit `SettingsPatch`: 1m tot 60m, 24h tot 2160h, 1m tot 15m, 5m tot 120m. */
export const DURATION_RULES: Record<DurationKey, DurationRule> = {
  access_token_ttl: { min: MIN, max: 60 * MIN, presets: [5, 10, 15, 30, 60].map((m) => m * MIN) },
  refresh_token_ttl: {
    min: DAY,
    max: 90 * DAY,
    presets: [1, 7, 14, 30, 60, 90].map((d) => d * DAY)
  },
  stream_token_ttl: { min: MIN, max: 15 * MIN, presets: [1, 2, 5, 10, 15].map((m) => m * MIN) },
  stream_session_ttl: { min: 5 * MIN, max: 120 * MIN, presets: [5, 15, 30, 60, 120].map((m) => m * MIN) }
};

/** `max_stream_sessions`: 1 tot 32. */
export const MAX_STREAMS = { min: 1, max: 32 } as const;
/** `server_name`: 1 tot 64 tekens. `cors_origins`: ten hoogste zestien. */
export const SERVER_NAME_MAX = 64;
export const CORS_MAX = 16;

const PART = /(\d+(?:\.\d+)?)(h|m|s)/g;

/** "15m0s" naar 900; null bij iets wat geen duur is. */
export function parseDuration(text: string): number | null {
  const trimmed = text.trim();
  if (trimmed === '' || trimmed.replace(PART, '') !== '') return null;
  let total = 0;
  for (const match of trimmed.matchAll(PART)) {
    const n = Number(match[1]);
    total += n * (match[2] === 'h' ? HOUR : match[2] === 'm' ? MIN : 1);
  }
  return Math.round(total);
}

/** Seconden naar de kortste vorm die de server leest: `720h`, `15m` of `90s`. */
export function toWireDuration(seconds: number): string {
  if (seconds % HOUR === 0) return `${seconds / HOUR}h`;
  if (seconds % MIN === 0) return `${seconds / MIN}m`;
  return `${seconds}s`;
}

/** "15 minuten", "2 uur", "30 dagen": de grootste eenheid die heel uitkomt. */
export function durationLabel(seconds: number): string {
  const [unit, size] =
    seconds % DAY === 0 && seconds >= DAY
      ? (['day', DAY] as const)
      : seconds % HOUR === 0 && seconds >= HOUR
        ? (['hour', HOUR] as const)
        : seconds % MIN === 0
          ? (['minute', MIN] as const)
          : (['second', 1] as const);
  return new Intl.NumberFormat(intlLocale(), {
    style: 'unit',
    unit,
    unitDisplay: 'long'
  }).format(seconds / size);
}

export function durationOptions(key: DurationKey, current: number): SelectOption[] {
  const values = new Set([...DURATION_RULES[key].presets, current]);
  return [...values]
    .sort((a, b) => a - b)
    .map((seconds) => ({ value: String(seconds), label: durationLabel(seconds) }));
}

/** De duur van een instelling in seconden; een waarde die de server niet stuurt is null. */
export function settingSeconds(settings: Settings, key: DurationKey): number | null {
  return parseDuration(settings[key].value);
}

export function durationInRange(key: DurationKey, seconds: number): boolean {
  const { min, max } = DURATION_RULES[key];
  return seconds >= min && seconds <= max;
}

/** Een geheel getal binnen de grens, of null. */
export function parseMaxStreams(text: string): number | null {
  if (!/^\d+$/.test(text.trim())) return null;
  const n = Number(text);
  return n >= MAX_STREAMS.min && n <= MAX_STREAMS.max ? n : null;
}

/**
 * Een lijst uit een tekstvak: één per regel (een komma of spatie scheidt ook),
 * leeg weg, dubbel weg, volgorde behouden.
 */
export function parseList(text: string): string[] {
  const seen = new Set<string>();
  for (const part of text.split(/[\s,]+/)) {
    const value = part.trim();
    if (value !== '') seen.add(value);
  }
  return [...seen];
}

/** `schema://host[:poort]`, http of https, zonder pad, inloggegevens, query of fragment. */
export function isOrigin(text: string): boolean {
  try {
    const url = new URL(text);
    return (
      (url.protocol === 'http:' || url.protocol === 'https:') &&
      url.username === '' &&
      url.password === '' &&
      url.search === '' &&
      url.hash === '' &&
      (url.pathname === '/' || url.pathname === '') &&
      !text.endsWith('/') &&
      text === url.origin
    );
  } catch {
    return false;
  }
}

/** Absolute http(s)-URL zonder inloggegevens, query of fragment (public_url). */
export function isPublicUrl(text: string): boolean {
  try {
    const url = new URL(text);
    return (
      (url.protocol === 'http:' || url.protocol === 'https:') &&
      url.username === '' &&
      url.password === '' &&
      url.search === '' &&
      url.hash === ''
    );
  } catch {
    return false;
  }
}

export function sameList(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((value, i) => value === b[i]);
}

export const SETTING_FIELD_LABELS: Record<string, MessageKey> = {
  server_name: 'admin.set.field.server_name',
  access_token_ttl: 'admin.set.field.access_token_ttl',
  refresh_token_ttl: 'admin.set.field.refresh_token_ttl',
  stream_token_ttl: 'admin.set.field.stream_token_ttl',
  stream_session_ttl: 'admin.set.field.stream_session_ttl',
  max_stream_sessions: 'admin.set.field.max_stream_sessions',
  public_url: 'admin.set.field.public_url',
  web_origin: 'admin.set.field.web_origin',
  cors_origins: 'admin.set.field.cors_origins'
};

export function isEmptyPatch(patch: SettingsPatch): boolean {
  return Object.keys(patch).length === 0;
}

export interface Risk {
  key: MessageKey;
  params?: Record<string, string>;
  /** Een wijziging die jezelf kan buitensluiten krijgt de zware toon. */
  lockout: boolean;
}

/**
 * Wat een netwerkwijziging kan kosten. `pageOrigin` is waar de beheerder nu
 * kijkt: stelt hij een andere web-origin in, dan werkt deze pagina na het
 * opslaan mogelijk niet meer.
 */
export function networkRisks(patch: SettingsPatch, pageOrigin: string): Risk[] {
  const risks: Risk[] = [];
  if (patch.web_origin !== undefined) {
    risks.push(
      patch.web_origin !== '' && patch.web_origin !== pageOrigin
        ? { key: 'admin.net.risk.webOriginElsewhere', params: { page: pageOrigin, origin: patch.web_origin }, lockout: true }
        : { key: 'admin.net.risk.webOrigin', lockout: true }
    );
  }
  if (patch.cors_origins !== undefined) risks.push({ key: 'admin.net.risk.cors', lockout: true });
  if (patch.public_url !== undefined) risks.push({ key: 'admin.net.risk.publicUrl', lockout: false });
  return risks;
}

export function securityRisks(patch: SettingsPatch): Risk[] {
  const risks: Risk[] = [];
  if (patch.access_token_ttl !== undefined) risks.push({ key: 'admin.sec.risk.access', lockout: false });
  if (patch.refresh_token_ttl !== undefined) risks.push({ key: 'admin.sec.risk.refresh', lockout: false });
  return risks;
}

export function mediaRisks(patch: SettingsPatch): Risk[] {
  const risks: Risk[] = [];
  if (patch.stream_session_ttl !== undefined || patch.max_stream_sessions !== undefined) {
    risks.push({ key: 'admin.media.risk.sessions', lockout: false });
  }
  if (patch.stream_token_ttl !== undefined) risks.push({ key: 'admin.media.risk.token', lockout: false });
  return risks;
}

/** De omgevingsvariabele achter elke instelling: de waarde die geldt zolang niemand hem hier wijzigt. */
export const SETTING_ENV: Record<keyof Settings, string | null> = {
  server_name: 'PLEYA_SERVER_NAME',
  access_token_ttl: 'PLEYA_SERVER_ACCESS_TOKEN_TTL',
  refresh_token_ttl: 'PLEYA_SERVER_REFRESH_TOKEN_TTL',
  stream_token_ttl: 'PLEYA_SERVER_STREAM_TOKEN_TTL',
  stream_session_ttl: 'PLEYA_SERVER_STREAM_SESSION_TTL',
  /** Er is geen variabele voor; de laag `env` is hier de ingebouwde standaard. */
  max_stream_sessions: null,
  public_url: 'PLEYA_SERVER_PUBLIC_URL',
  web_origin: 'PLEYA_SERVER_WEB_ORIGIN',
  cors_origins: 'PLEYA_SERVER_CORS_ORIGINS'
};

/** Eén regel voor de bevestiging: "Toegangstoken geldig: 15 minuten". */
export function changeLine(key: string, value: unknown): string {
  const labelKey = SETTING_FIELD_LABELS[key];
  const label = labelKey ? t(labelKey) : key;
  let shown: string;
  if (Array.isArray(value)) {
    shown = value.length === 0 ? t('admin.set.cleared') : value.join(', ');
  } else if (typeof value === 'string' && key.endsWith('_ttl')) {
    const seconds = parseDuration(value);
    shown = seconds === null ? value : durationLabel(seconds);
  } else if (value === '') {
    shown = t('admin.set.cleared');
  } else {
    shown = String(value);
  }
  return `${label}: ${shown}`;
}

export function changeLines(patch: SettingsPatch): string[] {
  return Object.entries(patch).map(([key, value]) => changeLine(key, value));
}
