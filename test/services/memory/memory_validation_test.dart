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
      expect(memoryValueKey('Café Noir'), 'café noir');
    });

    test('the same sentence written differently gives the same key', () {
      expect(memoryValueKey('Houdt niet van horror.'), memoryValueKey('houdt  niet van HORROR'));
    });
  });

  group('facts that already have an owner', () {
    test('children\'s ages are refused', () {
      for (final value in [
        'Onze dochter is 8',
        'De kinderen zijn 6 en 9 jaar',
        'Mijn zoon van 12 kijkt mee',
        'We hebben een achtjarige dochter',
        'Heeft een 8-jarige zoon',
        'Jongste is 4 jaar oud',
        'My daughter is 8',
        'Our kids are 6 and 9 years old',
        'The children are aged 7 and 10',
        'Leeftijden van de kinderen',
      ]) {
        expect(checkMemoryValue(value).code, MemoryCode.ownedKidsAges, reason: value);
      }
    });

    test('language and subtitle preferences are refused', () {
      for (final value in [
        'Wil altijd Nederlandse ondertitels',
        'Kijkt zonder ondertiteling',
        'Prefers English subtitles',
        'Kijkt het liefst in het Engels',
        'Watches everything in English',
        'Audio altijd in de originele taal',
        'Gesproken taal Engels',
        'Prefers the original language',
        'Never dubbed, always Japanese audio',
      ]) {
        expect(checkMemoryValue(value).code, MemoryCode.ownedLanguage, reason: value);
      }
    });

    test('nearby facts that belong in the memory pass', () {
      for (final value in [
        'Kijkt op vrijdag met de kinderen',
        'Heeft twee kinderen',
        'Houdt van Franse films',
        'Houdt van Koreaanse series',
        'Vindt films uit de jaren 80 leuk',
        'Kijkt elke zaterdag een film met Tim',
        'Likes films about the eighties',
        'Houdt niet van horror',
      ]) {
        expect(checkMemoryValue(value).code, MemoryCode.ok, reason: value);
      }
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
