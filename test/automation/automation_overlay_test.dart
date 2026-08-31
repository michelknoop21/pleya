import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_overlay.dart';

void main() {
  setUp(() => AutomationOverlayController.debugSetInstance(null));
  tearDown(() => AutomationOverlayController.debugSetInstance(null));

  test('copyWith only changes the given fields', () {
    const base = AutomationOverlayState();
    final flipped = base.copyWith(enabled: true);
    expect(flipped.enabled, isTrue);
    expect(flipped.showIds, base.showIds);
    expect(flipped.showBounds, base.showBounds);
  });

  testWidgets('is a true pass-through when kPleyaVerify is false (the default build)', (tester) async {
    await tester.pumpWidget(const AutomationOverlay(child: MaterialApp(home: Text('content'))));

    expect(find.text('content'), findsOneWidget);
    // The screenshot boundary never mounts under the default build — proof
    // /v1/screenshot has nothing to attach to outside kPleyaVerify.
    expect(automationScreenshotBoundaryKey.currentContext, isNull);
  });

  testWidgets('captureAutomationScreenshot returns a PNG for a mounted boundary', (tester) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: automationScreenshotBoundaryKey,
        child: const MaterialApp(home: ColoredBox(color: Colors.red)),
      ),
    );

    await tester.runAsync(() async {
      final png = await captureAutomationScreenshot();
      expect(png, isNotNull);
      // PNG magic bytes.
      expect(png!.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    });
  });

  test('captureAutomationScreenshot returns null when the boundary is not mounted', () async {
    final png = await captureAutomationScreenshot();
    expect(png, isNull);
  });
}
