import 'baseline_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown_gear.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown_painter.dart';

const _screen = Size(400, 800);
const _tabBar = 80.0;

class _Rig {
  final controller = ScrollController();
  final teeth = <int>[];
  final rowCount = ValueNotifier<int>(0);
  int taps = 0;
  Duration now = Duration.zero;

  /// [rows] rows of 100 px under a viewport of 800 px.
  Widget host({required int rows, bool reduceMotion = false}) {
    rowCount.value = rows;
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: _screen,
          padding: const EdgeInsets.only(bottom: _tabBar),
          disableAnimations: reduceMotion,
        ),
        child: Material(
          child: ScrollCrown(
            enabled: true,
            onToothTick: () => teeth.add(1),
            clock: () => now,
            child: ValueListenableBuilder<int>(
              valueListenable: rowCount,
              builder: (context, count, _) => ListView.builder(
                controller: controller,
                itemCount: count,
                itemExtent: 100,
                itemBuilder: (context, i) => Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => taps++, child: Text('row $i')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Finder get _rail => find.byKey(const ValueKey('scroll_crown_rail'));
Finder get _gear => find.byKey(const ValueKey('scroll_crown_gear'));

bool _visible(WidgetTester tester) => tester.widget<ScrollCrownGear>(find.byType(ScrollCrownGear)).visible;

/// The x of a touch on the right edge, inside the rail.
const _edgeX = 400 - 22.0;

double _phase(WidgetTester tester) => (tester.widget<CustomPaint>(_gear).painter! as ScrollCrownPainter).phase;

Future<TestGesture> _start(WidgetTester tester, _Rig rig, Offset position) async {
  final gesture = await tester.createGesture();
  await gesture.down(position, timeStamp: rig.now);
  return gesture;
}

Future<void> _setUp(WidgetTester tester, _Rig rig, {int rows = 40, bool reduceMotion = false}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh tree per rig: no crown state carries over from an earlier one.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(rig.host(rows: rows, reduceMotion: reduceMotion));
  await tester.pump();
}

/// Scrolls the content a little in the middle of the screen, which brings
/// the crown up.
Future<void> _wake(WidgetTester tester) async {
  await tester.dragFrom(const Offset(200, 400), const Offset(0, -40));
  await tester.pump();
}

/// Drags down the rail from [startY] in [steps] moves of [step] px,
/// advancing the fake clock by [msPerStep] each move.
Future<void> _scrub(
  WidgetTester tester,
  _Rig rig, {
  required int steps,
  double step = 2,
  int msPerStep = 50,
  double startY = 1,
}) async {
  final gesture = await _start(tester, rig, Offset(_screen.width - 22, startY));
  for (var i = 0; i < steps; i++) {
    rig.now += Duration(milliseconds: msPerStep);
    await gesture.moveBy(Offset(0, step), timeStamp: rig.now);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  test('a drag anchors the offset and reaches both ends from any grab point', () {
    for (final startY in [48.0, 200.0, 350.0, 600.0, 652.0]) {
      double map(double delta) => baselineOffsetForDrag(
        startPixels: 3000,
        startY: startY,
        dragDelta: delta,
        railHeight: 700,
        minExtent: -100,
        maxExtent: 7000,
      );
      expect(map(0), 3000, reason: 'grabbing does not jump');
      expect(map(700 - startY), 7000);
      expect(map(-startY), -100);
    }
  });

  test('dragging inward from the rail padding starts smoothly', () {
    expect(
      baselineOffsetForDrag(
        startPixels: 3000,
        startY: 690,
        dragDelta: -0.001,
        railHeight: 700,
        minExtent: 0,
        maxExtent: 7000,
      ),
      closeTo(3000, 0.1),
    );
    expect(
      baselineOffsetForDrag(
        startPixels: 3000,
        startY: 10,
        dragDelta: 0.001,
        railHeight: 700,
        minExtent: 0,
        maxExtent: 7000,
      ),
      closeTo(3000, 0.1),
    );
  });

  test('content shorter than two screens gets no crown', () {
    ScrollMetrics metrics(double max) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: max,
      pixels: 0,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );
    expect(ScrollCrown.isLongEnough(metrics(0)), isFalse);
    expect(ScrollCrown.isLongEnough(metrics(799)), isFalse);
    expect(ScrollCrown.isLongEnough(metrics(800)), isTrue);
    expect(ScrollCrown.isLongEnough(metrics(double.infinity)), isFalse);
  });

  for (final horizontal in [false, true]) {
    testWidgets(
      horizontal
          ? 'horizontal movement with vertical jitter reaches content'
          : 'three-point slow correction wins before the underlying long press',
      (tester) async {
        tester.view.physicalSize = _screen;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = ScrollController();
        addTearDown(controller.dispose);
        var longPresses = 0;
        var horizontalMoves = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: ScrollCrown(
              enabled: true,
              controller: controller,
              child: GestureDetector(
                onLongPress: () => longPresses++,
                onHorizontalDragUpdate: (_) => horizontalMoves++,
                child: ListView.builder(
                  controller: controller,
                  itemCount: 100,
                  itemExtent: 72,
                  itemBuilder: (_, i) => SizedBox.expand(child: Text('row $i')),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final gesture = await tester.startGesture(const Offset(380, 300));
        await tester.pump(const Duration(milliseconds: 100));
        if (horizontal) {
          await gesture.moveBy(const Offset(-2, 1));
          await gesture.moveBy(const Offset(-30, 0));
          await gesture.moveBy(const Offset(-20, 0));
        } else {
          await gesture.moveBy(const Offset(0, 3));
        }
        await tester.pump(const Duration(milliseconds: 600));
        expect(longPresses, 0);
        expect(
          controller.offset,
          closeTo(horizontal ? 0 : controller.position.maxScrollExtent * 3 / (800 - 48 - 300), .01),
        );
        if (horizontal) expect(horizontalMoves, greaterThan(0));
        await gesture.cancel();
        await tester.pump();
        final before = controller.offset;
        final afterCancel = await tester.startGesture(const Offset(380, 600));
        await afterCancel.moveBy(const Offset(-2, 1));
        await afterCancel.moveBy(const Offset(-30, 0));
        await afterCancel.moveBy(const Offset(-20, 0));
        await afterCancel.up();
        await tester.pump();
        expect(controller.offset, before, reason: 'a cancelled gesture must not leave a stale direction origin');
        expect(horizontalMoves, greaterThan(0));
      },
    );
  }

  testWidgets('short content never shows the crown, not even when scrolled', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig, rows: 14); // 1400 px under 800: 1.75 screens
    expect(_gear, findsNothing);
    await _wake(tester);
    expect(rig.controller.offset, greaterThan(0), reason: 'the list does scroll');
    expect(_gear, findsNothing);
    expect(_rail, findsNothing);
  });

  testWidgets('the crown appears on scroll and fades after the hide delay', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    expect(_gear, findsOneWidget, reason: 'mounted but hidden');
    expect(_visible(tester), isFalse);

    await _wake(tester);
    expect(_visible(tester), isTrue);

    await tester.pump(ScrollCrown.hideDelay + const Duration(milliseconds: 50));
    expect(_visible(tester), isFalse);
  });

  testWidgets('after scrolling, a swipe along the edge away from the gear still scrolls normally', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await _wake(tester);
    expect(_visible(tester), isTrue, reason: 'the crown came up through scrolling');
    final start = rig.controller.offset;

    // Far below the gear (which rests near the top): an ordinary swipe up.
    await tester.dragFrom(const Offset(_edgeX, 500), const Offset(0, -200));
    await tester.pump();
    expect(rig.controller.offset, closeTo(start + 200, 30), reason: 'content follows the finger, not reversed');
  });

  testWidgets('the first drag on the visible resting hint already controls the wheel', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    expect(_visible(tester), isFalse);
    final gesture = await _start(tester, rig, const Offset(_edgeX, 360));
    rig.now += const Duration(milliseconds: 100);
    await gesture.moveBy(const Offset(0, 40), timeStamp: rig.now);
    await tester.pump();
    expect(rig.controller.offset, greaterThan(0));
    await gesture.up();
    await tester.pump();
  });

  testWidgets('a touch on the edge makes the whole edge a rail', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await tester.tapAt(const Offset(_edgeX, 500));
    await tester.pump();
    expect(_visible(tester), isTrue);

    rig.now += const Duration(milliseconds: 100);
    final drag100down = await _start(tester, rig, const Offset(_edgeX, 500));
    rig.now += const Duration(milliseconds: 100);
    await drag100down.moveBy(const Offset(0, 100), timeStamp: rig.now);
    await drag100down.up();
    await tester.pump();
    expect(rig.controller.offset, greaterThan(0));
  });

  testWidgets('the first drag on the gear after it faded already scrubs', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await _wake(tester);
    await tester.pump(ScrollCrown.hideDelay + const Duration(milliseconds: 50));
    expect(_visible(tester), isFalse);
    final start = rig.controller.offset;

    await _scrub(tester, rig, steps: 50, step: 2, startY: 20); // 100 px down the rail
    final max = rig.controller.position.maxScrollExtent;
    expect(rig.controller.offset, greaterThan(start + 0.08 * max), reason: 'scrubbed, not swiped up to 0');
  });

  testWidgets('more items loading mid-drag do not stretch the scrub', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await _wake(tester);
    final start = rig.controller.offset;
    final maxAtStart = rig.controller.position.maxScrollExtent;

    final gesture = await _start(tester, rig, const Offset(_edgeX, 20));
    for (var i = 0; i < 25; i++) {
      rig.now += const Duration(milliseconds: 5);
      await gesture.moveBy(const Offset(0, 2), timeStamp: rig.now);
      await tester.pump();
    }
    rig.rowCount.value = 120; // a page loads: three times the content
    await tester.pump();
    // The list takes the new length on its next layout, which the next move
    // brings; the move after that is where a stretched mapping would jump.
    rig.now += const Duration(milliseconds: 5);
    await gesture.moveBy(const Offset(0, 2), timeStamp: rig.now);
    await tester.pump();
    expect(rig.controller.position.maxScrollExtent, greaterThan(maxAtStart * 2));
    final beforeMove = rig.controller.offset;
    rig.now += const Duration(milliseconds: 5);
    await gesture.moveBy(const Offset(0, 2), timeStamp: rig.now);
    await tester.pump();
    expect(
      rig.controller.offset - beforeMove,
      closeTo((maxAtStart - start) * 2 / (720 - 48 - 20), .01),
      reason: 'loading preserves the original scale',
    );
    await gesture.up();
    await tester.pump();
    expect(rig.controller.offset, closeTo(start + (maxAtStart - start) * 54 / (720 - 48 - 20), .01));
  });

  testWidgets('crown drag maps the remaining rail directly to the remaining library', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await _wake(tester);
    final start = rig.controller.offset;

    await _scrub(tester, rig, steps: 12, step: 2); // within the fine excursion
    final expected = start + 24 / (720 - 48 - 1) * (rig.controller.position.maxScrollExtent - start);
    // The touch slop before the drag is recognised costs a few pixels.
    expect(rig.controller.offset, closeTo(expected, 1));
    expect(rig.teeth, isNotEmpty);
  });

  testWidgets('one continuous stroke reaches each end', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    for (final direction in [1, -1]) {
      for (var stroke = 0; stroke < 1; stroke++) {
        await tester.tapAt(const Offset(_edgeX, 360));
        await tester.pump();
        final gesture = await _start(tester, rig, Offset(_edgeX, direction > 0 ? 48 : 672));
        rig.now += const Duration(milliseconds: 500);
        await gesture.moveTo(Offset(_edgeX, direction > 0 ? 672 : 48), timeStamp: rig.now);
        await gesture.up();
        await tester.pump();
      }
      expect(rig.controller.offset, closeTo(direction > 0 ? rig.controller.position.maxScrollExtent : 0, .01));
    }
  });

  testWidgets('an already reached end follows loading while held, but not after release', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    rig.controller.jumpTo(rig.controller.position.maxScrollExtent - 40);
    await tester.pump();
    await tester.tapAt(const Offset(_edgeX, 650));
    final gesture = await _start(tester, rig, const Offset(_edgeX, 650));
    rig.now += const Duration(milliseconds: 50);
    await gesture.moveTo(const Offset(_edgeX, 700), timeStamp: rig.now);
    await tester.pump();
    expect(rig.controller.offset, rig.controller.position.maxScrollExtent);
    rig.rowCount.value = 120;
    await tester.pumpAndSettle();
    expect(rig.controller.offset, rig.controller.position.maxScrollExtent);
    await gesture.up();
    await tester.pump();
    final releasedOffset = rig.controller.offset;
    rig.rowCount.value = 160;
    await tester.pumpAndSettle();
    expect(rig.controller.offset, releasedOffset, reason: 'loading after release must not take over scrolling');
  });

  testWidgets('a partial drag inside the rail does not take over loading', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig, rows: 120);
    await tester.tapAt(const Offset(_edgeX, 360));
    await tester.pump();
    final gesture = await _start(tester, rig, const Offset(_edgeX, 360));
    rig.now += const Duration(seconds: 20);
    await gesture.moveTo(const Offset(_edgeX, 600), timeStamp: rig.now);
    await tester.pump();
    final before = rig.controller.offset;
    expect(before, lessThan(rig.controller.position.maxScrollExtent));
    rig.rowCount.value = 160;
    await tester.pumpAndSettle();
    expect(rig.controller.offset, before);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('released crown immediately reflects the actual library position', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    final rail = tester.getRect(_rail);
    final gesture = await _start(tester, rig, const Offset(_edgeX, 400));
    rig.now += const Duration(milliseconds: 300);
    await gesture.moveBy(const Offset(0, 100), timeStamp: rig.now);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final position = rig.controller.position;
    final expectedTop = rail.top + position.pixels / position.maxScrollExtent * (rail.height - ScrollCrownGear.height);
    expect(tester.getTopLeft(find.byType(ScrollCrownGear)).dy, closeTo(expectedTop, .01));
    await tester.pump(ScrollCrown.hideDelay + const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(_edgeX, 360));
    await tester.pump();
    final returning = await _start(tester, rig, const Offset(_edgeX, 400));
    rig.now += const Duration(milliseconds: 300);
    await returning.moveTo(const Offset(_edgeX, 48), timeStamp: rig.now);
    await tester.pump();
    await returning.up();
    await tester.pump();
    expect(position.pixels, 0);
    expect(
      tester.getTopLeft(find.byType(ScrollCrownGear)).dy,
      rail.top,
      reason: 'library start means crown at the top',
    );
  });

  testWidgets('ratchet ticks scale with the drag distance', (tester) async {
    final short = _Rig();
    await _setUp(tester, short);
    await _wake(tester);
    await _scrub(tester, short, steps: 35, step: 2); // 70 px
    expect(short.teeth.length, inInclusiveRange(9, 10));

    final long = _Rig();
    await _setUp(tester, long);
    await _wake(tester);
    await _scrub(tester, long, steps: 70, step: 2); // 140 px
    expect(long.teeth.length, inInclusiveRange(19, 20));
  });

  testWidgets('a fast drag is rate limited, not queued', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await _wake(tester);
    // 70 moves of 10 px, 5 ms apart: 100 teeth pass in 350 ms.
    await _scrub(tester, rig, steps: 70, step: 10, msPerStep: 5);
    expect(rig.teeth.length, lessThanOrEqualTo(350 ~/ 35 + 1));
  });

  testWidgets('the teeth turn with the drag, but not under reduce motion', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await _wake(tester);
    await _scrub(tester, rig, steps: 20, step: 2);
    expect(_phase(tester), isNot(0));

    final still = _Rig();
    await _setUp(tester, still, reduceMotion: true);
    await _wake(tester);
    final before = still.controller.offset;
    await _scrub(tester, still, steps: 20, step: 2);
    expect(_phase(tester), 0);
    expect(still.controller.offset, greaterThan(before), reason: 'scrubbing still works');
  });

  testWidgets('taps at the edge still reach the content under the rail', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await _wake(tester);
    expect(_rail, findsOneWidget);
    final button = find.byType(TextButton).hitTestable().first;
    await tester.tap(button);
    await tester.pump();
    expect(rig.taps, 1);
  });

  testWidgets('nested header consumes only the crown distance and returns fully to start', (tester) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nested = GlobalKey<NestedScrollViewState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NestedScrollView(
            key: nested,
            floatHeaderSlivers: true,
            headerSliverBuilder: (context, _) => [
              const SliverAppBar(key: ValueKey('nested_header'), expandedHeight: 134, floating: true, snap: true),
            ],
            body: ScrollCrown(
              enabled: true,
              child: ListView.builder(itemCount: 40, itemExtent: 100, itemBuilder: (_, i) => Text('row $i')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double offset() => nested.currentState!.outerController.offset + nested.currentState!.innerController.offset;
    final rail = tester.getRect(_rail);
    final max =
        nested.currentState!.outerController.position.maxScrollExtent +
        nested.currentState!.innerController.position.maxScrollExtent;
    final origin = 400 - rail.top;
    double firstExpected(double dy) => max * dy / (rail.height - 48 - origin);
    final gesture = await tester.startGesture(const Offset(_edgeX, 400));
    await gesture.moveBy(const Offset(0, 3));
    await tester.pump();
    expect(offset(), closeTo(firstExpected(3), .01));
    await tester.pump(); // Re-anchor after the nested header layout.
    expect(tester.getCenter(_gear).dy, closeTo(405, .01));
    double headerPaintExtent() =>
        tester.renderObject<RenderSliver>(find.byKey(const ValueKey('nested_header'))).geometry!.paintExtent;
    final headerAfterMove = headerPaintExtent();
    await tester.pump(const Duration(milliseconds: 600));
    expect(headerPaintExtent(), headerAfterMove);
    await gesture.moveBy(const Offset(0, 3));
    await tester.pump();
    expect(offset(), closeTo(firstExpected(6), .01));
    await gesture.moveBy(const Offset(0, -6));
    await tester.pump();
    expect(offset(), closeTo(0, .01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(offset(), closeTo(0, .01));
    final returnRail = tester.getRect(_rail);
    final returnOrigin = 400 - returnRail.top;
    final returnGain = max / (returnRail.height - 48 - returnOrigin);
    final returnGesture = await tester.startGesture(const Offset(_edgeX, 400));
    await returnGesture.moveBy(const Offset(0, 200));
    await tester.pump();
    final beforeReverse = offset();
    await returnGesture.moveBy(const Offset(0, -3));
    await tester.pump();
    expect(offset(), closeTo(beforeReverse - 3 * returnGain, .01));
    await tester.pump();
    expect(tester.getCenter(_gear).dy, closeTo(599, .01));
    final reverseHeader = headerPaintExtent();
    await tester.pump(const Duration(milliseconds: 600));
    expect(headerPaintExtent(), reverseHeader);
    await returnGesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('VoiceOver sees a slider that pages the view', (tester) async {
    final handle = tester.ensureSemantics();
    final rig = _Rig();
    await _setUp(tester, rig);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Scroll through the page')),
      isSemantics(label: 'Scroll through the page', isSlider: true, value: '0%'),
    );
    tester.semantics.performAction(find.semantics.byLabel('Scroll through the page'), SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(rig.controller.offset, greaterThan(0));
    handle.dispose();
  });
}
