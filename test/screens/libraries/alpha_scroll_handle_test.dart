import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_first_character.dart';
import 'package:pleya/screens/libraries/alpha_jump_helper.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown_painter.dart';
import 'package:pleya/screens/libraries/alpha_scroll_handle.dart';

const _chars = [
  LibraryFirstCharacter(key: '#', title: '#', size: 10),
  LibraryFirstCharacter(key: 'A', title: 'A', size: 10),
  LibraryFirstCharacter(key: 'B', title: 'B', size: 10),
  LibraryFirstCharacter(key: 'C', title: 'C', size: 10),
];

const _railHeight = 560.0;

/// Stands in for the browse tab: holds the scroll fraction and derives the
/// letter from it, the way the grid does from its scroll offset.
class _Host extends StatefulWidget {
  final List<double> scrubs;
  final List<int> jumps;
  final List<int> teeth;
  final List<int> letterTicks;
  final Duration Function() clock;
  final bool reduceMotion;

  const _Host({
    required this.scrubs,
    required this.jumps,
    required this.teeth,
    required this.letterTicks,
    required this.clock,
    this.reduceMotion = false,
  });

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final _helper = AlphaJumpHelper(_chars);
  double _fraction = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 700), disableAnimations: widget.reduceMotion),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              height: _railHeight,
              child: AlphaScrollHandle(
                firstCharacters: _chars,
                onJump: widget.jumps.add,
                onScrub: (f) {
                  widget.scrubs.add(f);
                  setState(() => _fraction = f);
                },
                readScrollFraction: () => _fraction,
                currentLetter: _helper.letterAtFraction(_fraction),
                onToothTick: () => widget.teeth.add(1),
                onLetterTick: () => widget.letterTicks.add(1),
                clock: widget.clock,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Rig {
  final scrubs = <double>[];
  final jumps = <int>[];
  final teeth = <int>[];
  final letterTicks = <int>[];
  Duration now = Duration.zero;

  Widget host({bool reduceMotion = false}) => _Host(
    scrubs: scrubs,
    jumps: jumps,
    teeth: teeth,
    letterTicks: letterTicks,
    clock: () => now,
    reduceMotion: reduceMotion,
  );
}

Finder get _rail => find.byKey(const ValueKey('alpha_scroll_rail'));

double _phase(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.byKey(const ValueKey('alpha_scroll_crown')));
  return (paint.painter! as ScrollCrownPainter).phase;
}

/// Drags down the rail from near its top in [steps] moves of [step] px,
/// advancing the fake clock by [msPerStep] each move.
Future<void> _drag(WidgetTester tester, _Rig rig, {required int steps, double step = 2, int msPerStep = 50}) async {
  final topLeft = tester.getTopLeft(_rail);
  final gesture = await tester.startGesture(topLeft + const Offset(22, 1));
  for (var i = 0; i < steps; i++) {
    rig.now += Duration(milliseconds: msPerStep);
    await gesture.moveBy(Offset(0, step));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  test('every letter maps to the cumulative start offset of its titles', () {
    final helper = AlphaJumpHelper(_chars);
    expect([for (final l in helper.letters) helper.indexForLetter(l)], [0, 10, 20, 30]);
    expect(helper.letterAtFraction(0.0), '#');
    expect(helper.letterAtFraction(0.26), 'A');
    expect(helper.letterAtFraction(0.99), 'C');
  });

  testWidgets('the rail maps the drag onto the whole scroll range', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.host());

    await _drag(tester, rig, steps: 140, step: 2);
    expect(rig.scrubs.last, closeTo(280 / _railHeight, 0.01), reason: 'half the rail is half the list');

    await _drag(tester, rig, steps: 200, step: 2);
    expect(rig.scrubs.last, 1.0, reason: 'clamped at the end of the list');
  });

  testWidgets('ratchet ticks scale with the drag distance', (tester) async {
    final short = _Rig();
    await tester.pumpWidget(short.host());
    await _drag(tester, short, steps: 35, step: 2); // 70 px
    // One tick per toothPitch; the touch slop before the drag is recognised
    // may cost one tooth.
    expect(short.teeth.length, inInclusiveRange(9, 10));

    final long = _Rig();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(long.host());
    await _drag(tester, long, steps: 70, step: 2); // 140 px
    expect(long.teeth.length, inInclusiveRange(19, 20));
  });

  testWidgets('a fast drag is capped by the tick rate limit', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.host());
    // 140 px in 70 moves of 5 ms: 20 teeth pass in 350 ms.
    await _drag(tester, rig, steps: 70, step: 2, msPerStep: 5);
    final cap = 350 ~/ AlphaScrollHandle.minTickInterval.inMilliseconds + 1;
    expect(rig.teeth.length, lessThanOrEqualTo(cap));
    expect(rig.teeth.length, greaterThan(0));
  });

  testWidgets('a letter change gives one firmer tick, none within a letter', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.host());

    await _drag(tester, rig, steps: 290, step: 2);

    expect(rig.letterTicks.length, 3, reason: '# to A, A to B, B to C');
  });

  testWidgets('the bubble shows the letter beside the finger while dragging', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.host());
    final gesture = await tester.startGesture(tester.getTopLeft(_rail) + const Offset(22, 1));
    for (var i = 0; i < 100; i++) {
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump();
    }
    expect(find.text('A'), findsOneWidget);
    final bubble = tester.getCenter(find.byKey(const ValueKey('alpha_scroll_bubble')));
    final finger = tester.getTopLeft(_rail).dy + 201;
    expect((bubble.dy - finger).abs(), lessThan(4), reason: 'bubble at finger height');
    await gesture.up();
  });

  testWidgets('the gear turns with the drag, but not under reduce motion', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.host());
    await _drag(tester, rig, steps: 30);
    expect(_phase(tester), greaterThan(0));

    final still = _Rig();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(still.host(reduceMotion: true));
    await _drag(tester, still, steps: 30);
    expect(_phase(tester), 0);
    expect(still.scrubs, isNotEmpty, reason: 'scrubbing still works');
    expect(still.teeth, isNotEmpty, reason: 'haptics stay on under reduce motion');
  });

  testWidgets('accessibility increase steps to the next letter', (tester) async {
    final rig = _Rig();
    await tester.pumpWidget(rig.host());
    final semantics = tester.ensureSemantics();
    final node = tester.getSemantics(find.byType(AlphaScrollHandle));
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(rig.jumps, [10]);
    expect(rig.letterTicks.length, 1);
    semantics.dispose();
  });
}
