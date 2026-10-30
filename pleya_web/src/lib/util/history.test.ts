import { describe, expect, it } from 'vitest';
import type { HistoryEntry, Item } from '../api/types';
import { groupByDay, historyLine, historyPercent, ratedItems } from './history';

const item = (id: string, extra: Partial<Item> = {}) => ({ id, title: id, kind: 'movie', added_at: '2026-10-01T00:00:00Z', ...extra }) as Item;
const entry = (id: string, extra: Partial<HistoryEntry> = {}) => ({
  id, item: item(id), started_at: '2026-10-30T18:00:00', ended_at: '2026-10-30T19:02:00',
  start_position_ms: 0, end_position_ms: 2_520_000, duration_ms: 6_000_000, completed: false, device_name: 'iPhone', ...extra
}) as HistoryEntry;

describe('history rows', () => {
  it('groups by local day in server order and names today and yesterday', () => {
    const days = groupByDay([
      entry('a'), entry('b', { ended_at: '2026-10-30T08:00:00' }),
      entry('c', { ended_at: '2026-10-29T23:30:00' }), entry('d', { ended_at: '2026-10-12T10:00:00' })
    ], new Date('2026-10-30T20:00:00'));
    expect(days.map((day) => day.entries.map((row) => row.id))).toEqual([['a', 'b'], ['c'], ['d']]);
    expect(days.slice(0, 2).map((day) => day.label)).toEqual(['Today', 'Yesterday']);
    expect(days[2]?.label).toContain('12');
  });
  it('states how far a session got, and only what is known', () => {
    expect(historyPercent(entry('a'))).toBe(42);
    expect(historyPercent(entry('a', { duration_ms: null }))).toBeNull();
    expect(historyPercent(entry('a', { end_position_ms: 9_000_000 }))).toBe(100);
    expect(historyLine(entry('a'))).toMatch(/^Up to 42% · .+ · iPhone$/);
    expect(historyLine(entry('a', { duration_ms: null, device_name: null }))).not.toContain('Up to');
    expect(historyLine(entry('a', { completed: true }))).toMatch(/^Finished · .+ – .+ · iPhone$/);
  });
  it('keeps each rated title once and skips unrated ones', () => {
    expect(ratedItems([item('a', { rating: 7 }), item('b'), item('a', { rating: 7 }), item('c', { rating: 1 })]).map((row) => row.id)).toEqual(['a', 'c']);
  });
});
