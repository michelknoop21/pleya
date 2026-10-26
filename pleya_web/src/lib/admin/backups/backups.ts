/**
 * De gegevens en rekenregels van Onderhoud (scherm 35, S25.6).
 *
 * Bron: `GET /backups` en de drie schrijfroutes. Wat de northstar tekent en het
 * contract niet draagt staat er niet: een downloadknop (er is bewust geen
 * route, zie `adminBackups.ts`), het blok "Versie en upgrade" (geen route geeft
 * het upgradepad of de laatste upgrade), de "Faalpaden"-lijst (de server meldt
 * alleen `failure_code` per back-up) en de onderhoudsmodus als schakelaar (die
 * gaat alleen aan door een restore, nooit op verzoek).
 */
import type { AdminBackupsApi } from '../../api/adminBackups';
import { ApiError, TransportError } from '../../api/errors';
import type { Backup, BackupList } from '../../api/types';
import type { PillTone } from '../../components/StatusPill.svelte';
import { plural, t } from '../../i18n';
import { formatCount, formatDayClock } from '../../util/format';

/** Zo vaak ververst de pagina zolang er een back-up of hersteltest loopt. */
export const BACKUP_POLL_MS = 4000;
/** Een geslaagde hersteltest hoort niet ouder te zijn dan een week (de server doet hem wekelijks). */
export const TEST_MAX_AGE_DAYS = 7;
/** Zo vaak kijkt de pagina of de server na een restore terug is, en hoe lang hij wacht. */
export const RESTORE_POLL_MS = 3000;
export const RESTORE_GIVE_UP_MS = 10 * 60_000;

/** De namen van de omgevingsvariabelen; de waarden komen uit `GET /backups`. */
export const BACKUP_ENV = {
  dir: 'PLEYA_SERVER_BACKUP_DIR',
  schedule: 'PLEYA_SERVER_BACKUP_TIME',
  retention: 'PLEYA_SERVER_BACKUP_RETENTION_DAYS',
  key: 'PLEYA_SERVER_BACKUP_KEY'
} as const;

export function countLabel(key: string, count: number): string {
  return plural(key, count, { count: formatCount(count) });
}

/** "14 dagen", voor de bewaartermijn. */
export function daysLabel(days: number): string {
  return countLabel('admin.bak.days', days);
}

export function loadBackups(api: AdminBackupsApi, signal?: AbortSignal): Promise<BackupList> {
  return api.list(signal);
}

/** Loopt er een back-up of een hersteltest? Dan ververst de pagina en blijft elke schrijfknop uit. */
export function isLive(list: BackupList): boolean {
  return list.items.some((b) => b.status === 'running' || b.last_restore_test?.status === 'running');
}

/** Alleen een geslaagde back-up met een zin van de server is terug te zetten. */
export function canRestore(backup: Backup): boolean {
  return backup.status === 'ok' && Boolean(backup.restore_confirmation);
}

export function canVerify(backup: Backup): boolean {
  return backup.status === 'ok';
}

export interface Chip {
  tone: PillTone;
  label: string;
}

export function statusChip(backup: Backup): Chip {
  switch (backup.status) {
    case 'ok':
      return { tone: 'ok', label: t('admin.bak.status.ok') };
    case 'running':
      return { tone: 'run', label: t('admin.bak.status.running') };
    case 'failed':
      return { tone: 'err', label: t('admin.bak.status.failed') };
    case 'missing':
      return { tone: 'warn', label: t('admin.bak.status.missing') };
    default:
      return { tone: 'idle', label: backup.status };
  }
}

export function triggerLabel(backup: Backup): string {
  switch (backup.trigger) {
    case 'schedule':
      return t('admin.bak.trigger.schedule');
    case 'manual':
      return t('admin.bak.trigger.manual');
    case 'upgrade':
      return t('admin.bak.trigger.upgrade');
    default:
      return backup.trigger;
  }
}

/** "database (schema 19), 1.204 titels"; zonder wat de server nog niet weet. */
export function contentLine(backup: Backup): string {
  const parts: string[] = [];
  parts.push(
    backup.schema_version !== null
      ? t('admin.bak.content.schema', { schema: backup.schema_version })
      : t('admin.bak.content.database')
  );
  if (backup.titles !== null) parts.push(countLabel('admin.bak.titles', backup.titles));
  return parts.join(', ');
}

export function secretsLabel(backup: Backup): string {
  return backup.secrets_included ? t('admin.bak.secrets.in') : t('admin.bak.secrets.out');
}

/** De laatste hersteltest als label en toelichting. */
export function testChip(backup: Backup, now: number): { chip: Chip; detail: string | null } {
  const test = backup.last_restore_test;
  if (!test) return { chip: { tone: 'warn', label: t('admin.bak.test.never') }, detail: null };
  if (test.status === 'running') {
    return { chip: { tone: 'run', label: t('admin.bak.test.running') }, detail: null };
  }
  const when = formatDayClock(test.finished_at ?? test.started_at, now);
  if (test.status === 'ok') {
    const found =
      test.titles_found !== null && test.titles_expected !== null
        ? t('admin.bak.test.counted', { found: test.titles_found, expected: test.titles_expected })
        : null;
    return {
      chip: { tone: 'ok', label: t('admin.bak.test.ok') },
      detail: [when, found].filter(Boolean).join(' · ') || null
    };
  }
  return {
    chip: { tone: 'err', label: t('admin.bak.test.failed') },
    detail: [when, test.failure_code ? failureLine(test.failure_code) : null].filter(Boolean).join(' · ') || null
  };
}

/** Een faalcode van een back-up of hersteltest als zin. */
export function failureLine(code: string): string {
  switch (code) {
    case 'storage.full':
      return t('admin.bak.failure.storageFull');
    case 'server.database_unavailable':
      return t('admin.bak.failure.database');
    default:
      return t('admin.bak.failure.code', { code });
  }
}

export type WarningId = 'failed' | 'domain' | 'noKey' | 'testOld' | 'testNever' | 'missing';

export interface Warning {
  id: WarningId;
  tone: 'warn' | 'err';
  title: string;
  message: string;
}

const DAY_MS = 86_400_000;

/** Wanneer de laatste geslaagde hersteltest klaar was, of null als er nooit een slaagde. */
function lastGoodTest(list: BackupList): number | null {
  let best: number | null = null;
  for (const b of list.items) {
    const test = b.last_restore_test;
    if (test?.status !== 'ok') continue;
    const at = Date.parse(test.finished_at ?? test.started_at);
    if (!Number.isNaN(at) && (best === null || at > best)) best = at;
  }
  return best;
}

/**
 * De meldingen boven de lijst, belangrijkste eerst. `same_failure_domain` en
 * `secrets_key_configured` komen rechtstreeks uit het antwoord; de twee over
 * de hersteltest en een mislukte laatste back-up volgen uit de rijen.
 */
export function warnings(list: BackupList, now: number): Warning[] {
  const out: Warning[] = [];
  const newest = list.items[0];
  if (newest?.status === 'failed') {
    out.push({
      id: 'failed',
      tone: 'err',
      title: t('admin.bak.warn.failed.title'),
      message: t('admin.bak.warn.failed.body', {
        reason: newest.failure_code ? failureLine(newest.failure_code) : t('admin.bak.failure.unknown')
      })
    });
  }
  if (list.same_failure_domain) {
    out.push({
      id: 'domain',
      tone: 'warn',
      title: t('admin.bak.warn.domain.title'),
      message: t('admin.bak.warn.domain.body', { dir: list.dir })
    });
  }
  if (!list.secrets_key_configured) {
    out.push({
      id: 'noKey',
      tone: 'warn',
      title: t('admin.bak.warn.noKey.title'),
      message: t('admin.bak.warn.noKey.body', { variable: BACKUP_ENV.key })
    });
  }
  if (list.items.some((b) => b.status === 'ok')) {
    const good = lastGoodTest(list);
    if (good === null) {
      out.push({
        id: 'testNever',
        tone: 'warn',
        title: t('admin.bak.warn.testNever.title'),
        message: t('admin.bak.warn.testNever.body')
      });
    } else if (now - good > TEST_MAX_AGE_DAYS * DAY_MS) {
      out.push({
        id: 'testOld',
        tone: 'warn',
        title: t('admin.bak.warn.testOld.title'),
        message: t('admin.bak.warn.testOld.body', { days: TEST_MAX_AGE_DAYS })
      });
    }
  }
  const missing = list.items.filter((b) => b.status === 'missing').length;
  if (missing > 0) {
    out.push({
      id: 'missing',
      tone: 'warn',
      title: t('admin.bak.warn.missing.title'),
      message: plural('admin.bak.warn.missing.body', missing, { dir: list.dir })
    });
  }
  return out;
}

export type RestoreOutcome = 'back' | 'signin' | 'timeout';

export interface WaitOptions {
  signal?: AbortSignal;
  intervalMs?: number;
  maxMs?: number;
  /** Voor tests: een wachtfunctie die niet echt wacht. */
  sleep?: (ms: number, signal?: AbortSignal) => Promise<void>;
}

function sleepFor(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener(
      'abort',
      () => {
        clearTimeout(timer);
        resolve();
      },
      { once: true }
    );
  });
}

/**
 * Wacht tot de server na een restore weer antwoordt. Tijdens de restore krijgt
 * elke aanvraag 503 `server.maintenance`, en tijdens de herstart is er geen
 * verbinding of antwoordt de proxy ervoor met een 5xx: dat is allemaal "nog
 * niet". Een 200 is "terug". Een 401 betekent dat de sessie in de teruggezette
 * database niet bestaat: dan is niet wachten maar opnieuw inloggen de uitweg.
 * Elke andere fout telt als nog niet, tot de wachttijd om is.
 */
export async function waitForServer(
  api: AdminBackupsApi,
  { signal, intervalMs = RESTORE_POLL_MS, maxMs = RESTORE_GIVE_UP_MS, sleep = sleepFor }: WaitOptions = {}
): Promise<RestoreOutcome> {
  const tries = Math.max(1, Math.ceil(maxMs / intervalMs));
  for (let i = 0; i < tries; i += 1) {
    if (signal?.aborted) return 'timeout';
    try {
      await api.list(signal);
      return 'back';
    } catch (err) {
      if (signal?.aborted) return 'timeout';
      if (err instanceof ApiError && err.status === 401) return 'signin';
      if (!(err instanceof ApiError) && !(err instanceof TransportError)) throw err;
    }
    await sleep(intervalMs, signal);
  }
  return 'timeout';
}
