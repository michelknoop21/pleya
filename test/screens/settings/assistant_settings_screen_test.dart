import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/screens/settings/assistant_settings_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../../test_helpers/prefs.dart';

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

List<AssistantModelInfo> _infos(List<String> ids) => [for (final id in ids) AssistantModelInfo(id: id)];

void main() {
  final s = t.assistant.settings;

  // The summary carries Big P's voice switch, a SettingsService pref.
  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
  });

  Future<void> pump(
    WidgetTester tester,
    _FakeStore store,
    AssistantModelLister lister, {
    AssistantModelPuller? puller,
  }) async {
    // Tall enough that the summary, picker and update row fit without the
    // focus-following scroll moving a target away between ensureVisible
    // and tap.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: AssistantSettingsScreen(
            store: store,
            listModels: lister,
            pullModel: puller ?? (_, _) => const Stream.empty(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets the debounced auto-load fire and finish.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Finder field(int index) => find.byType(EditableText).at(index);

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  testWidgets('cloud: choose, key, models load by themselves, pick, test, save; key stays hidden', (tester) async {
    final store = _FakeStore();
    final seen = <AssistantProviderConfig>[];
    await pump(tester, store, (config) async {
      seen.add(config);
      return _infos(['gpt-oss:120b', 'qwen3:32b']);
    });

    await tapText(tester, s.ollamaCloud);
    await tester.enterText(field(0), 'sk-secret');
    await settle(tester);
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
    expect(store.config!.webSearchChoice, isNull, reason: 'untouched switch keeps the per-kind default');
    expect(store.config!.webSearch, isTrue);

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
      return _infos(['llama3.1']);
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
    await settle(tester);
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
    await settle(tester);
    expect(find.text(s.errorUnauthorized), findsOneWidget);
  });

  testWidgets('test fails when the chosen model disappeared', (tester) async {
    var models = _infos(['a', 'b']);
    await pump(tester, _FakeStore(), (_) async => models);
    await tapText(tester, s.ollamaCloud);
    await tester.enterText(field(0), 'key');
    await settle(tester);
    await tapText(tester, 'b');
    models = _infos(['a']);
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

  testWidgets('a single tool model is picked by itself', (tester) async {
    await pump(tester, _FakeStore(), (_) async => _infos(['only:1b']));
    await tapText(tester, s.ollamaCloud);
    await tester.enterText(field(0), 'key');
    await settle(tester);
    expect(find.text(s.test), findsOneWidget);
    await tapText(tester, s.test);
    await tapText(tester, s.save);
  });

  testWidgets('summary: a vanished saved model is called out; a pick saves at once', (tester) async {
    final store = _FakeStore(
      const AssistantProviderConfig(
        kind: AssistantProviderKind.ollamaCloud,
        baseUrl: AssistantProviderConfig.ollamaCloudUrl,
        apiKey: 'k',
        model: 'old:7b',
      ),
    );
    await pump(tester, store, (_) async => _infos(['new:8b']));
    expect(find.text(s.savedModelGone(model: 'old:7b')), findsOneWidget);
    await tapText(tester, 'new:8b');
    expect(store.saves, 1);
    expect(store.config!.model, 'new:8b');
    expect(store.config!.apiKey, 'k');
    expect(find.text(s.savedModelGone(model: 'old:7b')), findsNothing);
  });

  for (final (model, kept) in [('qwen3:32b', true), ('gpt-oss:120b', false)]) {
    testWidgets(
      'Change and save again with ${kept ? 'the same' : 'another'} model ${kept ? 'keeps' : 'drops'} the timeout',
      (tester) async {
        final store = _FakeStore(
          const AssistantProviderConfig(
            kind: AssistantProviderKind.ollamaCloud,
            baseUrl: AssistantProviderConfig.ollamaCloudUrl,
            apiKey: 'k',
            model: 'qwen3:32b',
            timeoutOverride: Duration(seconds: 5),
          ),
        );
        await pump(tester, store, (_) async => _infos(['gpt-oss:120b', 'qwen3:32b']));
        await tapText(tester, s.change);
        await tapText(tester, s.ollamaCloud);
        await tester.enterText(field(0), 'k2');
        await settle(tester);
        await tapText(tester, model);
        await tapText(tester, s.test);
        await tapText(tester, s.save);

        expect(store.config!.model, model);
        expect(store.config!.timeoutOverride, kept ? const Duration(seconds: 5) : null);
      },
    );
  }

  testWidgets('Change to the same provider keeps the saved key and URL: only the model changes', (tester) async {
    final seen = <AssistantProviderConfig>[];
    for (final saved in const [
      AssistantProviderConfig(
        kind: AssistantProviderKind.ollamaCloud,
        baseUrl: AssistantProviderConfig.ollamaCloudUrl,
        apiKey: 'k',
        model: 'qwen3:32b',
      ),
      AssistantProviderConfig(
        kind: AssistantProviderKind.ollamaServer,
        baseUrl: 'http://o.lan:11434',
        headerName: 'X-Auth',
        headerValue: 'secret',
        model: 'qwen3:32b',
      ),
    ]) {
      final store = _FakeStore(saved);
      await pump(tester, store, (config) async {
        seen.add(config);
        return _infos(['gpt-oss:120b', 'qwen3:32b']);
      });
      await tapText(tester, s.change);
      await tapText(tester, saved.kind == AssistantProviderKind.ollamaCloud ? s.ollamaCloud : s.ollamaServer);
      await settle(tester);
      // Nothing typed: the secret stays out of the field, the models load anyway.
      expect(find.text('gpt-oss:120b'), findsOneWidget, reason: saved.kind.name);
      expect(find.text('secret'), findsNothing);
      await tapText(tester, 'gpt-oss:120b');
      await tapText(tester, s.test);
      await tapText(tester, s.save);

      expect(store.config!.model, 'gpt-oss:120b');
      expect(store.config!.apiKey, saved.apiKey);
      expect(store.config!.baseUrl, saved.baseUrl);
      expect(store.config!.headerName, saved.headerName);
      expect(store.config!.headerValue, saved.headerValue);
      expect(seen.last.apiKey, saved.apiKey, reason: 'the test call used the kept key');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Change to the same server with another URL or header does not send the saved header value', (
    tester,
  ) async {
    final seen = <AssistantProviderConfig>[];
    await pump(
      tester,
      _FakeStore(
        const AssistantProviderConfig(
          kind: AssistantProviderKind.ollamaServer,
          baseUrl: 'http://o.lan:11434',
          headerName: 'X-Auth',
          headerValue: 'secret',
          model: 'qwen3:32b',
        ),
      ),
      (config) async {
        seen.add(config);
        return _infos(['qwen3:32b']);
      },
    );
    await tapText(tester, s.change);
    await tapText(tester, s.ollamaServer);
    await settle(tester);
    expect(seen.last.headerValue, 'secret', reason: 'same host and header keep it');

    await tester.enterText(field(0), 'http://other.lan:11434');
    await settle(tester);
    expect(seen.last.baseUrl, 'http://other.lan:11434');
    expect(seen.last.headerValue, isEmpty);

    await tester.enterText(field(0), 'http://o.lan:11434');
    await tester.enterText(field(1), 'X-Other');
    await settle(tester);
    expect(seen.last.headerName, 'X-Other');
    expect(seen.last.headerValue, isEmpty);
  });

  testWidgets('summary: long OpenRouter lists are capped behind Meer tonen', (tester) async {
    final store = _FakeStore(
      const AssistantProviderConfig(
        kind: AssistantProviderKind.openRouter,
        baseUrl: AssistantProviderConfig.openRouterUrl,
        apiKey: 'k',
        model: 'v/m00',
      ),
    );
    await pump(tester, store, (_) async => _infos([for (var i = 0; i < 30; i++) 'v/m${i.toString().padLeft(2, '0')}']));
    expect(find.text('v/m11'), findsOneWidget);
    expect(find.text('v/m12'), findsNothing);
    await tapText(tester, s.showMore(count: 18));
    expect(find.text('v/m12'), findsOneWidget);
    expect(find.text(s.updateModel), findsNothing, reason: 'OpenRouter has nothing to pull');
  });

  testWidgets('Ollama server: Model bijwerken shows progress, then refreshes', (tester) async {
    const config = AssistantProviderConfig(
      kind: AssistantProviderKind.ollamaServer,
      baseUrl: 'http://nas.lan:11434',
      model: 'llama3.1',
    );
    var lists = 0;
    final pulls = StreamController<AssistantPullProgress>();
    await pump(
      tester,
      _FakeStore(config),
      (_) async {
        lists++;
        return _infos(['llama3.1']);
      },
      puller: (c, model) {
        expect(model, 'llama3.1');
        expect(c.baseUrl, 'http://nas.lan:11434');
        return pulls.stream;
      },
    );
    expect(lists, 1);
    // The spinner runs while pulling, so no pumpAndSettle until it ends.
    await tester.ensureVisible(find.text(s.updateModel));
    await tester.tap(find.text(s.updateModel));
    await tester.pump();
    pulls.add(const AssistantPullProgress(status: 'pulling abc', completed: 1, total: 4));
    await tester.pump();
    expect(find.text(s.updating(status: 'pulling abc')), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.25);
    pulls.add(const AssistantPullProgress(status: 'success'));
    await pulls.close();
    await tester.pumpAndSettle();
    expect(find.text(s.updateDone(model: 'llama3.1')), findsOneWidget);
    expect(lists, 2);
  });

  testWidgets('Ollama server: a pull error is mapped, not shown raw', (tester) async {
    await pump(
      tester,
      _FakeStore(
        const AssistantProviderConfig(
          kind: AssistantProviderKind.ollamaServer,
          baseUrl: 'http://nas.lan:11434',
          model: 'llama3.1',
        ),
      ),
      (_) async => _infos(['llama3.1']),
      puller: (_, _) => Stream.error(const AssistantPullException('pull model manifest: file does not exist')),
    );
    await tapText(tester, s.updateModel);
    expect(find.text(s.pullErrorUnknown), findsOneWidget);
  });

  testWidgets('summary: the web switch saves at once', (tester) async {
    final store = _FakeStore(
      const AssistantProviderConfig(
        kind: AssistantProviderKind.ollamaServer,
        baseUrl: 'http://nas.lan:11434',
        model: 'llama3.1',
      ),
    );
    await pump(tester, store, (_) async => _infos(['llama3.1']));
    expect(find.text(s.webSearchNoteServer), findsOneWidget);
    await tapText(tester, s.webSearch);
    expect(store.config!.webSearch, isTrue, reason: 'off by default for a local server');
    expect(store.config!.webSearchChoice, isTrue);
    expect(store.saves, 1);
  });

  test('pull errors map to their own sentences', () {
    expect(assistantPullErrorText(const AssistantPullException('no space left on device')), s.pullErrorDisk);
    expect(assistantPullErrorText(const AssistantPullException('boom')), s.pullErrorFailed(reason: 'boom'));
    expect(assistantPullErrorText(const AssistantModelException(AssistantModelError.unreachable)), s.errorUnreachable);
  });

  test('model details line: Ollama facts and a relative date; OpenRouter context and price', () {
    final now = DateTime.utc(2026, 10, 2);
    final ollama = AssistantModelInfo(
      id: 'llama3.1:8b',
      parameterSize: '8.0B',
      quantization: 'Q4_K_M',
      sizeBytes: 4920753328,
      modifiedAt: DateTime.utc(2026, 9, 29),
    );
    final line = assistantModelDetails(ollama, now: now);
    expect(line, startsWith('8.0B · Q4_K_M · '));
    expect(line, endsWith(s.updatedDays(n: 3)));
    expect(assistantModelUpdatedLabel(now, now: now), s.updatedToday);
    expect(assistantModelUpdatedLabel(DateTime.utc(2026, 6, 1), now: now), s.updatedMonths(n: 4));
    expect(assistantModelUpdatedLabel(DateTime.utc(2024, 9, 1), now: now), s.updatedYears(n: 2));
    const router = AssistantModelInfo(
      id: 'openai/gpt-x',
      name: 'GPT X',
      contextLength: 128000,
      promptPrice: 0,
      completionPrice: 0,
    );
    expect(assistantModelDetails(router), 'openai/gpt-x · ${s.contextLength(size: '128k')} · ${s.priceFree}');
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

  testWidgets('Back on the provider choice closes the TV nested route it was opened in', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: TvNestedRouteScope(
            dismiss: ([_]) => dismissed++,
            markResult: (_) {},
            child: AssistantSettingsScreen(store: _FakeStore(), listModels: (_) async => const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(s.ollamaServer), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });
}
