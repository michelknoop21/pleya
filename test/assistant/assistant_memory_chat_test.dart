import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/multi_server_manager.dart';

import '../services/memory/memory_test_support.dart';
import 'assistant_memory_support.dart';

/// The memory in the conversation: what is stored at once, what waits for a
/// yes on the card, and what never happens without one.
void main() {
  late AppDatabase db;
  late MultiServerManager servers;
  late MemoryProfile profile;
  late ScriptedModel model;

  AssistantController make(List<Object> script, {MemoryProfile? as, List<AssistantTool>? tools}) {
    model = ScriptedModel(script);
    final who = as ?? profile;
    final c = AssistantController(
      buildContext: (_) => who.context(servers),
      rolloutEnabled: true,
      entitlement: const Entitled(),
      loadConfig: () async => memoryConfig,
      modelFor: (_) => model,
      languageName: () => 'Dutch',
      tools: tools ?? [pingTool, ...assistantMemoryTools],
    );
    addTearDown(c.dispose);
    return c;
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

  const horror = {'value': 'Houdt niet van horror', 'category': 'dislike'};
  const friday = {'value': 'Kijkt op vrijdagavond met het gezin', 'category': 'household'};

  group('a proposal', () {
    test('without a yes stores nothing: the card waits under the answer', () async {
      final c = make([callTool('remember_fact', horror), say('Drie spannende titels zonder horror.')]);
      await c.submit('Iets spannends voor vanavond, maar geen horror, daar houd ik niet van.');

      expect(c.answer, 'Drie spannende titels zonder horror.');
      final card = c.memoryProposal!;
      expect(card.kind, AssistantMemoryProposalKind.remember);
      expect(card.value, 'Houdt niet van horror');
      expect(card.category, MemoryCategory.dislike);
      expect(model.toolOutputs.single['status'], 'proposed');
      expect(await profile.values(), isEmpty);
      expect(c.memoryStored, isFalse);
    });

    test('answered with no stores nothing and takes the card away', () async {
      final c = make([callTool('remember_fact', horror), say('Klaar.')]);
      await c.submit('Iets spannends, maar geen horror.');
      await c.answerMemoryProposal(c.memoryProposal!, accept: false);

      expect(c.memoryProposal, isNull);
      expect(c.memoryOutcome, isNull);
      expect(await profile.values(), isEmpty);
    });

    test('left behind by a new question stores nothing', () async {
      final c = make([callTool('remember_fact', horror), say('Klaar.'), say('Iets anders.')]);
      await c.submit('Iets spannends, maar geen horror.');
      final card = c.memoryProposal!;
      await c.submit('En wat is er nieuw?');

      expect(c.memoryProposal, isNull);
      // The old card answers nothing any more.
      await c.answerMemoryProposal(card, accept: true);
      expect(await profile.values(), isEmpty);
    });

    test('answered with yes stores the sentence of the card, once', () async {
      final c = make([callTool('remember_fact', horror), say('Klaar.')]);
      await c.submit('Iets spannends, maar geen horror.');
      final card = c.memoryProposal!;
      await c.answerMemoryProposal(card, accept: true);
      await c.answerMemoryProposal(card, accept: true);

      final facts = await profile.service.list();
      expect([for (final f in facts) f.value], ['Houdt niet van horror']);
      expect(facts.single.source, MemorySource.assistantConfirmed);
      expect(facts.single.category, MemoryCategory.dislike);
      expect(c.memoryOutcome!.ok, isTrue);
      expect(c.memoryStored, isTrue);
      expect(c.memoryProposal, isNull);
      expect(c.answer, 'Klaar.\nOnthouden: Houdt niet van horror.', reason: 'Pleya says literally what was stored');
    });

    test('is not shown twice for the same sentence, and at most three wait', () async {
      final c = make([
        callTools([
          ('remember_fact', horror),
          ('remember_fact', horror),
          ('remember_fact', {'value': 'Houdt van komedies', 'category': 'preference'}),
          ('remember_fact', {'value': 'Kijkt graag documentaires', 'category': 'preference'}),
        ]),
        callTool('remember_fact', {'value': 'Kijkt vaak in het weekend', 'category': 'habit'}),
        say('Klaar.'),
      ]);
      await c.submit('Geen horror, wel komedies en documentaires, meestal in het weekend.');

      expect(model.toolOutputs.last, {'error': 'too_many_proposals'});
      expect(await profile.values(), isEmpty);
      await c.answerMemoryProposal(c.memoryProposal!, accept: false);
      await c.answerMemoryProposal(c.memoryProposal!, accept: false);
      await c.answerMemoryProposal(c.memoryProposal!, accept: false);
      expect(c.memoryProposal, isNull);
    });
  });

  group('"onthoud dat"', () {
    test('stores a new fact at once and exactly once, and Pleya says literally what', () async {
      final c = make([callTool('remember_fact', friday), say('Ik heb het genoteerd.')]);
      await c.submit('Onthoud dat we op vrijdagavond met het gezin kijken', typed: true);

      final facts = await profile.service.list();
      expect([for (final f in facts) f.value], ['Kijkt op vrijdagavond met het gezin']);
      expect(facts.single.source, MemorySource.userExplicit);
      expect(c.answer, 'Onthouden: Kijkt op vrijdagavond met het gezin.');
      expect(c.memoryProposal, isNull);
      expect(c.memoryStored, isTrue);
      expect(c.resultIsError, isFalse);
    });

    test('a second write in the same turn becomes a proposal', () async {
      final c = make([
        callTools([('remember_fact', friday), ('remember_fact', horror)]),
        callTool('remember_fact', {'value': 'Houdt van komedies', 'category': 'preference'}),
        say('Klaar.'),
      ]);
      await c.submit('Onthoud dat we op vrijdag met het gezin kijken en dat ik geen horror wil.', typed: true);

      // Two claims in one sentence: the first call stores the typed words, not one half of them.
      const typed = 'We op vrijdag met het gezin kijken en dat ik geen horror wil';
      expect(await profile.values(), [typed]);
      expect(c.memoryProposal!.value, 'Houdt niet van horror');
      await c.answerMemoryProposal(c.memoryProposal!, accept: false);
      expect(c.memoryProposal!.value, 'Houdt van komedies');
      expect(await profile.values(), [typed]);
    });

    test('"onthoud:" and "remember that" count too', () async {
      for (final (prompt, value, stored) in [
        ('Onthoud: ik houd niet van horror.', 'Houdt niet van horror', 'Houdt niet van horror'),
        // "do" and "does" are no one verb to the code: the typed words are stored.
        ('Remember that I do not like horror.', 'Does not like horror', 'I do not like horror'),
        ('Remember: we watch on Fridays', 'Watches on Fridays', 'Watches on Fridays'),
      ]) {
        final c = make([
          callTool('remember_fact', {'value': value, 'category': 'dislike'}),
          say('Ok.'),
        ]);
        await c.submit(prompt, typed: true);
        expect(await profile.values(), [stored], reason: prompt);
        await profile.service.clearAll();
      }
    });

    test('with replaces never replaces without a yes', () async {
      final old = await profile.store('Kijkt op vrijdagavond met het gezin', category: MemoryCategory.household);
      final c = make([
        callTool('remember_fact', {
          'value': 'Kijkt op zaterdagavond met het gezin',
          'category': 'household',
          'replaces': old.ref,
        }),
        say('Ik stel voor dit te vervangen.'),
      ]);
      await c.submit('Onthoud dat we tegenwoordig op zaterdag met het gezin kijken', typed: true);

      expect(await profile.values(), ['Kijkt op vrijdagavond met het gezin']);
      final card = c.memoryProposal!;
      expect(card.kind, AssistantMemoryProposalKind.replace);
      expect(card.target!.value, 'Kijkt op vrijdagavond met het gezin');
      expect(card.value, 'Kijkt op zaterdagavond met het gezin');
      expect(c.answer, 'Ik stel voor dit te vervangen.');

      await c.answerMemoryProposal(card, accept: true);
      final facts = await profile.service.list();
      expect([for (final f in facts) f.value], ['Kijkt op zaterdagavond met het gezin']);
      expect(facts.single.id, old.id, reason: 'an update of the same row, not a second one');
    });

    test('is not recognised in a title, a question or further on in the sentence', () async {
      for (final prompt in [
        'Zoek Remember the Titans',
        'Remember that film with the heist?',
        'Kun je onthouden dat ik geen horror wil?',
        'Ik wil geen horror, onthoud dat even.',
        'Onthoud dat ik geen horror wil. Wat is er vanavond?',
      ]) {
        final c = make([callTool('remember_fact', horror), say('Ok.')]);
        await c.submit(prompt, typed: true);
        expect(await profile.values(), isEmpty, reason: prompt);
        expect(c.memoryProposal, isNotNull, reason: prompt);
      }
    });

    test('in a task the model cut off the question stores nothing at once', () async {
      final c = make([
        callTool('split_tasks', {
          'tasks': [
            {'title': 'Onthouden', 'intent': 'command', 'prompt': 'Onthoud dat ik geen horror wil'},
            {'title': 'Zoeken', 'intent': 'command', 'prompt': 'Zoek een komedie'},
          ],
        }),
        callTool('remember_fact', horror),
        say('Ok.'),
        say('Ok.'),
      ]);
      await c.submit('Doe twee dingen voor me vanavond', typed: true);

      expect(await profile.values(), isEmpty);
    });
  });

  group('forgetting and replacing', () {
    test('forget never removes without a yes, and removes with one', () async {
      final fact = await profile.store('Houdt niet van horror', category: MemoryCategory.dislike);
      final c = make([
        callTool('forget_fact', {'ref': fact.ref}),
        say('Ik stel voor dit te vergeten.'),
      ]);
      await c.submit('Onthoud dat je mijn afkeer van horror mag vergeten', typed: true);

      expect(await profile.values(), ['Houdt niet van horror']);
      final card = c.memoryProposal!;
      expect(card.kind, AssistantMemoryProposalKind.forget);
      expect(card.target!.id, fact.id);

      await c.answerMemoryProposal(card, accept: true);
      expect(await profile.values(), isEmpty);
      expect(c.memoryOutcome!.kind, AssistantMemoryProposalKind.forget);
      expect(c.memoryOutcome!.fact!.value, 'Houdt niet van horror');
      expect(c.memoryStored, isFalse);
      expect(c.answer, endsWith('Vergeten: Houdt niet van horror.'));
    });

    test('replaces replaces only after a yes, without "onthoud dat" as well', () async {
      final old = await profile.store('Kijkt op vrijdagavond met het gezin');
      final c = make([
        callTool('remember_fact', {'value': 'Kijkt op zaterdagavond', 'category': 'habit', 'replaces': old.ref}),
        say('Ok.'),
      ]);
      await c.submit('We kijken tegenwoordig op zaterdag.');
      expect(await profile.values(), ['Kijkt op vrijdagavond met het gezin']);

      await c.answerMemoryProposal(c.memoryProposal!, accept: true);
      final facts = await profile.service.list();
      expect(facts.single.value, 'Kijkt op zaterdagavond');
      expect(facts.single.category, MemoryCategory.habit);
      expect(c.memoryOutcome!.ok, isTrue);
    });

    test('an unknown reference changes nothing and proposes nothing', () async {
      await profile.store('Houdt niet van horror');
      final c = make([
        callTools([
          ('forget_fact', {'ref': 'deadbeef'}),
          ('remember_fact', {'value': 'Houdt van horror', 'category': 'preference', 'replaces': 'deadbeef'}),
          ('forget_fact', {'ref': 'not a ref'}),
        ]),
        say('Welke bedoel je?'),
      ]);
      await c.submit('Vergeet die ene.');

      expect(model.toolOutputs, everyElement({'error': 'unknown_ref'}));
      expect(await profile.values(), ['Houdt niet van horror']);
      expect(c.memoryProposal, isNull);
      expect(c.resultIsError, isFalse, reason: 'the model asks which one; no failed task');
    });

    test('an ambiguous reference changes nothing and proposes nothing', () async {
      var n = 0;
      final twins = MemoryProfile(db, 'profile-twins', newId: () => 'aaaaaaaa-000${n++}');
      await twins.store('Houdt niet van horror');
      await twins.store('Houdt van komedies');
      final c = make([
        callTools([
          ('forget_fact', {'ref': 'aaaaaaaa'}),
          ('remember_fact', {'value': 'Kijkt graag thrillers', 'category': 'preference', 'replaces': 'aaaaaaaa'}),
        ]),
        say('Welke bedoel je?'),
      ], as: twins);
      await c.submit('Vergeet die ene.');

      expect(model.toolOutputs, everyElement({'error': 'ambiguous_ref'}));
      expect(await twins.values(), unorderedEquals(['Houdt niet van horror', 'Houdt van komedies']));
      expect(c.memoryProposal, isNull);
    });

    test('a replacement that is the sentence of another fact is refused as duplicate', () async {
      final old = await profile.store('Kijkt op vrijdagavond');
      await profile.store('Houdt niet van horror');
      final c = make([
        callTool('remember_fact', {'value': 'houdt niet van horror!', 'category': 'dislike', 'replaces': old.ref}),
        say('Dat staat er al.'),
      ]);
      await c.submit('Vervang vrijdag door geen horror.');

      expect(model.toolOutputs.single, {'error': 'duplicate'});
      expect(c.memoryProposal, isNull);
    });

    test('what the settings own is refused with a fixed code and never proposed', () async {
      final c = make([
        callTools([
          ('remember_fact', {'value': 'Mijn dochter is 8 jaar', 'category': 'household'}),
          ('remember_fact', {'value': 'Kijkt met Nederlandse ondertitels', 'category': 'preference'}),
        ]),
        say('Dat stel je in bij Kinderprofiel en Taal.'),
      ]);
      await c.submit('Onthoud dat mijn dochter 8 is en dat ik Nederlandse ondertitels wil');

      expect(model.toolOutputs, [
        {'error': 'owned_by_kids_ages_setting'},
        {'error': 'owned_by_language_setting'},
      ]);
      expect(await profile.values(), isEmpty);
      expect(c.memoryProposal, isNull);
      expect(c.resultIsError, isFalse);
    });
  });

  group('the profile', () {
    test('switched between the proposal and the yes: nothing is stored', () async {
      final c = make([callTool('remember_fact', horror), say('Klaar.')]);
      await c.submit('Iets spannends, maar geen horror.');
      final card = c.memoryProposal!;
      profile.active = 'profile-b';
      await c.answerMemoryProposal(card, accept: true);

      expect(await profile.values(), isEmpty);
      expect(c.memoryOutcome!.code, 'profile_changed');
      expect(c.memoryStored, isFalse);
      expect(c.answer, endsWith(t.assistant.memory.profileChanged));
    });

    test('switched between the proposal and the yes: nothing is replaced or forgotten', () async {
      final fact = await profile.store('Houdt niet van horror');
      final other = await profile.store('Kijkt op vrijdag');
      final c = make([
        callTools([
          ('forget_fact', {'ref': fact.ref}),
          ('remember_fact', {'value': 'Kijkt op zaterdag', 'category': 'habit', 'replaces': other.ref}),
        ]),
        say('Klaar.'),
      ]);
      await c.submit('Wijzig mijn herinneringen over horror en vrijdag.');
      profile.active = 'profile-b';
      await c.answerMemoryProposal(c.memoryProposal!, accept: true);
      await c.answerMemoryProposal(c.memoryProposal!, accept: true);

      expect(await profile.values(), unorderedEquals(['Houdt niet van horror', 'Kijkt op vrijdag']));
    });

    test('switched during the ask: the tools read and write nothing', () async {
      await profile.store('Houdt niet van horror');
      final c = make([
        callTools([('recall_memory', {}), ('remember_fact', friday)]),
        say('Klaar.'),
      ]);
      profile.active = 'profile-b';
      await c.submit('Onthoud dat we op vrijdag kijken', typed: true);

      expect(model.offeredTo(0), ['ping'], reason: 'the memory of a profile that is not active is not offered');
      expect(await profile.values(), ['Houdt niet van horror']);
    });

    test('memory switched off between the proposal and the yes: nothing is stored', () async {
      final c = make([callTool('remember_fact', horror), say('Klaar.')]);
      await c.submit('Iets spannends, maar geen horror.');
      await profile.service.setEnabled(false);
      await c.answerMemoryProposal(c.memoryProposal!, accept: true);

      expect(await profile.values(), isEmpty);
      expect(c.memoryOutcome!.code, 'memory_off');
    });
  });
}
