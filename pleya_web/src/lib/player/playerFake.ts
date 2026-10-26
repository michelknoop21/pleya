/**
 * Testdubbels voor de speler: een nep-API die elke aanvraag vastlegt, een
 * nep-`<video>` en een nep-hls.js. Alleen voor Vitest; niets hiervan komt in
 * de bundel, want niets buiten de tests importeert dit bestand.
 */
import { vi } from 'vitest';

import { ApiError } from '../api/errors';
import type { Capabilities } from '../api/types';
import type { HlsCtor, HlsErrorData, HlsLike } from './hlsEngine';
import type { PlaybackApi } from './playbackApi';
import type { PlayerDeps } from './playerSession.svelte';
import type { PlaybackPlan } from './types';

export const ACCESS_TOKEN = 'geheim-accesstoken-123';
export const STREAM_TOKEN = 'kort-streamtoken-456';

export function plan(over: Partial<PlaybackPlan> = {}): PlaybackPlan {
  return {
    item_id: 'item-1',
    version_id: 'v-1',
    delivery_mode: 'direct_play',
    stream_url: '/pleya/v1/stream/v-1',
    container: 'original',
    video: { action: 'copy' },
    audio: { action: 'copy' },
    seekable: true,
    session_id: null,
    reason: { code: 'direct.supported', params: {} },
    reasons: [{ code: 'direct.supported', params: {} }],
    ...over
  };
}

export const transcodePlan = (over: Partial<PlaybackPlan> = {}) =>
  plan({
    delivery_mode: 'transcode',
    stream_url: '/pleya/v1/playback/sessions/sess-1/index.m3u8',
    container: 'hls',
    video: { action: 'transcode' },
    seekable: false,
    session_id: 'sess-1',
    reason: { code: 'video.codec_unsupported', params: {} },
    reasons: [{ code: 'video.codec_unsupported', params: {} }],
    ...over
  });

export function apiError(code: string, status: number, details: Record<string, unknown> = {}) {
  return new ApiError({ code, message: code, status, retryable: false, details });
}

export interface FakeApi extends PlaybackApi {
  calls: string[];
  stops: { id: string; keepalive: boolean }[];
  heartbeats: string[];
}

export function fakeApi(
  opts: {
    plan?: () => Promise<PlaybackPlan>;
    heartbeat?: () => Promise<true>;
    streamSession?: () => Promise<{ stream_session_id: string; expires_at: string }>;
  } = {}
): FakeApi {
  const api: FakeApi = {
    calls: [],
    stops: [],
    heartbeats: [],
    plan: vi.fn(async (body) => {
      api.calls.push(`plan ${body.item_id}`);
      return opts.plan ? opts.plan() : plan();
    }),
    streamSession: vi.fn(async (versionId: string) => {
      api.calls.push(`stream-session ${versionId}`);
      return opts.streamSession
        ? opts.streamSession()
        : { stream_session_id: 'ss-1', expires_at: '2026-10-26T12:00:00Z' };
    }),
    streamToken: vi.fn(async (versionId: string) => {
      api.calls.push(`stream-token ${versionId}`);
      return { stream_token: STREAM_TOKEN, expires_at: '2026-10-26T12:00:00Z' };
    }),
    heartbeat: vi.fn(async (id: string) => {
      api.heartbeats.push(id);
      return opts.heartbeat ? opts.heartbeat() : (true as const);
    }),
    stop: vi.fn((id: string, keepalive: boolean) => {
      api.stops.push({ id, keepalive });
    }),
    bearer: vi.fn(async () => ACCESS_TOKEN),
    subtitleText: vi.fn(async () => 'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHallo\n')
  };
  return api;
}

/** Een `<video>` zonder decoder: houdt bij wat de speler eraan doet. */
export function fakeMedia() {
  const listeners = new Map<string, (() => void)[]>();
  const media = {
    src: '',
    srcHistory: [] as string[],
    duration: 600,
    currentTime: 0,
    paused: true,
    loads: 0,
    error: null as { code: number } | null,
    play: vi.fn(() => {
      media.paused = false;
      return Promise.resolve();
    }),
    pause: vi.fn(() => {
      media.paused = true;
    }),
    load: vi.fn(() => {
      media.loads += 1;
    }),
    removeAttribute: vi.fn((name: string) => {
      if (name === 'src') media.src = '';
    }),
    addEventListener: (type: string, fn: () => void) => {
      listeners.set(type, [...(listeners.get(type) ?? []), fn]);
    },
    emit(type: string) {
      for (const fn of listeners.get(type) ?? []) fn();
    }
  };
  return new Proxy(media, {
    set(target, key, value) {
      if (key === 'src' && value) target.srcHistory.push(String(value));
      (target as Record<string | symbol, unknown>)[key] = value;
      return true;
    }
  });
}

export type FakeMedia = ReturnType<typeof fakeMedia>;

/** Een nep-hls.js waarvan elke instantie vastgelegd wordt. */
export function fakeHls() {
  const instances: FakeHlsInstance[] = [];
  class FakeHlsInstance implements HlsLike {
    config: Record<string, unknown>;
    source = '';
    media: unknown = null;
    destroyed = false;
    startLoads = 0;
    recoveries = 0;
    swaps = 0;
    #handlers = new Map<string, ((e: string, d: HlsErrorData) => void)[]>();
    constructor(config: Record<string, unknown>) {
      this.config = config;
      instances.push(this);
    }
    loadSource(url: string) {
      this.source = url;
    }
    attachMedia(media: HTMLMediaElement) {
      this.media = media;
    }
    on(event: string, fn: (e: string, d: HlsErrorData) => void) {
      this.#handlers.set(event, [...(this.#handlers.get(event) ?? []), fn]);
    }
    emit(event: string, data: HlsErrorData) {
      for (const fn of this.#handlers.get(event) ?? []) fn(event, data);
    }
    startLoad() {
      this.startLoads += 1;
    }
    recoverMediaError() {
      this.recoveries += 1;
    }
    swapAudioCodec() {
      this.swaps += 1;
    }
    destroy() {
      this.destroyed = true;
    }
  }
  const Hls = Object.assign(FakeHlsInstance, {
    isSupported: () => true,
    Events: { ERROR: 'hlsError', FRAG_LOADED: 'hlsFragLoaded' },
    ErrorTypes: { NETWORK_ERROR: 'networkError', MEDIA_ERROR: 'mediaError' }
  }) as unknown as HlsCtor;
  return { Hls, instances };
}

export const SERVER_CAPS = {
  browse: true,
  search: true,
  artwork: true,
  watch_state: true,
  playback_plan: true,
  transcode: true,
  stream_sessions: true
} as Capabilities;

/** Handmatige timers: `tick()` draait elke interval één keer. */
export function manualTimers() {
  const intervals = new Map<number, () => void>();
  let next = 1;
  return {
    setInterval: (fn: () => void) => {
      const id = next++;
      intervals.set(id, fn);
      return id;
    },
    clearInterval: (id: unknown) => {
      intervals.delete(id as number);
    },
    tick() {
      for (const fn of [...intervals.values()]) fn();
    },
    get active() {
      return intervals.size;
    }
  };
}

export function deps(
  api: FakeApi,
  over: Partial<PlayerDeps> & { hls?: ReturnType<typeof fakeHls> } = {}
): PlayerDeps {
  const hls = over.hls ?? fakeHls();
  return {
    api,
    server: SERVER_CAPS,
    probe: () => ({ caps: { decoder: {} }, hls: { hlsjs: true, native: false } }),
    loadHls: async () => hls.Hls,
    origin: 'http://pleya.test',
    timers: manualTimers(),
    ...over
  };
}
