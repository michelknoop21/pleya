/// One concrete backend source contributing to a [UnifiedMediaGroup]
/// (hoofdstuk 4.2 of docs/tvos-unified-experience.md). Pure projection over
/// an existing [MediaItem] — never replaces it, never mutated after
/// construction.
///
/// Hoofdstuk 4.2's full shape also carries `SourceAvailability availability`.
/// That field needs live server/profile state — expected-vs-online-vs-hidden
/// — which is exactly what fase 2's source resolver and visibility boundary
/// (hoofdstuk 27, fase 2) add. Fase 1 stays visibility-agnostic and does not
/// touch server state at all, so `availability` is intentionally not part of
/// this type yet; fase 2 extends it rather than fase 1 guessing its shape.
library;

import '../ids.dart';
import '../media_backend.dart';
import '../media_item.dart';
import '../../utils/external_ids.dart';

class UnifiedMediaSource {
  /// Stable identifier for this source within its group. Currently
  /// [MediaItem.globalKey] (`serverId:id`) — unique per concrete item, so it
  /// survives being re-sorted or re-grouped across refreshes.
  final String sourceKey;

  final MediaItem item;
  final ServerId serverId;
  final String serverName;
  final MediaBackend backend;
  final String? libraryId;
  final String? libraryTitle;

  /// External ids collected for [item] during identity resolution. May be
  /// empty when the source never entered a duplicate bucket (hoofdstuk 11.2
  /// fase A/B) and so was never enriched.
  final ExternalIds externalIds;

  const UnifiedMediaSource({
    required this.sourceKey,
    required this.item,
    required this.serverId,
    required this.serverName,
    required this.backend,
    this.libraryId,
    this.libraryTitle,
    this.externalIds = const ExternalIds(),
  });

  /// Builds a source from a concrete [item] plus whatever [externalIds] were
  /// collected for it. [item] must carry a [MediaItem.serverId] — a source
  /// with no server cannot later be addressed for playback or details
  /// (hoofdstuk 4.4), so an item missing one signals a bug upstream rather
  /// than a state this type should represent silently.
  factory UnifiedMediaSource.fromItem(MediaItem item, {ExternalIds externalIds = const ExternalIds()}) {
    final rawServerId = item.serverId;
    if (rawServerId == null || rawServerId.isEmpty) {
      throw ArgumentError.value(item, 'item', 'UnifiedMediaSource requires MediaItem.serverId');
    }
    return UnifiedMediaSource(
      sourceKey: item.globalKey,
      item: item,
      serverId: ServerId(rawServerId),
      serverName: item.serverName ?? rawServerId,
      backend: item.backend,
      libraryId: item.libraryId,
      libraryTitle: item.libraryTitle,
      externalIds: externalIds,
    );
  }

  @override
  String toString() => 'UnifiedMediaSource($sourceKey, backend: ${backend.id})';
}
