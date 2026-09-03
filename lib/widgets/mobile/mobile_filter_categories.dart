/// What the two-column filter panel offers, as data — mockup
/// `04-filters-sheet.png`, iOS Unified 2026 fase 3.
///
/// The panel's left column is a list of categories and the right column is
/// whichever one is open. Both are derived: from the catalogue's participating
/// libraries (which servers and libraries exist), from the loaded filter
/// options (which genres and years exist), and from the backend capabilities
/// (whether genre, year and watch state may be offered at all).
///
/// Pure so the derivation is testable without a widget tree, and so the panel
/// itself only has to draw a list. The rule that matters lives here: a
/// category the participating backends cannot execute is **listed and
/// disabled**, never silently dropped. A row that vanishes leaves the user
/// wondering whether the app forgot the filter or the catalogue has no genres;
/// a row that says why is the difference between a missing feature and an
/// explained one, and `filters.unsupported` exists for exactly that sentence.
library;

import '../../i18n/strings.g.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_filter_options.dart';
import '../../utils/global_key_utils.dart';

/// The five sections of mockup 04's left column, in the order it draws them.
enum MobileFilterCategory { status, genre, year, servers, libraries }

/// One selectable value in a category's right-hand column.
///
/// [id] is what goes into the selection — a genre name, a year as a string, a
/// server id, a `serverId:libraryId` key — and [label] is what the row reads.
/// They differ for servers and libraries, where the id is stable and the label
/// is the name the user gave the thing.
typedef MobileFilterOption = ({String id, String label});

/// One row of the left column, with everything needed to draw it: what it is
/// called, how many values are picked, whether it may be used at all, and the
/// values it opens.
class MobileFilterSection {
  final MobileFilterCategory category;
  final String label;
  final List<MobileFilterOption> options;

  /// Ids from [options] currently picked — what the right column ticks.
  final Set<String> selected;

  /// False when the participating backends cannot execute this filter. The row
  /// still draws, greyed, with [t.unifiedCatalog.filters.unsupported] beneath
  /// it.
  final bool supported;

  /// How many *narrowings* this category holds, which is not always
  /// [selected] `.length`. Status always has a ticked row, because "All" is a
  /// row rather than the absence of one, and mockup 04 draws no number beside
  /// it while it sits there — a count of 1 for "not filtering" would be a lie
  /// that also lands in the header's "2 active".
  ///
  /// Zero for an unsupported category, matching
  /// `UnifiedCatalogFilterSelection.constrainedTo`: an unusable genre choice
  /// stays in storage and stays ticked, but it narrows nothing right now, so
  /// numbering it would put a count on a row that changes no result.
  final int activeCount;

  const MobileFilterSection({
    required this.category,
    required this.label,
    required this.options,
    required this.selected,
    required this.supported,
    required this.activeCount,
  });

  /// Whether the right-hand column has anything to draw. A supported category
  /// with no values (no server reported a genre) gets
  /// [t.unifiedCatalog.filters.noValues] rather than an empty panel.
  bool get hasOptions => options.isNotEmpty;
}

/// Builds the five sections for one catalogue.
///
/// [selection] is the *stored* selection, not the constrained one: the panel
/// is where an unusable choice is unticked, so it has to be visible there. The
/// count beside a category applies the constraint (see [MobileFilterSection.activeCount]),
/// the ticks do not.
List<MobileFilterSection> buildMobileFilterSections({
  required UnifiedCatalogFilterSelection selection,
  required UnifiedFilterCapabilities capabilities,
  required UnifiedFilterOptions options,
  required List<CatalogLibrary> eligibleLibraries,
}) {
  final servers = <String, String>{};
  final libraries = <MobileFilterOption>[];
  for (final library in eligibleLibraries) {
    servers.putIfAbsent(library.serverId.value, () => library.serverName);
    libraries.add((id: buildGlobalKey(library.serverId, library.libraryId), label: library.libraryTitle));
  }

  return [
    MobileFilterSection(
      category: MobileFilterCategory.status,
      label: t.unifiedCatalog.filters.status,
      // Two states, and they are the two `LibraryQuery.includeWatched`
      // expresses. "Watched" and "in progress" are deliberately not here —
      // see [UnifiedWatchFilter]'s own doc for why adding them is a contract
      // change and not a panel decision.
      options: [
        (id: UnifiedWatchFilter.all.name, label: t.unifiedCatalog.filters.all),
        (id: UnifiedWatchFilter.unwatched.name, label: t.unifiedCatalog.filters.unwatched),
      ],
      // "All" is the absence of a filter, so it is drawn as the ticked row
      // when nothing is set rather than leaving the category with no answer.
      selected: {selection.watchState.name},
      supported: capabilities.supportsWatchFilter,
      activeCount: capabilities.supportsWatchFilter && selection.watchState != UnifiedWatchFilter.all ? 1 : 0,
    ),
    MobileFilterSection(
      category: MobileFilterCategory.genre,
      label: t.unifiedCatalog.filters.genre,
      options: [for (final genre in options.genres) (id: genre, label: genre)],
      selected: selection.genres,
      supported: capabilities.supportsMetadataFilters,
      activeCount: capabilities.supportsMetadataFilters ? selection.genres.length : 0,
    ),
    MobileFilterSection(
      category: MobileFilterCategory.year,
      label: t.unifiedCatalog.filters.year,
      options: [for (final year in options.years) (id: '$year', label: '$year')],
      selected: {for (final year in selection.years) '$year'},
      supported: capabilities.supportsMetadataFilters,
      activeCount: capabilities.supportsMetadataFilters ? selection.years.length : 0,
    ),
    // Servers and libraries are always available: restricting which cursors
    // take part is the merge engine's own job, not something a backend has to
    // support (see `unified_catalog_filters.dart`'s library doc).
    MobileFilterSection(
      category: MobileFilterCategory.servers,
      label: t.unifiedCatalog.filters.servers,
      options: [for (final entry in servers.entries) (id: entry.key, label: entry.value)],
      selected: selection.serverIds,
      supported: true,
      activeCount: selection.serverIds.length,
    ),
    MobileFilterSection(
      category: MobileFilterCategory.libraries,
      label: t.unifiedCatalog.filters.libraries,
      options: libraries,
      selected: selection.libraryKeys,
      supported: true,
      activeCount: selection.libraryKeys.length,
    ),
  ];
}

/// [selection] with [optionId] toggled inside [category].
///
/// Status is single-valued and the others are multi-valued, which is the one
/// asymmetry the panel has: picking a watch state replaces the previous one,
/// picking a genre adds to it. Untoggling the last genre yields an empty set,
/// which is what "no genre filter" is — not a set holding every genre.
UnifiedCatalogFilterSelection toggleMobileFilter({
  required UnifiedCatalogFilterSelection selection,
  required MobileFilterCategory category,
  required String optionId,
}) {
  Set<T> flip<T>(Set<T> current, T value) =>
      current.contains(value) ? ({...current}..remove(value)) : {...current, value};

  return switch (category) {
    MobileFilterCategory.status => selection.copyWith(
      watchState: optionId == UnifiedWatchFilter.unwatched.name ? UnifiedWatchFilter.unwatched : UnifiedWatchFilter.all,
    ),
    MobileFilterCategory.genre => selection.copyWith(genres: flip(selection.genres, optionId)),
    MobileFilterCategory.year => switch (int.tryParse(optionId)) {
      final year? => selection.copyWith(years: flip(selection.years, year)),
      null => selection,
    },
    MobileFilterCategory.servers => selection.copyWith(serverIds: flip(selection.serverIds, optionId)),
    MobileFilterCategory.libraries => selection.copyWith(libraryKeys: flip(selection.libraryKeys, optionId)),
  };
}

/// The one-line summary drawn on the right of the status row, beside "N titles
/// loaded" — mockup 03's "Sciencefiction · 2020–2025".
///
/// Values, not field names: the field names are on the panel, and repeating
/// them here would spend the line on words the user already chose. Years
/// collapse into a range because a run of them is what a year filter usually
/// is, and eight separate years would push the count off the row.
///
/// Returns null when nothing narrows the *items*. A source restriction is
/// deliberately not summarised here — it has its own control, which carries
/// its own label (DEC-094).
String? mobileActiveFilterSummary({
  required UnifiedCatalogFilterSelection selection,
  required UnifiedFilterCapabilities capabilities,
}) {
  final applied = selection.constrainedTo(capabilities);
  final parts = <String>[
    if (applied.watchState == UnifiedWatchFilter.unwatched) t.unifiedCatalog.filters.unwatched,
    ...(applied.genres.toList()..sort()),
    ...switch (applied.years.length) {
      0 => const <String>[],
      1 => ['${applied.years.first}'],
      _ => ['${applied.years.reduce((a, b) => a < b ? a : b)}–${applied.years.reduce((a, b) => a > b ? a : b)}'],
    },
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
