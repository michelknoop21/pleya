/// Big P's answer in the balloon on iPhone and iPad (39 E, F, G, I): cards
/// that open or request, three follow-ups, the Pleya card that holds him
/// out, and two columns on an iPad.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/big_p/big_p_input_bar.dart';
import 'package:pleya/screens/big_p/big_p_mobile_conversation.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_confirm_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:pleya/widgets/big_p/big_p_scale.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tv/assistant/tv_assistant_test_support.dart';
import 'big_p_mobile_fixtures.dart';

void main() {
  late FakeAssistantController c;
  late BigPMobileSession session;

  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = FakeAssistantController();
    session = BigPMobileSession(c, now: () => DateTime(2026, 10, 4, 21, 14));
    addTearDown(() {
      session.dispose();
      c.dispose();
    });
  });

  Widget app(Widget child, {EdgeInsets safe = EdgeInsets.zero, double keyboard = 0}) => TranslationProvider(
    child: ChangeNotifierProvider<BigPMobileSession>.value(
      value: session,
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              viewPadding: safe,
              padding: safe,
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );

  /// The host out over an empty page, reduced motion.
  Future<void> pumpHost(
    WidgetTester tester, {
    Size size = const Size(402, 874),
    EdgeInsets safe = EdgeInsets.zero,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    session.summon();
    await tester.pumpWidget(
      app(
        const Stack(fit: StackFit.expand, children: [Scaffold(), BigPMobileHost()]),
        safe: safe,
        keyboard: keyboard,
      ),
    );
    await settle(tester);
  }

  testWidgets('a title in the library opens; one only Seerr knows is requested', (tester) async {
    answerTitles(c);
    final opened = <AssistantTitleTarget>[];
    tester.view.physicalSize = const Size(402, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        Scaffold(
          body: BigPScale(
            pt: 0.53,
            child: BigPMobileConversation(
              controller: c,
              name: 'Michel',
              onExample: (_) {},
              onSetup: () {},
              onOpenTitle: opened.add,
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.textContaining('Welke animatiefilms'), findsOneWidget);
    await tester.tap(find.widgetWithText(BigPMatchCard, 'Tears of Steel'));
    expect(opened.single.item.title, 'Tears of Steel');
    expect(c.picked, isEmpty);

    await tester.tap(find.widgetWithText(BigPMatchCard, 'Spring'));
    await tester.pump();
    expect(c.picked.single.seerrId, springRequest.seerrId);
    expect(opened, hasLength(1));
  });

  testWidgets('exactly three follow-ups float beside Big P; a tap asks it', (tester) async {
    answerTitles(c);
    await pumpHost(tester);
    final followUps = find.byWidgetPredicate((w) => w is BigPChip && w.dense);
    expect(followUps, findsNWidgets(3));
    final label = tester.widget<BigPChip>(followUps.first).label;
    await tester.tap(followUps.first);
    await tester.pump();
    expect(c.listenContexts, hasLength(1));
    expect(c.submitted, [label]);
  });

  testWidgets('no follow-ups after an error', (tester) async {
    answerTitles(c);
    c.resultIsError = true;
    await pumpHost(tester);
    expect(find.byWidgetPredicate((w) => w is BigPChip && w.dense), findsNothing);
  });

  testWidgets('watch stats: the card and the ranked titles in the balloon', (tester) async {
    answerWatchStats(c);
    await pumpHost(tester);
    expect(find.text('Kijkcijfers'), findsOneWidget);
    expect(find.text('36×'), findsOneWidget);
    expect(find.widgetWithText(BigPMatchCard, 'Sintel'), findsOneWidget);
  });

  testWidgets('a waiting card hides the field and holds Big P out', (tester) async {
    answerTitles(c);
    c.pending = createSam();
    await pumpHost(tester);
    expect(find.byType(BigPConfirmCard), findsOneWidget);
    expect(find.byType(BigPInputBar), findsNothing);
    expect(find.byWidgetPredicate((w) => w is BigPChip && w.dense), findsNothing);

    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(session.stage, BigPStage.out, reason: 'the dim does not park him');
    session.park();
    expect(session.stage, BigPStage.out, reason: 'nor does back');
    expect(find.byType(BigPConfirmCard), findsOneWidget);

    await tester.tap(find.text(t.assistant.result.cancel));
    expect(c.cancelledPending, 1);
    expect(c.confirmedPasswords, isEmpty);
  });

  testWidgets('negative control: without a card the dim parks him', (tester) async {
    answerTitles(c);
    await pumpHost(tester);
    expect(find.byType(BigPInputBar), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(session.stage, BigPStage.parked);
  });

  testWidgets('the password goes to confirmPending and nowhere else', (tester) async {
    c
      ..prompt = 'Maak Sam aan en geef hem alleen Kids.'
      ..state = AssistantSurfaceState.working
      ..pending = createSam(password: AssistantPasswordMode.required);
    await pumpHost(tester);

    await tester.tap(find.text(t.assistant.confirm.passwordPlaceholder));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
    );
    expect(field.obscureText, isTrue);
    await tester.enterText(find.byType(TextField), 'geheim-42');
    await tester.tap(find.text(t.common.save));
    await settle(tester);

    expect(find.textContaining('geheim-42'), findsNothing, reason: 'the card shows dots');
    await tester.ensureVisible(find.text(t.assistant.confirm.create));
    await tester.pump();
    await tester.tap(find.text(t.assistant.confirm.create));
    expect(c.confirmedPasswords, ['geheim-42']);
    expect(c.submitted, isEmpty);
    expect(c.picked, isEmpty);
    expect(c.prompt, isNot(contains('geheim')));
  });

  testWidgets('on an iPad the cards stand in two columns, the field in the balloon', (tester) async {
    answerTitles(c);
    await pumpHost(tester, size: const Size(1180, 820));
    final tears = tester.getTopLeft(find.widgetWithText(BigPMatchCard, 'Tears of Steel'));
    final dream = tester.getTopLeft(find.widgetWithText(BigPMatchCard, 'Elephants Dream'));
    final spring = tester.getTopLeft(find.widgetWithText(BigPMatchCard, 'Spring'));
    expect(dream.dy, tears.dy);
    expect(dream.dx, greaterThan(tears.dx));
    expect(spring.dx, tears.dx);
    expect(spring.dy, greaterThan(tears.dy));
    expect(find.byWidgetPredicate((w) => w is BigPChip && w.dense), findsNWidgets(3));
    // The field sits inside the balloon, left of Big P.
    final bar = tester.getRect(find.byType(BigPInputBar));
    expect(bar.right, lessThan(1180 - 200));
  });

  Finder followUps() => find.byWidgetPredicate((w) => w is BigPChip && w.dense);

  testWidgets('an iPhone SE with the keyboard up: every follow-up takes a tap', (tester) async {
    answerTitles(c);
    await pumpHost(tester, size: const Size(375, 667), safe: const EdgeInsets.only(top: 20), keyboard: 260);
    expect(followUps(), findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      expect(followUps().at(i).hitTestable(), findsOneWidget, reason: 'pill $i');
    }
    // The top one, nearest the balloon.
    final label = tester.widget<BigPChip>(followUps().first).label;
    await tester.tap(followUps().first);
    await tester.pump();
    expect(c.submitted, [label]);
  });

  testWidgets('the field asks on after an answer, and plainly before one', (tester) async {
    await pumpHost(tester);
    expect(find.text(t.assistant.idle.ask), findsOneWidget);
    expect(find.text(t.assistant.mobile.askFurther), findsNothing);

    answerTitles(c);
    c.emit();
    await settle(tester);
    expect(find.text(t.assistant.mobile.askFurther), findsOneWidget);
  });

  testWidgets('the result card tells when the answer came in, not when it was drawn', (tester) async {
    await pumpHost(tester);
    c
      ..prompt = 'Scan de bibliotheek.'
      ..state = AssistantSurfaceState.working
      ..emit();
    await tester.pump();
    c
      ..state = AssistantSurfaceState.result
      ..resultIsError = true
      ..emit();
    await settle(tester);
    expect(session.resultAt, DateTime(2026, 10, 4, 21, 14));
    // 21:14, or 9:14 PM without the 24-hour clock.
    expect(find.textContaining('9:14'), findsOneWidget);
  });

  testWidgets('in the balloon the card has no frame and two equal buttons; it answers once', (tester) async {
    c
      ..prompt = 'Maak Sam aan en geef hem alleen Kids.'
      ..state = AssistantSurfaceState.working
      ..pending = createSam();
    await pumpHost(tester);
    expect(tester.widget<BigPConfirmCard>(find.byType(BigPConfirmCard)).embedded, isTrue);
    final cancel = tester.getSize(find.widgetWithText(BigPButton, t.assistant.result.cancel));
    final create = tester.getSize(find.widgetWithText(BigPButton, t.assistant.confirm.create));
    expect(cancel.width, create.width);

    final approve = find.text(t.assistant.confirm.create);
    await tester.ensureVisible(approve);
    await tester.pump();
    await tester.tap(approve);
    await tester.tap(approve);
    await tester.tap(find.text(t.assistant.result.cancel));
    expect(c.confirmedPasswords, [null]);
    expect(c.cancelledPending, 0);
  });

  testWidgets('the password dialog closes with its card', (tester) async {
    c
      ..prompt = 'Maak Sam aan.'
      ..state = AssistantSurfaceState.working
      ..pending = createSam(password: AssistantPasswordMode.required);
    await pumpHost(tester);
    await tester.tap(find.text(t.assistant.confirm.passwordPlaceholder));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    // Timed out: the controller drops the card.
    c
      ..pending = null
      ..state = AssistantSurfaceState.result
      ..resultIsError = true
      ..emit();
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BigPConfirmCard), findsNothing);
    expect(c.confirmedPasswords, isEmpty);
  });
}
