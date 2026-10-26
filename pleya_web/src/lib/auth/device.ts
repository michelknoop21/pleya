/**
 * Wie deze browser is, voor de sessierij op de server (DEC-123, DEC-164).
 *
 * Twee velden op `LoginRequest` en `SetupRequest`, en alleen wanneer de server
 * `capabilities.sessions` adverteert: zonder die vlag kent een oudere server de
 * velden niet, en de bodies zijn gesloten.
 *
 * - `device_id` is een willekeurige id per browserprofiel, bewaard in
 *   `localStorage`. Hij zegt niets over de gebruiker of het toestel; hij maakt
 *   alleen dat dezelfde browser na uitloggen en opnieuw inloggen herkenbaar
 *   dezelfde blijft. Zonder opslag leeft hij zo lang als de pagina.
 * - `device_name` is wat een beheerder in de toestellenlijst leest: "Safari op
 *   macOS", "Chrome op Windows". Afgeleid van de browser, nooit de volledige
 *   User-Agent, en nooit langer dan `DEVICE_NAME_MAX`.
 */
import type { Capabilities } from '../api/types';
import { t } from '../i18n';

export const DEVICE_ID_KEY = 'pleya.device_id';

/**
 * Bovengrens voor de toestelnaam. Het schema `DeviceName` noemt alleen een
 * minimum; 64 is de grens van `server_name`, en een naam die langer is past in
 * geen enkele lijst op een telefoon.
 */
export const DEVICE_NAME_MAX = 64;

export interface DeviceStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

function defaultStorage(): DeviceStorage | null {
  try {
    return localStorage;
  } catch {
    return null;
  }
}

/** Een UUID v4 uit getRandomValues: randomUUID bestaat alleen in een secure context, en http://nas:8832 is dat niet. */
function randomId(): string {
  const bytes = new Uint8Array(16);
  try {
    crypto.getRandomValues(bytes);
  } catch {
    for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256);
  }
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

const ID_SHAPE = /^web-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

let pageId: string | null = null;

/** Alleen voor tests: vergeet de id die voor de levensduur van de pagina gold. */
export function resetPageDeviceId(): void {
  pageId = null;
}

/**
 * De id van dit browserprofiel. Leest en schrijft binnen try/catch: een
 * browser met opslag uit, of een privévenster dat gooit, krijgt een id voor de
 * levensduur van de pagina en geen fout.
 */
export function deviceId(storage: DeviceStorage | null = defaultStorage()): string {
  try {
    const stored = storage?.getItem(DEVICE_ID_KEY);
    if (stored && ID_SHAPE.test(stored)) return stored;
  } catch {
    // Lezen geweigerd: door naar een nieuwe id.
  }
  const fresh = pageId ?? `web-${randomId()}`;
  pageId = fresh;
  try {
    storage?.setItem(DEVICE_ID_KEY, fresh);
  } catch {
    // Schrijven geweigerd: de id geldt dan voor deze pagina.
  }
  return fresh;
}

/** Wat de browser over zichzelf zegt. Bewust smal: alleen wat de naam nodig heeft. */
export interface BrowserHints {
  userAgent?: string;
  /** `navigator.userAgentData`, waar die bestaat (Chromium). */
  userAgentData?: { brands?: { brand: string }[]; platform?: string; mobile?: boolean } | null;
  /** `navigator.maxTouchPoints`: een iPad doet zich in Safari voor als Mac. */
  maxTouchPoints?: number;
}

function browserFromBrands(brands: { brand: string }[]): string | null {
  const names = brands.map((b) => b.brand);
  if (names.some((n) => /Edge/i.test(n))) return 'Edge';
  if (names.some((n) => /Opera/i.test(n))) return 'Opera';
  if (names.some((n) => /Google Chrome/i.test(n))) return 'Chrome';
  if (names.some((n) => /Chromium/i.test(n))) return 'Chromium';
  return null;
}

function browserFromAgent(ua: string): string | null {
  if (/EdgiOS\/|Edg\//.test(ua)) return 'Edge';
  if (/OPR\/|Opera/.test(ua)) return 'Opera';
  if (/FxiOS\/|Firefox\//.test(ua)) return 'Firefox';
  if (/CriOS\/|Chrome\//.test(ua)) return 'Chrome';
  if (/Version\/[\d.]+.*Safari\//.test(ua)) return 'Safari';
  return null;
}

function platformFromHint(platform: string): string | null {
  if (/mac/i.test(platform)) return 'macOS';
  if (/win/i.test(platform)) return 'Windows';
  if (/android/i.test(platform)) return 'Android';
  if (/chrome ?os/i.test(platform)) return 'ChromeOS';
  if (/linux/i.test(platform)) return 'Linux';
  return null;
}

function platformFromAgent(ua: string, touchPoints: number): string | null {
  if (/iPhone|iPod/.test(ua)) return 'iPhone';
  if (/iPad/.test(ua)) return 'iPad';
  if (/Android/.test(ua)) return 'Android';
  if (/Windows/.test(ua)) return 'Windows';
  if (/CrOS/.test(ua)) return 'ChromeOS';
  if (/Macintosh|Mac OS X/.test(ua)) return touchPoints > 1 ? 'iPad' : 'macOS';
  if (/Linux/.test(ua)) return 'Linux';
  return null;
}

/** Kapt af op tekens en niet op UTF-16-eenheden, zodat er geen half teken overblijft. */
export function clampDeviceName(name: string, max = DEVICE_NAME_MAX): string {
  const chars = Array.from(name.trim());
  return chars.length <= max ? chars.join('') : chars.slice(0, max).join('').trimEnd();
}

/** "Safari op macOS", "Chrome op Windows", "Firefox op Linux", of "Browser". */
export function deviceName(hints: BrowserHints = currentHints()): string {
  const ua = hints.userAgent ?? '';
  const data = hints.userAgentData ?? null;
  const browser = (data?.brands ? browserFromBrands(data.brands) : null) ?? browserFromAgent(ua);
  // Een iPhone of iPad staat alleen in de User-Agent; userAgentData kent ze niet.
  const fromAgent = platformFromAgent(ua, hints.maxTouchPoints ?? 0);
  const platform =
    fromAgent === 'iPhone' || fromAgent === 'iPad'
      ? fromAgent
      : ((data?.platform ? platformFromHint(data.platform) : null) ?? fromAgent);

  let name: string;
  if (browser && platform) name = t('device.browserOn', { browser, platform });
  else if (platform) name = t('device.browserOn', { browser: t('device.browser'), platform });
  else name = browser ?? t('device.browser');
  return clampDeviceName(name) || t('device.browser');
}

function currentHints(): BrowserHints {
  if (typeof navigator === 'undefined') return {};
  const nav = navigator as Navigator & { userAgentData?: BrowserHints['userAgentData'] };
  return {
    userAgent: nav.userAgent,
    userAgentData: nav.userAgentData ?? null,
    maxTouchPoints: nav.maxTouchPoints
  };
}

export interface DeviceFields {
  device_id?: string;
  device_name?: string;
}

/**
 * De velden voor setup en login, of niets wanneer de server ze niet kent.
 * `capabilities` is null zolang `GET /info` nog niet beantwoord is, en dan
 * sturen we evenmin iets.
 */
export function deviceFields(
  // Optioneel en niet Pick<Capabilities>: een oudere server stuurt de vlag
  // niet, ook al zegt het gegenereerde type dat hij er altijd is.
  capabilities: Partial<Pick<Capabilities, 'sessions'>> | null | undefined,
  storage?: DeviceStorage | null,
  hints?: BrowserHints
): DeviceFields {
  if (capabilities?.sessions !== true) return {};
  return {
    device_id: deviceId(storage === undefined ? defaultStorage() : storage),
    device_name: deviceName(hints)
  };
}
