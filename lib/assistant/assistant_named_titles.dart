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
  void add(String raw, String? year) {
    final title = raw.trim();
    final key = assistantTitleKey(title);
    if (key.isEmpty || title.length > 80 || !seen.add(key)) return;
    found.add((title: title, year: year == null ? null : int.tryParse(year)));
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

/// The titles [displays] already show as cards or rows.
Set<String> assistantShownTitleKeys(Iterable<AssistantDisplay> displays) => {
  for (final d in displays)
    ...switch (d) {
      AssistantTitleMatches(:final matches) => [for (final m in matches) m.title],
      AssistantMediaGrid(:final entries) => [for (final e in entries) e.item.title ?? ''],
      AssistantRequestOptions(:final options) => [for (final o in options) o.title],
      AssistantWatchStats(:final titles) => [for (final t in titles) t.title],
      AssistantServerComparison(:final missing) => [for (final i in missing) i.title ?? ''],
      _ => const <String>[],
    }.map(assistantTitleKey),
};
