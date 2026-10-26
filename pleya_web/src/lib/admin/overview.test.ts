import { describe, expect, it } from 'vitest';

import type { Job, Scan, StorageRoot } from '../api/types';
import { activity, currentScan, storageSummary, streamProgress, type OverviewData } from './overview';

function root(path: string, free: number, total: number, mounted = true): StorageRoot {
  return {
    path,
    fs_type: 'btrfs',
    inode_trusted: true,
    inode_trust_source: 'fstype_default',
    mounted,
    free_bytes: free,
    total_bytes: total,
    libraries: []
  };
}

function scan(id: string, state: Scan['state'], startedAt: string): Scan {
  return {
    id,
    library_id: 'l1',
    trigger: 'manual',
    state,
    started_at: startedAt,
    finished_at: state === 'running' ? null : startedAt,
    files_seen: 10,
    files_new: 0,
    files_renamed: 0,
    files_changed: 0,
    files_probed: 0,
    files_missing: 0,
    bytes_hashed: 0,
    items_created: 0,
    versions_created: 0,
    error_count: 0,
    last_error: null,
    current_path: null
  };
}

function job(id: string, state: Job['state'], at: string): Job {
  return {
    id,
    kind: 'backup_verify',
    state,
    attempts: 3,
    max_attempts: 3,
    last_error: 'timeout',
    run_at: at,
    created_at: at,
    finished_at: at,
    cancel_requested_at: null
  };
}

describe('opslag over de roots', () => {
  it('telt roots op hetzelfde bestandssysteem één keer', () => {
    // Zoals de NAS: drie roots onder één mount, twee onder een tweede.
    const s = storageSummary([
      root('/a/Films', 3_000, 6_000),
      root('/a/Kids', 3_000, 6_000),
      root('/a/Series', 3_000, 6_000),
      root('/b/Films', 2_000, 10_000),
      root('/b/Series', 2_000, 10_000)
    ]);
    expect(s).toMatchObject({ free: 5_000, total: 16_000, rootCount: 5 });
    expect(s.unmounted).toEqual([]);
  });

  it('telt een niet-gemounte root niet mee in de ruimte maar wel apart', () => {
    const s = storageSummary([root('/a', 1_000, 2_000), root('/boeken', 0, 0, false)]);
    expect(s.free).toBe(1_000);
    expect(s.unmounted.map((r) => r.path)).toEqual(['/boeken']);
  });
});

describe('scan en activiteit', () => {
  const base = { libraries: [{ id: 'l1', title: 'Films', kind: 'movies', item_count: 1 }] };

  it('kiest de lopende scan boven de laatste', () => {
    const scans = [scan('a', 'done', '2026-10-25T12:00:00Z'), scan('b', 'running', '2026-10-25T11:00:00Z')];
    expect(currentScan(scans)).toMatchObject({ active: true, scan: { id: 'b' } });
    expect(currentScan([scans[0]!])).toMatchObject({ active: false, scan: { id: 'a' } });
    expect(currentScan([])).toBeNull();
  });

  it('zet scans en mislukte taken samen, nieuwste eerst, zonder geslaagde taken', () => {
    const data = {
      ...base,
      scans: [scan('s1', 'done', '2026-10-25T10:00:00Z')],
      jobs: [job('j1', 'failed', '2026-10-25T11:00:00Z'), job('j2', 'succeeded', '2026-10-25T12:00:00Z')]
    } as unknown as OverviewData;
    const rows = activity(data);
    expect(rows.map((r) => r.kind)).toEqual(['job', 'scan']);
    expect(rows[1]).toMatchObject({ library: 'Films' });
  });
});

describe('voortgang van een stream', () => {
  it('geeft alleen een percentage met positie en duur', () => {
    const base = {
      id: 'x',
      user_id: 'u',
      username: 'u',
      item_id: 'i',
      item_title: 't',
      item_kind: 'movie' as const,
      started_at: '',
      expires_at: ''
    };
    expect(streamProgress({ ...base, position_ms: 420, duration_ms: 1000 })).toBe(42);
    expect(streamProgress(base)).toBeNull();
  });
});
