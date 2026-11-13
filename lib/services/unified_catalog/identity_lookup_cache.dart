/// One session-wide answer per external-id lookup, shared by every unified
/// projection (Home, Verder kijken, search). A series' provider numbers do not
/// change while the app runs, and Verder kijken asks for them on every
/// refresh; without this each refresh cost one request per series per server.
library;

import '../../media/ids.dart';
import '../../utils/external_ids.dart';
import '../multi_server_manager.dart';
import '../pleya_server_client.dart';

/// How long an answer is reused. A rematch on the server shows up after this.
const identityLookupTtl = Duration(minutes: 30);
const _maxEntries = 4000;

class _Entry {
  _Entry(this.future, this.storedAt);
  final Future<ExternalIds> future;
  final DateTime storedAt;
}

final Expando<Map<String, _Entry>> _cacheOf = Expando('identityLookupCache');

/// The provider numbers of [targetId] on [serverId], through [manager]'s live
/// client. Throws when the server has no client or the lookup fails, so the
/// caller degrades that one item to guid-only evidence.
///
/// Not cached: a failed lookup (the next round retries it), and anything from
/// a Pleya Server. Its answer is only proof together with the identity source
/// the client reports at that moment (`canTrustStoredIdentity`), and the
/// client already keeps its own short cache.
Future<ExternalIds> fetchExternalIdsForIdentity(
  MultiServerManager manager,
  String serverId,
  String targetId, {
  DateTime Function() now = DateTime.now,
}) {
  final client = manager.getClient(ServerId(serverId));
  if (client == null) return Future.error(StateError('No client for server $serverId'));
  if (client is PleyaServerClient) return client.fetchExternalIds(targetId);

  final cache = _cacheOf[manager] ??= {};
  final key = '$serverId:$targetId';
  final hit = cache[key];
  if (hit != null && now().difference(hit.storedAt) < identityLookupTtl) return hit.future;

  if (cache.length >= _maxEntries) cache.clear();
  final future = client.fetchExternalIds(targetId);
  final entry = _Entry(future, now());
  cache[key] = entry;
  return future.catchError((Object error) {
    if (identical(cache[key], entry)) cache.remove(key);
    throw error;
  });
}

/// Drops every remembered answer of [manager], for a refresh the viewer asked
/// for and for tests.
void clearIdentityLookupCache(MultiServerManager manager) => _cacheOf[manager]?.clear();
