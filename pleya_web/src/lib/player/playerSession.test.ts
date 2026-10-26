/**
 * Het afspeelpad van begin tot opruimen, tegen nepdubbels: plan naar weg,
 * credential naar URL, hartslag, foutstaat en opruimen. Elke kritieke regel
 * heeft een negatieve controle ernaast.
 */
import { describe, expect, it, vi } from 'vitest';

import { setLocale } from '../i18n';
import {
  ACCESS_TOKEN,
  STREAM_TOKEN,
  SERVER_CAPS,
  apiError,
  deps,
  fakeApi,
  fakeHls,
  fakeMedia,
  manualTimers,
  plan,
  transcodePlan
} from './playerFake';
import { PlayerSession } from './playerSession.svelte';
import { StreamSessionCache } from './streamSessionCache';

setLocale('en');

const target = { itemId: 'item-1', versionId: 'v-1' };
const asMedia = (m: unknown) => m as HTMLMediaElement;

describe('direct play', () => {
  it('zet alleen de niet-geheime streamsessie-id in de URL', async () => {
    const api = fakeApi();
    const media = fakeMedia();
    const s = new PlayerSession(deps(api));
    await s.start(asMedia(media), target);

    expect(s.phase).toBe('ready');
    expect(media.src).toBe('/pleya/v1/stream/v-1?ss=ss-1');
    expect(api.calls).toEqual(['plan item-1', 'stream-session v-1']);
    expect(media.play).toHaveBeenCalled();
  });

  it('valt zonder streamsessies terug op het streamtoken, zoals het contract toestaat', async () => {
    const api = fakeApi();
    const media = fakeMedia();
    const s = new PlayerSession(deps(api, { server: { ...SERVER_CAPS, stream_sessions: false } }));
    await s.start(asMedia(media), target);
    expect(media.src).toBe(`/pleya/v1/stream/v-1?stream_token=${STREAM_TOKEN}`);
  });

  it('speelt zonder planner de gekozen versie direct af', async () => {
    const api = fakeApi();
    const media = fakeMedia();
    const s = new PlayerSession(deps(api, { server: { ...SERVER_CAPS, playback_plan: false } }));
    await s.start(asMedia(media), target);
    expect(api.calls).toEqual(['stream-session v-1']);
    expect(media.src).toBe('/pleya/v1/stream/v-1?ss=ss-1');
  });

  it('springt na het laden naar de hervatpositie', async () => {
    const media = fakeMedia();
    const s = new PlayerSession(deps(fakeApi()));
    await s.start(asMedia(media), { ...target, startAt: 120 });
    media.emit('loadedmetadata');
    expect(media.currentTime).toBe(120);
  });

  it('meldt een decodeerfout van de <video> als foutstaat', async () => {
    const media = fakeMedia();
    const s = new PlayerSession(deps(fakeApi()));
    await s.start(asMedia(media), target);
    s.mediaFailed({ code: 4 });
    expect(s.phase).toBe('error');
    expect(s.problem?.code).toBe('client.media_decode');
  });
});

describe('omzetsessie met hls.js', () => {
  it('houdt de sessie vast, geeft hls.js een URL zonder credential en zet de bearer in de header', async () => {
    const api = fakeApi({ plan: async () => transcodePlan() });
    const hls = fakeHls();
    const timers = manualTimers();
    const media = fakeMedia();
    const s = new PlayerSession(deps(api, { hls, timers }));
    await s.start(asMedia(media), target);

    expect(s.phase).toBe('ready');
    expect(s.heldSession).toBe('sess-1');
    expect(hls.instances[0]?.source).toBe('http://pleya.test/pleya/v1/playback/sessions/sess-1/index.m3u8');
    expect(api.calls).not.toContain('stream-session v-1');

    timers.tick();
    timers.tick();
    expect(api.heartbeats).toEqual(['sess-1', 'sess-1']);
  });

  it('ruimt bij sluiten alles op: hls.js weg, <video> los, sessie gestopt', async () => {
    const api = fakeApi({ plan: async () => transcodePlan() });
    const hls = fakeHls();
    const timers = manualTimers();
    const media = fakeMedia();
    const s = new PlayerSession(deps(api, { hls, timers }));
    await s.start(asMedia(media), target);

    s.dispose(true);
    expect(hls.instances[0]?.destroyed).toBe(true);
    expect(media.removeAttribute).toHaveBeenCalledWith('src');
    expect(media.load).toHaveBeenCalled();
    expect(api.stops).toEqual([{ id: 'sess-1', keepalive: true }]);
    expect(timers.active).toBe(0);
    timers.tick();
    expect(api.heartbeats).toEqual([]);
  });

  it('negatieve controle: zonder sluiten blijft de sessie staan en tikt de hartslag door', async () => {
    const api = fakeApi({ plan: async () => transcodePlan() });
    const timers = manualTimers();
    const s = new PlayerSession(deps(api, { timers }));
    await s.start(asMedia(fakeMedia()), target);
    timers.tick();
    expect(api.stops).toEqual([]);
    expect(s.heldSession).toBe('sess-1');
    expect(timers.active).toBe(1);
  });

  it('stopt een sessie die binnenkomt nadat de speler al gesloten is', async () => {
    let resolve: (p: ReturnType<typeof transcodePlan>) => void = () => undefined;
    const api = fakeApi({ plan: () => new Promise((r) => (resolve = r)) });
    const hls = fakeHls();
    const s = new PlayerSession(deps(api, { hls }));
    const pending = s.start(asMedia(fakeMedia()), target);
    s.dispose();
    resolve(transcodePlan());
    await pending;
    expect(api.stops).toEqual([{ id: 'sess-1', keepalive: false }]);
    expect(hls.instances).toHaveLength(0);
    expect(s.phase).toBe('idle');
  });

  it('gaat na een fatale hls-fout naar de foutstaat en stopt de sessie', async () => {
    const api = fakeApi({ plan: async () => transcodePlan() });
    const hls = fakeHls();
    const s = new PlayerSession(deps(api, { hls }));
    await s.start(asMedia(fakeMedia()), target);
    hls.instances[0]!.emit('hlsError', { type: 'otherError', details: 'x', fatal: true });
    expect(s.phase).toBe('error');
    expect(s.problem?.code).toBe('client.media_decode');
    expect(api.stops).toEqual([{ id: 'sess-1', keepalive: false }]);
  });

  it('gaat naar de foutstaat als de server de sessie vergeten is (404 op de hartslag)', async () => {
    const api = fakeApi({
      plan: async () => transcodePlan(),
      heartbeat: async () => {
        throw apiError('library.not_found', 404);
      }
    });
    const timers = manualTimers();
    const s = new PlayerSession(deps(api, { timers }));
    await s.start(asMedia(fakeMedia()), target);
    timers.tick();
    await vi.waitFor(() => expect(s.phase).toBe('error'));
    expect(s.problem?.code).toBe('client.session_ended');
    expect(timers.active).toBe(0);
    expect(api.stops).toEqual([]);
  });

  it('gebruikt native HLS alleen zonder MediaSource, met het streamtoken van de versie', async () => {
    const api = fakeApi({ plan: async () => transcodePlan() });
    const hls = fakeHls();
    const media = fakeMedia();
    const s = new PlayerSession(
      deps(api, { hls, probe: () => ({ caps: {}, hls: { hlsjs: false, native: true } }) })
    );
    await s.start(asMedia(media), target);
    expect(hls.instances).toHaveLength(0);
    expect(media.src).toBe(`/pleya/v1/playback/sessions/sess-1/index.m3u8?stream_token=${STREAM_TOKEN}`);
  });
});

describe('fouten uit het plan', () => {
  const cases: [string, number, string][] = [
    ['playback.transcode_busy', 503, 'retry'],
    ['playback.transcode_failed', 502, 'retry'],
    ['session.stream_session_limit', 429, 'retry'],
    ['server.database_unavailable', 503, 'retry'],
    ['library.not_found', 404, 'back'],
    ['auth.token_expired', 401, 'login']
  ];
  for (const [code, status, wayOut] of cases) {
    it(`${code} wordt een foutstaat met uitweg ${wayOut}`, async () => {
      const api = fakeApi({
        plan: async () => {
          throw apiError(code, status);
        }
      });
      const s = new PlayerSession(deps(api));
      await s.start(asMedia(fakeMedia()), target);
      expect(s.phase).toBe('error');
      expect(s.problem?.code).toBe(code);
      expect(s.problem?.wayOut).toBe(wayOut);
    });
  }

  it('een streamsessielimiet bij direct play is ook een foutstaat', async () => {
    const api = fakeApi({
      streamSession: async () => {
        throw apiError('session.stream_session_limit', 429);
      }
    });
    const s = new PlayerSession(deps(api));
    await s.start(asMedia(fakeMedia()), target);
    expect(s.problem?.code).toBe('session.stream_session_limit');
  });

  it('een onbekende leveringswijze stopt de al gestarte sessie', async () => {
    const api = fakeApi({
      plan: async () => transcodePlan({ delivery_mode: 'teleport' as never })
    });
    const s = new PlayerSession(deps(api));
    await s.start(asMedia(fakeMedia()), target);
    expect(s.problem?.code).toBe('client.plan_unknown');
    expect(api.stops).toEqual([{ id: 'sess-1', keepalive: false }]);
  });
});

describe('geen token in een URL', () => {
  it('het accesstoken komt in geen enkele bron-URL voor, ook niet na opnieuw starten', async () => {
    const api = fakeApi({ plan: async () => plan() });
    const hls = fakeHls();
    const media = fakeMedia();
    const s = new PlayerSession(deps(api, { hls }));
    await s.start(asMedia(media), target);
    (api.plan as unknown as { mockImplementation: (f: () => unknown) => void }).mockImplementation(
      async () => transcodePlan()
    );
    await s.start(asMedia(media), target);
    const urls = [...media.srcHistory, ...hls.instances.map((i) => i.source)];
    expect(urls.length).toBeGreaterThan(1);
    for (const url of urls) expect(url).not.toContain(ACCESS_TOKEN);
    for (const url of hls.instances.map((i) => i.source)) expect(url).not.toContain('?');
  });

  it('negatieve controle: de toets ziet het wel als het token in een URL staat', () => {
    const leaked = `/pleya/v1/stream/v-1?token=${ACCESS_TOKEN}`;
    expect(leaked).toContain(ACCESS_TOKEN);
  });
});

describe('streamsessies hergebruiken', () => {
  it('opent per versie één streamsessie en gebruikt hem opnieuw tot hij bijna verloopt', async () => {
    let now = Date.parse('2026-10-26T11:00:00Z');
    const cache = new StreamSessionCache(() => now);
    const api = fakeApi({
      streamSession: async () => ({ stream_session_id: `ss-${now}`, expires_at: '2026-10-26T11:30:00Z' })
    });
    const s = new PlayerSession(deps(api, { streamSessions: cache }));
    await s.start(asMedia(fakeMedia()), target);
    await s.start(asMedia(fakeMedia()), target);
    expect(api.calls.filter((c) => c.startsWith('stream-session'))).toHaveLength(1);

    now = Date.parse('2026-10-26T11:29:30Z');
    await s.start(asMedia(fakeMedia()), target);
    expect(api.calls.filter((c) => c.startsWith('stream-session'))).toHaveLength(2);
  });

  it('vraagt na een geweigerde bron een nieuwe aan (negatieve controle op blind hergebruik)', async () => {
    const cache = new StreamSessionCache(() => Date.parse('2026-10-26T11:00:00Z'));
    const api = fakeApi();
    const s = new PlayerSession(deps(api, { streamSessions: cache }));
    await s.start(asMedia(fakeMedia()), target);
    s.mediaFailed({ code: 4 });
    await s.start(asMedia(fakeMedia()), target);
    expect(api.calls.filter((c) => c.startsWith('stream-session'))).toHaveLength(2);
  });
});
