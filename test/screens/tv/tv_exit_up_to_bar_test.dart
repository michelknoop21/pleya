/// A-24 (DEC-XXX-A24), review finding 556-I1: a settings subpage under the
/// collapsible bar has a way up to that bar.
///
/// Instellingen opens Over, Logboeken and Servers under the collapsible bar,
/// which is off screen while the remote is in the page. UP from the top focus
/// stop of those pages used to do nothing, so search, Home and the account
/// menu were only reachable after Menu. The pages are framed the way
/// `TvRootShell` frames a nested route ([TvNestedSurface]) under a shell that
/// answers `focusSidebar`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/screens/settings/logs_screen.dart';
import 'package:pleya/screens/tv/sections/tv_about_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/app_logger.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_menu_grid.dart';
import 'package:pleya/widgets/tv/tv_page_chip_bar.dart';

import '../../test_helpers/prefs.dart';

Future<int Function()> _pump(WidgetTester tester, Widget page, {required TvTopNavPresentation topNav}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var toBar = 0;
  final route = TvNestedRoute(id: 'probe', builder: (_) => page, topNav: topNav);
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: MainScreenFocusScope(
          focusSidebar: () => toBar++,
          focusContent: () {},
          isSidebarFocused: false,
          sideNavigationWidth: 0,
          child: Material(
            child: TvNestedSurface(route: route, dismiss: ([_]) {}, child: page),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return () => toBar;
}

FocusNode _nodeOf(WidgetTester tester, Finder finder) =>
    tester.widget<FocusableWrapper>(finder).focusNode ??
    tester.widget<Focus>(find.descendant(of: finder, matching: find.byType(Focus)).first).focusNode!;

Finder _tile(String instance) => find.byWidgetPredicate(
  (w) =>
      w is FocusableWrapper && w.automationId == AutomationIds.myPleyaSectionTile && w.automationInstance == instance,
);

Future<void> _up(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    PackageInfo.setMockInitialValues(
      appName: 'Pleya',
      packageName: 'nl.michelknoop.pleya',
      version: '2.8.0',
      buildNumber: '212',
      buildSignature: '',
    );
  });
  setUp(() {
    resetSharedPreferencesForTest();
    MemoryLogOutput.clearLogs();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    MemoryLogOutput.clearLogs();
  });

  testWidgets('Over: UP from the top tile goes to the collapsible bar, a lower tile steps up first', (tester) async {
    final toBar = await _pump(tester, const TvAboutScreen(), topNav: TvTopNavPresentation.collapsible);

    _nodeOf(tester, _tile('about.about_privacy')).requestFocus();
    await tester.pump();
    await _up(tester);
    expect(toBar(), 0, reason: 'a tile below the first row steps up inside the page');
    expect(_nodeOf(tester, _tile('about.about_source')).hasPrimaryFocus, isTrue);

    await _up(tester);
    expect(toBar(), 1);
  });

  testWidgets('Over under the persistent bar keeps its old UP', (tester) async {
    final toBar = await _pump(tester, const TvAboutScreen(), topNav: TvTopNavPresentation.persistent);
    _nodeOf(tester, _tile('about.about_source')).requestFocus();
    await tester.pump();
    await _up(tester);
    expect(toBar(), 0);
    expect(_nodeOf(tester, _tile('about.about_source')).hasPrimaryFocus, isTrue);
  });

  testWidgets('a menu grid without a way up of its own (Servers, Verbinding toevoegen) gets the bar', (tester) async {
    final nodes = FocusMemoryTracker(debugLabelPrefix: 'probeGrid');
    addTearDown(nodes.dispose);
    final toBar = await _pump(
      tester,
      TvMenuGrid(
        nodes: nodes,
        columns: 2,
        automationInstance: 'servers',
        sections: [
          TvMenuSection(
            items: [
              TvMenuItem(key: 'servers_add', icon: Icons.add, title: 'Add', onSelect: () {}),
              TvMenuItem(key: 'servers_share', icon: Icons.share, title: 'Share', onSelect: () {}),
            ],
          ),
        ],
      ),
      topNav: TvTopNavPresentation.collapsible,
    );
    nodes.get('servers_add').requestFocus();
    await tester.pump();
    await _up(tester);
    expect(toBar(), 1);
  });

  testWidgets('Logboeken: UP scrolls the reader back first, then goes to the bar', (tester) async {
    setLoggerLevel(true);
    for (var i = 0; i < 80; i++) {
      appLogger.i('line $i');
    }
    final toBar = await _pump(tester, const LogsScreen(), topNav: TvTopNavPresentation.collapsible);
    final refresh = find.byWidgetPredicate((w) => w is FocusableWrapper && w.automationInstance == 'logs.refresh');
    _nodeOf(tester, refresh).requestFocus();
    await tester.pump();

    // Scroll the reader down, then back: the first UP only scrolls.
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
    );
    scrollable.position.jumpTo(160);
    await tester.pump();
    await _up(tester);
    await tester.pumpAndSettle();
    expect(toBar(), 0, reason: 'the reader was not at its top');

    scrollable.position.jumpTo(0);
    await tester.pump();
    await _up(tester);
    expect(toBar(), 1);
    expect(find.byType(TvPageChipBar), findsOneWidget);
  });
}
