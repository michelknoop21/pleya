/**
 * De spoorkeuze van het filmdetail op weg naar de speler: in de link, in de
 * planaanvraag en op het element.
 */
import { cleanup, fireEvent, render, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import type { Item } from '../api/types';
import Player from './Player.svelte';
import { SERVER_CAPS, deps, fakeApi } from './playerFake';
import { playerHref } from './route';

const item: Item = {
  id: 'item-1', kind: 'movie', title: 'Film', added_at: '2026-01-01T00:00:00Z',
  versions: [{
    id: 'v-1', container: 'mp4', duration_ms: 60_000, file_count: 1,
    audio_streams: [
      { id: 'a-en', index: 1, codec: 'aac', language: 'eng', is_default: true },
      { id: 'a-nl', index: 2, codec: 'aac', language: 'nld', is_default: false }
    ],
    subtitle_streams: [
      { id: 's-nl', format: 'vtt', is_external: true, is_forced: false, is_hearing_impaired: false, is_default: false, language: 'nld' },
      { id: 's-pgs', format: 'pgs', index: 3, is_external: false, is_forced: false, is_hearing_impaired: false, is_default: false }
    ]
  }]
};

beforeEach(() => {
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockImplementation(() => Promise.resolve());
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => undefined);
  vi.spyOn(HTMLMediaElement.prototype, 'load').mockImplementation(() => undefined);
  URL.createObjectURL = vi.fn(() => 'blob:http://pleya.test/vtt');
  URL.revokeObjectURL = vi.fn();
});

function mount(picks: { audioId?: string; subtitleId?: string }, audioSelection = true) {
  const api = fakeApi();
  render(Player, { props: {
    item, version: item.versions![0], ...picks, onclose: vi.fn(), onlogin: vi.fn(),
    deps: deps(api, { server: { ...SERVER_CAPS, playback_audio_selection: audioSelection } })
  } });
  return api;
}
const ready = async (api: ReturnType<typeof fakeApi>) => {
  await waitFor(() => expect(api.plan).toHaveBeenCalled());
  await waitFor(() => expect(document.querySelector('video')?.getAttribute('src')).toBeTruthy());
  await fireEvent.loadedMetadata(document.querySelector('video')!);
};

describe('spoorkeuze naar de speler', () => {
  it('zet de keuze in de spelerlink en laat hem weg zonder keuze', () => {
    expect(playerHref('m', 12_000, 'v', undefined, { audio: 'a-nl', subtitle: 's-nl' })).toBe('/items/m/play?t=12&version=v&audio=a-nl&subtitle=s-nl');
    expect(playerHref('m', 12_000, 'v', undefined, {})).toBe('/items/m/play?t=12&version=v');
  });

  it('vraagt het plan om het gekozen audiospoor en zet de gekozen ondertitel aan', async () => {
    const api = mount({ audioId: 'a-nl', subtitleId: 's-nl' });
    await ready(api);
    expect(api.plan).toHaveBeenCalledWith(expect.objectContaining({ version_id: 'v-1', audio_stream_id: 'a-nl' }));
    await waitFor(() => expect(api.subtitleText).toHaveBeenCalledWith('s-nl', expect.any(AbortSignal)));
  });

  it('laat het plan met rust voor het standaardspoor, zonder capability en zonder keuze', async () => {
    for (const [picks, selection] of [[{ audioId: 'a-en' }, true], [{ audioId: 'a-nl' }, false], [{}, true]] as const) {
      const api = mount(picks, selection);
      await ready(api);
      expect(vi.mocked(api.plan).mock.calls[0]![0]).not.toHaveProperty('audio_stream_id');
      expect(api.subtitleText).not.toHaveBeenCalled();
      cleanup();
    }
  });

  it('vraagt geen ondertitel op die de browser niet kan tonen', async () => {
    const api = mount({ subtitleId: 's-pgs' });
    await ready(api);
    expect(api.subtitleText).not.toHaveBeenCalled();
  });
});
