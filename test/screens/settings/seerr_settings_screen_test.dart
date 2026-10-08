import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/focus/focusable_text_field.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/screens/settings/seerr_settings_screen.dart';
import 'package:pleya/services/settings_service.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

void main() {
  late FakeSeerr fake;
  late MemorySeerrStore store;
  late SeerrProvider provider;
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    fake = FakeSeerr()
      ..on('GET /status', {'version': 'synthetic'})
      ..on('GET /auth/me', {'id': 7, 'displayName': 'synthetic-A', 'permissions': 2})
      ..on('POST /auth/local', {'id': 7, 'displayName': 'synthetic-A', 'permissions': 32});
    store = MemorySeerrStore();
    provider = SeerrProvider(httpClient: fake.client, store: store);
    await provider.onActiveProfileChanged('probe-only');
    addTearDown(provider.dispose);
  });
  Finder field(String label) =>
      find.byWidgetPredicate((w) => w is FocusableTextFormField && w.decoration?.labelText == label);
  Finder button(String which) => find.descendant(
    of: seerrNode(AutomationIds.settingsFormButton, 'seerr.$which'),
    matching: find.byType(FilledButton),
  );
  Future<void> enter(WidgetTester tester, String label, String value) async {
    await tester.ensureVisible(field(label));
    await tester.enterText(field(label), value);
    await tester.pump();
  }

  Future<void> testedA(WidgetTester tester, String changed) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSeerr(tester, provider, const SeerrSettingsScreen(), host: false);
    await seerrSettle(tester);
    await enter(tester, t.seerr.serverUrl, 'https://synthetic.example.invalid');
    final mode = changed == 'apiKey' ? t.seerr.authApiKey : t.seerr.authLocal;
    await tester.ensureVisible(find.text(mode));
    await tester.tap(find.text(mode));
    await tester.pump();
    if (changed == 'apiKey') {
      await enter(tester, t.seerr.apiKey, 'synthetic-key-A');
    } else {
      await enter(tester, t.seerr.email, 'synthetic-A@example.invalid');
      await enter(tester, t.seerr.password, 'synthetic-password-A');
    }
    await tester.ensureVisible(button('test'));
    await tester.tap(button('test'));
    await seerrSettle(tester);
    expect(button('save'), findsOneWidget);
    expect(store.sessions, isEmpty, reason: 'test does not persist');
  }

  Future<void> editB(WidgetTester tester, String changed) => switch (changed) {
    'apiKey' => enter(tester, t.seerr.apiKey, 'synthetic-key-B'),
    'email' => enter(tester, t.seerr.email, 'synthetic-B@example.invalid'),
    _ => enter(tester, t.seerr.password, 'synthetic-password-B'),
  };
  for (final changed in ['apiKey', 'email', 'password']) {
    testWidgets('$changed: credential edit invalidates tested Save', (tester) async {
      await testedA(tester, changed);
      await editB(tester, changed);
      expect(button('save'), findsNothing, reason: 'untested B must invalidate A result');
      expect(store.sessions, isEmpty);
      await tester.ensureVisible(button('test'));
      await tester.tap(button('test'));
      await seerrSettle(tester);
      await tester.ensureVisible(button('save'));
      await tester.tap(button('save'));
      await seerrSettle(tester);
      final saved = store.sessions['probe-only'];
      expect(saved, isNotNull);
      if (changed == 'apiKey') {
        expect(saved!.apiKey, 'synthetic-key-B');
      } else {
        expect(saved!.email, changed == 'email' ? 'synthetic-B@example.invalid' : 'synthetic-A@example.invalid');
        expect(saved.password, changed == 'password' ? 'synthetic-password-B' : 'synthetic-password-A');
      }
    });
  }
  testWidgets('URL edit removes tested Save', (tester) async {
    await testedA(tester, 'apiKey');
    await enter(tester, t.seerr.serverUrl, 'https://synthetic-B.example.invalid');
    expect(button('save'), findsNothing);
    expect(store.sessions, isEmpty);
  });
  testWidgets('auth mode edit removes tested Save', (tester) async {
    await testedA(tester, 'apiKey');
    await tester.ensureVisible(find.text(t.seerr.authLocal));
    await tester.tap(find.text(t.seerr.authLocal));
    await tester.pump();
    expect(button('save'), findsNothing);
    expect(store.sessions, isEmpty);
  });
}
