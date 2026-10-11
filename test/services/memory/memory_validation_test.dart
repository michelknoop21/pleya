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

  group('match words', () {
    test('short words and function words carry no match', () {
      expect(memoryMatchWords('Wat is er voor de kinderen?'), {'kinderen'});
      expect(memoryMatchWords('The one with the heist'), {'one', 'heist'});
      expect(memoryMatchWords('sci-fi'), {'sci'});
    });
  });
}
