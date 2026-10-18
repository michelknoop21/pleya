part of 'assistant_run.dart';

// Several titles named: the cards are those titles, not every search the
// model ran on the way (BP-11l).

extension _AssistantNamedOnly on AssistantRun {
  /// When the user named a number of titles (at least two) and [answer] names
  /// that many, found in the grids of this run, each grid keeps only the
  /// named titles and a grid with none of them goes. The model often runs a
  /// few searches to find its picks; the user sees the picks, not the leftovers.
  /// An answer that names fewer than asked, or whose titles are not in any
  /// grid (history named as a reason), changes nothing. Only removes cards, so
  /// the age gate and the rights checks that admitted them still hold.
  void _keepNamedOnly(String answer) {
    if (_actions.isNotEmpty || _spoilerQuestion != null || _ctx.libraryDoctorMode) return;
    // A question without a number ("what was added this week") is a listing:
    // the model may highlight two, the rest of the list is still the answer.
    final need = _wanted;
    if (need == null || need < 2) return;
    final named = assistantNamedTitles(answer);
    if (named.length < need) return;
    bool isNamed(MediaItem item, int index) => assistantSameTitle(
      (key: assistantTitleKey(item.title ?? ''), year: item.year),
      assistantTitleKey(named[index].title),
      named[index].year,
    );
    bool isAny(MediaItem item) => Iterable.generate(named.length).any((n) => isNamed(item, n));
    final found = <int>{};
    for (final d in _displays) {
      if (d is! AssistantMediaGrid || _pickGrids.contains(d)) continue;
      for (final e in d.entries) {
        for (var i = 0; i < named.length; i++) {
          if (isNamed(e.item, i)) found.add(i);
        }
      }
    }
    if (found.length < need) return;
    for (var i = 0; i < _displays.length; i++) {
      final grid = _displays[i];
      if (grid is! AssistantMediaGrid || _pickGrids.contains(grid)) continue;
      final kept = [
        for (final e in grid.entries)
          if (isAny(e.item)) e,
      ];
      if (kept.length == grid.entries.length) continue;
      if (kept.isEmpty) {
        _displays.removeAt(i--);
      } else {
        _displays[i] = AssistantMediaGrid(kept, facts: grid.facts);
      }
    }
  }
}
