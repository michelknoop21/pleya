/// The compact back-and-title header the northstar draws on `03-alle-films`,
/// `05-zoeken` and `19-aanvragen`.
///
/// Pins the one number fase 3 had drifted on. Not a golden: the test font
/// gives every glyph an em box, so a rendered width here says nothing about a
/// real device. The size itself is what was measured off the frozen PNGs, so
/// the size itself is what this asserts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_catalog_header.dart';
import 'package:pleya/widgets/mobile/mobile_page_title_row.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('the compact header title is the measured northstar size', (tester) async {
    await pump(tester, MobileCatalogHeader(title: 'All movies', onBack: () {}, onSearch: () {}));

    final title = tester.widget<Text>(find.text('All movies'));
    expect(title.style?.fontSize, MobileCatalogHeader.titleFontSize);
    expect(MobileCatalogHeader.titleFontSize, 18);
    expect(title.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('a landing keeps its own large title, which is a different heading', (tester) async {
    // The correction is scoped to the compact header. Folding the two into one
    // number would flatten mockup 01's page title onto mockup 03's toolbar
    // title, and the northstar draws them at visibly different sizes.
    await pump(tester, const MobilePageTitleRow(title: 'Series', viewAllLabel: 'All series'));

    final title = tester.widget<Text>(find.text('Series'));
    expect(title.style?.fontSize, MobilePageTitleRow.titleFontSize);
    expect(MobilePageTitleRow.titleFontSize, greaterThan(MobileCatalogHeader.titleFontSize));
  });
}
