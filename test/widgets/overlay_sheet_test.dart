import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/overlay_sheet_geometry.dart';

void main() {
  testWidgets('scrollable sheet does not attach to parent primary controller', (tester) async {
    final parentController = ScrollController();
    addTearDown(parentController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: PrimaryScrollController(
          controller: parentController,
          child: OverlaySheetHost(
            child: Scaffold(
              body: CustomScrollView(
                primary: true,
                slivers: [
                  SliverFillRemaining(
                    child: Center(
                      child: Builder(
                        builder: (context) => ElevatedButton(
                          onPressed: () {
                            OverlaySheetController.of(context).show<void>(
                              builder: (_) => ListView.builder(
                                itemCount: 30,
                                itemBuilder: (_, index) => ListTile(title: Text('Item $index')),
                              ),
                            );
                          },
                          child: const Text('Open'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(parentController.positions.length, 1);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(parentController.positions.length, 1);
    expect(find.text('Item 0'), findsOneWidget);
  });

  group('opt-in canPop / onSystemBack', () {
    // Pushes an OverlaySheetHost route on top of a home route so we can observe
    // whether a simulated system back pops the route. The host's child has an
    // "Open" button that shows a sheet containing "SHEET".
    Future<void> pushHost(WidgetTester tester, {required bool? canPop, VoidCallback? onSystemBack}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OverlaySheetHost(
                        canPop: canPop,
                        onSystemBack: onSystemBack,
                        child: Scaffold(
                          body: Builder(
                            builder: (sheetContext) => Center(
                              child: ElevatedButton(
                                onPressed: () => OverlaySheetController.of(sheetContext).show<void>(
                                  builder: (_) => const SizedBox(height: 120, child: Center(child: Text('SHEET'))),
                                ),
                                child: const Text('Open'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Push'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget, reason: 'host route is shown');
    }

    testWidgets('canPop null installs no PopScope (system back pops the route)', (tester) async {
      await pushHost(tester, canPop: null);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsNothing, reason: 'route popped back to home');
      expect(find.text('Push'), findsOneWidget);
    });

    testWidgets('canPop true pops the route natively on system back', (tester) async {
      await pushHost(tester, canPop: true);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsNothing, reason: 'route popped');
    });

    testWidgets('canPop false blocks the pop and runs onSystemBack', (tester) async {
      var backs = 0;
      await pushHost(tester, canPop: false, onSystemBack: () => backs++);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget, reason: 'route not popped');
      expect(backs, 1);
    });

    testWidgets('system back closes an open sheet instead of popping or running onSystemBack', (tester) async {
      var backs = 0;
      await pushHost(tester, canPop: false, onSystemBack: () => backs++);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('SHEET'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('SHEET'), findsNothing, reason: 'sheet closed');
      expect(find.text('Open'), findsOneWidget, reason: 'screen not popped');
      expect(backs, 0, reason: 'onSystemBack not called while a sheet was open');
    });
  });

  testWidgets('back key closes the sheet even when focus escaped outside it', (tester) async {
    final outsideNode = FocusNode(debugLabel: 'outside');
    addTearDown(outsideNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: OverlaySheetHost(
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  Focus(focusNode: outsideNode, child: const SizedBox(width: 10, height: 10)),
                  ElevatedButton(
                    onPressed: () => OverlaySheetController.of(context).show<void>(
                      builder: (_) => const SizedBox(height: 120, child: Center(child: Text('SHEET'))),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('SHEET'), findsOneWidget);

    // Focus escapes the sheet (the bug scenario: a background screen
    // re-requested focus). The host's fallback handler must still close.
    outsideNode.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('SHEET'), findsNothing, reason: 'sheet closed via escaped-focus fallback');
  });

  group('presentation placement', () {
    const viewport = Size(1440, 900);

    /// Rect of the sheet surface itself (the Material inside the sheet's
    /// layout delegate), which is what the user sees land in the wrong corner.
    Rect sheetRect(WidgetTester tester) {
      return tester.getRect(
        find.descendant(of: find.byType(CustomSingleChildLayout), matching: find.byType(Material)).first,
      );
    }

    Future<void> pumpHost(
      WidgetTester tester, {
      required OverlaySheetPresentation presentation,
      int itemCount = 1,
    }) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: OverlaySheetHost(
            // Keyed by presentation so re-pumping in one test builds a fresh
            // host instead of inheriting the previous one's open sheet.
            key: ValueKey(presentation),
            child: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => OverlaySheetController.of(context).show<void>(
                      presentation: presentation,
                      builder: (_) => ListView.builder(
                        itemCount: itemCount,
                        itemBuilder: (_, i) => SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: Center(child: Text('Item $i')),
                        ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// Parks the mouse near the right edge, the way clicking a header action in
    /// the top-right corner does.
    Future<void> moveMouseToRightEdge(WidgetTester tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(() => mouse.removePointer());
      await mouse.addPointer(location: const Offset(1400, 60));
      await mouse.moveTo(const Offset(1400, 60));
      await tester.pump();
    }

    testWidgets('panel opens centred and fully on screen despite the mouse being far right', (tester) async {
      await pumpHost(tester, presentation: OverlaySheetPresentation.panel);
      await moveMouseToRightEdge(tester);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final rect = sheetRect(tester);
      expect(rect.center.dx, moreOrLessEquals(viewport.width / 2, epsilon: 1));
      expect(rect.left, greaterThanOrEqualTo(24));
      expect(rect.right, lessThanOrEqualTo(viewport.width - 24));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(viewport.height));
    });

    testWidgets('sheet still anchors to the mouse, so context menus keep opening at the cursor', (tester) async {
      await pumpHost(tester, presentation: OverlaySheetPresentation.sheet);
      await moveMouseToRightEdge(tester);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final rect = sheetRect(tester);
      expect(
        rect.center.dx,
        greaterThan(viewport.width / 2 + 100),
        reason: 'pointer-anchored: pushed towards the cursor, not centred',
      );
      expect(rect.right, lessThanOrEqualTo(viewport.width - 16));
    });

    testWidgets('a long list scrolls inside the panel instead of overflowing', (tester) async {
      await pumpHost(tester, presentation: OverlaySheetPresentation.panel, itemCount: 80);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final rect = sheetRect(tester);
      expect(rect.height, lessThanOrEqualTo(viewport.height * 0.8));
      expect(find.text('Item 0'), findsOneWidget);

      await tester.drag(find.text('Item 1'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Item 0'), findsNothing, reason: 'the list scrolled inside the panel');
      expect(tester.takeException(), isNull);
    });

    testWidgets('escape closes a panel', (tester) async {
      await pumpHost(tester, presentation: OverlaySheetPresentation.panel);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Item 0'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Item 0'), findsNothing);
    });

    // Until fase 4 a TV panel fell through to the compact bottom sheet, so the
    // source picker of hoofdstuk 14.1 would have opened as a mobile sheet on a
    // television. The two presentations now mean different things on TV, and
    // the sheet's own numbers are unchanged — which is what these two pin.
    testWidgets('on TV a panel is a centred modal, not the compact sheet', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      await pumpHost(tester, presentation: OverlaySheetPresentation.sheet);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final sheet = sheetRect(tester);

      await pumpHost(tester, presentation: OverlaySheetPresentation.panel);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final panel = sheetRect(tester);

      expect(panel, isNot(sheet));
      expect(panel.center.dx, moreOrLessEquals(viewport.width / 2, epsilon: 1));
      expect(panel.center.dy, moreOrLessEquals(viewport.height / 2, epsilon: 1));
      expect(panel.width, greaterThan(sheet.width));
      // Generous outer margins: a 10-foot modal floats, it does not fill. The
      // width band of 14.1 is a reference measurement on a 1920x1080 output,
      // so it is checked as a proportion — see `overlay_sheet_geometry_test`.
      expect(panel.left, greaterThan(viewport.width * 0.2));
      expect(panel.right, lessThan(viewport.width * 0.8));
    });

    testWidgets('on TV the sheet keeps its own compact placement', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      await pumpHost(tester, presentation: OverlaySheetPresentation.sheet);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final sheet = sheetRect(tester);
      expect(sheet.width, lessThanOrEqualTo(400));
      expect(sheet.bottom, moreOrLessEquals(viewport.height, epsilon: 1), reason: 'still hangs off the bottom edge');
    });
  });
}
