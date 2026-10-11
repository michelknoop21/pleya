import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_memory_host.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import '../services/memory/memory_test_support.dart';
import 'assistant_find_fakes.dart';
import 'assistant_memory_support.dart';

class _Server extends FakeServer {
  _Server(super.id);
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;
}

/// Holds every reply back until [release] completes.
class _SlowModel extends ScriptedModel {
  _SlowModel(super.script);
  final release = Completer<void>();

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    await release.future;
    return super.chat(messages, tools, abort: abort);
  }
}

/// The run of the memory screen: only the memory tools, its own state, and
/// the same rules for writing as the conversation.
void main() {
  late AppDatabase db;
  late MultiServerManager servers;
  late MemoryProfile profile;
  late ScriptedModel model;
  AssistantProviderConfig? config = memoryConfig;

  AssistantMemoryHost host(List<Object> script, {ScriptedModel? use}) {
    model = use ?? ScriptedModel(script);
    final h = AssistantMemoryHost(
      buildContext: () => profile.context(servers),
      languageName: () => 'Dutch',
      entitlement: const Entitled(),
      loadConfig: () async => config,
      modelFor: (_) => model,
    );
    addTearDown(h.dispose);
    return h;
  }

  setUp(() async {
    await resetMemoryPrefs();
    await LocaleSettings.setLocale(AppLocale.nl);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));
    config = memoryConfig;
    db = memoryTestDatabase();
    addTearDown(db.close);
    servers = MultiServerManager();
    addTearDown(servers.dispose);
    profile = MemoryProfile(db, 'profile-a');
  });

  const memoryTools = ['recall_memory', 'remember_fact', 'forget_fact'];

  test('offers the three memory tools and nothing else, whatever the question', () async {
    for (final question in [
      'Wat herinner je je over mij?',
      'Wie is Walter White en wat gebeurde er met hem?',
      'Controleer de bibliotheek op ontbrekende afleveringen',
      'Zoek een komedie voor vanavond',
    ]) {
      final h = host([
        callTools([
          ('spoiler_context', {}),
          ('diagnose_library', {}),
          ('search_catalog', {'query': 'x'}),
        ]),
        say('Dat hoort in het gesprek met Big P.'),
      ]);
      await h.ask(question);

      expect(model.offered, everyElement(memoryTools), reason: question);
      expect(model.toolOutputs, everyElement({'error': 'unknown_tool'}), reason: question);
      expect(h.answer, 'Dat hoort in het gesprek met Big P.', reason: question);
    }
  });

  test('"Wat herinner je je over mij?" is answered from the memory, not as a spoiler question', () async {
    await profile.store('Houdt niet van horror', category: MemoryCategory.dislike);
    final h = host([callTool('recall_memory'), say('Je houdt niet van horror.')]);
    await h.ask('Wat herinner je je over mij?');

    expect(h.answer, 'Je houdt niet van horror.');
    expect(h.failure, isNull);
    expect((model.toolOutputs.single['facts'] as List).single['text'], 'Houdt niet van horror');
  });

  test(
    '"Vergeet de herinnering over horror" gives the forget card; yes removes and marks the overview stale',
    () async {
      final fact = await profile.store('Houdt niet van horror', category: MemoryCategory.dislike);
      final h = host([
        callTool('recall_memory', {'query': 'horror'}),
        callTool('forget_fact', {'ref': fact.ref}),
        say('Zal ik dat vergeten?'),
      ]);
      await h.ask('Vergeet de herinnering over horror');

      final card = h.proposal!;
      expect(card.kind, AssistantMemoryProposalKind.forget);
      expect(card.target!.value, 'Houdt niet van horror');
      expect(await profile.values(), ['Houdt niet van horror']);
      expect(h.overviewStale, isFalse);

      await h.answerProposal(card, accept: true);
      expect(await profile.values(), isEmpty);
      expect(h.proposal, isNull);
      expect(h.outcome!.ok, isTrue);
      expect(h.overviewStale, isTrue);
      h.overviewWritten();
      expect(h.overviewStale, isFalse);
    },
  );

  test('a typed "onthoud dat" stores at once and marks the overview stale', () async {
    final h = host([
      callTool('remember_fact', {'value': 'Kijkt op vrijdagavond met het gezin', 'category': 'household'}),
      say('Genoteerd.'),
    ]);
    await h.ask('Onthoud dat we op vrijdagavond met het gezin kijken');

    expect(await profile.values(), ['Kijkt op vrijdagavond met het gezin']);
    expect(h.answer, 'Onthouden: Kijkt op vrijdagavond met het gezin.');
    expect(h.proposal, isNull);
    expect(h.overviewStale, isTrue);
  });

  test('a replacement waits for a yes, also after "onthoud dat"', () async {
    final old = await profile.store('Kijkt op vrijdagavond met het gezin', category: MemoryCategory.household);
    final h = host([
      callTool('remember_fact', {
        'value': 'Kijkt op zaterdagavond met het gezin',
        'category': 'household',
        'replaces': old.ref,
      }),
      say('Zal ik dit vervangen?'),
    ]);
    await h.ask('Onthoud dat we tegenwoordig op zaterdag met het gezin kijken');

    expect(await profile.values(), ['Kijkt op vrijdagavond met het gezin']);
    expect(h.overviewStale, isFalse);
    await h.answerProposal(h.proposal!, accept: false);
    expect(await profile.values(), ['Kijkt op vrijdagavond met het gezin']);
    expect(h.overviewStale, isFalse);
    expect(h.outcome, isNull);
  });

  test('a tapped follow-up never stores without a yes, whatever it says', () async {
    final h = host([
      callTool('remember_fact', {'value': 'Houdt van horror', 'category': 'preference'}),
      say('Zal ik dat onthouden?'),
    ]);
    await h.askFollowUp('Onthoud dat ik van horror houd');

    expect(await profile.values(), isEmpty);
    expect(h.proposal!.value, 'Houdt van horror');
    expect(h.overviewStale, isFalse);

    await h.answerProposal(h.proposal!, accept: true);
    expect(await profile.values(), ['Houdt van horror']);
    expect((await profile.service.list()).single.source, MemorySource.assistantConfirmed);
  });

  test('a profile switch between the card and the yes stores nothing', () async {
    final h = host([
      callTool('remember_fact', {'value': 'Houdt van horror', 'category': 'preference'}),
      say('Zal ik dat onthouden?'),
    ]);
    await h.ask('Ik houd van horror.');
    final card = h.proposal!;
    profile.active = 'profile-b';
    await h.answerProposal(card, accept: true);

    expect(await profile.values(), isEmpty);
    expect(h.outcome!.code, 'profile_changed');
    expect(h.overviewStale, isFalse);
  });

  test('a children\'s profile reads and writes nothing here either', () async {
    await profile.store('Houdt niet van horror');
    profile.kids = true;
    final h = host([
      callTools([
        ('recall_memory', {}),
        ('remember_fact', {'value': 'Houdt van horror', 'category': 'preference'}),
      ]),
      say('Dat kan hier niet.'),
    ]);
    await h.ask('Onthoud dat ik van horror houd');

    expect(model.calls, 0, reason: 'no model call on a children\'s profile');
    expect(h.failure, 'kids_mode_unsupported');
    expect(await profile.values(), ['Houdt niet van horror']);
    expect(h.proposal, isNull);
  });

  group('with a server in sight, so a run could reach the model', () {
    setUp(() {
      servers.debugRegisterClientForTesting(_Server('w'));
      servers.setVisibleServerIds(null);
    });

    test('an adult profile with its memory on does call the model', () async {
      final h = host([say('Niets.')]);
      await h.ask('Wat weet je van mij?');
      expect(model.calls, 1);
      expect(h.failure, isNull);
    });

    test('memory off: no model call, a fixed code', () async {
      await profile.service.setEnabled(false);
      final h = host([say('Vrij antwoord.')]);
      await h.ask('Wat weet je van mij?');

      expect(model.calls, 0);
      expect(h.failure, 'memory_off');
      expect(h.answer, isEmpty);
    });

    test('a children\'s profile: no model call, a fixed code', () async {
      profile.kids = true;
      final h = host([say('Vrij antwoord.')]);
      await h.ask('Wat weet je van mij?');

      expect(model.calls, 0);
      expect(h.failure, 'kids_mode_unsupported');
    });

    test('another active profile: no model call', () async {
      profile.active = 'profile-b';
      final h = host([say('Vrij antwoord.')]);
      await h.ask('Wat weet je van mij?');

      expect(model.calls, 0);
      expect(h.failure, 'memory_off');
    });
  });

  test('a children\'s profile between the card and the yes: the card goes and a yes writes nothing', () async {
    final h = host([
      callTool('remember_fact', {'value': 'Houdt van horror', 'category': 'preference'}),
      say('Ok.'),
    ]);
    await h.ask('Ik houd van horror.');
    final card = h.proposal!;
    await h.recheckCards();
    expect(h.proposal, same(card));

    profile.kids = true;
    await h.answerProposal(card, accept: true);
    expect(await profile.values(), isEmpty);
    expect(h.outcome!.code, 'kids_mode_unsupported');

    final again = host([
      callTool('remember_fact', {'value': 'Houdt van horror', 'category': 'preference'}),
      say('Ok.'),
    ]);
    profile.kids = false;
    await again.ask('Ik houd van horror.');
    expect(again.proposal, isNotNull);
    profile.kids = true;
    await again.recheckCards();
    expect(again.proposal, isNull);
  });

  group('next to the conversation', () {
    AssistantController chat(ScriptedModel chatModel) {
      final c = AssistantController(
        buildContext: (_) => profile.context(servers),
        rolloutEnabled: true,
        entitlement: const Entitled(),
        loadConfig: () async => memoryConfig,
        modelFor: (_) => chatModel,
        languageName: () => 'Dutch',
        tools: [pingTool, ...assistantMemoryTools],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the field reads none of the chat\'s turns and adds none', () async {
      final chatModel = ScriptedModel([say('GEHEIM-CHAT-ANTWOORD over komedies.')]);
      final c = chat(chatModel);
      await c.submit('Wat is een goede komedie?');
      expect(c.conversation, hasLength(1));

      final h = host([say('Ik weet nog niets over je.')]);
      await h.ask('Wat herinner je je over mij?');

      expect(model.sent(0), isNot(contains('GEHEIM-CHAT-ANTWOORD')));
      expect(model.sent(0), isNot(contains('goede komedie')));
      expect(c.conversation, hasLength(1));
      expect(c.conversation.single.question, 'Wat is een goede komedie?');
      expect(c.prompt, 'Wat is een goede komedie?');
      expect(c.answer, 'GEHEIM-CHAT-ANTWOORD over komedies.');
      expect(c.state, AssistantSurfaceState.result);
    });

    test('a card waiting in the chat does not block the field, and the field\'s card is not the chat\'s', () async {
      final chatModel = ScriptedModel([
        callTool('remember_fact', {'value': 'Houdt niet van horror', 'category': 'dislike'}),
        say('Klaar.'),
      ]);
      final c = chat(chatModel);
      await c.submit('Iets spannends, maar geen horror.');
      expect(c.memoryProposal, isNotNull);

      final h = host([
        callTool('remember_fact', {'value': 'Houdt van komedies', 'category': 'preference'}),
        say('Zal ik dat onthouden?'),
      ]);
      await h.ask('Ik houd van komedies.');
      expect(h.busy, isFalse);
      expect(h.proposal!.value, 'Houdt van komedies');
      expect(c.memoryProposal!.value, 'Houdt niet van horror');

      await h.answerProposal(h.proposal!, accept: true);
      expect(await profile.values(), ['Houdt van komedies']);
      expect(c.memoryProposal, isNotNull, reason: 'the chat card still waits');
    });
  });

  group('its own busy state', () {
    test('a second question while one runs is not started', () async {
      final slow = _SlowModel([say('Eerste antwoord.')]);
      final h = host([], use: slow);
      final first = h.ask('Wat weet je van mij?');
      await Future<void>.delayed(Duration.zero);
      expect(h.busy, isTrue);
      await h.ask('En nog iets?');
      expect(h.question, 'Wat weet je van mij?');

      slow.release.complete();
      await first;
      expect(h.busy, isFalse);
      expect(h.answer, 'Eerste antwoord.');
      expect(slow.calls, 1);
    });

    test('a cancelled run drops its answer and its card', () async {
      final slow = _SlowModel([
        callTool('remember_fact', {'value': 'Houdt van horror', 'category': 'preference'}),
        say('Laat antwoord.'),
      ]);
      final h = host([], use: slow);
      final running = h.ask('Ik houd van horror.');
      await Future<void>.delayed(Duration.zero);
      h.cancel();
      expect(h.busy, isFalse);
      slow.release.complete();
      await running;

      expect(h.answer, isEmpty);
      expect(h.proposal, isNull);
      expect(await profile.values(), isEmpty);
    });

    test('no model set up, a provider error and memory off end with a fixed code', () async {
      config = null;
      final h = host([]);
      await h.ask('Wat weet je van mij?');
      expect(h.failure, 'needs_setup');
      expect(h.busy, isFalse);

      config = memoryConfig;
      final broken = host([const AssistantModelException(AssistantModelError.unreachable)]);
      await broken.ask('Wat weet je van mij?');
      expect(broken.failure, 'providerError');
      expect(broken.answer, isEmpty);

      await profile.service.setEnabled(false);
      final off = host([]);
      await off.ask('Wat weet je van mij?');
      expect(off.failure, 'memory_off');
      expect(model.calls, 0);
    });
  });
}
