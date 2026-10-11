import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_single_title.dart';

// Every question the review rounds found inside the gate while it asks for
// more than one thing, for what there is, or uses the described title as the
// example or the exception. All of them are outside now.

void expectOutside(List<String> prompts) {
  for (final prompt in prompts) {
    expect(assistantAsksOneTitle(prompt), isFalse, reason: prompt);
  }
}

void main() {
  test('R1: the title and its sequels, parts or the rest; a second pointer', () {
    expectOutside(const [
      'laat die film met tom hanks zien en de vervolgen',
      'laat die film met tom hanks over speelgoed zien en de vervolgen',
      'that movie with tom hanks, and the sequels',
      'die film met tom hanks over speelgoed en deel 2',
      'die film met tom hanks over speelgoed, deel twee',
      'that show about dragons and its spin-offs',
      'that show about dragons and the prequel',
      'that movie with tom hanks plus the whole trilogy',
      'die serie over draken met de hele trilogie erbij',
      'that movie about toys, part 2',
      'die film met tom hanks over death row, en de rest van zijn werk',
      'die film met tom hanks, en wat heb je verder van hem',
      'what is the movie with tom hanks and what do you also have of him',
      'die film met tom hanks en ook iets met brad pitt',
      'die film met tom hanks en die met leonardo dicaprio',
      'that movie with tom hanks and the one with brad pitt',
      'die film met tom hanks over death row en die serie over draken',
      'that movie about death row and that show about dragons',
      'die film met tom hanks of die met brad pitt',
      'die film met tom hanks over death row of zoiets',
      'that movie with tom hanks and anything similar',
      'die film met Tom Hanks, heb je er nog meer zoals die?',
      'die film over death row en vergelijkbaar werk',
    ]);
  });

  test('R2: "welke film met X" asks which of his films, or what there is', () {
    expectOutside(const [
      'welke film met tom hanks heb ik nog niet gezien',
      'welke serie met bryan cranston heb ik',
      'welke film van tom hanks kan ik vanavond kijken',
      'welke film met tom hanks raad je aan',
      'welke film met tom hanks hebben we',
      'welke film met tom hanks staat erop',
      'which movie with tom hanks should i watch tonight',
      'which film with tom hanks is the best',
      'which movie with tom hanks do i have',
      "which tom hanks movie haven't i seen",
      "which movie by spielberg haven't seen yet",
      'which movie with tom hanks can i watch',
      'what movie with tom hanks is there',
      'welke film met tom hanks is het leukst',
      'welke films met Tom Hanks heb ik',
      'die serie waar iedereen over praat en wat nog meer',
      'heb ik die film met tom hanks en de andere delen',
      'die reeks films met tom hanks',
      'de films van die serie over draken',
    ]);
  });

  test('R3: a sequel without the known signal words', () {
    expectOutside(const [
      'die film over speelgoed en het tweede deel',
      'die film met tom hanks over speelgoed en de opvolger',
      'that movie about toys and the follow-up',
      'that movie about toys and the next one',
      'that movie about toys and the second one',
      'die film over speelgoed en de tweede',
      'die film over speelgoed en nummer twee',
      'die film over speelgoed en wat erna kwam',
      'that movie about toys and what came after',
      'die film over speelgoed en de remake',
      'that movie about toys and the remake',
      'die film over speelgoed, beide',
      'that movie about toys, both of them',
      'die film over speelgoed, de hele serie',
      'die serie over draken en de film erbij',
      'die serie over draken en de bijbehorende film',
      'laat die film met tom hanks over speelgoed zien en het tweede deel',
      'that movie with tom hanks about toys and the follow-up',
      'die film met tom hanks over speelgoed, beide',
    ]);
  });

  test('R4: "in welke film speelt X", "which movie has X"', () {
    expectOutside(const [
      'in welke film speelt tom hanks',
      'welke film heeft tom hanks gemaakt',
      'which movie has tom hanks in it',
      'which film has tom hanks',
      'what movie has brad pitt',
      'welke serie heeft bryan cranston',
    ]);
  });

  test('R5: the described title is the example or the exception', () {
    expectOutside(const [
      'een film met tom hanks maar niet die film over death row',
      'iets met tom hanks behalve die film over death row',
      'a tom hanks movie, not that movie about death row',
      'anything but that movie about death row',
      'wat past bij die film over death row',
      'wat past bij die film met tom hanks over death row',
      'what goes well with that movie about death row',
      'wat kijk ik na die film over death row',
      'what should i watch after that movie about death row',
      'die film over death row en wat erop lijkt',
      'die film met tom hanks over death row en wat erop lijkt',
      'die film over death row en iets in dezelfde sfeer',
      'that movie about death row and something in the same vein',
      'that movie about death row and stuff in that genre',
      'die film over death row en wat daarbij past',
      'iets in de trant van die film met tom hanks over death row',
    ]);
  });

  test('third review, no finding then: comparisons, persons, seasons, superlatives', () {
    expectOutside(const [
      'is die film met tom hanks over death row beter dan forrest gump',
      'wat is beter, die film over death row of forrest gump',
      'that movie about death row or shawshank',
      'die film met tom hanks over death row en forrest gump',
      'die film met tom hanks over death row en eentje met brad pitt',
      'die film met tom hanks over death row en nog een met brad pitt',
      'die film met tom hanks over death row en dan nog die met brad pitt',
      'the series about dragons and the series about vikings',
      'die film over death row, en daarnaast die over de gevangenisontsnapping',
      'eerst die film over death row, daarna die over de ontsnapping',
      'that movie about death row, then the one about the escape',
      'heb ik die film met tom hanks over death row en forrest gump',
      'staat die film over death row erop en de serie',
      'die film met tom hanks over death row en nog twee',
      'wat heeft de regisseur van die film met tom hanks over death row nog gemaakt',
      'waar ken ik die acteur uit die film over death row van',
      'waar speelt de hoofdrolspeler van die serie over draken nog in',
      'seizoen 2 van die serie over draken',
      'welk seizoen van die serie over draken is het beste',
      'de laatste aflevering van die serie over draken',
      'elke aflevering van die serie over draken',
      'het eerste seizoen van die serie over draken en het tweede',
      'welke aflevering van friends gaat over thanksgiving',
      'which episode is the one where ross gets married',
      'en van die film over death row?',
      'welke film is het langst',
      'welke film heeft de hoogste score',
      'which movie has the best rating',
      'welke film is het meest gekeken',
      'welke film was dat die ik gisteren keek',
      'de film die ik gisteren keek',
      'de serie die ik aan het kijken was',
      'de film van vanavond',
      'geef me drie keer die film met tom hanks',
    ]);
  });

  test('third review, outside already: plurals, the rest, follow-up questions', () {
    expectOutside(const [
      'die documentaires over de oceaan',
      'those documentaries about the ocean',
      'die drie series over draken',
      'die series over draken',
      'die twee films met tom hanks',
      'die films met tom hanks',
      "die programma's over koken",
      'those cartoons about dragons',
      'die dingen met tom hanks',
      'that movie or the other one',
      'the whole series of that movie about toys',
      'what did the director of that movie about death row make',
      'what has the lead of that show about dragons been in',
      'every episode of that show',
      'which series with bryan cranston do i have',
      'en daarna?',
      'en die met brad pitt?',
      'and that one about the escape?',
      'en welke nog?',
      'welke film is nieuw',
      'which movie is the newest',
      'welke film is er vandaag bijgekomen',
      'de film van tom hanks',
    ]);
  });

  // Written against the closed form itself: each fits pointer, kind word and
  // describing word, and brings the second thing in without a comma or "en".
  test('attacks on the closed form: several, compared, referred to, a sequel', () {
    const attacks = [
      'die film over speelgoed de hele reeks',
      'die film over speelgoed het tweede deel',
      'die film over speelgoed beide',
      'die film over speelgoed met de opvolger erbij',
      'die film met tom hanks over speelgoed samen met de vervolgen',
      'die film over death row in dezelfde sfeer',
      'die film over death row naast forrest gump',
      'die film over death row tegenover forrest gump',
      'die film over death row in plaats van forrest gump',
      'die film over death row gevolgd door forrest gump',
      'die twee films over draken',
      'die andere film over death row',
      'die film over death row die erop lijkt',
      'die serie over draken waar de film bij hoort',
      'welke film gaat over death row of over een ontsnapping',
      'welke film gaat over draken naast shrek',
      'hoe heet die film over speelgoed en hoe heet de opvolger',
      'die film met tom hanks over death row daarna forrest gump',
      'die film over speelgoed inclusief de rest',
      'die ene met tom hanks alle drie',
      'die nieuwe film over draken',
      'that movie about toys the whole trilogy',
      'that movie about toys both of them',
      'that movie about toys the follow-up',
      'that movie about death row versus shawshank',
      'that movie about death row as well as shawshank',
      'that movie about death row followed by the next',
      'that other movie about death row',
      'which movie is about death row besides the green mile',
      'which movie is about dragons or about vikings',
      'the one with tom hanks alongside forrest gump',
      'that movie with tom hanks about toys including the sequels',
      'this show about dragons compared to the one about vikings',
      'that movie about death row something in the same vein',
      "what's that movie about toys and its sequel called",
      'that movie about toys\nand the rest',
    ];
    expect(attacks.length, greaterThanOrEqualTo(30));
    expectOutside(attacks);
  });
}
