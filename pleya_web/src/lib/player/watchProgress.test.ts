import { describe, expect, it, vi } from 'vitest';
import { ResumeFloor, WatchProgress } from './watchProgress';
import { manualTimers } from './playerFake';
import type { UserState, WatchStateEvent } from './types';

const state = (revision: number, owned = true): UserState => ({
  position_ms: 0, watched: false, play_count: 0, updated_at: '2026-10-29T12:00:00Z', revision, owned_by_this_session: owned
});
const settle = async () => { for (let i=0;i<10;i++) await Promise.resolve(); };
function setup(enabled = true, ownership = true) {
  let position = 0;
  const report = vi.fn(async (_body: WatchStateEvent, _keepalive: boolean) => state(8));
  const timers = manualTimers();
  const progress = new WatchProgress({ report, enabled, ownership, itemId: 'movie', revision: 7,
    sample: () => ({ position, duration: 100 }), timers });
  return { progress, report, timers, setPosition: (p: number) => position = p };
}

describe('browser watch-state ownership', () => {
  it('only actual play starts one stable viewing session, including pause and resume', async () => {
    const { progress, report, setPosition } = setup();
    expect(report).not.toHaveBeenCalled();
    progress.play(); await settle();
    setPosition(12); progress.report(); await settle();
    progress.play(); progress.finish(false); await settle();
    const bodies = report.mock.calls.map(([body]) => body);
    expect(bodies[0]).toMatchObject({ item_id: 'movie', explicit_action: 'playback_started', base_revision: 7 });
    expect(bodies.map(body => body.explicit_action)).toEqual(['playback_started','none','none']);
    expect(new Set(bodies.map(body => body.session_id)).size).toBe(1);
    expect(bodies[1]).toMatchObject({ position_ms: 12000, duration_ms: 100000, base_revision: 8, backlog: false });
  });
  it('a press on play claims the viewing with cause user_started, and only under ownership', async () => {
    const owned = setup();
    owned.progress.play(); await settle();
    owned.setPosition(5); owned.progress.report(); await settle();
    expect(owned.report.mock.calls[0]![0]).toMatchObject({ explicit_action: 'playback_started', cause: 'user_started' });
    expect(owned.report.mock.calls[1]![0]).not.toHaveProperty('cause');
    const legacy = setup(true, false);
    legacy.progress.play(); await settle();
    expect(legacy.report.mock.calls[0]![0]).not.toHaveProperty('cause');
  });
  it('a start refused on a stale revision is sent once more with the revision the server returned', async () => {
    const { progress, report, timers } = setup();
    report.mockResolvedValueOnce(state(10, false));
    report.mockResolvedValue(state(11));
    progress.play(); await settle();
    timers.tick(); await settle();
    const bodies = report.mock.calls.map(([body]) => body);
    expect(bodies.map(body => body.explicit_action)).toEqual(['playback_started', 'playback_started', 'none']);
    expect(bodies[1]).toMatchObject({ base_revision: 10, cause: 'user_started' });
    expect(bodies[2]).toMatchObject({ base_revision: 11 });
  });
  it('never reacquires ownership when another device owns the response', async () => {
    const { progress, report, timers } = setup();
    report.mockResolvedValue(state(10, false));
    progress.play(); await settle();
    timers.tick(); await settle();
    progress.finish(false); await settle();
    // One retry of the start itself; passive events never acquire.
    expect(report.mock.calls.slice(0, 2).every(([body]) => body.explicit_action === 'playback_started')).toBe(true);
    expect(report.mock.calls.slice(2).every(([body]) => body.explicit_action === 'none' && body.base_revision === 10)).toBe(true);
  });
  it('coalesces slow progress and sends the latest snapshot with the received revision', async () => {
    const { progress, report, setPosition } = setup();
    let release!: (state: UserState) => void;
    report.mockImplementationOnce(() => new Promise(resolve => release = resolve));
    progress.play();
    setPosition(2); progress.report(); setPosition(5); progress.report();
    expect(report).toHaveBeenCalledTimes(1);
    release(state(9)); await settle();
    expect(report).toHaveBeenCalledTimes(2);
    expect(report.mock.calls[1]![0]).toMatchObject({ position_ms: 5000, base_revision: 9 });
    progress.finish(false); await settle();
  });
  it('uses the existing 90 percent completion threshold and disposes once', async () => {
    const { progress, report, setPosition, timers } = setup();
    progress.play(); await settle();
    setPosition(89.9); progress.report(); await settle();
    expect(report.mock.calls.at(-1)![0].completed).toBe(false);
    setPosition(90); progress.finish(true); await settle();
    expect(report.mock.calls.at(-1)).toEqual([expect.objectContaining({ completed: true, position_ms: 90000 }), true]);
    const count = report.mock.calls.length;
    progress.finish(false); timers.tick(); progress.play(); progress.report(); await settle();
    expect(report).toHaveBeenCalledTimes(count);
  });
  it('does nothing without watch_state and omits ownership fields on older servers', async () => {
    const old = setup(false); old.progress.play(); old.progress.finish(true); await settle();
    expect(old.report).not.toHaveBeenCalled();
    const legacy = setup(true, false); legacy.progress.play(); await settle();
    expect(legacy.report.mock.calls[0]![0]).not.toHaveProperty('base_revision');
    expect(legacy.report.mock.calls[0]![0]).not.toHaveProperty('backlog');
    legacy.progress.finish(false); await settle();
  });
  it('starts the final keepalive synchronously even while a progress request is pending', async () => {
    const { progress, report, setPosition } = setup();
    let release!: (state: UserState) => void;
    report.mockImplementationOnce(() => new Promise(resolve => release = resolve));
    progress.play(); setPosition(17); progress.finish(true);
    expect(report).toHaveBeenCalledTimes(2);
    expect(report.mock.calls[1]).toEqual([expect.objectContaining({ position_ms: 17000 }), true]);
    release(state(9)); await settle();
    expect(report).toHaveBeenCalledTimes(2);
  });
  it('repeats a start that got no answer, so one 503 does not cost the viewing', async () => {
    const { progress, report, timers, setPosition } = setup();
    report.mockRejectedValueOnce(new Error('503'));
    progress.play(); await settle();
    setPosition(15); timers.tick(); await settle();
    setPosition(30); timers.tick(); await settle();
    expect(report.mock.calls.map(([body]) => body.explicit_action)).toEqual(['playback_started', 'playback_started', 'none']);
    expect(report.mock.calls[1]![0]).toMatchObject({ position_ms: 15000, cause: 'user_started', base_revision: 7 });
    expect(report.mock.calls[2]![0]).not.toHaveProperty('cause');
    progress.finish(false); await settle();
  });
  it('a viewing that never got its start through still claims with the last report', async () => {
    const { progress, report, setPosition } = setup();
    report.mockRejectedValueOnce(new Error('503'));
    progress.play(); await settle();
    setPosition(40); progress.finish(true); await settle();
    expect(report.mock.calls[1]).toEqual([expect.objectContaining({ explicit_action: 'playback_started', position_ms: 40000 }), true]);
  });
  it('a failure after the start was answered stays passive', async () => {
    const { progress, report, timers } = setup();
    progress.play(); await settle();
    report.mockRejectedValueOnce(new Error('offline'));
    timers.tick(); await settle();
    timers.tick(); await settle();
    expect(report.mock.calls.map(([body]) => body.explicit_action)).toEqual(['playback_started', 'none', 'none']);
    progress.finish(false); await settle();
  });
});

describe('the resume point of an unfinished seek', () => {
  it('reports the old point until playback reaches it, whatever the video shows', () => {
    const floor = new ResumeFloor(600);
    expect(floor.position(0)).toBe(600);
    expect(floor.position(12)).toBe(600);
    expect(floor.position(600)).toBe(600);
    expect(floor.position(601)).toBe(601);
    expect(floor.position(30)).toBe(30);
  });
  it('lets go when the viewer picks a position himself', () => {
    const floor = new ResumeFloor(600);
    floor.release();
    expect(floor.position(10)).toBe(10);
  });
  it('does nothing without a resume point', () => {
    expect(new ResumeFloor(0).position(0)).toBe(0);
  });
});
