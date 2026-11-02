import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { retryAfterMs, SUBTITLE_RETRY_LIMIT_MS, SubtitleNotReadyError, subtitleTextWhenReady } from './subtitleRetry';

const notReady = (seconds: number) => new SubtitleNotReadyError(seconds * 1000);

describe('retryAfterMs', () => {
  it.each([
    ['5', 5000], ['7', 7000], [' 5 ', 5000], [null, 5000], ['', 5000],
    ['Wed, 21 Oct 2026 07:28:00 GMT', 5000], ['0', 1000], ['3600', 60000]
  ])('%s', (header, ms) => expect(retryAfterMs(header)).toBe(ms));
});

describe('subtitleTextWhenReady', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('repeats after Retry-After and stops at the file', async () => {
    const load = vi.fn<(signal: AbortSignal) => Promise<string>>()
      .mockRejectedValueOnce(notReady(5)).mockRejectedValueOnce(notReady(5)).mockResolvedValue('WEBVTT');
    const text = subtitleTextWhenReady(load, new AbortController().signal);
    await vi.advanceTimersByTimeAsync(4999);
    expect(load).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(load).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(5000);
    await expect(text).resolves.toBe('WEBVTT');
    expect(load).toHaveBeenCalledTimes(3);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('does not repeat any other outcome', async () => {
    const load = vi.fn(async () => { throw new Error('subtitle 502'); });
    await expect(subtitleTextWhenReady(load, new AbortController().signal)).rejects.toThrow('subtitle 502');
    expect(load).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('gives up after eleven minutes', async () => {
    const load = vi.fn(async () => { throw notReady(5); });
    const text = subtitleTextWhenReady(load, new AbortController().signal);
    const outcome = text.catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(SUBTITLE_RETRY_LIMIT_MS - 1);
    const calls = load.mock.calls.length;
    expect(calls).toBeGreaterThan(100);
    await vi.advanceTimersByTimeAsync(1);
    expect(await outcome).toMatchObject({ name: 'AbortError' });
    await vi.advanceTimersByTimeAsync(60_000);
    expect(load.mock.calls.length).toBe(calls);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('stops at once when the viewer chooses something else', async () => {
    const outer = new AbortController();
    const load = vi.fn(async () => { throw notReady(5); });
    const outcome = subtitleTextWhenReady(load, outer.signal).catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(1000);
    outer.abort();
    expect(await outcome).toMatchObject({ name: 'AbortError' });
    await vi.advanceTimersByTimeAsync(60_000);
    expect(load).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);
  });
});
