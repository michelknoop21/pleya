import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_node.dart';
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
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/tv_catalog_artwork.dart';

class _Client implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('plex');
  @override
  String get serverName => 'plex';
  @override
  MediaBackend get backend => MediaBackend.plex;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> fetchCollections(String libraryId) async => [
    MediaItem(
      id: 'c1',
      backend: MediaBackend.plex,
      kind: MediaKind.collection,
      title: 'Own cover',
      serverId: 'plex',
      thumbPath: TvGoldenArtwork.pathFor(1),
      artPath: TvGoldenArtwork.pathFor(2),
    ),
  ];

  @override
  Future<List<MediaPlaylist>> fetchPlaylists({String playlistType = 'video', bool? smart}) async => const [];

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  testWidgets('a focused card never draws a blurred artwork layer behind the page', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TvDetectionService.debugSetAppleTVOverride(true);
    TvGoldenArtwork.install();
    addTearDown(() {
      TvDetectionService.debugSetAppleTVOverride(null);
      TvGoldenArtwork.remove();
    });

    final manager = MultiServerManager()..debugRegisterClientForTesting(_Client());
    final multi = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: 'movies',
          backend: MediaBackend.plex,
          title: 'movies',
          kind: MediaKind.movie,
          serverId: 'plex',
          serverName: 'plex',
        ),
      ]);
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
    expect(find.text('Own cover'), findsOneWidget);

    // Focus the card and let the old 150 ms selection settle timer elapse.
    tester.binding.focusManager.rootScope.descendants
        .firstWhere((node) => node.debugLabel?.startsWith('tvcollections') ?? false)
        .requestFocus();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(ImageFiltered), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is AutomationNode && widget.id == 'library.atmosphere'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
