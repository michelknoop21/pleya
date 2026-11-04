/**
 * De gegevens en rekenregels van Diagnostiek (scherm 32), en het rapport voor
 * support dat daaruit volgt.
 *
 * Alles is alleen-lezen: `GET /server` (versie, database, ffprobe, gezondheid),
 * `GET /info` (protocol en capabilities), `GET /server/environment` en
 * `GET /server/log`. Niets daarvan draagt een geheim: de server laat een
 * variabele met een geheimnaam weg, maskeert de DSN en redigeert de logregels
 * op de weg de buffer in. Deze laag vertrouwt daar niet blind op: een waarde
 * die er toch uitziet als een wachtwoord in een URL, of een sleutel waarvan de
 * naam een geheim aankondigt, wordt hier nog eens gemaskeerd, ook in het rapport.
 *
 * Niet gebouwd omdat het contract het niet levert: de bouwdatum (de server
 * meldt één `build`-tekst), het geheugengebruik en het piekgebruik, het aantal
 * wachtende taken, en "gestreamd naar" per taak. Er is ook geen route naar een
 * volledige log; de ringbuffer is alles.
 */
import type { AdminSettingsApi } from '../../api/adminSettings';
import type { PleyaClient } from '../../api/client';
import type { Info, ServerDetail, ServerEnvironment, ServerLog } from '../../api/types';
import { plural } from '../../i18n';

export const LOG_LIMIT = 50;

export type EnvironmentEntry = ServerEnvironment['entries'][number];
export type LogEntry = ServerLog['entries'][number];

export interface DiagnosticsData {
  server: ServerDetail;
  info: Info;
  /** Null als de omgeving niet te lezen was. */
  environment: EnvironmentEntry[] | null;
  /** Null als de log niet te lezen was. */
  log: LogEntry[] | null;
}

export async function loadDiagnostics(
  client: PleyaClient,
  settingsApi: AdminSettingsApi,
  signal?: AbortSignal
): Promise<DiagnosticsData> {
  const [server, info, environment, log] = await Promise.all([
    client.server(signal),
    client.info(signal),
    settingsApi.environment(signal).catch(() => null),
    settingsApi.log('warn', LOG_LIMIT, signal).catch(() => null)
  ]);
  return { server, info, environment, log };
}

const SECRET_NAME = /(KEY|TOKEN|SECRET|PASSWORD|PASS|PEPPER|DSN)$/i;
const URL_PASSWORD = /(:\/\/[^:/@\s]+:)[^@\s]+@/g;
const MASK = '•••';

/** Een tweede slot achter dat van de server: een geheim komt niet in de DOM. */
export function maskEntry(entry: EnvironmentEntry): EnvironmentEntry {
  if (SECRET_NAME.test(entry.key) && entry.value !== '') {
    return { ...entry, value: MASK, redacted: true };
  }
  const value = entry.value.replace(URL_PASSWORD, `$1${MASK}@`);
  return value === entry.value ? entry : { ...entry, value, redacted: true };
}

export function maskLine(text: string): string {
  return text.replace(URL_PASSWORD, `$1${MASK}@`);
}

/** De capabilities die de server aanbiedt (waar) en die hij niet aanbiedt (onwaar), op volgorde. */
export function capabilityFlags(info: Info): { name: string; on: boolean }[] {
  return Object.entries(info.capabilities)
    .filter(([, value]) => typeof value === 'boolean')
    .map(([name, value]) => ({ name, on: value === true }))
    .sort((a, b) => Number(b.on) - Number(a.on));
}

/** Het rapport voor support als platte tekst; dezelfde gegevens als het scherm. */
export function buildReport(data: DiagnosticsData, generatedAt: Date): string {
  const { server, info } = data;
  const lines: string[] = [];
  lines.push(`Pleya server diagnostics, ${generatedAt.toISOString()}`, '');
  lines.push('[versions]');
  lines.push(`server: ${server.name} ${server.version}`);
  if (server.build) lines.push(`build: ${server.build}`);
  lines.push(`started: ${server.started_at}`);
  lines.push(
    `protocol: v${info.protocol.major}, feature level ${info.protocol.feature_level}, profile ${info.protocol.profile}`
  );
  if (server.database) lines.push(`database: postgres ${server.database.version}, schema ${server.database.schema}`);
  if (server.ffprobe) lines.push(`ffprobe: ${server.ffprobe.found ? (server.ffprobe.version ?? 'found') : 'not found'}`);
  lines.push('', '[capabilities]');
  for (const flag of capabilityFlags(info)) lines.push(`${flag.name}: ${flag.on ? 'on' : 'off'}`);
  if (server.health) {
    lines.push('', '[health]');
    lines.push(`ready: ${server.health.ready ? 'ok' : 'not ready'}`);
    lines.push(`jobs running: ${server.health.jobs_running}, failed: ${server.health.jobs_failed}`);
  }
  lines.push('', '[environment]');
  if (data.environment === null) lines.push('(unreadable)');
  else for (const entry of data.environment.map(maskEntry)) lines.push(`${entry.key}=${entry.value}`);
  lines.push('', '[log, warnings and errors]');
  if (data.log === null) lines.push('(unreadable)');
  else {
    for (const entry of data.log) {
      lines.push(maskLine(`${entry.at} ${entry.level} ${entry.component ?? ''} ${entry.message}`.replace(/ {2,}/g, ' ')));
    }
  }
  return lines.join('\n') + '\n';
}

/** De bestandsnaam van het rapport: `pleya-diagnostics-2026-10-26.txt`. */
export function reportFileName(at: Date): string {
  return `pleya-diagnostics-${at.toISOString().slice(0, 10)}.txt`;
}

/** Bewaart tekst als bestand in de browser; geen aanvraag naar de server. */
export function saveTextFile(name: string, text: string): void {
  const url = URL.createObjectURL(new Blob([text], { type: 'text/plain;charset=utf-8' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.rel = 'noopener';
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function levelTone(level: string): 'warn' | 'err' | 'idle' {
  return level === 'error' ? 'err' : level === 'warn' ? 'warn' : 'idle';
}

export function uptimeText(startedAt: string, now = Date.now()): string | null {
  const start = Date.parse(startedAt);
  if (Number.isNaN(start) || start > now) return null;
  const days = Math.floor((now - start) / 86_400_000);
  if (days >= 1) return plural('admin.diag.uptime.days', days);
  const hours = Math.floor((now - start) / 3_600_000);
  return plural('admin.diag.uptime.hours', hours);
}
