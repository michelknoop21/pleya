/// Fase 3's reactive lifecycle owner for `UnifiedCatalogService` (hoofdstuk 12
/// and 27 fase 3 of docs/tvos-unified-experience.md): wires the headless
/// k-way merge engine to the real app providers and layers the transient
/// `isInitialLoading`/`isLoadingMore` state around `loadMore` that the pure
/// `UnifiedCatalogSnapshot` deliberately does not carry (see that type's own
/// doc comment).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/unified_catalog/catalog_service.dart';
import '../services/unified_catalog/source_cursor.dart';
import '../services/unified_catalog/source_preference_store.dart';
import '../services/unified_catalog/unified_catalog_query.dart';
import '../services/unified_catalog/unified_catalog_snapshot.dart';
import '../utils/global_key_utils.dart';
import 'hidden_libraries_provider.dart';
import 'libraries_provider.dart';
import 'multi_server_provider.dart';

enum UnifiedCatalogLoadState { initial, loading, loaded, error }

/// Lives inside the profile-keyed provider subtree (`ProfileSessionScreen`),
/// alongside `LibrariesProvider`/`HiddenLibrariesProvider`/`MultiServerProvider`
/// — unified state is profile-scoped (hoofdstuk 22: "dispose unified
/// providers" on profile switch), so that subtree's `KeyedSubtree` is this
/// provider's entire disposal mechanism; there is no manual teardown to wire.
///
/// Lazy by construction, matching [LibrariesProvider]'s `initialize`-then-load
/// split: building this provider starts no catalog load and opens no
/// connection. A consumer opts in by calling [ensureStarted] (or [loadMore]/
/// [refresh]/[setQuery] directly, each of which starts the merge if it hasn't
/// already). Registering this provider in the profile tree before any
/// Films/Series screen exists to read it is therefore safe — construction
/// alone does no work.
class UnifiedCatalogProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  UnifiedCatalogProvider({
    required MultiServerProvider multiServer,
    required LibrariesProvider libraries,
    required HiddenLibrariesProvider hiddenLibraries,
    required MediaKind kind,
  }) : _multiServer = multiServer,
       _libraries = libraries,
       _hiddenLibraries = hiddenLibraries,
       _query = UnifiedCatalogQuery(kind: kind) {
    // A late server connecting, a library being hidden/unhidden, or the
    // library list itself changing must feed a fresh eligible-library set
    // into the merge (hoofdstuk 27 fase 3: "late-server delta merge"). Guarded
    // inside the handlers to do nothing before [ensureStarted] — matching
    // [DiscoverProvider]'s own "no work for a consumer that never asked" rule.
    _libraries.addListener(_onDependenciesChanged);
    _hiddenLibraries.addListener(_onDependenciesChanged);
    _multiServer.addOnlineServersListener(_onOnlineServersChanged);
  }

  final MultiServerProvider _multiServer;
  final LibrariesProvider _libraries;
  final HiddenLibrariesProvider _hiddenLibraries;

  UnifiedCatalogQuery _query;
  UnifiedCatalogService? _service;
  UnifiedCatalogSnapshot _snapshot = const UnifiedCatalogSnapshot();
  UnifiedCatalogLoadState _loadState = UnifiedCatalogLoadState.initial;
  bool _isLoadingMore = false;
  Set<String> _lastSeenLibraryKeys = const {};

  /// The profile's remembered source choices, re-read on every restart and
  /// handed to the merge for hoofdstuk 13.2's tier 4. Held here rather than
  /// inside the service because the service is built once and then reused
  /// across query changes, while the choices keep being made.
  Set<String> _rememberedSourceKeys = const {};

  /// The caller's source restriction; see [setQuery]. Held across reconciles so
  /// a server coming online under an active "only this server" filter is
  /// evaluated against that filter rather than silently joining the merge.
  bool Function(CatalogLibrary library)? _librarySelector;

  UnifiedCatalogQuery get query => _query;
  UnifiedCatalogSnapshot get snapshot => _snapshot;

  /// Every library this catalog *could* draw from — visible server, visible
  /// library, right kind — before the caller's own restriction.
  ///
  /// This is what a source filter panel lists: a server the user has excluded
  /// still has to appear, with its tick off, or there is no way back to it.
  List<CatalogLibrary> get eligibleLibraries => eligibleCatalogLibraries(
    libraries: _libraries.libraries,
    kind: _query.kind,
    isServerVisible: _multiServer.serverManager.isServerVisible,
    hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
  );

  /// The libraries actually taking part in the current merge — [eligibleLibraries]
  /// with [setQuery]'s `librarySelector` applied.
  ///
  /// Read by the filter surface to decide which *item* filters may be offered
  /// at all: a filter is a promise about the whole result list, so it can only
  /// be offered when every backend behind these libraries executes it. Because
  /// this follows the restriction rather than preceding it, excluding a backend
  /// that cannot filter is enough to get those filters back.
  List<CatalogLibrary> get participatingLibraries => _eligibleLibraries();
  bool get isInitialLoading => _loadState == UnifiedCatalogLoadState.loading;
  bool get isLoadingMore => _isLoadingMore;

  /// Whether the last restart ended in the unexpected-error branch of
  /// [_restart].
  ///
  /// Distinct from `snapshot.initialLoadFailed`, which is the merge engine
  /// reporting that every participating library failed. This one covers the
  /// case that never reaches the engine at all — no library was eligible to be
  /// asked, or something threw outside the per-library error handling — and a
  /// surface showing a full-page error needs both, because either one leaves it
  /// with nothing to draw.
  bool get loadFailed => _loadState == UnifiedCatalogLoadState.error;

  /// Whether [ensureStarted] (or an equivalent) has been called at least
  /// once — the one bit that distinguishes "never asked" from "asked, still
  /// loading" for a consumer that only wants to know whether to opt in.
  bool get hasStarted => _service != null;

  /// Starts the merge for the current query if it hasn't already, then loads
  /// the first page. No-op once started — call [refresh] for an explicit
  /// reload of the same query. This is the one place a consumer opts this
  /// provider into doing network work.
  Future<void> ensureStarted() {
    if (_service != null) return Future<void>.value();
    return _restart();
  }

  /// Advances the merge for the current query — the reactive counterpart of
  /// `UnifiedCatalogService.loadMore`, with [isLoadingMore] layered around it.
  /// Starts the merge first if [ensureStarted] was never called.
  Future<void> loadMore() async {
    if (_service == null) return ensureStarted();
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    safeNotifyListeners();
    try {
      _snapshot = await _service!.loadMore();
    } finally {
      _isLoadingMore = false;
      safeNotifyListeners();
    }
  }

  /// Re-runs the current query from scratch — hoofdstuk 12.5's sanctioned
  /// reorder path, and the pull-to-refresh / explicit-retry entry point.
  Future<void> refresh() => _restart();

  /// Re-reads one concrete item and folds it back into whichever group holds
  /// it, without re-paging (I19).
  ///
  /// [fetchItem] does the network call only when a service is running and the
  /// item is actually part of this merge — a lazy supplier rather than a
  /// pre-fetched [MediaItem], so a catalog nobody has opened yet, or one whose
  /// merge never popped this item, costs nothing. Returns whether the update
  /// landed; a caller that gets false has nothing to redraw here and should
  /// fall back to whatever its own surface already does for "unknown to this
  /// provider" (a hero pool, a different projection).
  Future<bool> refreshItem(String globalKey, Future<MediaItem?> Function() fetchItem) async {
    final service = _service;
    if (service == null) return false;
    if (!service.snapshot.groups.any((g) => g.sources.any((s) => s.sourceKey == globalKey))) return false;
    final updated = await fetchItem();
    if (updated == null || isDisposed) return false;
    final applied = service.applyUpdatedSourceItem(updated);
    if (applied) {
      _snapshot = service.snapshot;
      safeNotifyListeners();
    }
    return applied;
  }

  /// Applies a new sort/filter/kind, replacing the in-flight merge entirely
  /// (hoofdstuk 12.7: abandons every outstanding fetch via generation IDs).
  ///
  /// [librarySelector] narrows which of the eligible libraries take part —
  /// hoofdstuk 10.4's server and library filters. They are executed here, by
  /// leaving a cursor out of the merge, rather than by dropping items after it:
  /// an excluded server is then never asked at all, and — the reason it has to
  /// work this way — a page that fetched enough items for twenty groups still
  /// produces twenty, instead of three plus a hole in the paging count.
  ///
  /// Passing null clears any previous restriction, so "Alle bronnen" is the
  /// absence of a selector rather than a list that has to be kept in step with
  /// the server registry.
  Future<void> setQuery(UnifiedCatalogQuery query, {bool Function(CatalogLibrary library)? librarySelector}) {
    _query = query;
    _librarySelector = librarySelector;
    return _restart();
  }

  Future<void> _restart() async {
    final eligible = _eligibleLibraries();
    _lastSeenLibraryKeys = _libraryKeys(eligible);
    final service = _service;
    if (service == null) {
      _service = UnifiedCatalogService(
        query: _query,
        libraries: eligible,
        clientFor: _multiServer.serverManager.getClient,
        preferredSourceKeys: () => _rememberedSourceKeys,
      );
    } else {
      service.updateQuery(query: _query, libraries: eligible);
    }
    // isInitialLoading must flip true synchronously with this call — a
    // caller checking it right after `ensureStarted()`/`refresh()` (before
    // awaiting) relies on that, matching every other transient-state provider
    // in this codebase. So the preference read, which needs a await, happens
    // after this point rather than before it.
    _loadState = UnifiedCatalogLoadState.loading;
    safeNotifyListeners();
    try {
      // Re-read on every restart rather than once at construction: the
      // choices keep being made while this provider lives, and a snapshot
      // frozen at construction would never see a later one (I19/tier 4).
      _rememberedSourceKeys = await SourcePreferenceStore.readAllForActiveScope();
      _snapshot = await _service!.loadMore();
      _loadState = UnifiedCatalogLoadState.loaded;
    } catch (_) {
      // UnifiedCatalogService.loadMore never lets a per-library failure
      // escape — that lands in snapshot.failedLibraryIds instead. This only
      // guards against a genuinely unexpected error, so isInitialLoading
      // never gets stuck true with nothing left to clear it.
      _loadState = UnifiedCatalogLoadState.error;
    }
    safeNotifyListeners();
  }

  List<CatalogLibrary> _eligibleLibraries() {
    final eligible = eligibleLibraries;
    final selector = _librarySelector;
    return selector == null ? eligible : eligible.where(selector).toList();
  }

  Set<String> _libraryKeys(List<CatalogLibrary> libraries) => {
    for (final library in libraries) buildGlobalKey(library.serverId, library.libraryId),
  };

  void _onDependenciesChanged() => _reconcileEligibleLibraries();

  void _onOnlineServersChanged(Set<String> onlineServerIds) => _reconcileEligibleLibraries();

  void _reconcileEligibleLibraries() {
    if (_service == null) return;
    final eligible = _eligibleLibraries();
    final keys = _libraryKeys(eligible);
    if (setEquals(keys, _lastSeenLibraryKeys)) return;
    unawaited(_restart());
  }

  @override
  void dispose() {
    _libraries.removeListener(_onDependenciesChanged);
    _hiddenLibraries.removeListener(_onDependenciesChanged);
    _multiServer.removeOnlineServersListener(_onOnlineServersChanged);
    super.dispose();
  }
}
