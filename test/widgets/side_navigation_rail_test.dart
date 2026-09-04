import 'dart:ui' show PointerDeviceKind;
import 'package:pleya/media/ids.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/media/watch_session.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/now_watching_provider.dart';
import 'package:pleya/screens/now_watching_screen.dart';
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
  isLight: false,
  accent: Color(0xFFF42B1F),
  accentAlt: Color(0xFFFFB020),
  splashFactory: NoSplash.splashFactory,
);

/// [_testTokens] with real motion. The 1ms durations above make the expand and
/// collapse animations instantaneous, and the pointer-ownership tests below are
/// entirely about what happens *during* those 200ms.
const _motionTokens = MonoTokens(
  radiusSm: 8,
  radiusMd: 12,
  space: 8,
  fast: Duration(milliseconds: 120),
  normal: Duration(milliseconds: 200),
  slow: Duration(milliseconds: 300),
  bg: Colors.black,
  surface: Colors.black,
  surfaceElevated: Color(0xFF2F2F2F),
  outline: Colors.white24,
  text: Colors.white,
  textMuted: Colors.white70,
  isLight: false,
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

/// The rail over a full-bleed tap recorder, in the same order as
/// [main_screen.dart]'s Stack: content first, rail on top at left: 0. Returns a
/// reader for the number of taps that reached the content underneath.
///
/// What the stand-in content underneath the rail received. Two separate
/// receivers, because the two failures are opposites: the hero must never be
/// activated by a navigation interaction, and the control must never *stop*
/// being reachable because the rail reserved the strip it sits in.
class _ContentProbe {
  int heroTaps = 0;
  int controlTaps = 0;
  int controlHovers = 0;
}

/// Centre of [_ContentProbe.controlTaps]' receiver: a content control sitting in
/// the strip between the collapsed and the expanded rail, where a library page
/// puts Recommended/Browse/Collections.
const _contentControlCenter = Offset(150, 300);

/// The contract these tests hold is not "the box is N wide" but "one interaction
/// with the navigation never does something in the content underneath", so they
/// tap coordinates and count what arrives, and never read the rail's private
/// state or its hit-test flags.
Future<_ContentProbe> _pumpRailOverContent(
  WidgetTester tester, {
  MonoTokens themeTokens = _testTokens,
  List<NavigationTabId>? selected,
}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await SettingsService.getInstance();

  final librariesProvider = LibrariesProvider();
  addTearDown(librariesProvider.dispose);
  final hiddenLibrariesProvider = HiddenLibrariesProvider();
  await hiddenLibrariesProvider.ensureInitialized();
  addTearDown(hiddenLibrariesProvider.dispose);
  final manager = MultiServerManager();
  final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
  addTearDown(multiServerProvider.dispose);

  final probe = _ContentProbe();

  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [themeTokens]),
          home: Scaffold(
            body: Stack(
              children: [
                // Stand-in for the discover billboard: opaque and full bleed,
                // exactly like the hero's GestureDetector.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => probe.heroTaps++,
                    child: const SizedBox.expand(),
                  ),
                ),
                // Stand-in for a control the content puts right beside the shut
                // rail, such as the Recommended tab on a library page.
                Positioned(
                  left: _contentControlCenter.dx - 30,
                  top: _contentControlCenter.dy - 22,
                  width: 60,
                  height: 44,
                  child: MouseRegion(
                    onEnter: (_) => probe.controlHovers++,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => probe.controlTaps++,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  child: SideNavigationRail(
                    selectedTab: NavigationTabId.discover,
                    onDestinationSelected: (tab) => selected?.add(tab),
                    onLibrarySelected: (_) {},
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
  return probe;
}

/// Width of the panel as painted right now.
double _railPaintedWidth(WidgetTester tester) => tester
    .getSize(find.descendant(of: find.byType(SideNavigationRail), matching: find.byType(AnimatedContainer)).first)
    .width;

/// Enters from a corner far outside the band, so [target] produces a real
/// pointer-enter rather than an ambiguous first position.
Future<TestGesture> _hoverAt(WidgetTester tester, Offset target) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(gesture.removePointer);
  await gesture.addPointer(location: const Offset(1279, 719));
  await tester.pump();
  await gesture.moveTo(target);
  await tester.pump();
  return gesture;
}

/// A row that is always present, whatever the server config.
double _searchRowY(WidgetTester tester) =>
    tester.getCenter(find.widgetWithText(NavigationRailItem, t.common.search)).dy;

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

    // Downloads is hidden on Apple TV and fase 5 added the two unified
    // catalogs, so the rail is Home -> Films -> Series -> Search -> Settings
    // and Settings is exactly four steps down. Pressing a fifth time would
    // prove nothing: on macOS it saturates on the last item, but on Windows and
    // Linux the fullscreen toggle sits after Settings and swallows it, and
    // Enter there never reaches onDestinationSelected.
    await _press(tester, LogicalKeyboardKey.arrowDown);
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

  group('pointer ownership: the band between the collapsed and expanded rail', () {
    // x=150 sits in the strip that is menu when the rail is open and content
    // when it is shut. Who owns it must follow from what the user can see, not
    // from hover history and not from a width the rail might reach later.
    const bandX = 150.0;
    // Outside what the panel paints 60ms into a 200ms easeOutCubic (~172px),
    // so the mid-animation probes are not vacuous.
    const probeX = SideNavigationRailState.expandedWidth - 10;

    testWidgets('a tap on the collapsed rail never reaches the content underneath', (tester) async {
      final selected = <NavigationTabId>[];
      final probe = await _pumpRailOverContent(tester, selected: selected);
      expect(_railPaintedWidth(tester), SideNavigationRailState.collapsedWidth);

      await tester.tapAt(Offset(40, _searchRowY(tester)));
      await tester.pumpAndSettle();

      expect(probe.heroTaps, 0);
      expect(selected, isEmpty, reason: 'the first touch opens the rail, it does not navigate');
      expect(_railPaintedWidth(tester), SideNavigationRailState.expandedWidth);
    });

    testWidgets('a shut rail does not reserve the band: content there stays hoverable and clickable', (tester) async {
      // The regression this pins: claiming everything up to the expanded width
      // the moment a pointer entered it made the Recommended tab on a library
      // page unreachable on macOS. Approaching it opened the menu, which then
      // swallowed the click and slid the tab out from under the cursor.
      final probe = await _pumpRailOverContent(tester);
      expect(_railPaintedWidth(tester), SideNavigationRailState.collapsedWidth);

      // Straight at the control from the far corner. The pointer never crosses
      // the collapsed rail, so nothing has activated the navigation.
      await _hoverAt(tester, _contentControlCenter);
      await tester.pumpAndSettle();

      expect(
        _railPaintedWidth(tester),
        SideNavigationRailState.collapsedWidth,
        reason: 'hovering content beside a shut rail is not entering the menu',
      );
      expect(probe.controlHovers, 1, reason: 'the control must still see the pointer');

      await tester.tapAt(_contentControlCenter);
      await tester.pumpAndSettle();

      expect(probe.controlTaps, 1);
      expect(probe.heroTaps, 0);
    });

    testWidgets('entering over the rail hands it the band, and the pointer cannot outrun it', (tester) async {
      // The opposite failure, and the reason the band exists at all: once the
      // user is genuinely in the menu, racing ahead of the easeOutCubic must not
      // drop the pointer back onto the content and start the collapse timer.
      final selected = <NavigationTabId>[];
      final probe = await _pumpRailOverContent(tester, themeTokens: _motionTokens, selected: selected);
      final y = _searchRowY(tester);

      final gesture = await _hoverAt(tester, Offset(40, y));
      await tester.pump(const Duration(milliseconds: 60));

      final painted = _railPaintedWidth(tester);
      expect(painted, lessThan(probeX), reason: 'the pointer must arrive ahead of the paint for this to mean anything');

      await gesture.moveTo(Offset(probeX, y));
      await tester.pumpAndSettle();

      expect(_railPaintedWidth(tester), SideNavigationRailState.expandedWidth);

      await tester.tapAt(Offset(bandX, y));
      await tester.pumpAndSettle();

      expect(selected, [NavigationTabId.search]);
      expect(probe.heroTaps, 0);
    });

    testWidgets('a tap while the rail is opening never reaches the content underneath', (tester) async {
      final probe = await _pumpRailOverContent(tester, themeTokens: _motionTokens);
      final y = _searchRowY(tester);

      await _hoverAt(tester, Offset(40, y));
      await tester.pump(const Duration(milliseconds: 60));

      final painted = _railPaintedWidth(tester);
      expect(painted, greaterThan(SideNavigationRailState.collapsedWidth));
      expect(painted, lessThan(probeX), reason: 'the probe must sit outside what the panel paints');

      await tester.tapAt(Offset(probeX, y));
      await tester.pumpAndSettle();

      expect(probe.heroTaps, 0);
    });

    testWidgets('a row stays live while the rail is closing over it', (tester) async {
      // Race 2: the collapse timer flipped the rail to "collapsed" instantly and
      // killed every row, while the panel stood at full width for another 200ms.
      // A click on a plainly visible menu item then did nothing, or slipped past
      // the shrinking edge into the content.
      final selected = <NavigationTabId>[];
      final probe = await _pumpRailOverContent(tester, themeTokens: _motionTokens, selected: selected);
      final y = _searchRowY(tester);

      final gesture = await _hoverAt(tester, Offset(40, y));
      await tester.pumpAndSettle();
      expect(_railPaintedWidth(tester), SideNavigationRailState.expandedWidth);

      await gesture.moveTo(Offset(900, y));
      await tester.pump(const Duration(milliseconds: 150)); // the collapse delay
      await tester.pump(const Duration(milliseconds: 60)); // 60 of the 200ms collapse

      final painted = _railPaintedWidth(tester);
      expect(painted, greaterThan(SideNavigationRailState.collapsedWidth));
      expect(painted, lessThan(SideNavigationRailState.expandedWidth));

      // A row as it stands right now, well inside what the panel still paints,
      // so this is something the user can still see.
      final row = find.byType(NavigationRailItem).at(1);
      final rowRect = tester.getRect(row);
      await tester.tapAt(Offset(painted - 30, rowRect.center.dy));
      await tester.pumpAndSettle();

      expect(selected, isNotEmpty, reason: 'a visible row is a live row');
      expect(probe.heroTaps, 0);
    });

    testWidgets('a settled collapsed rail leaves the band clickable', (tester) async {
      // The guard against over-fixing: no permanent dead zone over the content.
      // tapAt synthesizes a touch pointer, so no hover precedes it, so the rail is
      // shut and x=$bandX is genuinely content.
      final probe = await _pumpRailOverContent(tester);
      expect(_railPaintedWidth(tester), SideNavigationRailState.collapsedWidth);

      await tester.tapAt(const Offset(bandX, 300));
      await tester.pumpAndSettle();

      expect(probe.controlTaps, 1);
      expect(_railPaintedWidth(tester), SideNavigationRailState.collapsedWidth);
    });
  });

  group('remote ownership: a sidebar Select never leaks into the content', () {
    // On tvOS the engine hands KeyDown and KeyUp to Flutter back to back, and
    // the rail moves focus into the content inside its own KeyDown handler
    // (main_screen's onDestinationSelected calls _focusContent). The paired
    // KeyUp therefore arrives at whatever the content just focused. It must not
    // count as an activation there.
    Future<({List<NavigationTabId> selected, List<String> contentSelects})> pumpRailAndContent(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await SettingsService.getInstance();
      final librariesProvider = LibrariesProvider();
      addTearDown(librariesProvider.dispose);
      final hiddenLibrariesProvider = HiddenLibrariesProvider();
      await hiddenLibrariesProvider.ensureInitialized();
      addTearDown(hiddenLibrariesProvider.dispose);
      final manager = MultiServerManager();
      final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(multiServerProvider.dispose);

      final selected = <NavigationTabId>[];
      final contentSelects = <String>[];
      final contentNode = FocusNode(debugLabel: 'content');
      addTearDown(contentNode.dispose);
      final railNode = FocusNode(debugLabel: 'railItem');
      addTearDown(railNode.dispose);

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
                body: Row(
                  children: [
                    SideNavigationRail(
                      selectedTab: NavigationTabId.discover,
                      isSidebarFocused: true,
                      onDestinationSelected: (tab) {
                        selected.add(tab);
                        // Exactly what main_screen does: hand focus to the
                        // content in the same gesture.
                        contentNode.requestFocus();
                      },
                      onLibrarySelected: (_) {},
                    ),
                    Expanded(
                      // Stands in for the hero's play pill: a real
                      // FocusableWrapper, the same one the TV hero uses.
                      child: FocusableWrapper(
                        focusNode: contentNode,
                        onSelect: () => contentSelects.add('play'),
                        child: const SizedBox.expand(),
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

      final item = find.widgetWithText(NavigationRailItem, t.common.search);
      tester.widget<NavigationRailItem>(item).focusNode.requestFocus();
      await tester.pumpAndSettle();

      return (selected: selected, contentSelects: contentSelects);
    }

    testWidgets('Select on a focused sidebar item runs the sidebar action only', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      final recorded = await pumpRailAndContent(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(recorded.selected, [NavigationTabId.search]);
      expect(recorded.contentSelects, isEmpty);
    });

    testWidgets('the key-up of that same press is not an activation in the content', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      final recorded = await pumpRailAndContent(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      // Focus is in the content now; the release of the press that moved it
      // must not act there.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(recorded.selected, [NavigationTabId.search], reason: 'the sidebar acted once');
      expect(recorded.contentSelects, isEmpty, reason: 'one press, one action');
    });

    testWidgets('moving focus from the sidebar into the content activates nothing', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      final recorded = await pumpRailAndContent(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(recorded.contentSelects, isEmpty);
      expect(recorded.selected, isEmpty);
    });
  });

  group('now watching: a conditional row is reachable, not just rendered', () {
    // The row is TV-only and comes and goes with the streams. It was rendered
    // while its focus key was missing from both the whitelist and the D-pad
    // order, so it was painted, its node was disposed on every rebuild, and
    // up/down walked straight past it. These tests are the fence around that.

    Future<({_FakeNowWatching now, List<NavigationTabId> selected, List<String> contentSelects})> pumpTvRail(
      WidgetTester tester, {
      bool hasOthers = true,
      bool alwaysExpanded = true,
      bool isSidebarFocused = true,
    }) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      await SettingsService.getInstance();

      final librariesProvider = LibrariesProvider();
      addTearDown(librariesProvider.dispose);
      final hiddenLibrariesProvider = HiddenLibrariesProvider();
      await hiddenLibrariesProvider.ensureInitialized();
      addTearDown(hiddenLibrariesProvider.dispose);
      final manager = MultiServerManager();
      final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(multiServerProvider.dispose);

      final nowWatching = _FakeNowWatching()..setOthers(hasOthers);
      addTearDown(nowWatching.dispose);

      final selected = <NavigationTabId>[];
      final contentSelects = <String>[];
      final contentNode = FocusNode(debugLabel: 'content');
      addTearDown(contentNode.dispose);

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
              ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
              ChangeNotifierProvider<NowWatchingProvider>.value(value: nowWatching),
            ],
            child: MaterialApp(
              theme: ThemeData(extensions: const [_testTokens]),
              home: Scaffold(
                body: Row(
                  children: [
                    SideNavigationRail(
                      selectedTab: NavigationTabId.discover,
                      isSidebarFocused: isSidebarFocused,
                      alwaysExpanded: alwaysExpanded,
                      onDestinationSelected: (tab) {
                        selected.add(tab);
                        contentNode.requestFocus();
                      },
                      onLibrarySelected: (_) {},
                    ),
                    Expanded(
                      child: FocusableWrapper(
                        focusNode: contentNode,
                        onSelect: () => contentSelects.add('play'),
                        child: const SizedBox.expand(),
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

      return (now: nowWatching, selected: selected, contentSelects: contentSelects);
    }

    void focusRow(WidgetTester tester, String label) {
      tester.widget<NavigationRailItem>(find.widgetWithText(NavigationRailItem, label)).focusNode.requestFocus();
    }

    bool rowHasFocus(WidgetTester tester, String label) =>
        tester.widget<NavigationRailItem>(find.widgetWithText(NavigationRailItem, label)).focusNode.hasFocus;

    testWidgets('without the row the existing order and navigation are unchanged', (tester) async {
      final recorded = await pumpTvRail(tester, hasOthers: false);

      expect(find.widgetWithText(NavigationRailItem, t.nowWatching.sidebarLabel), findsNothing);

      // Downloads is hidden on Apple TV and fase 5 added Films and Series, so
      // the rail is Home, Films, Series, Search, Settings.
      focusRow(tester, t.common.home);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(rowHasFocus(tester, t.unifiedCatalog.moviesTitle), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(rowHasFocus(tester, t.unifiedCatalog.seriesTitle), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(rowHasFocus(tester, t.common.search), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(rowHasFocus(tester, t.common.settings), isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(recorded.selected, [NavigationTabId.settings]);
    });

    testWidgets('with the row it is both rendered and focusable', (tester) async {
      await pumpTvRail(tester);

      final row = find.widgetWithText(NavigationRailItem, t.nowWatching.sidebarLabel);
      expect(row, findsOneWidget);

      tester.widget<NavigationRailItem>(row).focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(rowHasFocus(tester, t.nowWatching.sidebarLabel), isTrue);
    });

    testWidgets('Arrow Down from the row above lands exactly on it', (tester) async {
      await pumpTvRail(tester);

      focusRow(tester, t.common.search);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowDown);

      expect(rowHasFocus(tester, t.nowWatching.sidebarLabel), isTrue);
      expect(rowHasFocus(tester, t.common.settings), isFalse);
    });

    testWidgets('Arrow Up from the row below lands exactly on it', (tester) async {
      await pumpTvRail(tester);

      focusRow(tester, t.common.settings);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowUp);

      expect(rowHasFocus(tester, t.nowWatching.sidebarLabel), isTrue);
      expect(rowHasFocus(tester, t.common.search), isFalse);
    });

    testWidgets('Select opens the now watching screen and activates nothing else', (tester) async {
      final recorded = await pumpTvRail(tester);

      focusRow(tester, t.nowWatching.sidebarLabel);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.byType(NowWatchingScreen), findsOneWidget);
      expect(recorded.selected, isEmpty, reason: 'it opens a page, it does not switch tabs');
      expect(recorded.contentSelects, isEmpty, reason: 'the press never leaks into the content');
    });

    testWidgets('the collapsed rail walks the same order', (tester) async {
      await pumpTvRail(tester, alwaysExpanded: false);

      focusRow(tester, t.common.search);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowDown);

      expect(rowHasFocus(tester, t.nowWatching.sidebarLabel), isTrue);
    });

    testWidgets('the row appearing and disappearing leaves no stale focus node', (tester) async {
      final recorded = await pumpTvRail(tester);

      final before = tester
          .widget<NavigationRailItem>(find.widgetWithText(NavigationRailItem, t.nowWatching.sidebarLabel))
          .focusNode;
      focusRow(tester, t.nowWatching.sidebarLabel);
      await tester.pumpAndSettle();

      // The provider polls, so the rail rebuilds under the focused row.
      recorded.now.setOthers(true);
      await tester.pumpAndSettle();

      final after = tester
          .widget<NavigationRailItem>(find.widgetWithText(NavigationRailItem, t.nowWatching.sidebarLabel))
          .focusNode;
      expect(identical(before, after), isTrue, reason: 'a rebuild must not swap the node out from under the focus');
      expect(after.hasFocus, isTrue);

      // And when the last stream ends the row goes away without taking the
      // walk with it.
      recorded.now.setOthers(false);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(NavigationRailItem, t.nowWatching.sidebarLabel), findsNothing);

      focusRow(tester, t.common.search);
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(rowHasFocus(tester, t.common.settings), isTrue);
    });

    // A conditional row does not wait for the focus to leave before it goes.
    // "Now watching" disappears the moment the last stream stops, the
    // reconnect row the moment the server answers again, Live TV and Requests
    // when their server drops. Disposing the node that holds the focus hands
    // primary focus up to the enclosing scope, and a rail that holds the focus
    // with no item on it is a rail that is drawn open, cannot be moved within,
    // and has no key that leads out of it.
    testWidgets('a row that vanishes under the focus hands it to the row that took its place', (tester) async {
      final recorded = await pumpTvRail(tester);

      focusRow(tester, t.nowWatching.sidebarLabel);
      await tester.pumpAndSettle();
      expect(rowHasFocus(tester, t.nowWatching.sidebarLabel), isTrue);

      recorded.now.setOthers(false);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(NavigationRailItem, t.nowWatching.sidebarLabel), findsNothing);
      final focusedRows = tester
          .widgetList<NavigationRailItem>(find.byType(NavigationRailItem))
          .where((item) => item.focusNode.hasFocus)
          .length;
      expect(focusedRows, 1, reason: 'exactly one surviving row must hold the focus');

      // And the walk still works from wherever it landed, which is what
      // "the user can leave again" comes down to on a remote.
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<NavigationRailItem>(find.byType(NavigationRailItem))
            .where((item) => item.focusNode.hasFocus)
            .length,
        1,
      );
    });

    testWidgets('a row vanishing while the rail is not focused does not pull the focus back', (tester) async {
      final recorded = await pumpTvRail(tester, isSidebarFocused: false);

      focusRow(tester, t.nowWatching.sidebarLabel);
      await tester.pumpAndSettle();

      recorded.now.setOthers(false);
      await tester.pumpAndSettle();

      expect(
        tester.widgetList<NavigationRailItem>(find.byType(NavigationRailItem)).where((item) => item.focusNode.hasFocus),
        isEmpty,
        reason: 'the shell has the focus elsewhere; recovering it here would be the late callback winning',
      );
    });
  });
}

/// A [NowWatchingProvider] whose answer to "is anyone else streaming" is set by
/// the test. The real one needs a Tautulli client and a poll timer, neither of
/// which says anything about focus.
class _FakeNowWatching extends NowWatchingProvider {
  _FakeNowWatching() : super(client: () => null, enabled: () => false);

  NowWatching _state = NowWatching.empty;

  @override
  NowWatching get now => _state;

  void setOthers(bool hasOthers) {
    _state = hasOthers
        ? const NowWatching(
            sessions: [WatchSession(id: 's1', userName: 'Someone', title: 'A film')],
          )
        : NowWatching.empty;
    notifyListeners();
  }
}
