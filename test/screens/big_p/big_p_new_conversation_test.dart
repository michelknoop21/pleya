/// "Nieuw gesprek" on iPhone and iPad (mockup 40 A): when it shows, what a
/// tap does, and its alignment against the question field, the send button,
/// the follow-ups and Big P over the viewport matrix of the density audit.
///
/// Shots (screen, size, file) go to NEWCONV_SHOT_DIR when it is set.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/focus/focusable_text_field.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/screens/big_p/big_p_new_conversation_button.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:pleya/widgets/big_p/big_p_scale.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/golden.dart';
import '../../widgets/big_p/fake_assistant_controller.dart';
import '../tv/assistant/tv_assistant_test_support.dart' show settle;
import 'big_p_mobile_fixtures.dart';
import 'big_p_mobile_shots_test.dart' show precacheBigP;

final _shotDir = Platform.environment['NEWCONV_SHOT_DIR'];

typedef _Viewport = ({String name, Size size, EdgeInsets safe});

const _matrix = <_Viewport>[
  (name: 'se-375x667', size: Size(375, 667), safe: EdgeInsets.only(top: 20)),
  (name: 'iphone-402x874', size: Size(402, 874), safe: EdgeInsets.only(top: 54, bottom: 34)),
  (name: 'iphone-440x956', size: Size(440, 956), safe: EdgeInsets.only(top: 62, bottom: 34)),
  (name: 'ipad-744x1133', size: Size(744, 1133), safe: EdgeInsets.only(top: 24, bottom: 20)),
  (name: 'ipad-1024x1366', size: Size(1024, 1366), safe: EdgeInsets.only(top: 24, bottom: 20)),
  (name: 'split-507x744', size: Size(507, 744), safe: EdgeInsets.only(top: 24, bottom: 20)),
];

void main() {
  late FakeAssistantController c;
  late BigPMobileSession session;
  final boundary = GlobalKey();

  setUpAll(() async {
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = FakeAssistantController();
    session = BigPMobileSession(c);
    addTearDown(() {
      session.dispose();
      c.dispose();
    });
  });

  Future<void> pumpHost(WidgetTester tester, _Viewport v, {double textScale = 1}) async {
    tester.view.physicalSize = v.size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    session.summon();
    final theme = monoTheme(dark: true);
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<BigPMobileSession>.value(
          value: session,
          child: MaterialApp(
            theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Inter')),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: TextScaler.linear(textScale),
                  viewPadding: v.safe,
                  padding: v.safe,
                ),
                child: RepaintBoundary(
                  key: boundary,
                  child: const ColoredBox(
                    color: Color(0xFF0A0A0A),
                    child: Stack(fit: StackFit.expand, children: [Scaffold(), BigPMobileHost()]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Finder button() => find.byType(BigPNewConversationButton);
  Finder send() =>
      find.ancestor(of: find.byIcon(Symbols.arrow_upward_rounded), matching: find.byType(GestureDetector)).first;

  /// The visible pill inside the touch area.
  Rect pill(WidgetTester tester) =>
      tester.getRect(find.descendant(of: button(), matching: find.byType(Container)).first);

  Future<void> shot(WidgetTester tester, String name) async {
    final dir = _shotDir;
    if (dir == null) return;
    await precacheBigP(tester, boundary);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  group('when it shows', () {
    testWidgets('not in the greeting, not while working, not behind a confirmation', (tester) async {
      await pumpHost(tester, _matrix[1]);
      expect(button(), findsNothing);

      answerTitles(c);
      c
        ..state = AssistantSurfaceState.working
        ..emit();
      await settle(tester);
      expect(button(), findsNothing);

      c
        ..state = AssistantSurfaceState.result
        ..emit();
      await settle(tester);
      expect(button(), findsOneWidget);
    });

    testWidgets('a tap clears the conversation and the answer, back to the greeting', (tester) async {
      answerTitles(c);
      await pumpHost(tester, _matrix[1]);
      await tester.tap(button());
      await settle(tester);

      expect(c.newConversations, 1);
      expect(c.submitted, isEmpty, reason: 'it asks nothing');
      expect(c.state, AssistantSurfaceState.idle);
      expect(button(), findsNothing);
      expect(find.text(t.assistant.mobile.newConversationShort), findsNothing);
    });

    testWidgets('iPad says the full label, iPhone the short one', (tester) async {
      answerTitles(c);
      await pumpHost(tester, _matrix[1]);
      expect(
        find.descendant(of: button(), matching: find.text(t.assistant.mobile.newConversationShort)),
        findsOneWidget,
      );
      await pumpHost(tester, _matrix[3]);
      expect(find.descendant(of: button(), matching: find.text(t.assistant.mobile.newConversation)), findsOneWidget);
    });
  });

  group('alignment over the audit matrix', () {
    for (final v in _matrix) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('${v.name} at text scale $scale', (tester) async {
          answerTitles(c);
          await pumpHost(tester, v, textScale: scale);
          expect(tester.takeException(), isNull, reason: 'no overflow');

          final hit = tester.getRect(find.descendant(of: button(), matching: find.byType(GestureDetector)).first);
          expect(hit.width, greaterThanOrEqualTo(kBigPMinTouch - 0.01));
          expect(hit.height, greaterThanOrEqualTo(kBigPMinTouch - 0.01));

          // One line with the field and the send button.
          final visible = pill(tester);
          final sendRect = tester.getRect(send());
          final fieldRect = tester.getRect(find.byType(FocusableTextField));
          expect((visible.center.dy - sendRect.center.dy).abs(), lessThanOrEqualTo(1), reason: 'send button');
          expect((visible.center.dy - fieldRect.center.dy).abs(), lessThanOrEqualTo(1), reason: 'field');
          expect((hit.center.dy - sendRect.center.dy).abs(), lessThanOrEqualTo(1), reason: 'touch area');

          // No overlap with the field, the follow-ups or Big P.
          expect(hit.overlaps(fieldRect), isFalse, reason: 'field');
          for (final chip in find.byWidgetPredicate((w) => w is BigPChip && w.dense).evaluate()) {
            final rect = tester.getRect(find.byWidget(chip.widget));
            expect(hit.overlaps(rect), isFalse, reason: 'follow-up ${(chip.widget as BigPChip).label}');
          }
          expect(hit.overlaps(tester.getRect(find.byType(BigPAvatar).first)), isFalse, reason: 'Big P');

          // Whole, and inside the safe area.
          final text = find.descendant(of: button(), matching: find.byType(RichText)).evaluate();
          for (final e in text) {
            final ro = e.renderObject;
            if (ro is RenderParagraph) expect(ro.didExceedMaxLines, isFalse, reason: 'label cut');
          }
          expect(hit.left, greaterThanOrEqualTo(v.safe.left));
          expect(hit.right, lessThanOrEqualTo(v.size.width - v.safe.right));
          expect(hit.bottom, lessThanOrEqualTo(v.size.height - v.safe.bottom + 0.01));
          expect(hit.top, greaterThanOrEqualTo(v.safe.top));
          expect(pill(tester).width, lessThan(v.size.width * 0.6), reason: 'the field keeps its room');

          if (scale == 1.0 && const ['se-375x667', 'iphone-402x874', 'ipad-744x1133'].contains(v.name)) {
            await shot(tester, 'new-conversation-${v.name}-1-answer');
          }
        });
      }
    }
  });

  testWidgets('shots: the greeting after a tap', (tester) async {
    answerTitles(c);
    await pumpHost(tester, _matrix[1]);
    await tester.tap(button());
    await settle(tester);
    await shot(tester, 'new-conversation-iphone-402x874-2-greeting');
  });
}
