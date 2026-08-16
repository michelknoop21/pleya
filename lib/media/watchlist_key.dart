/// Canonical identity for a watchlist entry, shared by the two places a title
/// can show up: as a discover item in the cloud watchlist, and as a real item
/// on one of the user's own servers.
///
/// The app cannot use [MediaItem.globalKey] here. That key is `serverId:id`
/// and falls back to the bare id when there is no server. A discover item has
/// no server, so its rating key would land in the same namespace as a real
/// server rating key, and `ApiCache`, `WatchStateStore` and `DownloadProvider`
/// would quietly read and write each other's rows.
///
/// The key is a namespaced pair, most specific source first:
///
/// * `plex:<discover rating key>` from a `plex://movie/<key>` guid
/// * `imdb:<id>`, `tmdb:<id>` or `tvdb:<id>` from external ids
///
/// Namespaces keep an IMDb id from ever colliding with a Plex key, and the
/// value half is percent-encoded so a malformed id cannot fake a namespace
/// boundary.
library;

import '../utils/external_ids.dart';
import 'media_item.dart';

const String _separator = ':';

/// Strip the discover rating key off a Plex guid.
///
/// `plex://movie/5d776be17a53e9001e732ab9` becomes
/// `5d776be17a53e9001e732ab9`. This is the id the watchlist endpoints on
/// `discover.provider.plex.tv` expect; the server-side rating key of the same
/// title is a different, per-server number and will not work there.
///
/// Returns `null` for anything that is not a `plex://<type>/<key>` guid,
/// including the legacy `com.plexapp.agents.*` guids.
String? discoverRatingKeyFromGuid(String? guid) {
  if (guid == null) return null;
  const prefix = 'plex://';
  if (!guid.startsWith(prefix)) return null;

  final rest = guid.substring(prefix.length);
  final slash = rest.indexOf('/');
  if (slash <= 0) return null;

  // Drop any query string; Plex does not add one here today, but a guid that
  // grows one must not silently change identity.
  var key = rest.substring(slash + 1);
  final query = key.indexOf('?');
  if (query >= 0) key = key.substring(0, query);

  return key.isEmpty ? null : key;
}

/// External ids encoded in a legacy `com.plexapp.agents.*` guid, as older Plex
/// libraries still report them: `com.plexapp.agents.imdb://tt0111161?lang=en`.
///
/// Returns an empty [ExternalIds] for guids in any other shape.
ExternalIds externalIdsFromLegacyAgentGuid(String? guid) {
  const prefix = 'com.plexapp.agents.';
  if (guid == null || !guid.startsWith(prefix)) return const ExternalIds();

  final rest = guid.substring(prefix.length);
  final schemeEnd = rest.indexOf('://');
  if (schemeEnd <= 0) return const ExternalIds();

  final agent = rest.substring(0, schemeEnd).toLowerCase();
  var value = rest.substring(schemeEnd + 3);
  final query = value.indexOf('?');
  if (query >= 0) value = value.substring(0, query);
  // Legacy TVDB guids address an episode as `tvdb://73141/1/2`.
  final slash = value.indexOf('/');
  if (slash >= 0) value = value.substring(0, slash);
  if (value.isEmpty) return const ExternalIds();

  return switch (agent) {
    'imdb' => ExternalIds(imdb: value),
    'themoviedb' || 'tmdb' => ExternalIds(tmdb: int.tryParse(value)),
    'thetvdb' || 'tvdb' => ExternalIds(tvdb: int.tryParse(value)),
    _ => const ExternalIds(),
  };
}

/// The canonical watchlist key for [item], or `null` when the item carries no
/// identity that survives crossing servers.
///
/// [externalIds] is what the source knows on its own account: Plex delivers
/// them in a separate `Guid` array that [MediaItem] does not carry, and
/// Jellyfin in a `ProviderIds` map. Pass them when available; without them the
/// guid alone decides.
///
/// A `null` result is a real answer, not a failure to try: a title with no
/// guid and no external id cannot be matched on another server, so it does not
/// belong on a watchlist that spans servers.
String? watchlistKeyForItem(MediaItem item, {ExternalIds? externalIds}) {
  return watchlistKeyForIdentity(guid: item.guid, externalIds: externalIds);
}

/// [watchlistKeyForItem] for callers that hold a raw guid and external ids
/// without a [MediaItem] to wrap them in.
String? watchlistKeyForIdentity({String? guid, ExternalIds? externalIds}) {
  final plexKey = discoverRatingKeyFromGuid(guid);
  if (plexKey != null) return _key('plex', plexKey);

  final ids = externalIds ?? externalIdsFromLegacyAgentGuid(guid);
  final imdb = ids.imdb;
  if (imdb != null && imdb.isNotEmpty) return _key('imdb', imdb);
  final tmdb = ids.tmdb;
  if (tmdb != null) return _key('tmdb', '$tmdb');
  final tvdb = ids.tvdb;
  if (tvdb != null) return _key('tvdb', '$tvdb');

  // A caller that passed external ids may still hold a legacy agent guid that
  // carries the only usable id.
  if (externalIds != null) {
    final legacy = externalIdsFromLegacyAgentGuid(guid);
    if (legacy.hasAny) return watchlistKeyForIdentity(guid: null, externalIds: legacy);
  }

  return null;
}

String _key(String namespace, String value) => '$namespace$_separator${Uri.encodeComponent(value)}';
