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
    test('invisible format characters are dropped from the stored value and the key', () {
      for (final code in [0x200B, 0x200C, 0x200D, 0x00AD, 0x2060, 0x061C, 0xFE0F, 0xFE00, 0xE0100]) {
        final checked = checkMemoryValue('Hor${_char(code)}ror film${_char(code)}');
        expect(checked.code, MemoryCode.ok, reason: 'U+${code.toRadixString(16)}');
        expect(checked.value!.value, 'Horror film', reason: 'U+${code.toRadixString(16)}');
        expect(checked.value!.key, 'horror film', reason: 'U+${code.toRadixString(16)}');
      }
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
      });
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
      });
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
