import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_tools.dart';

import 'assistant_single_title_support.dart';

void main() {
  const one = 'Hoe heet die film met Tom Hanks over death row?';
  const answer = 'Dat is «$mile» (1999).';

  group('one title asked, one title named', () {
    test('NL: the search brings up his other films, only the named one keeps its card', () async {
      final r = await singleAsk([findHanks, answer], one);
      expect(r.text, answer);
      expect(cardsOf(r), [mile]);
    });

    test('EN question forms narrow the same way', () async {
      for (final prompt in [
        'What is that movie with Tom Hanks about death row?',
        'Which movie is about death row?',
        "I'm looking for that movie with Tom Hanks about death row",
      ]) {
        final r = await singleAsk([findHanks, 'That is «$mile» (1999).'], prompt);
        expect(cardsOf(r), [mile], reason: prompt);
      }
    });

    test('NL question forms narrow the same way', () async {
      for (final prompt in [
        'Ik zoek die film met Tom Hanks over deathrow',
        'Welke film gaat over een dodencel?',
        'die film met tom hanks over deathrow',
      ]) {
        final r = await singleAsk([findHanks, answer], prompt);
        expect(cardsOf(r), [mile], reason: prompt);
      }
    });

    test('a grid of search results is narrowed too and keeps the facts of its title', () async {
      const facts = TitleFacts(genres: ['Drama']);
      final r = await singleAsk(
        [
          {'name': 'search_catalog', 'args': <String, Object?>{}},
          answer,
        ],
        one,
        tools: [
          displayTool(
            'search_catalog',
            (_) => AssistantMediaGrid(
              [
                for (var i = 0; i < 61; i++) (item: movieItem('Other $i', 2000), group: null),
                (item: movieItem(mile, 1999), group: null),
                (item: movieItem('Cast Away', 2000), group: null),
              ],
              facts: {AssistantMediaGrid.keyOf((item: movieItem(mile, 1999), group: null)): facts},
            ),
          ),
        ],
      );
      final grid = r.displays.single as AssistantMediaGrid;
      expect(cardsOf(r), [mile]);
      expect(grid.facts.values.single, same(facts));
    });
    test('the same title named twice, once with its year, is one title', () async {
      final r = await singleAsk([findHanks, 'Dat is «$mile» (1999). «$mile» speelt in een dodencel.'], one);
      expect(cardsOf(r), [mile]);
    });

    test('a second result in the same run stays whole: only the search with the named title narrows', () async {
      final r = await singleAsk(
        [
          findHanks,
          {'name': 'recently_added', 'args': <String, Object?>{}},
          answer,
        ],
        one,
        tools: [
          ...assistantTools.where((t) => t.name == 'find_title'),
          displayTool(
            'recently_added',
            (_) => AssistantMediaGrid([
              (item: movieItem('Heat', 1995), group: null),
              (item: movieItem('Cast Away', 2000), group: null),
            ]),
          ),
        ],
      );
      expect(r.displays, hasLength(2));
      expect(cardsOf(r), [mile, 'Heat', 'Cast Away']);
    });

    test('request options for a title outside the library narrow to the named one too', () async {
      AssistantRequestOption option(String title, int year) => AssistantRequestOption(
        seerrId: title,
        title: title,
        kind: 'movie',
        posterUrl: '',
        overview: '',
        status: 'not_requested',
        year: year,
      );
      final r = await singleAsk(
        [
          {'name': 'find_request_title', 'args': <String, Object?>{}},
          answer,
        ],
        one,
        tools: [
          displayTool(
            'find_request_title',
            (ctx) => AssistantRequestOptions(ctx, [option(mile, 1999), option(gump, 1994), option('Cast Away', 2000)]),
          ),
        ],
      );
      final options = (r.displays.single as AssistantRequestOptions).options;
      expect([for (final o in options) o.title], [mile]);
    });
  });

  group('a named title the search did not find', () {
    test('gets its own card next to the search result, which stays whole', () async {
      final before = cardsOf(await singleAsk([findHanks, 'Hier zijn ze.'], 'Films met Tom Hanks'));
      final r = await singleAsk([findHanks, 'Dat is «Heat» (1995).'], 'Hoe heet die film over een bankoverval?');
      expect(cardsOf(r), [...before, 'Heat']);
    });

    test('a list about a title that is only referred to keeps every card', () async {
      for (final text in [
        'De regisseur van «Heat» (1995) maakte ook deze drie.',
        'Hij maakte onder meer «Ali» (2001).',
      ]) {
        final r = await singleAsk(
          [
            {'name': 'search_catalog', 'args': <String, Object?>{}},
            text,
          ],
          'Wat heeft de regisseur van de film Heat nog meer gemaakt?',
          tools: [
            ...assistantTools.where((t) => t.name == 'find_title'),
            displayTool(
              'search_catalog',
              (_) => AssistantMediaGrid([
                (item: movieItem('Collateral', 2004), group: null),
                (item: movieItem('Ali', 2001), group: null),
                (item: movieItem('Thief', 1981), group: null),
              ]),
            ),
          ],
        );
        expect(cardsOf(r), containsAll(['Collateral', 'Ali', 'Thief']), reason: text);
      }
    });
  });

  group('everything else keeps its cards', () {
    test('a question for several titles keeps every card, also when the answer names one', () async {
      for (final prompt in [
        'Welke films met Tom Hanks heb ik?',
        'Films met Tom Hanks',
        'Iets spannends voor vanavond',
        'Which movies with Tom Hanks do I have?',
        'Geef me drie opties, bijvoorbeeld die film met Tom Hanks',
        'Iets zoals die film met Tom Hanks over death row',
      ]) {
        final r = await singleAsk([findHanks, answer], prompt);
        expect(cardsOf(r).length, greaterThan(1), reason: prompt);
        expect(cardsOf(r), contains(gump), reason: prompt);
      }
    });

    test('the title and its sequels: the sequel keeps its card next to the named one', () async {
      for (final prompt in [
        'Laat die film met Tom Hanks over speelgoed zien en de vervolgen',
        'Die film met Tom Hanks over speelgoed en deel 2',
      ]) {
        final r = await singleAsk([findHanks, 'Dat is «$toy» (1995). De vervolgen staan hieronder.'], prompt);
        expect(cardsOf(r), containsAll([toy, 'Toy Story 2']), reason: prompt);
      }
    });

    test('"welke film met X" for what there is keeps every card, also when one is singled out', () async {
      final before = cardsOf(await singleAsk([findHanks, 'Hier zijn ze.'], 'Films met Tom Hanks'));
      for (final prompt in [
        'Welke film met Tom Hanks heb ik nog niet gezien',
        'Welke film van Tom Hanks kan ik vanavond kijken',
        'Which movie with Tom Hanks should I watch tonight',
      ]) {
        final r = await singleAsk([
          findHanks,
          'Je hebt er meerdere niet gezien; «Cast Away» (2000) springt eruit.',
        ], prompt);
        expect(cardsOf(r), before, reason: prompt);
      }
    });

    test('an answer that names no title leaves the found titles as they are', () async {
      final before = cardsOf(await singleAsk([findHanks, 'Hier zijn ze.'], 'Films met Tom Hanks'));
      final r = await singleAsk([findHanks, 'Ik weet niet zeker welke je bedoelt.'], one);
      expect(cardsOf(r), before, reason: 'no card is picked for the user');
    });

    test('an answer that names a title outside the result keeps the result and picks none', () async {
      final before = cardsOf(await singleAsk([findHanks, 'Hier zijn ze.'], 'Films met Tom Hanks'));
      final r = await singleAsk([findHanks, 'Dat is «Philadelphia» (1993).'], one);
      expect(cardsOf(r), before);
    });

    test('a named title whose only card cannot be opened or requested narrows nothing', () async {
      final r = await singleAsk(
        [
          {'name': 'trending_titles', 'args': <String, Object?>{}},
          answer,
        ],
        one,
        tools: [
          displayTool(
            'trending_titles',
            (ctx) => AssistantTitleMatches(ctx, [titleMatch(gump, 1994), titleMatch(mile, 1999, drawn: false)]),
          ),
        ],
      );
      expect(cardsOf(r), [gump, mile]);
    });

    test('an answer that names two titles keeps every card', () async {
      final before = cardsOf(await singleAsk([findHanks, 'Hier zijn ze.'], 'Films met Tom Hanks'));
      final r = await singleAsk([findHanks, 'Dat is «$mile» (1999) of anders «$gump» (1994).'], one);
      expect(cardsOf(r), before);
    });
  });

  group('a children\'s profile', () {
    const kidsOne = 'Hoe heet die film met Tom Hanks over speelgoed?';

    test('the age gate decides first, then the one named title keeps its card', () async {
      final r = await singleAsk([findHanks, 'Dat is «$toy» (1995).'], kidsOne, ctx: singleCtx(kids: true));
      expect(cardsOf(r), [toy]);
      expect(r.ageFilterNotice, isFalse);
    });

    test('a turned-down title gets no card, also as the one named title', () async {
      final m = [findHanks, 'Dat is «$mile» (1999).', 'Toch «$mile» (1999).'];
      final r = await singleAsk(m, one, ctx: singleCtx(kids: true));
      expect(r.ageFilterNotice, isTrue);
      expect(r.text, isEmpty);
      expect(cardsOf(r), isNot(contains(mile)));
      expect(cardsOf(r), isNot(contains(gump)), reason: 'the gate still holds for the rest');
    });
  });
}
