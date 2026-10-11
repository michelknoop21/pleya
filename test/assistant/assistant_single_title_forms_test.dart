import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_single_title.dart';

// Which questions are after one title. A form the gate misses only keeps the
// old behaviour (every card of the search); a form it wrongly takes can cost
// a right card. So everything doubtful is expected to be false here.

void main() {
  test('a title that is only referred to, or a question for more, is not a search for one title', () {
    for (final prompt in [
      'Wat heeft de regisseur van de film Heat nog meer gemaakt?',
      'Wie is de regisseur van de film Heat?',
      'Hoe heet de regisseur van de film Heat?',
      'Hoe heet de regisseur van die film met Tom Hanks over death row?',
      'Welke afleveringen van de serie Friends heb ik nog niet gezien?',
      'Laat alles zien met de acteurs uit de film Heat',
      'Wat kan ik kijken na de serie Breaking Bad?',
      'Meer van de maker van die serie',
      'Wat heb ik allemaal van de serie Star Trek?',
      'Alles van de serie Star Trek',
      'Laat alle resultaten zien voor de film met tom hanks',
      'Ik zoek die film met Tom Hanks, geef me alles wat je vindt',
      'Welke seizoenen van die serie met de scheikundeleraar heb ik?',
      'Die film met Tom Hanks over death row, en wat heeft hij nog meer gemaakt?',
      'Een andere film met Tom Hanks dan die film over death row',
      'What else did the director of the movie Heat make?',
      'Show me everything from the show about a chemistry teacher',
      'Which episodes of the show Friends have I not seen?',
      'Other things by the maker of that show about dragons',
      'All seasons of that series about dragons',
      'Give me more of that movie with Tom Hanks',
    ]) {
      expect(assistantAsksOneTitle(prompt), isFalse, reason: prompt);
    }
  });

  test('the search forms of the review, each with what it is expected to be', () {
    const forms = <String, bool>{
      // Dutch.
      'ik zoek die film met tom hanks over deathrow': true,
      'hoe heet die film met tom hanks': true,
      'welke film is dat met tom hanks': true,
      'wat is de naam van die serie waarin een leraar drugs maakt': true,
      'ken je die film waar tom hanks bewaker is': true,
      'ik zoek een film met Tom Hanks in een dodencel': true,
      'die tom hanks film over de dodencel': true,
      'welke tom hanks film gaat over de dodencel': true,
      'ik bedoel die ene met tom hanks in de gevangenis': true,
      'weet je welke ik bedoel, met tom hanks en die grote gevangene': true,
      'dat ding met tom hanks en de dodencel': true,
      'die tv-serie over een scheikundeleraar': true,
      'die anime over titanen': true,
      'dat programma over bakken': true,
      'Ik weet niet meer hoe de film met Tom Hanks in de gevangenis heet': true,
      'de film van Tom Hanks over de dodencel': true,
      'Welke film met Tom Hanks speelt in een dodencel?': true,
      'Welke serie gaat over een scheikundeleraar?': true,
      'Die ene docu over octopussen': true,
      'Een film met Tom Hanks in een dodencel, hoe heet die?': true,
      // No pointer and no verb of searching: may as well ask for a tip.
      'een film met tom hanks over death row': false,
      'film met tom hanks over death row': false,
      // Loose keywords, no pointer: nothing says one title is meant.
      'tom hanks dodencel film': false,
      // "Iets" asks openly, several fit.
      'ik zoek iets met tom hanks in een dodencel': false,
      // An actor alone: his other films answer this as well.
      'ik zoek een film met tom hanks': false,
      // "Die met" is also how a relative clause starts ("films die met ...").
      'heb ik die met tom hanks over de dodencel': false,
      // Names the title itself: the search then finds that one title anyway.
      'staat de green mile erop': false,
      // English.
      "what's that movie with tom hanks on death row": true,
      'the one where tom hanks is a prison guard': true,
      'that tom hanks movie about death row': true,
      'which tom hanks movie is about death row': true,
      'what was that tom hanks film called': true,
      'the tom hanks one about death row': true,
      'looking for a movie with tom hanks on death row': true,
      'Which film has Tom Hanks as a prison guard?': true,
      'I am looking for the movie with Tom Hanks on death row': true,
      'the show about a chemistry teacher': true,
      'What was the name of that Tom Hanks prison thing?': true,
      // Four words before the kind word and no description after it.
      'that tom hanks death row movie': false,
      // No pointer: reads as a search for films of that sort.
      'movie where tom hanks is a prison guard': false,
    };
    expect(forms, hasLength(40));
    forms.forEach((prompt, one) => expect(assistantAsksOneTitle(prompt), one, reason: prompt));
  });

  test('questions for a list or a tip are not after one title', () {
    for (final prompt in [
      'Films met Tom Hanks',
      'Welke films met Tom Hanks heb ik?',
      'Iets spannends voor vanavond',
      'Een film met Tom Hanks',
      'Welke series zijn nieuw?',
      'What series do I have?',
      'Movies like that film with Tom Hanks',
      'Iets zoals die film met Tom Hanks',
      'Geef me twee opties voor de film van vanavond',
      'Tips voor de serie van dit weekend',
      'Wat is er deze week toegevoegd?',
    ]) {
      expect(assistantAsksOneTitle(prompt), isFalse, reason: prompt);
    }
  });
}
