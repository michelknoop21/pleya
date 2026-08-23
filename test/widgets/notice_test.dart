import 'dart:async';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/notice/notice.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';

/// WCAG 2.1 relative luminance / contrast ratio, for opaque colours.
/// Mirrors `test/theme/artwork_contrast_test.dart` — computed from the live
/// tokens, never hardcoded.
double _luminance(Color c) {
  double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  MonoTokens tokensOf(ThemeData theme) => theme.extension<MonoTokens>()!;

  final dark = tokensOf(monoTheme(dark: true));
  final oled = tokensOf(monoTheme(dark: true, oled: true));
  final light = tokensOf(monoTheme(dark: false));

  group('notice level contrast', () {
    // Icon ink for each level, against the exact surface it renders on
    // (NoticeCard's background is always tokens(context).surfaceElevated).
    final cases = <String, Color Function(MonoTokens)>{
      'error': (t) => t.isLight ? kNoticeErrorLight : kNoticeErrorDark,
      'warning': (t) => t.isLight ? kNoticeWarningLight : kNoticeWarningDark,
      'success': (t) => t.isLight ? kNoticeSuccessLight : kNoticeSuccessDark,
      'info': (t) => t.isLight ? kNoticeInfoLight : kNoticeInfoDark,
    };

    for (final entry in cases.entries) {
      test('${entry.key} clears AA (4.5:1) in dark, oled, and light', () {
        for (final t in [dark, oled, light]) {
          final ratio = _contrast(entry.value(t), t.surfaceElevated);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '${entry.key} on surfaceElevated, isLight=${t.isLight}');
        }
      });
    }

    test('dark and OLED share the same surfaceElevated, so share the same ink', () {
      expect(dark.surfaceElevated, oled.surfaceElevated);
      for (final color in cases.values) {
        expect(color(dark), color(oled));
      }
    });
  });

  group('Notice duration', () {
    test('error is persistent (no auto-dismiss)', () {
      expect(noticeDurationFor(NoticeLevel.error), isNull);
    });

    test('success, info, and warning all auto-dismiss', () {
      expect(noticeDurationFor(NoticeLevel.success), isNotNull);
      expect(noticeDurationFor(NoticeLevel.info), isNotNull);
      expect(noticeDurationFor(NoticeLevel.warning), isNotNull);
    });
  });

  group('NoticeController persistence and dismissal', () {
    test('an error notice stays visible past its would-be duration', () {
      fakeAsync((async) {
        final controller = NoticeController();
        controller.show(const Notice(level: NoticeLevel.error, title: 'Boom', groupKey: 'boom'));
        async.elapse(const Duration(minutes: 5));
        expect(controller.visible, hasLength(1));
      });
    });

    test('a success notice auto-dismisses after its duration', () {
      fakeAsync((async) {
        final controller = NoticeController();
        controller.show(const Notice(level: NoticeLevel.success, title: 'Saved', groupKey: 'saved'));
        expect(controller.visible, hasLength(1));
        async.elapse(noticeDurationFor(NoticeLevel.success)! + const Duration(seconds: 1));
        expect(controller.visible, isEmpty);
      });
    });
  });

  group('NoticeController grouping', () {
    test('five notices with the same groupKey fold into one card with count 5', () {
      final controller = NoticeController();
      for (var i = 0; i < 5; i++) {
        controller.show(const Notice(level: NoticeLevel.warning, title: 'Retrying…', groupKey: 'retry-server-x'));
      }
      expect(controller.visible, hasLength(1));
      expect(controller.visible.single.count, 5);
    });

    test('a changing countdown folds into one card carrying the newest text', () {
      // The rate-limit message renders its remaining seconds into the text,
      // so the rendered string is a different dedupe key every second.
      // Callers pass a stable groupKey for exactly this case, and the fold
      // keeps the newest text so the number on screen does not go stale.
      final controller = NoticeController();
      controller.show(
        const Notice(level: NoticeLevel.error, title: 'Try again in 60 seconds', groupKey: 'logs.upload.rateLimited'),
      );
      controller.show(
        const Notice(level: NoticeLevel.error, title: 'Try again in 58 seconds', groupKey: 'logs.upload.rateLimited'),
      );
      expect(controller.visible, hasLength(1));
      expect(controller.visible.single.notice.title, 'Try again in 58 seconds');
    });

    test('different groupKeys do not fold', () {
      final controller = NoticeController();
      controller.show(const Notice(level: NoticeLevel.error, title: 'A', groupKey: 'a'));
      controller.show(const Notice(level: NoticeLevel.error, title: 'B', groupKey: 'b'));
      expect(controller.visible, hasLength(2));
    });
  });

  group('NoticeController queue', () {
    test('at most 3 notices are visible at once; the rest queue', () {
      final controller = NoticeController();
      for (var i = 0; i < 4; i++) {
        controller.show(Notice(level: NoticeLevel.warning, title: 'n$i', groupKey: 'group-$i'));
      }
      expect(controller.visible, hasLength(3));
    });

    test('dismissing a visible notice promotes the oldest queued one', () {
      final controller = NoticeController();
      final ids = [
        for (var i = 0; i < 4; i++)
          controller.show(Notice(level: NoticeLevel.warning, title: 'n$i', groupKey: 'group-$i')),
      ];
      expect(controller.visible.map((e) => e.notice.title), ['n0', 'n1', 'n2']);

      controller.dismiss(ids[0]);

      expect(controller.visible, hasLength(3));
      expect(controller.visible.map((e) => e.notice.title), containsAll(['n1', 'n2', 'n3']));
    });
  });

  group('NoticeAction context', () {
    // The exact regression the ProfileNavigationScope gotcha warns about: an
    // action built with a BuildContext from inside a nested Navigator must
    // navigate on *that* navigator when invoked, never on whatever context
    // NoticeHost itself would have (which sits outside that scope).
    testWidgets('runs the callback captured at the action call site, not the host', (tester) async {
      final outerNavKey = GlobalKey<NavigatorState>();
      final innerNavKey = GlobalKey<NavigatorState>();
      late BuildContext innerContext;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: outerNavKey,
          home: Navigator(
            key: innerNavKey,
            onGenerateRoute: (settings) => MaterialPageRoute(
              builder: (context) {
                innerContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = NoticeController();
      final action = NoticeAction(
        label: 'Open',
        onPressed: () {
          Navigator.of(innerContext).push(MaterialPageRoute(builder: (_) => const Text('pushed-by-notice-action')));
        },
      );
      final id = controller.show(Notice(level: NoticeLevel.error, title: 'Err', primary: action, groupKey: 'nav'));

      controller.runAction(id, action);
      await tester.pumpAndSettle();

      expect(find.text('pushed-by-notice-action'), findsOneWidget);
      expect(innerNavKey.currentState!.canPop(), isTrue);
      expect(outerNavKey.currentState!.canPop(), isFalse);
    });

    test('running an action dismisses its notice', () {
      final controller = NoticeController();
      var ran = false;
      final action = NoticeAction(label: 'Retry', onPressed: () => ran = true);
      final id = controller.show(Notice(level: NoticeLevel.error, title: 'Err', primary: action, groupKey: 'g'));

      controller.runAction(id, action);

      expect(ran, isTrue);
      expect(controller.visible, isEmpty);
    });
  });

  group('NoticeController runAction error safety', () {
    test('a synchronously-throwing action does not crash runAction', () {
      final controller = NoticeController();
      final action = NoticeAction(label: 'Boom', onPressed: () => throw Exception('sync boom'));
      final id = controller.show(Notice(level: NoticeLevel.error, title: 'Err', primary: action, groupKey: 'g1'));

      expect(() => controller.runAction(id, action), returnsNormally);
      expect(controller.visible, isEmpty);
    });

    test('an asynchronously-rejecting action does not become an unhandled Future error', () async {
      final controller = NoticeController();
      final action = NoticeAction(
        label: 'Boom',
        onPressed: () async {
          await Future<void>.delayed(Duration.zero);
          throw Exception('async boom');
        },
      );
      final id = controller.show(Notice(level: NoticeLevel.error, title: 'Err', primary: action, groupKey: 'g2'));

      var caughtByZone = false;
      await runZonedGuarded(() async {
        controller.runAction(id, action);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }, (error, stack) => caughtByZone = true);

      expect(caughtByZone, isFalse);
      expect(controller.visible, isEmpty);
    });
  });
}
