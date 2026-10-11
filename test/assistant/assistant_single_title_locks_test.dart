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

    test('I1: a question for films of that sort', () async {
      await keepsAll('that kind of movie with tom hanks', 'Then «Cast Away» (2000) is one for you.');
      await keepsAll("i'm looking for that kind of movie with tom hanks", 'Then «Cast Away» (2000) is one for you.');
      await keepsAll('ik zoek dat soort film met tom hanks', 'Dan is «Cast Away» (2000) iets voor jou.');
    });

    test('M1: a second question behind the description, no comma', () async {
      await keepsAll('die film met tom hanks over speelgoed hoeveel zijn er daarvan', 'Van «$toy» heb je er twee.');
      await keepsAll('die film met tom hanks wat heeft hij gemaakt', 'Onder andere «Cast Away» (2000).');
    });
  });

  group('lock two shut: the question fits, the answer points at more', () {
    test('an answer that points at several titles keeps every card', () async {
      for (final answer in [
        'Dat is «$mile» (1999). Ik heb zijn andere werk erbij gezet.',
        'Hij speelt in meerdere; «Cast Away» (2000) springt eruit.',
        'Dat is «$toy» (1995). De vervolgen staan erbij.',
        'Bij «$mile» (1999) passen de films hieronder.',
        'Hier zijn ze: «$mile» (1999) voorop.',
        'Dit zijn de films, «$mile» (1999) voorop.',
        'Kijk eens naar deze, te beginnen met «$mile» (1999).',
        'Bijvoorbeeld «Cast Away».',
        'Een film zoals «Cast Away» (2000).',
        'Je hebt ze allebei, «$toy» (1995) voorop.',
        'That is «$mile» (1999). The others are below.',
        'That is «$toy» (1995), the sequels are there too.',
        'Here they are, starting with «$mile» (1999).',
        'These are his films, «$mile» (1999) first.',
        'For example «Cast Away» (2000).',
        'You have both, «$toy» (1995) first.',
      ]) {
        final r = await singleAsk([findHanks, answer], one);
        expect(cardsOf(r), all, reason: answer);
      }
    });

    // M3: words that an answer about one title simply uses ("ook", "nog",
    // "meer", "deel", "also", "more", "part") do not shut the lock.
    test('the owner\'s question with an ordinary answer about one title: one card', () async {
      for (final answer in [
        'Dat is «$mile» (1999).',
        'Je bedoelt «$mile» (1999), met Tom Hanks als bewaker in een dodencel.',
        'Dat is «$mile» (1999). Hij staat ook in je bibliotheek. Wil je nog iets weten?',
        'Dat is «$mile» (1999). Wil je er meer over weten?',
        'Dat is «$mile» (1999), met naast Tom Hanks ook Michael Clarke Duncan als deel van het verhaal.',
        "That is «$mile» (1999). It's also in your library, he plays the part of a guard. Want to know more?",
      ]) {
        final r = await singleAsk([findHanks, answer], 'die film met tom hanks over deathrow');
        expect(cardsOf(r), [mile], reason: answer);
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
      expect(assistantAnswerPointsAtMore('Dat is «Hier zijn ze» (2020).'), isFalse);
    });
  });
}
