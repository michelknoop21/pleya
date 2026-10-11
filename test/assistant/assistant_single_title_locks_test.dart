import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_single_title.dart';

import 'assistant_single_title_support.dart';

// The two locks in a run. Lock one: the question is one described title and
// nothing else. Lock two: the answer names one title and points at nothing
// more. With either lock shut, every card of the search stays.

void main() {
  const one = 'Hoe heet die film met Tom Hanks over death row?';
  late List<String> all;

  setUp(() async => all = cardsOf(await singleAsk([findHanks, 'Hier zijn ze.'], 'Films met Tom Hanks')));

  test('the owner\'s question, one title named: exactly one card', () async {
    final r = await singleAsk([findHanks, 'Dat is «$mile» (1999).'], 'die film met tom hanks over deathrow');
    expect(all, hasLength(5));
    expect(cardsOf(r), [mile]);
  });

  group('lock one shut: the question asks for more than the one title', () {
    Future<void> keepsAll(String prompt, String answer) async {
      expect(cardsOf(await singleAsk([findHanks, answer], prompt)), all, reason: prompt);
    }

    test('R3: the title and its sequel', () async {
      const answer = 'Dat is «$toy» (1995).';
      await keepsAll('laat die film met tom hanks over speelgoed zien en het tweede deel', answer);
      await keepsAll('die film met tom hanks over speelgoed en de opvolger', answer);
      await keepsAll('that movie with tom hanks about toys and the follow-up', answer);
      await keepsAll('die film met tom hanks over speelgoed, beide', answer);
    });

    test('R4: which film has the actor in it', () async {
      const answer = 'Je kunt «Cast Away» (2000) kiezen.';
      await keepsAll('in welke film speelt tom hanks', answer);
      await keepsAll('which movie has tom hanks in it', answer);
    });

    test('R5: the described title is the exception or the example', () async {
      await keepsAll(
        'een film met tom hanks maar niet die film over death row',
        'Wat dacht je van «Cast Away» (2000)?',
      );
      await keepsAll('wat past bij die film met tom hanks over death row', 'Je bedoelt «$mile» (1999).');
      await keepsAll('die film met tom hanks over death row en wat erop lijkt', 'Je bedoelt «$mile» (1999).');
    });

    test('a second question in the same sentence', () async {
      await keepsAll('Hoe heet die film met Tom Hanks over death row en wat is er nieuw deze week', 'Dat is «$mile».');
    });
  });

  group('lock two shut: the question fits, the answer points at more', () {
    test('a word for more in the answer keeps every card', () async {
      for (final answer in [
        'Dat is «$mile» (1999). Ik heb ook zijn andere werk gevonden.',
        'Dat is «$mile» (1999), kijk ook eens verder.',
        'Hij speelt in meerdere; «Cast Away» (2000) springt eruit.',
        'Dat is «$toy» (1995). Het tweede deel staat eronder.',
        'Bij «$mile» (1999) passen de films hieronder.',
        'That is «$mile» (1999). The others are below.',
        'That is «$mile» (1999), there is also a sequel.',
      ]) {
        final r = await singleAsk([findHanks, answer], one);
        expect(cardsOf(r), all, reason: answer);
      }
    });

    test('a list in the answer keeps every card', () async {
      for (final answer in [
        'Dat is «$mile» (1999).\n- een dodencel\n- een bewaker',
        'Dat is «$mile» (1999).\n1. een dodencel\n2. een bewaker',
      ]) {
        final r = await singleAsk([findHanks, answer], one);
        expect(cardsOf(r), all, reason: answer);
      }
    });

    test('the words of the title itself, and one list line, do not count', () async {
      expect(assistantAnswerPointsAtMore('Dat is «The Other Guys» (2010).'), isFalse);
      expect(assistantAnswerPointsAtMore('Dat is «Deel van mij».\n- uit 2020'), isFalse);
      expect(assistantAnswerPointsAtMore('Dat is «Heat» (1995), met Al Pacino in een bankoverval.'), isFalse);
      expect(assistantAnswerPointsAtMore('Dat is «Heat» (1995). Meer staat hieronder.'), isTrue);
    });
  });
}
