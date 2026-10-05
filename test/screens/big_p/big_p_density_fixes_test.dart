/// Big P on a phone and tablet, from the viewport-density audit: touch
/// targets of 44 pt, no cut year or library, the primary action in view on a
/// small phone at large text, and a password label that stays whole.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/big_p_scale.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/golden.dart';
import '../../widgets/big_p/fake_assistant_controller.dart';
import '../tv/assistant/tv_assistant_test_support.dart' show settle;
import 'big_p_mobile_fixtures.dart';

void main() {
  late FakeAssistantController c;
  late BigPMobileSession session;

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

  /// The host out over an empty page, at the real DPR of 2 and a text scale.
  Future<void> pumpHost(
    WidgetTester tester, {
    required Size size,
    EdgeInsets safe = EdgeInsets.zero,
    double textScale = 1,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size * 2;
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
                  viewPadding: safe,
                  padding: safe,
                  viewInsets: EdgeInsets.only(bottom: keyboard),
                ),
                child: const Stack(fit: StackFit.expand, children: [Scaffold(), BigPMobileHost()]),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// What a tap on [chip] reaches: the chip's own GestureDetector.
  Size tapSize(WidgetTester tester, Finder chip) =>
      tester.getSize(find.descendant(of: chip, matching: find.byType(GestureDetector)).first);

  const se = Size(375, 667);
  const iphone = Size(402, 874);
  const safeTop20 = EdgeInsets.only(top: 20);
  const safeTop54 = EdgeInsets.only(top: 54, bottom: 34);

  group('touch targets of 44 pt', () {
    testWidgets('the send button, the example pills and the follow-ups', (tester) async {
      await pumpHost(tester, size: iphone, safe: safeTop54);
      // The greeting's examples.
      final example = find.byWidgetPredicate((w) => w is BigPChip && !w.dense).first;
      expect(tapSize(tester, example).height, greaterThanOrEqualTo(44));
      final send = find.ancestor(of: find.byIcon(Symbols.arrow_upward_rounded), matching: find.byType(GestureDetector));
      expect(tester.getSize(send.first), const Size(44, 44));

      answerTitles(c);
      c.emit();
      await settle(tester);
      final followUps = find.byWidgetPredicate((w) => w is BigPChip && w.dense);
      expect(followUps, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(tapSize(tester, followUps.at(i)).height, greaterThanOrEqualTo(44), reason: 'follow-up $i');
      }
    });

    for (final dy in [-20.0, 20.0]) {
      testWidgets('a tap ${dy.abs()} pt ${dy < 0 ? 'above' : 'below'} the middle of a 34 pt pill selects it', (
        tester,
      ) async {
        answerTitles(c);
        await pumpHost(tester, size: iphone, safe: safeTop54);
        final box = tester.getRect(find.byWidgetPredicate((w) => w is BigPChip && w.dense).first);
        await tester.tapAt(Offset(box.center.dx, box.center.dy + dy));
        await tester.pump();
        expect(c.submitted, hasLength(1));
      });
    }

    testWidgets('an age chip is a 44 pt target on a phone', (tester) async {
      answerKidsAges(c);
      await pumpHost(tester, size: iphone, safe: safeTop54);
      final chip = find.ancestor(of: find.text('9'), matching: find.byType(GestureDetector)).first;
      expect(tester.getSize(chip).width, greaterThanOrEqualTo(43.99));
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(43.99));
    });

    testWidgets('TV has no minimum: only a BigPScale (phone, tablet) asks for one', (tester) async {
      late double tv, phone;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              tv = BigPScale.minTouch(context);
              return BigPScale(
                pt: 0.6,
                child: Builder(
                  builder: (context) {
                    phone = BigPScale.minTouch(context);
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      );
      expect((tv, phone), (0.0, 44.0));
    });
  });

  group('the iPad balloon, two columns', () {
    for (final scale in [1.0, 1.3]) {
      testWidgets('year and library stay whole at text scale $scale', (tester) async {
        answerFactsTitles(c);
        await pumpHost(
          tester,
          size: const Size(744, 1133),
          safe: const EdgeInsets.only(top: 24, bottom: 20),
          textScale: scale,
        );
        final cut = <String>[];
        for (final e in find.byType(RichText).evaluate()) {
          final ro = e.renderObject;
          if (ro is! RenderParagraph) continue;
          final text = ro.text.toPlainText();
          final card = text.startsWith('Film') || text.contains('bibliotheek') || text.contains('Animatie');
          if (card && ro.didExceedMaxLines) cut.add(text);
        }
        expect(cut, isEmpty);
      });
    }
  });

  group('the primary action stays in view', () {
    testWidgets('Aanmaken and Annuleren on an iPhone SE at text scale 1.3', (tester) async {
      c
        ..prompt = 'Maak Sam aan en geef hem alleen Kids.'
        ..state = AssistantSurfaceState.working
        ..pending = createSam(password: AssistantPasswordMode.required);
      await pumpHost(tester, size: se, safe: safeTop20, textScale: 1.3);
      final buttons = find.byType(BigPButton);
      expect(buttons, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expect(buttons.at(i).hitTestable(), findsOneWidget, reason: 'button $i without scrolling');
      }
      // The password field Aanmaken waits for is not behind a scroll either.
      expect(find.text(t.assistant.confirm.passwordPlaceholder).hitTestable(), findsOneWidget);
    });

    testWidgets('Bewaar with the ages card on an iPhone SE at text scale 1.3', (tester) async {
      answerKidsAges(c);
      await pumpHost(tester, size: se, safe: safeTop20, textScale: 1.3);
      expect(find.byType(BigPButton).hitTestable(), findsOneWidget);
    });
  });

  group('the password row', () {
    Future<void> pumpPassword(WidgetTester tester) async {
      c
        ..prompt = 'Maak Sam aan en geef hem alleen Kids.'
        ..state = AssistantSurfaceState.working
        ..pending = createSam(password: AssistantPasswordMode.required);
      await pumpHost(tester, size: iphone, safe: safeTop54, textScale: 1.3);
    }

    testWidgets('the label is one line at text scale 1.3, not broken inside the word', (tester) async {
      await pumpPassword(tester);
      final label = tester.renderObject<RenderParagraph>(find.text(t.assistant.confirm.password));
      expect(label.size.height, lessThan(label.getMinIntrinsicHeight(double.infinity) * 1.5));
    });

    testWidgets('the field is a 44 pt touch target', (tester) async {
      await pumpPassword(tester);
      final field = find.text(t.assistant.confirm.passwordPlaceholder);
      final box = find.ancestor(of: field, matching: find.byType(Container)).first;
      expect(tester.getSize(box).height, greaterThanOrEqualTo(43.99));
    });
  });
}
