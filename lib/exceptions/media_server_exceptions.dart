import 'dart:async';
import 'dart:io';

import 'package:http/http.dart';

/// Sealed base for backend-agnostic media-server exceptions. Both Plex and
/// Jellyfin auth/HTTP layers throw subtypes from this hierarchy so consumers
/// can catch with one filter and match exhaustively when they care which
/// failure mode it is.
sealed class MediaServerException implements Exception {
  final String message;
  const MediaServerException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// The supplied base URL is unreachable, returns the wrong shape, or doesn't
/// look like the expected backend at all. Surfaces in onboarding probes
/// (Jellyfin `/System/Info/Public`, Plex resource discovery).
class MediaServerUrlException extends MediaServerException {
  const MediaServerUrlException(super.message);
}

/// Authentication failed — bad password, expired token, disabled user,
/// rate-limit. [statusCode] is the HTTP status when the failure was a 4xx
/// response; null for transport-layer auth signals (e.g. token rejected
/// during refresh).
class MediaServerAuthException extends MediaServerException {
  final int? statusCode;
  const MediaServerAuthException(super.message, {this.statusCode});
}

/// Auth polling reached a terminal server-side expiry/rejection state before
/// the user completed the external sign-in flow.
class MediaServerPinExpiredException extends MediaServerAuthException {
  const MediaServerPinExpiredException() : super('PIN expired before sign-in');
}

/// HTTP transport / non-2xx errors. Carries the status code (when known),
/// the parsed response body, and the originating URI so callers can log
/// useful diagnostics. Both Plex and Jellyfin route their HTTP failures
/// through this type — it's the canonical backend-agnostic transport
/// exception.
enum MediaServerHttpErrorType { connectionTimeout, receiveTimeout, connectionError, cancelled, unknown }

class MediaServerHttpException extends MediaServerException {
  final MediaServerHttpErrorType type;
  final int? statusCode;
  final dynamic responseData;
  final Uri? requestUri;

  MediaServerHttpException({required this.type, String? message, this.statusCode, this.responseData, this.requestUri})
    : super(message ?? '');

  /// Map a caught exception to a [MediaServerHttpException].
  factory MediaServerHttpException.from(Object error, {Uri? uri}) {
    return switch (error) {
      MediaServerHttpException() => error,
      RequestAbortedException(:final message, uri: final errorUri) => MediaServerHttpException(
        type: MediaServerHttpErrorType.cancelled,
        message: message,
        requestUri: errorUri ?? uri,
      ),
      TimeoutException(:final message) => MediaServerHttpException(
        type: MediaServerHttpErrorType.connectionTimeout,
        message: message,
        requestUri: uri,
      ),
      SocketException(:final message) => MediaServerHttpException(
        type: MediaServerHttpErrorType.connectionError,
        message: message,
        requestUri: uri,
      ),
      HttpException(:final message) => MediaServerHttpException(
        type: MediaServerHttpErrorType.connectionError,
        message: message,
        requestUri: uri,
      ),
      ClientException(:final message, uri: final errorUri) => MediaServerHttpException(
        type: MediaServerHttpErrorType.connectionError,
        message: message,
        requestUri: errorUri ?? uri,
      ),
      _ => MediaServerHttpException(type: MediaServerHttpErrorType.unknown, message: error.toString(), requestUri: uri),
    };
  }

  /// Whether the error looks transient (network/timeout) and worth retrying.
  bool get isTransient =>
      type == MediaServerHttpErrorType.connectionTimeout ||
      type == MediaServerHttpErrorType.connectionError ||
      type == MediaServerHttpErrorType.receiveTimeout;

  @override
  String toString() {
    final parts = <String>[type.name];
    if (statusCode != null) parts.add('HTTP $statusCode');
    if (message.isNotEmpty) parts.add(message);
    final uri = requestUri;
    if (uri != null) parts.add('${uri.host}${uri.path}');
    return 'MediaServerHttpException(${parts.join(': ')})';
  }
}

/// Whether a failed *write* to a media server is worth queueing for a retry
/// when the server comes back, or is a dead end that reconnecting will never
/// resolve (hoofdstuk 13.4 point 4, and fase 9's remove-from-Continue-Watching
/// replay rule).
///
/// The distinction matters because a queue entry is a promise to the user:
/// "the rest will be retried". Queueing a write the backend does not implement,
/// or one it rejected because the session is no longer valid, turns that
/// promise into a row that retries forever and never lands.
///
/// Not retryable:
/// - [MediaServerAuthException], and any 401/403 — the user has to sign in
///   again, which is an action reconnecting does not perform for them.
/// - [UnsupportedError] — the backend has no such endpoint at all. Jellyfin's
///   `removeFromContinueWatching` throws exactly this.
/// - Any other 4xx except 408 (request timeout) and 429 (rate limited), which
///   are the two client-range statuses that genuinely mean "try again".
///
/// Everything else — timeouts, socket errors, 5xx, an unrecognised throw — is
/// retryable. Erring towards retry is the safe direction: a queued entry that
/// turns out to be hopeless is capped by `maxSyncAttempts`, while a dropped
/// one is a write the user was told had been remembered and silently was not.
bool isRetryableServerWriteFailure(Object error) {
  if (error is UnsupportedError) return false;
  if (error is MediaServerAuthException) return false;
  final status = error is MediaServerHttpException ? error.statusCode : null;
  if (status == null) return true;
  if (status == 408 || status == 429) return true;
  return status < 400 || status >= 500;
}
