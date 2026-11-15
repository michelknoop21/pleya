/**
 * Startpositie in het afspeelplan (DEC-XXX): een omzetting begint op het punt
 * waar gekeken wordt, en de speler rekent overal in filmtijd, offset plus de
 * tijd van het element. Elke regel heeft een controle zonder de capability.
 */
import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Capabilities, Item } from '../api/types';
import { setLocale } from '../i18n';
import Player from './Player.svelte';
import { SERVER_CAPS, deps, fakeApi, fakeHls, fakeMedia, plan, transcodePlan } from './playerFake';
import { PlayerSession, STOP_WAIT_MS } from './playerSession.svelte';
import { PlayerSubtitles } from './playerSubtitles.svelte';
import type { PlaybackPlanRequest } from './types';

const START_CAPS = { ...SERVER_CAPS, playback_start_position: true, playback_quality: true };
const target = { itemId: 'item-1', versionId: 'v-1' };
const asMedia = (m: unknown) => m as HTMLMediaElement;

/** Een server met startpositie: de stream begint op het keyframe 6 s vóór de gevraagde positie. */
const keyframePlan = async (body: PlaybackPlanRequest) =>
  transcodePlan(body.start_position_ms === undefined ? {} : { start_position_ms: Math.max(0, body.start_position_ms - 6000) });

describe('het plan vanaf een positie', () => {
  it('vraagt met de capability het plan vanaf het hervatpunt en laat hls.js binnen de stream op dat punt beginnen', async () => {
    const api = fakeApi({ plan: keyframePlan });
    const hls = fakeHls();
    const s = new PlayerSession(deps(api, { hls, server: START_CAPS }));
    await s.start(asMedia(fakeMedia()), { ...target, startAt: 3600 });
    expect(vi.mocked(api.plan).mock.calls[0]![0]).toMatchObject({ start_position_ms: 3_600_000 });
    expect(s.offset).toBe(3594);
    // Het keyframe ligt 6 s eerder; die 6 s speelt hls.js niet opnieuw.
    expect(hls.instances[0]?.config['startPosition']).toBe(6);
  });

  it('negatieve controle: zonder capability geen veld, en hls.js begint op het hervatpunt', async () => {
    const api = fakeApi({ plan: keyframePlan });
    const hls = fakeHls();
    const s = new PlayerSession(deps(api, { hls }));
    await s.start(asMedia(fakeMedia()), { ...target, startAt: 3600 });
    expect(vi.mocked(api.plan).mock.calls[0]![0]).not.toHaveProperty('start_position_ms');
    expect(s.offset).toBe(0);
    expect(hls.instances[0]?.config['startPosition']).toBe(3600);
  });

  it('stuurt het veld niet voor de eigen HLS-speler van de browser, waarvan de tijdlijn niet gemeten is', async () => {
    const api = fakeApi({ plan: keyframePlan });
    const s = new PlayerSession(deps(api, { server: START_CAPS, probe: () => ({ caps: { decoder: {} }, hls: { hlsjs: false, native: true } }) }));
    await s.start(asMedia(fakeMedia()), { ...target, startAt: 3600 });
    expect(vi.mocked(api.plan).mock.calls[0]![0]).not.toHaveProperty('start_position_ms');
    expect(s.startsAtPosition).toBe(false);
  });

  it('direct play meldt 0: het element zoekt zelf naar het hervatpunt', async () => {
    const api = fakeApi({ plan: async () => plan({ start_position_ms: 0 }) });
    const media = fakeMedia();
    const s = new PlayerSession(deps(api, { server: START_CAPS }));
    await s.start(asMedia(media), { ...target, startAt: 120 });
    media.emit('loadedmetadata');
    expect(s.offset).toBe(0);
    expect(media.currentTime).toBe(120);
  });

  it('stopt de oude omzetsessie en wacht daarop voordat het nieuwe plan vertrekt', async () => {
    const api = fakeApi({ plan: keyframePlan });
    let stopped: () => void = () => undefined;
    const s = new PlayerSession(deps(api, { server: START_CAPS }));
    const media = asMedia(fakeMedia());
    await s.start(media, { ...target, startAt: 60 });
    api.stop = vi.fn((id: string) => {
      api.calls.push(`stop ${id}`);
      return new Promise<void>((r) => (stopped = r));
    });
    const second = s.start(media, { ...target, startAt: 600 });
    await Promise.resolve();
    await Promise.resolve();
    expect(api.calls).toEqual(['plan item-1', 'stop sess-1']);
    stopped();
    await second;
    expect(api.calls).toEqual(['plan item-1', 'stop sess-1', 'plan item-1']);
    expect(s.offset).toBe(594);
  });
});

describe('opnieuw na een fout', () => {
  it('wacht de DELETE van de gestrande sessie af voordat het nieuwe plan vertrekt', async () => {
    const api = fakeApi({ plan: keyframePlan });
    let stopped: () => void = () => undefined;
    api.stop = vi.fn((id: string) => {
      api.calls.push(`stop ${id}`);
      return new Promise<void>((r) => (stopped = r));
    });
    const hls = fakeHls();
    const s = new PlayerSession(deps(api, { hls, server: START_CAPS }));
    const media = asMedia(fakeMedia());
    await s.start(media, { ...target, startAt: 60 });
    hls.instances[0]!.emit('hlsError', { type: 'networkError', details: 'fragLoadError', fatal: true, response: { code: 404 } });
    expect(s.phase).toBe('error');

    const retry = s.start(media, { ...target, startAt: 60 });
    await Promise.resolve();
    await Promise.resolve();
    expect(api.calls).toEqual(['plan item-1', 'stop sess-1']);
    stopped();
    await retry;
    expect(api.calls).toEqual(['plan item-1', 'stop sess-1', 'plan item-1']);
  });

  it('een DELETE die nooit antwoordt houdt de volgende start hooguit STOP_WAIT_MS op', async () => {
    vi.useFakeTimers();
    try {
      const api = fakeApi({ plan: keyframePlan });
      const s = new PlayerSession(deps(api, { server: START_CAPS }));
      const media = asMedia(fakeMedia());
      await s.start(media, { ...target, startAt: 60 });
      api.stop = vi.fn((id: string) => {
        api.calls.push(`stop ${id}`);
        return new Promise<void>(() => undefined);
      });
      const second = s.start(media, { ...target, startAt: 600 });
      await vi.advanceTimersByTimeAsync(STOP_WAIT_MS - 1);
      expect(api.calls).toEqual(['plan item-1', 'stop sess-1']);
      expect(s.phase).toBe('loading');
      await vi.advanceTimersByTimeAsync(1);
      await second;
      expect(api.calls).toEqual(['plan item-1', 'stop sess-1', 'plan item-1']);
      expect(s.phase).not.toBe('loading');
    } finally {
      vi.useRealTimers();
    }
  });
});

const item: Item = {
  id: 'item-1', kind: 'movie', title: 'Dune: Part Two', year: 2024, added_at: '2026-01-01T00:00:00Z',
  versions: [{
    id: 'v-1', container: 'mkv', duration_ms: 9_963_000, file_count: 1,
    video_streams: [{ id: 'vs', index: 0, codec: 'hevc', height: 2160 }],
    audio_streams: [{ id: 'a1', index: 1, codec: 'aac', channels: 2, language: 'dut', is_default: true }],
    subtitle_streams: []
  }]
};

beforeEach(() => {
  setLocale('nl');
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockImplementation(() => Promise.resolve());
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => undefined);
  vi.spyOn(HTMLMediaElement.prototype, 'load').mockImplementation(() => undefined);
});
afterEach(() => setLocale('en'));

async function mount(server: Capabilities = START_CAPS, startAt = 3600) {
  const api = fakeApi({ plan: keyframePlan });
  const hls = fakeHls();
  render(Player, { props: { item, version: item.versions![0], startAt, deps: deps(api, { hls, server }), onclose: vi.fn(), onlogin: vi.fn() } });
  await screen.findByText('Omgezet');
  const video = document.querySelector('video')!;
  Object.defineProperty(video, 'seekable', { configurable: true, value: { length: 1, end: () => 600 } });
  return { api, hls, video };
}

const lastPlan = (api: ReturnType<typeof fakeApi>) => vi.mocked(api.plan).mock.calls.at(-1)![0];

describe('filmtijd in de speler', () => {
  it('meldt de voortgang als offset plus de tijd van het element', async () => {
    const { api, video } = await mount();
    video.currentTime = 10;
    await fireEvent.playing(video);
    await waitFor(() => expect(api.reportWatchState).toHaveBeenCalledTimes(1));
    expect(vi.mocked(api.reportWatchState).mock.calls[0]![0]).toMatchObject({ position_ms: 3_604_000 });
  });

  it('toont tijd en resterende tijd in filmtijd', async () => {
    const { video } = await mount();
    video.currentTime = 10;
    await fireEvent.timeUpdate(video);
    expect(screen.getByText('1:00:04')).toBeInTheDocument();
  });

  it('zoekt in filmtijd: tien seconden vooruit is currentTime plus tien, niet het doel zelf', async () => {
    const { video } = await mount();
    video.currentTime = 10;
    await fireEvent.timeUpdate(video);
    await fireEvent.click(screen.getByRole('button', { name: '10 seconden vooruit' }));
    expect(video.currentTime).toBe(20);
  });

  it('vraagt voor een punt vóór het begin van de stream een nieuw plan vanaf dat punt', async () => {
    const { api, video } = await mount();
    video.currentTime = 2;
    await fireEvent.timeUpdate(video);
    await fireEvent.keyDown(window, { key: 'ArrowLeft' });
    await waitFor(() => expect(api.plan).toHaveBeenCalledTimes(2));
    expect(lastPlan(api)).toMatchObject({ start_position_ms: 3_586_000 });
    expect(api.stops).toEqual([{ id: 'sess-1', keepalive: false }]);
  });

  it('vraagt bij een kwaliteitswissel het plan vanaf de huidige positie, zonder de waarschuwing', async () => {
    const { api, video } = await mount();
    video.currentTime = 6;
    await fireEvent.timeUpdate(video);
    await fireEvent.click(screen.getByRole('button', { name: 'Instellingen' }));
    await fireEvent.click(screen.getByRole('menuitem', { name: /Kwaliteit/ }));
    expect(screen.queryByText(/Omzetten begint bij het begin/)).toBeNull();
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /^720p/ }));
    await waitFor(() => expect(api.plan).toHaveBeenCalledTimes(2));
    expect(lastPlan(api)).toMatchObject({ start_position_ms: 3_600_000, quality: { max_height: 720 } });
  });

  it('negatieve controle: zonder capability blijft de waarschuwing en gaat er geen positie mee', async () => {
    const { api, video } = await mount({ ...SERVER_CAPS, playback_quality: true });
    video.currentTime = 600;
    await fireEvent.timeUpdate(video);
    await fireEvent.click(screen.getByRole('button', { name: 'Instellingen' }));
    await fireEvent.click(screen.getByRole('menuitem', { name: /Kwaliteit/ }));
    expect(screen.getByText(/Omzetten begint bij het begin/)).toBeInTheDocument();
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /^720p/ }));
    await waitFor(() => expect(api.plan).toHaveBeenCalledTimes(2));
    expect(lastPlan(api)).not.toHaveProperty('start_position_ms');
  });
});

describe('Opnieuw en ondertitels in de speler', () => {
  it('"Opnieuw" gaat verder waar het speelde, niet waar de laatste start begon', async () => {
    const { api, hls, video } = await mount();
    video.currentTime = 30;
    await fireEvent.timeUpdate(video);
    hls.instances[0]!.emit('hlsError', { type: 'networkError', details: 'fragLoadError', fatal: true, response: { code: 404 } });
    await fireEvent.click(await screen.findByRole('button', { name: 'Opnieuw proberen' }));
    await waitFor(() => expect(api.plan).toHaveBeenCalledTimes(2));
    expect(lastPlan(api)).toMatchObject({ start_position_ms: 3_624_000 });
  });

  it('geeft de offset van de stream aan de ondertitels', async () => {
    const setOffset = vi.spyOn(PlayerSubtitles.prototype, 'setOffset');
    await mount();
    await waitFor(() => expect(setOffset).toHaveBeenLastCalledWith(3594));
    setOffset.mockRestore();
  });
});

describe('ondertitels in filmtijd', () => {
  const cue = (startTime: number) => ({ startTime, endTime: startTime + 2, text: 'x' });
  const fakeTrack = (cues: ReturnType<typeof cue>[]) => ({ mode: 'hidden', cues, activeCues: null });
  const event = (type: string, track: unknown) => ({ type, currentTarget: { track } }) as unknown as Event;

  it('schuift de cues met de offset terug, ook na een nieuw plan op een ander punt', () => {
    const subs = new PlayerSubtitles({ subtitleText: vi.fn() }, () => undefined);
    const track = fakeTrack([cue(3605), cue(10)]);
    subs.setOffset(3594);
    subs.syncCues(event('load', track));
    expect(track.cues.map((c) => c.startTime)).toEqual([11, 10 - 3594]);
    subs.setOffset(594);
    expect(track.cues[0]!.startTime).toBe(3011);
    subs.syncCues(event('cuechange', track));
    expect(track.cues[0]!.startTime).toBe(3011);
  });

  it('verschuift een vers geladen spoor opnieuw, en zonder offset niets', () => {
    const subs = new PlayerSubtitles({ subtitleText: vi.fn() }, () => undefined);
    const track = fakeTrack([cue(5)]);
    subs.syncCues(event('load', track));
    expect(track.cues[0]!.startTime).toBe(5);
    subs.setOffset(4);
    track.cues = [cue(5)];
    subs.syncCues(event('load', track));
    expect(track.cues[0]!.startTime).toBe(1);
  });
});
