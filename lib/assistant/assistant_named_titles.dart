/// Films and series Big P names in his answer, so Pleya can show each as a
/// card to open or request (DEC-142: Pleya draws, the model only names).
library;

import 'assistant_tools.dart';

/// A title as the cards compare it: lower case, letters and digits only. A
/// trailing "(2018)" is dropped: Plex names some shows "Bluey (2018)", and
/// the model names the same show «Bluey» with the year apart.
String assistantTitleKey(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

/// Accented letters and the plain letter they fold to.
const _folds = {
  'a': 'àáâãäåā',
  'c': 'çč',
  'e': 'èéêëē',
  'i': 'ìíîïī',
  'n': 'ñ',
  'o': 'òóôõöøō',
  's': 'š',
  'u': 'ùúûüū',
  'y': 'ýÿ',
  'z': 'ž',
};
final _foldOf = {
  for (final e in _folds.entries)
    for (final c in e.value.split('')) c: e.key,
};

/// [text] as plain words: lower case, accents folded, every run of other
/// characters a single space.
String assistantPlainWords(String text) => text
    .toLowerCase()
    .split('')
    .map((c) => _foldOf[c] ?? c)
    .join()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// The plain words that name [title] in running text: the whole title, and
/// the main title before a subtitle after ":" or " - " when it has two words
/// or eight letters, so a short main title does not match ordinary prose.
List<String> assistantTitleWords(String title) {
  final full = assistantPlainWords(title);
  final cut = title.indexOf(RegExp('[:]|\\s[-\u2013]\\s'));
  final main = cut > 0 ? assistantPlainWords(title.substring(0, cut)) : '';
  return [
    if (full.isNotEmpty) full,
    if (main.isNotEmpty && main != full && (main.contains(' ') || main.length >= 8)) main,
  ];
}

/// The titles in [answer]: everything between « and », and list items that
/// carry a year ("• Interstellar (2014)") when the model left the marks out.
/// At most five, in order, each once.
List<({String title, int? year})> assistantNamedTitles(String answer) {
  final found = <({String title, int? year})>[];
  final seen = <String>{};
  void add(String raw, String? rawYear) {
    final title = raw.trim();
    // A year find_title would refuse drops the year, not every title.
    final year = switch (int.tryParse(rawYear ?? '')) {
      final y? when y >= 1870 && y <= 2100 => y,
      _ => null,
    };
    final key = assistantTitleKey(title);
    // Dune (1984) and Dune (2021) are two titles.
    if (key.isEmpty || title.length > 80 || !seen.add('$key:${year ?? ''}')) return;
    found.add((title: title, year: year));
  }

  for (final m in RegExp(r'«([^»\n]{1,80})»(?:\s*\((\d{4})\))?').allMatches(answer)) {
    add(m[1]!, m[2]);
  }
  if (found.isEmpty) {
    final item = RegExp(
      r'^[ \t]*(?:[-*•]|\d+[.)])[ \t]+\**([^\n(*]{1,80}?)\**[ \t]*\(((?:19|20)\d{2})\)',
      multiLine: true,
    );
    for (final m in item.allMatches(answer)) {
      add(m[1]!, m[2]);
    }
  }
  return found.take(5).toList();
}

/// The titles [displays] show as cards, as title key and year (null when
/// the card has none). Only what is drawn counts: a title past a card's cap
/// has no card, so a named title there still gets one.
Set<({String key, int? year})> assistantShownTitles(Iterable<AssistantDisplay> displays) => {
  for (final d in displays)
    ...switch (d) {
      AssistantTitleMatches(:final matches) => [for (final m in matches) (m.title, m.year)],
      AssistantMediaGrid(:final entries) => [for (final e in entries.take(12)) (e.item.title ?? '', e.item.year)],
      AssistantRequestOptions(:final options) => [for (final o in options) (o.title, o.year)],
      // A watched title without a library copy is a dimmed card: the named
      // title still gets one it can open or request.
      AssistantWatchStats(:final titles) => [
        for (final t in titles.take(5))
          if (t.target case final target?) (t.title, target.item.year),
      ],
      AssistantServerComparison(:final missing) => [for (final i in missing.take(12)) (i.title ?? '', i.year)],
      _ => const <(String, int?)>[],
    }.map((t) => (key: assistantTitleKey(t.$1), year: t.$2)),
};

/// Whether a card for [key] and [year] answers a title named with
/// [namedYear]: the same title, and the same year when both are known.
bool assistantSameTitle(({String key, int? year}) card, String key, int? namedYear) =>
    card.key == key && (namedYear == null || card.year == null || card.year == namedYear);

/// Big P's words without em or en dashes: a spaced or run-on dash becomes a
/// comma, one between digits or letters a hyphen ("2018\u20132020" is "2018-2020").
/// The model is told so too; this is the net under it.
String assistantPlainDashes(String text) => text
    .replaceAll(RegExp(r'\s*[\u2014\u2015]\s*'), ', ')
    .replaceAll(RegExp(r'\s+\u2013\s+'), ', ')
    .replaceAll('\u2013', '-')
    .replaceAllMapped(RegExp(r',\s*([.!?])'), (m) => m[1]!)
    .replaceAll(RegExp(r',\s*$'), '');
