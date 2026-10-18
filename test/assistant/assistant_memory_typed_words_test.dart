import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_memory_host.dart';
import 'package:pleya/assistant/assistant_memory_intent.dart';
import 'package:pleya/assistant/assistant_spoiler_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/multi_server_manager.dart';

import '../services/memory/memory_test_support.dart';
import 'assistant_memory_support.dart';

/// What the user typed, what the model wanted stored instead, and the typed
/// words as Pleya stores them.
typedef _Attack = (String typed, String model, String stored);

/// The re-review's examples: each stored a claim the user never made.
const List<_Attack> _reported = [
  ('Onthoud dat ik niet van horror houd', 'Houdt van horror', 'Ik niet van horror houd'),
  ('Onthoud dat ik geen horror wil zien', 'Wil horror zien', 'Ik geen horror wil zien'),
  ('Remember that I do not like horror', 'Likes horror', 'I do not like horror'),
  ('Remember that I never watch horror', 'Watches horror', 'I never watch horror'),
  ('Onthoud dat ik van horror houd', 'Houdt niet van horror', 'Ik van horror houd'),
  (
    'Onthoud dat ik van horror houd maar mijn vrouw niet',
    'Vrouw houdt van horror',
    'Ik van horror houd maar mijn vrouw niet',
  ),
  (
    'Onthoud dat ik liever komedie dan horror kijk',
    'Kijkt liever horror dan komedie',
    'Ik liever komedie dan horror kijk',
  ),
  (
    'Onthoud dat ik horror alleen kijk als de kinderen slapen',
    'Kijkt horror met de kinderen',
    'Ik horror alleen kijk als de kinderen slapen',
  ),
  ('Onthoud dat ik de film Hostel te eng vond', 'Vond Hostel niet te eng', 'Ik de film Hostel te eng vond'),
  (
    'Onthoud dat ik maximaal 2 afleveringen per avond kijk',
    'Kijkt maximaal 9 afleveringen per avond',
    'Ik maximaal 2 afleveringen per avond kijk',
  ),
  ('Onthoud dat ik van horror houd en van komedie', 'Houdt van horror 18+', 'Ik van horror houd en van komedie'),
];

/// Ten more: negation, number, order and condition, in Dutch and English.
const List<_Attack> _own = [
  ('Onthoud dat ik nooit horror kijk', 'Kijkt horror', 'Ik nooit horror kijk'),
  ('Remember that I like horror', 'Likes no horror', 'I like horror'),
  ('Onthoud dat ik wel van thrillers houd', 'Houdt van thrillers', 'Ik wel van thrillers houd'),
  (
    'Remember that I watch at most 3 episodes a night',
    'Watches at most 30 episodes a night',
    'I watch at most 3 episodes a night',
  ),
  ('Onthoud dat ik films uit 1999 mooi vind', 'Vindt films uit 1998 mooi', 'Ik films uit 1999 mooi vind'),
  ('Remember that I prefer comedy over horror', 'Prefers horror over comedy', 'I prefer comedy over horror'),
  (
    'Onthoud dat mijn vrouw meer van drama houdt dan ik',
    'Houdt meer van drama dan vrouw',
    'Mijn vrouw meer van drama houdt dan ik',
  ),
  ('Remember that I only watch horror if the kids sleep', 'Watches horror', 'I only watch horror if the kids sleep'),
  ('Onthoud dat ik series kijk zonder reclame', 'Kijkt series met reclame', 'Ik series kijk zonder reclame'),
  ('Remember that I like horror if it is not gory', 'Likes gory horror', 'I like horror if it is not gory'),
];

/// The second re-review's examples: the difference sat in a sign, an emoji or
/// an invisible character, or in a last word turned to the front.
const List<_Attack> _signs = [
  (
    'Onthoud dat ik 2 afleveringen per avond kijk',
    'Kijkt <2 afleveringen per avond',
    'Ik 2 afleveringen per avond kijk',
  ),
  ('Remember that I watch 2 episodes a night', 'Watches -2 episodes a night', 'I watch 2 episodes a night'),
  ('Onthoud dat ik films van 16 kijk', 'Kijkt films van 16+', 'Ik films van 16 kijk'),
  ('Onthoud dat ik 1,5 uur per dag kijk', 'Kijkt 1-5 uur per dag', 'Ik 1,5 uur per dag kijk'),
  ('Onthoud dat ik van horror houd', 'Houdt ≠ van horror', 'Ik van horror houd'),
  ('Onthoud dat ik van horror houd', '🚫 Houdt van horror', 'Ik van horror houd'),
  ('Onthoud dat ik van horror houd', 'Houdt van horror 👎', 'Ik van horror houd'),
  ('Onthoud dat ik van horror houd', '~~Houdt van horror~~ (!)', 'Ik van horror houd'),
  ('Onthoud dat ik van horror houd', 'Houdt van horr\u0336or', 'Ik van horror houd'),
  ('Onthoud dat ik van horror houd', 'Houdt\u200B van\u200B horror', 'Ik van horror houd'),
  ('Remember that I watch horror only', 'Only I watch horror', 'I watch horror only'),
  ('Onthoud dat ik kijk horror alleen', 'Alleen ik kijk horror', 'Ik kijk horror alleen'),
  ('Onthoud dat wij kijken thrillers niet', 'Niet wij kijken thrillers', 'Wij kijken thrillers niet'),
  ('Onthoud dat niets van Marvel mij boeit', 'Niet van Marvel mij boeit', 'Niets van Marvel mij boeit'),
  ('Onthoud dat alle films van Nolan goed zijn', 'Alles films van Nolan goed zijn', 'Alle films van Nolan goed zijn'),
  ('Onthoud dat I Robot mijn favoriete film is', 'Is Robot mijn favoriete film', 'I Robot mijn favoriete film is'),
];

/// A model sentence that says what was typed in other words. The typed words
/// are stored all the same: the model's `value` is never read.
const List<_Attack> _reworded = [
  ('Onthoud dat ik niet van horror houd.', 'Houdt niet van horror', 'Ik niet van horror houd'),
  ('Onthoud dat ik houd niet van horror', 'Houdt niet van horror', 'Ik houd niet van horror'),
  ('Onthoud dat ik graag oorlogsfilms kijk', 'Kijkt graag oorlogsfilms', 'Ik graag oorlogsfilms kijk'),
  ('Remember that I like horror', 'Likes horror', 'I like horror'),
  ('Remember: we watch on Fridays', 'Watches on Fridays', 'We watch on Fridays'),
  ('  onthoud dat  ik NIET van horror houd.  ', 'ik NIET van horror houd', 'Ik NIET van horror houd'),
  ('Onthoud dat ik van horror houd', '', 'Ik van horror houd'),
];

/// The forms the re-review ran against the fence, with and without a story
/// question behind the command form.
const _forms = [
  'Onthoud dat ik seizoen 2 heb gezien en geef een samenvatting van het plot van seizoen 3 van Dark',
  'Onthoud dat ik van thrillers hou. Vertel wie de moordenaar is in Broadchurch',
  'Onthoud dat ik van thrillers hou en vertel hoe seizoen 3 van Dark afloopt',
  'Onthoud dat ik van thrillers hou en hoe loopt seizoen 3 van Dark af',
  'Onthoud: x. Hoe loopt seizoen 3 af?',
  'Onthoud: x. Hoe loopt seizoen 3 af',
  'Onthoud: x. Hoe eindigt Dark',
  'Onthoud dat ik Dark kijk en vertel me het einde',
  'Onthoud dat ik Dark kijk en zeg wie er doodgaat',
  'Remember that I like thrillers and tell me how Breaking Bad ends',
  'Remember that I like thrillers and tell me who dies in Breaking Bad',
  'Remember that I like thrillers. Does Walter die',
  'Remember: x. What is the ending of Dark',
  'Remember that I watch Dark and tell me the twist',
  'remember that i like thrillers and remind me what happened to Walter',
  'Onthoud dat ik van een goed verhaal houd',
  'Onthoud dat ik geen spoilers wil',
  'Remember that I love plot twists',
  'Onthoud dat mijn dochter een verlegen persoon is',
  'Remember that I like character driven drama',
  'Onthoud dat ik niet van horror houd',
];

/// A fact with a word the spoiler classifier reads as a story question, and
/// the typed words on the card.
const _innocent = [
  ('Onthoud dat ik geen spoilers wil', 'Ik geen spoilers wil'),
  ('Onthoud dat ik van een goed verhaal houd', 'Ik van een goed verhaal houd'),
  ('Remember that I love plot twists', 'I love plot twists'),
  ('Onthoud dat mijn dochter een verlegen persoon is', 'Mijn dochter een verlegen persoon is'),
  ('Remember that I like character driven drama.', 'I like character driven drama'),
];

/// The first review's leaks: a story question behind the command form.
const _leaks = [
  'Onthoud dat ik seizoen 2 heb gezien en geef een samenvatting van het plot van seizoen 3 van Dark',
  'Onthoud dat ik van thrillers hou. Vertel wie de moordenaar is in het verhaal van Broadchurch',
  'Remember that I like thrillers and remind me what happened to Walter in the story',
  'Onthoud: niets. Recap seizoen 3 van Dark met spoilers',
];

/// A typed "onthoud dat" stores the user's claim and no other one, and a
/// story word behind the command form reaches no model.
void main() {
  late AppDatabase db;
  late MultiServerManager servers;
  late MemoryProfile profile;
  late ScriptedModel model;

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

  List<Object> remember(String value) => [
    callTool('remember_fact', {'value': value, 'category': 'preference'}),
    say('Ok.'),
  ];

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

  group('a direct save never changes what was typed', () {
    for (final (typed, wanted, stored) in [..._reported, ..._own, ..._signs, ..._reworded]) {
      test('"$typed" stores the typed words, not "$wanted"', () async {
        final c = make(remember(wanted));
        await c.submit(typed, typed: true);

        final facts = await profile.service.list();
        expect([for (final f in facts) f.value], [stored]);
        expect(facts.single.source, MemorySource.userExplicit);
        expect(c.memoryProposal, isNull);
        expect(c.answer, 'Onthouden: $stored.');
        expect(c.resultIsError, isFalse);
      });
    }

    test('a proposal of Big P, without the command form, keeps the model\'s words on the card', () async {
      final c = make(remember('Houdt van horror'));
      await c.submit('Ik houd echt van horror', typed: true);

      expect(await profile.values(), isEmpty);
      expect(c.memoryProposal!.value, 'Houdt van horror');
      await c.answerMemoryProposal(c.memoryProposal!, accept: true);
      expect(await profile.values(), ['Houdt van horror']);
    });

    test('typed words in the subordinate order that name an age or a language are refused', () async {
      for (final (typed, code) in [
        ('Onthoud dat onze zoon bijna negen wordt', 'owned_by_kids_ages_setting'),
        ('Onthoud dat ik liever Engels dan Nederlands hoor', 'owned_by_language_setting'),
      ]) {
        final c = make(remember('Houdt van paarden'));
        await c.submit(typed, typed: true);
        expect(await profile.values(), isEmpty, reason: typed);
        expect(model.toolOutputs.single, {'error': code}, reason: typed);
        expect(c.memoryProposal, isNull, reason: typed);
      }
    });

    test('the typed words pass the memory\'s own refusals: an age is not stored', () async {
      final c = make(remember('Dochter houdt van paarden'));
      await c.submit('Onthoud dat mijn dochter 8 jaar is', typed: true);

      expect(await profile.values(), isEmpty);
      expect(model.toolOutputs.single, {'error': 'owned_by_kids_ages_setting'});
      expect(c.memoryProposal, isNull);
      expect(c.resultIsError, isFalse);
    });

    test('typed words that are stored already are known, not an error', () async {
      await profile.store('Ik niet van horror houd');
      final c = make(remember('Houdt van horror'));
      await c.submit('Onthoud dat ik niet van horror houd', typed: true);

      expect(await profile.values(), ['Ik niet van horror houd']);
      expect(model.toolOutputs.single['status'], 'already_known');
      expect(c.resultIsError, isFalse);
    });

    test('the field of the memory screen stores the typed words too', () async {
      final h = host(remember('Houdt van horror'));
      await h.ask('Onthoud dat ik niet van horror houd');

      expect(await profile.values(), ['Ik niet van horror houd']);
      expect(h.answer, 'Onthouden: Ik niet van horror houd.');
      expect(h.proposal, isNull);
    });
  });

  group('"onthoud dat" with a story word reaches no model', () {
    for (final (typed, stored) in _innocent) {
      test('"$typed" gives Pleya\'s line and a card with the typed words; a yes stores them', () async {
        final c = make(remember('Iets anders'));
        await c.submit(typed, typed: true);

        expect(model.calls, 0);
        expect(c.answer, t.assistant.memory.storyAsk);
        expect(c.displays, isEmpty);
        expect(c.resultIsError, isFalse);
        expect(await profile.values(), isEmpty);
        final card = c.memoryProposal!;
        expect(card.kind, AssistantMemoryProposalKind.remember);
        expect(card.value, stored);

        await c.answerMemoryProposal(card, accept: true);
        expect(await profile.values(), [stored]);
        expect(c.answer, endsWith('Onthouden: $stored.'));
        expect(model.calls, 0);
      });
    }

    for (final (typed, stored) in [
      ('Wil je onthouden dat ik geen spoilers wil', 'Ik geen spoilers wil'),
      ('Kun je onthouden dat ik van een goed verhaal houd', 'Ik van een goed verhaal houd'),
      ('Please remember that I love plot twists', 'I love plot twists'),
    ]) {
      test('the polite form "$typed" does not vanish: the line and a card, no model call', () async {
        final c = make(remember('Iets anders'));
        await c.submit(typed, typed: true);

        expect(model.calls, 0);
        expect(c.answer, t.assistant.memory.storyAsk);
        expect(await profile.values(), isEmpty);
        expect(c.memoryProposal!.value, stored);
        await c.answerMemoryProposal(c.memoryProposal!, accept: true);
        expect(await profile.values(), [stored]);
      });
    }

    test('the polite form never stores at once, and with a question mark it is a question', () async {
      var c = make(remember('Houdt van thrillers'));
      await c.submit('Wil je onthouden dat ik van thrillers houd', typed: true);
      expect(await profile.values(), isEmpty);
      expect(c.memoryProposal!.value, 'Houdt van thrillers');

      c = make(remember('Wil geen spoilers'));
      await c.submit('Wil je onthouden dat ik geen spoilers wil?', typed: true);
      expect(model.offered.first, isNot(contains('remember_fact')));
      expect(await profile.values(), isEmpty);
      expect(c.memoryProposal, isNull);
    });

    test('an invisible character in the story word does not lift the fence', () async {
      const typed = 'Onthoud dat ik geen sp\u200Boilers wil';
      expect(assistantNeedsSpoilerScope(typed), isTrue);
      expect(assistantNeedsSpoilerScope('Geef een sam\u00ADenvatting van seizoen 3 van Dark'), isTrue);
      final c = make(remember('Iets anders'));
      await c.submit(typed, typed: true);

      expect(model.calls, 0);
      expect(c.answer, t.assistant.memory.storyAsk);
      expect(await profile.values(), isEmpty);
    });

    test('a no on the card stores nothing', () async {
      final c = make(const []);
      await c.submit('Onthoud dat ik geen spoilers wil', typed: true);
      await c.answerMemoryProposal(c.memoryProposal!, accept: false);

      expect(await profile.values(), isEmpty);
      expect(c.memoryProposal, isNull);
      expect(model.calls, 0);
    });

    for (final typed in _leaks) {
      test('"$typed" gets no model call and no story', () async {
        final c = make([say('Jonas is de reiziger en hij sterft.'), say('Nog meer verhaal.')]);
        await c.submit(typed, typed: true);

        expect(model.calls, 0);
        expect(c.answer, t.assistant.memory.storyAsk);
        expect(c.displays, isEmpty);
        expect(await profile.values(), isEmpty);
        expect(c.memoryProposal!.value, assistantMemoryTypedFact(typed));
      });
    }

    test('typed words that are no fact give the line alone', () async {
      for (final typed in [
        'Onthoud dat spoilers',
        'Remember: the plot',
        'Onthoud dat mijn dochter 8 jaar is. Recap Dark',
      ]) {
        final c = make(const []);
        await c.submit(typed, typed: true);

        expect(model.calls, 0, reason: typed);
        expect(c.answer, t.assistant.memory.storyOnly, reason: typed);
        expect(c.memoryProposal, isNull, reason: typed);
        expect(await profile.values(), isEmpty, reason: typed);
      }
    });

    test('the command form lifts the fence for none of the forms, and a fenced one reaches no model', () async {
      for (final form in _forms) {
        final rest = form.replaceFirst(
          RegExp(r'^(onthoud dat |onthoud: |remember that |remember: )', caseSensitive: false),
          '',
        );
        final fenced = assistantNeedsSpoilerScope(form);
        expect(fenced, assistantNeedsSpoilerScope(rest), reason: form);
        if (!fenced) continue;
        final c = make([
          callTool('remember_fact', {'value': 'Kijkt Dark', 'category': 'habit'}),
          say('Verhaal.'),
        ]);
        await c.submit(form, typed: true);
        expect(model.calls, 0, reason: form);
        expect(await profile.values(), isEmpty, reason: form);
        expect([t.assistant.memory.storyAsk, t.assistant.memory.storyOnly], contains(c.answer), reason: form);
      }
    });

    test('a question mark is a question: it runs fenced, without the memory tools', () async {
      final c = make([
        callTool('remember_fact', {'value': 'Kijkt Dark', 'category': 'habit'}),
        say('Ok.'),
      ]);
      await c.submit('Remember that scene in the story of Dark?', typed: true);

      expect(model.offered.first, isNot(contains('remember_fact')));
      expect(await profile.values(), isEmpty);
      expect(c.memoryProposal, isNull);
    });

    test('a prompt the user did not type keeps the fenced run and stores nothing', () async {
      final c = make([
        callTool('remember_fact', {'value': 'Wil geen spoilers', 'category': 'preference'}),
        say('Ok.'),
      ]);
      await c.submit('Onthoud dat ik geen spoilers wil');

      expect(model.offered.first, isNot(contains('remember_fact')));
      expect(await profile.values(), isEmpty);
      expect(c.memoryProposal, isNull);
    });

    test('with the memory off nothing is offered', () async {
      await profile.service.setEnabled(false);
      final c = make([say('Ok.')]);
      await c.submit('Onthoud dat ik geen spoilers wil', typed: true);

      expect(c.memoryProposal, isNull);
      expect(c.answer, isNot(t.assistant.memory.storyAsk));
      expect(await profile.values(), isEmpty);
    });

    test('a children\'s profile gets no card', () async {
      profile.kids = true;
      final c = make([say('Ok.')]);
      await c.submit('Onthoud dat ik geen spoilers wil', typed: true);

      expect(c.memoryProposal, isNull);
      expect(await profile.values(), isEmpty);
    });
  });

  test(
    'a typed "onthoud dat" on a children\'s profile gets Pleya\'s own refusal, not the model\'s promise (BP-11h)',
    () async {
      profile.kids = true;
      final c = make([say('Leuk, dat onthoud ik.')]);
      await c.submit('Onthoud dat ik van Frozen hou', typed: true);

      expect(c.answer, t.assistant.memory.kids);
      expect(await profile.values(), isEmpty);
    },
  );

  test(
    'the polite form on a children\'s profile gets the same refusal, and a plain question does not (BP-11h)',
    () async {
      profile.kids = true;
      final polite = make([say('Natuurlijk, dat onthoud ik.')]);
      await polite.submit('Wil je onthouden dat ik van Frozen hou', typed: true);
      expect(polite.answer, t.assistant.memory.kids);

      final question = make([say('Frozen is een Disney-film.')]);
      await question.submit('Wat weet je over Frozen?', typed: true);
      expect(question.answer, 'Frozen is een Disney-film.');
    },
  );

  group('the field of the memory screen answers the same way', () {
    for (final (typed, stored) in _innocent) {
      test('"$typed": no model call, the line, the card, a yes stores the typed words', () async {
        final h = host(remember('Iets anders'));
        await h.ask(typed);

        expect(model.calls, 0);
        expect(h.answer, t.assistant.memory.storyAsk);
        expect(h.failure, isNull);
        expect(await profile.values(), isEmpty);
        expect(h.proposal!.value, stored);

        await h.answerProposal(h.proposal!, accept: true);
        expect(await profile.values(), [stored]);
        expect(h.answer, endsWith('Onthouden: $stored.'));
        expect(h.overviewStale, isTrue);
        expect(model.calls, 0);
      });
    }

    test('the story questions behind the command form reach no model either', () async {
      for (final typed in _leaks) {
        final h = host([say('Jonas is de reiziger en hij sterft.')]);
        await h.ask(typed);
        expect(model.calls, 0, reason: typed);
        expect(h.answer, t.assistant.memory.storyAsk, reason: typed);
        expect(await profile.values(), isEmpty, reason: typed);
      }
    });

    test('a follow-up the model wrote is no typed request: it goes to the model, with a card at most', () async {
      final h = host(remember('Wil geen spoilers'));
      await h.askFollowUp('Onthoud dat ik geen spoilers wil');

      expect(model.calls, greaterThan(0));
      expect(await profile.values(), isEmpty);
      expect(h.answer, isNot(t.assistant.memory.storyAsk));
    });
  });
}
