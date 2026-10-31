/// What a write to another copy of a title needs first. Grouping may fold two
/// cards on title and year, which is good enough to show one card and not good
/// enough to write: two films can share both (hoofdstuk 13.2).
library;

import 'dart:async';

import '../../media/ids.dart';
import '../../media/media_identity.dart';
import '../../media/episode_collection.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/carried_external_ids.dart';
import '../../media/unified/identity_evidence.dart';
import '../../media/unified/unified_media_source.dart';
import '../../utils/app_logger.dart';
import '../../utils/external_ids.dart';
import 'source_episode_index.dart';

/// [guid] when it says what the title is. An unmatched item carries a
/// server-local one, and two servers can hold the same `local://` number for
/// two different home videos. The raw value stays: servers compare it as they
/// stored it.
String? provingGuid(String? guid) {
  if (normalizeStableGuid(guid) == null) return null;
  return guid!.trim().toLowerCase().startsWith('local://') ? null : guid.trim();
}

/// Decides whether two sources are one title, on a shared guid or provider
/// number. Reads what a source does not carry itself, once per source, from a
/// server [clientFor] hands out.
class UnifiedCopyProof {
  UnifiedCopyProof(this.clientFor, {this.wait = const Duration(seconds: 3)});

  final MediaServerClient? Function(ServerId serverId) clientFor;
  final Duration wait;
  final Map<String, Future<ExternalIds?>> _ids = {};

  Future<bool> sameTitle(UnifiedMediaSource a, UnifiedMediaSource b) async {
    final idsOf = await Future.wait([_idsOf(a), _idsOf(b)]);
    final claim = MediaIdentity(guid: _titleGuid(a), externalIds: idsOf.first, title: a.item.title, kind: a.item.kind);
    final other = (item: b.item.copyWith(guid: _titleGuid(b)), ids: idsOf.last);
    return claim.pickAllMatches([other], allowTitleFallback: false).isNotEmpty;
  }

  /// An episode's guid names that episode, and each server has its own.
  static String? _titleGuid(UnifiedMediaSource source) => source.item.isEpisode ? null : provingGuid(source.item.guid);

  Future<ExternalIds> _idsOf(UnifiedMediaSource source) async {
    if (source.externalIds.hasAny) return source.externalIds;
    final carried = externalIdsCarriedBy(source.item);
    if (carried != null) return carried;
    final read = await (_ids[source.sourceKey] ??= _read(source));
    // A server that did not answer gets asked again next time.
    if (read == null) _ids.remove(source.sourceKey);
    return read ?? const ExternalIds();
  }

  Future<ExternalIds?> _read(UnifiedMediaSource source) async {
    final client = clientFor(source.serverId);
    final id = source.item.kind == MediaKind.movie ? source.item.id : seriesIdOf(source);
    if (client == null || id == null) return null;
    try {
      return await client.fetchExternalIds(id).timeout(wait);
    } catch (e) {
      appLogger.d('No provider numbers for ${source.sourceKey}', error: e);
      return null;
    }
  }
}

/// The seasons of [copy] that [show] holds too, Specials left out. Empty when
/// either side does not answer: nothing is marked on a guess.
Future<List<MediaItem>> seasonsInCommon(
  MediaItem show,
  MediaItem copy, {
  required MediaServerClient? Function(ServerId serverId) clientFor,
}) async {
  final mine = serverIdOrNull(show.serverId);
  final theirs = serverIdOrNull(copy.serverId);
  if (mine == null || theirs == null) return const [];
  try {
    final own = await clientFor(mine)?.fetchChildren(show.id);
    final other = await clientFor(theirs)?.fetchChildren(copy.id);
    final numbers = {
      for (final season in own ?? const <MediaItem>[])
        if (season.isSeason && season.index != null && !isSpecialSeasonNumber(season.index)) season.index,
    };
    return [
      for (final season in other ?? const <MediaItem>[])
        if (season.isSeason && numbers.contains(season.index)) season.copyWith(serverId: theirs.value),
    ];
  } catch (e) {
    appLogger.d('Seasons of ${show.globalKey} and ${copy.globalKey} could not be compared', error: e);
    return const [];
  }
}
