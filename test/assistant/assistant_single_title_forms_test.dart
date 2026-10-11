import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_single_title.dart';

// Which questions are after one title. The gate is a closed form: a pointer,
// a kind word, a describing word and the description, with nothing in it that
// can bring in a second thing. A form the gate misses only keeps the old
// behaviour (every card of the search); a form it wrongly takes can cost a
// right card. So everything doubtful is expected to be false here.

void expectGate(Map<String, bool> forms) =>
    forms.forEach((prompt, one) => expect(assistantAsksOneTitle(prompt), one, reason: prompt));

void main() {
  test('the owner\'s question and its nearest forms are after one title', () {
    for (final prompt in [
      'die film met tom hanks over deathrow',
      'Die film met Tom Hanks over deathrow?',
      'hoe heet die film met tom hanks over de dodencel',
      'hoe heet die film met tom hanks over de dodencel ook alweer?',
      "what's that movie with tom hanks about death row",
      'what’s that movie with tom hanks about death row called?',
      'die serie over draken',
      'that show about a chemistry teacher',
      'welke film gaat over een dodencel',
      'which movie is about death row',
      'ik zoek die film met tom hanks over deathrow',
      'Hoe heet die film over een bankoverval?',
      'Hoe heet die film met Tom Hanks over speelgoed?',
      "i'm looking for that movie with tom hanks about death row",
      'do you know that series about dragons',
      'the one with tom hanks on death row',
      'that movie about the end of the world',
      'what was that movie about death row again',
      'wat was die film waarin tom hanks bewaker is',
    ]) {
      expect(assistantAsksOneTitle(prompt), isTrue, reason: prompt);
    }
  });

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
      // A second question in the same sentence (first review, I2).
      'Hoe heet die film met Tom Hanks over death row en wat is er nieuw deze week',
    ]) {
      expect(assistantAsksOneTitle(prompt), isFalse, reason: prompt);
    }
  });

  test('the search forms of the first review, each with what it is expected to be', () {
    const forms = <String, bool>{
      // Dutch, inside the closed form.
      'ik zoek die film met tom hanks over deathrow': true,
      'hoe heet die film met tom hanks': true,
      'wat is de naam van die serie waarin een leraar drugs maakt': true,
      'ken je die film waar tom hanks bewaker is': true,
      'die tom hanks film over de dodencel': true,
      'ik bedoel die ene met tom hanks in de gevangenis': true,
      'die tv-serie over een scheikundeleraar': true,
      'die anime over titanen': true,
      'dat programma over bakken': true,
      'Welke serie gaat over een scheikundeleraar?': true,
      'Die ene docu over octopussen': true,
      // Dutch, one title asked but outside the closed form: every card stays.
      'welke film is dat met tom hanks': false,
      'ik zoek een film met Tom Hanks in een dodencel': false,
      'welke tom hanks film gaat over de dodencel': false,
      'weet je welke ik bedoel, met tom hanks en die grote gevangene': false,
      'dat ding met tom hanks en de dodencel': false,
      'Ik weet niet meer hoe de film met Tom Hanks in de gevangenis heet': false,
      'de film van Tom Hanks over de dodencel': false,
      'Welke film met Tom Hanks speelt in een dodencel?': false,
      'Een film met Tom Hanks in een dodencel, hoe heet die?': false,
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
      // English, inside the closed form.
      "what's that movie with tom hanks on death row": true,
      'the one where tom hanks is a prison guard': true,
      'that tom hanks movie about death row': true,
      // English, one title asked but outside the closed form.
      'which tom hanks movie is about death row': false,
      'what was that tom hanks film called': false,
      'the tom hanks one about death row': false,
      'looking for a movie with tom hanks on death row': false,
      'Which film has Tom Hanks as a prison guard?': false,
      'I am looking for the movie with Tom Hanks on death row': false,
      'the show about a chemistry teacher': false,
      'What was the name of that Tom Hanks prison thing?': false,
      // Four words before the kind word and no description after it.
      'that tom hanks death row movie': false,
      // No pointer: reads as a search for films of that sort.
      'movie where tom hanks is a prison guard': false,
    };
    expect(forms, hasLength(40));
    expectGate(forms);
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
      'Geef me drie opties, bijvoorbeeld die film met Tom Hanks',
      'Iets zoals die film met Tom Hanks over death row',
      'Which movies with Tom Hanks do I have?',
    ]) {
      expect(assistantAsksOneTitle(prompt), isFalse, reason: prompt);
    }
  });

  // The price of the closed form: one description with a joining word in it,
  // or "welke" with an actor, is one title to a reader and still falls
  // outside. These were inside before; whoever widens the gate for them has to
  // keep the review tables green.
  test('one description with "en" in it, or "welke film met X", falls outside on purpose', () {
    for (final prompt in [
      'die film met tom hanks en die grote zwarte gevangene in de dodencel',
      'that movie with tom hanks and the big inmate on death row',
      'die serie over een leraar en zijn oud-leerling die drugs maken',
      'welke film met tom hanks gaat over een dodencel',
      'which tom hanks movie is about death row',
      'which movie with tom hanks is about death row',
      'welke film met tom hanks is dat over de dodencel',
      // Other prices: a digit, a rank, "bij", "na", "niet", a lead-in outside the list.
      'die serie over de jaren 80',
      'die film over de eerste maanlanding',
      'die film waar hij bij de politie werkt',
      'that movie where he looks like a clown',
      'die film waar ze niet uit het huis kunnen',
      'ik vroeg bijvoorbeeld om die film met tom hanks over deathrow',
      'ik zoek 1 film, die film met tom hanks over deathrow',
      'wie speelt er in die film met tom hanks over death row',
    ]) {
      expect(assistantAsksOneTitle(prompt), isFalse, reason: prompt);
    }
  });

  // Fourth review, I1: a word for a sort between the pointer and the kind
  // word asks for films of that sort, not for one title.
  test('I1: "dat soort film", "that kind of movie" fall outside', () {
    expectGate(const {
      'that kind of movie about heists': false,
      'that type of movie with tom hanks': false,
      'this sort of show about detectives': false,
      "i'm looking for that kind of movie about heists": false,
      'do you know that kind of show about detectives': false,
      'dat soort film over overvallen': false,
      'dat type film met tom hanks': false,
      'ik zoek dat soort film over overvallen': false,
      'ken je dat soort serie over detectives': false,
      'dat slag film over overvallen': false,
      'dat typ film over overvallen': false,
      // In the description the same words describe: the gate stays open.
      'that movie about a kind giant on death row': true,
      'die film over een type dat nooit opgeeft': true,
    });
  });

  // Fourth review, M1: a second question behind the description without a
  // comma, as dictation gives it.
  test('M1: a question word or a word for the lot after the description falls outside', () {
    expectGate(const {
      'die film over speelgoed hoeveel zijn er daarvan': false,
      'die film over speelgoed de complete collectie': false,
      'that movie about toys the complete collection': false,
      'die film over death row iets dergelijks': false,
      'die film over death row wat raad je aan': false,
      'die film over death row wat kijk ik hierna': false,
      'that movie about death row what do you recommend': false,
      'that movie about death row what should i see afterwards': false,
      'die film met tom hanks wat heeft hij gemaakt': false,
      'that movie with tom hanks what has he been in': false,
      'die film met tom hanks etc': false,
      'die film met tom hanks etc.': false,
      'die film met tom hanks enzo': false,
      'die film met tom hanks enzovoort': false,
      'die film over de dodencel wie speelt daarin': false,
      'die film met tom hanks hoe lang duurt die': false,
      'die film met tom hanks waarom is die zo bekend': false,
      'die film met tom hanks wanneer kwam die uit': false,
      'that movie about death row who directed it': false,
      'that movie about death row how long is it': false,
      'that movie about death row why is it famous': false,
      'that movie about death row when did it come out': false,
      // A question word in the lead-in, before the pointer, stays inside.
      'hoe heet die film met tom hanks over de dodencel': true,
      'wat is die film met tom hanks': true,
      "what's that movie with tom hanks about death row": true,
      // "Waar" and "where" describe ("die film waar hij ...").
      'die film waar hij bewaker is': true,
      'die film met tom hanks waar hij bewaker is': true,
      'that movie where he is a prison guard': true,
      'that movie with tom hanks where he is a guard': true,
    });
  });
}
