// The way into the memory screen: the row "Geheugen" in Instellingen > Big P,
// with and without a model set up, on a phone and on TV.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/screens/settings/assistant_settings_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';
import 'package:pleya/services/memory/memory_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../../services/memory/memory_test_support.dart';
import '../../test_helpers/prefs.dart';
import 'memory/memory_finders.dart';
import 'memory/memory_screen_support.dart';

class _Store implements AssistantProviderStore {
  _Store(this.config);

  final AssistantProviderConfig? config;

  @override
  Future<AssistantProviderConfig?> load() async => config;

  @override
  Future<void> save(AssistantProviderConfig config, {bool replaceUnreadable = false}) async {}

  @override
  Future<void> clear() async {}
}

const _saved = AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://nas.lan', model: 'm');

void main() {
  Future<void> pump(WidgetTester tester, {AssistantProviderConfig? config, bool memory = true, bool tv = false}) async {
    await tester.runAsync(() async {
      await useDutch();
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await (await StorageService.getInstance()).setActiveProfileId('p');
      await SettingsService.getInstance();
      if (tv) await TvDetectionService.getInstance(forceTv: true);
    });
    TvDetectionService.setForceTVSync(tv);
    addTearDown(() => TvDetectionService.setForceTVSync(false));
    tester.view.physicalSize = tv ? tvSize : phoneSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryTestDatabase();
    addTearDown(db.close);
    final profile = Profile.plexHome(id: 'p', displayName: 'Michel', createdAt: DateTime(2026));
    final screen = AssistantSettingsScreen(
      store: _Store(config),
      listModels: (_) async => const [],
      autoLoadDelay: Duration.zero,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => FakeActiveProfile(profile)),
          if (memory)
            ChangeNotifierProvider<MemoryService>(
              create: (_) => MemoryService(database: db, profileId: 'p', enabledStore: FakeEnabledStore('p')),
            ),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: tv ? Scaffold(body: screen) : screen,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  final row = memoryId(AutomationIds.settingsFormButton, 'assistant.memory');

  for (final (name, config) in [('with a model set up', _saved), ('without a model', null)]) {
    testWidgets('the row "Geheugen" stands in Big P\'s settings $name and opens the memory screen', (tester) async {
      await pump(tester, config: config);

      expect(row, findsOneWidget);
      expect(find.text(t.assistant.memory.screen.title), findsOneWidget);
      expect(find.text(t.assistant.memory.screen.tileSubtitle), findsOneWidget);

      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(find.text(t.assistant.memory.screen.title));
      await settle(tester);
      expect(find.byType(AssistantMemoryScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('no row where no profile session provides a memory', (tester) async {
    await pump(tester, config: _saved, memory: false);
    expect(row, findsNothing);
  });

  testWidgets('TV: the row is a focus stop above the provider summary and Select opens the screen', (tester) async {
    await pump(tester, config: _saved, tv: true);

    expect(row, findsOneWidget);
    // The summary lands on "Wijzigen"; the row is the stop above it.
    for (var i = 0; i < 4 && !holdsFocus(tester, row); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(holdsFocus(tester, row), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    expect(find.byType(AssistantMemoryScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
