/// Shared `fetchExternalIds` closure builder for the unified identity
/// pipeline (`UnifiedIdentityResolver`, consumed via `HomeProjectionService`
/// and `searchProjection`). Every projection call site needs the exact same
/// shape: resolve a server's client from `MultiServerProvider`, fetch, or
/// degrade that one server's evidence to guid-only by throwing when no
/// client is registered for it — never fail the whole projection over one
/// missing server.
library;

import '../media/ids.dart';
import '../providers/multi_server_provider.dart';
import 'external_ids.dart';

/// Builds the `fetchExternalIds` callback `UnifiedIdentityResolver` (and
/// everything built on it) expects, backed by [multiServer]'s live clients.
Future<ExternalIds> Function(String serverId, String targetId) externalIdsFetcherFor(MultiServerProvider multiServer) {
  return (serverId, targetId) async {
    final client = multiServer.serverManager.getClient(ServerId(serverId));
    if (client == null) throw StateError('No client for server $serverId');
    return client.fetchExternalIds(targetId);
  };
}
