import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_memory_host.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/multi_server_manager.dart';

import '../services/memory/memory_test_support.dart';
import 'assistant_memory_support.dart';

/// What the model says after a refusal. Pleya's own line replaces it.
const _modelWords = 'Ok, onthouden.';

/// A tool that hands the UI a grid of titles, as a search would.
final _showTool = AssistantTool(
  name: 'show',
  description: 'show',
  risk: AssistantToolRisk.read,
  properties: const {},
  needsServer: false,
  serves: (_, _) => true,
  run: (_, _, _) async => AssistantToolResult(
    const {'ok': true},
    display: AssistantMediaGrid([
      (
        item: MediaItem(id: '42', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Cars', serverId: 's1'),
        group: null,
      ),
    ]),
  ),
);

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
      tools: [pingTool, _showTool, ...assistantMemoryTools],
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

    test('a refused sentence in a run that showed titles: only the fixed line, the cards stay', () async {
      const claim = 'Ik heb onthouden dat je zoon 9 is. Hier zijn films.';
      final c = make([
        callTool('remember_fact', {'value': 'Zoon is 9', 'category': 'household'}),
        callTool('show'),
        say(claim),
      ]);
      await c.submit('Onthoud dat mijn zoon van 9 van Cars houdt', typed: true);

      expect(model.toolOutputs.first, {'error': 'owned_by_kids_ages_setting'});
      expect(c.answer, 'Leeftijden van kinderen onthoud ik hier niet. Die stel je in bij Kinderprofiel.');
      expect(c.displays.whereType<AssistantMediaGrid>(), hasLength(1));
      expect(await profile.values(), isEmpty);
      expect(c.memoryStored, isFalse);
    });

    test('a second remember after a refusal gets no card', () async {
      final c = make([
        callTool('remember_fact', {'value': 'Zoon is 9', 'category': 'household'}),
        callTool('remember_fact', {'value': 'Tim is 9 en houdt van Cars', 'category': 'household'}),
        say(_modelWords),
      ]);
      await c.submit('Onthoud dat mijn zoon van 9 van Cars houdt', typed: true);

      expect(model.toolOutputs, [
        {'error': 'owned_by_kids_ages_setting'},
        {'error': 'not_after_refusal'},
      ]);
      expect(c.memoryProposal, isNull);
      expect(c.answer, 'Leeftijden van kinderen onthoud ik hier niet. Die stel je in bij Kinderprofiel.');
      expect(await profile.values(), isEmpty);
      expect(c.resultIsError, isFalse);
    });

    test('forgetting after a refusal keeps its card', () async {
      final fact = await profile.store('Houdt van westerns');
      final c = make([
        callTool('remember_fact', {'value': 'Zoon is 9', 'category': 'household'}),
        callTool('forget_fact', {'ref': fact.ref}),
        say(_modelWords),
      ]);
      await c.submit('Onthoud dat mijn zoon van 9 van Cars houdt', typed: true);

      expect(c.memoryProposal?.kind, AssistantMemoryProposalKind.forget);
      expect(c.answer, isNot(contains(_modelWords)));
      expect(await profile.values(), ['Houdt van westerns']);
    });

    test('the model claims it remembered without asking for the save: Pleya says nothing was stored', () async {
      final c = make([say(_modelWords)]);
      await c.submit('Onthoud dat ik op zondag graag natuurfilms kijk', typed: true);

      expect(c.answer, 'Dat heb ik niet onthouden. Er is niets opgeslagen.');
      expect(await profile.values(), isEmpty);
      expect(c.memoryProposal, isNull);
      expect(c.memoryStored, isFalse);
      expect(c.resultIsError, isFalse);

      await LocaleSettings.setLocale(AppLocale.en);
      final en = make([say('Ok, remembered.')]);
      await en.submit('Remember that I like nature films on Sundays', typed: true);
      expect(en.answer, 'I did not remember that. Nothing was stored.');
      expect(await profile.values(), isEmpty);
    });

    test('nothing stored and titles shown: the fixed line without the model text, the cards stay', () async {
      final c = make([callTool('show'), say('Onthouden. Hier zijn films.')]);
      await c.submit('Onthoud dat ik op zondag graag natuurfilms kijk', typed: true);

      expect(c.answer, 'Dat heb ik niet onthouden. Er is niets opgeslagen.');
      expect(c.displays.whereType<AssistantMediaGrid>(), hasLength(1));
      expect(await profile.values(), isEmpty);
    });

    test('typed words the memory would refuse, and no save asked: the line of the refusal', () async {
      final c = make([say(_modelWords)]);
      await c.submit('Onthoud dat mijn zoon van 9 van Cars houdt', typed: true);

      expect(c.answer, 'Leeftijden van kinderen onthoud ik hier niet. Die stel je in bij Kinderprofiel.');
      expect(await profile.values(), isEmpty);
    });

    test('the model text stays when the request was not typed or waits on a card', () async {
      final chip = make([say(_modelWords)]);
      await chip.submit('Onthoud dat ik op zondag graag natuurfilms kijk');
      expect(chip.answer, _modelWords);

      // A card: the first call was another tool, so the save waits for a yes.
      final card = make([callTool('ping'), ...remember('Kijkt op zondag graag natuurfilms')]);
      await card.submit('Onthoud dat ik op zondag graag natuurfilms kijk', typed: true);
      expect(card.memoryProposal, isNotNull);
      expect(card.answer, _modelWords);
    });

    test('the sentence is in the memory already and the model only answers: Pleya says it was there', () async {
      await profile.store('Ik op zondag graag natuurfilms kijk');
      final c = make([say('Dat wist ik al.')]);
      await c.submit('Onthoud dat ik op zondag graag natuurfilms kijk', typed: true);

      expect(c.answer, 'Dat stond al in je geheugen.');
      expect(await profile.values(), ['Ik op zondag graag natuurfilms kijk']);
      expect(c.memoryProposal, isNull);
      expect(c.memoryStored, isFalse);
      expect(c.resultIsError, isFalse);

      await LocaleSettings.setLocale(AppLocale.en);
      await profile.store('I like nature films on Sundays');
      final en = make([say('I knew that.')]);
      await en.submit('Remember that I like nature films on Sundays', typed: true);
      expect(en.answer, 'That was already in your memory.');
    });

    test('the sentence is in the memory already and the model reads the memory first: the same line', () async {
      await profile.store('Ik op zondag graag natuurfilms kijk');
      final c = make([callTool('recall_memory'), say('Dat staat er al in.')]);
      await c.submit('Onthoud dat ik op zondag graag natuurfilms kijk', typed: true);

      expect(c.answer, 'Dat stond al in je geheugen.');
      expect(await profile.values(), ['Ik op zondag graag natuurfilms kijk']);
      expect(c.resultIsError, isFalse);
    });

    test('the sentence is in the memory already and the model asks for the save: the same line', () async {
      await profile.store('Ik op zondag graag natuurfilms kijk');
      final c = make(remember('Kijkt op zondag graag natuurfilms'));
      await c.submit('Onthoud dat ik op zondag graag natuurfilms kijk', typed: true);

      expect(model.toolOutputs.single['status'], 'already_known');
      expect(c.answer, 'Dat stond al in je geheugen.');
      expect(await profile.values(), ['Ik op zondag graag natuurfilms kijk']);
      expect(c.memoryStored, isFalse);
    });

    test('another sentence in the memory is not this one: nothing stored says so', () async {
      await profile.store('Houdt van westerns');
      final c = make([say(_modelWords)]);
      await c.submit('Onthoud dat ik op zondag graag natuurfilms kijk', typed: true);

      expect(c.answer, 'Dat heb ik niet onthouden. Er is niets opgeslagen.');
      expect(await profile.values(), ['Houdt van westerns']);
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

    test('no save asked: the field says nothing was stored', () async {
      final h = host([say(_modelWords)]);
      await h.ask('Onthoud dat ik op zondag graag natuurfilms kijk');

      expect(h.answer, 'Dat heb ik niet onthouden. Er is niets opgeslagen.');
      expect(h.failure, isNull);
      expect(h.proposal, isNull);
      expect(await profile.values(), isEmpty);
    });

    test('the sentence is in the memory already: the field says it was there', () async {
      await profile.store('Ik op zondag graag natuurfilms kijk');
      final h = host([say('Dat wist ik al.')]);
      await h.ask('Onthoud dat ik op zondag graag natuurfilms kijk');
      expect(h.answer, 'Dat stond al in je geheugen.');
      expect(h.failure, isNull);
      expect(h.proposal, isNull);

      final read = host([callTool('recall_memory'), say('Dat staat er al in.')]);
      await read.ask('Onthoud dat ik op zondag graag natuurfilms kijk');
      expect(read.answer, 'Dat stond al in je geheugen.');
      expect(read.failure, isNull);
      expect(await profile.values(), ['Ik op zondag graag natuurfilms kijk']);
    });
  });
}
