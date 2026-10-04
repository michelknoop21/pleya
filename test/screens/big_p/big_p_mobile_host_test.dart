import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/screens/big_p/big_p_face_button.dart';
import 'package:pleya/screens/big_p/big_p_input_bar.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/screens/main/mobile_main_scaffold.dart';
import 'package:pleya/screens/main/mobile_tab_bar.dart';
import 'package:pleya/screens/settings/assistant_settings_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_suggestions.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:pleya/widgets/big_p/big_p_balloon.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/glass_phone.dart';
import '../../test_helpers/prefs.dart';
import '../../widgets/big_p/fake_assistant_controller.dart';

AssistantPendingAction _card() => AssistantPendingAction(
  kind: AssistantActionKind.createUser,
  serverId: ServerId('nas'),
  serverName: 'NAS',
  subject: 'Sam',
  execute: ({password}) async => const {},
);

void main() {
  late FakeAssistantController c;
  late BigPMobileSession session;

  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = FakeAssistantController();
    session = BigPMobileSession(c);
    addTearDown(() {
      session.dispose();
      c.dispose();
    });
  });

  /// A header with the face button over a page, and the host above both, as
  /// MobileMainScaffold stacks them. Reduced motion: no slide to wait for.
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(402, 874),
    EdgeInsets safe = const EdgeInsets.only(top: 54, bottom: 34),
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<BigPMobileSession>.value(
          value: session,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  viewPadding: safe,
                  padding: keyboard > 0 ? safe.copyWith(bottom: 0) : safe,
                  viewInsets: EdgeInsets.only(bottom: keyboard),
                ),
                child: const Stack(
                  fit: StackFit.expand,
                  children: [
                    Scaffold(
                      body: Align(alignment: Alignment.topRight, child: BigPFaceButton()),
                    ),
                    BigPMobileHost(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The examples the balloon shows: picked once per summon, then kept.
  List<String> shownExamples() => BigPSuggestions.of(c).examples(t.assistant.mobile.examples);

  Future<void> summon(WidgetTester tester) async {
    await tester.tap(find.byType(BigPFaceButton));
    await settle(tester);
  }

  test('an action bar gives Big P no slot while hidden or without the rollout flag', () {
    for (final a in AssistantAvailability.values) {
      expect(showsBigPAction(rolloutEnabled: false, availability: a), isFalse, reason: 'flag off, $a');
      expect(showsBigPAction(rolloutEnabled: true, availability: a), a != AssistantAvailability.hidden, reason: '$a');
    }
    expect(showsBigPAction(rolloutEnabled: true, availability: null), isFalse);
  });

  testWidgets('the face button is hidden while Big P is hidden, shown at needsSetup', (tester) async {
    c.availability = AssistantAvailability.hidden;
    await pump(tester);
    expect(find.byType(IconButton), findsNothing);

    c
      ..availability = AssistantAvailability.needsSetup
      ..emit();
    await tester.pump();
    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byType(BigPPortrait), findsOneWidget);
  });

  testWidgets('a tap brings Big P out and leaves an empty ring', (tester) async {
    await pump(tester);
    await summon(tester);
    expect(session.stage, BigPStage.out);
    expect(find.byType(BigPPortrait), findsNothing);
    expect(find.byType(BigPAvatar), findsOneWidget);
    expect(shownExamples(), hasLength(3));
    for (final example in shownExamples()) {
      expect(find.text(example), findsOneWidget);
    }
    expect(find.text(assistantGreeting('', greeting: t.assistant.mobile.greeting)), findsOneWidget);
  });

  testWidgets('needsSetup says so with one button, which opens the settings and parks', (tester) async {
    c.availability = AssistantAvailability.needsSetup;
    await pump(tester);
    await summon(tester);
    expect(find.text(t.assistant.mobile.noModelTitle), findsOneWidget);
    // The iCloud line only where the keychain syncs; not on this test host.
    expect(find.text(t.assistant.mobile.icloudNote), findsNothing);
    expect(find.byType(BigPButton), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byType(BigPButton));
    await settle(tester);
    expect(find.byType(AssistantSettingsScreen), findsOneWidget);
    expect(session.stage, BigPStage.parked);
  });

  testWidgets('focus on the field starts listening; leaving it empty stops', (tester) async {
    await pump(tester);
    await summon(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(c.state, AssistantSurfaceState.listening);
    expect(find.text(t.assistant.mobile.listening), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(c.cancelledListening, 1);
  });

  testWidgets('send asks the controller and closes the keyboard', (tester) async {
    await pump(tester);
    await summon(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Iets met ruimte? ');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(c.submitted, ['Iets met ruimte?']);
    expect(c.cancelledListening, 0);
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('bigp.input'));
  });

  testWidgets('an example asks it', (tester) async {
    await pump(tester);
    await summon(tester);
    final example = shownExamples().first;
    await tester.tap(find.text(example));
    await tester.pump();
    expect(c.submitted, [example]);
  });

  testWidgets('a tap on the dim parks Big P', (tester) async {
    await pump(tester);
    await summon(tester);
    await tester.tapAt(const Offset(200, 60));
    await settle(tester);
    expect(session.stage, BigPStage.parked);
    expect(find.byType(BigPAvatar), findsNothing);
    expect(find.byType(BigPPortrait), findsOneWidget);
  });

  testWidgets('the dim does not park while a confirmation waits', (tester) async {
    await pump(tester);
    await summon(tester);
    c
      ..state = AssistantSurfaceState.working
      ..pending = _card()
      ..emit();
    await tester.pump();
    await tester.tapAt(const Offset(200, 60));
    await settle(tester);
    expect(session.stage, BigPStage.out);
  });

  testWidgets('parked, nothing ticks', (tester) async {
    await pump(tester);
    await summon(tester);
    await tester.tapAt(const Offset(200, 60));
    await settle(tester);
    expect(find.byType(BigPAvatar), findsNothing);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('a confirmation that arrives while parked dots the face button, Big P stays in', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('bigp-face-waiting')), findsNothing);
    c
      ..state = AssistantSurfaceState.working
      ..pending = _card()
      ..emit();
    await tester.pump();
    expect(find.byKey(const ValueKey('bigp-face-waiting')), findsOneWidget);
    expect(session.stage, BigPStage.parked);
    expect(find.byType(BigPAvatar), findsNothing);

    await summon(tester);
    expect(find.byKey(const ValueKey('bigp-face-waiting')), findsNothing);
  });

  testWidgets('parking while listening lets the mic go; the next summon greets', (tester) async {
    await pump(tester);
    await summon(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(c.state, AssistantSurfaceState.listening);
    await tester.tapAt(const Offset(200, 60));
    await settle(tester);
    expect(c.cancelledListening, 1);
    expect(c.state, AssistantSurfaceState.idle);
    final before = shownExamples().toSet();
    await summon(tester);
    expect(find.text(shownExamples().first), findsOneWidget);
    expect(shownExamples().toSet(), isNot(before), reason: 'a new summon, new examples');
  });

  testWidgets('send while he works keeps the text', (tester) async {
    await pump(tester);
    await summon(tester);
    await tester.tap(find.byType(TextField));
    c
      ..state = AssistantSurfaceState.working
      ..emit();
    await tester.enterText(find.byType(TextField), 'En nog iets');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(c.submitted, isEmpty);
    expect(find.text('En nog iets'), findsOneWidget);
  });

  testWidgets('an iPad held upright fits the balloon beside Big P', (tester) async {
    c.availability = AssistantAvailability.needsSetup;
    await pump(tester, size: const Size(820, 1180), safe: const EdgeInsets.only(top: 24, bottom: 20));
    await summon(tester);
    // A row wider than the screen paints the overflow stripe over Big P.
    expect(tester.takeException(), isNull);
    expect(tester.getTopRight(find.byType(BigPAvatar)).dx, lessThanOrEqualTo(820));
    expect(
      tester.getTopRight(find.byType(BigPBalloon)).dx,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(BigPAvatar)).dx),
    );
  });

  testWidgets('an iPhone SE with the keyboard up keeps the balloon readable', (tester) async {
    await pump(tester, size: const Size(375, 667), safe: const EdgeInsets.only(top: 20), keyboard: 260);
    await summon(tester);
    expect(tester.takeException(), isNull);
    final balloon = tester.getSize(find.byType(BigPBalloon));
    expect(balloon.height, greaterThanOrEqualTo(150));
    expect(tester.getSize(find.byType(BigPAvatar)).height, lessThan(237));
    // Big P and the field stay above the keyboard.
    expect(tester.getBottomLeft(find.byType(BigPInputBar)).dy, lessThanOrEqualTo(667 - 260));
  });

  testWidgets('beside an answer Big P steps back to 150, the greeting keeps 237', (tester) async {
    await pump(tester);
    await summon(tester);
    expect(tester.getSize(find.byType(BigPAvatar)).height, 237);
    c
      ..prompt = 'Wat is er nieuw?'
      ..answer = 'Twee films. De rest is ouder.'
      ..state = AssistantSurfaceState.result
      ..emit();
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(BigPAvatar)).height, 150);
    // Only the first sentence is the bold lead.
    expect(find.text('Twee films.'), findsOneWidget);
    expect(find.text('De rest is ouder.'), findsOneWidget);
  });

  testWidgets('a first sentence longer than two lines is no bold lead', (tester) async {
    const long =
        'The latest additions are mostly 2026 releases, with Tears of Steel and Sintel joined alongside a '
        'handful of older favourites from the Blender studio.';
    await pump(tester);
    await summon(tester);
    c
      ..prompt = 'Wat is er nieuw?'
      ..answer = '$long De rest is ouder.'
      ..state = AssistantSurfaceState.result
      ..emit();
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(long), findsNothing);
    final text = tester.widget<Text>(find.text('$long De rest is ouder.'));
    expect(text.style!.fontWeight, isNot(FontWeight.w700));
  });

  for (final (answer, lead, rest) in [
    ('Top drie:\n1. Inception\n2. Tenet', 'Top drie:', '1. Inception\n2. Tenet'),
    ('Kijk dit\n• A. Goed', 'Kijk dit', '• A. Goed'),
  ]) {
    testWidgets('the lead stops at the first line: $lead', (tester) async {
      await pump(tester);
      await summon(tester);
      c
        ..prompt = 'Wat raad je aan?'
        ..answer = answer
        ..state = AssistantSurfaceState.result
        ..emit();
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.text(lead)).style!.fontWeight, FontWeight.w700);
      expect(find.text(rest), findsOneWidget);
    });
  }

  testWidgets('the face button says whether Big P is out and that a card waits', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    bool toggled() => tester.getSemantics(find.byType(IconButton)).flagsCollection.isToggled == ui.Tristate.isTrue;
    expect(toggled(), isFalse);
    await summon(tester);
    expect(toggled(), isTrue);
    await tester.tapAt(const Offset(200, 60));
    await settle(tester);
    c
      ..state = AssistantSurfaceState.working
      ..pending = _card()
      ..emit();
    await tester.pump();
    expect(tester.getSemantics(find.byType(IconButton)).value, t.assistant.mobile.notConfirmedYet);
    handle.dispose();
  });

  testWidgets('in the shell he stands on the floating bar and the reconnect strip', (tester) async {
    resetSharedPreferencesForTest();
    await glassPhone(tester, glass: true);
    final strip = Container(key: const ValueKey('strip'), height: 40, color: Colors.blue);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: glassPhoneTheme(),
          home: Provider<ActiveProfileProvider?>.value(
            value: null,
            child: ChangeNotifierProvider<BigPMobileSession>.value(
              value: session,
              child: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: true),
                  child: MobileMainScaffold(
                    body: const SizedBox.expand(),
                    reconnectStrip: strip,
                    overlay: const BigPMobileHost(),
                    tabBar: MobileTabBar(
                      tabs: glassPhoneTabs(),
                      currentIndex: 0,
                      onDestinationSelected: (_) {},
                      hideLabels: false,
                      presentation: TabBarPresentation.unified2026,
                      onLibraryLongPress: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    session.summon();
    await settle(tester);
    final stripTop = tester.getTopLeft(find.byKey(const ValueKey('strip'))).dy;
    final barBottom = tester.getBottomLeft(find.byType(BigPInputBar)).dy;
    expect(barBottom, lessThanOrEqualTo(stripTop));
    expect(stripTop - barBottom, lessThan(12));
  });
}
