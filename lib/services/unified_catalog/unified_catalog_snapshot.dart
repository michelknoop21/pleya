/// Settled-state result exposed by `UnifiedCatalogService.snapshot` after
/// each merge round (hoofdstuk 12 and 27 fase 3 of
/// docs/tvos-unified-experience.md).
///
/// Deliberately carries no transient UI-loading flags (`isInitialLoading`,
/// `isLoadingMore`) — this type is fase 3's own, produced by the headless
/// k-way merge engine, which never has a reason to report "loading" about
/// itself. That reactive state belongs to whatever wraps this snapshot in a
/// `ChangeNotifier` around each `loadMore` call, which is
/// `unified_catalog_provider.dart`'s job (deferred): adding those fields here
/// now, before anything sets them, would be exactly the kind of
/// later-phase placeholder fase 1 already established this project avoids
/// (see `UnifiedMediaGroup`'s own `coverage` field history).
library;

import '../../media/unified/unified_media_group.dart';

class UnifiedCatalogSnapshot {
  /// Every group produced so far, in final display order. Recomputed
  /// wholesale each round (`groupUnifiedMediaSources` is a pure,
  /// order-preserving function of the full candidate history — see
  /// `catalog_service.dart`), so a group already shown keeps its position
  /// here even when a later round adds a source to it; a caller diffing by
  /// [UnifiedMediaGroup.groupId] sees an update, not a reshuffle.
  final List<UnifiedMediaGroup> groups;

  /// True when the very first round produced nothing and every participating
  /// library failed (not just "the catalog happens to be empty" — see
  /// [failedLibraryIds] to tell those apart).
  final bool initialLoadFailed;

  /// Library keys (`serverId:libraryId`) whose most recent fetch attempt
  /// failed. Cleared for a library the moment it answers successfully. A
  /// library appearing here does not stop the merge — hoofdstuk 12.6: one
  /// failure never permanently drops a library, it is retried on the next
  /// `UnifiedCatalogService.loadMore` call.
  final Set<String> failedLibraryIds;

  /// True once every participating library cursor is exhausted — only then
  /// is [groups] the complete, final list (hoofdstuk 12's DoD: "geen exact
  /// totaal voordat streams compleet zijn").
  final bool isComplete;

  bool get hasMore => !isComplete;

  /// The exact number of groups this query will ever produce, or `null`
  /// while any library might still contribute more (see [isComplete]).
  int? get totalGroupCount => isComplete ? groups.length : null;

  const UnifiedCatalogSnapshot({
    this.groups = const [],
    this.initialLoadFailed = false,
    this.failedLibraryIds = const {},
    this.isComplete = false,
  });
}
