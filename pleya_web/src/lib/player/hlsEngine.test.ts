/**
 * hls.js-herstel en de hartslag, tegen een nep-hls.js en handmatige timers.
 */
import { describe, expect, it, vi } from 'vitest';

import { attachHls, hlsConfig, MAX_MEDIA_RECOVERIES, MAX_NETWORK_RETRIES } from './hlsEngine';
import { ACCESS_TOKEN, apiError, fakeApi, fakeHls, manualTimers } from './playerFake';
import { HEARTBEAT_EVERY_MS, TranscodeHold } from './transcodeHold';

function attach() {
  const { Hls, instances } = fakeHls();
  const onFatal = vi.fn();
  const scheduled: (() => void)[] = [];
  const handle = attachHls({
    Hls,
    media: {} as HTMLMediaElement,
    url: 'http://pleya.test/pleya/v1/playback/sessions/s/index.m3u8',
    bearer: async () => ACCESS_TOKEN,
    onFatal,
    schedule: (fn) => scheduled.push(fn)
  });
  const hls = instances[0]!;
  const net = (code = 0) =>
    hls.emit('hlsError', { type: 'networkError', details: 'fragLoadError', fatal: true, response: { code } });
  const med = () => hls.emit('hlsError', { type: 'mediaError', details: 'bufferStalledError', fatal: true });
  return { hls, onFatal, scheduled, handle, net, med };
}

describe('hls.js-configuratie', () => {
  it('zet de bearer in een header, opent zelf en draait zonder worker vanaf het begin', async () => {
    const config = hlsConfig(async () => ACCESS_TOKEN);
    expect(config['enableWorker']).toBe(false);
    expect(config['startPosition']).toBe(0);
    const xhr = { open: vi.fn(), setRequestHeader: vi.fn() };
    const setup = config['xhrSetup'] as (x: unknown, u: string) => Promise<void>;
    await setup(xhr, 'http://pleya.test/seg_00001.m4s');
    expect(xhr.open).toHaveBeenCalledWith('GET', 'http://pleya.test/seg_00001.m4s', true);
    expect(xhr.setRequestHeader).toHaveBeenCalledWith('Authorization', `Bearer ${ACCESS_TOKEN}`);
  });

  it('laadt de afspeellijst zonder query', () => {
    const { hls } = attach();
    expect(hls.source).toBe('http://pleya.test/pleya/v1/playback/sessions/s/index.m3u8');
    expect(hls.media).not.toBeNull();
  });
});

describe('herstel', () => {
  it('negeert een niet-fatale fout', () => {
    const { hls, onFatal } = attach();
    hls.emit('hlsError', { type: 'networkError', details: 'x', fatal: false });
    expect(onFatal).not.toHaveBeenCalled();
    expect(hls.startLoads).toBe(0);
  });

  it('probeert een fatale netwerkfout opnieuw met startLoad en geeft daarna op', () => {
    const { hls, onFatal, scheduled, net } = attach();
    for (let i = 0; i < MAX_NETWORK_RETRIES; i++) {
      net(0);
      scheduled.shift()?.();
    }
    expect(hls.startLoads).toBe(MAX_NETWORK_RETRIES);
    expect(onFatal).not.toHaveBeenCalled();
    net(0);
    expect(onFatal).toHaveBeenCalledWith('client.media_network');
    expect(hls.destroyed).toBe(true);
  });

  it('een geladen fragment zet de teller terug', () => {
    const { hls, onFatal, scheduled, net } = attach();
    for (let i = 0; i < MAX_NETWORK_RETRIES + 2; i++) {
      net(0);
      scheduled.shift()?.();
      hls.emit('hlsFragLoaded', { type: '', details: '', fatal: false });
    }
    expect(onFatal).not.toHaveBeenCalled();
  });

  it('een 404 op een sessiebestand is meteen klaar: de sessie is weg', () => {
    const { hls, onFatal, net } = attach();
    net(404);
    expect(onFatal).toHaveBeenCalledWith('client.session_ended');
    expect(hls.startLoads).toBe(0);
  });

  it('herstelt een mediafout eerst, dan met swapAudioCodec, en geeft dan op', () => {
    const { hls, onFatal, med } = attach();
    med();
    expect(hls.recoveries).toBe(1);
    med();
    expect(hls.swaps).toBe(1);
    expect(hls.recoveries).toBe(MAX_MEDIA_RECOVERIES);
    med();
    expect(onFatal).toHaveBeenCalledWith('client.media_decode');
    expect(hls.destroyed).toBe(true);
  });

  it('een fatale fout van een ander type eindigt meteen in de foutstaat', () => {
    const { onFatal, hls } = attach();
    hls.emit('hlsError', { type: 'muxError', details: 'x', fatal: true });
    expect(onFatal).toHaveBeenCalledWith('client.media_decode');
  });

  it('na destroy doet een late fout niets meer', () => {
    const { onFatal, handle, net } = attach();
    handle.destroy();
    net(500);
    expect(onFatal).not.toHaveBeenCalled();
  });
});

describe('TranscodeHold', () => {
  it('tikt elke vijftien seconden en stopt één keer', () => {
    expect(HEARTBEAT_EVERY_MS).toBe(15_000);
    const api = fakeApi();
    const timers = manualTimers();
    const hold = new TranscodeHold(api, vi.fn(), timers);
    hold.hold('s1');
    timers.tick();
    expect(api.heartbeats).toEqual(['s1']);
    hold.release(false);
    hold.release(false);
    expect(api.stops).toEqual([{ id: 's1', keepalive: false }]);
    expect(timers.active).toBe(0);
  });

  it('een nieuwe sessie stopt de vorige', () => {
    const api = fakeApi();
    const hold = new TranscodeHold(api, vi.fn(), manualTimers());
    hold.hold('a');
    hold.hold('b');
    expect(api.stops).toEqual([{ id: 'a', keepalive: false }]);
    expect(hold.sessionId).toBe('b');
  });

  it('een netwerkfout op de hartslag is geen verlies', async () => {
    const onLost = vi.fn();
    const api = fakeApi({
      heartbeat: async () => {
        throw apiError('client.transport', 0);
      }
    });
    const timers = manualTimers();
    const hold = new TranscodeHold(api, onLost, timers);
    hold.hold('s1');
    timers.tick();
    await vi.waitFor(() => expect(api.heartbeats).toEqual(['s1']));
    expect(onLost).not.toHaveBeenCalled();
    expect(timers.active).toBe(1);
  });
});
