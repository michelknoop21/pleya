import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_kids_ages_store.dart';
import 'package:pleya/assistant/assistant_kids_profile_store.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/screens/settings/assistant_settings_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _FakeStore implements AssistantProviderStore {
  _FakeStore(this.config);
  AssistantProviderConfig? config;

  @override
  Future<AssistantProviderConfig?> load() async => config;

  @override
  Future<void> save(AssistantProviderConfig config, {bool replaceUnreadable = false}) async => this.config = config;

  @override
  Future<void> clear() async => config = null;
}

class _ActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  _ActiveProfile(this.active);
  @override
  final Profile? active;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _base = AssistantProviderConfig(
  kind: AssistantProviderKind.ollamaServer,
  baseUrl: 'http://nas.lan:11434',
  model: 'llama3.1',
);

void main() {
  final s = t.assistant.settings;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  Future<void> pump(
    WidgetTester tester,
    _FakeStore store, {
    Size size = const Size(402, 2400),
    Profile? profile,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app = TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: AssistantSettingsScreen(store: store, listModels: (_) async => const [], autoLoadDelay: Duration.zero),
      ),
    );
    if (profile != null) {
      app = ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _ActiveProfile(profile), child: app);
    }
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Finder switchRow() => find.widgetWithText(SwitchListTile, s.factsOnline);

  testWidgets('online facts: on by default, off and on again are saved', (tester) async {
    final store = _FakeStore(_base);
    await pump(tester, store);
    expect(tester.widget<SwitchListTile>(switchRow()).value, isTrue);
    expect(find.text(s.tmdbKey), findsOneWidget);

    await tester.ensureVisible(switchRow());
    await tester.tap(switchRow());
    await tester.pumpAndSettle();
    expect(store.config!.onlineFactsChoice, isFalse);
    expect(store.config!.onlineFacts, isFalse);
    expect(tester.widget<SwitchListTile>(switchRow()).value, isFalse);
    expect(find.text(s.tmdbKey), findsNothing, reason: 'no key needed with online off');

    await tester.tap(switchRow());
    await tester.pumpAndSettle();
    expect(store.config!.onlineFacts, isTrue);
  });

  testWidgets('TMDB key: saved masked, never shown back, cleared', (tester) async {
    final store = _FakeStore(_base);
    await pump(tester, store);
    final keyField = find.widgetWithText(TextFormField, s.tmdbKey);
    await tester.ensureVisible(keyField);
    expect(
      tester.widget<EditableText>(find.descendant(of: keyField, matching: find.byType(EditableText))).obscureText,
      isTrue,
    );

    await tester.enterText(keyField, 'eyJ-secret-token');
    await tapText(tester, s.tmdbKeySave);
    expect(store.config!.tmdbKey, 'eyJ-secret-token');
    expect(find.textContaining('eyJ-secret-token'), findsNothing);
    expect(find.text(s.tmdbKeyStored), findsOneWidget);
    final editable = tester.widget<EditableText>(find.descendant(of: keyField, matching: find.byType(EditableText)));
    expect(editable.controller.text, isEmpty);

    await tapText(tester, s.tmdbKeyClear);
    expect(store.config!.tmdbKey, isEmpty);
    expect(find.text(s.tmdbKeyStored), findsNothing);
    expect(find.text(s.tmdbKeyClear), findsNothing);
  });

  testWidgets('kids ages: shown for this profile and cleared', (tester) async {
    await tester.runAsync(() async {
      await (await StorageService.getInstance()).setActiveProfileId('parent');
      await KidsAgesStore().save([9, 4]);
    });
    final store = _FakeStore(_base);
    await pump(tester, store);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text(s.kidsAges), findsOneWidget);
    expect(find.text(s.kidsAgesValue(ages: '4, 9')), findsOneWidget);

    await tapText(tester, s.kidsAgesClear);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text(s.kidsAgesNone), findsOneWidget);
    final ages = await tester.runAsync(() => KidsAgesStore().read());
    expect(ages, isEmpty);
  });

  Finder kidsRow() => find.widgetWithText(SwitchListTile, s.kidsProfile);

  testWidgets('Kinderprofiel: off by default, switched on and off for this profile only', (tester) async {
    await tester.runAsync(() async => (await StorageService.getInstance()).setActiveProfileId('child'));
    await pump(tester, _FakeStore(_base));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text(s.kidsProfileNote), findsOneWidget);
    expect(tester.widget<SwitchListTile>(kidsRow()).value, isFalse);
    expect(tester.widget<SwitchListTile>(kidsRow()).onChanged, isNotNull);

    Future<void> toggle() async {
      await tester.ensureVisible(kidsRow());
      await tester.tap(kidsRow());
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
    }

    await toggle();
    expect(await tester.runAsync(() => KidsProfileStore().read()), isTrue);
    expect(tester.widget<SwitchListTile>(kidsRow()).value, isTrue);

    await toggle();
    expect(await tester.runAsync(() => KidsProfileStore().read()), isFalse);
  });

  testWidgets('Kinderprofiel on a Plex account Plex marks as restricted: on and locked', (tester) async {
    await tester.runAsync(() async => (await StorageService.getInstance()).setActiveProfileId('plex'));
    final kid = Profile.plexHome(id: 'plex', displayName: 'Mila', plexRestricted: true, createdAt: DateTime(2026));
    await pump(tester, _FakeStore(_base), profile: kid);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final row = tester.widget<SwitchListTile>(kidsRow());
    expect(row.value, isTrue);
    expect(row.onChanged, isNull, reason: 'cannot be switched off');
    expect(find.textContaining(s.kidsProfileLocked), findsOneWidget);
    expect(await tester.runAsync(() => KidsProfileStore().read()), isFalse, reason: 'nothing stored: Plex decides');
  });
}
