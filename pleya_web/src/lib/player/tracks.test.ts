import { describe, expect, it } from 'vitest';
import { subtitleWebVtt, subtitleOptions } from './tracks';
import type { Version } from '../api/types';

describe('browser text subtitle delivery', () => {
  it('converts SRT cue numbers, CRLF and Unicode without changing times or lines', () => {
    const srt = '\uFEFF1\r\n00:00:01,250 --> 00:00:03,500\r\nHé <i>wereld</i>\r\nTweede regel\r\n\r\n2\r\n01:02:03,004 --> 01:02:04,005\r\nLater\r\n';
    expect(subtitleWebVtt(srt, 'srt')).toBe('WEBVTT\n\n1\n00:00:01.250 --> 00:00:03.500\nHé <i>wereld</i>\nTweede regel\n\n2\n01:02:03.004 --> 01:02:04.005\nLater\n');
  });
  it('accepts SRT without cue numbers and preserves valid WebVTT', () => {
    expect(subtitleWebVtt('00:00:00,000 --> 00:00:01,000\nHello', 'srt')).toContain('00:00:00.000 --> 00:00:01.000');
    expect(subtitleWebVtt('WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello\n', 'vtt')).toBe('WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHello\n');
  });
  it.each(['<html>not subtitles</html>', '1\n00:60:00,000 --> 00:61:00,000\nWrong', '1\n00:00:03,000 --> 00:00:01,000\nBackwards'])('rejects malformed SRT instead of creating an empty track', body => {
    expect(() => subtitleWebVtt(body, 'srt')).toThrow('Invalid SRT');
  });
  it('skips a broken cue and keeps the rest of the track', () => {
    const srt = '1\n00:00:01,000 --> 00:00:02,000\nEerste\n\n2\nkapotte regel\nTekst\n\n3\n00:00:09,000 --> 00:00:03,000\nAchteruit\n\n4\n00:00:05,000 --> 00:00:06,000\n\n5\n00:00:07,000 --> 00:00:08,000\nLaatste\n';
    expect(subtitleWebVtt(srt, 'srt')).toBe('WEBVTT\n\n1\n00:00:01.000 --> 00:00:02.000\nEerste\n\n5\n00:00:07.000 --> 00:00:08.000\nLaatste\n');
  });
  it('rejects oversized or unknown formats without claiming conversion', () => {
    expect(() => subtitleWebVtt('1\n00:00:00,000 --> 00:00:01,000\n' + 'x'.repeat(4 * 1024 * 1024), 'srt')).toThrow('Subtitle too large');
    expect(() => subtitleWebVtt('[Script Info]', 'ass')).toThrow('Unsupported subtitle format');
    expect(() => subtitleWebVtt('<html>not vtt</html>', 'vtt')).toThrow('Invalid WebVTT');
  });
  it('offers embedded text only when the server advertises delivery', () => {
    const base = { is_forced: false, is_hearing_impaired: false, is_default: false };
    const version: Version = { id: 'v', container: 'mkv', duration_ms: 1000, file_count: 1, subtitle_streams: [
      { ...base, id: 'external', format: 'srt', is_external: true },
      { ...base, id: 'embedded', format: 'srt', is_external: false, index: 3 },
      { ...base, id: 'bitmap', format: 'pgs', is_external: false, index: 4 }
    ] };
    expect(subtitleOptions(version).usable.map(s=>s.id)).toEqual(['external']);
    expect(subtitleOptions(version, true).usable.map(s=>s.id)).toEqual(['external','embedded']);
    expect(subtitleOptions(version, true).skipped).toBe(1);
  });
});
