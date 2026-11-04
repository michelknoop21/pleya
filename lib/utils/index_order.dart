import '../i18n/strings.g.dart';
import '../media/media_item.dart';

/// Orders items by their number, with items that have none after the numbered
/// ones, and those on title.
///
/// This is the order Pleya Server hands out for a season's children, and the
/// order the client has to agree with when it sorts on its own (downloaded
/// episodes, a merged season list). `(a.index ?? 0)` read a missing number as
/// zero, which put an unnumbered episode in front of episode 1, and gave two
/// unnumbered episodes the same key so their order depended on the sort. Dart's
/// `List.sort` is not stable, so equal keys can swap between runs.
///
/// Ties end on the id, so the result never depends on the input order.
int compareByIndexNullsLast(MediaItem a, MediaItem b) {
  final ai = a.index;
  final bi = b.index;
  if (ai != null && bi != null) {
    final byIndex = ai.compareTo(bi);
    if (byIndex != 0) return byIndex;
  } else if (ai != null) {
    return -1;
  } else if (bi != null) {
    return 1;
  }
  final byTitle = _sortTitle(a).compareTo(_sortTitle(b));
  if (byTitle != 0) return byTitle;
  return a.id.compareTo(b.id);
}

String _sortTitle(MediaItem item) => (item.titleSort ?? item.title ?? '').toLowerCase();

/// The text on the play button of a show: `S1E4` when both numbers are known,
/// and plain "Play" when they are not.
///
/// An episode without a number (a loose download the server could only name by
/// its title) has no `S1E?` to show, and the old `?? 0` printed `S1E0`, which
/// names a season-zero episode that does not exist.
String playEpisodeLabel({required int? season, required int? episode}) {
  if (season == null || episode == null) return t.common.play;
  return t.discover.playEpisode(season: season.toString(), episode: episode.toString());
}
