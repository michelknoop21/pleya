/// A logical title with one or more concrete [UnifiedMediaSource]s (hoofdstuk
/// 4.2 of docs/tvos-unified-experience.md). Pure presentation/aggregation
/// model — grouping never discards a source, and this type never issues a
/// write of its own (hoofdstuk 4.6).
///
/// Hoofdstuk 4.2's full shape also carries `SourceCoverageState coverage`.
/// Coverage means "did we ask every server that could plausibly have this
/// title, and did they all answer" — meaningless without fase 2's
/// `findAllByIdentity` fan-out and expected-server bookkeeping (hoofdstuk 27,
/// fase 2 adds `source_coverage_state.dart`). Fase 1 only ever sees the
/// sources a caller already fetched, so it cannot know what it didn't ask;
/// `coverage` is intentionally left for fase 2 to add rather than fase 1
/// inventing a placeholder value fase 2 would have to redesign anyway.
library;

import 'canonical_media_identity.dart';
import 'unified_media_source.dart';
import 'unified_watch_state.dart';

class UnifiedMediaGroup {
  /// Stable while this group's provider/session lives (hoofdstuk 11.9).
  /// Fase 1 has no provider yet (that's fase 3's `UnifiedCatalogProvider`), so
  /// this is deterministically derived from content — see
  /// `grouping_service.dart` — rather than assigned by a long-lived store.
  final String groupId;

  final CanonicalMediaIdentity identity;

  /// Every contributing source. Never a subset — hoofdstuk 4.2/11.5 require
  /// grouping to preserve all sources, never silently drop one.
  final List<UnifiedMediaSource> sources;

  final String representativeSourceKey;
  final UnifiedWatchState watchState;

  UnifiedMediaGroup({
    required this.groupId,
    required this.identity,
    required List<UnifiedMediaSource> sources,
    required this.representativeSourceKey,
    required this.watchState,
  }) : sources = List.unmodifiable(sources) {
    assert(this.sources.isNotEmpty, 'UnifiedMediaGroup requires at least one source');
    assert(
      this.sources.any((s) => s.sourceKey == representativeSourceKey),
      'representativeSourceKey must name one of sources',
    );
  }

  UnifiedMediaSource get representativeSource => sources.firstWhere((s) => s.sourceKey == representativeSourceKey);

  bool get hasMultipleSources => sources.length > 1;

  @override
  String toString() => 'UnifiedMediaGroup($groupId, ${sources.length} source${sources.length == 1 ? '' : 's'})';
}
