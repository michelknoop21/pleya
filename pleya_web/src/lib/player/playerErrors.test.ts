/**
 * Elke foutcode krijgt een eigen zin met een uitweg, in beide talen; plus de
 * hulpjes voor toetsenbord, tijd, sporen en de route.
 */
import { afterEach, describe, expect, it } from 'vitest';

import { TransportError } from '../api/errors';
import type { Version } from '../api/types';
import { setLocale } from '../i18n';
import { DeliveryError } from './delivery';
import { formatPlayTime, keyAction, nextSpeed } from './keyboard';
import { deliveryLabel, resolutionClass } from './labels';
import { apiError } from './playerFake';
import { mediaErrorCode, playerProblem } from './playerErrors';
import { isPlayerPath, playerHref } from './route';
import { audioOptions, subtitleOptions } from './tracks';

afterEach(() => setLocale('en'));

const CODES: [string, number, string][] = [
  ['auth.token_expired', 401, 'login'],
  ['auth.permission_not_allowed', 403, 'back'],
  ['library.not_found', 404, 'back'],
  ['library.version_multifile', 409, 'back'],
  ['session.stream_session_limit', 429, 'retry'],
  ['playback.version_unavailable', 409, 'retry'],
  ['playback.transcode_busy', 503, 'retry'],
  ['playback.transcode_failed', 502, 'retry'],
  ['playback.file_corrupt', 502, 'back'],
  ['server.database_unavailable', 503, 'retry']
];

describe('playerProblem', () => {
  it('geeft elke servercode een eigen Nederlandse zin en uitweg', () => {
    setLocale('nl');
    const seen = new Set<string>();
    for (const [code, status, wayOut] of CODES) {
      const p = playerProblem(apiError(code, status));
      expect(p.wayOut, code).toBe(wayOut);
      expect(p.message, code).not.toMatch(/player\.err/);
      seen.add(p.message);
    }
    expect(seen.size).toBe(CODES.length);
  });

  it('onderscheidt een 415 zonder omzetter van een 415 met', () => {
    const without = playerProblem(
      apiError('playback.not_playable', 415, {
        reasons: [{ code: 'video.codec_unsupported' }, { code: 'server.transcode_unavailable' }]
      })
    );
    const withT = playerProblem(apiError('playback.not_playable', 415, { reasons: [] }));
    expect(without.message).toMatch(/no converter/);
    expect(withT.message).not.toMatch(/no converter/);
  });

  it('netwerk, clientcodes, een interne fout met aanvraag-id en een onbekende code', () => {
    expect(playerProblem(new TransportError(new Error('x'))).code).toBe('client.transport');
    expect(playerProblem(new DeliveryError('client.hls_unsupported')).wayOut).toBe('back');
    expect(playerProblem(apiError('server.internal', 500, { request_id: 'r-9' })).message).toContain('r-9');
    expect(playerProblem(apiError('playback.brand_new', 409)).message).toContain('playback.brand_new');
    expect(playerProblem(new Error('x')).code).toBe('client.unknown');
  });

  it('negeert MEDIA_ERR_ABORTED en vertaalt netwerk en decoderen', () => {
    expect(mediaErrorCode(null)).toBeNull();
    expect(mediaErrorCode({ code: 1 })).toBeNull();
    expect(mediaErrorCode({ code: 2 })).toBe('client.media_network');
    expect(mediaErrorCode({ code: 4 })).toBe('client.media_decode');
  });
});

describe('toetsenbord', () => {
  it('spatie, pijlen, f en m', () => {
    expect(keyAction({ key: ' ' })).toEqual({ kind: 'toggle' });
    expect(keyAction({ key: 'ArrowLeft' })).toEqual({ kind: 'seekBy', seconds: -10 });
    expect(keyAction({ key: 'ArrowRight' })).toEqual({ kind: 'seekBy', seconds: 10 });
    expect(keyAction({ key: 'ArrowUp' })).toEqual({ kind: 'volumeBy', delta: 0.1 });
    expect(keyAction({ key: 'f' })).toEqual({ kind: 'fullscreen' });
    expect(keyAction({ key: 'm' })).toEqual({ kind: 'mute' });
  });

  it('laat een knop, een schuifbalk en een sneltoets met Cmd met rust', () => {
    expect(keyAction({ key: ' ', targetTag: 'BUTTON' })).toBeNull();
    expect(keyAction({ key: 'ArrowLeft', targetTag: 'INPUT', targetType: 'range' })).toBeNull();
    expect(keyAction({ key: 'f', metaKey: true })).toBeNull();
    expect(keyAction({ key: 'f', targetTag: 'INPUT', targetType: 'text' })).toBeNull();
  });

  it('tijd en snelheid', () => {
    expect(formatPlayTime(4001)).toBe('1:06:41');
    expect(formatPlayTime(65)).toBe('1:05');
    expect(formatPlayTime(Number.NaN)).toBe('0:00');
    expect(nextSpeed(1)).toBe(1.25);
    expect(nextSpeed(0.75)).toBe(1);
  });
});

describe('sporen, chip en route', () => {
  const version: Version = {
    id: 'v',
    container: 'mkv',
    duration_ms: 1000,
    file_count: 1,
    video_streams: [{ id: 'vs', index: 0, codec: 'hevc', height: 2160 }],
    audio_streams: [
      { id: 'a1', index: 1, codec: 'eac3', channels: 6, language: 'eng', is_default: false },
      { id: 'a2', index: 2, codec: 'aac', channels: 2, language: 'dut', is_default: true }
    ],
    subtitle_streams: [
      { id: 's1', format: 'vtt' as const, is_external: true, is_forced: false, is_hearing_impaired: false, is_default: false, language: 'dut' },
      { id: 's2', format: 'srt' as const, is_external: true, is_forced: false, is_hearing_impaired: false, is_default: false },
      { id: 's3', format: 'vtt' as const, index: 4, is_external: false, is_forced: false, is_hearing_impaired: false, is_default: false }
    ]
  };

  it('biedt alleen externe WebVTT aan en telt de rest', () => {
    const subs = subtitleOptions(version);
    expect(subs.usable.map((s) => s.id)).toEqual(['s1']);
    expect(subs.skipped).toBe(2);
    expect(audioOptions(version).map((a) => a.isDefault)).toEqual([false, true]);
  });

  it('de chip noemt wijze, codec en resolutie, behalve bij omzetten', () => {
    expect(deliveryLabel('direct_play', version)).toBe('Direct play · HEVC 4K');
    expect(deliveryLabel('transcode', version)).toBe('Transcode');
    expect(resolutionClass(1080)).toBe('1080p');
  });

  it('herkent het spelerpad en bouwt de hervat-URL in seconden', () => {
    expect(isPlayerPath('/items/abc/play')).toBe(true);
    expect(isPlayerPath('/items/abc')).toBe(false);
    expect(playerHref('abc', 4_001_500)).toBe('/items/abc/play?t=4001');
    expect(playerHref('abc')).toBe('/items/abc/play');
  });
});

describe('ondertiteltekst', () => {
  it('haalt WebVTT-opmaak weg en zet meerdere cues onder elkaar', async () => {
    const { cueText } = await import('./tracks');
    expect(cueText([{ text: '<i>Hallo</i>' }, { text: '<v Paul>daar' }])).toBe('Hallo\ndaar');
    expect(cueText(null)).toBe('');
  });
});
