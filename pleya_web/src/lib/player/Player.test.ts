/**
 * De spelerschil als component: laden, spelen met besturing, de foutstaat met
 * uitweg, de spoorkiezer, het toetsenbord, en opruimen bij unmount en
 * `pagehide`. De `<video>` van jsdom decodeert niets; play, pause en load zijn
 * hier gestubd.
 */
import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Item } from '../api/types';
import { setLocale } from '../i18n';
import Player from './Player.svelte';
import { apiError, deps, fakeApi, transcodePlan } from './playerFake';
import { SubtitleNotReadyError } from './subtitleRetry';

const item: Item = {
  id: 'item-1',
  kind: 'movie',
  title: 'Dune: Part Two',
  year: 2024,
  added_at: '2026-01-01T00:00:00Z',
  versions: [
    {
      id: 'v-1',
      container: 'mp4',
      duration_ms: 9_963_000,
      file_count: 1,
      video_streams: [{ id: 'vs', index: 0, codec: 'hevc', height: 2160 }],
      audio_streams: [{ id: 'a1', index: 1, codec: 'aac', channels: 2, language: 'dut', is_default: true }],
      subtitle_streams: [
        { id: 'sub-nl', format: 'vtt', is_external: true, is_forced: false, is_hearing_impaired: false, is_default: false, language: 'dut' },
        { id: 'sub-x', format: 'pgs', index: 3, is_external: false, is_forced: false, is_hearing_impaired: false, is_default: false }
      ]
    }
  ]
};

beforeEach(() => {
  setLocale('nl');
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockImplementation(() => Promise.resolve());
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => undefined);
  vi.spyOn(HTMLMediaElement.prototype, 'load').mockImplementation(() => undefined);
  URL.createObjectURL = vi.fn(() => 'blob:http://pleya.test/vtt');
  URL.revokeObjectURL = vi.fn();
});
afterEach(() => setLocale('en'));

function mount(api = fakeApi(), extra: { onclose?: () => void; onlogin?: () => void; startAt?: number } = {}) {
  const onclose = extra.onclose ?? vi.fn();
  const onlogin = extra.onlogin ?? vi.fn();
  const view = render(Player, {
    props: { item, version: item.versions![0], deps: deps(api), onclose, onlogin, ...(extra.startAt ? { startAt: extra.startAt } : {}) }
  });
  return { api, view, onclose, onlogin };
}

describe('spelerschil', () => {
  it('toont titel, regel en wat er speelt, met benoemde besturing', async () => {
    mount();
    expect(screen.getByRole('heading', { name: 'Dune: Part Two' })).toBeInTheDocument();
    await screen.findByRole('button', { name: '10 seconden vooruit' });
    expect(screen.getByText(/2024 · 2u 46m/)).toBeInTheDocument();
    expect(screen.getByText('Direct afspelen · HEVC 4K')).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'Afspelen' }).length).toBeGreaterThan(0);
    expect(screen.getByRole('slider', { name: 'Positie' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Volledig scherm' })).toBeInTheDocument();
    expect(document.querySelector('video')?.getAttribute('src')).toBe('/pleya/v1/stream/v-1?ss=ss-1');
  });

  it('laat tijdens het laden een status zien', () => {
    const api = fakeApi({ plan: () => new Promise(() => undefined) });
    mount(api);
    expect(screen.getByRole('status')).toHaveTextContent('Afspelen wordt voorbereid');
  });

  it('toont een fout met een zin en opnieuw proberen, dat opnieuw start', async () => {
    let fail = true;
    const api = fakeApi({
      plan: async () => {
        if (fail) throw apiError('playback.transcode_busy', 503);
        return transcodePlan();
      }
    });
    mount(api);
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Alle omzetplekken op de server zijn bezet');
    fail = false;
    await fireEvent.click(screen.getByRole('button', { name: 'Opnieuw proberen' }));
    await screen.findByText('Omgezet');
    expect(api.plan).toHaveBeenCalledTimes(2);
  });

  it('biedt bij een verlopen sessie inloggen aan', async () => {
    const api = fakeApi({
      plan: async () => {
        throw apiError('auth.token_invalid', 401);
      }
    });
    const { onlogin } = mount(api);
    await fireEvent.click(await screen.findByRole('button', { name: 'Inloggen' }));
    expect(onlogin).toHaveBeenCalled();
  });

  it('opent de spoorkiezer met alleen WebVTT en laadt de gekozen ondertitel', async () => {
    const { api } = mount();
    await screen.findByRole('button', { name: '10 seconden vooruit' });
    await fireEvent.click(screen.getByRole('button', { name: 'Audio en ondertitels' }));
    const dialog = screen.getByRole('dialog', { name: 'Audio en ondertitels' });
    expect(dialog).toHaveTextContent('1 ondertitel moet eerst omgezet worden');
    await fireEvent.click(screen.getByRole('radio', { name: 'Nederlands' }));
    await waitFor(() => expect(document.querySelector('track')).not.toBeNull());
    expect(api.subtitleText).toHaveBeenCalledWith('sub-nl', expect.any(AbortSignal));
    expect(document.querySelector('track')?.getAttribute('src')).toBe('blob:http://pleya.test/vtt');
    await fireEvent.keyDown(window, { key: 'Escape' });
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('bedient spatie en m vanaf het toetsenbord', async () => {
    mount();
    await screen.findByRole('button', { name: '10 seconden vooruit' });
    const video = document.querySelector('video')!;
    const play = vi.mocked(HTMLMediaElement.prototype.play);
    play.mockClear();
    Object.defineProperty(video, 'paused', { configurable: true, value: true });
    await fireEvent.keyDown(window, { key: ' ' });
    expect(play).toHaveBeenCalledTimes(1);
    await fireEvent.keyDown(window, { key: 'm' });
    expect(video.muted).toBe(true);
  });
});

describe('opruimen', () => {
  it('stopt de omzetsessie bij unmount', async () => {
    const api = fakeApi({ plan: async () => transcodePlan() });
    const { view } = mount(api);
    await screen.findByText('Omgezet');
    expect(api.stops).toEqual([]);
    view.unmount();
    expect(api.stops).toEqual([{ id: 'sess-1', keepalive: false }]);
  });

  it('stopt hem met keepalive bij pagehide', async () => {
    const api = fakeApi({ plan: async () => transcodePlan() });
    mount(api);
    await screen.findByText('Omgezet');
    window.dispatchEvent(new Event('pagehide'));
    expect(api.stops).toEqual([{ id: 'sess-1', keepalive: true }]);
  });

  it('de terugknop roept sluiten aan', async () => {
    const { onclose } = mount();
    await fireEvent.click(screen.getByRole('button', { name: 'Terug' }));
    expect(onclose).toHaveBeenCalled();
  });
});

describe('public browser watch-state actions', () => {
  it('reports only after actual playback, then pause, seek and pagehide', async () => {
    const { api } = mount();
    await screen.findByText('Direct afspelen · HEVC 4K');
    expect(api.reportWatchState).not.toHaveBeenCalled();
    const video = document.querySelector('video')!;
    await fireEvent.play(video);
    expect(api.reportWatchState).not.toHaveBeenCalled();
    video.currentTime = 15;
    await fireEvent.playing(video);
    await waitFor(() => expect(api.reportWatchState).toHaveBeenCalledTimes(1));
    expect(vi.mocked(api.reportWatchState).mock.calls[0]![0]).toMatchObject({ explicit_action: 'playback_started', position_ms: 15000 });
    video.currentTime = 20;
    await fireEvent.pause(video);
    await waitFor(() => expect(api.reportWatchState).toHaveBeenCalledTimes(2));
    video.currentTime = 30;
    await fireEvent.seeked(video);
    await waitFor(() => expect(api.reportWatchState).toHaveBeenCalledTimes(3));
    window.dispatchEvent(new Event('pagehide'));
    await waitFor(() => expect(api.reportWatchState).toHaveBeenCalledTimes(4));
    expect(vi.mocked(api.reportWatchState).mock.calls[3]).toEqual([expect.objectContaining({ position_ms: 30000, explicit_action: 'none' }), true]);
  });

  it('a media error after minute 50 reports the last position, not the emptied element', async () => {
    const { api } = mount();
    await screen.findByText('Direct afspelen · HEVC 4K');
    const video = document.querySelector('video')!;
    video.currentTime = 3000;
    await fireEvent.playing(video);
    await fireEvent.timeUpdate(video);
    await waitFor(() => expect(api.reportWatchState).toHaveBeenCalledTimes(1));
    // Teardown resets the element before the error effect samples it.
    vi.mocked(HTMLMediaElement.prototype.load).mockImplementation(function (this: HTMLMediaElement) { this.currentTime = 0; });
    Object.defineProperty(video, 'error', { value: { code: 4 }, configurable: true });
    await fireEvent.error(video);
    await waitFor(() => expect(api.reportWatchState).toHaveBeenCalledTimes(2));
    expect(vi.mocked(api.reportWatchState).mock.calls[1]![0]).toMatchObject({ position_ms: 3000000, explicit_action: 'none' });
  });

  it('a transcoded stream that ignores the resume position reports nothing', async () => {
    const api = fakeApi({ plan: async () => transcodePlan() });
    mount(api, { startAt: 3000 });
    await waitFor(() => expect(document.querySelector('video')).not.toBeNull());
    await screen.findByRole('button', { name: '10 seconden vooruit' });
    await fireEvent.playing(document.querySelector('video')!);
    await new Promise(resolve => setTimeout(resolve, 0));
    expect(api.reportWatchState).not.toHaveBeenCalled();
  });
});

describe('subtitle delivery through the public player', () => {
  it('offers SRT and passes its format into the browser track conversion', async () => {
    const api = fakeApi();
    vi.mocked(api.subtitleText).mockResolvedValue('1\n00:00:00,000 --> 00:00:05,000\nHello');
    const version = { ...item.versions![0]!, subtitle_streams: [{ id: 'srt', format: 'srt' as const,
      is_external: true, is_default: false, is_forced: false, is_hearing_impaired: false, title: 'Sidecar SRT' }] };
    render(Player, { props: { item, version, deps: deps(api), onclose: vi.fn(), onlogin: vi.fn() } });
    await screen.findByText('Direct afspelen · HEVC 4K');
    await fireEvent.click(screen.getByRole('button', { name: 'Ondertitels' }));
    await fireEvent.click(screen.getByRole('radio', { name: 'Sidecar SRT' }));
    await waitFor(() => expect(document.querySelector('track')).toHaveAttribute('src', 'blob:http://pleya.test/vtt'));
    expect(api.subtitleText).toHaveBeenCalledWith('srt', expect.any(AbortSignal));
  });
  it('reports a failed replacement and keeps the previous subtitle selected', async () => {
    const api = fakeApi(); mount(api);
    await screen.findByText('Direct afspelen · HEVC 4K');
    await fireEvent.click(screen.getByRole('button', { name: 'Ondertitels' }));
    vi.mocked(api.subtitleText).mockRejectedValueOnce(new Error('offline'));
    await fireEvent.click(screen.getByRole('radio', { name: 'Nederlands' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('De ondertitel kon niet worden geladen');
    expect(screen.getByRole('radio', { name: 'Uit' })).toBeChecked();
  });
});

describe('embedded subtitle the server is still preparing', () => {
  const embedded = {
    ...item.versions![0]!,
    subtitle_streams: [{
      id: 'embedded', format: 'srt' as const, is_external: false, is_default: false,
      is_forced: false, is_hearing_impaired: false, title: 'Ingebed', index: 2
    }]
  };
  const open = async (api: ReturnType<typeof fakeApi>) => {
    const base = deps(api);
    render(Player, { props: { item, version: embedded, deps: { ...base, server: { ...base.server!, embedded_subtitles: true } }, onclose: vi.fn(), onlogin: vi.fn() } });
    await screen.findByText('Direct afspelen · HEVC 4K');
    await fireEvent.click(screen.getByRole('button', { name: 'Ondertitels' }));
    await fireEvent.click(screen.getByRole('radio', { name: 'Ingebed' }));
  };

  it('names the wait on the subtitle button and shows the track without an action', async () => {
    const api = fakeApi();
    let finish!: (body: string) => void;
    vi.mocked(api.subtitleText)
      .mockRejectedValueOnce(new SubtitleNotReadyError(1))
      .mockImplementationOnce(() => new Promise(resolve => finish = resolve));
    await open(api);
    await fireEvent.click(screen.getByRole('button', { name: 'Sluiten' }));
    expect(screen.getByRole('status')).toHaveTextContent('Ondertitels voorbereiden');
    expect(screen.getByRole('button', { name: 'Ondertitels voorbereiden' })).toBeInTheDocument();
    await waitFor(() => expect(api.subtitleText).toHaveBeenCalledTimes(2));
    finish('1\n00:00:00,000 --> 00:00:05,000\nHallo');
    await waitFor(() => expect(document.querySelector('track')).not.toBeNull());
    expect(screen.queryByRole('status')).toBeNull();
    expect(screen.getByRole('button', { name: 'Ondertitels' })).toBeInTheDocument();
  });

  it('offers Opnieuw after a failure while the film keeps playing', async () => {
    const api = fakeApi();
    vi.mocked(api.subtitleText).mockRejectedValueOnce(new Error('subtitle 502'));
    await open(api);
    expect(await screen.findByRole('alert')).toHaveTextContent('Ondertitels konden niet worden voorbereid');
    expect(document.querySelector('video')?.getAttribute('src')).toBe('/pleya/v1/stream/v-1?ss=ss-1');
    await fireEvent.click(screen.getByRole('button', { name: 'Sluiten' }));
    expect(screen.getByRole('status')).toHaveTextContent('Ondertitels konden niet worden voorbereid');
    vi.mocked(api.subtitleText).mockResolvedValueOnce('1\n00:00:00,000 --> 00:00:05,000\nHallo');
    // Voorbij het venster waarin de server zijn fout onthoudt (playerSubtitles.test.ts).
    const later = Date.now() + 16_000;
    const clock = vi.spyOn(Date, 'now').mockReturnValue(later);
    await fireEvent.click(screen.getByRole('button', { name: 'Opnieuw' }));
    await waitFor(() => expect(document.querySelector('track')).not.toBeNull());
    clock.mockRestore();
    expect(api.subtitleText).toHaveBeenCalledTimes(2);
    expect(screen.queryByRole('status')).toBeNull();
  });
});

it('keeps an already loaded subtitle when a replacement fails', async () => {
  const api = fakeApi();
  const version = { ...item.versions![0]!, subtitle_streams: [...item.versions![0]!.subtitle_streams!, {
    id: 'replacement', format: 'srt' as const, is_external: true, is_default: false,
    is_forced: false, is_hearing_impaired: false, title: 'Replacement'
  }] };
  render(Player, { props: { item, version, deps: deps(api), onclose: vi.fn(), onlogin: vi.fn() } });
  await screen.findByText('Direct afspelen · HEVC 4K');
  await fireEvent.click(screen.getByRole('button', { name: 'Ondertitels' }));
  await fireEvent.click(screen.getByRole('radio', { name: 'Nederlands' }));
  await waitFor(() => expect(document.querySelector('track')).not.toBeNull());
  vi.mocked(api.subtitleText).mockRejectedValueOnce(new Error('offline'));
  await fireEvent.click(screen.getByRole('radio', { name: 'Replacement' }));
  await screen.findByRole('alert');
  expect(screen.getByRole('radio', { name: 'Nederlands' })).toBeChecked();
  expect(document.querySelector('track')).toHaveAttribute('src', 'blob:http://pleya.test/vtt');
  expect(URL.revokeObjectURL).not.toHaveBeenCalled();
});

it.each(['off', 'unmount'])('aborts pending subtitles on %s and releases a late blob', async action => {
  const api = fakeApi();
  let release!: (body: string) => void;
  vi.mocked(api.subtitleText).mockImplementationOnce(() => new Promise(resolve => release = resolve));
  const { view } = mount(api);
  await screen.findByText('Direct afspelen · HEVC 4K');
  await fireEvent.click(screen.getByRole('button', { name: 'Ondertitels' }));
  await fireEvent.click(screen.getByRole('radio', { name: 'Nederlands' }));
  const signal = vi.mocked(api.subtitleText).mock.calls.at(-1)![1]!;
  if (action === 'off') await fireEvent.click(screen.getByRole('radio', { name: 'Uit' }));
  else view.unmount();
  expect(signal.aborted).toBe(true);
  release('WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nLate caption\n');
  await waitFor(() => expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:http://pleya.test/vtt'));
  expect(document.querySelector('track')).toBeNull();
});

it('closes the track menu with Escape from a radio and returns focus to its opener', async () => {
  mount();
  await screen.findByText('Direct afspelen · HEVC 4K');
  const opener = screen.getByRole('button', { name: 'Ondertitels' });
  opener.focus();
  await fireEvent.click(opener);
  await screen.findByRole('dialog');
  expect(document.activeElement?.tagName).toBe('INPUT');
  await fireEvent.keyDown(document.activeElement!, { key: 'Escape' });
  await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());
  expect(opener).toHaveFocus();
});

it('tells the route when the title played to its end, so a playlist can go on', async () => {
  const onfinished = vi.fn();
  render(Player, { props: { item, version: item.versions![0]!, deps: deps(fakeApi()), onclose: vi.fn(), onlogin: vi.fn(), onfinished } });
  const video = document.querySelector('video')!;
  expect(onfinished).not.toHaveBeenCalled();
  await fireEvent.ended(video);
  expect(onfinished).toHaveBeenCalledTimes(1);
});
