/// The provider numbers a server's own list answer already carried for an
/// item, so the unified identity pipeline can recognise a title on another
/// server without a detail request and without leaning on its title.
library;

import '../../utils/external_ids.dart';
import '../media_backend.dart';
import '../media_item.dart';
import '../media_kind.dart';

/// Where each backend puts the numbers on [MediaItem.raw]:
/// - Plex: the `Guid` array of a request made with `includeGuids=1`;
/// - Jellyfin and Emby: the `ProviderIds` map (part of the browse fields);
/// - Pleya Server: `pleyaExternalIds`, written by the mapper only when the
///   server sent the `external_ids` key, so an older server leaves it out.
const pleyaExternalIdsRawKey = 'pleyaExternalIds';

/// The numbers [item]'s list answer carried, or null when it carried none this
/// client can trust as "what the server knows". An empty [ExternalIds] is a
/// real answer (the server knows the title has no numbers); null means "not
/// asked", and the caller may look it up.
///
/// Movies and shows only. An episode's numbers on Plex and Jellyfin describe
/// the episode itself, not its show, so they are never a substitute for the
/// show-plus-ordinal identity Continue Watching groups on.
ExternalIds? externalIdsCarriedBy(MediaItem item) {
  if (item.kind != MediaKind.movie && item.kind != MediaKind.show) return null;
  final raw = item.raw;
  if (raw == null) return null;
  switch (item.backend) {
    case MediaBackend.plex:
      final guids = raw['Guid'];
      return guids is List ? ExternalIds.fromGuids(guids) : null;
    case MediaBackend.jellyfin:
      final ids = raw['ProviderIds'];
      return ids is Map ? ExternalIds.fromJellyfinProviderIds(Map<String, Object?>.from(ids)) : null;
    case MediaBackend.pleyaServer:
      final ids = raw[pleyaExternalIdsRawKey];
      return ids is Map ? ExternalIds.fromJson(Map<String, Object?>.from(ids)) : null;
    case MediaBackend.local:
      return null;
  }
}
