/**
 * De server onthoudt een mislukte extractie 15 s. Opnieuw binnen dat venster zou
 * dezelfde `502` terugkrijgen zonder dat er iets geprobeerd is.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Version } from '../api/types';
import { PlayerSubtitles } from './playerSubtitles.svelte';

const version = {
  subtitle_streams: [
    { id: 'ingebed', is_external: false, format: 'srt' },
    { id: 'los', is_external: true, format: 'srt' }
  ]
} as unknown as Version;

beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal('URL', Object.assign(URL, { createObjectURL: () => 'blob:x', revokeObjectURL: () => {} }));
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

const text = '1\n00:00:00,000 --> 00:00:05,000\nHallo';

describe('Opnieuw na een mislukte extractie', () => {
  it('wacht tot de server de fout vergeten is en toont intussen de voorbereiding', async () => {
    const subtitleText = vi.fn().mockRejectedValueOnce(new Error('502')).mockResolvedValue(text);
    const subs = new PlayerSubtitles({ subtitleText }, () => version);
    await subs.choose('ingebed');
    expect(subs.failedId).toBe('ingebed');

    subs.retry();
    expect(subs.preparing).toBe(true);
    expect(subs.error).toBeNull();
    await vi.advanceTimersByTimeAsync(14_000);
    expect(subtitleText).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1_000);
    expect(subtitleText).toHaveBeenCalledTimes(2);
    await vi.waitFor(() => expect(subs.activeId).toBe('ingebed'));
  });

  it('wacht niet langer dan nodig als de kijker later op Opnieuw drukt', async () => {
    const subtitleText = vi.fn().mockRejectedValueOnce(new Error('502')).mockResolvedValue(text);
    const subs = new PlayerSubtitles({ subtitleText }, () => version);
    await subs.choose('ingebed');
    await vi.advanceTimersByTimeAsync(20_000);
    subs.retry();
    await vi.advanceTimersByTimeAsync(0);
    expect(subtitleText).toHaveBeenCalledTimes(2);
  });

  it('een los spoor heeft dat venster niet', async () => {
    const subtitleText = vi.fn().mockRejectedValueOnce(new Error('offline')).mockResolvedValue(text);
    const subs = new PlayerSubtitles({ subtitleText }, () => version);
    await subs.choose('los');
    subs.retry();
    await vi.advanceTimersByTimeAsync(0);
    expect(subtitleText).toHaveBeenCalledTimes(2);
  });

  it('een andere keuze breekt het wachten af', async () => {
    const subtitleText = vi.fn().mockRejectedValueOnce(new Error('502')).mockResolvedValue(text);
    const subs = new PlayerSubtitles({ subtitleText }, () => version);
    await subs.choose('ingebed');
    subs.retry();
    await subs.choose(null);
    await vi.advanceTimersByTimeAsync(20_000);
    expect(subtitleText).toHaveBeenCalledTimes(1);
    expect(subs.preparing).toBe(false);
  });
});
