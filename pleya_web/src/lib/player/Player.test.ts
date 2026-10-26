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

function mount(api = fakeApi(), extra: { onclose?: () => void; onlogin?: () => void } = {}) {
  const onclose = extra.onclose ?? vi.fn();
  const onlogin = extra.onlogin ?? vi.fn();
  const view = render(Player, {
    props: { item, version: item.versions![0], deps: deps(api), onclose, onlogin }
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
    expect(api.subtitleText).toHaveBeenCalledWith('sub-nl');
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
