import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/notice/notice.dart';
import 'package:pleya/widgets/notice/notice_card.dart';
import 'package:pleya/widgets/notice/notice_controller.dart';

/// The close affordance used to be the 18px glyph itself, with no padding and
/// a deferToChild hit test, so it laid out and hit-tested at 18×18. These
/// tests pin both halves: the box is large enough, and it actually responds
/// across its whole area rather than only on the glyph.
void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Widget wrap(Widget child) => MaterialApp(
    theme: monoTheme(dark: true),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomRight,
        child: SizedBox(width: 420, child: child),
      ),
    ),
  );

  NoticeEntry entryFor(Notice notice) => NoticeEntry(id: 'n1', notice: notice, count: 1);

  Future<int> pumpCard(WidgetTester tester, {bool tv = false, double scale = 1.0, Notice? notice}) async {
    var dismissals = 0;
    await tester.pumpWidget(
      wrap(
        NoticeCard(
          entry: entryFor(notice ?? const Notice(level: NoticeLevel.error, title: 'Boom', groupKey: 'b')),
          onDismiss: () => dismissals++,
          tv: tv,
          scale: scale,
        ),
      ),
    );
    return dismissals;
  }

  group('close target', () {
    testWidgets('is at least 44x44 on pointer and touch', (tester) async {
      await pumpCard(tester);
      final rect = tester.getRect(find.byKey(kNoticeCloseKey));
      expect(rect.width, greaterThanOrEqualTo(44.0));
      expect(rect.height, greaterThanOrEqualTo(44.0));
    });

    // Laying out at 48 proves nothing on its own: with the default
    // deferToChild behavior the box would still only hit-test on the glyph.
    testWidgets('responds in every corner, not just on the glyph', (tester) async {
      for (final corner in ['topLeft', 'topRight', 'bottomLeft', 'bottomRight']) {
        var dismissed = false;
        await tester.pumpWidget(
          wrap(
            NoticeCard(
              entry: entryFor(const Notice(level: NoticeLevel.error, title: 'Boom', groupKey: 'b')),
              onDismiss: () => dismissed = true,
            ),
          ),
        );
        final rect = tester.getRect(find.byKey(kNoticeCloseKey));
        final point = switch (corner) {
          'topLeft' => rect.topLeft + const Offset(1, 1),
          'topRight' => rect.topRight + const Offset(-1, 1),
          'bottomLeft' => rect.bottomLeft + const Offset(1, -1),
          _ => rect.bottomRight + const Offset(-1, -1),
        };
        await tester.tapAt(point);
        await tester.pump();
        expect(dismissed, isTrue, reason: corner);
      }
    });

    testWidgets('is scaled up for TV', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      await pumpCard(tester, tv: true, scale: 0.85);
      final rect = tester.getRect(find.byKey(kNoticeCloseKey));
      expect(rect.width, greaterThanOrEqualTo(kNoticeCloseTargetTv * 0.85));
      expect(rect.width, greaterThan(kNoticeCloseTargetTouch));
    });
  });

  group('close affordance accessibility', () {
    testWidgets('carries a tooltip that can actually be shown', (tester) async {
      await pumpCard(tester);
      expect(find.byTooltip(t.common.close), findsOneWidget);

      // NoticeHost lives above the Navigator, so there is no Overlay ancestor
      // unless it wraps one itself. Tooltip resolves the overlay lazily when
      // shown, so this long-press is the only thing that catches a missing one.
      await tester.longPress(find.byKey(kNoticeCloseKey));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('is announced as a button with a label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester);
      expect(
        tester.getSemantics(find.byKey(kNoticeCloseKey)),
        matchesSemantics(label: t.common.close, isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('TV rendering', () {
    // Nothing inside the card can ever hold focus: the host sits above the
    // Navigator, and directional traversal only walks the focused route's
    // scope. So the "unfocused" dim would never lift on a TV.
    testWidgets('does not render its buttons permanently dimmed', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      await pumpCard(
        tester,
        tv: true,
        notice: const Notice(
          level: NoticeLevel.error,
          title: 'Boom',
          groupKey: 'b',
          primary: NoticeAction(label: 'Retry', onPressed: _noop, recovery: true),
        ),
      );
      final buttons = tester.widgetList<FocusableButton>(find.byType(FocusableButton));
      expect(buttons, isNotEmpty);
      for (final button in buttons) {
        expect(button.dimWhenUnfocused, isFalse);
      }
    });
  });

  group('pointer absorption', () {
    testWidgets('a tap on the card padding does not fall through to the app', (tester) async {
      var behind = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Stack(
            children: [
              GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => behind++, child: const SizedBox.expand()),
              Align(
                alignment: Alignment.bottomRight,
                child: SizedBox(
                  width: 420,
                  child: NoticeCard(
                    entry: entryFor(const Notice(level: NoticeLevel.error, title: 'Boom', groupKey: 'b')),
                    onDismiss: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      final card = tester.getRect(find.byType(NoticeCard));
      await tester.tapAt(card.topLeft + const Offset(2, 2));
      await tester.pump();
      expect(behind, 0);
    });
  });
}

void _noop() {}
