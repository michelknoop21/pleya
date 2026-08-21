import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/apple_tv_scale.dart';
import 'package:pleya/widgets/notice/notice.dart';
import 'package:pleya/widgets/notice/notice_card.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';
import 'package:pleya/widgets/notice/notice_host.dart';

/// NoticeHost renders the global singleton, so every test drains it again.
void _drain() {
  for (final entry in noticeController.visible.toList()) {
    noticeController.dismiss(entry.id);
  }
}

void _noop() {}

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));
  tearDown(() {
    _drain();
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.debugSetTvOverride(null);
  });

  // Persistent on purpose: no pending timer to trip the test binding, and it
  // is the notice shape that actually depends on a working close affordance.
  Notice error({String title = 'Boom'}) => Notice(
    level: NoticeLevel.error,
    title: title,
    groupKey: title,
    primary: const NoticeAction(label: 'Retry', onPressed: _noop, recovery: true),
  );

  /// The real shape: a full-bleed app layer with the host stacked on top,
  /// and no Overlay above either of them.
  Future<int> pumpHost(WidgetTester tester) async {
    var behind = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => behind++),
              const NoticeHost(),
            ],
          ),
        ),
      ),
    );
    return behind;
  }

  group('pointer routing', () {
    testWidgets('a tap away from the cards reaches the app underneath', (tester) async {
      var behind = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => behind++),
                const NoticeHost(),
              ],
            ),
          ),
        ),
      );
      noticeController.show(error());
      await tester.pump();
      expect(find.byType(NoticeCard), findsOneWidget);

      // Opposite corner from every layer's alignment.
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(behind, 1);
    });

    testWidgets('a tap on a card does not reach the app underneath', (tester) async {
      var behind = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => behind++),
                const NoticeHost(),
              ],
            ),
          ),
        ),
      );
      noticeController.show(error());
      await tester.pump();

      await tester.tapAt(tester.getCenter(find.byType(NoticeCard)));
      await tester.pump();
      expect(behind, 0);
      expect(noticeController.visible, hasLength(1));
    });
  });

  group('manual dismissal', () {
    testWidgets('the close button removes the notice on the desktop layer', (tester) async {
      await pumpHost(tester);
      noticeController.show(error());
      await tester.pump();

      await tester.tap(find.byKey(kNoticeCloseKey));
      await tester.pump();
      expect(noticeController.visible, isEmpty);
    });

    testWidgets('the close button removes the notice on the TV layer', (tester) async {
      TvDetectionService.debugSetTvOverride(true);
      await pumpHost(tester);
      noticeController.show(error());
      await tester.pump();

      await tester.tap(find.byKey(kNoticeCloseKey));
      await tester.pump();
      expect(noticeController.visible, isEmpty);
    });

    // The mobile layer needs a mobile host OS, which the test runner is not,
    // so the swipe is exercised against the same Dismissible wrapping that
    // _MobileLayer builds. What is actually at risk is the card's new opaque
    // Listener swallowing the horizontal drag.
    testWidgets('a card inside a Dismissible still answers a swipe', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Dismissible(
                key: const ValueKey('card'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) => dismissed = true,
                child: NoticeCard(
                  entry: NoticeEntry(id: 'x', notice: error(), count: 1),
                  onDismiss: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(Dismissible), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });

    testWidgets('dismissing one card promotes a queued one into view', (tester) async {
      await pumpHost(tester);
      for (var i = 0; i < 4; i++) {
        noticeController.show(error(title: 'n$i'));
      }
      await tester.pump();
      expect(find.byType(NoticeCard), findsNWidgets(3));
      expect(find.text('n3'), findsNothing);

      await tester.tap(find.byKey(kNoticeCloseKey).first);
      await tester.pump();
      expect(find.text('n3'), findsOneWidget);
    });
  });

  // Regression: the host used to be a sibling of AppleTvScale, so a card was
  // drawn at 1× over a UI drawn at 1.85× and read its scale from a 1920-tall
  // MediaQuery that clamped to 1.0. It rendered at roughly half the size of
  // everything around it.
  testWidgets('a TV card is drawn in the same space as the app behind it', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    TvDetectionService.debugSetAppleTVOverride(true);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: AppleTvScale(
            child: Stack(fit: StackFit.expand, children: [const SizedBox.expand(), const NoticeHost()]),
          ),
        ),
      ),
    );
    noticeController.show(error());
    await tester.pump();

    final painted = tester.getRect(find.byType(NoticeCard)).width;
    expect(painted, greaterThan(500), reason: 'card must be scaled up with the rest of the tvOS UI');
    expect(painted, closeTo(420 * 0.85 * AppleTvScale.scale, 1.0));
  });
}
