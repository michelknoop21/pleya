/// One concrete backend source contributing to a [UnifiedMediaGroup]
/// (hoofdstuk 4.2 of docs/tvos-unified-experience.md). Pure projection over
/// an existing [MediaItem] — never replaces it, never mutated after
/// construction.
///
/// Hoofdstuk 4.2's full shape also carries `SourceAvailability availability`.
/// That field needs live server/profile state, so fase 1 left it out. Fase 2
/// then modelled reachability at two other altitudes instead — coverage per
/// *group* ([SourceCoverageState]) and eligibility per *server*
/// (`EligibleSourceServer`) — and never came back to this type. Fase 4 is the
/// first phase that needs the per-row answer (ranking tier 2 of hoofdstuk 4.7,
/// and the picker's offline/auth rows), so [availability] lands here now,
/// completing 4.2's declared shape.
///
/// It defaults to [SourceAvailability.unknown] rather than being required: a
/// source built while paging the catalogue genuinely has not had its server
/// re-checked, and saying so is more honest than defaulting to `online` and
/// letting the player discover otherwise.
library;

import '../ids.dart';
import '../media_backend.dart';
import '../media_item.dart';
import '../../utils/external_ids.dart';
import 'source_availability.dart';

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

  /// Whether this source is usable right now. Live state: a source outlives
  /// the moment its server was last checked, so callers holding one across a
  /// server going up or down re-stamp it through [withAvailability] rather
  /// than trusting the value they were handed.
  final SourceAvailability availability;

  const UnifiedMediaSource({
    required this.sourceKey,
    required this.item,
    required this.serverId,
    required this.serverName,
    required this.backend,
    this.libraryId,
    this.libraryTitle,
    this.externalIds = const ExternalIds(),
    this.availability = SourceAvailability.unknown,
  });

  /// This source with [availability] restamped from current server state.
  /// Everything else is identity and does not change with reachability.
  UnifiedMediaSource withAvailability(SourceAvailability availability) => UnifiedMediaSource(
    sourceKey: sourceKey,
    item: item,
    serverId: serverId,
    serverName: serverName,
    backend: backend,
    libraryId: libraryId,
    libraryTitle: libraryTitle,
    externalIds: externalIds,
    availability: availability,
  );

  /// Builds a source from a concrete [item] plus whatever [externalIds] were
  /// collected for it. [item] must carry a [MediaItem.serverId] — a source
  /// with no server cannot later be addressed for playback or details
  /// (hoofdstuk 4.4), so an item missing one signals a bug upstream rather
  /// than a state this type should represent silently.
  factory UnifiedMediaSource.fromItem(
    MediaItem item, {
    ExternalIds externalIds = const ExternalIds(),
    SourceAvailability availability = SourceAvailability.unknown,
  }) {
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
      availability: availability,
    );
  }

  @override
  String toString() => 'UnifiedMediaSource($sourceKey, backend: ${backend.id})';
}
