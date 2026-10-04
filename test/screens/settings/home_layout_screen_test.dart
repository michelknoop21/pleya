import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/automation/automation_registry.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/continue_watching_hidden_provider.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/screens/settings/home_layout_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/continue_watching_hidden_items.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const _verifyOn = bool.fromEnvironment('PLEYA_VERIFY');

class _DiscoverRows extends ChangeNotifier implements DiscoverProvider {
  @override
  List<MediaHub> get hubs => const [
    MediaHub(
      id: 'films',
      identifier: 'recent.movies',
      title: 'Recent toegevoegd',
      type: 'movie',
      items: [],
      serverId: 'zolder',
      serverName: 'Zolder',
    ),
    MediaHub(
      id: 'series',
      identifier: 'recent.shows',
      title: 'Recent toegevoegd',
      type: 'show',
      items: [],
      serverId: 'zolder',
      serverName: 'Zolder',
    ),
    MediaHub(
      id: 'latest-shows',
      identifier: 'home.latestshows',
      title: 'Recent toegevoegde series',
      type: 'show',
      items: [],
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('TV-kop en rijacties blijven binnen de veilige paginamarge', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    resetSharedPreferencesForTest();
    final layout = HomeLayoutProvider();
    await layout.ensureInitialized();
    addTearDown(layout.dispose);
    final discover = _DiscoverRows();
    addTearDown(discover.dispose);

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<HomeLayoutProvider>.value(value: layout),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ],
          child: MaterialApp(theme: monoTheme(dark: true), home: const HomeLayoutScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getRect(find.text(t.settings.homeLayout)).left, greaterThanOrEqualTo(48));
    expect(tester.getRect(find.byType(Switch).first).right, lessThanOrEqualTo(1920 - 48));
    if (_verifyOn) {
      final declared = AutomationRegistry.instance.snapshot()['declared'] as List<dynamic>;
      expect(declared.where((node) => node['id'] == 'my_pleya.section.content[home_layout]'), hasLength(1));
    }
  });

  testWidgets('gelijke rijtitels tonen films en series als afzonderlijke context', (tester) async {
    resetSharedPreferencesForTest();
    final layout = HomeLayoutProvider();
    await layout.ensureInitialized();
    addTearDown(layout.dispose);
    final discover = _DiscoverRows();
    addTearDown(discover.dispose);

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<HomeLayoutProvider>.value(value: layout),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ],
          child: const MaterialApp(home: HomeLayoutScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recent toegevoegd'), findsNWidgets(2));
    expect(find.text('${t.search.filters.movies} · Zolder'), findsOneWidget);
    expect(find.text('${t.search.filters.shows} · Zolder'), findsOneWidget);
    expect(find.text(t.search.filters.shows), findsNothing);
  });

  testWidgets('Verborgen items staat onder de rijen zodra er iets verborgen is (DEC-145)', (tester) async {
    resetSharedPreferencesForTest();
    final layout = HomeLayoutProvider();
    await layout.ensureInitialized();
    addTearDown(layout.dispose);
    final discover = _DiscoverRows();
    addTearDown(discover.dispose);
    final hidden = (await tester.runAsync(() async {
      final provider = ContinueWatchingHiddenProvider();
      await provider.ensureInitialized();
      await provider.hide(
        MediaItem(id: 'f1', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: 'Sintel', serverId: 'nas'),
      );
      return provider;
    }))!;
    addTearDown(hidden.dispose);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget app({required bool withHidden}) => TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeLayoutProvider>.value(value: layout),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          if (withHidden) ChangeNotifierProvider<ContinueWatchingHiddenProvider>.value(value: hidden),
        ],
        child: const MaterialApp(home: HomeLayoutScreen()),
      ),
    );

    await tester.pumpWidget(app(withHidden: false));
    await tester.pump();
    expect(find.textContaining(t.discover.hiddenItems), findsNothing);

    await tester.pumpWidget(app(withHidden: true));
    await tester.pump();
    expect(find.text(continueWatchingHiddenLabel(1)), findsOneWidget);
  });

  group('unified rijen op iPhone en TV (DEC-145)', () {
    Future<({HomeLayoutProvider layout, ContinueWatchingHiddenProvider hidden})> pumpUnified(
      WidgetTester tester, {
      required bool tv,
      bool hideOne = false,
    }) async {
      resetSharedPreferencesForTest();
      final providers = (await tester.runAsync(() async {
        final layout = HomeLayoutProvider();
        await layout.ensureInitialized();
        final hidden = ContinueWatchingHiddenProvider();
        await hidden.ensureInitialized();
        if (hideOne) {
          await hidden.hide(
            MediaItem(
              id: 'f1',
              backend: MediaBackend.jellyfin,
              kind: MediaKind.movie,
              title: 'Sintel',
              serverId: 'nas',
            ),
          );
        }
        return (layout: layout, hidden: hidden);
      }))!;
      addTearDown(providers.layout.dispose);
      addTearDown(providers.hidden.dispose);
      final discover = _DiscoverRows();
      addTearDown(discover.dispose);
      final projection = _UnifiedRows();
      addTearDown(projection.dispose);

      if (tv) {
        TvDetectionService.debugSetAppleTVOverride(true);
        addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
      } else {
        // An iPhone: 393x852 points at 3x, which `PlatformDetector.isPhone`
        // reads as a phone rather than a tablet.
        tester.view.physicalSize = const Size(1179, 2556);
        tester.view.devicePixelRatio = 3;
      }
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<HomeLayoutProvider>.value(value: providers.layout),
              ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
              ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: projection),
              ChangeNotifierProvider<ContinueWatchingHiddenProvider>.value(value: providers.hidden),
            ],
            child: MaterialApp(theme: monoTheme(dark: true), home: const HomeLayoutScreen()),
          ),
        ),
      );
      await tester.pump();
      return providers;
    }

    testWidgets('iPhone toont de unified rijen en verbergt een samengevoegde rij op al zijn ids', (tester) async {
      final providers = await pumpUnified(tester, tv: false);

      // The unified list, not the legacy hubs `DiscoverProvider` would give.
      expect(find.text('Recent uitgebracht'), findsOneWidget);
      expect(find.text('Samengevoegd'), findsOneWidget);
      expect(find.text('Recent toegevoegde series'), findsNothing);

      final mergedSwitch = find.descendant(
        of: find.widgetWithText(ListTile, 'Samengevoegd'),
        matching: find.byType(Switch),
      );
      await tester.tap(mergedSwitch);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      expect(providers.layout.isRowHidden('zolder:recent'), isTrue);
      expect(providers.layout.isRowHidden('nas:recent'), isTrue);
      expect(providers.layout.isRowHidden('zolder:top'), isFalse);
      expect(tester.widget<Switch>(mergedSwitch).value, isFalse);
    });

    testWidgets('TV verplaatst een samengevoegde rij met al zijn ids, en Verborgen items is een tegel', (tester) async {
      final providers = await pumpUnified(tester, tv: true, hideOne: true);

      final down = find.descendant(
        of: find.widgetWithText(ListTile, 'Samengevoegd'),
        matching: find.widgetWithIcon(IconButton, Symbols.arrow_downward_rounded),
      );
      await tester.tap(down);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();

      // Recent uitgebracht stays first; the merged row moved under Top Picks
      // and took both of its ids with it, side by side.
      expect(providers.layout.order, [':pleya:home:latest-movies', 'zolder:top', 'zolder:recent', 'nas:recent']);

      final label = find.text(continueWatchingHiddenLabel(1));
      expect(label, findsOneWidget);
      final surface = tester.widget<Material>(find.ancestor(of: label, matching: find.byType(Material)).first);
      final rowSurface = tester.widget<Material>(
        find.ancestor(of: find.text('Samengevoegd'), matching: find.byType(Material)).first,
      );
      expect(surface.type, MaterialType.canvas);
      expect(surface.color, rowSurface.color, reason: 'the same tile fill as the rows above it');
      expect(surface.borderRadius, rowSurface.borderRadius);
      expect(tester.getTopLeft(label).dy, greaterThan(tester.getTopLeft(find.text('Top Picks')).dy));
    });
  });
}

/// Three unified rows as the Home projection hands them out: Recent
/// uitgebracht, a row merged from two servers, and a single-server row.
class _UnifiedRows extends ChangeNotifier implements TvHomeProjectionProvider {
  @override
  UnifiedMediaHub? get latestMovies => UnifiedMediaHub(
    hubId: 'pleya:home:latest-movies',
    title: 'Recent uitgebracht',
    kind: UnifiedHubKind.movie,
    groups: const [],
    contributingRowIds: const [':pleya:home:latest-movies'],
  );

  @override
  List<UnifiedMediaHub> get hubs => [
    UnifiedMediaHub(
      hubId: 'merged',
      title: 'Samengevoegd',
      kind: UnifiedHubKind.show,
      groups: const [],
      contributingRowIds: const ['zolder:recent', 'nas:recent'],
    ),
    UnifiedMediaHub(
      hubId: 'top',
      title: 'Top Picks',
      kind: UnifiedHubKind.movie,
      groups: const [],
      contributingRowIds: const ['zolder:top'],
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
