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
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/tv_hig.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings_section.dart';
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

  testWidgets('a settings row is Body over Caption 1 in a row under 100 pt', (tester) async {
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
    expect(points(tester.getSize(find.byType(ListTile)).height), lessThanOrEqualTo(100));
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

  // VIS-0925-G (DEC-139): the text keeps its HIG size, the air shrinks.
  group('VIS-0925-G targeted densification', () {
    testWidgets('a two-line settings row is at most 84 pt, a one-line row 56', (tester) async {
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
      expect(points(tester.getSize(rows.at(0)).height), lessThanOrEqualTo(84.5));
      expect(points(tester.getSize(rows.at(1)).height), lessThanOrEqualTo(56.5));
      // The text did not shrink with the row.
      expect(fontPoints(tester, 'Thema'), closeTo(TvHig.body, 0.1));
      expect(fontPoints(tester, 'OLED'), closeTo(TvHig.caption1, 0.1));
    });

    test('catalog card text is at least the tvOS minimum on the canonical canvas', () {
      // Tokens go through scaleOf (0.85 on 1038x584), then the 1.85 wrapper.
      double pt(double token) => points(token * 0.85);
      expect(pt(TvCatalogLayout.cardMetaFontSize), greaterThanOrEqualTo(TvHig.caption2));
      expect(pt(TvCatalogLayout.cardTitleFontSize), greaterThanOrEqualTo(TvHig.caption1));
    });
  });
}
