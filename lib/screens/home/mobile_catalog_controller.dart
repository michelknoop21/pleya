/// What the catalogue screen holds that the merge engine deliberately does
/// not: the sort and filters the user picked, the filter values the servers
/// offer, and which of those filters the participating backends can actually
/// execute. iOS Unified 2026 fase 3.
///
/// `UnifiedCatalogProvider` owns the merge and its snapshot, and stays free of
/// view settings on purpose — it takes a finished [UnifiedCatalogQuery] and a
/// library restriction, and asks no questions about where they came from. This
/// is where they come from.
///
/// ## The order the four steps have to run in
///
/// It is not arbitrary, and getting it backwards produces a filter panel that
/// lies. A source restriction decides which libraries take part; the
/// participating libraries decide which backends are in the mix; the backends
/// decide which item filters can be honoured; and only then can the stored
/// preferences be turned into a query. Running capabilities *before* the
/// restriction would mean one Pleya Server library suppressed the genre filter
/// permanently, when excluding that server is precisely how a user gets it back
/// (`unified_catalog_filters.dart` says so in its own doc).
///
/// ## Why the stored selection is never overwritten with the constrained one
///
/// Same reason, one step further. `constrainedTo` is applied when building the
/// query and when counting active filters, never when writing back: a genre
/// choice suppressed by today's source mix has to survive, or narrowing the
/// sources would not bring it back — it would find nothing left to restore.
/// The one thing that *is* written back is a server or library that no longer
/// exists ([UnifiedCatalogFilterSelection.withKnownSources]), because that key
/// has no row left in the panel to untick it with.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../media/ids.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../providers/unified_catalog_provider.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_catalog_query_store.dart';
import '../../services/unified_catalog/unified_filter_options.dart';
import '../../utils/global_key_utils.dart';

class MobileCatalogController extends ChangeNotifier {
  MobileCatalogController({required this.catalog, required this.kind, required this.clientFor});

  /// The merge this controller feeds. Public because the screen reads it for
  /// the snapshot and the loading flags, and a test needs to hand in a fake.
  final UnifiedCatalogProvider catalog;

  final MediaKind kind;

  /// Resolves a client per server for the filter-option load.
  final MediaServerClient? Function(ServerId serverId) clientFor;

  UnifiedCatalogPreferences _preferences = UnifiedCatalogPreferences.defaults;
  UnifiedFilterOptions _options = UnifiedFilterOptions.empty;
  bool _isReady = false;
  bool _isDisposed = false;

  UnifiedCatalogSort get sort => _preferences.sort;

  /// The selection as stored — what the panel ticks. See this library's doc for
  /// why this is not the constrained one.
  UnifiedCatalogFilterSelection get selection => _preferences.filters;

  UnifiedFilterOptions get options => _options;

  /// False until the stored preferences have been read and the first query
  /// handed to the merge. The screen shows its loading state through this
  /// window rather than a catalogue sorted by something the user did not pick.
  bool get isReady => _isReady;

  /// Every library this catalogue could draw from, restriction or not — what
  /// the panel's Servers and Libraries sections list. A server the user
  /// excluded still has to appear, with its tick off, or there is no way back
  /// to it.
  List<CatalogLibrary> get eligibleLibraries => catalog.eligibleLibraries;

  /// Which filters the backends behind the *participating* libraries can
  /// execute. Recomputed on every read rather than cached: a late server
  /// joining the merge changes the answer, and the provider already restarts
  /// itself when that happens.
  UnifiedFilterCapabilities get capabilities =>
      unifiedFilterCapabilitiesFor(_participatingLibraries().map((l) => l.backend));

  /// How many sources the catalogue is narrowed to, or null when it is not
  /// narrowed at all. Drives the sources control's label.
  ///
  /// Counts *libraries*, not servers, because that is what the merge actually
  /// runs over: picking one server with three libraries and picking those three
  /// libraries are the same catalogue, and one label has to be true for both.
  int? get restrictedSourceCount {
    if (!_preferences.filters.restrictsSources) return null;
    return _participatingLibraries().length;
  }

  /// Fields narrowing the items right now — the badge on the filters control
  /// and the "N active" in the panel's header.
  int get activeFilterCount => _preferences.filters.constrainedTo(capabilities).activeCount;

  /// Reads the stored setup, drops sources that no longer exist, and starts the
  /// merge. Safe to call more than once; only the first call does anything.
  Future<void> start() async {
    if (_isReady) return;
    final stored = await UnifiedCatalogQueryStore.read(kind);
    if (_isDisposed) return;
    _preferences = stored.copyWith(filters: _withKnownSources(stored.filters));
    _isReady = true;
    // Written back only when the pruning actually changed something, so a
    // normal open does not touch storage.
    if (_preferences.filters != stored.filters) unawaited(_persist());
    notifyListeners();
    await _applyToCatalog();
    unawaited(_loadOptions());
  }

  /// Applies a new sort and restarts the merge. No-op when nothing changed, so
  /// re-picking the current sort does not scroll the grid back to the top.
  Future<void> setSort(UnifiedCatalogSort sort) async {
    if (sort == _preferences.sort) return;
    _preferences = _preferences.copyWith(sort: sort);
    notifyListeners();
    unawaited(_persist());
    await _applyToCatalog();
  }

  /// Applies a selection from the filter panel and restarts the merge.
  ///
  /// Reloads the filter *values* too when the source restriction changed: the
  /// genres on offer are the union of what the participating libraries report,
  /// so excluding a server can legitimately shorten that list.
  Future<void> setFilters(UnifiedCatalogFilterSelection selection) async {
    final pruned = _withKnownSources(selection);
    if (pruned == _preferences.filters) return;
    // setEquals, not `!=`: Dart's Set has no value equality, so `!=` here
    // would be identity and would report a change on every apply — reloading
    // the filter values each time somebody picked a genre.
    final sourcesChanged =
        !setEquals(pruned.serverIds, _preferences.filters.serverIds) ||
        !setEquals(pruned.libraryKeys, _preferences.filters.libraryKeys);
    _preferences = _preferences.copyWith(filters: pruned);
    notifyListeners();
    unawaited(_persist());
    await _applyToCatalog();
    if (sourcesChanged) unawaited(_loadOptions());
  }

  Future<void> clearFilters() => setFilters(UnifiedCatalogFilterSelection.empty);

  List<CatalogLibrary> _participatingLibraries() =>
      catalog.eligibleLibraries.where(_preferences.filters.selects).toList();

  UnifiedCatalogFilterSelection _withKnownSources(UnifiedCatalogFilterSelection selection) {
    final eligible = catalog.eligibleLibraries;
    // An empty catalogue prunes nothing. Before any server has connected,
    // `eligibleLibraries` is empty for a reason that has nothing to do with the
    // user's choices, and pruning against it would silently delete a whole
    // stored selection on a cold, offline start.
    if (eligible.isEmpty) return selection;
    return selection.withKnownSources(
      knownServerIds: {for (final library in eligible) library.serverId.value},
      knownLibraryKeys: {for (final library in eligible) buildGlobalKey(library.serverId, library.libraryId)},
    );
  }

  Future<void> _applyToCatalog() {
    final selection = _preferences.filters;
    return catalog.setQuery(
      buildUnifiedCatalogQuery(kind: kind, preferences: _preferences, capabilities: capabilities),
      // Null rather than a selector that lets everything through: the provider
      // documents null as "no restriction", and a server appearing later then
      // joins the merge instead of being measured against a list built before
      // it existed.
      librarySelector: selection.restrictsSources ? selection.selects : null,
    );
  }

  Future<void> _persist() => UnifiedCatalogQueryStore.write(kind, _preferences);

  Future<void> _loadOptions() async {
    final loaded = await loadUnifiedFilterOptions(libraries: _participatingLibraries(), clientFor: clientFor);
    if (_isDisposed) return;
    _options = loaded;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
