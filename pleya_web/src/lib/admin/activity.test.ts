import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { setLocale } from '../i18n';
import { job, library, root, scan } from './opsFake';
import {
  failedJobTitle,
  failureItems,
  historyRows,
  isLive,
  planScanAll,
  runningItems,
  scanJob,
  scanResult,
  type ActivityData
} from './activity';

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

const films = library('l1', 'Films');
const boeken = library('l2', 'Boeken');
const NOW = Date.parse('2026-10-26T12:00:00Z');

function data(extra: Partial<ActivityData> = {}): ActivityData {
  return {
    libraries: [films, boeken],
    roots: [root('/a', films), root('/b', boeken)],
    scans: [],
    next: null,
    jobs: [],
    ...extra
  };
}

describe('wat er loopt', () => {
  it('vindt de job achter een scan, zolang die nog af te breken is', () => {
    const running = scan('l1', 'running', { id: 's1' });
    const jobs = [
      job('old', { scan_id: 's1', state: 'failed' }),
      job('now', { scan_id: 's1', state: 'running' })
    ];
    expect(scanJob(jobs, running)?.id).toBe('now');
    expect(scanJob([jobs[0]!], running)).toBeNull();
  });

  it('telt een scan en een lopende taak van een andere soort, maar een scanjob niet dubbel', () => {
    const items = runningItems(
      data({
        scans: [scan('l1', 'running', { id: 's1' }), scan('l2', 'done', { id: 's2' })],
        jobs: [
          job('j1', { state: 'running', scan_id: 's1' }),
          job('j2', { kind: 'backup_create', state: 'running' }),
          job('j3', { kind: 'backup_create', state: 'pending' })
        ]
      })
    );
    expect(items.map((i) => (i.kind === 'scan' ? i.scan.id : i.job.id))).toEqual(['s1', 'j2']);
  });

  it('ververst alleen als er echt iets loopt of nu aan de beurt is', () => {
    expect(isLive(data({ scans: [scan('l1', 'queued', { id: 's' })] }), NOW)).toBe(true);
    expect(isLive(data({ jobs: [job('j', { state: 'running' })] }), NOW)).toBe(true);
    expect(isLive(data({ jobs: [job('j', { state: 'pending', run_at: '2026-10-26T11:00:00Z' })] }), NOW)).toBe(true);
    // Een taak voor morgen is geen reden om elke vijf seconden te vragen.
    expect(isLive(data({ jobs: [job('j', { state: 'pending', run_at: '2026-10-27T11:00:00Z' })] }), NOW)).toBe(false);
    expect(isLive(data({ scans: [scan('l1', 'done', { id: 's' })], jobs: [job('j')] }), NOW)).toBe(false);
  });
});

describe('fouten', () => {
  it('zet mislukte jobs nieuwste eerst en daarna de niet-gemounte roots', () => {
    const items = failureItems(
      data({
        roots: [root('/a', films), root('/b', boeken, { mounted: false })],
        jobs: [
          job('oud', { finished_at: '2026-10-25T08:00:00Z' }),
          job('nieuw', { finished_at: '2026-10-26T08:00:00Z' }),
          job('klaar', { state: 'succeeded' }),
          job('bezig', { state: 'running' })
        ]
      })
    );
    expect(items.map((i) => (i.kind === 'job' ? i.job.id : i.root.path))).toEqual(['nieuw', 'oud', '/b']);
  });

  it('noemt een scanjob bij zijn bibliotheek en een onbekende soort neutraal', () => {
    expect(failedJobTitle(job('j'), 'Films')).toBe('Scan van Films mislukt');
    expect(failedJobTitle(job('j'), null)).toBe('Scan mislukt');
    expect(failedJobTitle(job('j', { kind: 'backup_verify' }), null)).toBe('Controle van een back-up mislukt');
    expect(failedJobTitle(job('j', { kind: 'nieuw_soort' }), null)).toBe('Taak mislukt');
  });
});

describe('alles scannen', () => {
  it('slaat een bibliotheek met een niet-gemounte root over', () => {
    const plan = planScanAll(
      data({ roots: [root('/a', films), root('/b', boeken, { mounted: false })] })
    );
    expect(plan.start.map((l) => l.id)).toEqual(['l1']);
    expect(plan.skipped.map((l) => l.id)).toEqual(['l2']);
  });

  it('start geen scan voor een bibliotheek waarvan de laatste scan nog wacht of loopt', () => {
    const plan = planScanAll(data({ scans: [scan('l1', 'queued', { id: 's' })] }));
    expect(plan.running.map((l) => l.id)).toEqual(['l1']);
    expect(plan.start.map((l) => l.id)).toEqual(['l2']);
  });

  it('start wel opnieuw als de laatste scan klaar is', () => {
    const plan = planScanAll(data({ scans: [scan('l1', 'done', { id: 's' })] }));
    expect(plan.start.map((l) => l.id)).toEqual(['l1', 'l2']);
  });
});

describe('geschiedenis', () => {
  it('laat wachtende en lopende scans weg en een herhaalde scan maar één keer staan', () => {
    const done = scan('l1', 'done', { id: 's1' });
    const rows = historyRows(
      [scan('l2', 'running', { id: 'r' }), done, scan('l1', 'queued', { id: 'q' }), done],
      [films, boeken],
      NOW
    );
    expect(rows.map((r) => r.id)).toEqual(['s1']);
  });

  it('zet de duur van begin tot eind, en n.v.t. zonder einde', () => {
    const rows = historyRows(
      [
        scan('l1', 'done', { id: 'a', started_at: '2026-10-26T08:00:00Z', finished_at: '2026-10-26T08:00:40Z' }),
        scan('l1', 'cancelled', { id: 'b', finished_at: null })
      ],
      [films],
      NOW
    );
    expect(rows[0]!.duration).toBe('40 s');
    expect(rows[1]!.duration).toBe('n.v.t.');
    expect(rows[1]!.state).toBe('gestopt');
  });

  it('noemt de soort start: handmatig, volgens schema, bij het opstarten', () => {
    const rows = historyRows(
      (['manual', 'schedule', 'startup'] as const).map((trigger, i) =>
        scan('l1', 'done', { id: `s${i}`, trigger })
      ),
      [films],
      NOW
    );
    expect(rows.map((r) => r.trigger)).toEqual(['handmatig', 'volgens schema', 'bij het opstarten']);
  });

  it('toont bij een mislukte scan de laatste foutmelding en het aantal fouten', () => {
    expect(scanResult(scan('l1', 'failed', { last_error: 'root niet gemount', files_seen: 0 }))).toBe(
      'root niet gemount · 0 bestanden gezien'
    );
    expect(scanResult(scan('l1', 'done', { error_count: 1, files_seen: 10 }))).toContain('1 fout');
  });
});
