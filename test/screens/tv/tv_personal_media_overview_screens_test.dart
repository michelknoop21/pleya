import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
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
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/tv_catalog_artwork.dart';

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
  final Map<String, List<MediaItem>> members = {};
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
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String id, {
    int? start,
    int? size,
    AbortController? abort,
    String? libraryId,
    String? libraryTitle,
  }) async => LibraryPage(items: members[id] ?? [], totalCount: members[id]?.length ?? 0);

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
  setUpAll(loadAppFontsForGoldens);
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('production collection overview presents covers without merging source objects', (tester) async {
    setGoldenSurfaceSize(tester);
    TvDetectionService.debugSetAppleTVOverride(true);
    TvGoldenArtwork.install();
    addTearDown(() {
      TvDetectionService.debugSetAppleTVOverride(null);
      TvGoldenArtwork.remove();
    });
    final manager = MultiServerManager();
    final client = _Client('plex', MediaBackend.plex);
    client.collections['movies'] = [
      for (var count = 1; count <= 4; count++)
        MediaItem(
          id: 'c$count',
          backend: MediaBackend.plex,
          kind: MediaKind.collection,
          title: '$count films',
          serverId: 'plex',
          leafCount: count,
        ),
      MediaItem(
        id: 'own',
        backend: MediaBackend.plex,
        kind: MediaKind.collection,
        title: 'Own cover',
        serverId: 'plex',
        thumbPath: TvGoldenArtwork.pathFor(4),
      ),
    ];
    for (var count = 1; count <= 4; count++) {
      client.members['c$count'] = [
        for (var i = 0; i < count; i++)
          MediaItem(
            id: 'm$i',
            backend: MediaBackend.plex,
            kind: MediaKind.movie,
            title: 'Film $i',
            serverId: 'plex',
            thumbPath: TvGoldenArtwork.pathFor(i),
          ),
      ];
    }
    manager.debugRegisterClientForTesting(client);
    final multi = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()..debugSetLibraries([_library('plex', 'movies')]);
    final personal = PersonalMediaProvider(multiServer: multi, libraries: libraries);
    addTearDown(() {
      personal.dispose();
      libraries.dispose();
      multi.dispose();
      manager.dispose();
    });
    await personal.load();
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<PersonalMediaProvider>.value(value: personal),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multi),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: const Scaffold(body: TvCollectionsOverviewScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 films'), findsOneWidget);
    expect(find.text('Own cover'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('LIBRARY_CAPTURE')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../.build/reports/library-screenshots/tv-collections-production.png'),
      );
    }
  });

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
    final visible = ValueNotifier(true);
    final elsewhere = FocusNode();
    addTearDown(visible.dispose);
    addTearDown(elsewhere.dispose);
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
            home: Scaffold(
              body: Column(
                children: [
                  TextButton(focusNode: elsewhere, onPressed: () {}, child: const Text('Other destination')),
                  Expanded(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: visible,
                      builder: (_, enabled, _) =>
                          TickerMode(enabled: enabled, child: const TvCollectionsOverviewScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shared name'), findsNWidgets(2));
    expect(find.byType(TvCatalogCard), findsNWidgets(2));
    expect(find.text('plex · movies'), findsWidgets);
    expect(find.text('plex · family'), findsWidgets);
    expect(tester.takeException(), isNull);

    tester.state<TvCollectionsOverviewScreenState>(find.byType(TvCollectionsOverviewScreen)).focusActiveTabIfReady();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvcollections(plex:movies:c1)');
    visible.value = false;
    await tester.pump();
    elsewhere.requestFocus();
    await tester.pump();
    tester.state<TvCollectionsOverviewScreenState>(find.byType(TvCollectionsOverviewScreen)).focusActiveTabIfReady();
    await tester.pump();
    expect(elsewhere.hasFocus, isTrue, reason: 'an offstage refresh cannot take focus from another destination');
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
