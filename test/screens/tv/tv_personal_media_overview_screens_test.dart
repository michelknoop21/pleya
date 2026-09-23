import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
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
import 'package:pleya/screens/tv/sections/tv_personal_media_overview_screens.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

class _Client implements MediaServerClient {
  _Client(this.id, this.backend);

  final String id;
  @override
  final MediaBackend backend;

  @override
  ServerId get serverId => ServerId(id);
  @override
  String get serverName => id;
  @override
  ServerCapabilities get capabilities =>
      backend == MediaBackend.plex ? ServerCapabilities.plex : ServerCapabilities.jellyfin;

  final Map<String, List<MediaItem>> collections = {};
  final List<MediaPlaylist> playlists = [];
  bool failCollections = false;

  @override
  Future<List<MediaItem>> fetchCollections(String libraryId) async {
    if (failCollections) throw StateError('offline');
    return collections[libraryId] ?? const [];
  }

  @override
  Future<List<MediaPlaylist>> fetchPlaylists({String playlistType = 'video', bool? smart}) async => playlists;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary _library(String server, String id) => MediaLibrary(
  id: id,
  backend: server == 'plex' ? MediaBackend.plex : MediaBackend.jellyfin,
  title: id,
  kind: MediaKind.movie,
  serverId: server,
  serverName: server,
);

MediaItem _collection(String server, String id) => MediaItem(
  id: id,
  backend: server == 'plex' ? MediaBackend.plex : MediaBackend.jellyfin,
  kind: MediaKind.collection,
  title: 'Shared name',
  serverId: server,
  serverName: server,
);

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('collections remain separate per library and have a focusable first tile', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final manager = MultiServerManager();
    final plex = _Client('plex', MediaBackend.plex)
      ..collections['movies'] = [_collection('plex', 'c1')]
      ..collections['family'] = [_collection('plex', 'c2')];
    manager.debugRegisterClientForTesting(plex);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()..debugSetLibraries([_library('plex', 'movies'), _library('plex', 'family')]);
    final personal = PersonalMediaProvider(multiServer: multiServer, libraries: libraries);
    await personal.load();
    addTearDown(() {
      personal.dispose();
      libraries.dispose();
      multiServer.dispose();
      manager.dispose();
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<PersonalMediaProvider>.value(
          value: personal,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: const Scaffold(body: TvCollectionsOverviewScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared name'), findsNWidgets(2));
    expect(find.text('movies'), findsWidgets);
    expect(find.text('family'), findsWidgets);
    expect(tester.takeException(), isNull);

    tester.state<TvCollectionsOverviewScreenState>(find.byType(TvCollectionsOverviewScreen)).focusActiveTabIfReady();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'plex:movies:c1');
  });

  testWidgets('a failed collection source does not hide playlists from another server', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final manager = MultiServerManager();
    final plex = _Client('plex', MediaBackend.plex)..failCollections = true;
    final jellyfin = _Client('jellyfin', MediaBackend.jellyfin)
      ..playlists.add(
        const MediaPlaylist(
          id: 'p1',
          backend: MediaBackend.jellyfin,
          title: 'Weekend',
          playlistType: 'video',
          serverId: 'jellyfin',
          serverName: 'jellyfin',
        ),
      );
    manager
      ..debugRegisterClientForTesting(plex)
      ..debugRegisterClientForTesting(jellyfin);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()..debugSetLibraries([_library('plex', 'movies')]);
    final personal = PersonalMediaProvider(multiServer: multiServer, libraries: libraries);
    await personal.load();
    addTearDown(() {
      personal.dispose();
      libraries.dispose();
      multiServer.dispose();
      manager.dispose();
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<PersonalMediaProvider>.value(
          value: personal,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: const Scaffold(body: TvPlaylistsOverviewScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Weekend'), findsOneWidget);
    expect(find.text(t.playlists.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
