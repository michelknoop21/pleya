part of 'assistant_run.dart';

// One title asked, one title named: the cards are that title, not the whole
// search that found it.

extension _AssistantSingleTitle on AssistantRun {
  /// When the question is after one title and [answer] names exactly one that
  /// a title card or grid draws, keeps only the cards of that title. In every
  /// other case the cards stay as they are: an answer that names none, two or
  /// a title without a card picks nothing for the user. Only removes cards, so
  /// the age gate and the rights checks that admitted them still hold.
  void _keepTheOneNamed(String answer) {
    // After an action the action is the answer; a diagnosis or a fenced story
    // question is worded by Pleya, not by this text.
    if (!_oneTitleAsked || _actions.isNotEmpty || _spoilerQuestion != null || _ctx.libraryDoctorMode) return;
    final named = assistantNamedTitles(answer);
    if (named.length != 1) return;
    final key = assistantTitleKey(named.single.title);
    bool isIt(String? title, int? year) =>
        assistantSameTitle((key: assistantTitleKey(title ?? ''), year: year), key, named.single.year);
    final next = <AssistantDisplay>[];
    var found = false;
    for (final display in _displays) {
      switch (display) {
        case AssistantTitleMatches(:final context, :final matches):
          // A match that cannot be opened or requested is not drawn: no card.
          final kept = [
            for (final m in matches)
              if ((m.targets.isNotEmpty || m.request != null) && isIt(m.title, m.year)) m,
          ];
          found = found || kept.isNotEmpty;
          if (kept.isNotEmpty) next.add(kept.length == matches.length ? display : AssistantTitleMatches(context, kept));
        case AssistantMediaGrid(:final entries, :final facts):
          final kept = [
            for (final e in entries.take(kAssistantListedTitles))
              if (isIt(e.item.title, e.item.year)) e,
          ];
          found = found || kept.isNotEmpty;
          if (kept.isNotEmpty)
            next.add(kept.length == entries.length ? display : AssistantMediaGrid(kept, facts: facts));
        default:
          next.add(display);
      }
    }
    // The named title has no card: the search result stays whole.
    if (!found) return;
    _displays
      ..clear()
      ..addAll(next);
  }
}
