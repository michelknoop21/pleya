/// A-24 (DEC-XXX-A24): Instellingen on Apple TV opens under the collapsible top
/// bar, and with the bar gone the page fits the window without shrinking any
/// text.
///
/// The view is 1037.84x583.78 logical pixels, what Flutter sees on an Apple TV
/// behind the 1.85 wrapper (density audit of 26 October 2026), so a logical
/// size divided by `TvHig.of` is the size in points on the 1920x1080 canvas.
/// The page is framed the way `TvRootShell` frames the route
/// `tvMyPleyaNestedRoute` builds: the whole window and the bar's own inset
/// under a collapsible bar, the box under the bar's band under a persistent
/// one. The frame follows the production route, so a route that still keeps
/// the bar fails here on layout as well as on its presentation.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/screens/settings/settings_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_navigator.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/tv_hig.dart';
import 'package:pleya/widgets/settings/settings_studio_theme.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/settings_tv_harness.dart';

late AppDatabase _db;

/// Apple TV's logical window behind the 1.85 wrapper.
const _window = Size(1037.84, 583.78);

/// The persistent bar's band as the density audit measured it: 144 pt.
const _barBandPt = 144.0;

/// How the shell frames [route]: see `TvRootShell`, the `Positioned` per
/// nested route and the `topInset` it hands [TvNestedSurface].
Widget _shellFrame(TvNestedRoute route, Widget page) => TvDisplayMetrics(
  size: _window,
  child: Builder(
    builder: (context) {
      final covers = route.topNav.coversWindow;
      final scale = TvLayoutConstants.scaleOf(context);
      return Padding(
        padding: EdgeInsets.only(top: covers ? 0 : _barBandPt * TvHig.of(context)),
        child: TvNestedSurface(
          route: route,
          dismiss: ([_]) {},
          topInset: covers ? TvTopNavLayout.topInset * scale : 0,
          child: page,
        ),
      );
    },
  ),
);

Finder _category(int index) => find.byWidgetPredicate(
  (w) => w is FocusableWrapper && w.automationId == AutomationIds.settingsCategory && w.automationInstance == '$index',
);

Finder _setting(String key) => find.byWidgetPredicate(
  (w) => w is FocusableWrapper && w.automationId == AutomationIds.myPleyaSectionTile && w.automationInstance == key,
);

FocusNode _nodeOf(WidgetTester tester, Finder finder) =>
    tester.widget<FocusableWrapper>(finder).focusNode ??
    tester.widget<Focus>(find.descendant(of: finder, matching: find.byType(Focus)).first).focusNode!;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() => PlexApiCache.initialize(_db = AppDatabase.forTesting(NativeDatabase.memory())));
  setUp(() {
    resetSharedPreferencesForTest();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  test('Instellingen opens under the collapsible bar; the other Mijn Pleya sections keep theirs', () {
    expect(tvMyPleyaNestedRoute(TvMyPleyaSection.settings).topNav, TvTopNavPresentation.collapsible);
    for (final section in TvMyPleyaSection.values.where((s) => s != TvMyPleyaSection.settings)) {
      expect(tvMyPleyaNestedRoute(section).topNav, TvTopNavPresentation.persistent, reason: section.name);
    }
  });

  testWidgets('a page opened from a settings page gets the collapsible bar, a page opened elsewhere does not', (
    tester,
  ) async {
    late TvTopNavPresentation inSettings;
    late TvTopNavPresentation elsewhere;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Column(
          children: [
            Builder(
              builder: (context) {
                elsewhere = tvSettingsTopNavFor(context);
                return const SizedBox();
              },
            ),
            SettingsStudioTheme(
              child: Builder(
                builder: (context) {
                  inSettings = tvSettingsTopNavFor(context);
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );
    expect(inSettings, TvTopNavPresentation.collapsible);
    expect(elsewhere, TvTopNavPresentation.persistent);
  });

  testWidgets('a subpage of the TV settings page opens in the shell under the collapsible bar', (tester) async {
    final opened = <TvNestedRoute>[];
    Future<Object?> push(TvNestedRoute route) {
      opened.add(route);
      return Completer<Object?>().future;
    }

    tvContentRouteRegistry.attach(push);
    addTearDown(() => tvContentRouteRegistry.detach(push));
    await tester.runAsync(() => SettingsService.getInstance());
    await pumpTvSettings(tester, db: _db);

    for (var i = 0; _category(i).evaluate().isNotEmpty; i++) {
      final title = find.descendant(of: _category(i), matching: find.text(t.settings.advanced));
      if (title.evaluate().isEmpty) continue;
      _nodeOf(tester, _category(i)).requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.select);
    }
    _nodeOf(tester, _setting('settings.about')).requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.select);

    expect(opened.map((r) => r.id), ['tvSettings_about']);
    expect(opened.single.topNav, TvTopNavPresentation.collapsible);
    await unmountTvSettings(tester);
  });

  testWidgets('with the bar gone the rail fits on 1038x584, rows and heading show, and no text is under 23 pt', (
    tester,
  ) async {
    await tester.runAsync(() => SettingsService.getInstance());
    final route = tvMyPleyaNestedRoute(TvMyPleyaSection.settings);
    await pumpTvSettings(tester, db: _db, window: _window, wrap: (page) => _shellFrame(route, page));

    final context = tester.element(find.byType(SettingsScreen));
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    double points(double logical) => logical / pt;

    // No band above the page: its title sits in the top overscan band's
    // place, not under a bar.
    final title = tester.getRect(find.text(t.settings.title));
    expect(title.top, closeTo(TvCatalogLayout.topSafeInset * scale, 0.5));

    // The rail: every pill inside its column, with room for one more (Big P,
    // in a build that carries it; this test build does not).
    final rail = tester.getRect(find.ancestor(of: _category(0), matching: find.byType(Scrollable)).first);
    final pills = [for (var i = 0; _category(i).evaluate().isNotEmpty; i++) tester.getRect(_category(i))];
    expect(pills.length, greaterThanOrEqualTo(7));
    for (final pill in pills) {
      expect(pill.top, greaterThanOrEqualTo(rail.top));
      expect(pill.bottom, lessThanOrEqualTo(rail.bottom), reason: 'pill at ${points(pill.top)} pt is cut off');
    }
    final pitch = pills[1].top - pills[0].top;
    final eighthBottom = pills[0].top + 7 * pitch + pills[0].height;
    expect(eighthBottom, lessThanOrEqualTo(rail.bottom), reason: 'eight pills do not fit');

    // The rows column: the eyebrow, the heading and at least four rows of
    // Weergave without scrolling.
    final rows = find.ancestor(of: _setting('setting.theme_mode'), matching: find.byType(Scrollable)).first;
    final column = tester.getRect(rows);
    expect(tester.getRect(find.text(t.settingsStudio.appearanceHeadline)).top, greaterThanOrEqualTo(column.top));
    final visible = [
      for (final key in ['setting.theme_mode', 'setting.liquid_glass', 'setting.view_mode', 'setting.library_density'])
        tester.getRect(_setting(key)),
    ];
    for (final row in visible) {
      expect(row.bottom, lessThanOrEqualTo(column.bottom));
    }

    // Text: nothing under the tvOS minimum, and the page's own type at the
    // sizes it had before the bar went.
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
      find.descendant(of: find.byType(SettingsScreen), matching: find.byType(RichText)),
    )) {
      final size = paragraph.text.style?.fontSize;
      final text = paragraph.text.toPlainText();
      if (size == null || text.trim().isEmpty) continue;
      expect(points(size), greaterThanOrEqualTo(TvHig.caption2 - 0.01), reason: '"$text" is ${points(size)} pt');
    }
    double fontOf(String text) => tester.renderObject<RenderParagraph>(find.text(text)).text.style!.fontSize!;
    expect(fontOf(t.settings.title), closeTo(TvMyPleyaLayout.pageTitleFontSize * scale, 0.01));
    expect(points(fontOf(t.settingsStudio.tvTagline)), closeTo(TvHig.caption1, 0.01));
    expect(points(fontOf(t.settings.appearance)), closeTo(TvHig.body, 0.01));
    expect(points(fontOf(t.settingsStudio.appearanceHeadline)), closeTo(TvHig.title3, 0.01));
    expect(points(fontOf(t.settingsStudio.tvFooterHint)), closeTo(TvHig.caption2, 0.01));
    await unmountTvSettings(tester);
  });

  testWidgets('UP from the top pill and from the top row goes to the top bar', (tester) async {
    await tester.runAsync(() => SettingsService.getInstance());
    var toBar = 0;
    await pumpTvSettings(tester, db: _db, focusSidebar: () => toBar++);

    _nodeOf(tester, _category(0)).requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(toBar, 1);

    _nodeOf(tester, _setting('setting.theme_mode')).requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(toBar, 2);

    // Further down, UP stays in the page.
    _nodeOf(tester, _category(1)).requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(toBar, 2);
    expect(_nodeOf(tester, _category(0)).hasPrimaryFocus, isTrue);
    await unmountTvSettings(tester);
  });
}
