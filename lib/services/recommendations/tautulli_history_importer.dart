import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../database/app_database.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_role.dart';
import '../../media/media_server_client.dart';
import '../../models/tautulli/tautulli_models.dart';
import '../../utils/app_logger.dart';
import '../../utils/global_key_utils.dart';
import '../tautulli/tautulli_import_access.dart';
import 'tautulli_import_binding.dart';

/// Rows per API page. Tautulli serves these comfortably and it keeps the
/// bundled dedup lookup to a sane `IN (…)` list.
const int kImportPageLength = 200;

/// Page budget per pass. Forward and the first pass may spend more than a
/// follow-up backfill, which only has to make steady progress.
const int kForwardMaxPages = 25;
const int kInitialMaxPages = 25;
const int kBackfillMaxPages = 10;

/// Days of overlap on a forward pass. `after` is day-granular and the device
/// may sit in a different timezone than the Tautulli host, so a record that
/// lands on an already-passed day would otherwise be missed. Overlap is free:
/// `sourceEventId` deduplicates it away.
const int kOverlapDays = 2;

/// Metadata lookups in flight at once.
const int kResolveConcurrency = 4;

/// A completed Tautulli view is suppressed only by a positive local playback
/// interaction this close to it.
const Duration kCrossSourceWindow = Duration(hours: 6);

/// Percentages that decide the signal.
const int kCompletedPercent = 85;
const int kPartialPercent = 50;

/// Backfill resumes once retention has aged the profile back below this
/// fraction of the cap. The gap keeps it from flapping on the boundary.
const double kBackfillResumeFraction = 0.9;

/// Consecutive truncated forward passes before the window is abandoned with a
/// loud log line rather than retried forever.
const int kForwardTruncationLimit = 3;

/// Cursor states. Only [exhausted] is final.
const String kBackfillPending = 'pending';
const String kBackfillExhausted = 'exhausted';
const String kBackfillRetentionCap = 'retentionCap';

const String _kSource = kInteractionSourceTautulli;

/// What one sync did, for logging and for deciding whether to rebuild rows.
class TautulliImportOutcome {
  final int fetched;
  final int imported;
  final int deduplicated;
  final int skipped;
  final int unresolvable;
  final bool partial;

  const TautulliImportOutcome({
    this.fetched = 0,
    this.imported = 0,
    this.deduplicated = 0,
    this.skipped = 0,
    this.unresolvable = 0,
    this.partial = false,
  });

  bool get changedAnything => imported > 0;

  TautulliImportOutcome merge(TautulliImportOutcome other) => TautulliImportOutcome(
    fetched: fetched + other.fetched,
    imported: imported + other.imported,
    deduplicated: deduplicated + other.deduplicated,
    skipped: skipped + other.skipped,
    unresolvable: unresolvable + other.unresolvable,
    partial: partial || other.partial,
  );

  @override
  String toString() =>
      'fetched=$fetched imported=$imported deduped=$deduplicated '
      'skipped=$skipped unresolvable=$unresolvable partial=$partial';
}

/// Pulls one profile's own Tautulli history into [MediaInteractions].
///
/// Everything about this is bounded and resumable. Passes have a page budget, a
/// watermark only advances over records that were actually processed, and the
/// backfill window's upper bound is frozen at the start so a calendar day
/// larger than one pass cannot re-anchor the cursor and stall.
class TautulliHistoryImporter {
  final AppDatabase _db;
  final TautulliImportAccess _access;
  final TautulliImportTarget _target;
  final MediaServerClient _client;
  final bool Function() _isCurrentProfile;
  final int Function() _nowMs;

  /// Page budgets. Overridable so tests can drive truncation, resumption and
  /// the frozen-window offset without fabricating five thousand fixtures.
  final int _pageLength;
  final int _initialMaxPages;
  final int _forwardMaxPages;
  final int _backfillMaxPages;

  /// Rows this profile may keep. Same reason: a test can reach the cap without
  /// building a real one.
  final int _profileCap;

  /// One in-flight sync per (profile, server). Static because the service is
  /// rebuilt with the provider tree, so a per-instance lock would not see the
  /// sync a previous instance still has running.
  static final Set<String> _inFlight = {};

  /// Per-sync metadata cache. An episode resolves its *show*, so a binge of
  /// twenty costs exactly one lookup.
  final Map<String, MediaItem?> _itemCache = {};

  TautulliHistoryImporter({
    required AppDatabase database,
    required this._access,
    required this._target,
    required this._client,
    required this._isCurrentProfile,
    int Function()? clock,
    this._pageLength = kImportPageLength,
    this._initialMaxPages = kInitialMaxPages,
    this._forwardMaxPages = kForwardMaxPages,
    this._backfillMaxPages = kBackfillMaxPages,
    this._profileCap = kProfileInteractionCap,
  }) : _db = database,
       _nowMs = clock ?? _systemClock;

  static int _systemClock() => DateTime.now().millisecondsSinceEpoch;

  String get _lockKey => '${_target.activeProfileId}|${_target.serverId}';

  /// Runs a forward pass and, when there is still room and older history to
  /// get, one bounded backfill pass. Returns null when another sync for the
  /// same profile and server is already running.
  Future<TautulliImportOutcome?> sync() async {
    if (!_inFlight.add(_lockKey)) {
      appLogger.d('TautulliHistoryImporter: sync already running for this profile and server');
      return null;
    }
    final epoch = AppDatabase.recommendationEpoch(_target.activeProfileId);
    final shortProfile = _shortHash(_target.activeProfileId);
    final shortServer = _shortIdentifier(_target.machineIdentifier);
    try {
      appLogger.i('TautulliHistoryImporter: sync started profile=$shortProfile server=$shortServer');
      var cursor = await _loadCursor();
      var outcome = const TautulliImportOutcome();

      final forward = await _runForward(cursor, epoch);
      outcome = outcome.merge(forward.outcome);
      cursor = forward.cursor;

      if (!forward.aborted) {
        final backfill = await _runBackfill(cursor, epoch);
        outcome = outcome.merge(backfill.outcome);
        cursor = backfill.cursor;
      }

      appLogger.i(
        'TautulliHistoryImporter: sync finished profile=$shortProfile server=$shortServer '
        'backfill=${cursor.backfillState} $outcome',
      );
      return outcome;
    } catch (e, s) {
      appLogger.w('TautulliHistoryImporter: sync failed (${_errorCategory(e)})', stackTrace: s);
      return const TautulliImportOutcome(partial: true);
    } finally {
      _inFlight.remove(_lockKey);
    }
  }

  // --- passes --------------------------------------------------------------

  Future<({_Cursor cursor, TautulliImportOutcome outcome, bool aborted})> _runForward(_Cursor cursor, int epoch) async {
    final firstRun = cursor.forwardCursorAt == 0;
    final floorMs = _nowMs() - const Duration(days: kInteractionRetentionDays).inMilliseconds;
    // Never ask for anything the retention window would throw away anyway.
    final overlapFrom = cursor.forwardCursorAt - kOverlapDays * Duration.millisecondsPerDay;
    final after = _day(firstRun ? floorMs : (overlapFrom < floorMs ? floorMs : overlapFrom));

    // A first run walks backwards into unknown territory, so it must respect
    // the retention cap. A follow-up forward pass only ever adds records newer
    // than everything stored, which the cap can never make pointless.
    final pass = await _drain(
      after: after,
      before: null,
      startOffset: 0,
      maxPages: firstRun ? _initialMaxPages : _forwardMaxPages,
      stopAtRetentionCap: firstRun,
      epoch: epoch,
    );
    if (pass.aborted) return (cursor: cursor, outcome: pass.outcome, aborted: true);

    var next = cursor;
    if (pass.newestAt != null) {
      if (pass.truncated && !firstRun) {
        // Records between the old watermark and the oldest one processed were
        // not seen, so the watermark must not jump over them.
        final tries = cursor.forwardTruncationCount + 1;
        if (tries < kForwardTruncationLimit) {
          appLogger.w('TautulliHistoryImporter: forward pass truncated (attempt $tries), watermark held');
          next = cursor.copyWith(forwardTruncationCount: tries);
        } else {
          appLogger.w(
            'TautulliHistoryImporter: forward pass truncated $tries times, skipping the range '
            '${_day(cursor.forwardCursorAt)}..${_day(pass.oldestAt ?? cursor.forwardCursorAt)} to keep syncing',
          );
          next = cursor.copyWith(
            forwardCursorAt: pass.newestAt,
            forwardLastRowId: pass.newestRowId,
            forwardTruncationCount: 0,
          );
        }
      } else {
        next = cursor.copyWith(
          forwardCursorAt: pass.newestAt,
          forwardLastRowId: pass.newestRowId,
          forwardTruncationCount: 0,
        );
      }
    }

    if (firstRun) {
      // Freeze the backfill window right here: everything above pass.oldestAt
      // is done, so the remaining work is one stable window below it.
      if (pass.exhausted) {
        next = next.copyWith(backfillState: kBackfillExhausted);
      } else {
        next = next.copyWith(
          backfillBeforeDay: _day(pass.oldestAt ?? _nowMs()),
          backfillOffset: 0,
          backfillCursorAt: pass.oldestAt,
          backfillState: pass.stoppedAtCap ? kBackfillRetentionCap : kBackfillPending,
        );
      }
    }

    await _saveCursor(next, epoch);
    return (cursor: next, outcome: pass.outcome, aborted: false);
  }

  Future<({_Cursor cursor, TautulliImportOutcome outcome})> _runBackfill(_Cursor cursor, int epoch) async {
    if (cursor.backfillState == kBackfillExhausted) {
      return (cursor: cursor, outcome: const TautulliImportOutcome());
    }
    final beforeDay = cursor.backfillBeforeDay;
    if (beforeDay == null) return (cursor: cursor, outcome: const TautulliImportOutcome());

    // Two separate stop conditions, both about there being no room. A profile
    // that is already at the cap must not spend even one page: backfill walks
    // towards older records, and the prune keeps the newest, so every row it
    // could fetch here would be deleted by the same call that stored it.
    final stored = await _db.countMediaInteractions(_target.activeProfileId);
    if (stored >= _profileCap) {
      final capped = cursor.copyWith(backfillState: kBackfillRetentionCap);
      if (capped.backfillState != cursor.backfillState) await _saveCursor(capped, epoch);
      return (cursor: capped, outcome: const TautulliImportOutcome());
    }
    // Hysteresis on the way back: only resume once retention has actually made
    // room, so a profile hovering on the boundary does not flap.
    if (cursor.backfillState == kBackfillRetentionCap && stored >= _profileCap * kBackfillResumeFraction) {
      return (cursor: cursor, outcome: const TautulliImportOutcome());
    }

    final floorMs = _nowMs() - const Duration(days: kInteractionRetentionDays).inMilliseconds;
    final afterDay = _day(floorMs);
    if (afterDay.compareTo(beforeDay) > 0) {
      // The rolling 365-day floor has climbed past the frozen upper bound, so
      // the window is empty for good.
      final done = cursor.copyWith(backfillState: kBackfillExhausted);
      await _saveCursor(done, epoch);
      return (cursor: done, outcome: const TautulliImportOutcome());
    }

    final pass = await _drain(
      after: afterDay,
      before: beforeDay,
      startOffset: cursor.backfillOffset,
      maxPages: _backfillMaxPages,
      stopAtRetentionCap: true,
      epoch: epoch,
    );
    if (pass.aborted) return (cursor: cursor, outcome: pass.outcome);

    // The offset is the only cursor inside this window, and the window's upper
    // bound never moves, so a calendar day bigger than one pass simply spans
    // several passes instead of re-anchoring on itself.
    final next = cursor.copyWith(
      backfillOffset: cursor.backfillOffset + pass.rowsSeen,
      backfillCursorAt: pass.oldestAt ?? cursor.backfillCursorAt,
      backfillState: pass.exhausted
          ? kBackfillExhausted
          : (pass.stoppedAtCap ? kBackfillRetentionCap : kBackfillPending),
    );
    await _saveCursor(next, epoch);
    return (cursor: next, outcome: pass.outcome);
  }

  // --- one bounded window --------------------------------------------------

  Future<_PassResult> _drain({
    required String after,
    required String? before,
    required int startOffset,
    required int maxPages,
    required bool stopAtRetentionCap,
    required int epoch,
  }) async {
    var outcome = const TautulliImportOutcome();
    var rowsSeen = 0;
    int? newestAt;
    int? newestRowId;
    int? oldestAt;
    var exhausted = false;
    var stoppedAtCap = false;

    for (var page = 0; page < maxPages; page++) {
      if (!_stillOurs(epoch)) {
        return _PassResult(outcome: outcome, aborted: true, rowsSeen: rowsSeen);
      }
      final result = await _access.fetchImportHistory(
        _target.serverId,
        userId: _target.userId,
        length: _pageLength,
        start: startOffset + rowsSeen,
        after: after,
        before: before,
      );
      if (result == null) {
        // The integration went away or was switched off mid-sync.
        return _PassResult(
          outcome: outcome.merge(const TautulliImportOutcome(partial: true)),
          aborted: true,
          rowsSeen: rowsSeen,
        );
      }

      final entries = result.entries;
      if (entries.isEmpty) {
        exhausted = true;
        break;
      }
      rowsSeen += entries.length;
      outcome = outcome.merge(TautulliImportOutcome(fetched: entries.length));

      for (final e in entries) {
        final at = e.date;
        if (at == null) continue;
        final atMs = at * 1000;
        if (newestAt == null || atMs > newestAt) {
          newestAt = atMs;
          newestRowId = e.rowId;
        }
        if (oldestAt == null || atMs < oldestAt) oldestAt = atMs;
      }

      final pageOutcome = await _ingestPage(entries, epoch);
      if (pageOutcome == null) {
        return _PassResult(outcome: outcome, aborted: true, rowsSeen: rowsSeen);
      }
      outcome = outcome.merge(pageOutcome);

      if (entries.length < _pageLength) {
        exhausted = true;
        break;
      }
      if (stopAtRetentionCap) {
        final stored = await _db.countMediaInteractions(_target.activeProfileId);
        if (stored >= _profileCap) {
          stoppedAtCap = true;
          break;
        }
      }
    }

    return _PassResult(
      outcome: outcome,
      rowsSeen: rowsSeen,
      newestAt: newestAt,
      newestRowId: newestRowId,
      oldestAt: oldestAt,
      exhausted: exhausted,
      stoppedAtCap: stoppedAtCap,
      truncated: !exhausted && !stoppedAtCap,
    );
  }

  /// Turns one page into rows. Returns null when the write must not happen.
  Future<TautulliImportOutcome?> _ingestPage(List<TautulliHistoryEntry> entries, int epoch) async {
    var skipped = 0;
    var unresolvable = 0;

    // Accept only what is provably this user's, on this server.
    final usable = <TautulliHistoryEntry>[];
    for (final e in entries) {
      if (e.userId != _target.userId) {
        skipped++;
        continue;
      }
      final reported = e.machineId?.trim() ?? '';
      // Older Tautulli builds omit machine_id, so absence is not a rejection;
      // a value that disagrees is.
      if (reported.isNotEmpty && reported != _target.machineIdentifier) {
        skipped++;
        continue;
      }
      if (e.date == null) {
        skipped++;
        continue;
      }
      if (_signalFor(e) == null) {
        skipped++;
        continue;
      }
      final key = _catalogueKeyFor(e);
      if (key == null) {
        skipped++;
        continue;
      }
      usable.add(e);
    }
    if (usable.isEmpty) {
      return TautulliImportOutcome(skipped: skipped);
    }

    // Which of these we already have. `insertOrIgnore` plus the partial unique
    // index would drop them anyway, but counting them as imported would make
    // every overlapping forward pass look like new data and trigger a pointless
    // rebuild. Asking first is also what keeps the two-day overlap cheap: these
    // rows never reach the metadata lookup below.
    final alreadyImported = await _db.existingImportedEventIds(_target.activeProfileId, {
      for (final e in usable) _sourceEventIdFor(e),
    });
    var deduplicated = alreadyImported.length;
    final fresh = [
      for (final e in usable)
        if (!alreadyImported.contains(_sourceEventIdFor(e))) e,
    ];
    if (fresh.isEmpty) {
      return TautulliImportOutcome(deduplicated: deduplicated, skipped: skipped);
    }

    // Resolve distinct catalogue keys with bounded concurrency. Episodes
    // resolve their show, so a whole season is one lookup.
    await _resolveAll({for (final e in fresh) _catalogueKeyFor(e)!});
    if (!_stillOurs(epoch)) return null;

    // One bundled lookup for the cross-source window instead of one per row.
    final candidates = <String>{};
    var minAt = 1 << 62;
    var maxAt = 0;
    for (final e in fresh) {
      if (_itemCache[_catalogueKeyFor(e)!] == null) continue;
      final atMs = e.date! * 1000;
      candidates.add(_globalKeyFor(e));
      if (atMs < minAt) minAt = atMs;
      if (atMs > maxAt) maxAt = atMs;
    }
    final windowMs = kCrossSourceWindow.inMilliseconds;
    final localPlays = candidates.isEmpty
        ? const <String, List<int>>{}
        : await _db.localPositiveInteractionsIn(
            _target.activeProfileId,
            candidates,
            minAt - windowMs,
            maxAt + windowMs,
          );

    final rows = <MediaInteractionsCompanion>[];
    for (final e in fresh) {
      final item = _itemCache[_catalogueKeyFor(e)!];
      if (item == null) {
        unresolvable++;
        continue;
      }
      final globalKey = _globalKeyFor(e);
      final atMs = e.date! * 1000;
      final nearbyLocal = localPlays[globalKey];
      if (nearbyLocal != null && nearbyLocal.any((t) => (t - atMs).abs() <= windowMs)) {
        // Pleya already recorded this same view. A rewatch days later falls
        // outside the window and is kept.
        deduplicated++;
        continue;
      }
      rows.add(_companionFor(e, item, globalKey));
    }

    if (rows.isNotEmpty) {
      if (!_stillOurs(epoch)) return null;
      await _db.insertImportedInteractions(rows, profileId: _target.activeProfileId);
    }
    return TautulliImportOutcome(
      imported: rows.length,
      deduplicated: deduplicated,
      skipped: skipped,
      unresolvable: unresolvable,
    );
  }

  MediaInteractionsCompanion _companionFor(TautulliHistoryEntry e, MediaItem item, String globalKey) {
    final signal = _signalFor(e)!;
    final isEpisode = e.mediaType == 'episode';
    final seriesKey = isEpisode ? globalKey : null;
    return MediaInteractionsCompanion.insert(
      profileId: _target.activeProfileId,
      globalKey: globalKey,
      mediaKind: isEpisode ? MediaKind.episode.name : MediaKind.movie.name,
      eventType: signal.type,
      eventWeight: signal.weight,
      occurredAt: e.date! * 1000,
      genresJson: Value(jsonEncode(item.genres ?? const <String>[])),
      actorsJson: Value(jsonEncode([for (final r in item.roles?.take(5) ?? const <MediaRole>[]) r.tag])),
      directorsJson: Value(jsonEncode(item.directors ?? const <String>[])),
      moodsJson: Value(jsonEncode(item.moods ?? const <String>[])),
      studio: Value(item.studio),
      year: Value(item.year),
      communityRating: Value(item.rating),
      seriesKey: Value(seriesKey),
      source: const Value(_kSource),
      sourceEventId: Value(_sourceEventIdFor(e)),
      sourceServerId: Value(_target.machineIdentifier),
      completionPercent: Value(e.percentComplete),
      playSeconds: Value(e.playSeconds),
    );
  }

  // --- helpers -------------------------------------------------------------

  /// The rating key whose metadata describes this row's taste: the movie
  /// itself, or an episode's *show*. Never the episode, so a binge resolves
  /// once and taste reflects the series.
  String? _catalogueKeyFor(TautulliHistoryEntry e) {
    switch (e.mediaType) {
      case 'movie':
        return e.ratingKey?.toString();
      case 'episode':
        return e.grandparentRatingKey?.toString();
      default:
        return null; // clip, track, live: no taste signal worth storing.
    }
  }

  /// Stable external identity of one Tautulli record. Ungrouped history keeps
  /// `row_id` stable, which is what makes a re-import a no-op.
  String _sourceEventIdFor(TautulliHistoryEntry e) => '$_kSource:${_target.machineIdentifier}:${e.rowId}';

  /// The stored identity of the row. An episode is stored under its series, so
  /// it shares an evidence key with the rest of the binge.
  String _globalKeyFor(TautulliHistoryEntry e) => buildGlobalKey(_target.serverId, _catalogueKeyFor(e)!);

  ({String type, double weight})? _signalFor(TautulliHistoryEntry e) {
    // watched_status is Tautulli's own verdict against the admin's configured
    // threshold, which can sit below 85 percent, so it is checked first and the
    // percentage is a second chance rather than the only rule.
    if (e.watchedStatus >= 1 || e.percentComplete >= kCompletedPercent) {
      return (type: 'completed', weight: 1.0);
    }
    if (e.percentComplete >= kPartialPercent) return (type: 'partial', weight: 0.4);
    // An abandoned play is not a dislike. Imported history never turns
    // negative; only an explicit action in Pleya does.
    return null;
  }

  Future<void> _resolveAll(Set<String> keys) async {
    final pending = keys.where((k) => !_itemCache.containsKey(k)).toList();
    for (var i = 0; i < pending.length; i += kResolveConcurrency) {
      final slice = pending.skip(i).take(kResolveConcurrency);
      await Future.wait([
        for (final key in slice)
          _client.fetchItem(key).then((item) => _itemCache[key] = item).catchError((Object e) {
            // A deleted or unreadable item costs one row, never the sync.
            _itemCache[key] = null;
            return null;
          }),
      ]);
    }
  }

  /// Both guards, checked immediately before every write.
  ///
  /// The profile check catches a switch; the epoch catches a deletion, which
  /// wipes recommendation data while the profile is *still* active and so would
  /// pass the first check. Dart is single-threaded per isolate, so the only
  /// interleave points are awaits and this sits directly before the write. That
  /// narrows the window to the practical minimum; it is not a transaction
  /// spanning both operations.
  bool _stillOurs(int epoch) =>
      _isCurrentProfile() && AppDatabase.recommendationEpoch(_target.activeProfileId) == epoch;

  Future<_Cursor> _loadCursor() async {
    final row = await _db.getHistorySyncCursor(_target.activeProfileId, _target.machineIdentifier, _kSource);
    return _Cursor.fromRow(row);
  }

  Future<void> _saveCursor(_Cursor cursor, int epoch) async {
    if (!_stillOurs(epoch)) return;
    await _db.upsertHistorySyncCursor(
      HistorySyncCursorsCompanion.insert(
        profileId: _target.activeProfileId,
        serverId: _target.machineIdentifier,
        source: _kSource,
        forwardCursorAt: Value(cursor.forwardCursorAt),
        forwardLastRowId: Value(cursor.forwardLastRowId),
        backfillBeforeDay: Value(cursor.backfillBeforeDay),
        backfillOffset: Value(cursor.backfillOffset),
        backfillCursorAt: Value(cursor.backfillCursorAt),
        backfillState: Value(cursor.backfillState),
        forwardTruncationCount: Value(cursor.forwardTruncationCount),
        lastSyncAt: Value(_nowMs()),
      ),
    );
  }

  static String _day(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs).toUtc();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String _shortHash(String value) => value.hashCode.toRadixString(16).padLeft(8, '0').substring(0, 8);

  static String _shortIdentifier(String value) => value.length <= 6 ? value : '${value.substring(0, 6)}…';

  static String _errorCategory(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('apikey') || text.contains('unauthorized') || text.contains('forbidden')) return 'isAuth';
    if (text.contains('socket') || text.contains('timeout') || text.contains('connection')) return 'isNetwork';
    return 'isMalformed';
  }
}

class _PassResult {
  final TautulliImportOutcome outcome;
  final bool aborted;
  final int rowsSeen;
  final int? newestAt;
  final int? newestRowId;
  final int? oldestAt;
  final bool exhausted;
  final bool stoppedAtCap;
  final bool truncated;

  const _PassResult({
    required this.outcome,
    this.aborted = false,
    this.rowsSeen = 0,
    this.newestAt,
    this.newestRowId,
    this.oldestAt,
    this.exhausted = false,
    this.stoppedAtCap = false,
    this.truncated = false,
  });
}

class _Cursor {
  final int forwardCursorAt;
  final int? forwardLastRowId;
  final String? backfillBeforeDay;
  final int backfillOffset;
  final int? backfillCursorAt;
  final String backfillState;
  final int forwardTruncationCount;

  const _Cursor({
    this.forwardCursorAt = 0,
    this.forwardLastRowId,
    this.backfillBeforeDay,
    this.backfillOffset = 0,
    this.backfillCursorAt,
    this.backfillState = kBackfillPending,
    this.forwardTruncationCount = 0,
  });

  static _Cursor fromRow(HistorySyncCursorRow? row) {
    if (row == null) return const _Cursor();
    return _Cursor(
      forwardCursorAt: row.forwardCursorAt,
      forwardLastRowId: row.forwardLastRowId,
      backfillBeforeDay: row.backfillBeforeDay,
      backfillOffset: row.backfillOffset,
      backfillCursorAt: row.backfillCursorAt,
      backfillState: row.backfillState,
      forwardTruncationCount: row.forwardTruncationCount,
    );
  }

  _Cursor copyWith({
    int? forwardCursorAt,
    int? forwardLastRowId,
    String? backfillBeforeDay,
    int? backfillOffset,
    int? backfillCursorAt,
    String? backfillState,
    int? forwardTruncationCount,
  }) => _Cursor(
    forwardCursorAt: forwardCursorAt ?? this.forwardCursorAt,
    forwardLastRowId: forwardLastRowId ?? this.forwardLastRowId,
    backfillBeforeDay: backfillBeforeDay ?? this.backfillBeforeDay,
    backfillOffset: backfillOffset ?? this.backfillOffset,
    backfillCursorAt: backfillCursorAt ?? this.backfillCursorAt,
    backfillState: backfillState ?? this.backfillState,
    forwardTruncationCount: forwardTruncationCount ?? this.forwardTruncationCount,
  );
}
