/// Films and series Big P names in his answer, so Pleya can show each as a
/// card to open or request (DEC-142: Pleya draws, the model only names).
library;

import 'assistant_tools.dart';

/// A title as the cards compare it: lower case, letters and digits only.
String assistantTitleKey(String title) => title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

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
      AssistantWatchStats(:final titles) => [for (final t in titles.take(5)) (t.title, t.target?.item.year)],
      AssistantServerComparison(:final missing) => [for (final i in missing.take(12)) (i.title ?? '', i.year)],
      _ => const <(String, int?)>[],
    }.map((t) => (key: assistantTitleKey(t.$1), year: t.$2)),
};

/// Whether a card for [key] and [year] answers a title named with
/// [namedYear]: the same title, and the same year when both are known.
bool assistantSameTitle(({String key, int? year}) card, String key, int? namedYear) =>
    card.key == key && (namedYear == null || card.year == null || card.year == namedYear);
