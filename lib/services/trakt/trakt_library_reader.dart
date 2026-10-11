import 'dart:async';

import '../../models/trakt/trakt_title.dart';
import '../../utils/app_logger.dart';
import 'trakt_client.dart';

/// What the user has watched on Trakt: films and series, compact.
class TraktSeen {
  const TraktSeen({this.movies = const [], this.shows = const []});
  final List<TraktTitle> movies;
  final List<TraktTitle> shows;
}

class _Slot<T> {
  T? value;
  DateTime? at;
  DateTime? failedAt;
  Future<T?>? inFlight;
}

/// Reads the signed-in user's Trakt history and watchlist through the client
/// the sync service already holds, so no second client carries a copy of the
/// session and no rotated refresh token is reused.
///
/// Memory only: Trakt viewing history is never written to disk. A read that
/// fails keeps answering with the last good list for [staleFor] and is not
/// retried for [failureBackoff], so a slow or blocked Trakt costs one wait,
/// not one per tool call. Unavailable (no client, another profile, no good
/// list yet) is null, never an exception.
class TraktLibraryReader {
  TraktLibraryReader({
    required TraktClient? Function() clientOf,
    required String Function() userOf,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 5),
  }) : _clientOf = clientOf,
       _userOf = userOf,
       _now = now ?? DateTime.now;

  static const Duration ttl = Duration(minutes: 15);
  static const Duration staleFor = Duration(hours: 6);
  static const Duration failureBackoff = Duration(seconds: 90);

  final TraktClient? Function() _clientOf;
  final String Function() _userOf;
  final DateTime Function() _now;
  final Duration timeout;

  int _epoch = 0;
  final _seen = _Slot<TraktSeen>();
  final _watchlist = _Slot<List<TraktTitle>>();

  /// Forgets everything: a profile change, disconnect or the kids shield.
  void reset() {
    _epoch++;
    for (final slot in [_seen, _watchlist]) {
      slot
        ..value = null
        ..at = null
        ..failedAt = null
        ..inFlight = null;
    }
  }

  /// The watched films and series, or null when unavailable. [expectUser] is
  /// the profile the asking turn belongs to: a turn that outlives a profile
  /// switch gets nothing instead of the next profile's history.
  Future<TraktSeen?> seen({required String expectUser}) => _read(_seen, expectUser, () async {
    final client = _clientOf()!;
    final (movies, shows) = await (client.getWatched(shows: false), client.getWatched(shows: true)).wait;
    return TraktSeen(movies: movies, shows: shows);
  });

  /// The newest watchlist entries, up to [limit] films and [limit] series,
  /// newest first, or null.
  Future<List<TraktTitle>?> watchlist({required String expectUser, int limit = 50}) =>
      _read(_watchlist, expectUser, () async {
        final client = _clientOf()!;
        final (movies, shows) = await (
          client.getWatchlist(shows: false, limit: limit),
          client.getWatchlist(shows: true, limit: limit),
        ).wait;
        // Both kinds are kept (each up to [limit]) so a kind filter applied
        // afterwards still has its own newest entries.
        return [...movies, ...shows]..sort((a, b) => (b.at ?? '').compareTo(a.at ?? ''));
      });

  Future<T?> _read<T>(_Slot<T> slot, String expectUser, Future<T> Function() fetch) {
    if (_clientOf() == null || _userOf() != expectUser) return Future.value();
    final now = _now();
    final at = slot.at;
    if (slot.value != null && at != null && now.difference(at) < ttl) return Future.value(slot.value);
    final failedAt = slot.failedAt;
    if (failedAt != null && now.difference(failedAt) < failureBackoff) return Future.value(_stale(slot, now));
    final running = slot.inFlight;
    if (running != null) return _waitFor(slot, running);

    final epoch = _epoch;
    // The download is not tied to the wait: a list too big for [timeout] is
    // still kept when it arrives, so the next ask is served from the cache.
    final job = () async {
      try {
        final value = await fetch();
        if (epoch != _epoch) return null;
        slot
          ..value = value
          ..at = _now()
          ..failedAt = null;
        return value;
      } catch (e) {
        if (epoch != _epoch) return null;
        appLogger.w('Trakt: reading the library failed, using the last good list if any', error: e.runtimeType);
        slot.failedAt = _now();
        return _stale(slot, _now());
      } finally {
        if (epoch == _epoch) slot.inFlight = null;
      }
    }();
    slot.inFlight = job;
    return _waitFor(slot, job);
  }

  /// A caller waits at most [timeout]; on timeout it gets the last good list
  /// and is not sent to the same download again for [failureBackoff].
  Future<T?> _waitFor<T>(_Slot<T> slot, Future<T?> job) => job.timeout(
    timeout,
    onTimeout: () {
      slot.failedAt ??= _now();
      return _stale(slot, _now());
    },
  );

  T? _stale<T>(_Slot<T> slot, DateTime now) {
    final at = slot.at;
    return slot.value != null && at != null && now.difference(at) < staleFor ? slot.value : null;
  }
}
