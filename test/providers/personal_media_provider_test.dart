import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_playlist.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/personal_media_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';

MediaLibrary _library(String serverId, String id, String title, MediaBackend backend) => MediaLibrary(
  id: id,
  backend: backend,
  title: title,
  kind: MediaKind.movie,
  serverId: serverId,
  serverName: serverId,
);

MediaItem _collection(String serverId, String id, String title, MediaBackend backend) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.collection,
  title: title,
  serverId: serverId,
  serverName: serverId,
);

MediaPlaylist _playlist(String serverId, String id, String title, MediaBackend backend) => MediaPlaylist(
  id: id,
  backend: backend,
  title: title,
  playlistType: 'video',
  serverId: serverId,
  serverName: serverId,
);

class _Client implements MediaServerClient {
  _Client({required String id, required this.backend, required this.capabilities}) : serverId = ServerId(id);

  @override
  final ServerId serverId;
  @override
  final MediaBackend backend;
  @override
  final ServerCapabilities capabilities;
  @override
  String get serverName => serverId.value;

  final Map<String, List<MediaItem>> collections = {};
  List<MediaPlaylist> playlists = [];
  final Set<String> failingLibraries = {};
  bool failPlaylists = false;
  final Map<String, int> collectionCalls = {};
  int playlistCalls = 0;
  Completer<void>? collectionGate;

  @override
  Future<List<MediaItem>> fetchCollections(String libraryId) async {
    collectionCalls.update(libraryId, (count) => count + 1, ifAbsent: () => 1);
    if (collectionGate case final gate?) await gate.future;
    if (failingLibraries.contains(libraryId)) throw StateError('collection failure: $libraryId');
    return collections[libraryId] ?? const [];
  }

  @override
  Future<List<MediaPlaylist>> fetchPlaylists({String playlistType = 'video', bool? smart}) async {
    playlistCalls++;
    if (failPlaylists) throw StateError('playlist failure');
    return playlists;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late LibrariesProvider libraries;

  setUp(() {
    manager = MultiServerManager();
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    libraries = LibrariesProvider();
  });

  tearDown(() {
    libraries.dispose();
    multiServer.dispose();
    manager.dispose();
  });

  test('loads collections per library and playlists once per capable server', () async {
    final plex = _Client(id: 'plex', backend: MediaBackend.plex, capabilities: ServerCapabilities.plex)
      ..collections.addAll({
        'movies': [_collection('plex', 'c1', 'Oscar winners', MediaBackend.plex)],
        'family': [_collection('plex', 'c2', 'Family night', MediaBackend.plex)],
      });
    plex.playlists = [_playlist('plex', 'p1', 'Friday', MediaBackend.plex)];

    final jellyfin = _Client(id: 'jellyfin', backend: MediaBackend.jellyfin, capabilities: ServerCapabilities.jellyfin)
      ..collections['jf-movies'] = [_collection('jellyfin', 'c3', 'Classics', MediaBackend.jellyfin)]
      ..collections['jf-shows'] = [_collection('jellyfin', 'c3', 'Classics', MediaBackend.jellyfin)];
    jellyfin.playlists = [_playlist('jellyfin', 'p2', 'Weekend', MediaBackend.jellyfin)];

    final local = _Client(id: 'local', backend: MediaBackend.local, capabilities: ServerCapabilities.local);
    manager
      ..debugRegisterClientForTesting(plex)
      ..debugRegisterClientForTesting(jellyfin)
      ..debugRegisterClientForTesting(local);
    libraries.debugSetLibraries([
      _library('plex', 'movies', 'Movies', MediaBackend.plex),
      _library('plex', 'family', 'Family', MediaBackend.plex),
      _library('jellyfin', 'jf-movies', 'JF Movies', MediaBackend.jellyfin),
      _library('jellyfin', 'jf-shows', 'JF Shows', MediaBackend.jellyfin),
      _library('local', 'folder', 'Folder', MediaBackend.local),
    ]);

    final provider = PersonalMediaProvider(multiServer: multiServer, libraries: libraries);
    await provider.load();

    expect(provider.state, PersonalMediaLoadState.loaded);
    expect(provider.collections.map((entry) => (entry.item.title, entry.library.title)), [
      ('Oscar winners', 'Movies'),
      ('Family night', 'Family'),
      ('Classics', 'JF Movies'),
    ]);
    expect(provider.playlists.map((entry) => (entry.playlist.title, entry.serverId)), [
      ('Friday', 'plex'),
      ('Weekend', 'jellyfin'),
    ]);
    expect(plex.collectionCalls, {'movies': 1, 'family': 1});
    expect(jellyfin.collectionCalls, {'jf-movies': 1});
    expect(provider.collections.last.sourceLabel, 'jellyfin');
    expect(provider.collections.last.item.libraryId, isNull, reason: 'Jellyfin BoxSets are not owned by JF Movies');
    expect(local.collectionCalls, isEmpty, reason: 'unsupported backends get no misleading collection probe');
    expect(plex.playlistCalls, 1, reason: 'two Plex libraries still produce one server-scoped playlist request');
    expect(jellyfin.playlistCalls, 1);
    expect(local.playlistCalls, 0, reason: 'the capability hides unsupported playlists');
    provider.dispose();
  });

  test('partial failures preserve successes and retry only failed scopes', () async {
    final plex = _Client(id: 'plex', backend: MediaBackend.plex, capabilities: ServerCapabilities.plex)
      ..collections['movies'] = [_collection('plex', 'c1', 'Oscar winners', MediaBackend.plex)]
      ..failPlaylists = true;
    final jellyfin = _Client(id: 'jellyfin', backend: MediaBackend.jellyfin, capabilities: ServerCapabilities.jellyfin)
      ..collections['jf-movies'] = [_collection('jellyfin', 'c2', 'Classics', MediaBackend.jellyfin)]
      ..playlists = [_playlist('jellyfin', 'p2', 'Weekend', MediaBackend.jellyfin)]
      ..failingLibraries.add('jf-movies');
    manager
      ..debugRegisterClientForTesting(plex)
      ..debugRegisterClientForTesting(jellyfin);
    libraries.debugSetLibraries([
      _library('plex', 'movies', 'Movies', MediaBackend.plex),
      _library('jellyfin', 'jf-movies', 'JF Movies', MediaBackend.jellyfin),
    ]);

    final provider = PersonalMediaProvider(multiServer: multiServer, libraries: libraries);
    await provider.load();

    expect(provider.state, PersonalMediaLoadState.loaded);
    expect(provider.hasPartialFailure, isTrue);
    expect(provider.collections.single.item.title, 'Oscar winners');
    expect(provider.playlists.single.playlist.title, 'Weekend');
    expect(provider.failedCollectionLibraryKeys, {'jellyfin:jf-movies'});
    expect(provider.failedPlaylistServerIds, {'plex'});

    jellyfin.failingLibraries.clear();
    plex.failPlaylists = false;
    plex.playlists = [_playlist('plex', 'p1', 'Friday', MediaBackend.plex)];
    await provider.retryFailed();

    expect(provider.hasPartialFailure, isFalse);
    expect(provider.collections.map((entry) => entry.item.title), ['Oscar winners', 'Classics']);
    expect(provider.playlists.map((entry) => entry.playlist.title), ['Friday', 'Weekend']);
    expect(plex.collectionCalls['movies'], 1, reason: 'successful collection scope is not fetched again');
    expect(jellyfin.playlistCalls, 1, reason: 'successful playlist scope is not fetched again');
    expect(jellyfin.collectionCalls['jf-movies'], 2);
    expect(plex.playlistCalls, 2);
    provider.dispose();
  });

  test('a library arriving after the first empty load becomes visible', () async {
    final plex = _Client(id: 'plex', backend: MediaBackend.plex, capabilities: ServerCapabilities.plex)
      ..collections['movies'] = [_collection('plex', 'c1', 'Later collection', MediaBackend.plex)];
    manager.debugRegisterClientForTesting(plex);
    final provider = PersonalMediaProvider(multiServer: multiServer, libraries: libraries);

    await provider.load();
    expect(provider.collections, isEmpty);

    final arrived = Completer<void>();
    provider.addListener(() {
      if (provider.collections.isNotEmpty && !arrived.isCompleted) arrived.complete();
    });
    libraries.debugSetLibraries([_library('plex', 'movies', 'Movies', MediaBackend.plex)]);
    await arrived.future;

    expect(provider.collections.single.item.title, 'Later collection');
    expect(plex.collectionCalls['movies'], 1);
    provider.dispose();
  });

  test('a library arriving during retry loads after the failed scope completes', () async {
    final plex = _Client(id: 'plex', backend: MediaBackend.plex, capabilities: ServerCapabilities.plex)
      ..failingLibraries.add('movies')
      ..collections['movies'] = [_collection('plex', 'c1', 'Recovered', MediaBackend.plex)]
      ..collections['later'] = [_collection('plex', 'c2', 'New library', MediaBackend.plex)];
    manager.debugRegisterClientForTesting(plex);
    libraries.debugSetLibraries([_library('plex', 'movies', 'Movies', MediaBackend.plex)]);
    final provider = PersonalMediaProvider(multiServer: multiServer, libraries: libraries);
    await provider.load();

    plex.failingLibraries.clear();
    final gate = Completer<void>();
    plex.collectionGate = gate;
    final retry = provider.retryFailed();
    libraries.debugSetLibraries([
      _library('plex', 'movies', 'Movies', MediaBackend.plex),
      _library('plex', 'later', 'Later', MediaBackend.plex),
    ]);
    final arrived = Completer<void>();
    provider.addListener(() {
      if (provider.collections.any((entry) => entry.item.title == 'New library') && !arrived.isCompleted) {
        arrived.complete();
      }
    });
    gate.complete();
    await retry;
    await arrived.future.timeout(const Duration(seconds: 1));

    expect(provider.collections.map((entry) => entry.item.title), ['Recovered', 'New library']);
    provider.dispose();
  });
}
