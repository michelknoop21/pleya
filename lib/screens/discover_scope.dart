import '../media/media_kind.dart';

/// Which slice of the catalog a Home surface shows.
///
/// Series and Films are the same screen as Home with a type filter, not two
/// copies of it ([DEC-069](../../docs/DECISIONS.md)). Keeping them one screen
/// is what stops the hero, the rails, the layout preferences and the focus
/// handling from drifting into three versions that have to be fixed three
/// times.
enum DiscoverScope {
  /// Everything the profile can see. The behaviour Home has always had, and
  /// the default, so every existing call site is unaffected.
  all,

  /// Shows, seasons and episodes.
  series,

  /// Films.
  movies;

  bool get isFiltered => this != DiscoverScope.all;

  /// Whether an item of [kind] belongs in this scope.
  ///
  /// Continue Watching is the reason this is asked per item rather than per
  /// row: an episode belongs to Series, and the row it sits in holds films
  /// too.
  bool admitsKind(MediaKind kind) => switch (this) {
    DiscoverScope.all => true,
    DiscoverScope.series => kind.isShowRelated,
    DiscoverScope.movies => kind == MediaKind.movie,
  };
}
