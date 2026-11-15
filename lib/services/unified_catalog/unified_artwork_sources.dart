import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';

/// Artwork may come from any proven membership, never a same-name neighbour.
/// Keep the chosen representative first without changing playback/watch state.
Iterable<UnifiedMediaSource> unifiedArtworkSources(UnifiedMediaGroup group) sync* {
  yield group.representativeSource;
  yield* group.sources.where((source) => source.sourceKey != group.representativeSourceKey);
}
