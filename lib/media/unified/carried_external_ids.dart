/// The provider numbers a server's own list answer already carried for an
/// item, so the unified identity pipeline can recognise a title on another
/// server without a detail request and without leaning on its title.
library;

import '../../utils/external_ids.dart';
import '../media_backend.dart';
import '../media_item.dart';
import '../media_kind.dart';
import '../watchlist_key.dart' show externalIdsFromLegacyAgentGuid;

/// Where each backend puts the numbers on [MediaItem.raw]:
/// - Plex: the `Guid` array of a request made with `includeGuids=1`;
/// - Jellyfin and Emby: the `ProviderIds` map (part of the browse fields);
/// - Pleya Server: `pleyaExternalIds`, written by the mapper only when the
///   server sent the `external_ids` key, so an older server leaves it out.
const pleyaExternalIdsRawKey = 'pleyaExternalIds';
const pleyaExternalIdsSourceKey = 'pleyaExternalIdsSource';

/// Without live server context only persisted, explicitly applied proof is safe.
bool hasAppliedExternalIds(MediaItem item) {
  final ids = item.raw?[pleyaExternalIdsRawKey];
  if (item.raw?[pleyaExternalIdsSourceKey] != 'applied' || ids is! Map) return false;
  final tmdb = ids['tmdb'];
  return tmdb == null || (tmdb is int && tmdb > 0);
}

bool storedIdentityIsSafe(MediaItem item) => item.backend != MediaBackend.pleyaServer || hasAppliedExternalIds(item);

/// The numbers [item]'s list answer carried, or null when it carried none this
/// client can trust as "what the server knows". An empty [ExternalIds] is a
/// real answer (the server knows the title has no numbers); null means "not
/// asked", and the caller may look it up.
///
/// Movies and shows only. An episode's numbers on Plex and Jellyfin describe
/// the episode itself, not its show, so they are never a substitute for the
/// show-plus-ordinal identity Continue Watching groups on.
ExternalIds? externalIdsCarriedBy(MediaItem item, {bool allowLegacyPleya = false}) {
  if (item.kind != MediaKind.movie && item.kind != MediaKind.show) return null;
  final raw = item.raw;
  if (raw == null && item.backend != MediaBackend.plex) return null;
  switch (item.backend) {
    case MediaBackend.plex:
      final guids = raw?['Guid'];
      final fromArray = guids is List ? ExternalIds.fromGuids(guids) : null;
      if (fromArray != null && fromArray.hasAny) return fromArray;
      // A library on an old agent has no `Guid` array (or one that holds only
      // the catalogue guid); its number sits in the guid itself. Without this
      // such a title only got compared when the other server gave it the very
      // same title (DEC-198 read it in the lookup, which a differing title
      // never reaches).
      final legacy = _wellFormed(externalIdsFromLegacyAgentGuid(item.guid));
      return legacy.hasAny ? legacy : fromArray;
    case MediaBackend.jellyfin:
      final ids = raw!['ProviderIds'];
      return ids is Map ? ExternalIds.fromJellyfinProviderIds(Map<String, Object?>.from(ids)) : null;
    case MediaBackend.pleyaServer:
      if (!hasAppliedExternalIds(item) && !allowLegacyPleya) return null;
      final ids = raw![pleyaExternalIdsRawKey];
      return ids is Map ? ExternalIds.fromJson(Map<String, Object?>.from(ids)) : null;
    case MediaBackend.local:
      return null;
  }
}

/// A legacy guid is free text from an old agent. Only an imdb value shaped
/// like one (`tt` plus digits) becomes evidence; the numeric ids are parsed
/// as integers already.
ExternalIds _wellFormed(ExternalIds ids) {
  final imdb = ids.imdb;
  if (imdb == null || RegExp(r'^tt\d+$').hasMatch(imdb)) return ids;
  return ExternalIds(tmdb: ids.tmdb, tvdb: ids.tvdb);
}
