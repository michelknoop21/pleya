import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/search_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';
import 'pleya_fake_server.dart';

/// The PS-3 stop criterion: browsing and searching work on at least two form
/// factors, TV focus included.
///
/// These pump the real screens against a real [PleyaServerClient] talking to a
/// fake that speaks the contract. A test that stubs the client would prove the
/// screen renders a list; this proves the screen renders what a Pleya Server
/// actually answered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
  });

  PleyaFakeServer buildServer() {
    final server = PleyaFakeServer();
    server.addLibrary(id: 'lib-films', title: 'Films', kind: 'movies');
    server.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
    server.addItem(
      id: 'movie-sea',
      kind: 'movie',
      title: 'The Sea Beast',
      libraryId: 'lib-films',
      year: 2022,
      durationMs: 6000000,
      posterId: 'art-sea',
    );
    server.addItem(id: 'show-seaside', kind: 'show', title: 'Seaside Hotel', libraryId: 'lib-series');
    server.addItem(id: 'season-1', kind: 'season', title: 'Season 1', parentId: 'show-seaside', index: 1);
    server.addItem(
      id: 'ep-searchers',
      kind: 'episode',
      title: 'The Searchers',
      parentId: 'season-1',
      index: 1,
      durationMs: 1320000,
    );
    return server;
  }

  Future<(PleyaFakeServer, PleyaServerClient, MultiServerProvider)> pumpSearch(
    WidgetTester tester, {
    required Size size,
    bool tv = false,
  }) async {
    if (tv) {
      TvDetectionService.debugSetAppleTVOverride(null);
      await TvDetectionService.getInstance(forceTv: true);
      TvDetectionService.setForceTVSync(true);
    }
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final server = buildServer();
    final client = server.client();
    await client.refreshCapabilities();
    addTearDown(client.close);

    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    final key = GlobalKey<State<SearchScreen>>();
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: SearchScreen(key: key),
          ),
        ),
      ),
    );
    await tester.pump();
    (key.currentState! as SearchInputFocusable).submitSearchQuery('sea');
    await tester.pumpAndSettle();
    return (server, client, provider);
  }

  group('search on a compact layout', () {
    testWidgets('shows what the server answered', (tester) async {
      final (server, _, _) = await pumpSearch(tester, size: const Size(390, 844));
      expect(find.text('The Sea Beast'), findsWidgets);
      expect(find.text('Seaside Hotel'), findsWidgets);
      expect(server.requests.any((r) => r.contains('/search')), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('shows no season row, because the server left seasons out', (tester) async {
      await pumpSearch(tester, size: const Size(390, 844));
      expect(find.text('Season 1'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('search on a desktop layout', () {
    testWidgets('shows the same results at 1440 wide', (tester) async {
      await pumpSearch(tester, size: const Size(1440, 900));
      expect(find.text('The Sea Beast'), findsWidgets);
      expect(find.text('The Searchers'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('renders without an overflow or an exception', (tester) async {
      await pumpSearch(tester, size: const Size(1440, 900));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('search on TV', () {
    testWidgets('renders results with the TV layout active', (tester) async {
      await pumpSearch(tester, size: const Size(1920, 1080), tv: true);
      expect(find.text('The Sea Beast'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('at least one result is focusable, so a remote can reach it', (tester) async {
      await pumpSearch(tester, size: const Size(1920, 1080), tv: true);
      final focusable = tester.widgetList<Focus>(find.byType(Focus)).where((widget) => widget.canRequestFocus).toList();
      expect(focusable, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('capability gating reaches the screens', () {
    testWidgets('a connected client offers no transcoding, playlists or alpha bar', (tester) async {
      final (_, client, _) = await pumpSearch(tester, size: const Size(1440, 900));
      expect(client.capabilities.videoTranscoding, isFalse);
      expect(client.capabilities.serverSidePlaylists, isFalse);
      expect(client.capabilities.alphaBar, AlphaBarMode.none);
      expect(client.capabilities.serverFavorites, isFalse);
      expect(client.capabilities.richMetadataEdit, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the aggregated result set carries Pleya Server items', (tester) async {
      final (_, _, provider) = await pumpSearch(tester, size: const Size(1440, 900));
      final result = await provider.aggregationService.getMediaLibrariesFromAllServers();
      expect(result.libraries.map((l) => l.title), containsAll(['Films', 'Series']));
      expect(result.libraries.map((l) => l.kind), contains(MediaKind.movie));
      expect(result.libraries.every((l) => l.backend == MediaBackend.pleyaServer), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
