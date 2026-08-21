import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/icloud_sync_tile.dart';
import 'package:pleya/services/icloud_sync_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';

/// The tile is where the old bug was visible: an Apple TV showed "sign in to
/// iCloud" and a dead switch, because one boolean carried both "can this
/// platform sync" and "did the last call work". These assert the split — a
/// reachable-but-failing store keeps the control, a genuinely absent account
/// does not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(ICloudSyncService.debugReset);

  group('what each status renders', () {
    test('a healthy store shows the plain description and stays on', () {
      final state = ICloudSyncTileState.forStatus(ICloudSyncStatus.ok);
      expect(state.enabled, isTrue);
      expect(state.subtitle, t.settings.icloudSyncDescription);
    });

    test('an unresolved probe stays on rather than flashing a problem', () {
      final state = ICloudSyncTileState.forStatus(null);
      expect(state.enabled, isTrue);
      expect(state.subtitle, t.settings.icloudSyncDescription);
    });

    test('a transport error keeps the control and says so', () {
      final state = ICloudSyncTileState.forStatus(ICloudSyncStatus.error);
      expect(state.enabled, isTrue, reason: 'a supported transport must not be disabled pre-emptively');
      expect(state.subtitle, t.settings.icloudSyncError);
      expect(
        state.subtitle,
        isNot(t.settings.icloudSyncUnavailable),
        reason: 'a failing store must never masquerade as a missing iCloud account',
      );
    });

    test('a warning keeps the control and names the dropped keys', () {
      final state = ICloudSyncTileState.forStatus(ICloudSyncStatus.warning);
      expect(state.enabled, isTrue);
      expect(state.subtitle, t.settings.icloudSyncWarning);
    });

    test('a signed-out account is the one case that says "sign in"', () {
      final state = ICloudSyncTileState.forStatus(ICloudSyncStatus.signedOut);
      expect(state.enabled, isFalse);
      expect(state.subtitle, t.settings.icloudSyncUnavailable);
    });

    test('an unsupported platform is disabled without blaming the account', () {
      final state = ICloudSyncTileState.forStatus(ICloudSyncStatus.unsupported);
      expect(state.enabled, isFalse);
      expect(state.subtitle, t.settings.icloudSyncNotSupported);
      expect(state.subtitle, isNot(t.settings.icloudSyncUnavailable));
    });
  });

  group('the rendered switch', () {
    // Driven through the real method channel rather than a status setter, so
    // what is being tested is the whole path the device takes: native answer →
    // status → tile.
    const channel = MethodChannel('com.pleya/icloud_kvs');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void nativeAnswers(Object? answer) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'isAvailable') return null;
        if (answer is Exception) throw answer;
        return answer as bool?;
      });
    }

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> pump(WidgetTester tester) async {
      ICloudSyncService.debugCreate(settings: await SettingsService.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(body: ICloudSyncTile(onToggleFailed: () async {})),
        ),
      );
      await tester.pumpAndSettle();
    }

    SwitchListTile switchTile(WidgetTester tester) => tester.widget<SwitchListTile>(find.byType(SwitchListTile));

    testWidgets('a store that reports itself available enables the control — the tvOS case', (tester) async {
      // tvOS answers yes unconditionally, on the strength of its
      // ubiquity-kvstore-identifier entitlement.
      nativeAnswers(true);
      await pump(tester);

      expect(switchTile(tester).onChanged, isNotNull);
      expect(find.text(t.settings.icloudSyncDescription), findsOneWidget);
      expect(find.text(t.settings.icloudSyncUnavailable), findsNothing);
    });

    testWidgets('a transport failure leaves the control usable', (tester) async {
      nativeAnswers(PlatformException(code: 'ERR', message: 'store unreachable'));
      await pump(tester);

      expect(switchTile(tester).onChanged, isNotNull);
      expect(find.text(t.settings.icloudSyncError), findsOneWidget);
      expect(find.text(t.settings.icloudSyncUnavailable), findsNothing);
    });

    testWidgets('a signed-out account disables it', (tester) async {
      nativeAnswers(false);
      await pump(tester);

      expect(switchTile(tester).onChanged, isNull);
      expect(find.text(t.settings.icloudSyncUnavailable), findsOneWidget);
    });

    testWidgets('a missing plugin disables it without blaming the account', (tester) async {
      nativeAnswers(MissingPluginException('No implementation found'));
      await pump(tester);

      expect(switchTile(tester).onChanged, isNull);
      expect(find.text(t.settings.icloudSyncNotSupported), findsOneWidget);
    });
  });
}
