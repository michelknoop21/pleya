part of '../../pleya_server_client.dart';

/// Search across every library on one server.
///
/// One endpoint, one page of ordinary items. The contract has no separate
/// result type and no grouping per kind: the client groups, and does not have
/// to learn a second shape to do it.
mixin _PleyaServerSearchMethods on _PleyaServerRequests {
  /// Search titles on this server.
  ///
  /// No `kind` is sent, and that is the whole of [DEC-045]: without one the
  /// server answers with movies, shows and episodes and leaves seasons out,
  /// because a season's title is "Season 3" and carries nothing anyone types.
  /// Sending `kind=season` is the opt-in, and no browse or search path in the
  /// app wants it: a season is reached through its show.
  ///
  /// Cross-server search fans out in `data_aggregation_service`, which calls
  /// this once per server and merges. That layer needs no backend check, and
  /// this method exists in exactly the shape that keeps it that way.
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) async {
    final trimmed = query.trim();
    // `q` has minLength 1 in the contract, so an empty query is a 400 rather
    // than an empty result. Answering locally keeps a stray keystroke off the
    // wire and out of the error log.
    if (trimmed.isEmpty || !wireCapabilities.search) return const [];
    final json = await _getJson(
      '/search',
      queryParameters: {'q': trimmed, 'limit': '${limit.clamp(1, 500)}'},
      timeout: MediaServerTimeouts.searchPerServer,
    );
    if (json == null) return const [];
    try {
      final page = PleyaItemPage.fromJson(json);
      return PleyaServerMappers.items(page.knownItems, serverId: serverId.toString(), serverName: serverName);
    } on PleyaWireFormatException catch (e) {
      appLogger.w('PleyaServerClient: /search did not match the contract', error: e);
      return const [];
    }
  }
}
