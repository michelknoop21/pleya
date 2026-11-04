/**
 * Van afspeelplan naar wat de `<video>` krijgt.
 *
 * Twee wegen, en het plan van de server kiest (S17):
 *
 * - `direct_play`: het bestand zelf over `GET /stream/{version_id}` met
 *   HTTP-range. De browser zet een `src` en kan geen header meesturen, dus het
 *   credential reist als browser-streamsessie: de niet-geheime id als `ss` in
 *   de URL, het geheim als HttpOnly-cookie die JavaScript nooit ziet. Kent de
 *   server geen streamsessies, dan is de terugval het kortlevende streamtoken
 *   in de query, de uitzondering die het contract voor spelers zonder header
 *   maakt.
 * - `remux`, `direct_stream` en `transcode`: een HLS-afspeellijst van een
 *   omzetsessie. hls.js haalt elke afspeellijst en elk segment zelf op en zet
 *   er een Authorization-header op, dus deze URL draagt geen enkel
 *   credential. De streamsessie kan hier niet: de cookie heeft
 *   `Path=/pleya/v1/stream/` en bereikt `/playback/sessions/` nooit, en de
 *   server leest bij `ss` de versie uit het pad, dat hier geen versie draagt.
 *   Alleen een browser zonder MediaSource (oude iOS) speelt HLS zelf, en die
 *   krijgt het streamtoken in de query; zie `nativeHlsUrl`.
 */
import type { PlaybackPlan } from './types';
import type { HlsSupport } from './capabilities';

export type DeliveryMode = 'direct_play' | 'remux' | 'direct_stream' | 'transcode';

export type Delivery =
  | { kind: 'direct'; versionId: string; path: string; mode: 'direct_play' }
  | {
      kind: 'hls';
      versionId: string;
      sessionId: string;
      path: string;
      mode: Exclude<DeliveryMode, 'direct_play'>;
      engine: 'hlsjs' | 'native';
    };

/** Een plan dat deze client niet kan uitvoeren. De code gaat naar `playerErrors`. */
export class DeliveryError extends Error {
  readonly code: string;
  constructor(code: string) {
    super(code);
    this.name = 'DeliveryError';
    this.code = code;
  }
}

const SESSION_MODES = new Set(['remux', 'direct_stream', 'transcode']);

/**
 * Kiest de weg. `plan` is null wanneer de server geen planner heeft
 * (`capabilities.playback_plan` onwaar): dan direct play van de gekozen versie,
 * zoals de app het vóór S17 deed.
 */
export function chooseDelivery(
  plan: PlaybackPlan | null,
  fallbackVersionId: string,
  hls: HlsSupport
): Delivery {
  if (!plan || plan.delivery_mode === 'direct_play') {
    const versionId = plan?.version_id ?? fallbackVersionId;
    return {
      kind: 'direct',
      versionId,
      path: plan?.stream_url ?? `/pleya/v1/stream/${encodeURIComponent(versionId)}`,
      mode: 'direct_play'
    };
  }
  if (!SESSION_MODES.has(plan.delivery_mode) || !plan.session_id) {
    // Een leveringswijze die deze build niet kent verandert niet stilzwijgend
    // in iets anders: de sessie loopt al op de server en wordt opgeruimd.
    throw new DeliveryError('client.plan_unknown');
  }
  if (!hls.hlsjs && !hls.native) throw new DeliveryError('client.hls_unsupported');
  return {
    kind: 'hls',
    versionId: plan.version_id,
    sessionId: plan.session_id,
    path: plan.stream_url,
    mode: plan.delivery_mode as Exclude<DeliveryMode, 'direct_play'>,
    engine: hls.hlsjs ? 'hlsjs' : 'native'
  };
}

/** Plakt een queryparameter aan een pad, met de bestaande query intact. */
export function withQuery(path: string, name: string, value: string): string {
  const sep = path.includes('?') ? '&' : '?';
  return `${path}${sep}${encodeURIComponent(name)}=${encodeURIComponent(value)}`;
}

/** Direct play met een streamsessie: alleen de niet-geheime id staat in de URL. */
export function directUrlWithSession(delivery: { path: string }, streamSessionId: string): string {
  return withQuery(delivery.path, 'ss', streamSessionId);
}

/** De terugval zonder streamsessies, en de enige weg voor native HLS. */
export function urlWithStreamToken(path: string, streamToken: string): string {
  return withQuery(path, 'stream_token', streamToken);
}

/** Een server-relatief pad van het plan, gebonden aan de origin van de pagina. */
export function absolute(path: string, origin: string): string {
  return new URL(path, origin).toString();
}
