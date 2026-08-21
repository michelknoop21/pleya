/// Decides where a fresh playback open should start.
///
/// Before this existed the answer was assembled in two places that did not
/// agree: `navigateToVideoPlayer` only refetched the item when it carried no
/// view offset at all, and `_resolveOpenResumePosition` preferred locally
/// tracked offline progress over the server value whenever playback ran off a
/// downloaded file — including while the app was online and another device had
/// watched further. The result was a resume that could walk backwards.
///
/// The order below is on *intent, origin and time*, never on "whichever
/// position is larger". Picking the maximum looks safe and is exactly what
/// makes a rewind impossible.
library;

import 'package:flutter/foundation.dart';

/// Why a local progress record exists.
///
/// A [passive] record was written by the progress tracker while something was
/// playing; an [explicit] one follows a deliberate user action (seek, mark
/// unwatched, play from a chosen position). Only an explicit record is allowed
/// to beat a freshly fetched server value.
enum PlaybackResumeIntent { passive, explicit }

/// Where a local progress record came from.
enum PlaybackResumeOrigin {
  /// Written while playing a downloaded file, possibly with no network.
  offlinePlayback,

  /// Written as the direct result of a user action.
  userAction,
}

/// Which tier produced the resolved position. Reported so callers can log the
/// reason without re-deriving it, and so tests assert on the tier rather than
/// on a position that several tiers could coincidentally agree on.
enum PlaybackResumeSource {
  /// Caller asked to start from the beginning.
  restart,

  /// Caller passed an explicit position.
  requested,

  /// A local record that is demonstrably newer than the backend state.
  localNewer,

  /// Progress fetched from the backend during this open.
  freshBackend,

  /// The view offset already on the screen's metadata (fetch failed or was
  /// skipped).
  cachedMetadata,

  /// Locally tracked progress, with no backend value to compare against.
  localFallback,

  /// Nothing known; start from zero without a resume prompt.
  none,
}

/// Locally tracked progress for one item.
@immutable
class LocalResumeProgress {
  const LocalResumeProgress({
    required this.position,
    required this.updatedAt,
    required this.intent,
    required this.origin,
  });

  final Duration position;
  final DateTime updatedAt;
  final PlaybackResumeIntent intent;
  final PlaybackResumeOrigin origin;
}

/// Backend-held progress for one item.
///
/// [isFresh] separates a value fetched during this open from the view offset
/// that happened to be on the list/detail snapshot the user tapped. Both are
/// "the backend said so", but only one of them is known to be current, and a
/// stale one must not outrank newer local knowledge.
@immutable
class BackendResumeProgress {
  const BackendResumeProgress({required this.position, required this.isFresh, this.updatedAt});

  final Duration position;
  final bool isFresh;

  /// When the backend last saw this item, when it tells us. Plex and Jellyfin
  /// both expose it as `lastViewedAt`; it can be absent on endpoints that omit
  /// per-user data, in which case no ordering claim can be made.
  final DateTime? updatedAt;
}

/// The chosen position plus the tier that produced it.
@immutable
class PlaybackResumeResolution {
  const PlaybackResumeResolution(this.position, this.source);

  /// Null means "no resume position known", which is not the same as
  /// [Duration.zero] ("deliberately start at the beginning").
  final Duration? position;
  final PlaybackResumeSource source;

  @override
  String toString() => 'PlaybackResumeResolution(${position?.inMilliseconds}ms, ${source.name})';
}

/// The single place that answers "where does this open start?".
class PlaybackResumeResolver {
  const PlaybackResumeResolver._();

  /// Resolve the resume position from every source that has something to say.
  ///
  /// Tiers, highest first:
  ///  1. [restartFromBeginning], or an explicit [requestedPosition]
  ///  2. [local], when it is demonstrably newer than [backend]
  ///  3. [backend] when it was fetched during this open
  ///  4. [backend] from cached screen metadata
  ///  5. [local], when there is no backend value at all
  static PlaybackResumeResolution resolve({
    bool restartFromBeginning = false,
    Duration? requestedPosition,
    LocalResumeProgress? local,
    BackendResumeProgress? backend,
  }) {
    if (restartFromBeginning) {
      return const PlaybackResumeResolution(Duration.zero, PlaybackResumeSource.restart);
    }
    if (requestedPosition != null) {
      return PlaybackResumeResolution(requestedPosition, PlaybackResumeSource.requested);
    }

    if (local != null && backend != null && _localIsDemonstrablyNewer(local, backend)) {
      return PlaybackResumeResolution(local.position, PlaybackResumeSource.localNewer);
    }

    if (backend != null && backend.isFresh) {
      return PlaybackResumeResolution(backend.position, PlaybackResumeSource.freshBackend);
    }

    if (backend != null) {
      return PlaybackResumeResolution(backend.position, PlaybackResumeSource.cachedMetadata);
    }

    if (local != null) {
      return PlaybackResumeResolution(local.position, PlaybackResumeSource.localFallback);
    }

    return const PlaybackResumeResolution(null, PlaybackResumeSource.none);
  }

  /// Whether [local] can be *proven* newer than [backend].
  ///
  /// Two asymmetries are deliberate. Without a backend timestamp nothing can be
  /// proven, so a freshly fetched server value keeps precedence and only a
  /// stale cached one yields, and then only to a deliberate user action. And
  /// beating a fresh server value always requires such an action: a passive
  /// tracker write that merely happens to carry a later wall clock is exactly
  /// the "two players, one paused" case this whole phase is about.
  static bool _localIsDemonstrablyNewer(LocalResumeProgress local, BackendResumeProgress backend) {
    final backendUpdatedAt = backend.updatedAt;
    if (backendUpdatedAt == null) {
      return !backend.isFresh && _isDeliberate(local);
    }
    if (!local.updatedAt.isAfter(backendUpdatedAt)) return false;
    return !backend.isFresh || _isDeliberate(local);
  }

  /// A record only counts as a deliberate user action when intent *and* origin
  /// say so. Requiring both keeps a mislabelled offline-playback write, which
  /// is passive by nature, from being promoted into an override.
  static bool _isDeliberate(LocalResumeProgress local) =>
      local.intent == PlaybackResumeIntent.explicit && local.origin == PlaybackResumeOrigin.userAction;
}
