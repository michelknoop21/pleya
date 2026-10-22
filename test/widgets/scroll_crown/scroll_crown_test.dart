import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown_painter.dart';

const _screen = Size(400, 800);
const _tabBar = 80.0;
const _railHeight = 800 - _tabBar;

class _Rig {
  final controller = ScrollController();
  final teeth = <int>[];
  int taps = 0;
  Duration now = Duration.zero;

  /// [rows] rows of 100 px under a viewport of 800 px.
  Widget host({required int rows, bool reduceMotion = false}) => MaterialApp(
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
          child: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < rows; i++)
                SizedBox(
                  height: 100,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => taps++, child: Text('row $i')),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Finder get _rail => find.byKey(const ValueKey('scroll_crown_rail'));
Finder get _gear => find.byKey(const ValueKey('scroll_crown_gear'));

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
  test('a drag maps the rail height onto the scrollable length', () {
    double map(double delta, {double start = 0}) =>
        ScrollCrown.offsetForDrag(startPixels: start, dragDelta: delta, railHeight: 700, minExtent: 0, maxExtent: 7000);
    expect(map(350), 3500, reason: 'half the rail is half the scroll length');
    expect(map(7), 70, reason: 'one tooth of drag is a tenth-of-a-percent step');
    expect(map(-100, start: 3500), 2500, reason: 'dragging up scrolls back');
    expect(map(2000), 7000, reason: 'clamped at the end');
    expect(map(-50), 0, reason: 'clamped at the start');
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
    expect(_rail, findsNothing, reason: 'the edge does not take drags while hidden');

    await _wake(tester);
    expect(_rail, findsOneWidget);

    await tester.pump(ScrollCrown.hideDelay + const Duration(milliseconds: 50));
    expect(_rail, findsNothing);
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
