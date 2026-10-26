/**
 * Elke fout die de speler kan krijgen, als één zin met een uitweg (S13.2,
 * S18.3), naar het voorbeeld van `admin/libraryErrors.ts`.
 *
 * Servercodes komen uit `openapi.yaml` (planPlayback, createStreamSession,
 * heartbeatPlaybackSession) en uit `pleya_server/internal/api/errors.go`:
 *
 * - `playback.not_playable` (415), `playback.version_unavailable` (409),
 *   `playback.transcode_failed` (502), `playback.transcode_busy` (503),
 *   `playback.file_corrupt` (502, S25.5) en `library.version_multifile` (409);
 * - `session.stream_session_limit` (429): acht actieve streamsessies;
 * - `library.not_found` (404): het item bestaat niet of deze gebruiker mag de
 *   bibliotheek niet zien; de server maakt die twee bewust gelijk;
 * - `server.database_unavailable`, `server.internal` en de 401-codes.
 *
 * Codes met `client.` ontstaan in de browser en gaan nooit over de lijn:
 * hls.js die na zijn herstelpogingen opgeeft, een `<video>` die het bestand
 * niet kan decoderen, of een omzetsessie die op de server verdween.
 */
import { ApiError, TransportError, describeError } from '../api/errors';
import { t, type MessageKey } from '../i18n';
import { DeliveryError } from './delivery';

/** Wat de foutstaat naast "terug" aanbiedt. */
export type PlayerWayOut = 'retry' | 'login' | 'back';

export interface PlayerProblem {
  code: string;
  message: string;
  wayOut: PlayerWayOut;
}

const KNOWN: Record<string, { key: MessageKey; wayOut: PlayerWayOut }> = {
  'auth.token_expired': { key: 'player.err.signedOut', wayOut: 'login' },
  'auth.token_invalid': { key: 'player.err.signedOut', wayOut: 'login' },
  'auth.refresh_token_reused': { key: 'player.err.signedOut', wayOut: 'login' },
  'auth.permission_not_allowed': { key: 'player.err.noPermission', wayOut: 'back' },
  'library.not_found': { key: 'player.err.notFound', wayOut: 'back' },
  'library.version_multifile': { key: 'player.err.multifile', wayOut: 'back' },
  'session.stream_session_limit': { key: 'player.err.streamLimit', wayOut: 'retry' },
  'playback.version_unavailable': { key: 'player.err.versionUnavailable', wayOut: 'retry' },
  'playback.transcode_busy': { key: 'player.err.transcodeBusy', wayOut: 'retry' },
  'playback.transcode_failed': { key: 'player.err.transcodeFailed', wayOut: 'retry' },
  'playback.file_corrupt': { key: 'player.err.fileCorrupt', wayOut: 'back' },
  'server.database_unavailable': { key: 'player.err.database', wayOut: 'retry' },
  'client.transport': { key: 'player.err.network', wayOut: 'retry' },
  'client.media_network': { key: 'player.err.network', wayOut: 'retry' },
  'client.media_decode': { key: 'player.err.decode', wayOut: 'back' },
  'client.session_ended': { key: 'player.err.sessionEnded', wayOut: 'retry' },
  'client.hls_unsupported': { key: 'player.err.hlsUnsupported', wayOut: 'back' },
  'client.plan_unknown': { key: 'player.err.planUnknown', wayOut: 'back' },
  'client.no_version': { key: 'player.err.noVersion', wayOut: 'back' }
};

/** De laatste reden van een 415 zegt of omzetten het had kunnen redden. */
function notPlayable(error: ApiError): PlayerProblem {
  const reasons = error.details['reasons'];
  const codes = Array.isArray(reasons)
    ? reasons.map((r) => (r && typeof r === 'object' ? (r as { code?: unknown }).code : null))
    : [];
  const noTranscoder = codes.includes('server.transcode_unavailable');
  return {
    code: error.code,
    message: t(noTranscoder ? 'player.err.notPlayableNoTranscode' : 'player.err.notPlayable'),
    wayOut: 'back'
  };
}

export function playerProblemFromCode(code: string): PlayerProblem {
  const known = KNOWN[code];
  if (known) return { code, message: t(known.key), wayOut: known.wayOut };
  return { code, message: t('player.err.generic', { code }), wayOut: 'retry' };
}

export function playerProblem(error: unknown): PlayerProblem {
  if (error instanceof DeliveryError) return playerProblemFromCode(error.code);
  if (error instanceof ApiError) {
    if (error.code === 'playback.not_playable') return notPlayable(error);
    if (KNOWN[error.code]) return playerProblemFromCode(error.code);
    if (error.code === 'server.internal') {
      const id = error.details['request_id'];
      return {
        code: error.code,
        message:
          typeof id === 'string' && id !== ''
            ? t('player.err.internalId', { id })
            : t('player.err.internal'),
        wayOut: 'retry'
      };
    }
    if (error.isAuthFailure) return { code: error.code, message: describeError(error), wayOut: 'login' };
    return { code: error.code, message: describeError(error), wayOut: 'retry' };
  }
  if (error instanceof TransportError) return playerProblemFromCode('client.transport');
  return { code: 'client.unknown', message: t('player.err.unknown'), wayOut: 'retry' };
}

/**
 * Een fout van het `<video>`-element zelf. `MEDIA_ERR_ABORTED` (1) is de
 * gebruiker of de opruimcode en geen fout.
 */
export function mediaErrorCode(error: { code: number } | null): string | null {
  if (!error || error.code === 1) return null;
  return error.code === 2 ? 'client.media_network' : 'client.media_decode';
}
