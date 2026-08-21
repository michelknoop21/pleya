import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/models/tautulli/tautulli_models.dart';
import 'package:pleya/services/recommendations/tautulli_history_importer.dart';
import 'package:pleya/services/recommendations/tautulli_import_binding.dart';
import 'package:pleya/services/tautulli/tautulli_import_access.dart';

const _profile = 'profile-a';
const _machine = 'pms-1';
const _userId = 4725462;

final _now = DateTime.now().millisecondsSinceEpoch;
int _secondsAgo(int days) => (_now - days * Duration.millisecondsPerDay) ~/ 1000;

/// One recorded request, so the tests can assert on the *shape* of the calls
/// rather than only on their results.
class _Call {
  final int userId;
  final int length;
  final int start;
  final String? after;
  final String? before;
  const _Call({required this.userId, required this.length, required this.start, this.after, this.before});

  @override
  String toString() => 'user=$userId len=$length start=$start after=$after before=$before';
}

class _FakeAccess implements TautulliImportAccess {
  /// Rows the fake server holds, newest first.
  List<TautulliHistoryEntry> rows;
  Set<String> enabled;
  final List<_Call> calls = [];

  /// Page index (0-based) at which to throw, or null.
  int? failAtCall;

  /// Returns null (integration switched off) from this call index on.
  int? disableAtCall;

  _FakeAccess({this.rows = const [], this.enabled = const {_machine}});

  @override
  Set<String> enabledImportServerIds() => enabled;

  @override
  Future<TautulliHistoryPage?> fetchImportHistory(
    ServerId serverId, {
    required int userId,
    required int length,
    required int start,
    String? after,
    String? before,
  }) async {
    final index = calls.length;
    calls.add(_Call(userId: userId, length: length, start: start, after: after, before: before));
    if (disableAtCall != null && index >= disableAtCall!) return null;
    if (failAtCall != null && index == failAtCall) throw Exception('SocketException: boom');

    // The fake honours the same contract the real API documents: `after` and
    // `before` are inclusive day bounds and the result is newest first.
    final window = rows.where((r) {
      final day = _dayOf(r.date! * 1000);
      if (after != null && day.compareTo(after) < 0) return false;
      if (before != null && day.compareTo(before) > 0) return false;
      return true;
    }).toList();
    window.sort((a, b) => b.date!.compareTo(a.date!));
    final page = window.skip(start).take(length).toList();
    return TautulliHistoryPage(entries: page, recordsTotal: window.length, recordsFiltered: window.length);
  }

  static String _dayOf(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toUtc();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

class _FakeClient implements MediaServerClient {
  final Map<String, MediaItem?> items;
  final List<String> fetched = [];
  Set<String> throwFor = const {};

  _FakeClient(this.items);

  @override
  ServerId get serverId => ServerId(_machine);

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) async {
    fetched.add(id);
    if (throwFor.contains(id)) throw Exception('gone');
    return items[id];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _item(String id, {List<String> genres = const ['Sci-Fi'], MediaKind kind = MediaKind.movie}) =>
    MediaItem.plex(id: id, kind: kind, serverId: _machine, title: id, genres: genres, year: 2015);

TautulliHistoryEntry _entry({
  required int rowId,
  required int daysAgo,
  int userId = _userId,
  String mediaType = 'movie',
  int? ratingKey,
  int? grandparentRatingKey,
  double watchedStatus = 1,
  int percentComplete = 95,
  String? machineId = _machine,
  int? playSeconds = 3600,
}) => TautulliHistoryEntry(
  rowId: rowId,
  userId: userId,
  watchedStatus: watchedStatus,
  percentComplete: percentComplete,
  date: _secondsAgo(daysAgo),
  duration: playSeconds,
  playSeconds: playSeconds,
  machineId: machineId,
  mediaType: mediaType,
  ratingKey: ratingKey ?? rowId,
  grandparentRatingKey: grandparentRatingKey,
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  TautulliHistoryImporter importer(
    _FakeAccess access,
    _FakeClient client, {
    bool Function()? isCurrentProfile,
    String profileId = _profile,
    int pageLength = kImportPageLength,
    int initialMaxPages = kInitialMaxPages,
    int forwardMaxPages = kForwardMaxPages,
    int backfillMaxPages = kBackfillMaxPages,
    int profileCap = kProfileInteractionCap,
  }) => TautulliHistoryImporter(
    database: db,
    access: access,
    target: TautulliImportTarget(
      activeProfileId: profileId,
      userId: _userId,
      serverId: ServerId(_machine),
      machineIdentifier: _machine,
    ),
    client: client,
    isCurrentProfile: isCurrentProfile ?? () => true,
    clock: () => _now,
    pageLength: pageLength,
    initialMaxPages: initialMaxPages,
    forwardMaxPages: forwardMaxPages,
    backfillMaxPages: backfillMaxPages,
    profileCap: profileCap,
  );

  group('request shape', () {
    test('after and before are date bounds, start is only an offset', () async {
      final access = _FakeAccess(
        rows: [for (var i = 0; i < 3; i++) _entry(rowId: i, daysAgo: i)],
      );
      await importer(access, _FakeClient({for (var i = 0; i < 3; i++) '$i': _item('$i')})).sync();

      expect(access.calls, isNotEmpty);
      final first = access.calls.first;
      expect(first.userId, _userId);
      expect(first.length, kImportPageLength);
      expect(first.start, 0);
      expect(first.after, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(first.before, isNull, reason: 'a forward pass has no upper bound');
    });

    test('the first pass asks back exactly the retention window', () async {
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 1)]);
      await importer(access, _FakeClient({'1': _item('1')})).sync();
      final expected = DateTime.fromMillisecondsSinceEpoch(
        _now - kInteractionRetentionDays * Duration.millisecondsPerDay,
      ).toUtc();
      expect(access.calls.first.after, _FakeAccess._dayOf(expected.millisecondsSinceEpoch));
    });

    test('nothing is requested when the server is not enabled', () async {
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 1)], enabled: const {});
      access.disableAtCall = 0;
      final outcome = await importer(access, _FakeClient({})).sync();
      expect(outcome!.imported, 0);
      expect(await db.countMediaInteractions(_profile), 0);
    });
  });

  group('signals', () {
    Future<List<MediaInteractionRow>> importAll(List<TautulliHistoryEntry> rows) async {
      final access = _FakeAccess(rows: rows);
      final items = {for (final r in rows) '${r.ratingKey}': _item('${r.ratingKey}')};
      await importer(access, _FakeClient(items)).sync();
      return db.getMediaInteractions(_profile, enabledImportServerIds: const {_machine});
    }

    test('watched_status wins even below the percentage threshold', () async {
      // The measured fixture has watched_status 1 at percent_complete 82: the
      // admin's own threshold can sit below 85.
      final rows = await importAll([_entry(rowId: 1, daysAgo: 1, watchedStatus: 1, percentComplete: 82)]);
      expect(rows.single.eventType, 'completed');
      expect(rows.single.eventWeight, 1.0);
    });

    test('85 percent is completed even without watched_status', () async {
      final rows = await importAll([_entry(rowId: 1, daysAgo: 1, watchedStatus: 0, percentComplete: 85)]);
      expect(rows.single.eventType, 'completed');
    });

    test('84 percent is partial', () async {
      final rows = await importAll([_entry(rowId: 1, daysAgo: 1, watchedStatus: 0, percentComplete: 84)]);
      expect(rows.single.eventType, 'partial');
      expect(rows.single.eventWeight, 0.4);
    });

    test('50 percent is the partial boundary', () async {
      final rows = await importAll([_entry(rowId: 1, daysAgo: 1, watchedStatus: 0, percentComplete: 50)]);
      expect(rows.single.eventType, 'partial');
    });

    test('49 percent is ignored, never negative', () async {
      final rows = await importAll([_entry(rowId: 1, daysAgo: 1, watchedStatus: 0, percentComplete: 49)]);
      expect(rows, isEmpty);
    });

    test('a partial watched_status below 1 falls back to the percentage', () async {
      final rows = await importAll([_entry(rowId: 1, daysAgo: 1, watchedStatus: 0.5, percentComplete: 60)]);
      expect(rows.single.eventType, 'partial');
    });

    test('clips, tracks and live are skipped', () async {
      final access = _FakeAccess(
        rows: [
          for (final type in ['clip', 'track', 'live'])
            _entry(rowId: type.hashCode.abs() % 1000, daysAgo: 1, mediaType: type),
        ],
      );
      await importer(access, _FakeClient({})).sync();
      expect(await db.countMediaInteractions(_profile), 0);
    });

    test('playSeconds is stored and never confused with a media duration', () async {
      final rows = await importAll([_entry(rowId: 1, daysAgo: 1, playSeconds: 545)]);
      expect(rows.single.playSeconds, 545);
      expect(rows.single.completionPercent, 95);
    });
  });

  group('episodes', () {
    test('an episode is stored under its series and resolves the show once', () async {
      final access = _FakeAccess(
        rows: [
          for (var i = 0; i < 20; i++)
            _entry(rowId: i, daysAgo: i, mediaType: 'episode', ratingKey: 1000 + i, grandparentRatingKey: 77),
        ],
      );
      final client = _FakeClient({'77': _item('77', kind: MediaKind.show)});
      await importer(access, client).sync();

      final rows = await db.getMediaInteractions(_profile, enabledImportServerIds: const {_machine});
      expect(rows, hasLength(20));
      expect(rows.map((r) => r.globalKey).toSet(), {'$_machine:77'});
      expect(rows.map((r) => r.seriesKey).toSet(), {'$_machine:77'});
      expect(client.fetched, ['77'], reason: 'a binge of twenty costs one lookup');
    });

    test('an unresolvable item costs one row, not the sync', () async {
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 1), _entry(rowId: 2, daysAgo: 2)]);
      final client = _FakeClient({'1': null, '2': _item('2')});
      final outcome = await importer(access, client).sync();
      expect(outcome!.unresolvable, 1);
      expect(outcome.imported, 1);
    });

    test('a fetch that throws is treated as unresolvable', () async {
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 1), _entry(rowId: 2, daysAgo: 2)]);
      final client = _FakeClient({'1': _item('1'), '2': _item('2')})..throwFor = {'1'};
      final outcome = await importer(access, client).sync();
      expect(outcome!.imported, 1);
    });
  });

  group('defence in depth', () {
    test("another user's rows are rejected", () async {
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 1), _entry(rowId: 2, daysAgo: 2, userId: 999)]);
      final outcome = await importer(access, _FakeClient({'1': _item('1'), '2': _item('2')})).sync();
      expect(outcome!.imported, 1);
      expect(outcome.skipped, 1);
      final rows = await db.getMediaInteractions(_profile, enabledImportServerIds: const {_machine});
      expect(rows.single.globalKey, '$_machine:1');
    });

    test('a row from another server is skipped', () async {
      final access = _FakeAccess(
        rows: [
          _entry(rowId: 1, daysAgo: 1),
          _entry(rowId: 2, daysAgo: 2, machineId: 'pms-other'),
        ],
      );
      final outcome = await importer(access, _FakeClient({'1': _item('1'), '2': _item('2')})).sync();
      expect(outcome!.imported, 1);
      expect(outcome.skipped, 1);
    });

    test('a missing machine_id is not a rejection', () async {
      // Older Tautulli builds do not send it.
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 1, machineId: null)]);
      final outcome = await importer(access, _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.imported, 1);
    });

    test('every stored row carries the bound server and a stable event id', () async {
      final access = _FakeAccess(rows: [_entry(rowId: 42, daysAgo: 1)]);
      await importer(access, _FakeClient({'42': _item('42')})).sync();
      final row = (await db.getMediaInteractions(_profile, enabledImportServerIds: const {_machine})).single;
      expect(row.source, kInteractionSourceTautulli);
      expect(row.sourceServerId, _machine);
      expect(row.sourceEventId, 'tautulli:$_machine:42');
    });
  });

  group('idempotency and cursors', () {
    test('a second sync imports nothing new', () async {
      final access = _FakeAccess(
        rows: [for (var i = 0; i < 5; i++) _entry(rowId: i, daysAgo: i + 1)],
      );
      final client = _FakeClient({for (var i = 0; i < 5; i++) '$i': _item('$i')});

      final first = await importer(access, client).sync();
      expect(first!.imported, 5);

      final second = await importer(access, client).sync();
      expect(second!.imported, 0);
      expect(await db.countMediaInteractions(_profile), 5);
    });

    test('the forward pass overlaps by kOverlapDays and dedupes it away', () async {
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 5)]);
      final client = _FakeClient({'1': _item('1'), '2': _item('2')});
      await importer(access, client).sync();

      final cursor = await db.getHistorySyncCursor(_profile, _machine, 'tautulli');
      access.calls.clear();
      access.rows = [_entry(rowId: 1, daysAgo: 5), _entry(rowId: 2, daysAgo: 0)];
      final second = await importer(access, client).sync();

      expect(second!.imported, 1, reason: 'only the new record');
      final overlapDay = DateTime.fromMillisecondsSinceEpoch(
        cursor!.forwardCursorAt - kOverlapDays * Duration.millisecondsPerDay,
      ).toUtc();
      expect(access.calls.first.after, _FakeAccess._dayOf(overlapDay.millisecondsSinceEpoch));
    });

    test('records sharing a timestamp all land, and the row id is the tiebreak', () async {
      final access = _FakeAccess(rows: [for (var i = 0; i < 4; i++) _entry(rowId: i, daysAgo: 3)]);
      final client = _FakeClient({for (var i = 0; i < 4; i++) '$i': _item('$i')});
      final outcome = await importer(access, client).sync();
      expect(outcome!.imported, 4);
      final cursor = await db.getHistorySyncCursor(_profile, _machine, 'tautulli');
      expect(cursor!.forwardLastRowId, isNotNull);
    });

    test('a late record on an already-passed day still arrives', () async {
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 3)]);
      final client = _FakeClient({'1': _item('1'), '2': _item('2')});
      await importer(access, client).sync();
      // Same day as the watermark, added afterwards.
      access.rows = [...access.rows, _entry(rowId: 2, daysAgo: 3)];
      final second = await importer(access, client).sync();
      expect(second!.imported, 1);
    });

    test('a network failure mid-pass leaves the watermark alone', () async {
      final rows = [for (var i = 0; i < 5; i++) _entry(rowId: i, daysAgo: i + 1)];
      final client = _FakeClient({for (var i = 0; i < 5; i++) '$i': _item('$i')});

      final failing = _FakeAccess(rows: rows)..failAtCall = 0;
      final outcome = await importer(failing, client).sync();
      expect(outcome!.partial, isTrue);
      expect(await db.getHistorySyncCursor(_profile, _machine, 'tautulli'), isNull);

      // And a retry gets everything.
      final retry = await importer(_FakeAccess(rows: rows), client).sync();
      expect(retry!.imported, 5);
    });

    test('the lock is released after an exception', () async {
      final rows = [_entry(rowId: 1, daysAgo: 1)];
      final client = _FakeClient({'1': _item('1')});
      await importer(_FakeAccess(rows: rows)..failAtCall = 0, client).sync();
      final after = await importer(_FakeAccess(rows: rows), client).sync();
      expect(after, isNotNull, reason: 'a stuck lock would return null');
      expect(after!.imported, 1);
    });

    test('a concurrent sync for the same profile and server returns null', () async {
      final access = _FakeAccess(
        rows: [for (var i = 0; i < 5; i++) _entry(rowId: i, daysAgo: i + 1)],
      );
      final client = _FakeClient({for (var i = 0; i < 5; i++) '$i': _item('$i')});
      final a = importer(access, client).sync();
      final b = importer(access, client).sync();
      final results = await Future.wait([a, b]);
      expect(results.where((r) => r == null), hasLength(1));
    });
  });

  group('lifecycle guards', () {
    test('a profile switch before the commit writes nothing', () async {
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 1)]);
      var current = true;
      final outcome = await importer(
        access,
        _FakeClient({'1': _item('1')}),
        isCurrentProfile: () {
          final answer = current;
          current = false; // the switch happens during the pass
          return answer;
        },
      ).sync();
      expect(outcome!.imported, 0);
      expect(await db.countMediaInteractions(_profile), 0);
      expect(await db.getHistorySyncCursor(_profile, _machine, 'tautulli'), isNull);
    });

    test('a profile deletion during the import writes nothing', () async {
      final access = _FakeAccess(rows: [_entry(rowId: 1, daysAgo: 1)]);
      final client = _FakeClient({'1': _item('1')});
      // Bumping the epoch is exactly what deleteRecommendationDataForProfile
      // does, and it happens while the profile is still active, so the
      // is-this-my-profile check alone would not catch it.
      final job = importer(access, client).sync();
      await db.deleteRecommendationDataForProfile(_profile);
      await job;
      expect(await db.countMediaInteractions(_profile), 0);
      expect(await db.getHistorySyncCursor(_profile, _machine, 'tautulli'), isNull);
    });

    test('the policy going off mid-sync stops it without half state', () async {
      final access = _FakeAccess(
        rows: [for (var i = 0; i < 400; i++) _entry(rowId: i, daysAgo: i + 1)],
      )..disableAtCall = 1;
      final client = _FakeClient({for (var i = 0; i < 400; i++) '$i': _item('$i')});
      final outcome = await importer(access, client).sync();
      expect(outcome!.partial, isTrue);
      expect(await db.getHistorySyncCursor(_profile, _machine, 'tautulli'), isNull);
    });
  });

  group('retention cap', () {
    test('a descending pass stops once the profile is full and says so', () async {
      // More history than the profile may keep. Walking further down would only
      // feed the prune, so the pass has to stop and record why.
      final rows = [for (var i = 0; i < kProfileInteractionCap + 600; i++) _entry(rowId: i, daysAgo: 1 + i % 300)];
      final access = _FakeAccess(rows: rows);
      final client = _FakeClient({for (var i = 0; i < rows.length; i++) '$i': _item('$i')});

      await importer(access, client).sync();

      final stored = await db.countMediaInteractions(_profile);
      expect(stored, kProfileInteractionCap);
      final cursor = await db.getHistorySyncCursor(_profile, _machine, 'tautulli');
      expect(cursor!.backfillState, kBackfillRetentionCap);
      // The overshoot is at most one page: nothing is fetched that is known in
      // advance to be pruned straight away.
      expect(access.calls.length * kImportPageLength, lessThanOrEqualTo(kProfileInteractionCap + kImportPageLength));
    });

    test('a full profile spends no backfill page at all', () async {
      // Not "one page and then stop": a profile at the cap must not fetch even
      // a single older page, because the prune would delete every row of it.
      final rows = [for (var i = 0; i < 60; i++) _entry(rowId: i, daysAgo: 1 + i)];
      final client = _FakeClient({for (var i = 0; i < 60; i++) '$i': _item('$i')});
      await importer(_FakeAccess(rows: rows), client, pageLength: 10, initialMaxPages: 2, profileCap: 20).sync();
      expect(await db.countMediaInteractions(_profile), 20);

      final second = _FakeAccess(rows: rows);
      await importer(second, client, pageLength: 10, forwardMaxPages: 2, backfillMaxPages: 4, profileCap: 20).sync();
      expect(second.calls.where((c) => c.before != null), isEmpty);
      expect((await db.getHistorySyncCursor(_profile, _machine, 'tautulli'))!.backfillState, kBackfillRetentionCap);
    });

    test('a full profile does not spend another backfill pass', () async {
      final rows = [for (var i = 0; i < kProfileInteractionCap + 600; i++) _entry(rowId: i, daysAgo: 1 + i % 300)];
      final client = _FakeClient({for (var i = 0; i < rows.length; i++) '$i': _item('$i')});
      await importer(_FakeAccess(rows: rows), client).sync();

      final second = _FakeAccess(rows: rows);
      await importer(second, client).sync();
      // Forward only. A backfill pass would carry a `before` bound.
      expect(second.calls.where((c) => c.before != null), isEmpty);
    });

    test('backfill resumes once retention has aged the profile back down', () async {
      final rows = [for (var i = 0; i < kProfileInteractionCap + 600; i++) _entry(rowId: i, daysAgo: 1 + i % 300)];
      final client = _FakeClient({for (var i = 0; i < rows.length; i++) '$i': _item('$i')});
      await importer(_FakeAccess(rows: rows), client).sync();
      expect((await db.getHistorySyncCursor(_profile, _machine, 'tautulli'))!.backfillState, kBackfillRetentionCap);

      // Simulate a year passing: retention empties most of the profile.
      await db.customStatement('DELETE FROM media_interactions WHERE id > 50');
      expect(await db.countMediaInteractions(_profile), lessThan(kProfileInteractionCap));

      final resumed = _FakeAccess(rows: rows);
      await importer(resumed, client).sync();
      expect(resumed.calls.where((c) => c.before != null), isNotEmpty, reason: 'backfill picked up again');
    });
  });

  group('the frozen backfill window', () {
    // Small budgets so truncation, resumption and the offset are exercised for
    // real instead of behind five thousand fixtures.
    const page = 10;

    test('one calendar day bigger than a pass is drained across runs, not restarted', () async {
      // Every record on the same calendar day, more than one backfill pass can
      // carry. A day-granular `before` cursor would re-anchor on that day and
      // make no progress; the frozen window plus an offset walks through it.
      const total = 70;
      final rows = [_entry(rowId: 999999, daysAgo: 0), for (var i = 0; i < total; i++) _entry(rowId: i, daysAgo: 40)];
      final client = _FakeClient({for (var i = 0; i < total; i++) '$i': _item('$i'), '999999': _item('999999')});

      final offsets = <int>[];
      var lastStored = 0;
      var runs = 0;
      for (; runs < 20; runs++) {
        final access = _FakeAccess(rows: rows);
        await importer(
          access,
          client,
          pageLength: page,
          initialMaxPages: 2,
          forwardMaxPages: 2,
          backfillMaxPages: 2,
        ).sync();
        offsets.addAll(access.calls.where((c) => c.before != null).map((c) => c.start));
        final cursor = await db.getHistorySyncCursor(_profile, _machine, 'tautulli');
        final stored = await db.countMediaInteractions(_profile);
        if (cursor!.backfillState == kBackfillExhausted) break;
        expect(stored, greaterThan(lastStored), reason: 'run $runs made no progress: the boundary day re-anchored');
        lastStored = stored;
      }

      expect(runs, lessThan(20), reason: 'it has to terminate');
      expect(runs, greaterThan(1), reason: 'the budgets must actually force more than one run');
      expect(offsets.length, greaterThan(2), reason: 'the backfill pass has to have run for real');
      expect(await db.countMediaInteractions(_profile), total + 1);
      // Every offset requested exactly once, and never going backwards: that is
      // what a frozen window buys, and what a day-anchored cursor cannot give.
      expect(offsets.toSet().length, offsets.length, reason: 'an offset was requested twice');
      final sorted = [...offsets]..sort();
      expect(offsets, sorted, reason: 'offsets must only move forward');
      final stored = await db.getMediaInteractions(_profile, enabledImportServerIds: const {_machine});
      expect(stored.map((r) => r.sourceEventId).toSet(), hasLength(total + 1));
    });

    test('the backfill upper bound is frozen, not re-derived per run', () async {
      final rows = [for (var i = 0; i < 60; i++) _entry(rowId: i, daysAgo: 1 + i)];
      final client = _FakeClient({for (var i = 0; i < 60; i++) '$i': _item('$i')});

      await importer(
        _FakeAccess(rows: rows),
        client,
        pageLength: page,
        initialMaxPages: 2,
        backfillMaxPages: 0, // isolate the forward pass
      ).sync();
      final frozen = (await db.getHistorySyncCursor(_profile, _machine, 'tautulli'))!.backfillBeforeDay;
      expect(frozen, isNotNull);

      for (var run = 0; run < 3; run++) {
        final access = _FakeAccess(rows: rows);
        await importer(access, client, pageLength: page, forwardMaxPages: 2, backfillMaxPages: 1).sync();
        final backfill = access.calls.where((c) => c.before != null);
        if (backfill.isEmpty) break;
        expect(backfill.every((c) => c.before == frozen), isTrue, reason: 'the window moved on run $run');
      }
      expect(
        (await db.getHistorySyncCursor(_profile, _machine, 'tautulli'))!.backfillBeforeDay,
        frozen,
        reason: 'only the offset advances',
      );
    });

    test('the offset advances by exactly the rows a pass saw', () async {
      final rows = [for (var i = 0; i < 60; i++) _entry(rowId: i, daysAgo: 1 + i)];
      final client = _FakeClient({for (var i = 0; i < 60; i++) '$i': _item('$i')});
      await importer(_FakeAccess(rows: rows), client, pageLength: page, initialMaxPages: 2, backfillMaxPages: 0).sync();

      final previous = (await db.getHistorySyncCursor(_profile, _machine, 'tautulli'))!.backfillOffset;
      expect(previous, 0);
      final access = _FakeAccess(rows: rows);
      await importer(access, client, pageLength: page, forwardMaxPages: 2, backfillMaxPages: 2).sync();
      final after = (await db.getHistorySyncCursor(_profile, _machine, 'tautulli'))!;
      expect(after.backfillOffset, greaterThan(previous));
      expect(after.backfillOffset % page, 0);
    });

    test('a truncated first pass does not claim the window is exhausted', () async {
      final rows = [for (var i = 0; i < 60; i++) _entry(rowId: i, daysAgo: 1 + i)];
      final client = _FakeClient({for (var i = 0; i < 60; i++) '$i': _item('$i')});
      await importer(_FakeAccess(rows: rows), client, pageLength: page, initialMaxPages: 2, backfillMaxPages: 0).sync();

      final cursor = await db.getHistorySyncCursor(_profile, _machine, 'tautulli');
      expect(cursor!.backfillState, isNot(kBackfillExhausted));
      expect(cursor.backfillBeforeDay, isNotNull);
      expect(cursor.forwardCursorAt, greaterThan(0));
      // The older part is still reachable, which is the whole point.
      expect(await db.countMediaInteractions(_profile), lessThan(60));
    });

    test('the backfill pass really does fetch the older part', () async {
      final rows = [for (var i = 0; i < 60; i++) _entry(rowId: i, daysAgo: 1 + i)];
      final client = _FakeClient({for (var i = 0; i < 60; i++) '$i': _item('$i')});
      await importer(_FakeAccess(rows: rows), client, pageLength: page, initialMaxPages: 2, backfillMaxPages: 0).sync();
      final afterFirst = await db.countMediaInteractions(_profile);
      expect(afterFirst, 20, reason: 'two pages of ten, the rest is left for backfill');

      await importer(_FakeAccess(rows: rows), client, pageLength: page, forwardMaxPages: 2, backfillMaxPages: 4).sync();
      expect(await db.countMediaInteractions(_profile), greaterThan(afterFirst));
    });

    test('a small history is exhausted in one go', () async {
      final access = _FakeAccess(
        rows: [for (var i = 0; i < 5; i++) _entry(rowId: i, daysAgo: i + 1)],
      );
      final client = _FakeClient({for (var i = 0; i < 5; i++) '$i': _item('$i')});
      await importer(access, client).sync();
      final cursor = await db.getHistorySyncCursor(_profile, _machine, 'tautulli');
      expect(cursor!.backfillState, kBackfillExhausted);
      expect(access.calls.where((c) => c.before != null), isEmpty, reason: 'nothing left to backfill');
    });
  });

  group('cross-source deduplication', () {
    Future<void> local(String globalKey, {required int atMs, double weight = 1.0, String type = 'completed'}) =>
        db.insertMediaInteraction(
          MediaInteractionsCompanion.insert(
            profileId: _profile,
            globalKey: globalKey,
            mediaKind: 'movie',
            eventType: type,
            eventWeight: weight,
            occurredAt: atMs,
          ),
          profileId: _profile,
        );

    test('a local completion swallows the same view from Tautulli', () async {
      final entry = _entry(rowId: 1, daysAgo: 1);
      await local('$_machine:1', atMs: entry.date! * 1000 + 60 * 1000);

      final outcome = await importer(_FakeAccess(rows: [entry]), _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.imported, 0);
      expect(outcome.deduplicated, 1);
      expect(await db.countMediaInteractions(_profile), 1);
    });

    test('a local dismissal never swallows a completed Tautulli view', () async {
      // The event_weight > 0 clause exists for exactly this: a negative signal
      // is not evidence that the play was already recorded.
      final entry = _entry(rowId: 1, daysAgo: 1);
      await local('$_machine:1', atMs: entry.date! * 1000, weight: -0.3, type: 'skipped');

      final outcome = await importer(_FakeAccess(rows: [entry]), _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.imported, 1);
      expect(outcome.deduplicated, 0);
      expect(await db.countMediaInteractions(_profile), 2);
    });

    test('a genuine rewatch outside the window survives', () async {
      final entry = _entry(rowId: 1, daysAgo: 1);
      await local('$_machine:1', atMs: entry.date! * 1000 - kCrossSourceWindow.inMilliseconds - 1000);

      final outcome = await importer(_FakeAccess(rows: [entry]), _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.imported, 1);
    });

    test('the window boundary is inclusive', () async {
      final entry = _entry(rowId: 1, daysAgo: 1);
      await local('$_machine:1', atMs: entry.date! * 1000 + kCrossSourceWindow.inMilliseconds);
      final outcome = await importer(_FakeAccess(rows: [entry]), _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.imported, 0);
    });

    test("another profile's local play does not deduplicate this one", () async {
      final entry = _entry(rowId: 1, daysAgo: 1);
      await db.insertMediaInteraction(
        MediaInteractionsCompanion.insert(
          profileId: 'someone-else',
          globalKey: '$_machine:1',
          mediaKind: 'movie',
          eventType: 'completed',
          eventWeight: 1.0,
          occurredAt: entry.date! * 1000,
        ),
        profileId: 'someone-else',
      );

      final outcome = await importer(_FakeAccess(rows: [entry]), _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.imported, 1);
    });

    test('the same rating key on another server does not deduplicate', () async {
      // Rating keys are per-server, so the server id in the global key is what
      // keeps two unrelated titles apart.
      final entry = _entry(rowId: 1, daysAgo: 1);
      await local('other-server:1', atMs: entry.date! * 1000);

      final outcome = await importer(_FakeAccess(rows: [entry]), _FakeClient({'1': _item('1')})).sync();
      expect(outcome!.imported, 1);
    });

    test('one bundled lookup per page, not one per row', () async {
      final rows = [for (var i = 0; i < 40; i++) _entry(rowId: i, daysAgo: 1 + i)];
      final client = _FakeClient({for (var i = 0; i < 40; i++) '$i': _item('$i')});
      final counting = _CountingDatabase(db);
      final job = TautulliHistoryImporter(
        database: counting,
        access: _FakeAccess(rows: rows),
        target: TautulliImportTarget(
          activeProfileId: _profile,
          userId: _userId,
          serverId: ServerId(_machine),
          machineIdentifier: _machine,
        ),
        client: client,
        isCurrentProfile: () => true,
        clock: () => _now,
        pageLength: 20,
      );
      await job.sync();
      // Two pages of twenty rows: two lookups, not forty.
      expect(counting.localLookups, 2);
    });
  });
}

/// Counts the bundled cross-source lookups so "one query per page" is a
/// measured claim rather than a comment.
class _CountingDatabase extends AppDatabase {
  final AppDatabase _inner;
  int localLookups = 0;

  _CountingDatabase(this._inner) : super.forTesting(NativeDatabase.memory());

  @override
  Future<Map<String, List<int>>> localPositiveInteractionsIn(
    String profileId,
    Set<String> globalKeys,
    int fromMs,
    int toMs,
  ) {
    localLookups++;
    return _inner.localPositiveInteractionsIn(profileId, globalKeys, fromMs, toMs);
  }

  @override
  Future<Set<String>> existingImportedEventIds(String profileId, Set<String> sourceEventIds) =>
      _inner.existingImportedEventIds(profileId, sourceEventIds);

  @override
  Future<void> insertImportedInteractions(List<MediaInteractionsCompanion> entries, {required String profileId}) =>
      _inner.insertImportedInteractions(entries, profileId: profileId);

  @override
  Future<int> countMediaInteractions(String profileId, {Set<String>? enabledImportServerIds}) =>
      _inner.countMediaInteractions(profileId, enabledImportServerIds: enabledImportServerIds);

  @override
  Future<HistorySyncCursorRow?> getHistorySyncCursor(String profileId, String serverId, String source) =>
      _inner.getHistorySyncCursor(profileId, serverId, source);

  @override
  Future<void> upsertHistorySyncCursor(HistorySyncCursorsCompanion entry) => _inner.upsertHistorySyncCursor(entry);
}
