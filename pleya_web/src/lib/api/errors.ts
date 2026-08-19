/**
 * Het foutcodenregister uit hoofdstuk 7.1 van de specificatie.
 *
 * De code is het contract; `message` is voor logs en niet voor de UI. Deze
 * laag vertaalt de code naar een tekst en matcht nooit op het bericht. Een
 * code die hier niet in staat krijgt de generieke tekst en blijft in het
 * object staan, zodat een nieuwe servercode een nette fout oplevert en geen
 * lege melding.
 */
import type { ErrorEnvelope } from './types';

export class ApiError extends Error {
  readonly code: string;
  readonly status: number;
  readonly retryable: boolean;
  readonly details: Record<string, unknown>;

  constructor(init: {
    code: string;
    message: string;
    status: number;
    retryable: boolean;
    details?: Record<string, unknown>;
  }) {
    super(init.message);
    this.name = 'ApiError';
    this.code = init.code;
    this.status = init.status;
    this.retryable = init.retryable;
    this.details = init.details ?? {};
  }

  /** Milliseconden uit `details.retry_after_ms` bij `auth.rate_limited`. */
  get retryAfterMs(): number | null {
    const raw = this.details['retry_after_ms'];
    return typeof raw === 'number' && Number.isFinite(raw) ? raw : null;
  }

  get isAuthFailure(): boolean {
    return this.code.startsWith('auth.');
  }
}

/** Een fout die niet van de server komt: geen netwerk, of een afgebroken aanvraag. */
export class TransportError extends Error {
  override readonly cause: unknown;
  constructor(cause: unknown) {
    super('transport');
    this.name = 'TransportError';
    this.cause = cause;
  }
}

/**
 * Leest de foutvorm uit een antwoord. Een antwoord dat geen geldige envelop
 * draagt is zelf een fout: dan is er iets anders dan een Pleya Server aan de
 * lijn, en dat verzwijgen levert een leeg scherm zonder reden op.
 */
export function toApiError(status: number, body: unknown): ApiError {
  const envelope = body as ErrorEnvelope | undefined;
  const error = envelope?.error;
  if (!error || typeof error.code !== 'string') {
    return new ApiError({
      code: 'client.malformed_response',
      message: `Unexpected response (HTTP ${status})`,
      status,
      retryable: status >= 500
    });
  }
  return new ApiError({
    code: error.code,
    message: error.message ?? error.code,
    status,
    retryable: Boolean(error.retryable),
    details: (error.details ?? {}) as Record<string, unknown>
  });
}

/** Codes die de UI met een eigen woord benoemt. */
export const ERROR_MESSAGES: Record<string, string> = {
  'auth.invalid_credentials': 'That username and password do not match.',
  'auth.token_expired': 'Your session expired. Sign in again.',
  'auth.token_invalid': 'Your session is no longer valid. Sign in again.',
  'auth.refresh_token_reused': 'Your session was ended for safety. Sign in again.',
  'auth.setup_required': 'This server has no owner yet. Finish setup first.',
  'auth.setup_already_completed': 'This server already has an owner. Sign in instead.',
  'auth.setup_code_invalid': 'That setup code is not valid or has expired.',
  'auth.rate_limited': 'Too many attempts. Wait a moment and try again.',
  'library.not_found': 'That item is not on this server.',
  'library.scan_in_progress': 'A scan is running. Try again in a moment.',
  'library.cursor_invalid': 'The list moved on. Reloading from the start.',
  'library.search_query_empty': 'Type something to search for.',
  'library.version_multifile': 'This version is split across several files.',
  'playback.version_unavailable': 'That file cannot be read right now.',
  'storage.unavailable': 'The server cannot reach its storage right now.',
  'storage.full': 'The server has no room left to write.',
  'client.malformed_response': 'The server sent something this client cannot read.',
  'client.transport': 'Cannot reach the server. Check the connection and try again.'
};

export function describeError(error: unknown): string {
  if (error instanceof ApiError) {
    const known = ERROR_MESSAGES[error.code];
    if (known) return known;
    return `Something went wrong (${error.code}).`;
  }
  if (error instanceof TransportError) return ERROR_MESSAGES['client.transport']!;
  return 'Something went wrong.';
}
