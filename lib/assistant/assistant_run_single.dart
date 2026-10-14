part of 'assistant_run.dart';

// One title asked, one title named: the cards are that title, not the whole
// search that found it.

extension _AssistantSingleTitle on AssistantRun {
  /// When the question is after one title and [answer] names exactly one and
  /// points at nothing more, each list of titles, grid or set of request
  /// options that shows it keeps only that title. A result without it stays
  /// whole: it answers another part of the question. An answer that names
  /// none or two, or points at several ("andere", "hieronder", a list), picks
  /// nothing for the user. Only removes cards, so the age gate and the rights
  /// checks that admitted them still hold.
  void _keepTheOneNamed(String answer) {
    // After an action the action is the answer; a diagnosis or a fenced story
    // question is worded by Pleya, not by this text.
    if (!_oneTitleAsked || _actions.isNotEmpty || _spoilerQuestion != null || _ctx.libraryDoctorMode) return;
    final named = _theOneNamed(answer);
    if (named == null || assistantAnswerPointsAtMore(answer)) return;
    bool isIt(String? title, int? year) =>
        assistantSameTitle((key: assistantTitleKey(title ?? ''), year: year), named.key, named.year);
    for (var i = 0; i < _displays.length; i++) {
      final only = switch (_displays[i]) {
        AssistantTitleMatches(:final context, :final matches) => _only(
          matches,
          matches.length,
          // A match that cannot be opened or requested is not drawn: no card.
          (m) => (m.targets.isNotEmpty || m.request != null) && isIt(m.title, m.year),
          (kept) => AssistantTitleMatches(context, kept),
        ),
        AssistantMediaGrid(:final entries, :final facts) => _only(
          entries.take(kAssistantMaxListedTitles),
          entries.length,
          (e) => isIt(e.item.title, e.item.year),
          (kept) => AssistantMediaGrid(kept, facts: facts),
        ),
        AssistantRequestOptions(:final context, :final options) => _only(
          options,
          options.length,
          (o) => isIt(o.title, o.year),
          (kept) => AssistantRequestOptions(context, kept),
        ),
        _ => null,
      };
      if (only != null) _displays[i] = only;
    }
  }

  /// The title [answer] names when it names one: the same title twice, once
  /// with its year and once without, is still one. Two years are two titles.
  ({String key, int? year})? _theOneNamed(String answer) {
    final named = assistantNamedTitles(answer);
    final keys = {for (final n in named) assistantTitleKey(n.title)};
    final years = {for (final n in named) ?n.year};
    return keys.length == 1 && years.length <= 1 ? (key: keys.single, year: years.firstOrNull) : null;
  }
}

/// The display of the [all] that are the named title, or null when none is
/// or nothing would go: the display then stays as it is.
AssistantDisplay? _only<T>(
  Iterable<T> all,
  int total,
  bool Function(T) isIt,
  AssistantDisplay Function(List<T>) build,
) {
  final kept = all.where(isIt).toList();
  return kept.isEmpty || kept.length == total ? null : build(kept);
}
