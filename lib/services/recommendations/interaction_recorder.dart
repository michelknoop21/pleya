import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../database/app_database.dart';
import '../../media/ids.dart';
import '../../media/media_kind.dart';
import '../../media/media_role.dart';
import '../../media/media_server_client.dart';
import '../../utils/app_logger.dart';
import '../../utils/global_key_utils.dart';
import '../../utils/watch_state_notifier.dart';
import 'tautulli_history_importer.dart' show kCrossSourceWindow, kPartialPercent, kPartialWeight;

/// Records watch interactions into the local [MediaInteractions] store so the
/// on-device recommendation engine can learn taste. Subscribes to
/// [WatchStateNotifier] (same pattern as `TraktSyncService`), scoped to one
/// profile; dispose on profile switch. All data stays on-device.
///
/// Three signals are recorded: a finished item (weight +1.0), a
/// Continue-Watching dismissal (weight -0.3), and a partial view
/// ([kPartialWeight]) when a playback session ends between [kPartialPercent]
/// and the watched threshold, at most once per title per [kCrossSourceWindow].
/// An abandoned play below that percentage records nothing.
class InteractionRecorder {
  final AppDatabase _db;
  final String _profileId;
  final MediaServerClient? Function(ServerId serverId) _clientResolver;

  StreamSubscription<WatchStateEvent>? _sub;

  /// Per-session cache of resolved feature payloads keyed by global key, so a
  /// re-watch of the same item never re-fetches metadata.
  final Map<String, _Features> _featureCache = {};

  InteractionRecorder({required AppDatabase database, required this._profileId, required this._clientResolver})
    : _db = database;

  void start() {
    // No active profile → nothing to attribute interactions to; stay inert so
    // we never persist taste rows under an empty profile id.
    if (_profileId.isEmpty) return;
    _sub ??= WatchStateNotifier().stream.listen(
      _onEvent,
      onError: (Object e, StackTrace s) {
        appLogger.w('InteractionRecorder: stream error', error: e, stackTrace: s);
      },
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _featureCache.clear();
  }

  Future<void> _onEvent(WatchStateEvent event) async {
    try {
      final (String type, double weight)? mapped = switch (event.changeType) {
        WatchStateChangeType.watched => ('completed', 1.0),
        WatchStateChangeType.removedFromContinueWatching => ('skipped', -0.3),
        WatchStateChangeType.progressUpdate => await _partialSignal(event),
        WatchStateChangeType.unwatched => null,
      };
      if (mapped == null) return;

      final features = await _resolveFeatures(event);
      if (features == null) return; // couldn't enrich — skip rather than store a blank row

      await _db.insertMediaInteraction(
        MediaInteractionsCompanion.insert(
          profileId: _profileId,
          globalKey: event.globalKey,
          mediaKind: event.mediaType,
          eventType: mapped.$1,
          eventWeight: mapped.$2,
          occurredAt: DateTime.now().millisecondsSinceEpoch,
          genresJson: Value(jsonEncode(features.genres)),
          actorsJson: Value(jsonEncode(features.actors)),
          directorsJson: Value(jsonEncode(features.directors)),
          moodsJson: Value(jsonEncode(features.moods)),
          studio: Value(features.studio),
          year: Value(features.year),
          communityRating: Value(features.rating),
          seriesKey: Value(features.seriesKey),
        ),
        profileId: _profileId,
      );
    } catch (e, s) {
      appLogger.w('InteractionRecorder: failed to record interaction', error: e, stackTrace: s);
    }
  }

  /// A final stop between [kPartialPercent] and the client's watched threshold
  /// is evidence the title held attention. Below it nothing is recorded, as
  /// with the imported history (DEC-062). At or above the threshold the
  /// `watched` event carries the row, so nothing is written here either. One
  /// row per title per [kCrossSourceWindow], so pausing and resuming over an
  /// evening does not stack.
  Future<(String, double)?> _partialSignal(WatchStateEvent event) async {
    final duration = event.durationMs;
    final offset = event.viewOffset;
    if (!event.isFinal || duration == null || duration <= 0 || offset == null) return null;
    if (event.isNowWatched == true) return null;
    if (offset * 100 ~/ duration < kPartialPercent) return null;
    final since = DateTime.now().millisecondsSinceEpoch - kCrossSourceWindow.inMilliseconds;
    if (await _db.hasPositiveInteractionSince(_profileId, event.globalKey, since)) return null;
    return ('partial', kPartialWeight);
  }

  Future<_Features?> _resolveFeatures(WatchStateEvent event) async {
    final cached = _featureCache[event.globalKey];
    if (cached != null) return cached;

    final client = _clientResolver(event.serverId);
    if (client == null) return null;

    var item = await client.fetchItem(event.itemId);
    if (item == null) return null;

    // Every episode records its series key, because the scorer groups evidence
    // by it: twenty episodes of one show must saturate, not stack. Whether the
    // *show* is also fetched is a separate question, and only worth a round
    // trip when the episode itself carries no show-level genres/cast/crew.
    String? seriesKey;
    if (item.kind == MediaKind.episode) {
      final grandparentId = item.grandparentId;
      if (grandparentId != null) {
        final serverId = serverIdOrNull(item.serverId);
        seriesKey = serverId != null ? buildGlobalKey(serverId, grandparentId) : grandparentId;
        final episodeMetaSparse =
            (item.genres?.isEmpty ?? true) && (item.roles?.isEmpty ?? true) && (item.directors?.isEmpty ?? true);
        if (episodeMetaSparse) {
          final show = await client.fetchItem(grandparentId);
          if (show != null) item = show;
        }
      }
    }

    final features = _Features(
      genres: item.genres ?? const [],
      actors: [for (final r in item.roles?.take(5) ?? const <MediaRole>[]) r.tag],
      directors: item.directors ?? const [],
      moods: item.moods ?? const [],
      studio: item.studio,
      year: item.year,
      rating: item.rating,
      seriesKey: seriesKey,
    );
    _featureCache[event.globalKey] = features;
    return features;
  }
}

class _Features {
  final List<String> genres;
  final List<String> actors;
  final List<String> directors;
  final List<String> moods;
  final String? studio;
  final int? year;
  final double? rating;
  final String? seriesKey;

  const _Features({
    required this.genres,
    required this.actors,
    required this.directors,
    required this.moods,
    required this.studio,
    required this.year,
    required this.rating,
    required this.seriesKey,
  });
}
