/// DENS1: TV settings rows and settings index tiles in Apple's tvOS HIG sizes.
///
/// The view is 1038x584 logical pixels, what Flutter sees on an Apple TV
/// behind the 1.85 wrapper, so a logical size times 1080 / 584 is the size in
/// points on the television. Before DENS1 a settings row came out at 138 pt
/// around 26/22 pt text and an index tile at 160 pt around a 19 pt value line.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/tv_hig.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings_section.dart';
import 'package:pleya/widgets/tv/tv_appearance_categories.dart';
import 'package:pleya/widgets/tv/tv_menu_grid.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

void main() {
  const view = Size(1038, 584);
  double points(double logical) => logical * 1080 / view.height;

  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: monoTheme(dark: true),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  double fontPoints(WidgetTester tester, String text) =>
      points(tester.renderObject<RenderParagraph>(find.text(text)).text.style!.fontSize!);

  testWidgets('a settings row is Body over Caption 1 in a row under 110 pt', (tester) async {
    await pump(
      tester,
      TvSettingsDensity(
        child: SettingsGroup(
          children: [
            SettingNavigationTile(icon: Symbols.contrast_rounded, title: 'Thema', subtitle: 'OLED', onTap: () {}),
          ],
        ),
      ),
    );

    expect(fontPoints(tester, 'Thema'), closeTo(TvHig.body, 0.1));
    expect(fontPoints(tester, 'OLED'), closeTo(TvHig.caption1, 0.1));
    expect(points(tester.getSize(find.byType(ListTile)).height), lessThanOrEqualTo(110));
  });

  testWidgets('a settings index tile is Body over Caption 1 with the glyph beside it', (tester) async {
    final nodes = FocusMemoryTracker(debugLabelPrefix: 'dens1');
    addTearDown(nodes.dispose);
    await pump(
      tester,
      TvMenuGrid(
        nodes: nodes,
        columns: 2,
        automationInstance: 'dens1',
        sections: [
          TvMenuSection(
            items: [
              TvMenuItem(
                key: 'appearance',
                icon: Symbols.palette_rounded,
                title: 'Uiterlijk',
                value: 'OLED',
                onSelect: () {},
              ),
            ],
          ),
        ],
      ),
    );

    expect(fontPoints(tester, 'Uiterlijk'), closeTo(TvHig.body, 0.1));
    expect(fontPoints(tester, 'OLED'), closeTo(TvHig.caption1, 0.1));
    final tile = find.ancestor(of: find.text('Uiterlijk'), matching: find.byType(AnimatedContainer)).first;
    expect(points(tester.getSize(tile).height), lessThanOrEqualTo(110));
    // Beside, not above: the glyph and the title share a line.
    final glyph = tester.getRect(find.byIcon(Symbols.palette_rounded));
    expect(glyph.left, lessThan(tester.getRect(find.text('Uiterlijk')).left));
    expect(glyph.bottom, greaterThan(tester.getRect(find.text('Uiterlijk')).top));
  });

  // VIS-0925-G (DEC-139) took the rows to 56/84 pt; on the 77 inch set the
  // text then hugged the separators and the card stopped at three quarters of
  // the screen. VIS-0926-S1 gives the air back: same text, taller rows.
  group('VIS-0926-S1 settings spacing', () {
    testWidgets('a two-line settings row is 106 pt, a one-line row 70, the text unchanged', (tester) async {
      await pump(
        tester,
        TvSettingsDensity(
          child: SettingsGroup(
            children: [
              SettingNavigationTile(icon: Symbols.contrast_rounded, title: 'Thema', subtitle: 'OLED', onTap: () {}),
              SettingNavigationTile(icon: Symbols.language_rounded, title: 'Taal', onTap: () {}),
            ],
          ),
        ),
      );
      final rows = find.byType(ListTile);
      expect(points(tester.getSize(rows.at(0)).height), closeTo(106, 1));
      expect(points(tester.getSize(rows.at(1)).height), closeTo(70, 1));
      // The gap between title and value line is their leading: 38 and 36 pt.
      expect(points(tester.getSize(find.text('Thema')).height), closeTo(kTvSettingsTitleLeadingPt, 1));
      expect(points(tester.getSize(find.text('OLED')).height), closeTo(kTvSettingsValueLeadingPt, 1));
      // The text did not grow with the row.
      expect(fontPoints(tester, 'Thema'), closeTo(TvHig.body, 0.1));
      expect(fontPoints(tester, 'OLED'), closeTo(TvHig.caption1, 0.1));
    });

    testWidgets('category pills have an 18 pt inset and 16 pt between them', (tester) async {
      await pump(
        tester,
        TvAppearanceCategories(
          title: 'Uiterlijk',
          children: [
            const SettingsSectionHeader('Weergave'),
            SettingNavigationTile(icon: Symbols.contrast_rounded, title: 'Thema', onTap: () {}),
            const SettingsSectionHeader('Startscherm'),
            SettingNavigationTile(icon: Symbols.home_rounded, title: 'Start', onTap: () {}),
          ],
        ),
      );
      Rect around(String label, Type type) =>
          tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(type)).first);
      final pill = around('Weergave', Container);
      final label = tester.getRect(find.text('Weergave'));
      expect(points(pill.height - label.height), closeTo(2 * kTvCategoryPillInsetPt, 0.5));
      // The gap sits between the focus wrappers, so the ring never eats it.
      final first = around('Weergave', FocusableWrapper);
      final second = around('Startscherm', FocusableWrapper);
      expect(points(second.top - first.bottom), closeTo(kTvCategoryGapPt, 0.5));
    });

    // Uiterlijk > Startscherm on tvOS: six rows, one with a two-line value.
    // Mounted under the shell's top band as Verify measured it on 1038x584
    // (the page region starts at 179.4 pt, the surface's own top padding is
    // 34.6 pt of that), so the rows see the height they get on the device.
    testWidgets('a six-row Appearance category fills at least 90% of its column or scrolls', (tester) async {
      const shellTop = (179.36 - 34.6) * 584 / 1080;
      await pump(
        tester,
        Padding(
          padding: const EdgeInsets.only(top: shellTop),
          child: TvAppearanceCategories(
            title: 'Uiterlijk',
            children: [
              const SettingsSectionHeader('Startscherm'),
              for (var i = 0; i < 5; i++)
                SettingNavigationTile(icon: Symbols.home_rounded, title: 'Rij $i', subtitle: 'Aan', onTap: () {}),
              SettingNavigationTile(icon: Symbols.home_rounded, title: 'Rij 5', subtitle: 'Een\ntwee', onTap: () {}),
            ],
          ),
        ),
      );
      final card = tester.getRect(find.byType(SettingsGroup));
      final column = find.ancestor(of: find.byType(SettingsGroup), matching: find.byType(Scrollable)).first;
      final viewport = tester.getRect(column);
      final scrolls = tester.state<ScrollableState>(column).position.maxScrollExtent > 0;
      final fill = (card.bottom - viewport.top) / viewport.height;
      // VIS-0925-G's rows filled 80%; the photo from the set showed 75%.
      expect(scrolls || fill >= 0.9, isTrue, reason: 'card fills ${(fill * 100).toStringAsFixed(1)}% of its column');
    });

    test('catalog card text is at least the tvOS minimum on the canonical canvas', () {
      // Tokens go through scaleOf (0.85 on 1038x584), then the 1.85 wrapper.
      double pt(double token) => points(token * 0.85);
      expect(pt(TvCatalogLayout.cardMetaFontSize), greaterThanOrEqualTo(TvHig.caption2));
      expect(pt(TvCatalogLayout.cardTitleFontSize), greaterThanOrEqualTo(TvHig.caption1));
    });
  });
}
