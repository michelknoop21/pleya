/// What the kijklijst is narrowed to, as two independent questions.
///
/// Until [DEC-108](../../docs/DECISIONS.md#dec-108) this was one four-way
/// choice — Alles, Films, Series, Beschikbaar — drawn as a strip of chips. The
/// mockup puts it in the catalog's rail instead, and a rail row is one
/// question with one answer, so "kind" and "availability" had to stop sharing
/// a slot: on a phone picking Beschikbaar silently threw away the fact that
/// you were looking at films.
///
/// **The chips did not change.** The mobile bar still offers the same four,
/// and each one still maps onto the whole selection rather than onto one axis
/// (see [WatchlistFilterSelection.chip]), so tapping Beschikbaar there clears
/// the kind exactly as it always did. What is new is that the two axes can now
/// be set separately, which is what the rail does.
///
/// This is deliberately *not* `UnifiedCatalogFilterSelection`. That type is
/// bolted to the catalog domain — it selects `CatalogLibrary`s and
/// `UnifiedCatalogs.forKind` throws for anything outside movie and show — and
/// DEC-108 (2) is explicit that these screens borrow the presentation and keep
/// their own model.
library;

import 'media_kind.dart';
import 'watchlist_entry.dart';

/// Which kind of title the list is showing.
enum WatchlistKindFilter {
  all,
  movies,
  shows;

  /// Whether [kind] passes this filter.
  bool accepts(MediaKind kind) => switch (this) {
    WatchlistKindFilter.all => true,
    WatchlistKindFilter.movies => kind == MediaKind.movie,
    WatchlistKindFilter.shows => kind == MediaKind.show,
  };
}

/// The four chips the mobile filter bar offers, kept as their own type because
/// they are a *presentation* of [WatchlistFilterSelection] and not a second
/// model: each chip is one whole selection.
enum WatchlistFilterChip { all, movies, shows, available }

class WatchlistFilterSelection {
  const WatchlistFilterSelection({this.kind = WatchlistKindFilter.all, this.availableOnly = false});

  final WatchlistKindFilter kind;

  /// Only titles a reachable server actually holds.
  ///
  /// Turning this on costs a full sweep of everything still unresolved
  /// (`watchlist_screen.dart`'s `_setFilter`), because lazy resolving and
  /// filtering on availability contradict each other: entries outside the
  /// viewport are still unknown, so without the sweep the filter would hide
  /// titles that are in fact there. That price is what the rail may promise and
  /// nothing more — it cannot offer "Niet beschikbaar" as a third state without
  /// the same sweep, and it does not.
  final bool availableOnly;

  static const WatchlistFilterSelection none = WatchlistFilterSelection();

  bool get isEmpty => kind == WatchlistKindFilter.all && !availableOnly;

  WatchlistFilterSelection copyWith({WatchlistKindFilter? kind, bool? availableOnly}) =>
      WatchlistFilterSelection(kind: kind ?? this.kind, availableOnly: availableOnly ?? this.availableOnly);

  /// The whole selection one chip stands for.
  ///
  /// Availability and kind are mutually exclusive here, and that is the mobile
  /// bar's own long-standing behaviour rather than a limitation of this type:
  /// four chips can only express four states.
  static WatchlistFilterSelection chip(WatchlistFilterChip chip) => switch (chip) {
    WatchlistFilterChip.all => const WatchlistFilterSelection(),
    WatchlistFilterChip.movies => const WatchlistFilterSelection(kind: WatchlistKindFilter.movies),
    WatchlistFilterChip.shows => const WatchlistFilterSelection(kind: WatchlistKindFilter.shows),
    WatchlistFilterChip.available => const WatchlistFilterSelection(availableOnly: true),
  };

  bool accepts(WatchlistEntry entry) {
    if (!kind.accepts(entry.kind)) return false;
    if (availableOnly && entry.availability != WatchlistAvailability.available) return false;
    return true;
  }

  List<WatchlistEntry> apply(List<WatchlistEntry> entries) =>
      isEmpty ? entries : entries.where(accepts).toList(growable: false);

  @override
  bool operator ==(Object other) =>
      other is WatchlistFilterSelection && other.kind == kind && other.availableOnly == availableOnly;

  @override
  int get hashCode => Object.hash(kind, availableOnly);

  @override
  String toString() => 'WatchlistFilterSelection(${kind.name}${availableOnly ? ', available' : ''})';
}
