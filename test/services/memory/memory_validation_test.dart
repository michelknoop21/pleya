import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/memory/memory_models.dart';
import 'package:pleya/services/memory/memory_validation.dart';

String _char(int code) => String.fromCharCode(code);

void main() {
  group('shape', () {
    test('a plain sentence is trimmed and accepted', () {
      final checked = checkMemoryValue('  Houdt niet van horror.  ');
      expect(checked.code, MemoryCode.ok);
      expect(checked.value!.value, 'Houdt niet van horror.');
      expect(checked.value!.key, 'houdt niet van horror');
    });

    test('empty, blank and punctuation-only are refused as empty', () {
      for (final raw in ['', '   ', '\n', '!!!', '...  ?']) {
        expect(checkMemoryValue(raw).code, MemoryCode.empty, reason: '"$raw"');
      }
    });

    test('more than one line is refused', () {
      for (final breaker in ['\n', '\r', '\r\n', _char(0x0B), _char(0x0C), _char(0x85), _char(0x2028), _char(0x2029)]) {
        expect(checkMemoryValue('eerste${breaker}tweede').code, MemoryCode.notSingleLine);
      }
    });

    test('control characters and direction overrides are refused', () {
      for (final code in [0x00, 0x07, 0x09, 0x1B, 0x7F, 0x9F, 0x200E, 0x202E, 0x2066, 0xFEFF]) {
        expect(
          checkMemoryValue('kijkt${_char(code)}graag').code,
          MemoryCode.controlCharacters,
          reason: 'U+${code.toRadixString(16)}',
        );
      }
    });

    test('200 code points fit and 201 do not', () {
      expect(checkMemoryValue('a' * kMemoryValueMaxLength).code, MemoryCode.ok);
      expect(checkMemoryValue('a' * (kMemoryValueMaxLength + 1)).code, MemoryCode.tooLong);
      // An emoji is one code point but two UTF-16 units.
      final emoji = _char(0x1F3AC);
      expect(checkMemoryValue('${'a' * 199}$emoji').code, MemoryCode.ok);
    });
  });

  group('valueKey', () {
    test('lowercase, no punctuation, single spaces', () {
      expect(memoryValueKey('  Houdt NIET   van   horror!  '), 'houdt niet van horror');
      expect(memoryValueKey('Kijkt op vrijdag, met z\'n allen.'), 'kijkt op vrijdag met zn allen');
      expect(memoryValueKey('Café Noir'), 'cafe noir');
    });

    test('the same sentence written differently gives the same key', () {
      expect(memoryValueKey('Houdt niet van horror.'), memoryValueKey('houdt  niet van HORROR'));
    });
  });

  group('invisible characters and accents', () {
    test('invisible format characters are dropped from the key and kept in the stored value', () {
      for (final code in [0x200B, 0x200C, 0x200D, 0x00AD, 0x2060, 0x061C, 0xFE0F, 0xFE00, 0xE0100]) {
        final typed = 'Hor${_char(code)}ror film${_char(code)}';
        final checked = checkMemoryValue(typed);
        expect(checked.code, MemoryCode.ok, reason: 'U+${code.toRadixString(16)}');
        expect(checked.value!.value, typed, reason: 'U+${code.toRadixString(16)}');
        expect(checked.value!.key, 'horror film', reason: 'U+${code.toRadixString(16)}');
      }
    });

    test('a family emoji and a Persian word are stored byte for byte, with a stable key', () {
      final family = [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467].map(_char).join();
      final heart = '${_char(0x2764)}${_char(0xFE0F)}';
      // "mi-khaham", with a zero width non-joiner after the prefix.
      final persian = [0x645, 0x6CC, 0x200C, 0x62E, 0x648, 0x627, 0x647, 0x645].map(_char).join();

      for (final typed in ['Kijkt met $family films', '$heart horror', '$persian film']) {
        final checked = checkMemoryValue('  $typed  ');
        expect(checked.code, MemoryCode.ok, reason: typed);
        expect(utf8.encode(checked.value!.value), utf8.encode(typed), reason: typed);
      }

      expect(checkMemoryValue('Kijkt met $family films').value!.key, 'kijkt met films');
      expect(
        checkMemoryValue('$persian film').value!.key,
        checkMemoryValue('${persian.replaceAll(_char(0x200C), '')} film').value!.key,
      );
    });

    test('an invisible character inside a word does not hide a fact that has an owner', () {
      expect(checkMemoryValue('Onze doch${_char(0x200B)}ter is 8').code, MemoryCode.ownedKidsAges);
      expect(checkMemoryValue('Wil altijd onder${_char(0xAD)}titels').code, MemoryCode.ownedLanguage);
    });

    test('line breaks and control characters stay out of the stored value', () {
      final joiner = _char(0x200D);
      expect(checkMemoryValue('een$joiner\ntwee').code, MemoryCode.notSingleLine);
      expect(checkMemoryValue('een$joiner${_char(0x202E)}twee').code, MemoryCode.controlCharacters);
    });

    test('the key is accent-insensitive: one sentence with and without accents is one fact', () {
      expect(memoryValueKey('Kijkt één film per week'), memoryValueKey('Kijkt een film per week'));
    });

    test('only invisible characters is empty', () {
      expect(checkMemoryValue('${_char(0x200B)}${_char(0x2060)} ${_char(0xFE0F)}').code, MemoryCode.empty);
    });

    test('an emoji with a variation selector does not end up in the key', () {
      expect(checkMemoryValue('${_char(0x2764)}${_char(0xFE0F)} horror').value!.key, 'horror');
    });

    test('the composed and the decomposed spelling share a key', () {
      final composed = 'Caf${_char(0xE9)} Noir';
      final decomposed = 'Cafe${_char(0x301)} Noir';
      expect(composed == decomposed, isFalse);
      expect(memoryValueKey(composed), 'cafe noir');
      expect(memoryValueKey(decomposed), 'cafe noir');
      expect(memoryValueKey('Cafe Noir'), 'cafe noir');
      expect(memoryValueKey('Pâté, Señor Žižek & Ångström'), 'pate senor zizek angstrom');
    });

    test('known limit: an accented letter outside the Latin table keeps two keys', () {
      // Greek alpha with tonos, composed and decomposed.
      expect(memoryValueKey(_char(0x3AC)) == memoryValueKey('${_char(0x3B1)}${_char(0x301)}'), isFalse);
    });
  });

  group('overview body', () {
    test('a JSON object within the ceiling is kept, anything else is not', () {
      expect(isMemoryOverviewBody('{}'), isTrue);
      expect(isMemoryOverviewBody('{"sections":[{"title":"Smaak"}]}'), isTrue);
      for (final body in ['', 'tekst', '{"open":', '[]', '"tekst"', '12', 'null']) {
        expect(isMemoryOverviewBody(body), isFalse, reason: body);
      }
    });

    test('the ceiling counts UTF-8 bytes', () {
      String bodyOf(String text) => '{"t":"$text"}';
      final room = kMemoryOverviewMaxBytes - bodyOf('').length;
      expect(isMemoryOverviewBody(bodyOf('a' * room)), isTrue);
      expect(isMemoryOverviewBody(bodyOf('a' * (room + 1))), isFalse);
      // Two bytes per letter.
      expect(isMemoryOverviewBody(bodyOf(_char(0xE9) * (room ~/ 2 + 1))), isFalse);
    });
  });

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

    test('known limit: a month or a day between the child and the age is let through, in both orders', () {
      check({'Mijn zoon volgende maand 9 wordt': ok, 'Mijn zoon wordt volgende maand 9': ok});
    });

    test('known limit: an age without a child word next to the verb is let through', () {
      check({
        'Mijn 8-jarige houdt van Bluey': ok,
        'My 8 year old loves Bluey': ok,
        'Dochter, 8 jaar, kijkt mee': ok,
        'My daughter, 8, loves Frozen': ok,
        'Mijn zoon wordt volgende maand 9': ok,
        'Mijn kinderen (8 en 5) kijken mee': ok,
        'Kleindochter is 4': ok,
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

  group('match words', () {
    test('short words and function words carry no match', () {
      expect(memoryMatchWords('Wat is er voor de kinderen?'), {'kinderen'});
      expect(memoryMatchWords('The one with the heist'), {'one', 'heist'});
      expect(memoryMatchWords('sci-fi'), {'sci'});
    });
  });
}
