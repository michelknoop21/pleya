import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/profile/add_local_profile_screen.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
  });

  testWidgets('D-pad leaves profile name input and reaches actions', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: const InputModeTracker(child: MaterialApp(home: AddLocalProfileScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Apple TV never auto-opens a keyboard on focus (native entry opens on
    // explicit select only), so focus starts on the name field itself.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'AddLocalProfile:Name');
    expect(find.byKey(const Key('tv_virtual_keyboard_panel')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'AddLocalProfile:SetPin');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'AddLocalProfile:Continue');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'AddLocalProfile:Cancel');
  });

  testWidgets('Android TV virtual keyboard done leaves profile name input', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(null);
    await TvDetectionService.getInstance(forceTv: true);
    TvDetectionService.setForceTVSync(true);

    await tester.pumpWidget(
      TranslationProvider(
        child: const InputModeTracker(child: MaterialApp(home: AddLocalProfileScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvVirtualKeyboard');

    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'AddLocalProfile:SetPin');
  });

  testWidgets('remote back pops the new profile page', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: InputModeTracker(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddLocalProfileScreen())),
                    child: const Text('Open new profile'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open new profile'));
    await tester.pumpAndSettle();
    expect(find.text(t.profiles.newProfile), findsOneWidget);
    // Apple TV: no auto-opened keyboard panel, so back pops the page directly.
    expect(find.byKey(const Key('tv_virtual_keyboard_panel')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();

    expect(find.text('Open new profile'), findsOneWidget);
    expect(find.text(t.profiles.newProfile), findsNothing);
  });
}
