/// Fase 3's reactive lifecycle owner for `UnifiedCatalogService` (hoofdstuk 12
/// and 27 fase 3 of docs/tvos-unified-experience.md): wires the headless
/// k-way merge engine to the real app providers and layers the transient
/// `isInitialLoading`/`isLoadingMore` state around `loadMore` that the pure
/// `UnifiedCatalogSnapshot` deliberately does not carry (see that type's own
/// doc comment).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_kind.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/unified_catalog/catalog_service.dart';
import '../services/unified_catalog/source_cursor.dart';
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

  UnifiedCatalogQuery get query => _query;
  UnifiedCatalogSnapshot get snapshot => _snapshot;
  bool get isInitialLoading => _loadState == UnifiedCatalogLoadState.loading;
  bool get isLoadingMore => _isLoadingMore;

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

  /// Applies a new sort/filter/kind, replacing the in-flight merge entirely
  /// (hoofdstuk 12.7: abandons every outstanding fetch via generation IDs).
  Future<void> setQuery(UnifiedCatalogQuery query) {
    _query = query;
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
      );
    } else {
      service.updateQuery(query: _query, libraries: eligible);
    }
    _loadState = UnifiedCatalogLoadState.loading;
    safeNotifyListeners();
    try {
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

  List<CatalogLibrary> _eligibleLibraries() => eligibleCatalogLibraries(
    libraries: _libraries.libraries,
    kind: _query.kind,
    isServerVisible: _multiServer.serverManager.isServerVisible,
    hiddenLibraryKeys: _hiddenLibraries.hiddenLibraryKeys,
  );

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
