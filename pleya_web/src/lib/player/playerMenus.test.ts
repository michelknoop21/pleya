/**
 * Het doelbeeld Kijken-speler als component: het instellingenmenu (kwaliteit,
 * audio, snelheid, beeldverhouding, afspeelinfo), de ondertitelgrootte, de
 * kaart "volgende aflevering" en het slotscherm.
 */
import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { createRawSnippet, type Snippet } from 'svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Item } from '../api/types';
import { setLocale } from '../i18n';
import Player from './Player.svelte';
import { SERVER_CAPS, deps, fakeApi, transcodePlan } from './playerFake';

const item: Item = {
  id: 'e3', kind: 'episode', title: 'Wie leeft er', index: 3, parent_id: 's2', added_at: '2026-01-01T00:00:00Z',
  versions: [{
    id: 'v-1', container: 'mkv', duration_ms: 3_000_000, file_count: 1,
    video_streams: [{ id: 'vs', index: 0, codec: 'hevc', profile: 'Main 10', width: 3840, height: 2160 }],
    audio_streams: [
      { id: 'a-en', index: 1, codec: 'eac3', channels: 6, language: 'eng', is_default: true },
      { id: 'a-nl', index: 2, codec: 'aac', channels: 2, language: 'nld', is_default: false }
    ],
    subtitle_streams: [
      { id: 's-nl', format: 'srt', is_external: true, is_forced: false, is_hearing_impaired: false, is_default: false, language: 'nld' }
    ]
  }]
};
const following: Item = { id: 'e4', kind: 'episode', title: 'Dal van wee', index: 4, parent_id: 's2', duration_ms: 3_060_000, added_at: '2026-01-01T00:00:00Z' };

beforeEach(() => {
  setLocale('nl');
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockImplementation(() => Promise.resolve());
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => undefined);
  vi.spyOn(HTMLMediaElement.prototype, 'load').mockImplementation(() => undefined);
  URL.createObjectURL = vi.fn(() => 'blob:http://pleya.test/vtt');
  URL.revokeObjectURL = vi.fn();
});
afterEach(() => setLocale('en'));

type Extra = Partial<{ audioId: string; next: Item | null; onnext: () => void | Promise<unknown>; onfinished: () => void; end: Snippet<[{ replay: () => void }]>; caps: Record<string, boolean> }>;

async function mount(extra: Extra = {}, api = fakeApi()) {
  const { caps, ...props } = extra;
  render(Player, {
    props: {
      item, version: item.versions![0], heading: 'Severance', subheading: 'S2 · A3 · Wie leeft er',
      deps: deps(api, { server: { ...SERVER_CAPS, ...caps } }), onclose: vi.fn(), onlogin: vi.fn(), ...props
    }
  });
  await screen.findByRole('button', { name: '10 seconden vooruit' });
  await waitFor(() => expect(document.querySelector('video')?.getAttribute('src')).toBeTruthy());
  return { api, video: document.querySelector('video')! };
}

/** Zet de afspeelpositie zoals een `timeupdate` van de browser dat doet. */
async function at(video: HTMLVideoElement, seconds: number): Promise<void> {
  video.currentTime = seconds;
  await fireEvent.timeUpdate(video);
}

const settings = () => fireEvent.click(screen.getByRole('button', { name: 'Instellingen' }));

describe('kop en onderbalk', () => {
  it('toont de serie als kop met seizoen, aflevering en titel eronder', async () => {
    await mount();
    expect(screen.getByRole('heading', { name: 'Severance' })).toBeInTheDocument();
    expect(screen.getByText('S2 · A3 · Wie leeft er')).toBeInTheDocument();
  });

  it('toont de resterende tijd en hoe laat de aflevering klaar is', async () => {
    const { video } = await mount();
    await at(video, 1274);
    expect(screen.getByText('21:14')).toBeInTheDocument();
    expect(screen.getByText('nog 28:46')).toBeInTheDocument();
    expect(screen.getByText(/^· klaar om \d{2}:\d{2}$/)).toBeInTheDocument();
  });

  it('biedt de knop volgende aflevering alleen aan als er een is', async () => {
    const onnext = vi.fn();
    await mount({ next: following, onnext });
    await fireEvent.click(screen.getByRole('button', { name: 'Volgende aflevering' }));
    expect(onnext).toHaveBeenCalledTimes(1);
  });

  it('heeft zonder volgende aflevering geen knop daarvoor', async () => {
    await mount({ next: null, onnext: vi.fn() });
    expect(screen.queryByRole('button', { name: 'Volgende aflevering' })).toBeNull();
  });
});

describe('instellingenmenu', () => {
  it('toont audio, snelheid, beeldverhouding en afspeelinfo met hun huidige waarde', async () => {
    await mount();
    await settings();
    const menu = screen.getByRole('menu', { name: 'Instellingen' });
    expect(menu).toHaveTextContent('AudioEngels · eac3 · 6ch');
    expect(menu).toHaveTextContent('Snelheid1×');
    expect(menu).toHaveTextContent('BeeldverhoudingAutomatisch');
    expect(menu).toHaveTextContent('Afspeelinfouit');
    expect(screen.queryByRole('menuitem', { name: /Kwaliteit/ })).toBeNull();
    await fireEvent.keyDown(window, { key: 'Escape' });
    expect(screen.queryByRole('menu')).toBeNull();
  });

  it('vraagt bij een kwaliteitskeuze een nieuw plan met de limiet en zegt dat omzetten bij het begin start', async () => {
    const api = fakeApi({ plan: async () => transcodePlan() });
    const hls = (await import('./playerFake')).fakeHls();
    render(Player, {
      props: { item, version: item.versions![0], deps: deps(api, { hls, server: { ...SERVER_CAPS, playback_quality: true } }), onclose: vi.fn(), onlogin: vi.fn() }
    });
    await screen.findByText('Omgezet');
    const video = document.querySelector('video')!;
    await at(video, 600);
    await settings();
    await fireEvent.click(screen.getByRole('menuitem', { name: /Kwaliteit/ }));
    expect(screen.getByRole('menuitemradio', { name: 'Origineel · 4K' })).toHaveAttribute('aria-checked', 'true');
    // De server zet om vanaf nul en het plan kent geen startpositie: het menu belooft geen hervatten.
    expect(screen.getByText(/Omzetten begint bij het begin/)).toBeInTheDocument();
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /^720p/ }));
    await waitFor(() => expect(api.plan).toHaveBeenCalledTimes(2));
    expect(vi.mocked(api.plan).mock.calls[0]![0]).not.toHaveProperty('quality');
    expect(vi.mocked(api.plan).mock.calls[1]![0]).toMatchObject({ quality: { max_video_bitrate_kbps: 4000, max_height: 720 } });
  });

  it('vraagt bij een ander audiospoor een nieuw plan als de browser zelf niet kan wisselen', async () => {
    const { api, video } = await mount({ caps: { playback_audio_selection: true } });
    await at(video, 90);
    await settings();
    await fireEvent.click(screen.getByRole('menuitem', { name: /Audio/ }));
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Nederlands/ }));
    await waitFor(() => expect(api.plan).toHaveBeenCalledTimes(2));
    expect(vi.mocked(api.plan).mock.calls[1]![0]).toMatchObject({ version_id: 'v-1', audio_stream_id: 'a-nl' });
    expect(screen.getByText(/Omzetten begint bij het begin/)).toBeInTheDocument();
  });
  it('hervat direct play na een wissel op de positie, ook in het laatste tiende en na een tweede keuze tijdens het laden', async () => {
    let release: () => void = () => undefined;
    let slow = false;
    const api = fakeApi({ plan: async () => { if (slow) await new Promise<void>((r) => (release = r)); return (await import('./playerFake')).plan(); } });
    const { video } = await mount({ caps: { playback_audio_selection: true } }, api);
    Object.defineProperty(video, 'duration', { configurable: true, value: 3000 });
    await at(video, 2800);
    await settings();
    await fireEvent.click(screen.getByRole('menuitem', { name: /Audio/ }));
    slow = true;
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Nederlands/ }));
    // Het element is nu leeg, zoals na `load()` in de browser.
    await at(video, 0);
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Nederlands/ }));
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Engels/ }));
    slow = false;
    release();
    await waitFor(() => expect(video.getAttribute('src')).toBeTruthy());
    await screen.findByRole('button', { name: '10 seconden vooruit' });
    await fireEvent.loadedMetadata(video);
    expect(video.currentTime).toBe(2800);
  });
  it('gaat met Opnieuw na een mislukte wissel verder waar de wissel begon', async () => {
    let fail = false;
    const api = fakeApi({ plan: async () => { if (fail) throw (await import('./playerFake')).apiError('transcode.busy', 503); return (await import('./playerFake')).plan(); } });
    const { video } = await mount({ caps: { playback_audio_selection: true } }, api);
    Object.defineProperty(video, 'duration', { configurable: true, value: 3000 });
    await at(video, 900);
    await settings();
    await fireEvent.click(screen.getByRole('menuitem', { name: /Audio/ }));
    fail = true;
    await fireEvent.click(screen.getByRole('menuitemradio', { name: /Nederlands/ }));
    await at(video, 0);
    fail = false;
    await fireEvent.click(await screen.findByRole('button', { name: 'Opnieuw proberen' }));
    await waitFor(() => expect(video.getAttribute('src')).toBeTruthy());
    await fireEvent.loadedMetadata(video);
    expect(video.currentTime).toBe(900);
  });
  it('toont zonder capability en zonder sporen op het element het spoor dat speelt, niet de wens uit de link', async () => {
    await mount({ audioId: 'a-nl' });
    await fireEvent.loadedMetadata(document.querySelector('video')!);
    await settings();
    expect(screen.getByRole('menu', { name: 'Instellingen' })).toHaveTextContent('AudioEngels · eac3 · 6ch');
  });
  it('opent de audiokeuzes ook als twee sporen hetzelfde label hebben', async () => {
    const twin = structuredClone(item);
    twin.versions![0]!.audio_streams!.push({ id: 'a-en2', index: 3, codec: 'eac3', channels: 6, language: 'eng', is_default: false });
    render(Player, { props: { item: twin, version: twin.versions![0], deps: deps(fakeApi(), { server: SERVER_CAPS }), onclose: vi.fn(), onlogin: vi.fn() } });
    await screen.findByRole('button', { name: '10 seconden vooruit' });
    await settings();
    await fireEvent.click(screen.getByRole('menuitem', { name: /Audio/ }));
    expect(screen.getAllByRole('menuitemradio', { name: 'Engels · eac3 · 6ch' })).toHaveLength(2);
  });
  it('geeft de pijlen in het menu aan het menu: focus verschuift, volume en positie blijven staan', async () => {
    const { video } = await mount();
    await at(video, 100);
    await settings();
    const rows = screen.getAllByRole('menuitem');
    expect(rows[0]).toHaveFocus();
    await fireEvent.keyDown(rows[0]!, { key: 'ArrowDown' });
    expect(rows[1]).toHaveFocus();
    await fireEvent.keyDown(rows[1]!, { key: 'ArrowUp' });
    await fireEvent.keyDown(rows[0]!, { key: 'ArrowRight' });
    expect(rows[0]).toHaveFocus();
    expect(video.volume).toBe(1);
    expect(video.currentTime).toBe(100);
  });
  it('zet de focus in een subpagina op de gekozen waarde', async () => {
    await mount();
    await settings();
    await fireEvent.click(screen.getByRole('menuitem', { name: /Snelheid/ }));
    await waitFor(() => expect(screen.getByRole('menuitemradio', { name: '1×' })).toHaveFocus());
  });

  it('laat het audiospoor vast staan zonder capability en zonder sporen op het element', async () => {
    const { api } = await mount();
    await settings();
    await fireEvent.click(screen.getByRole('menuitem', { name: /Audio/ }));
    expect(screen.getByRole('menuitemradio', { name: /Nederlands/ })).toBeDisabled();
    expect(screen.getByText(/Wisselen kan in deze browser nog niet/)).toBeInTheDocument();
    expect(api.plan).toHaveBeenCalledTimes(1);
  });

  it('zet snelheid en beeldverhouding op het element', async () => {
    const { video } = await mount();
    await settings();
    await fireEvent.click(screen.getByRole('menuitem', { name: /Snelheid/ }));
    await fireEvent.click(screen.getByRole('menuitemradio', { name: '1,5×' }));
    expect(video.playbackRate).toBe(1.5);
    await fireEvent.click(screen.getByRole('menuitem', { name: 'Terug' }));
    await fireEvent.click(screen.getByRole('menuitem', { name: /Beeldverhouding/ }));
    await fireEvent.click(screen.getByRole('menuitemradio', { name: 'Beeldvullend' }));
    expect(video).toHaveClass('player__video--cover');
  });

  it('toont afspeelinfo uit het plan, de versie en het element', async () => {
    await mount();
    await settings();
    await fireEvent.click(screen.getByRole('menuitemcheckbox', { name: /Afspeelinfo/ }));
    const info = screen.getByRole('complementary', { name: 'Afspeelinfo' });
    expect(info).toHaveTextContent('Methode Direct afspelen');
    expect(info).toHaveTextContent('Video HEVC Main 10 · 3840 × 2160');
    expect(info).toHaveTextContent('Audio Engels · eac3 · 6ch');
    expect(info).toHaveTextContent('Ondertitels Uit');
    expect(info).not.toHaveTextContent('Bitrate');
  });
});

describe('ondertitelmenu', () => {
  it('noemt formaat en herkomst en zet de grootte op de getekende ondertitel', async () => {
    await mount();
    await fireEvent.click(screen.getByRole('button', { name: 'Ondertitels' }));
    expect(screen.getByRole('dialog', { name: 'Ondertitels' })).toHaveTextContent('SRT · los bestand');
    await fireEvent.click(screen.getByRole('button', { name: 'Groot' }));
    expect(screen.getByRole('button', { name: 'Groot' })).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('button', { name: 'Normaal' })).toHaveAttribute('aria-pressed', 'false');
  });
});

describe('kaart volgende aflevering', () => {
  it('komt in de laatste dertig seconden en telt af op de afspeelpositie', async () => {
    const onnext = vi.fn();
    const { video } = await mount({ next: following, onnext });
    await at(video, 2960);
    expect(screen.queryByText('4. Dal van wee')).toBeNull();
    await at(video, 2983);
    expect(screen.getByText('4. Dal van wee')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Volgende aflevering nu afspelen, start vanzelf over 7 seconden' })).toHaveTextContent('Afspelen · 7');
    expect(onnext).not.toHaveBeenCalled();
  });

  it('start de volgende aflevering vanzelf als het aftellen op nul staat, en maar één keer', async () => {
    const onnext = vi.fn();
    const { video } = await mount({ next: following, onnext });
    await at(video, 2990);
    await waitFor(() => expect(onnext).toHaveBeenCalledTimes(1));
    await at(video, 2995);
    await fireEvent.ended(video);
    expect(onnext).toHaveBeenCalledTimes(1);
  });

  it('wacht met vanzelf doorgaan zolang een menu open staat', async () => {
    const onnext = vi.fn();
    const { video } = await mount({ next: following, onnext });
    await settings();
    await at(video, 2990);
    expect(onnext).not.toHaveBeenCalled();
    await fireEvent.keyDown(window, { key: 'Escape' });
    await waitFor(() => expect(onnext).toHaveBeenCalledTimes(1));
  });
  it('mag na een afgebroken navigatie opnieuw doorgaan', async () => {
    const onnext = vi.fn().mockRejectedValueOnce(new Error('navigation cancelled'));
    await mount({ next: following, onnext });
    await fireEvent.click(screen.getByRole('button', { name: 'Volgende aflevering' }));
    await waitFor(() => expect(onnext).toHaveBeenCalledTimes(1));
    await new Promise((r) => setTimeout(r));
    await fireEvent.click(screen.getByRole('button', { name: 'Volgende aflevering' }));
    expect(onnext).toHaveBeenCalledTimes(2);
  });
  it('start meteen op de knop', async () => {
    const onnext = vi.fn();
    const { video } = await mount({ next: following, onnext });
    await at(video, 2975);
    await fireEvent.click(screen.getByRole('button', { name: /nu afspelen/ }));
    expect(onnext).toHaveBeenCalledTimes(1);
  });

  it('laat met Aftiteling kijken het beeld doorlopen en gaat pas aan het eind door', async () => {
    const onnext = vi.fn();
    const { video } = await mount({ next: following, onnext });
    await at(video, 2975);
    await fireEvent.click(screen.getByRole('button', { name: 'Aftiteling kijken' }));
    expect(screen.queryByText('4. Dal van wee')).toBeNull();
    await at(video, 2995);
    expect(onnext).not.toHaveBeenCalled();
    await fireEvent.ended(video);
    expect(onnext).toHaveBeenCalledTimes(1);
  });

  it('komt terug na terugspoelen uit het eindvenster', async () => {
    const { video } = await mount({ next: following, onnext: vi.fn() });
    await at(video, 2975);
    await fireEvent.click(screen.getByRole('button', { name: 'Aftiteling kijken' }));
    await at(video, 100);
    await at(video, 2975);
    expect(screen.getByText('4. Dal van wee')).toBeInTheDocument();
  });
});

describe('slotscherm', () => {
  const end = () => createRawSnippet<[{ replay: () => void }]>(() => ({ render: () => '<p>slotscherm</p>' }));

  it('komt in de laatste dertig seconden van een titel waar niets op volgt', async () => {
    const { video } = await mount({ end: end() });
    await at(video, 2960);
    expect(screen.queryByText('slotscherm')).toBeNull();
    await at(video, 2975);
    expect(screen.getByText('slotscherm')).toBeInTheDocument();
    expect(document.querySelector('.player')).toHaveClass('player--end');
  });

  it('gaat met de tegel terug naar volledig beeld en komt aan het eind terug', async () => {
    const { video } = await mount({ end: end() });
    await at(video, 2975);
    await fireEvent.click(screen.getByRole('button', { name: 'Aftiteling op volledig beeld' }));
    expect(screen.queryByText('slotscherm')).toBeNull();
    await fireEvent.ended(video);
    expect(screen.getByText('slotscherm')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Aftiteling op volledig beeld' })).toBeNull();
  });

  it('wijkt voor de kaart als er een volgende aflevering is', async () => {
    const { video } = await mount({ end: end(), next: following, onnext: vi.fn() });
    await at(video, 2975);
    expect(screen.queryByText('slotscherm')).toBeNull();
    expect(screen.getByText('4. Dal van wee')).toBeInTheDocument();
  });

  it('meldt het einde nog steeds aan een afspeellijst', async () => {
    const onfinished = vi.fn();
    const { video } = await mount({ onfinished });
    await fireEvent.ended(video);
    expect(onfinished).toHaveBeenCalledTimes(1);
  });
});
