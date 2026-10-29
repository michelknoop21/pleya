/**
 * De aanvragen van het afspeelpad, allemaal over de gegenereerde paden uit
 * `schema.d.ts`. Een pad dat het contract niet kent compileert hier niet.
 *
 * Kijkstatus volgt DEC-049; alleen de speler schrijft, nooit het cataloguspad.
 */
import type { components } from '../api/schema';
import type { PleyaClient } from '../api/client';
import type { PlaybackPlan, PlaybackPlanRequest, StreamSession, StreamToken, WatchStateEvent, UserState } from './types';

export interface PlaybackApi {
  reportWatchState(body: WatchStateEvent, keepalive?: boolean): Promise<UserState>;
  plan(body: PlaybackPlanRequest, signal?: AbortSignal): Promise<PlaybackPlan>;
  streamSession(versionId: string, signal?: AbortSignal): Promise<StreamSession>;
  streamToken(versionId: string, signal?: AbortSignal): Promise<StreamToken>;
  heartbeat(sessionId: string): Promise<true>;
  /**
   * Stopt een omzetsessie. Met `keepalive` overleeft de aanvraag het sluiten
   * van de pagina. `sendBeacon` kan dat niet: die kent alleen POST en geen
   * Authorization-header, en dit is een DELETE die een bearer vraagt.
   */
  stop(sessionId: string, keepalive: boolean): void;
  /** Een geldig accesstoken voor hls.js, zo nodig eerst ververst. */
  bearer(): Promise<string | null>;
  /** De bytes van een ondertitelbestand, met de bearer in de header. */
  subtitleText(subtitleId: string, signal?: AbortSignal): Promise<string>;
}

const ok = <T>(result: { error?: unknown; response: Response }, data: T) =>
  result.response.ok
    ? { data, response: result.response }
    : { error: result.error, response: result.response };

export function playbackApi(
  client: PleyaClient,
  fetchImpl: (input: string, init: RequestInit) => Promise<Response> = (i, init) =>
    globalThis.fetch(i, init)
): PlaybackApi {
  const generation = client.sessionGeneration;
  const assertAccount = () => {
    if (generation !== client.sessionGeneration) throw new Error('Playback account changed');
  };
  const owned = async <T>(request: () => Promise<T>): Promise<T> => {
    assertAccount();
    const result = await request();
    assertAccount();
    return result;
  };
  return {
    reportWatchState(body, keepalive = false) {
      try { assertAccount(); } catch (error) { return Promise.reject(error); }
      if (!keepalive) return owned(() => client.request((raw) => raw.POST('/watch-state', { body: body as components['schemas']['WatchStateEvent'] })));
      const access = client.tokens.accessToken;
      if (!access) return Promise.reject(new Error('No active playback account'));
      return fetchImpl(`${client.baseUrl}/watch-state`, {
        method: 'POST', keepalive: true,
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${access}` },
        body: JSON.stringify(body)
      }).then(async (response) => {
        if (!response.ok) throw new Error(`watch-state ${response.status}`);
        return await response.json() as UserState;
      });
    },
    plan: (body, signal) => owned(() => client.request((raw) => raw.POST('/playback/plan', { body, signal }))),

    streamSession: (versionId, signal) =>
      owned(() => client.request((raw) =>
        raw.POST('/auth/stream-session', { body: { version_id: versionId }, signal })
      )),

    streamToken: (versionId, signal) =>
      owned(() => client.request((raw) =>
        raw.POST('/auth/stream-token', { body: { version_id: versionId }, signal })
      )),

    heartbeat: (sessionId) =>
      owned(() => client.request<true>(async (raw) =>
        ok(
          await raw.POST('/playback/sessions/{session_id}/heartbeat', {
            params: { path: { session_id: sessionId } }
          }),
          true as const
        )
      )),

    stop(sessionId, keepalive) {
      if (generation !== client.sessionGeneration) return;
      // Synchroon gestart, zonder middleware ertussen: in `pagehide` is er
      // geen garantie dat een aanvraag na een await nog vertrekt. Is het
      // token net verlopen, dan ruimt de server de sessie na een minuut
      // zonder hartslag zelf op.
      const headers = new Headers();
      const access = client.tokens.accessToken;
      if (access) headers.set('Authorization', `Bearer ${access}`);
      const url = `${client.baseUrl}/playback/sessions/${encodeURIComponent(sessionId)}`;
      void fetchImpl(url, { method: 'DELETE', headers, keepalive }).catch(() => undefined);
    },

    bearer: () => owned(() => client.bearer()),

    async subtitleText(subtitleId, signal) {
      const headers = new Headers();
      const access = await owned(() => client.bearer());
      if (access) headers.set('Authorization', `Bearer ${access}`);
      const url = `${client.baseUrl}/subtitles/${encodeURIComponent(subtitleId)}`;
      const response = await fetchImpl(url, { headers, signal });
      if (!response.ok) throw new Error(`subtitle ${response.status}`);
      return await response.text();
    }
  };
}
