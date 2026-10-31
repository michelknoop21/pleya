/**
 * Scherm 19: de geschiedenisregels per dag, in de tijdzone van de lezer. De
 * server levert ze op `ended_at` gesorteerd, de groepen volgen die volgorde.
 */
import type { HistoryEntry, Item } from '../api/types';
import { knownDeviceName } from '../auth/device';
import { t } from '../i18n';
import { formatClock, formatDate } from './format';

export interface HistoryDay {
  key: string;
  label: string;
  entries: HistoryEntry[];
}

function dayKey(date: Date): string {
  return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`;
}

function dayLabel(iso: string, now: Date): string {
  const date = new Date(iso);
  if (dayKey(date) === dayKey(now)) return t('history.today');
  const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  if (dayKey(date) === dayKey(yesterday)) return t('history.yesterday');
  return formatDate(iso) ?? iso;
}

export function groupByDay(entries: HistoryEntry[], now = new Date()): HistoryDay[] {
  const days: HistoryDay[] = [];
  for (const entry of entries) {
    const key = dayKey(new Date(entry.ended_at));
    const day = days[days.length - 1];
    if (day?.key === key) day.entries.push(entry);
    else days.push({ key, label: dayLabel(entry.ended_at, now), entries: [entry] });
  }
  return days;
}

/** Tot hoever de sessie kwam, in hele procenten; null zonder bekende duur. */
export function historyPercent(entry: HistoryEntry): number | null {
  const duration = entry.duration_ms ?? entry.item.duration_ms;
  if (typeof duration !== 'number' || duration <= 0) return null;
  return Math.min(100, Math.round((entry.end_position_ms / duration) * 100));
}

/** "Uitgekeken · 21:40 tot 00:29 · Apple TV" of "Tot 42% · 19:02 · iPhone". */
export function historyLine(entry: HistoryEntry): string {
  const percent = historyPercent(entry);
  const parts = entry.completed
    ? [t('history.finished'), `${formatClock(entry.started_at)} – ${formatClock(entry.ended_at)}`]
    : [percent === null ? null : t('history.upTo', { percent }), formatClock(entry.ended_at)];
  const device = entry.device_name?.trim() ? (knownDeviceName(entry.device_name) ?? t('admin.devices.unknown')) : null;
  return [...parts, device].filter(Boolean).join(' · ');
}

/** Unieke items met een eigen cijfer, in de volgorde waarin ze binnenkwamen. */
export function ratedItems(items: Item[]): Item[] {
  const seen = new Set<string>();
  return items.filter((item) => {
    if (typeof item.rating !== 'number' || seen.has(item.id)) return false;
    seen.add(item.id);
    return true;
  });
}
