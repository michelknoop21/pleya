/**
 * Het foutcodenregister uit hoofdstuk 7.1 van de specificatie.
 *
 * De code is het contract; `message` is voor logs en niet voor de UI. Deze
 * laag vertaalt de code naar een tekst en matcht nooit op het bericht. Een
 * code die hier niet in staat krijgt de generieke tekst en blijft in het
 * object staan, zodat een nieuwe servercode een nette fout oplevert en geen
 * lege melding.
 */
import { t } from '../i18n';
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

/**
 * Codes die de UI met een eigen woord benoemt. Elke code heeft de sleutel
 * `error.<code>` in beide catalogi; de tekst zelf staat dus in `web.ts` en
 * `web.nl.ts`, niet hier.
 */
export const ERROR_CODES = [
  'auth.invalid_credentials',
  'auth.token_expired',
  'auth.token_invalid',
  'auth.refresh_token_reused',
  'auth.setup_required',
  'auth.setup_already_completed',
  'auth.setup_code_invalid',
  'auth.rate_limited',
  'library.not_found',
  'library.scan_in_progress',
  'library.not_config_managed',
  'library.cursor_invalid',
  'library.search_query_empty',
  'library.version_multifile',
  'playback.version_unavailable',
  'job.not_cancellable',
  'storage.unavailable',
  'storage.full',
  'client.malformed_response',
  'client.transport'
] as const;

export type ErrorCode = (typeof ERROR_CODES)[number];

function isKnownCode(code: string): code is ErrorCode {
  return (ERROR_CODES as readonly string[]).includes(code);
}

export function describeError(error: unknown): string {
  if (error instanceof ApiError) {
    if (isKnownCode(error.code)) return t(`error.${error.code}`);
    return t('error.genericCode', { code: error.code });
  }
  if (error instanceof TransportError) return t('error.client.transport');
  return t('error.generic');
}
