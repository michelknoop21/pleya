import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv_virtual_keyboard.dart';

void main() {
  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('select inserts the highlighted character', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller: controller);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(controller.text, '1');
  });

  testWidgets('down past the bottom row fires onNavigateDown instead of wrapping', (tester) async {
    final controller = TextEditingController();
    var navigatedDown = 0;
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller: controller, onNavigateDown: () => navigatedDown++);

    // Main layout has 5 rows; start on row 0.
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(navigatedDown, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(navigatedDown, 1);
  });

  testWidgets('up past the top row fires onNavigateUp instead of wrapping', (tester) async {
    final controller = TextEditingController();
    var navigatedUp = 0;
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller: controller, onNavigateUp: () => navigatedUp++);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(navigatedUp, 1);
  });

  testWidgets('back key fires onClose', (tester) async {
    final controller = TextEditingController();
    var closed = 0;
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller: controller, onClose: () => closed++);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, 0);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('showCancelKey false hides the Cancel key', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller: controller, showCancelKey: false);

    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('done key calls onSubmitted without needing a navigator pop', (tester) async {
    final controller = TextEditingController(text: 'abc');
    String? submitted;
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller: controller, onSubmitted: (value) => submitted = value);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(submitted, 'abc');
    expect(find.byKey(const Key('tv_virtual_keyboard_panel')), findsOneWidget);
  });

  testWidgets('physical keyboard input does not dismiss when disabled', (tester) async {
    final controller = TextEditingController();
    var closed = 0;
    addTearDown(controller.dispose);

    await _pumpPanel(tester, controller: controller, onClose: () => closed++, dismissOnPhysicalKeyboardInput: false);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.pumpAndSettle();

    expect(controller.text, 'a');
    expect(closed, 0);
  });

  testWidgets('an unmapped key falls through to ancestor handlers', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    final seenByAncestor = <LogicalKeyboardKey>[];
    TvDetectionService.debugSetAppleTVOverride(true);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent) seenByAncestor.add(event.logicalKey);
              return KeyEventResult.ignored;
            },
            child: Center(child: TvVirtualKeyboardPanel(controller: controller, showPreview: false)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The panel is permanently focused on the search page. If it claimed every
    // key, global TV shortcuts would be dead there — so anything it does not
    // act on has to keep travelling up.
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();

    expect(seenByAncestor, contains(LogicalKeyboardKey.f5));
    // ...and it genuinely did not treat it as text.
    expect(controller.text, isEmpty);
  });
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required TextEditingController controller,
  ValueChanged<String>? onSubmitted,
  VoidCallback? onClose,
  VoidCallback? onNavigateDown,
  VoidCallback? onNavigateUp,
  bool showCancelKey = true,
  bool dismissOnPhysicalKeyboardInput = true,
}) async {
  TvDetectionService.debugSetAppleTVOverride(true);
  await tester.binding.setSurfaceSize(const Size(1280, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: TvVirtualKeyboardPanel(
            controller: controller,
            showPreview: false,
            onSubmitted: onSubmitted,
            onClose: onClose,
            onNavigateDown: onNavigateDown,
            onNavigateUp: onNavigateUp,
            showCancelKey: showCancelKey,
            dismissOnPhysicalKeyboardInput: dismissOnPhysicalKeyboardInput,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
