import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_memory_host.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/multi_server_manager.dart';

import '../services/memory/memory_test_support.dart';
import 'assistant_memory_support.dart';

/// What the model says after a refusal. Pleya's own line replaces it.
const _modelWords = 'Ok, onthouden.';

final _tooLong = 'ik op zondag graag ${'heel ' * 45}lange natuurfilms kijk';

/// Typed words the memory does not take: Pleya says why in a fixed line of
/// its own, and the model's answer is not shown.
void main() {
  late AppDatabase db;
  late MultiServerManager servers;
  late MemoryProfile profile;
  late ScriptedModel model;

  List<Object> remember(String value) => [
    callTool('remember_fact', {'value': value, 'category': 'preference'}),
    say(_modelWords),
  ];

  AssistantController make(List<Object> script) {
    model = ScriptedModel(script);
    final c = AssistantController(
      buildContext: (_) => profile.context(servers),
      rolloutEnabled: true,
      entitlement: const Entitled(),
      loadConfig: () async => memoryConfig,
      modelFor: (_) => model,
      languageName: () => 'Dutch',
      tools: [pingTool, ...assistantMemoryTools],
    );
    addTearDown(c.dispose);
    return c;
  }

  AssistantMemoryHost host(List<Object> script) {
    model = ScriptedModel(script);
    final h = AssistantMemoryHost(
      buildContext: () => profile.context(servers),
      languageName: () => 'Dutch',
      entitlement: const Entitled(),
      loadConfig: () async => memoryConfig,
      modelFor: (_) => model,
    );
    addTearDown(h.dispose);
    return h;
  }

  setUp(() async {
    await resetMemoryPrefs();
    await LocaleSettings.setLocale(AppLocale.nl);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.en));
    db = memoryTestDatabase();
    addTearDown(db.close);
    servers = MultiServerManager();
    addTearDown(servers.dispose);
    profile = MemoryProfile(db, 'profile-a');
  });

  /// The typed request, the fixed code the model gets and Pleya's line.
  List<(String, String, String)> refusals() => [
    (
      'Onthoud dat mijn zoon van 9 van Cars houdt',
      'owned_by_kids_ages_setting',
      'Leeftijden van kinderen onthoud ik hier niet. Die stel je in bij Kinderprofiel.',
    ),
    (
      'Onthoud dat mijn dochter van acht van paarden houdt',
      'owned_by_kids_ages_setting',
      'Leeftijden van kinderen onthoud ik hier niet. Die stel je in bij Kinderprofiel.',
    ),
    (
      'Onthoud dat ik liever Engels dan Nederlands hoor',
      'owned_by_language_setting',
      'Een taalvoorkeur onthoud ik hier niet. Die stel je in bij de taalinstellingen, onder Taal en ondertitels.',
    ),
    (
      'Onthoud dat $_tooLong',
      'too_long',
      'Dat is te lang om te onthouden. Een herinnering is één zin van hoogstens 200 tekens.',
    ),
  ];

  group('in the conversation', () {
    test('an age, a language and a sentence that is too long each get their own line', () async {
      for (final (typed, code, line) in refusals()) {
        final c = make(remember('Houdt van paarden'));
        await c.submit(typed, typed: true);

        expect(model.toolOutputs.single, {'error': code}, reason: typed);
        expect(c.answer, line, reason: typed);
        expect(c.answer, isNot(contains(_modelWords)), reason: typed);
        expect(await profile.values(), isEmpty, reason: typed);
        expect(c.memoryProposal, isNull, reason: typed);
        expect(c.memoryStored, isFalse, reason: typed);
        expect(c.resultIsError, isFalse, reason: typed);
      }
    });

    test('a full memory gets its own line and stores nothing', () async {
      for (var i = 0; i < kMemoryFactLimit; i++) {
        await profile.store('Feit nummer $i');
      }
      final c = make(remember('Houdt van natuurfilms'));
      await c.submit('Onthoud dat ik op zondag graag natuurfilms kijk', typed: true);

      expect(model.toolOutputs.single, {'error': 'memory_full'});
      expect(c.answer, 'Het geheugen is vol. Verwijder eerst een herinnering, dan kan ik dit onthouden.');
      expect(await profile.service.list(), hasLength(kMemoryFactLimit));
      expect(c.memoryProposal, isNull);
    });

    test('the lines in English name the same two settings', () async {
      await LocaleSettings.setLocale(AppLocale.en);
      final lines = <String>[];
      for (final typed in [
        'Remember that my daughter of eight loves horses',
        'Remember that I prefer English over Dutch',
        'Remember that $_tooLong',
      ]) {
        final c = make(remember('Likes horses'));
        await c.submit(typed, typed: true);
        expect(await profile.values(), isEmpty, reason: typed);
        lines.add(c.answer);
      }

      expect(lines, [
        "I do not keep children's ages here. Set them under Children's profile.",
        'I do not keep a language preference here. Set it in the language settings, under Language & subtitles.',
        'That is too long to remember. A memory is one sentence of at most 200 characters.',
      ]);
    });

    test('a refusal of what the model proposed itself keeps the model\'s answer', () async {
      final c = make(remember('Dochter is 8'));
      await c.submit('Mijn dochter kijkt graag mee', typed: true);

      expect(model.toolOutputs.single, {'error': 'owned_by_kids_ages_setting'});
      expect(c.answer, _modelWords);
      expect(await profile.values(), isEmpty);
    });

    test('typed words that are stored say so as before', () async {
      final c = make(remember('Houdt van paarden'));
      await c.submit('Onthoud dat ik op zondag graag natuurfilms kijk', typed: true);

      expect(c.answer, 'Onthouden: Ik op zondag graag natuurfilms kijk.');
    });
  });

  group('in the field of the memory screen', () {
    test('each refusal gets the same line', () async {
      for (final (typed, code, line) in refusals()) {
        final h = host(remember('Houdt van paarden'));
        await h.ask(typed);

        expect(model.toolOutputs.single, {'error': code}, reason: typed);
        expect(h.answer, line, reason: typed);
        expect(h.failure, isNull, reason: typed);
        expect(h.proposal, isNull, reason: typed);
        expect(await profile.values(), isEmpty, reason: typed);
      }
    });
  });
}
