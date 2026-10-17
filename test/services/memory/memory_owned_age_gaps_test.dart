import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/memory/memory_models.dart';
import 'package:pleya/services/memory/memory_owned_facts.dart';

// BP-11b: age statements that slipped through the memory's refusal as loose
// text, so a child's age reached the model without the age gate.
void main() {
  const gaps = [
    'Mijn zoon van bijna 4',
    'mijn zoon van bijna 4 houdt van Cars',
    'Onze dochter van ongeveer 3',
    'my son of almost 4',
    'Mijn dochter is 2',
    'mijn kids zijn 3 en 5',
    'De kinderen zijn bijna 3 en 5',
    'Mijn dochter wordt 4 in maart',
    'onze zoon wordt in maart 4',
    'mijn jongste wordt in maart 4',
    'my daughter turns 4 in March',
    'ons dochtertje is bijna 2',
  ];
  for (final text in gaps) {
    test('refused as an age: $text', () => expect(ownedFactCode(text), MemoryCode.ownedKidsAges));
  }

  const fine = [
    'Ik kijk graag 3 dagen per week',
    'Mijn zoon houdt van Bluey',
    'Films van 90 minuten',
    'De oudste film is 10 jaar oud',
  ];
  for (final text in fine) {
    test('not an age: $text', () => expect(ownedFactCode(text), isNull));
  }
}
