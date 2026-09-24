import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/recommendations/interaction_recorder.dart';
import 'package:pleya/utils/watch_state_notifier.dart';

class _FakeClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('s1');
  @override
  MediaBackend get backend => MediaBackend.plex;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;
  @override
  Future<MediaItem?> fetchItem(String id, {bool useCache = true}) async =>
      MediaItem.plex(id: id, kind: MediaKind.movie, serverId: 's1', title: id, genres: const ['Drama'], year: 2019);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late InteractionRecorder recorder;
  final item = MediaItem.plex(id: 'm1', kind: MediaKind.movie, serverId: 's1', title: 'm1');
  const hour = 60 * 60 * 1000;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    recorder = InteractionRecorder(database: db, profileId: 'p1', clientResolver: (_) => _FakeClient())..start();
  });
  tearDown(() async {
    await recorder.dispose();
    await db.close();
  });

  Future<List<MediaInteractionRow>> rows() async {
    await pumpEventQueue();
    return db.getMediaInteractions('p1');
  }

  test('a final stop at 60 percent records one partial row', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 60 * 60000, duration: 100 * 60000, isFinal: true);
    final saved = await rows();
    expect(saved.single.eventType, 'partial');
    expect(saved.single.eventWeight, 0.4);
    expect(saved.single.genresJson, '["Drama"]');
  });

  test('below 50 percent nothing is recorded', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 20 * 60000, duration: 100 * 60000, isFinal: true);
    expect(await rows(), isEmpty);
  });

  test('a progress tick that is not final records nothing', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 60 * 60000, duration: 100 * 60000);
    expect(await rows(), isEmpty);
  });

  test('a final stop that already counts as watched leaves the row to the watched event', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 95 * 60000, duration: 100 * 60000, isFinal: true);
    expect(await rows(), isEmpty, reason: 'isNowWatched is true at 95 percent; the watched event carries this one');
  });

  test('a second final stop within six hours does not stack', () async {
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 55 * 60000, duration: 100 * 60000, isFinal: true);
    await rows();
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 70 * 60000, duration: 100 * 60000, isFinal: true);
    expect(await rows(), hasLength(1));
  });

  test('the six hour window is measured against the stored row', () async {
    await db.insertMediaInteraction(
      MediaInteractionsCompanion.insert(
        profileId: 'p1',
        globalKey: 's1:m1',
        mediaKind: 'movie',
        eventType: 'partial',
        eventWeight: 0.4,
        occurredAt: DateTime.now().millisecondsSinceEpoch - 7 * hour,
      ),
      profileId: 'p1',
    );
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 55 * 60000, duration: 100 * 60000, isFinal: true);
    expect(await rows(), hasLength(2));
  });

  test('a completed view after a partial within six hours keeps both rows', () async {
    // The spec allows 1.4 for one title in one evening; the window only stops
    // partials from stacking on each other.
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 60 * 60000, duration: 100 * 60000, isFinal: true);
    await rows();
    WatchStateNotifier().notifyWatched(item: item);
    expect((await rows()).map((r) => r.eventType), ['partial', 'completed']);
  });

  test("another profile's row does not suppress the partial (DEC-062)", () async {
    await db.insertMediaInteraction(
      MediaInteractionsCompanion.insert(
        profileId: 'p2',
        globalKey: 's1:m1',
        mediaKind: 'movie',
        eventType: 'completed',
        eventWeight: 1.0,
        occurredAt: DateTime.now().millisecondsSinceEpoch - hour,
      ),
      profileId: 'p2',
    );
    WatchStateNotifier().notifyProgress(item: item, viewOffset: 60 * 60000, duration: 100 * 60000, isFinal: true);
    expect((await rows()).single.eventType, 'partial');
  });

  group('an imported row inside the window', () {
    Future<void> imported() => db.insertImportedInteractions([
      MediaInteractionsCompanion.insert(
        profileId: 'p1',
        globalKey: 's1:m1',
        mediaKind: 'movie',
        eventType: 'completed',
        eventWeight: 1.0,
        occurredAt: DateTime.now().millisecondsSinceEpoch - hour,
        source: const Value(kInteractionSourceTautulli),
        sourceEventId: const Value('tautulli:s1:1'),
        sourceServerId: const Value('s1'),
      ),
    ], profileId: 'p1');

    test('from a disabled import server does not suppress the partial', () async {
      await imported();
      WatchStateNotifier().notifyProgress(item: item, viewOffset: 60 * 60000, duration: 100 * 60000, isFinal: true);
      expect((await rows()).single.eventType, 'partial');
    });

    test('from an enabled import server does suppress it', () async {
      await recorder.dispose();
      recorder = InteractionRecorder(
        database: db,
        profileId: 'p1',
        clientResolver: (_) => _FakeClient(),
        enabledImportServerIds: () => {'s1'},
      )..start();
      await imported();
      WatchStateNotifier().notifyProgress(item: item, viewOffset: 60 * 60000, duration: 100 * 60000, isFinal: true);
      expect(await rows(), isEmpty, reason: 'rows() reads local rows only; no local partial was written');
    });
  });
}
