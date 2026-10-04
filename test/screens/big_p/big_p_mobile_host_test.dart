import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/screens/big_p/big_p_face_button.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/screens/settings/assistant_settings_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
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
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: true, viewPadding: const EdgeInsets.only(top: 54, bottom: 34)),
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

  Future<void> summon(WidgetTester tester) async {
    await tester.tap(find.byType(BigPFaceButton));
    await settle(tester);
  }

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
    expect(find.text(t.assistant.mobile.examples.first), findsOneWidget);
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
    await tester.tap(find.text(t.assistant.mobile.examples.first));
    await tester.pump();
    expect(c.submitted, [t.assistant.mobile.examples.first]);
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
}
