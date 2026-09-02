import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../exceptions/media_server_exceptions.dart';
import '../i18n/strings.g.dart';
import '../main.dart' show rootNavigatorKey;
import '../screens/settings/logs_screen.dart';
import '../widgets/notice/notice.dart';
import 'app_logger.dart';
import 'playback_failure_classifier.dart';

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
      return t.errors.couldNotLoad(context: context);
  }
}

/// Generic fallback for unexpected errors. Never leaks raw `toString()` to
/// the UI — the raw error goes to [appLogger] via [friendlyError].
String mapUnexpectedErrorToMessage(dynamic error, {required String context}) {
  return friendlyError(error as Object, context: context);
}

/// Translate any caught error into a user-friendly, localized message.
///
/// Known network/transport/auth failures map to specific messages;
/// everything else falls back to a generic "something went wrong". The raw
/// error is logged, never shown — users get a next action, not a
/// stack-trace fragment.
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
  // MediaServerAuthException also covers MediaServerPinExpiredException (a
  // subtype) — both collapse to the same generic sign-in failure text; the
  // curated distinction isn't worth a second string yet.
  if (error is MediaServerAuthException) {
    appLogger.e('Authentication failed${context != null ? ' for $context' : ''}', error: error);
    return t.errors.authenticationFailed;
  }
  if (error is MediaServerUrlException) {
    appLogger.e('Server unreachable${context != null ? ' for $context' : ''}', error: error);
    return t.errors.connectionFailed;
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

/// Builds a [Notice] for [error], logging it with a [noticeCode] first so
/// the notice's "Details" action can jump straight to the matching log line.
///
/// [context] and [serverName] shape both the message and the notice's
/// `groupKey` (so retries against the *same* thing fold into one counter
/// instead of stacking — see [NoticeController]). Pass [onRetry] when the
/// caller can actually retry; it becomes the primary action and "Details"
/// moves to secondary. Without it, "Details" is primary.
Notice noticeForError(Object error, {String? context, String? serverName, VoidCallback? onRetry}) {
  final code = logNoticeError(context ?? 'error', error);
  final scope = serverName ?? context ?? 'generic';
  final (primary, secondary) = _noticeActions(onRetry: onRetry);

  if (error is MediaServerHttpException) {
    switch (error.type) {
      case MediaServerHttpErrorType.connectionTimeout:
      case MediaServerHttpErrorType.receiveTimeout:
        return Notice(
          level: NoticeLevel.error,
          title: t.notices.connectionTimeoutTitle,
          body: context != null ? t.notices.connectionTimeoutBody(context: context) : null,
          primary: primary,
          secondary: secondary,
          reportCode: code,
          groupKey: 'timeout:$scope',
        );
      case MediaServerHttpErrorType.connectionError:
        return Notice(
          level: NoticeLevel.error,
          title: t.notices.connectionFailedTitle,
          body: serverName != null ? t.notices.connectionFailedBody(serverName: serverName) : null,
          primary: primary,
          secondary: secondary,
          reportCode: code,
          groupKey: 'connection:$scope',
        );
      default:
        return Notice(
          level: NoticeLevel.error,
          title: context != null ? t.notices.couldNotLoadTitle(context: context) : t.notices.genericErrorTitle,
          primary: primary,
          secondary: secondary,
          reportCode: code,
          groupKey: 'http:$scope',
        );
    }
  }
  if (error is MediaServerAuthException) {
    return Notice(
      level: NoticeLevel.error,
      title: t.notices.authFailedTitle,
      primary: primary,
      secondary: secondary,
      reportCode: code,
      groupKey: 'auth:$scope',
    );
  }
  if (error is MediaServerUrlException) {
    return Notice(
      level: NoticeLevel.error,
      title: t.notices.connectionFailedTitle,
      body: serverName != null ? t.notices.connectionFailedBody(serverName: serverName) : null,
      primary: primary,
      secondary: secondary,
      reportCode: code,
      groupKey: 'url:$scope',
    );
  }
  if (error is SocketException || error is HandshakeException || error is HttpException) {
    return Notice(
      level: NoticeLevel.error,
      title: t.notices.connectionFailedTitle,
      body: serverName != null ? t.notices.connectionFailedBody(serverName: serverName) : null,
      primary: primary,
      secondary: secondary,
      reportCode: code,
      groupKey: 'connection:$scope',
    );
  }
  if (error is TimeoutException) {
    return Notice(
      level: NoticeLevel.error,
      title: t.notices.connectionTimeoutTitle,
      body: context != null ? t.notices.connectionTimeoutBody(context: context) : null,
      primary: primary,
      secondary: secondary,
      reportCode: code,
      groupKey: 'timeout:$scope',
    );
  }
  return Notice(
    level: NoticeLevel.error,
    title: context != null ? t.notices.couldNotLoadTitle(context: context) : t.notices.genericErrorTitle,
    primary: primary,
    secondary: secondary,
    reportCode: code,
    groupKey: 'unknown:$scope',
  );
}

/// Builds a [Notice] for a raw mpv/transcoder log line. The line itself is
/// never shown — [classifyPlaybackFailure] buckets it into a
/// [PlaybackFailureKind] first, and only the bucket's curated body text
/// reaches the screen. The raw line still goes to the log, tagged with the
/// notice's [Notice.reportCode].
Notice noticeForPlaybackFailure(String rawMessage, {VoidCallback? onRetry}) {
  final code = logNoticeError('playback', rawMessage);
  return noticeForPlaybackFailureKind(classifyPlaybackFailure(rawMessage), reportCode: code, onRetry: onRetry);
}

/// Builds the [Notice] for a playback failure whose [kind] is already known,
/// e.g. a Plex item whose `checkFiles=1` flags say the file is gone before
/// mpv ever opened it. [reportCode] is the code the caller logged; without
/// one, a line is logged here so "Details" still has something to point at.
///
/// Every playback notice is bounded in time, unlike other errors. The player
/// has already left the screen by the time it shows, so there is nothing to
/// act on, and a card that stays until it is clicked away is a card that is
/// still standing over the next video on a tv where nobody clicks.
Notice noticeForPlaybackFailureKind(PlaybackFailureKind kind, {String? reportCode, VoidCallback? onRetry}) {
  final code = reportCode ?? logNoticeError('playback', kind.name);
  final (primary, secondary) = _noticeActions(onRetry: onRetry);
  final title = switch (kind) {
    PlaybackFailureKind.fileUnavailable => t.notices.playbackFileUnavailableTitle,
    _ => t.notices.playbackStoppedTitle,
  };
  final body = switch (kind) {
    PlaybackFailureKind.fileUnavailable => t.notices.playbackFileUnavailableBody,
    PlaybackFailureKind.segmentUnavailable => t.notices.playbackSegmentUnavailableBody,
    PlaybackFailureKind.connectionLost => t.notices.playbackConnectionLostBody,
    PlaybackFailureKind.codecUnsupported => t.notices.playbackCodecUnsupportedBody,
    PlaybackFailureKind.serverError => t.notices.playbackServerErrorBody,
    PlaybackFailureKind.unknown => null,
  };
  return Notice(
    level: NoticeLevel.error,
    title: title,
    body: body,
    primary: primary,
    secondary: secondary,
    reportCode: code,
    groupKey: '$playbackNoticeGroupPrefix${kind.name}',
    durationOverride: playbackNoticeDuration,
  );
}

/// Every playback failure notice shares this [Notice.groupKey] prefix, so the
/// player can clear whatever is still standing once a video does play.
const String playbackNoticeGroupPrefix = 'playback:';

/// How long a playback failure stays on screen. Long enough to read two
/// sentences on a tv across the room, short enough not to outlive the next
/// thing the user starts.
const Duration playbackNoticeDuration = Duration(seconds: 12);

/// Builds a [Notice] for a failed play/shuffle launch. Deliberately doesn't
/// go through [noticeForError]: [actionLabel] is a verb ("Play", "Shuffle"),
/// so the verb-phrase "Failed to ${action}" reads right where
/// [noticeForError]'s noun-phrase "Couldn't load ${context}" wouldn't.
Notice noticeForPlaybackLaunchFailure(Object error, {required String actionLabel}) {
  final code = logNoticeError('playback-launch: $actionLabel', error);
  final (primary, secondary) = _noticeActions(onRetry: null);
  return Notice(
    level: NoticeLevel.error,
    title: t.messages.failedPlayback(action: actionLabel),
    primary: primary,
    secondary: secondary,
    reportCode: code,
    groupKey: 'playback-launch:$actionLabel',
  );
}

/// Retry (when offered) is always primary, "Details" (always offered, since
/// every [noticeForError] call already logged a code) fills whichever slot
/// is left. On tv this keeps a bare playback failure from defaulting to
/// "Details" as the loudest button when there's nothing to retry.
(NoticeAction primary, NoticeAction? secondary) _noticeActions({required VoidCallback? onRetry}) {
  final details = NoticeAction(
    label: t.common.details,
    onPressed: () => rootNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const LogsScreen())),
  );
  if (onRetry == null) return (details, null);
  return (NoticeAction(label: t.common.retry, onPressed: onRetry), details);
}
