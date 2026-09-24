import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;

import '../../database/app_database.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_role.dart';
import '../../utils/app_logger.dart';
import '../../utils/global_key_utils.dart';
import 'history_importer.dart';
import 'tautulli_history_importer.dart';

/// What the importer needs from a Jellyfin connection. The client implements
/// it; tests hand in a fake.
abstract interface class JellyfinHistorySource {
  ServerId get serverId;

  /// This user's played films and episodes, newest play first.
  Future<List<MediaItem>> fetchPlayedHistoryPage({required int startIndex, int limit});

  /// Titles this user stopped partway, with position and duration.
  Future<List<MediaItem>> fetchResumableItems({int limit});

  Future<MediaItem?> fetchItem(String id);
}

const String _kSource = kInteractionSourceJellyfin;
const int kJellyfinPageLength = 200;
const int kJellyfinResumeLimit = 100;

/// Imports one Jellyfin user's own history into [MediaInteractions].
///
/// No admin credential and no binding: the connection is the profile's own
/// login, so every row is the profile's and no other user on the server is
/// ever asked for (DEC-062). A played item becomes `completed`, a resumable
/// one between [kPartialPercent] and 90 percent becomes `partial` once (its
/// event id has no position in it, so a title that keeps being resumed stays
/// one row until it is finished).
///
/// ponytail: forward-only. The watermark is the newest `LastPlayedDate` seen;
/// every run reads at most `maxPagesFirstRun` pages. Anything older than that
/// is left out on purpose: the profile cap of 5000 rows would prune it anyway.
/// Add a backfill cursor like the Tautulli importer's if a real profile turns
/// out to need history beyond the first thousand plays.
class JellyfinHistoryImporter implements HistoryImporter {
  final AppDatabase _db;
  final String _profileId;
  final JellyfinHistorySource _source;
  final bool Function() _isCurrentProfile;
  final int Function() _nowMs;
  final int _maxPages;

  JellyfinHistoryImporter({
    required AppDatabase database,
    required this._profileId,
    required this._source,
    required this._isCurrentProfile,
    int Function()? clock,
    int maxPagesFirstRun = 5,
  }) : _db = database,
       _nowMs = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _maxPages = maxPagesFirstRun;

  String get _serverId => _source.serverId.toString();

  @override
  Future<TautulliImportOutcome?> sync() async {
    if (_profileId.isEmpty || !_isCurrentProfile()) return null;
    // The profile check catches a switch; the epoch catches a wipe of the
    // taste data while this profile stays active.
    final epoch = AppDatabase.recommendationEpoch(_profileId);
    bool stillOurs() => _isCurrentProfile() && AppDatabase.recommendationEpoch(_profileId) == epoch;
    try {
      final cursor = await _db.getHistorySyncCursor(_profileId, _serverId, _kSource);
      final watermarkMs = cursor?.forwardCursorAt ?? 0;

      final played = <MediaItem>[];
      var reachedWatermark = false;
      // A bounded read on every run, never a full crawl.
      for (var pages = 0; pages < _maxPages && !reachedWatermark; pages++) {
        final page = await _source.fetchPlayedHistoryPage(
          startIndex: pages * kJellyfinPageLength,
          limit: kJellyfinPageLength,
        );
        for (final item in page) {
          if ((item.lastViewedAt ?? 0) * 1000 <= watermarkMs) {
            reachedWatermark = true;
            break;
          }
          played.add(item);
        }
        if (page.length < kJellyfinPageLength) break;
      }
      final resumable = await _source.fetchResumableItems(limit: kJellyfinResumeLimit);

      final candidates = <_Candidate>[
        for (final item in played)
          if (item.lastViewedAt case final at?)
            _Candidate(
              item: item,
              type: 'completed',
              weight: 1.0,
              atMs: at * 1000,
              eventId: '$_kSource:$_serverId:${item.id}:$at',
            ),
        for (final item in resumable)
          if (_partialPercent(item) case final percent? when percent >= kPartialPercent && percent < 90)
            _Candidate(
              item: item,
              type: 'partial',
              weight: kPartialWeight,
              atMs: _nowMs(),
              eventId: '$_kSource:$_serverId:${item.id}:resume',
              completionPercent: percent,
            ),
      ];
      // The watermark covers every play seen, also the ones deduplicated below,
      // so a suppressed play is not asked for again on the next run.
      var newest = watermarkMs;
      for (final c in candidates) {
        if (c.type == 'completed' && c.atMs > newest) newest = c.atMs;
      }

      final existing = await _db.existingImportedEventIds(_profileId, {for (final c in candidates) c.eventId});
      final fresh = candidates.where((c) => !existing.contains(c.eventId)).toList();

      // Episodes resolve their series once, so a binge is one lookup.
      final features = <String, MediaItem>{};
      for (final c in fresh) {
        final key = c.featureItemId;
        if (features.containsKey(key)) continue;
        features[key] = key == c.item.id ? c.item : (await _source.fetchItem(key) ?? c.item);
      }

      // Keyed on the item itself, the key a local row carries for the same
      // play (the episode, not its series), as in the Tautulli importer.
      final serverId = _source.serverId;
      final windowMs = kCrossSourceWindow.inMilliseconds;
      final localPlays = fresh.isEmpty
          ? const <String, List<({int at, double weight})>>{}
          : await _db.localPositiveInteractionsIn(
              _profileId,
              {for (final c in fresh) buildGlobalKey(serverId, c.item.id)},
              fresh.map((c) => c.atMs).reduce(math.min) - windowMs,
              fresh.map((c) => c.atMs).reduce(math.max) + windowMs,
            );

      var deduplicated = 0;
      final rows = <MediaInteractionsCompanion>[];
      for (final c in fresh) {
        final nearby = localPlays[buildGlobalKey(serverId, c.item.id)];
        if (nearby != null && nearby.any((l) => (l.at - c.atMs).abs() <= windowMs && l.weight >= c.weight)) {
          deduplicated++;
          continue;
        }
        final globalKey = buildGlobalKey(serverId, c.featureItemId);
        final f = features[c.featureItemId]!;
        final isEpisode = c.item.kind == MediaKind.episode;
        rows.add(
          MediaInteractionsCompanion.insert(
            profileId: _profileId,
            globalKey: globalKey,
            mediaKind: isEpisode ? MediaKind.episode.name : MediaKind.movie.name,
            eventType: c.type,
            eventWeight: c.weight,
            occurredAt: c.atMs,
            genresJson: Value(jsonEncode(f.genres ?? const <String>[])),
            actorsJson: Value(jsonEncode([for (final r in f.roles?.take(5) ?? const <MediaRole>[]) r.tag])),
            directorsJson: Value(jsonEncode(f.directors ?? const <String>[])),
            moodsJson: Value(jsonEncode(f.moods ?? const <String>[])),
            studio: Value(f.studio),
            year: Value(f.year),
            communityRating: Value(f.rating),
            seriesKey: Value(isEpisode ? globalKey : null),
            source: const Value(_kSource),
            sourceEventId: Value(c.eventId),
            sourceServerId: Value(_serverId),
            completionPercent: Value(c.completionPercent),
          ),
        );
      }

      if (!stillOurs()) return null;
      if (rows.isNotEmpty) await _db.insertImportedInteractions(rows, profileId: _profileId);
      await _saveCursor(newest);
      return TautulliImportOutcome(fetched: candidates.length, imported: rows.length, deduplicated: deduplicated);
    } catch (e, s) {
      appLogger.w('JellyfinHistoryImporter: sync failed', error: e, stackTrace: s);
      return const TautulliImportOutcome(partial: true);
    }
  }

  Future<void> _saveCursor(int watermarkMs) => _db.upsertHistorySyncCursor(
    HistorySyncCursorsCompanion.insert(
      profileId: _profileId,
      serverId: _serverId,
      source: _kSource,
      forwardCursorAt: Value(watermarkMs),
      lastSyncAt: Value(_nowMs()),
    ),
  );

  static int? _partialPercent(MediaItem item) {
    final offset = item.viewOffsetMs;
    final duration = item.durationMs;
    if (offset == null || duration == null || duration <= 0) return null;
    return offset * 100 ~/ duration;
  }
}

class _Candidate {
  final MediaItem item;
  final String type;
  final double weight;
  final int atMs;
  final String eventId;
  final int? completionPercent;

  const _Candidate({
    required this.item,
    required this.type,
    required this.weight,
    required this.atMs,
    required this.eventId,
    this.completionPercent,
  });

  /// An episode is evidence about its series, like the Tautulli importer and
  /// the recorder: the series is what the scorer groups on.
  String get featureItemId => item.kind == MediaKind.episode ? (item.grandparentId ?? item.id) : item.id;
}
