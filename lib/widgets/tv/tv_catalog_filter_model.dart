/// What a catalog filter session knows, apart from how it is drawn: the draft,
/// the values the servers offer, and which categories this source set can
/// execute.
///
/// Lifted out of `tv_catalog_filter_panel.dart` unchanged when A-06c needed the
/// same session in a side panel. Two drawings of one session have to agree on
/// what a category is called, what is left out of the rail and when a choice
/// counts, and two copies of that rule would drift.
///
/// **Nothing here applies anything.** Every toggle changes the draft, and the
/// caller hands [draft] on when the viewer chooses Apply (hoofdstuk 10.6).
library;

import 'package:flutter/foundation.dart';

import '../../i18n/strings.g.dart';
import '../../media/library_menu_definition.dart';
import '../../media/media_server_client.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_filter_options.dart';
import '../../utils/global_key_utils.dart';
import '../../utils/home_custom_row_labels.dart';

/// Which category the panel opens on, and — since every category is one of
/// these — what the rail is a list of.
enum TvCatalogFilterSection {
  status,
  genre,
  audioLanguage,
  year,
  decade,
  contentRating,
  servers,
  libraries,
  serverCategory,
}

/// Rail order, which is hoofdstuk 10.6's listing verbatim: "Status; Genre;
/// Jaar; Servers; Bibliotheken".
///
/// The first build ran the other way round — the two source categories at the
/// top, because they are the only ones no backend can take away, so anything
/// omittable fell off the bottom and the top of the rail never moved. That is a
/// real property and this order gives it up. It was still the wrong trade:
/// leading with Servers and Bibliotheken leads with infrastructure, and those
/// are administration words. Someone narrowing a wall of posters wants
/// "Unwatched", and in that order it was fifth of five — while the Filters
/// capsule opens the panel on Status, so the default state put the cursor at the
/// bottom of the rail with four skipped labels above it. A settings window is
/// exactly what that reads as.
const List<TvCatalogFilterSection> _railOrder = [
  TvCatalogFilterSection.status,
  TvCatalogFilterSection.genre,
  TvCatalogFilterSection.audioLanguage,
  TvCatalogFilterSection.year,
  TvCatalogFilterSection.contentRating,
  TvCatalogFilterSection.servers,
  TvCatalogFilterSection.libraries,
];

/// The side panel's categories, from the shared menu definition. Status is not
/// among them: there it is the quick choices above the divider.
TvCatalogFilterSection _sectionOf(LibraryFilterCategory category) => switch (category) {
  LibraryFilterCategory.genre => TvCatalogFilterSection.genre,
  LibraryFilterCategory.year => TvCatalogFilterSection.year,
  LibraryFilterCategory.decade => TvCatalogFilterSection.decade,
  LibraryFilterCategory.contentRating => TvCatalogFilterSection.contentRating,
  LibraryFilterCategory.audioLanguage => TvCatalogFilterSection.audioLanguage,
  LibraryFilterCategory.servers => TvCatalogFilterSection.servers,
  LibraryFilterCategory.libraries => TvCatalogFilterSection.libraries,
};

/// One row's data, so a category's rows are described once and rendered once.
class TvCatalogFilterRowSpec {
  const TvCatalogFilterRowSpec({
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.secondary,
  });

  final String label;
  final String? secondary;
  final bool isSelected;
  final VoidCallback onPressed;
}

String tvCatalogFilterSectionLabel(TvCatalogFilterSection section) => switch (section) {
  TvCatalogFilterSection.status => t.unifiedCatalog.filters.status,
  TvCatalogFilterSection.genre => t.unifiedCatalog.filters.genre,
  TvCatalogFilterSection.audioLanguage => t.libraries.filterCategories.audioLanguage,
  TvCatalogFilterSection.year => t.unifiedCatalog.filters.year,
  TvCatalogFilterSection.decade => t.unifiedCatalog.filters.decade,
  TvCatalogFilterSection.contentRating => t.unifiedCatalog.filters.contentRating,
  TvCatalogFilterSection.servers => t.unifiedCatalog.filters.servers,
  TvCatalogFilterSection.libraries => t.unifiedCatalog.filters.libraries,
  // Named by the server: see TvCatalogFilterModel.serverCategories.
  TvCatalogFilterSection.serverCategory => '',
};

class TvCatalogFilterModel extends ChangeNotifier {
  TvCatalogFilterModel({
    required UnifiedCatalogFilterSelection selection,
    required this.capabilities,
    required this.libraries,
    this.clientFor,
  }) : _draft = selection;

  /// What the source set can execute. Assignable: a panel stays up while the
  /// sources behind it change.
  UnifiedFilterCapabilities capabilities;

  /// Every eligible library, restricted or not — a server the user has excluded
  /// still needs a row, or there is no way back to it.
  List<CatalogLibrary> libraries;

  /// Null in tests that only exercise the source categories, which need no
  /// network call at all.
  final MediaServerClient? Function(String serverId)? clientFor;

  UnifiedCatalogFilterSelection _draft;
  UnifiedFilterOptions _options = UnifiedFilterOptions.empty;
  bool _isLoadingOptions = false;
  bool _disposed = false;

  UnifiedCatalogFilterSelection get draft => _draft;
  bool get isLoadingOptions => _isLoadingOptions;

  void clearAll() => _setDraft(UnifiedCatalogFilterSelection.empty);

  void _setDraft(UnifiedCatalogFilterSelection next) {
    _draft = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// The category to open on, or the first available one when the caller asked
  /// for a category this source set cannot execute.
  ///
  /// Falling back rather than honouring the request is the whole point of
  /// omitting unavailable categories: opening on a category that is not in the
  /// rail would put the initial focus on nothing.
  TvCatalogFilterSection resolveInitialSection(TvCatalogFilterSection wanted) {
    final available = _sections(placeholders: false);
    return available.contains(wanted) ? wanted : available.first;
  }

  /// Which categories this source set can actually execute.
  ///
  /// Servers and Libraries are unconditional — they are executed by leaving a
  /// cursor out of the merge, not by asking a backend to filter — so the rail
  /// is never empty and [resolveInitialSection] always has something to fall
  /// back to.
  List<TvCatalogFilterSection> get availableSections => _sections(placeholders: _isLoadingOptions);

  /// The categories of the side panel, in the order of the menu definition.
  List<TvCatalogFilterSection> get menuSections => [
    for (final category in libraryFilterCategoryMenu)
      if (_supports(_sectionOf(category)) && (_isLoadingOptions || _hasChoices(_sectionOf(category))))
        _sectionOf(category),
  ];

  /// The quick choices this source set can run, in the menu's order.
  List<LibraryQuickFilter> get quickFilters => [
    for (final filter in libraryQuickFilterMenu)
      if (capabilities.supportsQuickFilter(filter)) filter,
  ];

  /// The booleans the servers list that the definition has no row for, at the
  /// bottom of the quick choices with the label the server gives them.
  List<LibraryServerFilter> get extraQuickFilters => capabilities.extraFilters;

  /// The non-boolean categories the servers list beyond Genre, Jaar, Decennium,
  /// Leeftijd and Audiotaal, after the categories of the definition.
  List<LibraryServerFilter> get serverCategories => capabilities.serverCategories;

  final Map<String, List<UnifiedFilterValue>> _serverValues = {};
  final Set<String> _serverValuesRequested = {};

  /// The rows of the server category [key]: empty until [loadServerCategory].
  List<TvCatalogFilterRowSpec> rowsForServerCategory(String key) => [
    for (final value in _serverValues[key] ?? const <UnifiedFilterValue>[])
      TvCatalogFilterRowSpec(
        label: value.label,
        isSelected: _draft.serverFilters[key]?.contains(value.value) ?? false,
        onPressed: () => _toggleServerValue(key, value.value),
      ),
  ];

  int activeCountForServerCategory(String key) => _draft.serverFilters[key]?.length ?? 0;

  bool isLoadingServerCategory(String key) => _serverValuesRequested.contains(key) && !_serverValues.containsKey(key);

  /// Fetches the values of [key] once, when the category is opened.
  Future<void> loadServerCategory(String key) async {
    final clientFor = this.clientFor;
    if (clientFor == null || !_serverValuesRequested.add(key)) return;
    notifyListeners();
    final values = await loadServerCategoryValues(
      libraries: libraries,
      clientFor: (serverId) => clientFor(serverId.value),
      filterKey: key,
    );
    if (_disposed) return;
    _serverValues[key] = values;
    notifyListeners();
  }

  void _toggleServerValue(String key, String value) {
    final current = {..._draft.serverFilters};
    final values = _toggled(current[key] ?? const <String>{}, value);
    if (values.isEmpty) {
      current.remove(key);
    } else {
      current[key] = values;
    }
    _setDraft(_draft.copyWith(serverFilters: current));
  }

  List<TvCatalogFilterSection> _sections({required bool placeholders}) => [
    for (final section in _railOrder)
      if (_supports(section) && (placeholders || _hasChoices(section))) section,
  ];

  /// Whether a category is missing because a backend cannot execute it, which
  /// is what the panel's note explains. A category hidden for lack of values is
  /// not "unavailable for these sources", and saying so would send the user
  /// looking for a server to exclude.
  bool get hasUnsupportedSections => _railOrder.any((section) => !_supports(section));

  /// Audiotaal and Leeftijd stay in the rail while the values load, so the
  /// rail does not grow under the eye (a focused row keeps its place), and go
  /// only once the servers have named no value at all. Jellyfin's `/Items/Filters` has no audio languages at all, so
  /// a Jellyfin-only catalog would otherwise show a category with nothing in
  /// it. Genre and Jaar keep their row and say "nothing to choose from": those
  /// every library has, and an empty one means something is wrong.
  bool _hasChoices(TvCatalogFilterSection section) => switch (section) {
    TvCatalogFilterSection.audioLanguage => _options.audioLanguages.isNotEmpty,
    TvCatalogFilterSection.contentRating => _options.contentRatings.isNotEmpty,
    _ => true,
  };

  bool _supports(TvCatalogFilterSection section) => switch (section) {
    TvCatalogFilterSection.status => capabilities.supportsWatchFilter,
    TvCatalogFilterSection.genre ||
    TvCatalogFilterSection.audioLanguage ||
    TvCatalogFilterSection.year ||
    TvCatalogFilterSection.decade ||
    TvCatalogFilterSection.contentRating => capabilities.supportsMetadataFilters,
    TvCatalogFilterSection.servers || TvCatalogFilterSection.libraries || TvCatalogFilterSection.serverCategory => true,
  };

  /// Genre and year values, fetched behind an already-open panel.
  ///
  /// The panel does not wait for them: Status, Servers and Libraries need
  /// nothing from a server, and blocking the whole modal on a fan-out would put
  /// a spinner in front of three categories that were ready immediately.
  Future<void> loadOptions() async {
    final clientFor = this.clientFor;
    if (clientFor == null) return;
    _isLoadingOptions = true;
    notifyListeners();
    final options = await loadUnifiedFilterOptions(
      libraries: libraries,
      clientFor: (serverId) => clientFor(serverId.value),
    );
    if (_disposed) return;
    _options = options.withStoredContentRatings(_draft.officialRatings);
    _isLoadingOptions = false;
    notifyListeners();
  }

  /// [section], or the nearest available row above it once it has gone.
  TvCatalogFilterSection survivingSection(TvCatalogFilterSection section) {
    final available = availableSections;
    if (available.contains(section)) return section;
    return _railOrder.take(_railOrder.indexOf(section)).lastWhere(available.contains, orElse: () => available.first);
  }

  void _toggleGenre(String genre) => _setDraft(_draft.copyWith(genres: _toggled(_draft.genres, genre)));

  void _toggleAudioLanguage(String language) =>
      _setDraft(_draft.copyWith(audioLanguages: _toggled(_draft.audioLanguages, language)));

  void _toggleContentRating(UnifiedFilterValue rating) => _setDraft(
    _draft.copyWith(
      officialRatings: toggleContentRating(_draft.officialRatings, label: rating.label, value: rating.value),
    ),
  );

  void _toggleYear(int year) => _setDraft(_draft.copyWith(years: _toggled(_draft.years, year)));

  void _toggleDecade(int decade) => _setDraft(_draft.copyWith(decades: _toggled(_draft.decades, decade)));

  /// The decades the servers' years fall in, newest first.
  List<int> get _decades => ({for (final year in _options.years) year - year % 10}.toList()..sort()).reversed.toList();

  void _toggleServer(String serverId) => _setDraft(_draft.copyWith(serverIds: _toggled(_draft.serverIds, serverId)));

  void _toggleLibrary(String key) => _setDraft(_draft.copyWith(libraryKeys: _toggled(_draft.libraryKeys, key)));

  void _setWatchState(UnifiedWatchFilter value) => _setDraft(_draft.copyWith(watchState: value));

  static Set<T> _toggled<T>(Set<T> current, T value) =>
      current.contains(value) ? ({...current}..remove(value)) : {...current, value};

  /// Distinct servers behind the eligible libraries, in a stable order.
  ///
  /// Ordered by name, then by id: server names are user-editable and can
  /// collide (edge case A7), so a name-only sort would let two servers swap
  /// rows between openings.
  List<({String id, String name})> get _servers {
    final byId = <String, String>{};
    for (final library in libraries) {
      byId.putIfAbsent(library.serverId.value, () => library.serverName);
    }
    final servers = [for (final entry in byId.entries) (id: entry.key, name: entry.value)];
    servers.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return servers;
  }

  /// The rows of one category, as data.
  List<TvCatalogFilterRowSpec> rowsFor(TvCatalogFilterSection section) => switch (section) {
    // Only the states every participating backend executes: Bekeken is
    // Jellyfin-only and disappears as soon as a Plex library takes part.
    TvCatalogFilterSection.status => [
      for (final state in UnifiedWatchFilter.values)
        if (capabilities.supportsWatchState(state))
          TvCatalogFilterRowSpec(
            label: unifiedWatchFilterLabel(state),
            isSelected: _draft.watchState == state,
            onPressed: () => _setWatchState(state),
          ),
    ],
    TvCatalogFilterSection.genre => [
      for (final genre in _options.genres)
        TvCatalogFilterRowSpec(
          label: genre,
          isSelected: _draft.genres.contains(genre),
          onPressed: () => _toggleGenre(genre),
        ),
    ],
    TvCatalogFilterSection.audioLanguage => [
      for (final language in _options.audioLanguages)
        TvCatalogFilterRowSpec(
          label: language.label,
          isSelected: _draft.audioLanguages.contains(language.value),
          onPressed: () => _toggleAudioLanguage(language.value),
        ),
    ],
    TvCatalogFilterSection.year => [
      for (final year in _options.years)
        TvCatalogFilterRowSpec(
          label: '$year',
          isSelected: _draft.years.contains(year),
          onPressed: () => _toggleYear(year),
        ),
    ],
    TvCatalogFilterSection.decade => [
      for (final decade in _decades)
        TvCatalogFilterRowSpec(
          label: '$decade',
          isSelected: _draft.decades.contains(decade),
          onPressed: () => _toggleDecade(decade),
        ),
    ],
    TvCatalogFilterSection.contentRating => [
      for (final rating in _options.contentRatings)
        TvCatalogFilterRowSpec(
          label: rating.label,
          isSelected: isContentRatingSelected(_draft.officialRatings, rating.label),
          onPressed: () => _toggleContentRating(rating),
        ),
    ],
    TvCatalogFilterSection.servers => [
      for (final server in _servers)
        TvCatalogFilterRowSpec(
          label: server.name,
          isSelected: _draft.serverIds.contains(server.id),
          onPressed: () => _toggleServer(server.id),
        ),
    ],
    TvCatalogFilterSection.libraries => [
      for (final library in libraries)
        TvCatalogFilterRowSpec(
          label: library.libraryTitle,
          // The server, because two libraries called "Movies" on two servers
          // are otherwise the same row twice.
          secondary: library.serverName,
          isSelected: _draft.libraryKeys.contains(buildGlobalKey(library.serverId, library.libraryId)),
          onPressed: () => _toggleLibrary(buildGlobalKey(library.serverId, library.libraryId)),
        ),
    ],
    TvCatalogFilterSection.serverCategory => const [],
  };

  /// How many choices a category currently carries, for its count chip.
  ///
  /// Status counts as one when it is narrowing and zero when it is not — "All"
  /// is the absence of a filter, and a chip reading 1 on an unfiltered category
  /// is the kind of detail that makes a panel feel like a form.
  int activeCountFor(TvCatalogFilterSection section) => switch (section) {
    TvCatalogFilterSection.status => _draft.watchState == UnifiedWatchFilter.all ? 0 : 1,
    TvCatalogFilterSection.genre => _draft.genres.length,
    TvCatalogFilterSection.audioLanguage => _draft.audioLanguages.length,
    TvCatalogFilterSection.year => _draft.years.length,
    TvCatalogFilterSection.decade => _draft.decades.length,
    TvCatalogFilterSection.contentRating => contentRatingLabels(_draft.officialRatings).length,
    TvCatalogFilterSection.servers => _draft.serverIds.length,
    TvCatalogFilterSection.libraries => _draft.libraryKeys.length,
    TvCatalogFilterSection.serverCategory => 0,
  };
}
