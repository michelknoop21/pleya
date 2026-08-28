import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/theme/mono_shapes.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/dialog_action_button.dart';
import 'package:pleya/widgets/focusable_popup_menu_button.dart';

/// A [StadiumBorder] with a focus-colored [BorderSide] is, as a value, not
/// equal to the [BorderSide.none] one the button theme carries — even though
/// the geometry is identical. Every shape comparison below normalizes through
/// this first.
OutlinedBorder _bare(OutlinedBorder shape) => shape.copyWith(side: BorderSide.none);

void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pump(WidgetTester tester, Widget child, {bool dark = true}) async {
    await tester.pumpWidget(
      InputModeTracker(
        child: MaterialApp(
          theme: monoTheme(dark: dark),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The button's actually-rendered shape, post theme resolution — not the
  /// (usually null) local `style.shape` on the raw widget.
  OutlinedBorder materialShapeOf(WidgetTester tester, Finder buttonFinder) {
    final material = tester.widget<Material>(find.descendant(of: buttonFinder, matching: find.byType(Material)).first);
    return material.shape! as OutlinedBorder;
  }

  /// The ring's shape, from the ring pad's `foregroundDecoration`. Null when
  /// the wrapper isn't in shape-aware ring mode (e.g. fill/delegated).
  ShapeDecoration? ringDecorationOf(WidgetTester tester, Finder wrapperFinder) {
    for (final c in tester.widgetList<AnimatedContainer>(
      find.descendant(of: wrapperFinder, matching: find.byType(AnimatedContainer)),
    )) {
      if (c.foregroundDecoration is ShapeDecoration) return c.foregroundDecoration! as ShapeDecoration;
    }
    return null;
  }

  /// The fill's shape/color, from the wrapper's own `decoration`. Null when
  /// the wrapper isn't in shape-aware fill mode.
  ShapeDecoration? fillDecorationOf(WidgetTester tester, Finder wrapperFinder) {
    for (final c in tester.widgetList<AnimatedContainer>(
      find.descendant(of: wrapperFinder, matching: find.byType(AnimatedContainer)),
    )) {
      if (c.decoration is ShapeDecoration) return c.decoration! as ShapeDecoration;
    }
    return null;
  }

  test('Filled, Elevated, Outlined and Text all resolve to MonoShapes.cta', () {
    final theme = monoTheme(dark: true);
    final expected = _bare(MonoShapes.cta);
    expect(_bare(theme.filledButtonTheme.style!.shape!.resolve(const {})!), expected);
    expect(_bare(theme.elevatedButtonTheme.style!.shape!.resolve(const {})!), expected);
    expect(_bare(theme.outlinedButtonTheme.style!.shape!.resolve(const {})!), expected);
    expect(_bare(theme.textButtonTheme.style!.shape!.resolve(const {})!), expected);
  });

  testWidgets('the focus ring shape matches the wrapped FilledButton exactly', (tester) async {
    await pump(
      tester,
      FocusableButton(
        autofocus: true,
        onPressed: () {},
        child: FilledButton(onPressed: () {}, child: const Text('Go')),
      ),
    );

    final ring = ringDecorationOf(tester, find.byType(FocusableButton));
    final buttonShape = materialShapeOf(tester, find.byType(FilledButton));

    expect(ring, isNotNull);
    expect(
      _bare(ring!.shape as OutlinedBorder),
      _bare(buttonShape),
      reason: 'the ring and the button it rings must be the exact same shape, or the ring will not fit',
    );
  });

  testWidgets('a focused ring is actually visible', (tester) async {
    await pump(
      tester,
      FocusableButton(
        autofocus: true,
        onPressed: () {},
        child: FilledButton(onPressed: () {}, child: const Text('Go')),
      ),
    );

    final ring = ringDecorationOf(tester, find.byType(FocusableButton))!;
    final side = (ring.shape as OutlinedBorder).side;
    expect(side.color.a, greaterThan(0.5), reason: 'a focused CTA must carry a visible ring, not a transparent one');
  });

  testWidgets('the ring reserves the same footprint focused and unfocused', (tester) async {
    final focusNode = FocusNode(debugLabel: 'ring-footprint');
    addTearDown(focusNode.dispose);

    await pump(
      tester,
      FocusableButton(
        focusNode: focusNode,
        onPressed: () {},
        child: FilledButton(onPressed: () {}, child: const Text('Go')),
      ),
    );
    final unfocusedSize = tester.getSize(find.byType(FocusableButton));

    focusNode.requestFocus();
    await tester.pumpAndSettle();
    final focusedSize = tester.getSize(find.byType(FocusableButton));

    expect(
      focusedSize,
      unfocusedSize,
      reason: 'focusing a CTA must not change its box — that is the whole point of the halo',
    );

    // And that footprint is exactly the child plus the ring halo on all sides.
    await pump(tester, FilledButton(onPressed: () {}, child: const Text('Go')));
    final bareSize = tester.getSize(find.byType(FilledButton));

    const halo = FocusTheme.focusBorderWidth * 2;
    expect(focusedSize.width, moreOrLessEquals(bareSize.width + halo));
    expect(focusedSize.height, moreOrLessEquals(bareSize.height + halo));
  });

  testWidgets('fill mode paints a background, not a foreground ring, and adds no footprint', (tester) async {
    final focusNode = FocusNode(debugLabel: 'fill-mode');
    addTearDown(focusNode.dispose);

    await pump(
      tester,
      FocusableButton(
        focusNode: focusNode,
        mode: FocusIndicatorMode.fill,
        shape: const CircleBorder(),
        onPressed: () {},
        child: const Icon(Icons.close),
      ),
    );

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    expect(
      ringDecorationOf(tester, find.byType(FocusableButton)),
      isNull,
      reason: 'fill mode must not also paint a ring',
    );
    final fill = fillDecorationOf(tester, find.byType(FocusableButton));
    expect(fill, isNotNull);
    expect(fill!.color!.a, greaterThan(0), reason: 'a focused fill-mode button must show its tint');

    final wrapperSize = tester.getSize(find.byType(FocusableButton));
    await pump(tester, const Icon(Icons.close));
    final bareSize = tester.getSize(find.byType(Icon));
    expect(wrapperSize, bareSize, reason: 'fill mode reserves no extra halo space');
  });

  testWidgets('delegated mode paints nothing itself and adds no footprint', (tester) async {
    await pump(
      tester,
      FocusableButton(
        autofocus: true,
        mode: FocusIndicatorMode.delegated,
        onPressed: () {},
        child: const Icon(Icons.close),
      ),
    );

    expect(ringDecorationOf(tester, find.byType(FocusableButton)), isNull);
    expect(fillDecorationOf(tester, find.byType(FocusableButton)), isNull);

    final wrapperSize = tester.getSize(find.byType(FocusableButton));
    await pump(tester, const Icon(Icons.close));
    final bareSize = tester.getSize(find.byType(Icon));
    expect(wrapperSize, bareSize, reason: 'delegated mode reserves no extra halo space');
  });

  testWidgets('DialogActionButton primary and secondary share one contour and one footprint', (tester) async {
    final primaryNode = FocusNode(debugLabel: 'primary');
    final secondaryNode = FocusNode(debugLabel: 'secondary');
    addTearDown(primaryNode.dispose);
    addTearDown(secondaryNode.dispose);

    await pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogActionButton(focusNode: secondaryNode, onPressed: () {}, label: 'Cancel'),
          DialogActionButton(focusNode: primaryNode, onPressed: () {}, label: 'Save', isPrimary: true),
        ],
      ),
    );

    final primaryFinder = find.byWidgetPredicate((w) => w is FocusableButton && w.focusNode == primaryNode);
    final secondaryFinder = find.byWidgetPredicate((w) => w is FocusableButton && w.focusNode == secondaryNode);

    primaryNode.requestFocus();
    await tester.pumpAndSettle();
    final primaryRing = ringDecorationOf(tester, primaryFinder);
    expect(primaryRing, isNotNull, reason: 'the primary dialog action must show a ring, same as the secondary');

    secondaryNode.requestFocus();
    await tester.pumpAndSettle();
    final secondaryRing = ringDecorationOf(tester, secondaryFinder);
    expect(secondaryRing, isNotNull);

    expect(
      _bare(primaryRing!.shape as OutlinedBorder),
      _bare(secondaryRing!.shape as OutlinedBorder),
      reason: 'primary (FilledButton) and secondary (TextButton) must ring with the same contour',
    );

    // Both now sit on the ring path, so both carry the same halo over their
    // own bare button — the primary/secondary footprint asymmetry (fill vs.
    // ring) this change fixes is gone.
    final primarySize = tester.getSize(primaryFinder);
    final secondarySize = tester.getSize(secondaryFinder);
    await pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: () {}, child: const Text('Cancel')),
          FilledButton(onPressed: () {}, child: const Text('Save')),
        ],
      ),
    );
    final bareSecondary = tester.getSize(find.byType(TextButton));
    final barePrimary = tester.getSize(find.byType(FilledButton));

    const halo = FocusTheme.focusBorderWidth * 2;
    expect(primarySize.height, moreOrLessEquals(barePrimary.height + halo));
    expect(secondarySize.height, moreOrLessEquals(bareSecondary.height + halo));
  });

  testWidgets('FocusableButton(shape: CircleBorder()) keeps its circle', (tester) async {
    await pump(
      tester,
      FocusableButton(autofocus: true, shape: const CircleBorder(), onPressed: () {}, child: const Icon(Icons.close)),
    );

    final ring = ringDecorationOf(tester, find.byType(FocusableButton));
    expect(ring, isNotNull);
    expect(ring!.shape, isA<CircleBorder>());
  });

  testWidgets('FocusablePopupMenuButton keeps its circle', (tester) async {
    final focusNode = FocusNode(debugLabel: 'popup-menu-shape');
    addTearDown(focusNode.dispose);

    await pump(
      tester,
      FocusablePopupMenuButton<String>(
        focusNode: focusNode,
        icon: const Icon(Icons.more_vert),
        itemBuilder: (_) => const [],
      ),
    );

    focusNode.requestFocus();
    await tester.pumpAndSettle();

    final fill = fillDecorationOf(tester, find.byType(FocusablePopupMenuButton<String>));
    expect(fill, isNotNull);
    expect(fill!.shape, isA<CircleBorder>());
  });
}
