import 'dart:ui' show PointerDeviceKind;
import 'package:pleya/media/ids.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:pleya/widgets/side_navigation_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

const _testTokens = MonoTokens(
  radiusSm: 8,
  radiusMd: 12,
  space: 8,
  fast: Duration(milliseconds: 1),
  normal: Duration(milliseconds: 1),
  slow: Duration(milliseconds: 1),
  bg: Colors.black,
  surface: Colors.black,
  surfaceElevated: Color(0xFF2F2F2F),
  outline: Colors.white24,
  text: Colors.white,
  textMuted: Colors.white70,
  accent: Color(0xFFF42B1F),
  accentAlt: Color(0xFFFFB020),
  splashFactory: NoSplash.splashFactory,
);

MediaLibrary _library({
  required String id,
  required String title,
  required ServerId serverId,
  required String serverName,
}) {
  return MediaLibrary(
    id: id,
    backend: MediaBackend.plex,
    title: title,
    kind: MediaKind.movie,
    serverId: serverId,
    serverName: serverName,
  );
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

BoxDecoration? _railItemDecoration(WidgetTester tester, Finder item) {
  return tester.widget<Container>(find.descendant(of: item, matching: find.byType(Container)).first).decoration
      as BoxDecoration?;
}

/// The rail's surface is now a plain [ColoredBox] (non-TV, opaque) or a
/// gradient scrim (TV, no solid panel), so "surface opacity" is expressed as
/// presence/absence of the opaque surface fill rather than an animated opacity.
bool _hasOpaqueSurface(WidgetTester tester) {
  return find.byWidgetPredicate((w) => w is ColoredBox && w.color == _testTokens.surface).evaluate().isNotEmpty;
}

Future<void> _pumpBasicRail(
  WidgetTester tester, {
  GlobalKey<SideNavigationRailState>? sideNavKey,
  NavigationTabId selectedTab = NavigationTabId.discover,
  String? selectedLibraryKey,
  List<MediaLibrary> libraries = const [],
  bool isSidebarFocused = false,
  bool alwaysExpanded = false,
  double? height,
}) async {
  await SettingsService.getInstance();

  final librariesProvider = LibrariesProvider();
  if (libraries.isNotEmpty) {
    await librariesProvider.updateLibraryOrder(libraries);
  }
  addTearDown(librariesProvider.dispose);

  final hiddenLibrariesProvider = HiddenLibrariesProvider();
  await hiddenLibrariesProvider.ensureInitialized();
  addTearDown(hiddenLibrariesProvider.dispose);

  final manager = MultiServerManager();
  final aggregation = DataAggregationService(manager);
  final multiServerProvider = MultiServerProvider(manager, aggregation);
  addTearDown(multiServerProvider.dispose);

  final rail = SideNavigationRail(
    key: sideNavKey,
    selectedTab: selectedTab,
    selectedLibraryKey: selectedLibraryKey,
    isSidebarFocused: isSidebarFocused,
    alwaysExpanded: alwaysExpanded,
    onDestinationSelected: (_) {},
    onLibrarySelected: (_) {},
  );

  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [_testTokens]),
          home: Scaffold(
            body: height == null ? rail : SizedBox(height: height, child: rail),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('closed TV rail is slim and keeps primary icons centered', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await SettingsService.getInstance();

    final librariesProvider = LibrariesProvider();
    addTearDown(librariesProvider.dispose);

    final hiddenLibrariesProvider = HiddenLibrariesProvider();
    await hiddenLibrariesProvider.ensureInitialized();
    addTearDown(hiddenLibrariesProvider.dispose);

    final manager = MultiServerManager();
    final aggregation = DataAggregationService(manager);
    final multiServerProvider = MultiServerProvider(manager, aggregation);
    addTearDown(multiServerProvider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [_testTokens]),
            home: Scaffold(
              body: SideNavigationRail(
                selectedTab: NavigationTabId.discover,
                isSidebarFocused: false,
                alwaysExpanded: false,
                onDestinationSelected: (_) {},
                onLibrarySelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = find.descendant(of: find.byType(SideNavigationRail), matching: find.byType(AnimatedContainer)).first;
    expect(tester.getSize(rail).width, SideNavigationRailState.tvCollapsedWidth);

    final firstIconCenter = tester.getCenter(find.byType(NavGlyph).first).dx;
    expect(firstIconCenter - tester.getTopLeft(rail).dx, closeTo(SideNavigationRailState.tvCollapsedWidth / 2, 0.1));

    final selectedItem = find.byType(NavigationRailItem).first;
    final selectedItemContainer = tester.widget<Container>(
      find.descendant(of: selectedItem, matching: find.byType(Container)).first,
    );
    expect((selectedItemContainer.decoration as BoxDecoration?)?.color, isNull);

    expect(_hasOpaqueSurface(tester), isFalse);
  });

  testWidgets('closed non-TV rail keeps an opaque surface', (tester) async {
    await _pumpBasicRail(tester);

    final rail = find.descendant(of: find.byType(SideNavigationRail), matching: find.byType(AnimatedContainer)).first;
    expect(tester.getSize(rail).width, SideNavigationRailState.collapsedWidth);
    expect(_hasOpaqueSurface(tester), isTrue);
  });

  testWidgets('expanded TV rail keeps a transparent surface', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await SettingsService.getInstance();

    final librariesProvider = LibrariesProvider();
    addTearDown(librariesProvider.dispose);

    final hiddenLibrariesProvider = HiddenLibrariesProvider();
    await hiddenLibrariesProvider.ensureInitialized();
    addTearDown(hiddenLibrariesProvider.dispose);

    final manager = MultiServerManager();
    final aggregation = DataAggregationService(manager);
    final multiServerProvider = MultiServerProvider(manager, aggregation);
    addTearDown(multiServerProvider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [_testTokens]),
            home: Scaffold(
              body: SideNavigationRail(
                selectedTab: NavigationTabId.discover,
                isSidebarFocused: true,
                alwaysExpanded: false,
                onDestinationSelected: (_) {},
                onLibrarySelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = find.descendant(of: find.byType(SideNavigationRail), matching: find.byType(AnimatedContainer)).first;
    expect(tester.getSize(rail).width, SideNavigationRailState.expandedWidth);

    expect(_hasOpaqueSurface(tester), isFalse);
  });

  testWidgets('expanded rail keeps selected background outside sidebar keyboard focus', (tester) async {
    await _pumpBasicRail(tester, alwaysExpanded: true);

    final selectedItem = find.byType(NavigationRailItem).first;
    expect(_railItemDecoration(tester, selectedItem)?.color, _testTokens.text.withValues(alpha: 0.06));
  });

  testWidgets('D-pad sidebar focus hides selected item background after focus moves', (tester) async {
    final sideNavKey = GlobalKey<SideNavigationRailState>();
    await _pumpBasicRail(tester, sideNavKey: sideNavKey, isSidebarFocused: true, alwaysExpanded: true);

    sideNavKey.currentState!.focusActiveItem();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowDown);

    final selectedItem = find.byType(NavigationRailItem).first;
    expect(_railItemDecoration(tester, selectedItem)?.color, isNull);
  });

  testWidgets('focusActiveItem focuses selected library and scrolls it into view', (tester) async {
    final sideNavKey = GlobalKey<SideNavigationRailState>();
    final libraries = List.generate(
      18,
      (index) => _library(id: '$index', title: 'Library $index', serverId: ServerId('server'), serverName: 'Server'),
    );
    final targetLibrary = libraries.last;

    await _pumpBasicRail(
      tester,
      sideNavKey: sideNavKey,
      selectedTab: NavigationTabId.libraries,
      selectedLibraryKey: targetLibrary.globalKey,
      libraries: libraries,
      isSidebarFocused: true,
      alwaysExpanded: true,
      height: 260,
    );

    final scrollable = find.descendant(of: find.byType(SideNavigationRail), matching: find.byType(Scrollable)).first;
    final scrollableState = tester.state<ScrollableState>(scrollable);
    expect(scrollableState.position.pixels, 0);

    sideNavKey.currentState!.focusActiveItem();
    await tester.pump();
    await tester.pumpAndSettle();

    final targetItemFinder = find.widgetWithText(NavigationRailItem, targetLibrary.title);
    expect(targetItemFinder, findsOneWidget);
    final targetItem = tester.widget<NavigationRailItem>(targetItemFinder);
    expect(targetItem.focusNode.hasFocus, isTrue);
    expect(scrollableState.position.pixels, greaterThan(0));

    final railRect = tester.getRect(find.byType(SideNavigationRail));
    final targetRect = tester.getRect(find.text(targetLibrary.title));
    expect(targetRect.top, greaterThanOrEqualTo(railRect.top));
    expect(targetRect.bottom, lessThanOrEqualTo(railRect.bottom));
  });

  testWidgets('reports interaction expansion for shell content push', (tester) async {
    await SettingsService.getInstance();

    final librariesProvider = LibrariesProvider();
    addTearDown(librariesProvider.dispose);

    final hiddenLibrariesProvider = HiddenLibrariesProvider();
    await hiddenLibrariesProvider.ensureInitialized();
    addTearDown(hiddenLibrariesProvider.dispose);

    final manager = MultiServerManager();
    final aggregation = DataAggregationService(manager);
    final multiServerProvider = MultiServerProvider(manager, aggregation);
    addTearDown(multiServerProvider.dispose);

    final reports = <bool>[];

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [_testTokens]),
            home: Scaffold(
              body: SideNavigationRail(
                selectedTab: NavigationTabId.discover,
                isSidebarFocused: false,
                alwaysExpanded: false,
                onInteractionExpandedChanged: reports.add,
                onDestinationSelected: (_) {},
                onLibrarySelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rail = find.descendant(of: find.byType(SideNavigationRail), matching: find.byType(AnimatedContainer)).first;
    expect(tester.getSize(rail).width, SideNavigationRailState.collapsedWidth);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: const Offset(799, 599));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(rail));
    await tester.pumpAndSettle();

    expect(reports.last, isTrue);
    expect(tester.getSize(rail).width, SideNavigationRailState.expandedWidth);

    await gesture.moveTo(tester.getBottomRight(rail) + const Offset(100, -10));
    await tester.pump(const Duration(milliseconds: 200));

    expect(reports.last, isFalse);
  });

  testWidgets('Apple TV D-pad focus skips hidden downloads item', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    await SettingsService.getInstance();

    final librariesProvider = LibrariesProvider();
    addTearDown(librariesProvider.dispose);

    final hiddenLibrariesProvider = HiddenLibrariesProvider();
    await hiddenLibrariesProvider.ensureInitialized();
    addTearDown(hiddenLibrariesProvider.dispose);

    final manager = MultiServerManager();
    final aggregation = DataAggregationService(manager);
    final multiServerProvider = MultiServerProvider(manager, aggregation);
    addTearDown(multiServerProvider.dispose);

    final sideNavKey = GlobalKey<SideNavigationRailState>();
    NavigationTabId? selectedTab;

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [_testTokens]),
            home: Scaffold(
              body: SideNavigationRail(
                key: sideNavKey,
                selectedTab: NavigationTabId.discover,
                isSidebarFocused: true,
                alwaysExpanded: true,
                onDestinationSelected: (tab) => selectedTab = tab,
                onLibrarySelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    sideNavKey.currentState!.focusActiveItem();
    await tester.pumpAndSettle();

    // Home -> Libraries -> Search -> Settings. Downloads is hidden on Apple TV.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.enter);

    expect(selectedTab, NavigationTabId.settings);
  });

  testWidgets('hidden libraries are excluded from the rail; visible ones are pinned and reachable', (tester) async {
    await SettingsService.getInstance();

    final visibleServerALibrary = _library(
      id: '1',
      title: 'Visible Server A',
      serverId: ServerId('server-a'),
      serverName: 'Server A',
    );
    final hiddenServerALibrary = _library(
      id: '2',
      title: 'Hidden Server A',
      serverId: ServerId('server-a'),
      serverName: 'Server A',
    );
    final visibleServerBLibrary = _library(
      id: '1',
      title: 'Visible Server B',
      serverId: ServerId('server-b'),
      serverName: 'Server B',
    );

    final librariesProvider = LibrariesProvider();
    await librariesProvider.updateLibraryOrder([visibleServerALibrary, hiddenServerALibrary, visibleServerBLibrary]);
    addTearDown(librariesProvider.dispose);

    final hiddenLibrariesProvider = HiddenLibrariesProvider();
    await hiddenLibrariesProvider.ensureInitialized();
    await hiddenLibrariesProvider.hideLibrary(hiddenServerALibrary.globalKey);
    addTearDown(hiddenLibrariesProvider.dispose);

    final manager = MultiServerManager();
    final aggregation = DataAggregationService(manager);
    final multiServerProvider = MultiServerProvider(manager, aggregation);
    addTearDown(multiServerProvider.dispose);

    final sideNavKey = GlobalKey<SideNavigationRailState>();
    var selectedLibraryKey = '';

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [_testTokens]),
            home: Scaffold(
              body: SideNavigationRail(
                key: sideNavKey,
                selectedTab: NavigationTabId.discover,
                isSidebarFocused: true,
                alwaysExpanded: true,
                onDestinationSelected: (_) {},
                onLibrarySelected: (key) => selectedLibraryKey = key,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    sideNavKey.currentState!.focusActiveItem();
    await tester.pumpAndSettle();

    // Libraries are pinned flat (no "Media" expand button). With server grouping
    // the visible order is: Home -> Server A header -> visible A. The hidden
    // library is managed in Settings and never appears in the rail.
    await _press(tester, LogicalKeyboardKey.arrowDown); // Server A header
    await _press(tester, LogicalKeyboardKey.arrowDown); // visible Server A library
    await _press(tester, LogicalKeyboardKey.enter);

    expect(selectedLibraryKey, visibleServerALibrary.globalKey);

    // Walking the whole rail never surfaces the hidden library.
    for (var i = 0; i < 10; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(selectedLibraryKey, isNot(hiddenServerALibrary.globalKey));
    }
  });
}
