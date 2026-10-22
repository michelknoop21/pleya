import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown_gear.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown_painter.dart';

const _screen = Size(400, 800);
const _tabBar = 80.0;
const _railHeight = 800 - _tabBar;

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
  final gesture = await tester.startGesture(Offset(_screen.width - 22, startY));
  for (var i = 0; i < steps; i++) {
    rig.now += Duration(milliseconds: msPerStep);
    await gesture.moveBy(Offset(0, step));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  test('a drag anchors the offset and reaches both ends from any grab point', () {
    for (final startY in [48.0, 200.0, 350.0, 600.0, 652.0]) {
      double map(double delta) => ScrollCrown.offsetForDrag(
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
      ScrollCrown.offsetForDrag(
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
      ScrollCrown.offsetForDrag(
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

  testWidgets('a touch on the edge makes the whole edge a rail', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await tester.tapAt(const Offset(_edgeX, 500));
    await tester.pump();
    expect(_visible(tester), isTrue);

    await tester.dragFrom(const Offset(_edgeX, 500), const Offset(0, 100));
    await tester.pump();
    final max = rig.controller.position.maxScrollExtent;
    // A swipe down would stay at 0; the rail maps 100 px onto the range.
    expect(rig.controller.offset, greaterThan(0.08 * max));
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

    final gesture = await tester.startGesture(const Offset(_edgeX, 20));
    for (var i = 0; i < 25; i++) {
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump();
    }
    rig.rowCount.value = 120; // a page loads: three times the content
    await tester.pump();
    // The list takes the new length on its next layout, which the next move
    // brings; the move after that is where a stretched mapping would jump.
    await gesture.moveBy(const Offset(0, 2));
    await tester.pump();
    expect(rig.controller.position.maxScrollExtent, greaterThan(maxAtStart * 2));
    final beforeMove = rig.controller.offset;
    await gesture.moveBy(const Offset(0, 2));
    await tester.pump();
    expect(rig.controller.offset - beforeMove, closeTo(2 / _railHeight * maxAtStart, 1), reason: 'no jump');
    await gesture.up();
    await tester.pump();
    expect(rig.controller.offset, lessThan(start + 70 / _railHeight * maxAtStart));
  });

  testWidgets('a rail drag scrolls pixel-proportionally over the whole range', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await _wake(tester);
    final max = rig.controller.position.maxScrollExtent; // 4000 - 800
    final start = rig.controller.offset;

    await _scrub(tester, rig, steps: 90, step: 2); // 180 px of the 720 px rail
    final expected = start + 180 / _railHeight * max;
    // The touch slop before the drag is recognised costs a few pixels.
    expect(rig.controller.offset, closeTo(expected, 20 / _railHeight * max));
    expect(rig.teeth, isNotEmpty);
  });

  testWidgets('a crown grabbed halfway down the rail reaches both ends', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await tester.tapAt(const Offset(_edgeX, 360));
    await tester.pump();

    await tester.dragFrom(const Offset(_edgeX, 360), const Offset(0, 340));
    await tester.pump();
    expect(rig.controller.offset, closeTo(rig.controller.position.maxScrollExtent, 0.01));

    await tester.dragFrom(const Offset(_edgeX, 360), const Offset(0, -340));
    await tester.pump();
    expect(rig.controller.offset, closeTo(rig.controller.position.minScrollExtent, 0.01));
  });

  testWidgets('the rail end reaches rows loaded during the drag', (tester) async {
    final rig = _Rig();
    await _setUp(tester, rig);
    await tester.tapAt(const Offset(_edgeX, 360));
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(_edgeX, 360));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    rig.rowCount.value = 120;
    await tester.pump();
    await gesture.moveTo(const Offset(_edgeX, 700));
    await tester.pumpAndSettle();
    expect(rig.controller.offset, closeTo(rig.controller.position.maxScrollExtent, 0.01));
    await gesture.up();
    await tester.pump();
    final releasedOffset = rig.controller.offset;
    rig.rowCount.value = 160;
    await tester.pumpAndSettle();
    expect(rig.controller.offset, releasedOffset, reason: 'loading after release must not take over scrolling');
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
