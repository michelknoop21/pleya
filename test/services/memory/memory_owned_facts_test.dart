import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/memory/memory_models.dart';
import 'package:pleya/services/memory/memory_validation.dart';

/// The recogniser of facts the settings own: a child's age and a language
/// preference, as tables of sentences with the expected outcome.
void main() {
  group('facts that already have an owner', () {
    const ok = MemoryCode.ok;
    const age = MemoryCode.ownedKidsAges;
    const language = MemoryCode.ownedLanguage;

    void check(Map<String, MemoryCode> cases) {
      for (final MapEntry(key: value, value: expected) in cases.entries) {
        expect(checkMemoryValue(value).code, expected, reason: value);
      }
    }

    test('an outright statement of a child\'s age is refused', () {
      check({
        'Onze dochter is 8': age,
        'De kinderen zijn 6 en 9 jaar': age,
        'Mijn zoon van 12 kijkt mee': age,
        'We hebben een achtjarige dochter': age,
        'Heeft een 8-jarige zoon': age,
        'Jongste is 4 jaar oud': age,
        'My daughter is 8': age,
        'Our kids are 6 and 9 years old': age,
        'The children are aged 7 and 10': age,
        'Has an 8 year old son': age,
        'Mijn dochter is 8 en mijn zoon 5': age,
        'Mijn dochter is 8, dus geen horror': age,
        // Let through by the first recogniser, from the review.
        'Mijn dochter wordt negen': age,
        'Mijn dochter is acht': age,
        'Zoon (8) en dochter (5)': age,
        'Kinderen: 8 en 5': age,
        'Twee kinderen, 8 en 5': age,
        'Our son just turned eight': age,
        // The verb last, as the words after "onthoud dat" are typed.
        'Mijn dochter 8 jaar is': age,
        'Mijn dochter 8 jaar is. Recap Dark': age,
        'De kinderen 6 en 9 zijn': age,
        'Onze zoon al twaalf jaar oud is': age,
      });
    });

    test('a number that counts something else is not an age', () {
      check({
        // Refused by the first recogniser, from the review.
        'Kijkt met de kinderen geen films van 16 en ouder': ok,
        'Mijn zoon kijkt al 2 jaar anime': ok,
        'De kinderen zijn 3 dagen per week bij ons': ok,
        'Mijn dochter is 2 keer per week bij oma': ok,
        'Onze kinderen kijken graag films van 90 minuten': ok,
        'The kids loved 12 Years a Slave': ok,
        'Oudste film in de collectie is van 39': ok,
        // Nearby.
        'Kijkt op vrijdag met de kinderen': ok,
        'Heeft twee kinderen': ok,
        'De kinderen zijn twee keer per week bij opa': ok,
        'De kinderen zijn om 20.00 thuis': ok,
        'Kijkt films die bij de leeftijd van de kinderen passen': ok,
        'Leeftijden van de kinderen': ok,
        'Vindt films uit de jaren 80 leuk': ok,
        'Likes films about the eighties': ok,
        'Kijkt elke zaterdag een film met Tim': ok,
        // Refused by the second recogniser, from the re-review.
        'De kinderen zijn 2 of 3 dagen per week bij ons': ok,
        'De kinderen zijn twee of drie avonden per week hier': ok,
        'Mijn zoon is 1 van de grootste Marvel-fans': ok,
        'My son is 1 of those Star Wars fans': ok,
        'De oudste film is 10 jaar oud': ok,
        'Mijn oudste dvd is 20 jaar oud': ok,
        'Mijn dochter is 3 maanden in Spanje': ok,
        'The kids are two of a kind': ok,
        'Mijn dochter is 2 jaar bezig met ballet': ok,
        'Mijn dochter 2 keer per week bij oma is': ok,
        'Ik met de kinderen 2 afleveringen per avond kijk': ok,
        'Mijn zoon 3 dagen per week bij ons is': ok,
      });
    });

    // One table for both word orders: the words after "onthoud dat" are stored
    // as typed, so the verb stands last there. Each pair is the subordinate
    // clause and its main clause.
    test('the verb last and the verb second: refused', () {
      check({
        // Let through in the subordinate order, from the second re-review.
        'Onze zoon bijna negen wordt': age,
        'Onze zoon wordt bijna negen': age,
        'Mijn dochter acht is': age,
        'Mijn dochter is acht': age,
        'Mijn dochter 8 geworden is': age,
        'Mijn dochter is 8 geworden': age,
        'Mijn dochter net acht geworden is': age,
        'Mijn dochter is net acht geworden': age,
        'Mijn kinderen acht en tien zijn': age,
        'Mijn kinderen zijn acht en tien': age,
        'Onze jongste 4 is': age,
        'Onze jongste is 4': age,
        'Ik liever Engels dan Nederlands hoor': language,
        'Hoort liever Engels dan Nederlands': language,
        // Refused before and still.
        'Mijn dochter 8 is': age,
        'Mijn dochter acht jaar is': age,
        'De kinderen 6, 9 en 11 zijn': age,
        'The kids are 8 and 11': age,
        'Ik altijd Nederlandse ondertitels wil': language,
        'Ik films in het Engels kijk': language,
        'Ik altijd Engels geluid wil': language,
        // Nearby, ages.
        'Onze dochter inmiddels 11 is': age,
        'Mijn zoon pas zes geworden is': age,
        'Onze oudste nu veertien is': age,
        'Mijn kleinkind bijna drie wordt': age,
        'Mijn dochter 8 jaar oud is': age,
        'De kinderen 8 en 11 zijn': age,
        'Mijn zoon al 12 is en mee mag kijken': age,
        'Onze zoon net een geworden is': age,
        'Mijn dochter 8': age,
        'Our youngest just turned four': age,
        "My daughter's 8": age,
        'Mijn kinderen nu acht en tien jaar oud zijn': age,
        // Nearby, language.
        'Ik liever Engels dan Nederlands luister': language,
        'Ik liever Engels dan Nederlands kijk': language,
        'Wij liever Japans dan Engels horen': language,
        'Ik films in Engels kijk': language,
        'Ik alles in English wil': language,
      });
    });

    test('the verb last and the verb second: let through', () {
      check({
        // Refused as an age in the subordinate order, from the second re-review.
        'De kinderen thuis met 4 zijn': ok,
        'De kinderen zijn thuis met 4': ok,
        'Mijn dochter nummer 1 is': ok,
        'Mijn dochter is nummer 1': ok,
        'Mijn dochter in seizoen 2 is': ok,
        'Mijn dochter is in seizoen 2': ok,
        'Mijn dochter bij aflevering 5 is': ok,
        'Mijn dochter is bij aflevering 5': ok,
        'Dochter is bij aflevering 5': ok,
        // Let through before and still, with their main clauses.
        'Mijn dochter 2 keer per week bij oma is': ok,
        'Mijn dochter is 2 keer per week bij oma': ok,
        'Ik met de kinderen 2 afleveringen per avond kijk': ok,
        'Ik kijk met de kinderen 2 afleveringen per avond': ok,
        'Mijn zoon 3 dagen per week bij ons is': ok,
        'Mijn zoon is 3 dagen per week bij ons': ok,
        // Nearby.
        'De kinderen 2 dagen per week hier zijn': ok,
        'Mijn zoon 1 van de grootste fans is': ok,
        'De kinderen 3 afleveringen per avond kijken': ok,
        'Mijn dochter een verlegen persoon is': ok,
        'De kinderen op zaterdag 2 films kijken': ok,
        'Mijn zoon groep 8 doet': ok,
        'Mijn dochter om 8 uur naar bed gaat': ok,
        'De kinderen met 3 vriendjes kijken': ok,
        'Mijn zoon deel 2 beter vindt': ok,
        'Mijn dochter 2 jaar op ballet zit': ok,
        'Onze oudste 3 films per week kijkt': ok,
        'Mijn zoon al 2 jaar anime kijkt': ok,
        'Mijn kinderen twee keer per week komen': ok,
        'De kinderen thuis 4 keer per week kijken': ok,
        'My kids watch 2 episodes a night': ok,
        'Mijn zoon per week 2 films kijkt': ok,
        'Ik liever Franse dan Duitse films kijk': ok,
        'Ik liever Chinees dan Italiaans eet': ok,
        'Ik graag Engelse series kijk': ok,
      });
    });

    // "Zoon van 9" is an age whatever follows, the "van" of "houden van"
    // included. From the third re-review; each pair is the subordinate clause
    // and its main clause.
    test('a child word, "van" or "of" and a number is an age in both word orders', () {
      check({
        'Mijn zoon van 9 van Cars houdt': age,
        'Mijn zoon van 9 houdt van Cars': age,
        'Mijn zoon van 12 van Marvel houdt': age,
        'Mijn zoon van 12 houdt van Marvel': age,
        'Mijn dochter van acht van paarden houdt': age,
        'Mijn dochter van acht houdt van paarden': age,
        'Mijn dochter van 8 van mij geen horror mag': age,
        'Mijn dochter van 8 mag van mij geen horror': age,
        'My daughter of eight loves horses': age,
        'My daughter of 8 loves horses': age,
        'My son of 9 is into Cars': age,
        'Mijn kinderen van acht en tien van Bluey houden': age,
        // Refused before and still.
        'Mijn zoon van 12': age,
        'Mijn zoon van 12 mee kijkt': age,
        'Mijn dochter van 8 graag Bluey kijkt': age,
        'Mijn dochter van acht': age,
        'A daughter aged nine': age,
      });
    });

    test('a child word, "van" and a number that is no age is let through', () {
      check({
        'Kijkt geen films voor kinderen van 16 en ouder': ok,
        'De kinderen van twee vrienden komen vaak kijken': ok,
        'De kinderen van 2 vrienden komen vaak kijken': ok,
        'Is een kind van twee culturen': ok,
        'Likes films about a child of two worlds': ok,
      });
    });

    test('child words from the third re-review, in both word orders', () {
      check({
        'Our eldest is 13 years old': age,
        'Onze oudste 13 is': age,
        'Mijn kleinzoon 9 is': age,
        'Mijn kleinzoon is 9': age,
        'Mijn kleindochter is 6': age,
        'Mijn kleindochter 6 is': age,
        'Kleindochter is 4': age,
        'Onze kleinkinderen zijn 3 en 5': age,
        'Onze kleinkinderen 3 en 5 zijn': age,
        'My grandson is 6': age,
        'My granddaughter just turned four': age,
        'Our grandchildren are 3 and 5': age,
        'Onze tweeling is zeven': age,
        'Onze tweeling zeven is': age,
        'The twins are seven': age,
        'Mijn zoontjes zijn 4 en 6': age,
        'Mijn zoontjes 4 en 6 zijn': age,
        'Mijn dochtertjes zijn 4 en 6': age,
        'Mijn dochtertje 3 is': age,
        'Mijn stiefzoon is 9': age,
        'Mijn stiefzoon 9 is': age,
        'Mijn stiefdochter van 11 van musicals houdt': age,
        'My stepson is 9': age,
        'My stepdaughter is 11': age,
        'Onze peuter is 2': age,
        'Onze peuter 2 is': age,
        'Onze kleuter is vijf': age,
        'Onze baby is 1': age,
        'Our toddler is 2': age,
        // The same words without an age.
        'Kijkt op zondag met de kleinkinderen': ok,
        'Mijn kleinzoon houdt van Cars': ok,
        'Onze tweeling kijkt graag Bluey': ok,
        'The twins love Frozen': ok,
        'Mijn stiefzoon kijkt 2 keer per week mee': ok,
        'Our eldest watches 3 films a week': ok,
      });
    });

    test('"jongste" or "oudste" and a count of something else is let through', () {
      check({
        'De jongste drie zijn te eng': ok,
        'De jongste twee films zijn te eng': ok,
        'The oldest three Star Wars films are the best': ok,
        // One child, one age, a singular verb: still refused.
        'Onze jongste 4 is': age,
        'Onze oudste nu veertien is': age,
        'Onze jongste drie wordt': age,
      });
    });

    test('known limit: a child named as boys, girls or "meiden" is let through', () {
      check({'De meiden zijn 10 en 12': ok, 'My boys are 8 and 10': ok, 'My little girl is five': ok});
    });

    test('known limit: a meal before "wil" reads as a language preference', () {
      check({
        'Liever Chinees dan Italiaans wil': language,
        'Ik liever Chinees dan Italiaans eet': ok,
        'I prefer Italian to Chinese food': ok,
      });
    });

    test('known limit: a month or a day between the child and the age is let through, in both orders', () {
      check({
        'Mijn zoon volgende maand 9 wordt': ok,
        'Mijn zoon wordt volgende maand 9': ok,
        'Mijn dochter morgen 8 wordt': ok,
        'Mijn dochter vorige week 8 geworden is': ok,
      });
    });

    test('known limit: an age without a child word next to the verb is let through', () {
      check({
        'Mijn 8-jarige houdt van Bluey': ok,
        'My 8 year old loves Bluey': ok,
        'Dochter, 8 jaar, kijkt mee': ok,
        'My daughter, 8, loves Frozen': ok,
        'Mijn zoon wordt volgende maand 9': ok,
        'Mijn kinderen (8 en 5) kijken mee': ok,
        'Mijn jongens zijn 6 en 9': ok,
        'Zoon: 8': ok,
        'De kinderen zijn zes of zeven': ok,
      });
    });

    test('known limit: a unit outside the list and a bare "oudste" are refused', () {
      check({'Mijn zoon is 2 meter lang': age, 'De oudste is 10 jaar oud': age});
    });

    test('known limit: an age beside a bare name is let through', () {
      check({'Tim is 8': ok, 'Emma wordt negen': ok});
    });

    test('an outright preference for spoken language or subtitles is refused', () {
      check({
        'Wil altijd Nederlandse ondertitels': language,
        'Kijkt zonder ondertiteling': language,
        'Ondertitels nooit aan': language,
        'Prefers English subtitles': language,
        'Kijkt het liefst in het Engels': language,
        'Watches everything in English': language,
        'Audio altijd in de originele taal': language,
        'Audio in het Engels': language,
        'Gesproken taal Engels': language,
        'Prefers the original language': language,
        'Never dubbed, always Japanese audio': language,
        // Let through by the first recogniser, from the review.
        'Wil altijd Engels geluid': language,
        'Liever Engels dan Nederlands': language,
        'Altijd OV, nooit nagesynchroniseerd': language,
        'Kijkt films het liefst in OV': language,
        'Prefers subbed anime': language,
        'Kijkt alles Zweeds gesproken': language,
      });
    });

    test('a language beside a genre, a country, a place or a name is not a preference', () {
      check({
        // Refused by the first recogniser, from the review.
        'Likes dramas set in the English countryside': ok,
        'Houdt van films die zich in het Franse platteland afspelen': ok,
        'Kijkt graag films die in Japanse steden spelen': ok,
        'Vindt The Subs een leuke band': ok,
        // Nearby.
        'Houdt van Franse films': ok,
        'Kijkt Engelse series': ok,
        'Houdt van Koreaanse series': ok,
        'Liever Franse dan Duitse films': ok,
        'Prefers French over German films': ok,
        'Leert Frans en kijkt daarom Franse films': ok,
        'Kijkt in het ov op de telefoon': ok,
        'Houdt niet van horror': ok,
        // Refused by the second recogniser, from the re-review.
        'Vindt de originele versie van Blade Runner beter dan de final cut': ok,
        'Prefers the original version of Star Wars': ok,
        'Reist met OV naar de bioscoop': ok,
        'Stephen King, dubbed the king of horror, is favoriet': ok,
      });
    });

    test('known limit: a bare language, subs and captions are let through', () {
      check({
        'Prefers English': ok,
        'Altijd Engels, nooit Nederlands': ok,
        'Kijkt alles met NL subs': ok,
        'Always watch with captions': ok,
      });
    });

    test('known limit: any mention of subtitles is refused', () {
      check({'Werkt als ondertitelaar': language});
    });

    test('known limit: a language outside the lists is let through', () {
      check({'Kijkt het liefst in het Hongaars': ok});
    });
  });
}
