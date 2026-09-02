import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/pleya_logo.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('renders the transparent mark asset with the expected image properties', (tester) async {
    await pump(tester, const PleyaLogo(size: 48));

    final imageFinder = find.descendant(of: find.byType(PleyaLogo), matching: find.byType(Image));
    expect(imageFinder, findsOneWidget);

    final image = tester.widget<Image>(imageFinder);
    expect(image.fit, BoxFit.contain);
    expect(image.filterQuality, FilterQuality.high);
    expect(image.width, 48);
    expect(image.height, 48);
    final assetImage = image.image as AssetImage;
    expect(assetImage.assetName, 'assets/branding/pleya_logo.png');
  });

  testWidgets('carries no clip, no fill and no circular container around it', (tester) async {
    for (final background in [Colors.white, const Color(0xFF0A64C6)]) {
      await pump(tester, ColoredBox(color: background, child: const PleyaLogo(size: 48)));

      final logo = find.byType(PleyaLogo);
      expect(find.descendant(of: logo, matching: find.byType(ClipRRect)), findsNothing);
      expect(find.descendant(of: logo, matching: find.byType(ClipOval)), findsNothing);
      expect(find.descendant(of: logo, matching: find.byType(ClipPath)), findsNothing);
      expect(find.descendant(of: logo, matching: find.byType(CircleAvatar)), findsNothing);

      for (final decoratedBox in tester.widgetList<DecoratedBox>(
        find.descendant(of: logo, matching: find.byType(DecoratedBox)),
      )) {
        final decoration = decoratedBox.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.color, isNull, reason: 'a DecoratedBox around the mark must not paint a fill colour');
        }
      }
      for (final container in tester.widgetList<Container>(
        find.descendant(of: logo, matching: find.byType(Container)),
      )) {
        expect(container.color, isNull, reason: 'a Container around the mark must not paint a fill colour');
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          expect(
            decoration.color,
            isNull,
            reason: 'a Container decoration around the mark must not paint a fill colour',
          );
        }
      }
    }
  });

  testWidgets('does not overflow inside a box smaller than its own size', (tester) async {
    await pump(tester, const SizedBox(width: 8, height: 8, child: PleyaLogo(size: 48)));

    expect(tester.takeException(), isNull);
  });

  /// Bronbewaker: [PleyaLogo] is the only place allowed to load
  /// `assets/branding/pleya_logo.png` directly. Every callsite goes through
  /// the widget so the no-clip/no-fill contract above actually covers them; a
  /// raw `Image.asset('assets/branding/pleya_logo.png')` slipped in elsewhere
  /// would escape it.
  test('assets/branding/pleya_logo.png is only referenced from pleya_logo.dart', () {
    const needle = 'assets/branding/pleya_logo.png';
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (!entity.readAsStringSync().contains(needle)) continue;
      final normalized = entity.path.replaceAll('\\', '/');
      if (normalized == 'lib/widgets/pleya_logo.dart') continue;
      // The one other consumer, by decision rather than by accident: the
      // backend badge draws the same generated P as a *source glyph* tinted to
      // its line's ink, and [DEC-076] puts the boundary at the widget, not the
      // asset — `PleyaLogo` is the brand mark and gets no colour parameter.
      // The badge honours the no-clip/no-fill contract above on its own.
      if (normalized == 'lib/widgets/backend_badge.dart') continue;
      offenders.add(normalized);
    }
    expect(offenders, isEmpty, reason: 'these files reference the raw asset instead of using PleyaLogo: $offenders');
  });
}
