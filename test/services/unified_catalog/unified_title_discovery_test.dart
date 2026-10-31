/// A play or a mark that came without its other sources finds them afterwards,
/// and only on proof: a write must never land on a same-named title (besluit 3
/// of DEC-XXX "Eén titel over servers heen").
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/playback_report_metadata.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/unified_catalog/unified_progress_mirror.dart';
import 'package:pleya/services/unified_catalog/unified_title_discovery.dart';
import 'package:pleya/services/unified_catalog/unified_title_playback.dart';
import 'package:pleya/utils/external_ids.dart';

import '../../test_helpers/prefs.dart';

class _Client implements MediaServerClient {
  _Client(this._id, {this.ids = const {}, this.episodes = const []});

  final String _id;
  final Map<String, ExternalIds> ids;
  final List<MediaItem> episodes;
  final stopped = <String>[];

  @override
  ServerId get serverId => ServerId(_id);

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  double get watchedThreshold => 0.9;

  @override
  bool get marksWatchedOnPlaybackStopped => false;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => ids[itemId] ?? const ExternalIds();

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async => episodes;

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

  @override
  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? playMethod,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {}

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? mediaSourceId,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) async => stopped.add(itemId);

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _film(String server, String id) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel', year: 2010, serverId: server);

void main() {
  late AppDatabase db;
  late MultiServerManager manager;
  late OfflineWatchSyncService queue;

  setUp(() {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    manager = MultiServerManager();
    queue = OfflineWatchSyncService(database: db, serverManager: manager);
  });

  tearDown(() async {
    queue.dispose();
    manager.dispose();
    await db.close();
  });

  UnifiedSourceGate gate() => UnifiedSourceGate(
    clientFor: manager.getClient,
    isOnline: manager.isServerOnline,
    isAuthRejected: (_) => false,
    isVisible: (_) => true,
    hiddenLibraryKeys: () => const {},
    isRestrictedProfile: () async => false,
  );

  UnifiedTitleDiscovery discoveryOf(
    List<MediaItem> answers, {
    Duration timeout = const Duration(seconds: 1),
    void Function(MediaIdentity identity)? onAsk,
  }) => UnifiedTitleDiscovery(
    gate: gate(),
    timeout: timeout,
    findSources: (identity, except) async {
      onAsk?.call(identity);
      return answers;
    },
  );

  const shared = ExternalIds(tmdb: 45745);

  test('a film the row showed on one server still reaches the other', () async {
    final other = _Client('other', ids: {'film-b': shared});
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
      ..debugRegisterClientForTesting(other);
    final playing = _film('playing', 'film-a').copyWith(durationMs: 7200000);
    final discovery = discoveryOf([_film('other', 'film-b').copyWith(durationMs: 7200000)]);

    await UnifiedProgressMirror.discovering(
      find: () => discovery.titleOf(playing),
      playing: playing,
      queue: queue,
    ).write(const Duration(minutes: 50), const Duration(hours: 2), watched: false);

    expect(other.stopped, ['film-b']);
  });

  test('a same-named title without a shared number is not a copy', () async {
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}))
      ..debugRegisterClientForTesting(_Client('other', ids: {'film-b': const ExternalIds(tmdb: 1)}));

    final title = await discoveryOf([_film('other', 'film-b')]).titleOf(_film('playing', 'film-a'));

    expect(title, isNull);
  });

  test('nothing to prove with: the servers are not even asked', () async {
    manager
      ..debugRegisterClientForTesting(_Client('playing'))
      ..debugRegisterClientForTesting(_Client('other'));
    var asked = false;

    final title = await discoveryOf([], onAsk: (_) => asked = true).titleOf(_film('playing', 'film-a'));

    expect(title, isNull);
    expect(asked, isFalse);
  });

  test('a server that does not answer leaves it on the source that plays', () async {
    manager.debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}));
    final never = UnifiedTitleDiscovery(
      gate: gate(),
      timeout: Duration.zero,
      findSources: (_, _) => Completer<List<MediaItem>>().future,
    );

    expect(await never.titleOf(_film('playing', 'film-a')), isNull);
  });

  test('a lookup that fails stays inside', () async {
    manager.debugRegisterClientForTesting(_Client('playing', ids: {'film-a': shared}));
    final failing = UnifiedTitleDiscovery(gate: gate(), findSources: (_, _) async => throw StateError('down'));

    expect(await failing.titleOf(_film('playing', 'film-a')), isNull);
  });

  test('an episode finds its series and reaches its copy', () async {
    final copy = MediaItem(
      id: 'ep-b',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      grandparentId: 'show-b',
      parentIndex: 1,
      index: 2,
      serverId: 'other',
    );
    final other = _Client('other', ids: {'show-b': shared}, episodes: [copy]);
    manager
      ..debugRegisterClientForTesting(_Client('playing', ids: {'show-a': shared}))
      ..debugRegisterClientForTesting(other);
    final episode = MediaItem(
      id: 'ep-a',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      grandparentId: 'show-a',
      grandparentTitle: 'Severance',
      parentIndex: 1,
      index: 2,
      serverId: 'playing',
    );
    MediaIdentity? asked;
    final show = MediaItem(id: 'show-b', backend: MediaBackend.plex, kind: MediaKind.show, serverId: 'other');

    final title = await discoveryOf([show], onAsk: (i) => asked = i).titleOf(episode);
    final copies = await title?.copiesOf(episode);

    expect(asked?.kind, MediaKind.show);
    expect(asked?.title, 'Severance');
    expect(copies?.map((c) => c.globalKey), ['other:ep-b']);
  });
}
