/**
 * De probe meldt wat de browser zegt, en niets meer: een nep-omgeving per
 * browserprofiel en de vorm die naar `POST /playback/plan` gaat.
 */
import { describe, expect, it } from 'vitest';

import { hlsSupport, probeCapabilities, type ProbeEnv } from './capabilities';
import { chooseDelivery, DeliveryError, directUrlWithSession, urlWithStreamToken } from './delivery';
import { plan, transcodePlan } from './playerFake';

function env(
  answers: Record<string, string>,
  mse: ((t: string) => boolean) | null = () => true,
  hdr = false
): ProbeEnv {
  return {
    canPlayType: (t) => answers[t] ?? '',
    mseIsTypeSupported: mse,
    matchMedia: (q) => ({ matches: hdr && q.includes('high') })
  };
}

const chromeLike = {
  'video/mp4; codecs="avc1.640028"': 'probably',
  'video/webm; codecs="vp9"': 'probably',
  'audio/mp4; codecs="mp4a.40.2"': 'probably',
  'audio/webm; codecs="opus"': 'probably',
  'video/mp4': 'maybe',
  'video/webm': 'maybe'
};

describe('probeCapabilities', () => {
  it('meldt codecs en containers die de browser bevestigt, als detected', () => {
    const caps = probeCapabilities(env(chromeLike));
    expect(caps.decoder?.video_codecs).toEqual({ value: ['h264', 'vp9'], confidence: 'detected' });
    expect(caps.decoder?.audio_codecs?.value).toEqual(['aac', 'opus']);
    expect(caps.decoder?.containers?.value).toEqual(['mp4', 'webm']);
    expect(caps.decoder?.max_bit_depth).toEqual({ value: 8, confidence: 'detected' });
  });

  it('telt "maybe" niet mee als MediaSource het tegenspreekt (negatieve controle)', () => {
    const answers = { ...chromeLike, 'video/mp4; codecs="hvc1.1.6.L120.90"': 'maybe' };
    expect(probeCapabilities(env(answers, () => false)).decoder?.video_codecs?.value).not.toContain('hevc');
    expect(probeCapabilities(env(answers, () => true)).decoder?.video_codecs?.value).toContain('hevc');
  });

  it('zegt tien bits zodra HEVC Main 10, AV1 of VP9 profiel 2 kan', () => {
    const caps = probeCapabilities(env({ ...chromeLike, 'video/mp4; codecs="hvc1.2.4.L120.90"': 'probably' }));
    expect(caps.decoder?.max_bit_depth?.value).toBe(10);
  });

  it('meldt HDR alleen uit een schermvraag, en Dolby Vision nooit', () => {
    expect(probeCapabilities(env(chromeLike, () => true, true)).display?.hdr_transfers?.value).toEqual([
      'hdr10',
      'hlg'
    ]);
    expect(probeCapabilities(env(chromeLike)).display?.hdr_transfers?.value).toEqual([]);
    const noMedia = { ...env(chromeLike), matchMedia: null };
    expect(probeCapabilities(noMedia).display).toBeUndefined();
  });

  it('laat audio en verbinding weg: die kan een pagina niet weten', () => {
    const caps = probeCapabilities(env(chromeLike));
    expect(caps.audio).toBeUndefined();
    expect(caps.connection).toBeUndefined();
  });

  it('herkent hls.js via MediaSource en native HLS via canPlayType', () => {
    expect(hlsSupport(env(chromeLike))).toEqual({ hlsjs: true, native: false });
    expect(
      hlsSupport(env({ 'application/vnd.apple.mpegurl': 'maybe' }, null))
    ).toEqual({ hlsjs: false, native: true });
  });
});

describe('chooseDelivery', () => {
  const hls = { hlsjs: true, native: false };

  it('direct play gebruikt het pad uit het plan', () => {
    expect(chooseDelivery(plan(), 'x', hls)).toEqual({
      kind: 'direct',
      versionId: 'v-1',
      path: '/pleya/v1/stream/v-1',
      mode: 'direct_play'
    });
  });

  it('zonder plan direct play van de gekozen versie', () => {
    expect(chooseDelivery(null, 'v 9', hls).path).toBe('/pleya/v1/stream/v%209');
  });

  it('remux, direct stream en transcode worden HLS met de sessie-id', () => {
    for (const mode of ['remux', 'direct_stream', 'transcode'] as const) {
      const d = chooseDelivery(transcodePlan({ delivery_mode: mode }), 'x', hls);
      expect(d).toMatchObject({ kind: 'hls', sessionId: 'sess-1', mode, engine: 'hlsjs' });
    }
    expect(chooseDelivery(transcodePlan(), 'x', { hlsjs: false, native: true })).toMatchObject({
      engine: 'native'
    });
  });

  it('weigert HLS in een browser die het niet kan, en een onbekende wijze', () => {
    expect(() => chooseDelivery(transcodePlan(), 'x', { hlsjs: false, native: false })).toThrow(DeliveryError);
    expect(() => chooseDelivery(transcodePlan({ session_id: null }), 'x', hls)).toThrow('client.plan_unknown');
  });

  it('zet in de URL alleen de sessie-id of het streamtoken, gecodeerd', () => {
    expect(directUrlWithSession({ path: '/pleya/v1/stream/v-1' }, 'a b')).toBe('/pleya/v1/stream/v-1?ss=a%20b');
    expect(urlWithStreamToken('/p?x=1', 't')).toBe('/p?x=1&stream_token=t');
  });
});
