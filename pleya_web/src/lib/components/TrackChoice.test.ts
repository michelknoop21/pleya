import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, onTestFinished, vi } from 'vitest';
import type { Version } from '../api/types';

const h = vi.hoisted(() => ({ get: vi.fn(), set: vi.fn(), caps: { track_preferences: true, playback_audio_selection: true } as Record<string, boolean> }));
vi.mock('../stores/session.svelte.js', () => ({ session: { client: {}, get capabilities() { return h.caps; } } }));
vi.mock('../api/personal', () => ({ personalApi: () => ({ trackPreference: h.get, setTrackPreference: h.set }) }));
import TrackChoice from './TrackChoice.svelte';

const none = { source_item_id: null, audio_language: null, subtitle_language: null, subtitle_mode: null, updated_at: null };
const version: Version = {
  id: 'v1', container: 'mkv', duration_ms: 60000, file_count: 1,
  audio_streams: [
    { id: 'a-en', index: 1, codec: 'truehd', channels: 8, language: 'eng', is_default: true },
    { id: 'a-nl', index: 2, codec: 'aac', channels: 2, language: 'nld', is_default: false },
    { id: 'a-x', index: 3, codec: 'ac3', channels: 6, language: null, is_default: false }
  ],
  subtitle_streams: [
    { id: 's-nl', index: 4, format: 'srt', language: 'nld', is_default: false, is_forced: false, is_hearing_impaired: false, is_external: true },
    { id: 's-en', index: 5, format: 'pgs', language: 'eng', is_default: false, is_forced: false, is_hearing_impaired: false, is_external: false }
  ]
};
const props = (onpick = vi.fn()) => ({
  item: { id: 'movie' }, version, versionOptions: [{ value: 'v1', label: 'Version 1' }], onversion: vi.fn(), onpick
});

beforeEach(() => {
  h.caps = { track_preferences: true, playback_audio_selection: true };
  h.get.mockReset().mockResolvedValue(none);
  h.set.mockReset().mockImplementation(async (_id: string, body: object) => ({ ...none, ...body }));
});

describe('spoorkeuze op het filmdetail', () => {
  it('toont versie, audio en ondertitels als drie keuzelijsten met de sporen van de versie', async () => {
    render(TrackChoice, { props: props() });
    expect(screen.getByRole('combobox', { name: 'Version' })).toHaveValue('v1');
    expect(screen.getByRole('combobox', { name: 'Audio' })).toHaveValue('a-en');
    expect(screen.getByRole('option', { name: /Dutch · aac · 2ch/ })).toBeInTheDocument();
    expect(screen.getByRole('combobox', { name: 'Subtitles' })).toHaveValue('');
    expect(screen.getByRole('option', { name: 'Off' })).toBeInTheDocument();
  });

  it('bewaart de keuze met track_preferences en geeft het spoor mee aan de speler', async () => {
    const onpick = vi.fn();
    render(TrackChoice, { props: props(onpick) });
    await fireEvent.change(screen.getByRole('combobox', { name: 'Audio' }), { target: { value: 'a-nl' } });
    await waitFor(() => expect(h.set).toHaveBeenCalledWith('movie', { audio_language: 'nld' }));
    await fireEvent.change(screen.getByRole('combobox', { name: 'Subtitles' }), { target: { value: 's-nl' } });
    await waitFor(() => expect(h.set).toHaveBeenLastCalledWith('movie', { subtitle_language: 'nld', subtitle_mode: 'on' }));
    expect(onpick).toHaveBeenLastCalledWith({ audio: 'a-nl', subtitle: 's-nl' });
    expect(screen.getByText(/remembered for this title/)).toBeInTheDocument();
    await fireEvent.change(screen.getByRole('combobox', { name: 'Subtitles' }), { target: { value: '' } });
    await waitFor(() => expect(h.set).toHaveBeenLastCalledWith('movie', { subtitle_mode: 'off' }));
  });

  it('bewaart niets zonder de capability; de keuze geldt dan alleen voor de eerstvolgende afspeelactie', async () => {
    h.caps = { track_preferences: false, playback_audio_selection: true };
    const onpick = vi.fn();
    render(TrackChoice, { props: props(onpick) });
    await fireEvent.change(screen.getByRole('combobox', { name: 'Audio' }), { target: { value: 'a-nl' } });
    await fireEvent.change(screen.getByRole('combobox', { name: 'Subtitles' }), { target: { value: 's-nl' } });
    expect(onpick).toHaveBeenLastCalledWith({ audio: 'a-nl', subtitle: 's-nl' });
    expect(h.get).not.toHaveBeenCalled();
    expect(h.set).not.toHaveBeenCalled();
    expect(screen.getByText(/next playback only/)).toBeInTheDocument();
  });

  it('zet de bewaarde voorkeur als beginstand en stuurt het standaardspoor niet mee', async () => {
    h.get.mockResolvedValue({ ...none, audio_language: 'NLD', subtitle_language: 'eng', subtitle_mode: 'on' });
    const onpick = vi.fn();
    render(TrackChoice, { props: props(onpick) });
    expect(onpick).toHaveBeenLastCalledWith({});
    await waitFor(() => expect(screen.getByRole('combobox', { name: 'Audio' })).toHaveValue('a-nl'));
    expect(screen.getByRole('combobox', { name: 'Subtitles' })).toHaveValue('s-en');
    expect(onpick).toHaveBeenLastCalledWith({ audio: 'a-nl', subtitle: 's-en' });
    // PGS kan de browserspeler niet tonen; dat staat erbij in plaats van een stille keuze.
    expect(screen.getByText(/does not show in this browser/)).toBeInTheDocument();
  });

  it('bewaart een spoor zonder bruikbare taalcode niet en meldt een mislukte opslag', async () => {
    render(TrackChoice, { props: props() });
    await fireEvent.change(screen.getByRole('combobox', { name: 'Audio' }), { target: { value: 'a-x' } });
    expect(h.set).not.toHaveBeenCalled();
    h.set.mockRejectedValueOnce(new Error('offline'));
    await fireEvent.change(screen.getByRole('combobox', { name: 'Audio' }), { target: { value: 'a-nl' } });
    expect(await screen.findByRole('alert')).toBeInTheDocument();
  });
});

it('laat de audiokeuze weg als server noch browser hem kan uitvoeren, en stuurt dan geen spoor mee', async () => {
  h.caps = { track_preferences: true };
  // jsdom kent `audioTracks`; Chrome niet. Zonder de eigenschap is er geen browserwissel.
  const native = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'audioTracks')!;
  delete (HTMLMediaElement.prototype as { audioTracks?: unknown }).audioTracks;
  onTestFinished(() => void Object.defineProperty(HTMLMediaElement.prototype, 'audioTracks', native));
  h.get.mockResolvedValue({ ...none, audio_language: 'nld' });
  const onpick = vi.fn();
  render(TrackChoice, { props: props(onpick) });
  await waitFor(() => expect(h.get).toHaveBeenCalled());
  expect(screen.queryByRole('combobox', { name: 'Audio' })).toBeNull();
  expect(screen.getByRole('combobox', { name: 'Subtitles' })).toBeInTheDocument();
  expect(onpick).toHaveBeenLastCalledWith({});
});
