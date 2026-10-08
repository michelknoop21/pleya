import 'dart:async';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/notice/notice.dart';
import 'package:pleya/widgets/notice/notice_card.dart';
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

  testWidgets('only busy notices declare an automation identity', (tester) async {
    for (final busy in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: NoticeCard(
              entry: NoticeEntry(
                id: 'notice-7',
                notice: Notice(level: NoticeLevel.info, title: 'Preparing', groupKey: 'preparation', busy: busy),
                count: 1,
              ),
              onDismiss: () {},
            ),
          ),
        ),
      );
      final node = tester.widget<AutomationNode>(find.byType(AutomationNode).first);
      expect(node.id, busy ? AutomationIds.noticeBusy : null);
      expect(node.instance, busy ? 'notice-7' : null);
    }
  });

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

  group('busy notice', () {
    test('never auto-dismisses, whatever its level or override says', () {
      const notice = Notice(
        level: NoticeLevel.info,
        title: 'Starting playback',
        groupKey: 'busy',
        durationOverride: Duration(seconds: 1),
        busy: true,
      );
      expect(notice.duration, isNull);
    });

    testWidgets('shows a spinner and leaves focus where it was', (tester) async {
      final origin = FocusNode();
      addTearDown(origin.dispose);
      const entry = NoticeEntry(
        id: 'n',
        notice: Notice(
          level: NoticeLevel.info,
          title: 'Starting playback',
          body: 'Movie 1',
          groupKey: 'busy',
          busy: true,
        ),
        count: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Column(
            children: [
              Focus(focusNode: origin, autofocus: true, child: const SizedBox(width: 10, height: 10)),
              NoticeCard(entry: entry, onDismiss: () {}, tv: true),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Movie 1'), findsOneWidget);
      expect(origin.hasPrimaryFocus, isTrue, reason: 'the card that started playback keeps focus');
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

  group('NoticeController repeat folding', () {
    // Three identical "Playback stopped" cards stacked in a column was the
    // reported bug: an error never auto-dismisses, so every repeat past the
    // dedupe window used to open a new card under the one still standing.
    test('a persistent error folds into the standing one past the dedupe window', () {
      fakeAsync((async) {
        final controller = NoticeController();
        for (var i = 0; i < 3; i++) {
          controller.show(const Notice(level: NoticeLevel.error, title: 'Playback stopped', groupKey: 'playback:x'));
          async.elapse(NoticeController.dedupeWindow * 2);
        }
        expect(controller.visible, hasLength(1));
        expect(controller.visible.single.count, 3);
      });
    });

    test('a timed notice past the dedupe window is a new card, not a fold', () {
      fakeAsync((async) {
        final controller = NoticeController();
        controller.show(const Notice(level: NoticeLevel.warning, title: 'Retrying', groupKey: 'retry'));
        async.elapse(NoticeController.dedupeWindow * 2);
        controller.show(const Notice(level: NoticeLevel.warning, title: 'Retrying', groupKey: 'retry'));
        expect(controller.visible, hasLength(1));
        expect(controller.visible.single.count, 1);
      });
    });
  });

  group('NoticeController dismissWhere', () {
    test('clears only the notices whose group matches', () {
      final controller = NoticeController();
      controller.show(const Notice(level: NoticeLevel.error, title: 'Stopped', groupKey: 'playback:unknown'));
      controller.show(const Notice(level: NoticeLevel.error, title: 'Gone', groupKey: 'playback:fileUnavailable'));
      controller.show(const Notice(level: NoticeLevel.error, title: 'Offline', groupKey: 'connection:server'));

      controller.dismissWhere((notice) => notice.groupKey.startsWith('playback:'));

      expect(controller.visible, hasLength(1));
      expect(controller.visible.single.notice.groupKey, 'connection:server');
    });

    test('clears queued notices too, so nothing is promoted afterwards', () {
      final controller = NoticeController();
      for (var i = 0; i < NoticeController.maxVisible + 2; i++) {
        controller.show(Notice(level: NoticeLevel.error, title: 'Stopped $i', groupKey: 'playback:$i'));
      }
      controller.dismissWhere((notice) => notice.groupKey.startsWith('playback:'));
      expect(controller.visible, isEmpty);
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

  group('NoticeController busy lifecycle', () {
    const busy = Notice(level: NoticeLevel.info, title: 'Starting playback', groupKey: 'playback-start:x', busy: true);

    NoticeController withStandingErrors() {
      final controller = NoticeController();
      for (var i = 0; i < NoticeController.maxVisible; i++) {
        controller.show(Notice(level: NoticeLevel.error, title: 'e$i', groupKey: 'error-$i'));
      }
      return controller;
    }

    Iterable<String> titles(NoticeController controller) => controller.visible.map((e) => e.notice.title);

    // Three errors nobody dismissed used to push the start notice into the
    // queue, where it sat until the start was over and it was dismissed
    // without ever rendering.
    test('shows at once when three persistent notices already fill the screen', () {
      final controller = withStandingErrors();

      final id = controller.show(busy);

      expect(controller.visible, hasLength(NoticeController.maxVisible));
      expect(controller.visible.map((e) => e.id), contains(id));
      expect(titles(controller), ['e0', 'e1', 'Starting playback']);
    });

    test('the notice it displaced comes back when the work ends', () {
      final controller = withStandingErrors();
      final id = controller.show(busy);

      controller.dismiss(id);

      expect(titles(controller), ['e0', 'e1', 'e2']);
    });

    test('a displaced notice comes back ahead of what was already waiting', () {
      final controller = withStandingErrors();
      controller.show(const Notice(level: NoticeLevel.error, title: 'waiting', groupKey: 'waiting'));
      final id = controller.show(busy);

      controller.dismiss(id);

      expect(titles(controller), ['e0', 'e1', 'e2']);
    });

    test('two starts with the same groupKey keep their own card and their own lifetime', () {
      final controller = NoticeController();

      final first = controller.show(busy);
      final second = controller.show(busy);

      expect(first, isNot(second));
      expect(controller.visible, hasLength(2));
      expect(controller.visible.map((e) => e.count), everyElement(1));

      controller.dismiss(first);

      expect(controller.visible.single.id, second, reason: 'the other start is still preparing');
    });

    test('an ordinary notice with the same key does not fold into a busy one', () {
      final controller = NoticeController();
      final busyId = controller.show(busy);

      final plainId = controller.show(
        const Notice(level: NoticeLevel.info, title: 'Started', groupKey: 'playback-start:x'),
      );

      expect(plainId, isNot(busyId));
      expect(controller.visible, hasLength(2));
    });

    test('a fourth busy notice waits for a busy one to end and displaces nothing more', () {
      final controller = withStandingErrors();
      final ids = [for (var i = 0; i < NoticeController.maxVisible + 1; i++) controller.show(busy)];
      expect(controller.visible.map((e) => e.id), ids.take(NoticeController.maxVisible));

      for (final id in ids) {
        controller.dismiss(id);
      }

      expect(titles(controller), unorderedEquals(['e0', 'e1', 'e2']));
    });

    test('a displaced notice survives a full queue, and the queue stays bounded', () {
      final controller = withStandingErrors();
      for (var i = 0; i < NoticeController.maxQueued; i++) {
        controller.show(Notice(level: NoticeLevel.error, title: 'q$i', groupKey: 'queued-$i'));
      }
      final id = controller.show(busy);
      // One more ordinary notice against the full queue drops the oldest
      // waiting one, which must not be the notice the spinner pushed aside.
      controller.show(const Notice(level: NoticeLevel.error, title: 'late', groupKey: 'late'));

      controller.dismiss(id);
      expect(titles(controller), ['e0', 'e1', 'e2']);

      var total = 0;
      while (controller.visible.isNotEmpty) {
        controller.dismiss(controller.visible.first.id);
        total++;
      }
      // The displaced notice held one of the queue's places while it waited.
      expect(total, NoticeController.maxVisible + NoticeController.maxQueued - 1);
    });

    test('a timed notice next to a busy one still leaves on its own timer', () {
      fakeAsync((async) {
        final controller = NoticeController();
        controller.show(const Notice(level: NoticeLevel.success, title: 'Saved', groupKey: 'saved'));
        controller.show(const Notice(level: NoticeLevel.error, title: 'e0', groupKey: 'error-0'));
        controller.show(const Notice(level: NoticeLevel.error, title: 'e1', groupKey: 'error-1'));
        async.elapse(const Duration(seconds: 1));
        controller.show(busy);
        expect(titles(controller), ['Saved', 'e0', 'Starting playback']);

        async.elapse(noticeDurationFor(NoticeLevel.success)! - const Duration(milliseconds: 1500));
        expect(titles(controller), contains('Saved'), reason: 'the busy notice did not restart its clock');
        async.elapse(const Duration(seconds: 1));

        expect(titles(controller), ['e0', 'Starting playback', 'e1']);
      });
    });

    test('a displaced timed notice is not timed out off screen and gets its full stay back', () {
      fakeAsync((async) {
        final controller = NoticeController();
        controller.show(const Notice(level: NoticeLevel.error, title: 'e0', groupKey: 'error-0'));
        controller.show(const Notice(level: NoticeLevel.error, title: 'e1', groupKey: 'error-1'));
        controller.show(const Notice(level: NoticeLevel.success, title: 'Saved', groupKey: 'saved'));
        final id = controller.show(busy);
        expect(titles(controller), ['e0', 'e1', 'Starting playback']);

        async.elapse(const Duration(minutes: 1));
        controller.dismiss(id);
        expect(titles(controller), ['e0', 'e1', 'Saved']);

        async.elapse(noticeDurationFor(NoticeLevel.success)! - const Duration(milliseconds: 100));
        expect(titles(controller), contains('Saved'));
        async.elapse(const Duration(seconds: 1));
        expect(titles(controller), ['e0', 'e1']);
      });
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
