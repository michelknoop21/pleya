import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tools.dart';

import 'assistant_single_title_support.dart';

// BP-11l: an answer that names its picks keeps the cards of those picks, not
// of every search the model ran to find them.

void main() {
  AssistantTool grid(String name, List<(String, int)> titles) =>
      displayTool(name, (_) => AssistantMediaGrid([for (final (t, y) in titles) (item: movieItem(t, y), group: null)]));

  final tools = [
    grid('search_a', [('Alpha', 2001), ('Bravo', 2002), ('Charlie', 2003), ('Delta', 2004)]),
    grid('search_b', [('Echo', 2005), ('Foxtrot', 2006), ('Golf', 2007)]),
  ];
  const calls = <Object>[
    {'name': 'search_a', 'args': <String, Object?>{}},
    {'name': 'search_b', 'args': <String, Object?>{}},
  ];

  test('three titles named out of seven cards from two searches: only those three stay', () async {
    final r = await singleAsk(
      [...calls, 'Probeer «Bravo» (2002), «Echo» (2005) of «Golf» (2007).'],
      'Geef me een paar films voor vanavond',
      tools: tools,
    );
    expect(cardsOf(r), ['Bravo', 'Echo', 'Golf']);
  });

  test('a grid with none of the named titles goes', () async {
    final r = await singleAsk(
      [...calls, 'Probeer «Alpha» (2001), «Charlie» (2003) of «Delta» (2004).'],
      'Geef me een paar films voor vanavond',
      tools: tools,
    );
    expect(cardsOf(r), ['Alpha', 'Charlie', 'Delta']);
  });

  test('fewer titles named than the user asked for: the cards stay whole', () async {
    final r = await singleAsk(
      [...calls, 'Probeer «Bravo» (2002) of «Echo» (2005).'],
      'Geef me vijf films voor vanavond',
      tools: tools,
    );
    expect(cardsOf(r), hasLength(7));
  });

  test('titles named that no grid holds change nothing', () async {
    final r = await singleAsk(
      [...calls, 'Probeer «Hotel» (2008) of «India» (2009).'],
      'Geef me een paar films voor vanavond',
      tools: tools,
    );
    expect(cardsOf(r), hasLength(7));
  });

  test('a listing question without a number keeps the whole list when two are highlighted', () async {
    final r = await singleAsk(
      [...calls, 'Probeer «Bravo» (2002) of «Echo» (2005).'],
      'Wat is er deze week toegevoegd?',
      tools: tools,
    );
    expect(cardsOf(r), hasLength(7));
  });

  test('"geef me er vijf andere" counts as five: the named five stay, the other searches go', () async {
    final r = await singleAsk(
      [...calls, 'Probeer «Alpha» (2001), «Bravo» (2002), «Echo» (2005), «Foxtrot» (2006) of «Golf» (2007).'],
      'die heb ik al gezien, geef me er vijf andere',
      tools: tools,
    );
    expect(cardsOf(r), ['Alpha', 'Bravo', 'Echo', 'Foxtrot', 'Golf']);
  });

  test('two different numbers in one question: the cards stay whole', () async {
    final r = await singleAsk(
      [...calls, 'Probeer «Alpha» (2001), «Bravo» (2002) en «Charlie» (2003).'],
      'Toon 3 series en 10 films',
      tools: tools,
    );
    expect(cardsOf(r), hasLength(7));
  });

  test('one title named is left to the single-title rule: the cards stay whole', () async {
    final r = await singleAsk(
      [...calls, 'Probeer «Bravo» (2002).'],
      'Geef me een paar films voor vanavond',
      tools: tools,
    );
    expect(cardsOf(r), hasLength(7));
  });
}
