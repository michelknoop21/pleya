import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;

import '../../database/app_database.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_role.dart';
import '../../profiles/profile_connection.dart';
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

/// Jellyfin marks an item played from 90 percent on (its own default), so a
/// resumable item stays partial up to there, not up to [kCompletedPercent].
const int kJellyfinPlayedPercent = 90;

/// Shortest gap between two syncs of one profile and server. A history page
/// carries `People`, which is heavy; a play in Pleya is recorded locally at
/// once, so the import only has to catch up on plays elsewhere.
const Duration kJellyfinSyncInterval = Duration(minutes: 15);

/// One importer per Jellyfin login that is this profile's own.
///
/// Fails closed (DEC-062, DEC-132): a connection that more than one profile
/// uses is borrowed, so its Jellyfin user is not this profile's and it imports
/// nothing, for the borrower and the lender alike: that Jellyfin user carries
/// both profiles' plays. [whenBound] is awaited first, so a Home load that
/// starts while the binder is still switching servers imports once binding
/// settles instead of skipping; nothing is built while [isCurrentProfile] is
/// false after that.
Future<List<JellyfinHistoryImporter>> ownJellyfinHistoryImporters({
  required AppDatabase database,
  required String profileId,
  required Future<List<ProfileConnection>> Function(String profileId) connectionsForProfile,
  required Future<List<ProfileConnection>> Function(String connectionId) profilesForConnection,
  required JellyfinHistorySource? Function(String connectionId) onlineSource,
  required bool Function() isCurrentProfile,
  Future<void> Function()? whenBound,
}) async {
  if (profileId.isEmpty) return const [];
  await whenBound?.call();
  if (!isCurrentProfile()) return const [];
  final importers = <JellyfinHistoryImporter>[];
  for (final pc in await connectionsForProfile(profileId)) {
    final source = onlineSource(pc.connectionId);
    if (source == null) continue;
    if (await _isShared(pc.connectionId, profileId, profilesForConnection)) continue;
    importers.add(
      JellyfinHistoryImporter(
        database: database,
        profileId: profileId,
        source: source,
        isCurrentProfile: isCurrentProfile,
      ),
    );
  }
  return importers;
}

/// Servers of this profile's Jellyfin connections that another profile also
/// uses. Their server-side history ("recently watched") carries both
/// profiles' plays, so the seed rows may not read it, for the lender and the
/// borrower alike: the same rule as [ownJellyfinHistoryImporters].
/// [jellyfinServerId] answers null for a connection that is not Jellyfin.
Future<Set<String>> sharedJellyfinServerIds({
  required String profileId,
  required Future<List<ProfileConnection>> Function(String profileId) connectionsForProfile,
  required Future<List<ProfileConnection>> Function(String connectionId) profilesForConnection,
  required ServerId? Function(String connectionId) jellyfinServerId,
}) async {
  final shared = <String>{};
  for (final pc in await connectionsForProfile(profileId)) {
    final serverId = jellyfinServerId(pc.connectionId);
    if (serverId == null) continue;
    if (await _isShared(pc.connectionId, profileId, profilesForConnection)) shared.add(serverId.toString());
  }
  return shared;
}

Future<bool> _isShared(
  String connectionId,
  String profileId,
  Future<List<ProfileConnection>> Function(String connectionId) profilesForConnection,
) async => (await profilesForConnection(connectionId)).any((row) => row.profileId != profileId);

/// Imports one Jellyfin user's own history into [MediaInteractions].
///
/// No admin credential and no binding: [ownJellyfinHistoryImporters] only
/// hands in the profile's own login, so every row is the profile's and no
/// other user on the server is ever asked for (DEC-062). A played item becomes
/// `completed`, a resumable one between [kPartialPercent] and
/// [kJellyfinPlayedPercent] becomes `partial` once per stop (its event id
/// carries the stop time, not the position).
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
      // A lastSyncAt in the future means the clock was set back; treat it as
      // stale rather than holding the import until the clock catches up.
      final last = cursor?.lastSyncAt;
      final sinceLast = last == null ? null : _nowMs() - last;
      if (sinceLast != null && sinceLast >= 0 && sinceLast < kJellyfinSyncInterval.inMilliseconds) {
        return const TautulliImportOutcome();
      }
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

      // Offset paging on DatePlayed shifts when a play lands mid-sync, so the
      // same event can arrive twice; the set keeps the counts honest.
      final seen = <String>{};
      final candidates = <_Candidate>[
        for (final item in played)
          if (item.lastViewedAt case final at?)
            if (seen.add('$_kSource:$_serverId:${item.id}:$at'))
              _Candidate(
                item: item,
                type: 'completed',
                weight: 1.0,
                atMs: at * 1000,
                eventId: '$_kSource:$_serverId:${item.id}:$at',
              ),
        // A resumable item without a play time is left out: stamping it with
        // now would move it on every sync and slip past the cross-source
        // window. The stop time is in the event id, so a rewatch that stops
        // partway again is a new row, while one stop resumed and re-read over
        // several syncs stays one.
        for (final item in resumable)
          if (_partialPercent(item) case final percent?
              when percent >= kPartialPercent && percent < kJellyfinPlayedPercent)
            if (item.lastViewedAt case final at?)
              if (seen.add('$_kSource:$_serverId:${item.id}:resume:$at'))
                _Candidate(
                  item: item,
                  type: 'partial',
                  weight: kPartialWeight,
                  // The moment of the stop, so the cross-source window meets
                  // the local partial that the recorder wrote at that stop.
                  atMs: at * 1000,
                  eventId: '$_kSource:$_serverId:${item.id}:resume:$at',
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

      // Episodes resolve their series once, so a binge is one lookup. A series
      // the server no longer knows, or whose lookup fails, maps to null: its
      // rows are unresolvable, never stored with the episode's empty features,
      // and one bad series does not fail the whole sync.
      final features = <String, MediaItem?>{};
      for (final c in fresh) {
        final key = c.featureItemId;
        if (features.containsKey(key)) continue;
        features[key] = key == c.item.id ? c.item : await _source.fetchItem(key).catchError((Object _) => null);
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
      var unresolvable = 0;
      final rows = <MediaInteractionsCompanion>[];
      for (final c in fresh) {
        final f = features[c.featureItemId];
        if (f == null) {
          unresolvable++;
          continue;
        }
        final nearby = localPlays[buildGlobalKey(serverId, c.item.id)];
        if (nearby != null && nearby.any((l) => (l.at - c.atMs).abs() <= windowMs && l.weight >= c.weight)) {
          deduplicated++;
          continue;
        }
        final globalKey = buildGlobalKey(serverId, c.featureItemId);
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
      if (!stillOurs()) return null;
      await _saveCursor(newest);
      return TautulliImportOutcome(
        fetched: candidates.length,
        imported: rows.length,
        deduplicated: deduplicated,
        unresolvable: unresolvable,
      );
    } catch (e, s) {
      appLogger.w('JellyfinHistoryImporter: sync failed', error: e, stackTrace: s);
      // A failed sync still counts for the throttle, or every Home load would
      // retry against a server that is already struggling. The watermark
      // stays, so the retry after the interval reads the same plays again.
      try {
        if (stillOurs()) await _saveCursor(null);
      } catch (e, s) {
        appLogger.w('JellyfinHistoryImporter: could not record the failed sync', error: e, stackTrace: s);
      }
      return const TautulliImportOutcome(partial: true);
    }
  }

  /// Null leaves the watermark as it is and only stamps [lastSyncAt].
  Future<void> _saveCursor(int? watermarkMs) => _db.upsertHistorySyncCursor(
    HistorySyncCursorsCompanion.insert(
      profileId: _profileId,
      serverId: _serverId,
      source: _kSource,
      forwardCursorAt: watermarkMs == null ? const Value.absent() : Value(watermarkMs),
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
