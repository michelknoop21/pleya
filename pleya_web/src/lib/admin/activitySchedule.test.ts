import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { setLocale } from '../i18n';
import type { ActivityData } from './activity';
import { scheduledRows } from './activitySchedule';
import { library, root } from './opsFake';

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

const NOW = Date.parse('2026-11-13T12:00:00Z');

function data(nextScanAt: string | null | undefined): ActivityData {
  const films = { ...library('l1', 'Films'), next_scan_at: nextScanAt };
  return { libraries: [films], roots: [root('/a', films)], scans: [], next: null, lastScans: {}, jobs: [] };
}

describe('de volgende geplande scan', () => {
  it('toont het tijdstip uit next_scan_at als de server scan_schedule kent', () => {
    const [row] = scheduledRows(data('2026-11-13T18:00:00Z'), NOW, true);
    expect(row!.next).toMatch(/\d{2}:\d{2}/);
  });

  it('toont geen tijd bij null, en geen kolom zonder de capability', () => {
    expect(scheduledRows(data(null), NOW, true)[0]!.next).toBeNull();
    expect(scheduledRows(data('2026-11-13T18:00:00Z'), NOW, false)[0]).not.toHaveProperty('next');
  });
});

describe('de kolom Volgende', () => {
  it('staat er met een tijd, met "Niet gepland" bij null, en ontbreekt zonder capability', async () => {
    const { render, screen } = await import('@testing-library/svelte');
    const { default: ActivityScheduled } = await import('./ActivityScheduled.svelte');
    const rows = [
      ...scheduledRows(data('2026-11-13T18:00:00Z'), NOW, true),
      ...scheduledRows(data(null), NOW, true).map(row => ({ ...row, library: { ...row.library, id: 'l2' } }))
    ];
    const view = render(ActivityScheduled, { props: { rows, scanning: {}, onscan: () => {} } });
    expect(screen.getAllByText('Volgende')).toHaveLength(2);
    expect(screen.getByText('Niet gepland')).toBeInTheDocument();
    view.unmount();
    render(ActivityScheduled, { props: { rows: scheduledRows(data(null), NOW, false), scanning: {}, onscan: () => {} } });
    expect(screen.queryByText('Volgende')).toBeNull();
  });
});
