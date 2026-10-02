import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/assistant_settings_screen.dart';
import 'package:pleya/theme/mono_theme.dart';

class _FakeStore implements AssistantProviderStore {
  _FakeStore([this.config]);
  AssistantProviderConfig? config;
  int saves = 0;

  @override
  Future<AssistantProviderConfig?> load() async => config;

  @override
  Future<void> save(AssistantProviderConfig config) async {
    saves++;
    this.config = config;
  }

  @override
  Future<void> clear() async => config = null;
}

void main() {
  final s = t.assistant.settings;

  Future<void> pump(WidgetTester tester, _FakeStore store, AssistantModelLister lister) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: AssistantSettingsScreen(store: store, listModels: lister),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(int index) => find.byType(EditableText).at(index);

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('cloud: choose, key, fetch, pick, test, save writes the store and hides the key', (tester) async {
    final store = _FakeStore();
    final seen = <AssistantProviderConfig>[];
    await pump(tester, store, (config) async {
      seen.add(config);
      return ['gpt-oss:120b', 'qwen3:32b'];
    });

    await tapText(tester, s.ollamaCloud);
    await tester.enterText(field(0), 'sk-secret');
    await tapText(tester, s.fetchModels);
    expect(seen.single.apiKey, 'sk-secret');
    expect(seen.single.baseUrl, AssistantProviderConfig.ollamaCloudUrl);

    await tapText(tester, 'qwen3:32b');
    await tapText(tester, s.test);
    expect(seen.length, 2);
    await tapText(tester, s.save);

    expect(store.saves, 1);
    expect(store.config!.kind, AssistantProviderKind.ollamaCloud);
    expect(store.config!.model, 'qwen3:32b');
    expect(store.config!.apiKey, 'sk-secret');
    expect(store.config!.isComplete, isTrue);

    // Summary: masked, and Change starts with an empty key field.
    expect(find.textContaining('sk-secret'), findsNothing);
    expect(find.textContaining(s.keyStored), findsOneWidget);
    await tapText(tester, s.change);
    await tapText(tester, s.ollamaCloud);
    expect(tester.widget<EditableText>(field(0)).controller.text, isEmpty);
  });

  testWidgets('server: invalid URL and invalid header are refused before any request', (tester) async {
    var calls = 0;
    await pump(tester, _FakeStore(), (_) async {
      calls++;
      return ['llama3.1'];
    });

    await tapText(tester, s.ollamaServer);
    await tester.enterText(field(0), 'nas.lan:11434');
    await tapText(tester, s.fetchModels);
    expect(find.text(s.errorUrlInvalid), findsOneWidget);

    await tester.enterText(field(0), 'http://nas.lan:11434/v1/');
    await tester.enterText(field(1), 'Bad Header');
    await tester.enterText(field(2), 'x');
    await tapText(tester, s.fetchModels);
    expect(find.text(s.errorHeaderInvalid), findsOneWidget);
    expect(calls, 0);

    await tester.enterText(field(1), 'X-Proxy-Key');
    await tapText(tester, s.fetchModels);
    expect(calls, 1);
    expect(find.text('llama3.1'), findsOneWidget);
  });

  testWidgets('a rejected key shows the mapped sentence, not the exception', (tester) async {
    await pump(
      tester,
      _FakeStore(),
      (_) async => throw const AssistantModelException(AssistantModelError.unauthorized),
    );
    await tapText(tester, s.openRouter);
    await tester.enterText(field(0), 'sk-or-bad');
    await tapText(tester, s.fetchModels);
    expect(find.text(s.errorUnauthorized), findsOneWidget);
  });

  testWidgets('test fails when the chosen model disappeared', (tester) async {
    var models = ['a', 'b'];
    await pump(tester, _FakeStore(), (_) async => models);
    await tapText(tester, s.ollamaCloud);
    await tester.enterText(field(0), 'key');
    await tapText(tester, s.fetchModels);
    await tapText(tester, 'b');
    models = ['a'];
    await tapText(tester, s.test);
    expect(find.text(s.modelMissing), findsOneWidget);
    expect(find.text(s.save), findsNothing);
  });

  testWidgets('disable clears the store', (tester) async {
    final store = _FakeStore(
      const AssistantProviderConfig(
        kind: AssistantProviderKind.ollamaServer,
        baseUrl: 'http://nas.lan:11434',
        model: 'llama3.1',
      ),
    );
    await pump(tester, store, (_) async => []);
    await tapText(tester, s.disable);
    await tapText(tester, s.disable); // dialog confirm
    expect(store.config, isNull);
    expect(find.text(s.providerHeading), findsOneWidget);
  });

  test('every model error maps to its own sentence', () {
    final texts = {for (final e in AssistantModelError.values) assistantSettingsErrorText(AssistantModelException(e))};
    expect(texts.length, AssistantModelError.values.length);
    expect(assistantSettingsErrorText(StateError('x')), s.errorBadResponse);
  });

  test('settings row exists only with the rollout flag', () {
    expect(assistantSettingsTvItem(onSelect: () {}, rolloutEnabled: false), isNull);
    final item = assistantSettingsTvItem(onSelect: () {}, rolloutEnabled: true);
    expect(item?.title, t.assistant.tileTitle);
  });
}
