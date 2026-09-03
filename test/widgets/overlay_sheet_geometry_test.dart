import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/overlay_sheet_geometry.dart';

/// Placement rules for the overlay sheet, tested as the pure function they are.
///
/// Two things are being nailed down here. The `sheet` numbers are a regression
/// lock: context menus have been landing on those exact pixels for a long time
/// and the panel work must not move them. The `panel` numbers are the fix for
/// Filters/Sort opening in the bottom-right corner of a wide window.
void main() {
  OverlaySheetGeometry sheetAt(Size size, {bool isTV = false, Alignment alignment = Alignment.bottomCenter}) {
    return resolveOverlaySheetGeometry(
      presentation: OverlaySheetPresentation.sheet,
      viewport: size,
      alignment: alignment,
      isTV: isTV,
    );
  }

  OverlaySheetGeometry panelAt(Size size, {bool isTV = false, BoxConstraints? constraints}) {
    return resolveOverlaySheetGeometry(
      presentation: OverlaySheetPresentation.panel,
      viewport: size,
      alignment: Alignment.bottomCenter,
      isTV: isTV,
      explicitConstraints: constraints,
    );
  }

  group('sheet keeps today\'s placement', () {
    test('phone: full width, three quarters high, flush to the bottom', () {
      const size = Size(390, 844);
      final g = sheetAt(size);

      expect(g.alignment, Alignment.bottomCenter);
      expect(g.constraints.maxWidth, double.infinity);
      expect(g.constraints.maxHeight, 844 * 0.75);
      expect(g.edgePadding, 0);
      expect(g.borderRadius, const BorderRadius.vertical(top: Radius.circular(16)));
      expect(g.allowPointerAnchor, isTrue);
      expect(g.allowDragHandle, isTrue);
      expect(g.enterOffset, const Offset(0, 844));
      expect(g.fadeIn, isFalse);
    });

    for (final size in const [Size(834, 1112), Size(1280, 800), Size(1440, 900), Size(2560, 1440)]) {
      test('desktop ${size.width.toInt()}x${size.height.toInt()}: the 700x400 box, 16px off the edges', () {
        final g = sheetAt(size);

        expect(g.alignment, Alignment.bottomCenter);
        expect(g.constraints.maxWidth, 700);
        expect(g.constraints.maxHeight, 400);
        expect(g.edgePadding, 16);
        expect(g.allowPointerAnchor, isTrue);
        expect(g.fadeIn, isFalse);
      });
    }

    test('TV: 400x400, no drag handle', () {
      final g = sheetAt(const Size(1920, 1080), isTV: true);

      expect(g.constraints.maxWidth, 400);
      expect(g.constraints.maxHeight, 400);
      expect(g.allowDragHandle, isFalse);
    });

    test('top-aligned sheet inverts radius, travel and the handle', () {
      final g = sheetAt(const Size(1280, 800), alignment: Alignment.topCenter);

      expect(g.borderRadius, const BorderRadius.vertical(bottom: Radius.circular(16)));
      expect(g.enterOffset, const Offset(0, -800));
      expect(g.allowDragHandle, isFalse);
    });

    test('caller constraints are passed straight through', () {
      const explicit = BoxConstraints(maxWidth: 320, maxHeight: 240);
      final g = resolveOverlaySheetGeometry(
        presentation: OverlaySheetPresentation.sheet,
        viewport: const Size(1440, 900),
        alignment: Alignment.bottomCenter,
        isTV: false,
        explicitConstraints: explicit,
      );

      expect(g.constraints, explicit);
    });
  });

  group('panel falls back to the sheet where the sheet is right', () {
    test('phone', () {
      const size = Size(390, 844);
      expect(panelAt(size), sheetAt(size));
    });

    test('TV', () {
      const size = Size(1920, 1080);
      expect(panelAt(size, isTV: true), sheetAt(size, isTV: true));
    });

    test('a 520px window is still a phone as far as layout goes', () {
      const size = Size(520, 360);
      expect(panelAt(size), sheetAt(size));
    });
  });

  group('panel centres itself on desktop', () {
    for (final size in const [Size(1280, 800), Size(1440, 900)]) {
      test('${size.width.toInt()}x${size.height.toInt()}', () {
        final g = panelAt(size);

        expect(g.alignment, Alignment.center);
        expect(g.constraints.maxWidth, lessThanOrEqualTo(560));
        expect(g.constraints.maxHeight, lessThanOrEqualTo(size.height * 0.8));
        expect(g.edgePadding, 24);
        expect(g.allowPointerAnchor, isFalse, reason: 'this is the bug: the panel must not follow the mouse');
        expect(g.allowDragHandle, isFalse);
        expect(g.borderRadius, BorderRadius.circular(16));
        expect(g.fadeIn, isTrue);
        expect(g.enterOffset.dy, lessThan(size.height / 4), reason: 'a centred panel lifts, it does not fly in');
        expect(g.isCentered, isTrue);
      });
    }

    test('height is a first-class input: a wide but short window still fits', () {
      final g = panelAt(const Size(1600, 420));

      expect(g.constraints.maxHeight, lessThanOrEqualTo(420 - g.edgePadding * 2));
      expect(g.constraints.maxHeight, greaterThan(0));
    });
  });

  group('panel never leaves the viewport', () {
    // 520x360 lands on the phone path; the three below are genuinely small
    // desktop windows, where the default 560-wide box does not fit as-is.
    for (final size in const [Size(700, 500), Size(600, 400), Size(640, 300)]) {
      test('${size.width.toInt()}x${size.height.toInt()} fits with its margins', () {
        final g = panelAt(size);

        expect(g.constraints.maxWidth + g.edgePadding * 2, lessThanOrEqualTo(size.width));
        expect(g.constraints.maxHeight + g.edgePadding * 2, lessThanOrEqualTo(size.height));
        expect(g.constraints.maxWidth, greaterThanOrEqualTo(0));
        expect(g.constraints.maxHeight, greaterThanOrEqualTo(0));
        expect(g.constraints.debugAssertIsValid(), isTrue);
      });
    }

    test('a degenerate viewport produces valid, non-negative bounds', () {
      // Not a real window: a zero-sized first frame that still reports a
      // non-mobile width. Must not hand the layout a negative maxHeight.
      final g = panelAt(const Size(600, 0));

      expect(g.constraints.maxWidth, greaterThanOrEqualTo(0));
      expect(g.constraints.maxHeight, greaterThanOrEqualTo(0));
      expect(g.constraints.debugAssertIsValid(), isTrue);
    });

    test('caller constraints are honoured, then capped by the viewport', () {
      final roomy = panelAt(const Size(1440, 900), constraints: const BoxConstraints(maxWidth: 320, maxHeight: 200));
      expect(roomy.constraints.maxWidth, 320, reason: 'smaller than the default: the caller wins');
      expect(roomy.constraints.maxHeight, 200);

      final greedy = panelAt(const Size(700, 500), constraints: const BoxConstraints(maxWidth: 900, maxHeight: 900));
      expect(greedy.constraints.maxWidth + greedy.edgePadding * 2, lessThanOrEqualTo(700));
      expect(greedy.constraints.maxHeight + greedy.edgePadding * 2, lessThanOrEqualTo(500));
    });
  });
}
