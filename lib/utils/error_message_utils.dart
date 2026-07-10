import 'dart:async';
import 'dart:io';

import '../i18n/strings.g.dart';
import 'app_logger.dart';
import '../exceptions/media_server_exceptions.dart';

/// Shared helpers for translating network errors into user-friendly messages.
String mapHttpErrorToMessage(MediaServerHttpException error, {required String context}) {
  switch (error.type) {
    case MediaServerHttpErrorType.connectionTimeout:
    case MediaServerHttpErrorType.receiveTimeout:
      return t.errors.connectionTimeout(context: context);
    case MediaServerHttpErrorType.connectionError:
      return t.errors.connectionFailed;
    default:
      appLogger.e('Error loading $context', error: error);
      final msg = error.message.isNotEmpty ? error.message : t.common.unknown;
      return t.errors.failedToLoad(context: context, error: msg);
  }
}

/// Generic fallback for unexpected errors. Never leaks raw `toString()` to
/// the UI — the raw error goes to [appLogger] via [friendlyError].
String mapUnexpectedErrorToMessage(dynamic error, {required String context}) {
  return friendlyError(error as Object, context: context);
}

/// Translate any caught error into a user-friendly, localized message.
///
/// Known network/transport failures map to specific messages; everything else
/// falls back to a generic "something went wrong". The raw error is logged,
/// never shown — users get a next action, not a stack-trace fragment.
String friendlyError(Object error, {String? context}) {
  if (error is MediaServerHttpException) {
    // Only the transient types map to a curated message. Other types (notably
    // `unknown`, whose `.message` is the original `error.toString()`) must NOT
    // surface their raw message — that's exactly the leak this helper prevents.
    // The raw exception still goes to the log.
    switch (error.type) {
      case MediaServerHttpErrorType.connectionTimeout:
      case MediaServerHttpErrorType.receiveTimeout:
        return context != null ? t.errors.connectionTimeout(context: context) : t.errors.connectionFailed;
      case MediaServerHttpErrorType.connectionError:
        return t.errors.connectionFailed;
      default:
        appLogger.e('Server error${context != null ? ' loading $context' : ''}', error: error);
        return context != null ? t.errors.couldNotLoad(context: context) : t.errors.somethingWentWrongTryAgain;
    }
  }
  if (error is SocketException || error is HandshakeException || error is HttpException) {
    return t.errors.connectionFailed;
  }
  if (error is TimeoutException) {
    return context != null ? t.errors.connectionTimeout(context: context) : t.errors.connectionFailed;
  }
  appLogger.e('Unexpected error${context != null ? ' in $context' : ''}', error: error);
  return context != null ? t.errors.couldNotLoad(context: context) : t.errors.somethingWentWrongTryAgain;
}
