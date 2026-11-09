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
import '../media/unified/unified_media_group.dart';
import '../media/unified/unified_media_source.dart';
import '../media/unified/unified_watch_state.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/unified_catalog/catalog_service.dart';
import '../services/unified_catalog/grouping_service.dart';
import '../services/unified_catalog/source_cursor.dart';
import '../services/unified_catalog/source_preference_store.dart';
import '../services/unified_catalog/unified_catalog_query.dart';
import '../services/unified_catalog/unified_catalog_snapshot.dart';
import '../utils/app_logger.dart';
import '../utils/global_key_utils.dart';
import 'hidden_libraries_provider.dart';
import 'local_library_provider.dart';
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
    LocalLibraryProvider? localLibrary,
    int groupsPerPage = 20,
  }) : _groupsPerPage = groupsPerPage,
       _multiServer = multiServer,
       _libraries = libraries,
       _hiddenLibraries = hiddenLibraries,
       _localLibrary = localLibrary,
       _query = UnifiedCatalogQuery(kind: kind) {
    _localLibrary?.addListener(_onDependenciesChanged);
    // A late server connecting, a library being hidden/unhidden, or the
    // library list itself changing must feed a fresh eligible-library set
    // into the merge (hoofdstuk 27 fase 3: "late-server delta merge"). Guarded
    // inside the handlers to do nothing before [ensureStarted] — matching
    // [DiscoverProvider]'s own "no work for a consumer that never asked" rule.
    _libraries.addListener(_onDependenciesChanged);
    _hiddenLibraries.addListener(_onDependenciesChanged);
    _multiServer.addOnlineServersListener(_onOnlineServersChanged);
  }

  final int _groupsPerPage;
  final MultiServerProvider _multiServer;
  final LibrariesProvider _libraries;
  final HiddenLibrariesProvider _hiddenLibraries;
  final LocalLibraryProvider? _localLibrary;

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
    libraries: {
      for (final l in [...?_localLibrary?.libraries, ..._libraries.libraries]) l.globalKey: l,
    }.values.where((library) => _localLibrary?.canReadLibrary(library) ?? true).toList(),
    kind: _query.kind,
    isServerVisible: (id) =>
        _multiServer.serverManager.isServerVisible(id) ||
        (_localLibrary?.libraries.any((l) => l.serverId == id.value) ?? false),
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
    if (isDisposed) return;
    if (_service == null) return ensureStarted();
    if (_isLoadingMore || _loadState == UnifiedCatalogLoadState.loading) return;
    final restartId = _restartId;
    final service = _service!;
    _isLoadingMore = true;
    safeNotifyListeners();
    try {
      final snapshot = await service.loadMore();
      if (isDisposed || restartId != _restartId) return;
      _snapshot = _preserveOrder ? _inVisibleOrder(snapshot) : snapshot;
    } finally {
      if (!isDisposed && restartId == _restartId) {
        _isLoadingMore = false;
        safeNotifyListeners();
      }
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
    final restartId = _restartId;
    if (isDisposed || service == null) return false;
    if (!service.snapshot.groups.any((g) => g.sources.any((s) => s.sourceKey == globalKey))) return false;
    final MediaItem? updated;
    try {
      updated = await fetchItem();
    } catch (e) {
      // A server error is not news about the item: the row stays as it was.
      appLogger.d('UnifiedCatalogProvider: refresh of $globalKey failed', error: e);
      return false;
    }
    if (updated == null || isDisposed || restartId != _restartId) return false;
    final applied = service.applyUpdatedSourceItem(updated);
    if (applied) {
      _snapshot = _preserveOrder ? _inVisibleOrder(service.snapshot) : service.snapshot;
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

  /// Bumped by every [_restart]. Two run into each other in the ordinary case: a
  /// library joins, this provider restarts on the query it had, and the screen
  /// answers with the query that fits. Only the newest may load and report.
  int _restartId = 0;

  bool _preserveOrder = false;

  Future<void> _restart({bool retainVisible = false}) async {
    if (isDisposed) return;
    final previousCount = retainVisible ? _snapshot.groups.length : 0;
    _preserveOrder = retainVisible;
    final restartId = ++_restartId;
    final eligible = _eligibleLibraries();
    _lastSeenLibraryKeys = _libraryKeys(eligible);
    _lastLocalRevision = _localLibrary?.revision;
    _lastReadBoundaryRevision = _localLibrary?.readBoundaryRevision;
    final service = _service;
    if (service == null) {
      _service = UnifiedCatalogService(
        query: _query,
        libraries: eligible,
        clientFor: _multiServer.serverManager.getClient,
        groupsPerPage: _groupsPerPage,
        preferredSourceKeys: () => _rememberedSourceKeys,
        cachedPage: (library, query) => _localLibrary?.page('${library.serverId}:${library.libraryId}', query),
        cachedExternalIds: (server, id) => _localLibrary?.externalIds(server, id),
      );
    } else {
      service.updateQuery(query: _query, libraries: eligible);
    }
    // isInitialLoading must flip true synchronously with this call — a
    // caller checking it right after `ensureStarted()`/`refresh()` (before
    // awaiting) relies on that, matching every other transient-state provider
    // in this codebase. So the preference read, which needs a await, happens
    // after this point rather than before it.
    _snapshot = retainVisible ? UnifiedCatalogSnapshot(groups: _snapshot.groups) : _service!.snapshot;
    _isLoadingMore = retainVisible;
    _loadState = retainVisible ? UnifiedCatalogLoadState.loaded : UnifiedCatalogLoadState.loading;
    safeNotifyListeners();
    try {
      // Re-read on every restart rather than once at construction: the
      // choices keep being made while this provider lives, and a snapshot
      // frozen at construction would never see a later one (I19/tier 4).
      _rememberedSourceKeys = await SourcePreferenceStore.readAllForActiveScope();
      if (isDisposed || restartId != _restartId) return;
      var snapshot = await _service!.loadMore();
      if (isDisposed || restartId != _restartId) return;
      // Rebuild only the already-visible prefix, using the existing bounded
      // rounds. Never fetch a second complete catalog to refresh a viewport.
      while (retainVisible &&
          snapshot.groups.length < previousCount &&
          !snapshot.isComplete &&
          snapshot.failedLibraryIds.isEmpty) {
        final count = snapshot.groups.length;
        snapshot = await _service!.loadMore();
        if (isDisposed || restartId != _restartId) return;
        if (snapshot.groups.length == count) break;
      }
      _snapshot = retainVisible ? _inVisibleOrder(snapshot) : snapshot;
      _isLoadingMore = false;
      _loadState = UnifiedCatalogLoadState.loaded;
    } catch (_) {
      if (isDisposed || restartId != _restartId) return;
      _isLoadingMore = false;
      if (retainVisible) {
        _snapshot = UnifiedCatalogSnapshot(groups: _snapshot.groups, failedLibraryIds: _lastSeenLibraryKeys);
      }
      // UnifiedCatalogService.loadMore never lets a per-library failure
      // escape — that lands in snapshot.failedLibraryIds instead. This only
      // guards against a genuinely unexpected error, so isInitialLoading
      // never gets stuck true with nothing left to clear it.
      _loadState = UnifiedCatalogLoadState.error;
    }
    safeNotifyListeners();
  }

  /// Content can arrive ahead of the viewport, or change a title's sort
  /// data. Both update cards in their existing positions; only an explicit
  /// refresh/query change applies the new global order. Match memberships as
  /// well as group ids so changed identity facts retain the session's keys.
  UnifiedCatalogSnapshot _inVisibleOrder(UnifiedCatalogSnapshot fresh) {
    // groupId is a session/bucket key, not a unique concrete membership:
    // weak ambiguous editions may legitimately have the same groupId.
    final bySource = {
      for (var index = 0; index < fresh.groups.length; index++)
        for (final source in fresh.groups[index].sources) source.sourceKey: index,
    };
    final keepUnobserved = !fresh.isComplete || fresh.failedLibraryIds.isNotEmpty;
    final groups = <UnifiedMediaGroup>[];
    final published = <int, int>{};
    for (final old in _snapshot.groups) {
      final matches = old.sources.map((source) => bySource[source.sourceKey]).nonNulls.toSet();
      final match =
          matches.where((index) => fresh.groups[index].groupId == old.groupId).firstOrNull ?? matches.firstOrNull;
      if (match == null) {
        if (keepUnobserved) groups.add(old);
        continue;
      }
      final updated = fresh.groups[match];
      final unobserved = keepUnobserved
          ? old.sources.where((source) => !bySource.containsKey(source.sourceKey)).toList()
          : const <UnifiedMediaSource>[];
      if (unobserved.isNotEmpty && updated.groupId != old.groupId) {
        // Only a rematched sibling was observed. Its new group does not
        // establish a new identity for the siblings still outside the prefix.
        groups.add(_withSources(old, unobserved));
        continue;
      }
      final previousIndex = published[match];
      if (previousIndex != null) {
        // Two old groups may now merge. Carry their still-unobserved members
        // into the one published candidate, without publishing it twice.
        final existing = groups[previousIndex];
        groups[previousIndex] = _withSources(existing, [
          ...existing.sources,
          if (keepUnobserved) ...old.sources.where((source) => !bySource.containsKey(source.sourceKey)),
        ]);
        continue;
      }
      final sources = {
        for (final source in old.sources)
          if (keepUnobserved && !bySource.containsKey(source.sourceKey)) source.sourceKey: source,
        // A fresh observation replaces its old item; a member observed in a
        // different candidate is never retained here after a split/rematch.
        for (final source in updated.sources) source.sourceKey: source,
      };
      // Keep the old membership order as the card's continuity anchor.
      final ordered = [
        for (final source in old.sources)
          if (sources.containsKey(source.sourceKey)) sources.remove(source.sourceKey)!,
        ...sources.values,
      ];
      published[match] = groups.length;
      groups.add(_withSources(updated, ordered, groupId: old.groupId));
    }
    for (var index = 0; index < fresh.groups.length; index++) {
      if (!published.containsKey(index)) groups.add(fresh.groups[index]);
    }
    return UnifiedCatalogSnapshot(
      groups: List.unmodifiable(groups),
      failedLibraryIds: fresh.failedLibraryIds,
      initialLoadFailed: groups.isEmpty && fresh.initialLoadFailed,
      isComplete: fresh.isComplete && fresh.failedLibraryIds.isEmpty,
    );
  }

  UnifiedMediaGroup _withSources(UnifiedMediaGroup group, List<UnifiedMediaSource> sources, {String? groupId}) {
    final members = {for (final source in sources) source.sourceKey: source};
    final preferred = members.keys.where(_rememberedSourceKeys.contains).firstOrNull;
    return UnifiedMediaGroup(
      groupId: groupId ?? group.groupId,
      identity: group.identity,
      sources: members.values.toList(),
      representativeSourceKey: selectRepresentativeSource(members.values.toList()),
      watchState: selectRepresentativeWatchState({
        for (final source in members.values) source.sourceKey: source.item,
      }, preferredSourceKey: preferred),
    );
  }

  List<CatalogLibrary> _eligibleLibraries() {
    final eligible = eligibleLibraries;
    final selector = _librarySelector;
    return selector == null ? eligible : eligible.where(selector).toList();
  }

  Set<String> _libraryKeys(List<CatalogLibrary> libraries) => {
    for (final library in libraries) buildGlobalKey(library.serverId, library.libraryId),
  };

  int? _lastLocalRevision;
  int? _lastReadBoundaryRevision;
  void _onDependenciesChanged() {
    if (isDisposed) return;
    final revision = _localLibrary?.revision;
    final boundary = _localLibrary?.readBoundaryRevision;
    final hardBoundary = boundary != _lastReadBoundaryRevision;
    _lastReadBoundaryRevision = boundary;
    if (hardBoundary || _lastLocalRevision != revision) {
      _lastLocalRevision = revision;
      if (_service != null) {
        final sameLibraries = setEquals(_libraryKeys(_eligibleLibraries()), _lastSeenLibraryKeys);
        appLogger.d(
          'catalog restart reason=${hardBoundary ? 'boundary' : 'revision'} '
          'retainVisible=${!hardBoundary && sameLibraries && _snapshot.groups.isNotEmpty} groups=${_snapshot.groups.length}',
        );
        unawaited(_restart(retainVisible: !hardBoundary && sameLibraries && _snapshot.groups.isNotEmpty));
        return;
      }
    }
    _reconcileEligibleLibraries();
  }

  void _onOnlineServersChanged(Set<String> onlineServerIds) => _reconcileEligibleLibraries();

  void _reconcileEligibleLibraries() {
    if (_service == null) return;
    final eligible = _eligibleLibraries();
    final keys = _libraryKeys(eligible);
    if (setEquals(keys, _lastSeenLibraryKeys)) return;
    appLogger.d('catalog restart reason=libraries retainVisible=false groups=${_snapshot.groups.length}');
    unawaited(_restart());
  }

  @override
  void dispose() {
    _restartId++;
    _snapshot = const UnifiedCatalogSnapshot();
    _isLoadingMore = false;
    _loadState = UnifiedCatalogLoadState.initial;
    _localLibrary?.removeListener(_onDependenciesChanged);
    _libraries.removeListener(_onDependenciesChanged);
    _hiddenLibraries.removeListener(_onDependenciesChanged);
    _multiServer.removeOnlineServersListener(_onOnlineServersChanged);
    // E12/hoofdstuk 22: a profile switch "annuleert requests" — this
    // provider is profile-scoped (its `KeyedSubtree` disposes it on switch),
    // so a page fetch still in flight for the profile the user just left
    // must stop rather than keep running against a server nobody is
    // watching anymore. Aborting is enough; nothing here can land in this
    // object's state again once it is disposed.
    _service?.cancelInFlight();
    super.dispose();
  }
}
