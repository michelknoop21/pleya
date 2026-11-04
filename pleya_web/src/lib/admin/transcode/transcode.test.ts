import { describe, expect, it } from 'vitest';

import type { TranscodeSession, TranscodeSessionList } from '../../api/types';
import { ADMIN_PATHS } from '../../api/admin';
import { activeSectionId, adminBackHref } from '../sections';
import { atMaximum, isLive, shortId, sortedSessions } from './transcode';

const session = (id: string, started: string): TranscodeSession => ({
  id,
  user_id: 'u1',
  version_id: 'v1',
  mode: 'transcode',
  hw_accel: null,
  started_at: started,
  last_heartbeat_at: started
});

const list = (max: number, items: TranscodeSession[]): TranscodeSessionList => ({
  max_sessions: max,
  hardware: { accel: 'none', reason: null },
  items
});

describe('rekenregels van scherm 37', () => {
  it('meldt het maximum alleen bij een maximum boven nul en een volle lijst', () => {
    const one = session('a', '2026-10-26T08:00:00Z');
    expect(atMaximum(list(1, [one]))).toBe(true);
    expect(atMaximum(list(2, [one]))).toBe(false);
    // Maximum 0 betekent uit, niet vol.
    expect(atMaximum(list(0, []))).toBe(false);
  });

  it('ververst alleen zolang er sessies zijn', () => {
    expect(isLive({ list: list(2, []), users: null })).toBe(false);
    expect(isLive({ list: list(2, [session('a', '2026-10-26T08:00:00Z')]), users: null })).toBe(true);
  });

  it('zet de langst lopende sessie bovenaan zonder de invoer te wijzigen', () => {
    const items = [session('nieuw', '2026-10-26T09:00:00Z'), session('oud', '2026-10-26T08:00:00Z')];
    expect(sortedSessions(items).map((s) => s.id)).toEqual(['oud', 'nieuw']);
    expect(items[0]!.id).toBe('nieuw');
  });

  it('kort een id in tot acht tekens', () => {
    expect(shortId('0191f2a4-7c3e-7d10')).toBe('0191f2a4');
  });

  it('hoort bij Media en streaming, met de terugpijl naar die sectie', () => {
    expect(activeSectionId('/admin/media/transcode')).toBe('media');
    expect(adminBackHref('/admin/media/transcode')).toBe('/admin/media');
  });

  it('gebruikt alleen routes die de beheerpoort al dekt, dus een lid raakt ze nooit', () => {
    expect(ADMIN_PATHS).toContain('/transcode-sessions');
    expect(ADMIN_PATHS).toContain('/users');
  });
});
