import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/overlay_sheet_geometry.dart';

/// Placement rules for the overlay sheet, tested as the pure function they are.
///
/// Two things are being nailed down here. The `sheet` numbers are a regression
/// lock: context menus have been landing on those exact pixels for a long time
/// and the panel work must not move them. The `panel` numbers are the fix for
/// Filters/Sort opening in the bottom-right corner of a wide window. Television
/// is neither: every presentation lands on the 10-foot box of hoofdstuk 14.1,
/// which is the last group in this file.
void main() {
  /// A caller that names no alignment passes null, which is what almost every
  /// surface in the app does. Passing `Alignment.bottomCenter` here would say
  /// something different, and on a television it means something different
  /// (OVR2), so the two are kept apart in the harness as well.
  OverlaySheetGeometry sheetAt(Size size, {bool isTV = false, Alignment? alignment}) {
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
      alignment: null,
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
        alignment: null,
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

  // Hoofdstuk 14.1 asks for a centred TV modal; before fase 4 `panel` fell
  // through to the 400x400 bottom sheet on TV, so the source picker would have
  // opened as a mobile sheet on a television. Since OVR1b that box is gone
  // altogether: on TV both presentations resolve here.
  group('every overlay is a centred 10-foot modal on TV', () {
    // The canonical Apple TV canvas per DEC-028 (1920x1080 / 1.85), the raw
    // 1920x1080 reference surface, and a 720p output.
    const canvases = [Size(1038, 584), Size(1920, 1080), Size(1280, 720)];

    for (final size in canvases) {
      test('${size.width.toInt()}x${size.height.toInt()}: centred, faded in, never pointer-anchored', () {
        final g = panelAt(size, isTV: true);

        expect(g.alignment, Alignment.center);
        expect(g.isCentered, isTrue);
        expect(g.allowPointerAnchor, isFalse, reason: 'a remote has no cursor to anchor to');
        expect(g.allowDragHandle, isFalse);
        expect(g.fadeIn, isTrue);
        expect(g.enterOffset.dy, lessThan(size.height / 8), reason: 'a centred panel lifts, it does not fly in');
      });

      test('${size.width.toInt()}x${size.height.toInt()}: hoofdstuk 14.1 width band, expressed as a fraction', () {
        final g = panelAt(size, isTV: true);

        // The contract's 900-1040 is a reference measurement on a 1920x1080
        // output. Scaling the resolved width back up to that surface is what
        // makes the assertion mean the same thing on every canvas — and is
        // exactly the check that fails if someone re-reads 1040 as logical px.
        final asReferenceWidth = g.constraints.maxWidth * (1920 / size.width);
        expect(asReferenceWidth, inInclusiveRange(900, 1040));
      });

      test('${size.width.toInt()}x${size.height.toInt()}: leaves generous outer margins', () {
        final g = panelAt(size, isTV: true);

        // The failure this guards is a panel that eats the screen because the
        // reference number was taken literally: at 1038 logical wide, a 1000px
        // panel would leave 19px of margin.
        final margin = (size.width - g.constraints.maxWidth) / 2;
        expect(margin, greaterThan(size.width * 0.2), reason: 'a 10-foot modal floats, it does not fill');
        expect(g.constraints.maxHeight, lessThanOrEqualTo(size.height * 0.85));
        expect(g.constraints.maxWidth + g.edgePadding * 2, lessThanOrEqualTo(size.width));
      });
    }

    // OVR1b. Until this was fixed the two presentations meant different things
    // on TV: `panel` got the box above, `sheet` got a hardcoded 400x400 flush
    // against the bottom of the viewport, which on a television is the
    // overscan band of hoofdstuk 8.1. Eleven surfaces open without naming a
    // presentation, so that box was what a rating sheet, a track picker or the
    // library quick picker actually got. The presentation now decides nothing
    // on TV; this function is the single owner of the 10-foot box.
    for (final size in canvases) {
      test('${size.width.toInt()}x${size.height.toInt()}: a sheet resolves to exactly the panel', () {
        expect(sheetAt(size, isTV: true), panelAt(size, isTV: true));
      });
    }

    test('a TV sheet is centred and clear of the viewport edges', () {
      const size = Size(1038, 584);
      final sheet = sheetAt(size, isTV: true);

      expect(sheet.alignment, Alignment.center);
      expect(sheet.isCentered, isTrue);
      expect(sheet.allowDragHandle, isFalse);
      expect(sheet.allowPointerAnchor, isFalse);
      expect(sheet.fadeIn, isTrue);
      expect(
        sheet.enterOffset.dy,
        lessThan(size.height / 8),
        reason: 'no full-viewport slide: the sheet no longer arrives from off-screen',
      );
      expect(sheet.constraints.maxHeight, lessThanOrEqualTo(size.height * 0.85));
      expect(sheet.constraints.maxWidth * (1920 / size.width), inInclusiveRange(900, 1040));
    });

    test('an explicit constraint on a TV sheet is capped by the viewport too', () {
      // The old sheet path handed explicit constraints straight through
      // without ever consulting the viewport, so a caller asking for 4000
      // could hang off the screen. The panel path intersects.
      final g = resolveOverlaySheetGeometry(
        presentation: OverlaySheetPresentation.sheet,
        viewport: const Size(1038, 584),
        alignment: null,
        isTV: true,
        explicitConstraints: const BoxConstraints(maxWidth: 4000, maxHeight: 4000),
      );

      expect(g.constraints.maxWidth + g.edgePadding * 2, lessThanOrEqualTo(1038));
      expect(g.constraints.maxHeight + g.edgePadding * 2, lessThanOrEqualTo(584));
    });

    test('an explicit constraint is still capped by the TV viewport', () {
      final g = panelAt(const Size(1038, 584), isTV: true, constraints: const BoxConstraints(maxWidth: 4000));
      expect(g.constraints.maxWidth + g.edgePadding * 2, lessThanOrEqualTo(1038));
    });

    test('a degenerate TV viewport produces valid, non-negative bounds', () {
      final g = panelAt(const Size(0, 0), isTV: true);
      expect(g.constraints.maxWidth, greaterThanOrEqualTo(0));
      expect(g.constraints.maxHeight, greaterThanOrEqualTo(0));
      expect(g.constraints.debugAssertIsValid(), isTrue);
    });
  });

  // OVR2. OVR1b sent every TV overlay through the panel, including the one
  // caller in the app that places itself. A television makes a surface safe; it
  // does not make every surface a panel.
  group('a caller that names its own placement keeps it on TV', () {
    const tv = Size(1038, 584);
    // Hoofdstuk 8.1's horizontal safe inset as a fraction of the 1920 surface,
    // which is the number _tvPanelGeometry already owns.
    const inset = 1038 * (72 / 1920);

    OverlaySheetGeometry placed(Alignment alignment, {BoxConstraints? constraints, Size size = tv}) {
      return resolveOverlaySheetGeometry(
        presentation: OverlaySheetPresentation.sheet,
        viewport: size,
        alignment: alignment,
        isTV: true,
        explicitConstraints: constraints,
      );
    }

    test('the alignment is the caller\'s, not the panel\'s', () {
      expect(placed(Alignment.topCenter).alignment, Alignment.topCenter);
      expect(placed(Alignment.bottomCenter).alignment, Alignment.bottomCenter);
      expect(placed(Alignment.topCenter), isNot(panelAt(tv, isTV: true)));
    });

    test('a box that fits is handed back untouched', () {
      final g = placed(Alignment.topCenter, constraints: const BoxConstraints(maxHeight: 80, maxWidth: 900));

      expect(g.constraints.maxWidth, 900);
      expect(g.constraints.maxHeight, 80);
    });

    test('a box that does not fit is clamped, and the alignment still stands', () {
      final g = placed(Alignment.topCenter, constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 80));

      expect(g.constraints.maxWidth, moreOrLessEquals(tv.width - inset * 2, epsilon: 0.01));
      expect(g.constraints.maxHeight, 80);
      expect(g.alignment, Alignment.topCenter, reason: 'clamping a size is not re-placing a surface');
    });

    test('it keeps both safe insets, so nothing lands in the overscan band', () {
      final g = placed(Alignment.topCenter, constraints: const BoxConstraints(maxHeight: 80, maxWidth: 900));

      expect(g.edgePadding, moreOrLessEquals(inset, epsilon: 0.01));
      expect(g.verticalEdgePadding, moreOrLessEquals(inset, epsilon: 0.01));
    });

    test('it is still a remote-driven surface: no pointer anchor, no drag handle', () {
      final g = placed(Alignment.bottomCenter);

      expect(g.allowPointerAnchor, isFalse);
      expect(g.allowDragHandle, isFalse);
      expect(g.enterOffset.dy, lessThan(tv.height / 8), reason: 'a lift, not a full-viewport slide');
    });

    test('the old 400x400 TV box is not what a placed sheet falls back to', () {
      final g = placed(Alignment.bottomCenter);

      expect(g.constraints.maxWidth, isNot(400));
      expect(g.constraints.maxHeight, isNot(400));
      expect(g.constraints.maxWidth * (1920 / tv.width), inInclusiveRange(900, 1040));
    });

    test('off TV a named alignment behaves exactly as it always did', () {
      final named = resolveOverlaySheetGeometry(
        presentation: OverlaySheetPresentation.sheet,
        viewport: const Size(1280, 800),
        alignment: Alignment.topCenter,
        isTV: false,
        explicitConstraints: null,
      );

      expect(named.alignment, Alignment.topCenter);
      expect(named.constraints.maxWidth, 700);
      expect(named.constraints.maxHeight, 400);
      expect(named.edgePadding, 16);
      expect(named.verticalEdgePadding, 0, reason: 'only a television needs the vertical inset');
      expect(named.fadeIn, isFalse);
    });
  });

  group('legacy panel caller constraints', () {
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
