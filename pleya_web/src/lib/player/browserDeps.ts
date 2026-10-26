/**
 * De echte afhankelijkheden van de speler: de API-client van de sessie, de
 * probe op deze browser en hls.js als losse bundel die pas laadt wanneer het
 * plan om HLS vraagt.
 */
import type { PleyaClient } from '../api/client';
import type { Capabilities } from '../api/types';
import { browserProbeEnv, hlsSupport, probeCapabilities } from './capabilities';
import type { HlsCtor } from './hlsEngine';
import { playbackApi } from './playbackApi';
import { streamSessions } from './streamSessionCache';
import type { PlayerDeps } from './playerSession.svelte';

export function browserPlayerDeps(client: PleyaClient, server: Capabilities | null): PlayerDeps {
  return {
    api: playbackApi(client),
    server,
    probe: () => {
      const env = browserProbeEnv();
      return { caps: probeCapabilities(env), hls: hlsSupport(env) };
    },
    // De lichte bouw: zonder alternatieve audio, ondertitels via HLS, EME en
    // CMCD. Een omzetsessie levert één fMP4-rendition, dus dat mist niets, en
    // het scheelt een derde van de bundel. Pas laden als het plan om HLS vraagt.
    loadHls: async () => (await import('hls.js/light')).default as unknown as HlsCtor,
    origin: location.origin,
    streamSessions
  };
}
