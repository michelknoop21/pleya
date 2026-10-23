// The alphabet is a passive label on the same ScrollCrown used on other pages.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown_gear.dart';

class _Rig {
  final controller = ScrollController(initialScrollOffset: 3000);
  final label = ValueNotifier('B');
  final ticks = <int>[];
  Duration now = Duration.zero;
  int userScrolls = 0;
  Widget host() => MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<String>(
        valueListenable: label,
        builder: (_, value, _) => ScrollCrown(
          enabled: true,
          controller: controller,
          positionLabel: value,
          clock: () => now,
          onToothTick: () => ticks.add(1),
          onScrubStart: () => userScrolls++,
          child: ListView.builder(
            controller: controller,
            itemExtent: 72,
            itemCount: 100,
            itemBuilder: (_, i) => Text('title $i'),
          ),
        ),
      ),
    ),
  );
  void dispose() {
    controller.dispose();
    label.dispose();
  }
}

Future<TestGesture> _start(WidgetTester tester, _Rig rig, Offset position) async {
  final gesture = await tester.createGesture();
  await gesture.down(position, timeStamp: rig.now);
  return gesture;
}

Future<void> _mount(WidgetTester tester, _Rig rig) async {
  tester.view.physicalSize = const Size(400, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(rig.dispose);
  await tester.pumpWidget(rig.host());
  await tester.pump();
  await tester.tapAt(const Offset(380, 350));
  await tester.pump();
}

Future<void> _drag(WidgetTester tester, _Rig rig, double dy) async {
  final gesture = await _start(tester, rig, const Offset(380, 350));
  rig.now += const Duration(seconds: 1);
  await gesture.moveBy(Offset(0, dy), timeStamp: rig.now);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('library has one shared wheel; changing letter changes no motion or haptics', (tester) async {
    final rig = _Rig();
    await _mount(tester, rig);
    expect(find.byType(ScrollCrown), findsOneWidget);
    expect(find.byType(ScrollCrownGear), findsOneWidget);
    final before = rig.controller.offset;
    final ticks = rig.ticks.length;
    rig.label.value = 'C';
    await tester.pump();
    expect(find.text('C'), findsOneWidget);
    expect(rig.controller.offset, before);
    expect(rig.ticks.length, ticks);
    await _drag(tester, rig, 24);
    expect(rig.controller.offset, greaterThan(before));
  });

  testWidgets('a label does not change the drag response', (tester) async {
    final labelled = _Rig();
    await _mount(tester, labelled);
    await _drag(tester, labelled, 24);
    final labelledOffset = labelled.controller.offset;
    await tester.pumpWidget(const SizedBox());
    final plain = _Rig()..label.value = '';
    await _mount(tester, plain);
    await _drag(tester, plain, 24);
    expect(plain.controller.offset, labelledOffset);
  });

  testWidgets('VoiceOver uses the same page action with and without an alphabet', (tester) async {
    final rig = _Rig();
    await _mount(tester, rig);
    final semantics = tester.ensureSemantics();

    final node = tester.getSemantics(
      find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.slider == true),
    );
    final before = rig.controller.offset;
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(rig.controller.offset, closeTo(before + rig.controller.position.viewportDimension * .8, .01));
    expect(rig.userScrolls, 1);
    semantics.dispose();
  });
}
