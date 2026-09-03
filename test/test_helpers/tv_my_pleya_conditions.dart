/// The three conditions hoofdstuk 18.3 puts in front of a Mijn Pleya tile,
/// as test doubles, so the *full* hub — every conditional tile at once — can be
/// rendered from more than one test file without either copying the other.
///
/// Downloads is deliberately not here: 18.3 says it never appears on an Apple
/// TV, and that is decided by `PlatformDetector.isAppleTV()`, not by a
/// provider.
library;

import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/services/api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';

/// Hoofdstuk 18.3's "Server Activities verschijnt alleen wanneer een relevante
/// Plex-bron aanwezig is".
///
/// `MultiServerProvider.hasOnlinePlexServers` resolves that through
/// `MultiServerManager.getPlexClient`, which type-checks for [PlexClient]
/// rather than reading `backend` — Activities needs Plex's own API, not merely
/// a server that calls itself Plex. So the double has to *be* a `PlexClient`,
/// and one whose health probe passes.
class OnlinePlexClientDouble implements PlexClient {
  OnlinePlexClientDouble(String id, this._name) : serverId = ServerId(id);

  @override
  final ServerId serverId;
  final String _name;

  @override
  String? get serverName => _name;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A watchlist that exists. The screen asks the provider a question rather than
/// reaching past it into a repository, so overriding the getter is the whole
/// double — and the snapshot store below is never read.
class StockedWatchlistDouble extends WatchlistProvider {
  StockedWatchlistDouble() : super(snapshots: WatchlistSnapshotStore(cache: _UnusedCache()));

  @override
  bool get hasWatchlist => true;
}

class ConfiguredSeerrDouble extends SeerrProvider {
  @override
  bool get isConfigured => true;
}

/// Keeps a database out of a widget test: [StockedWatchlistDouble] never
/// touches its store.
class _UnusedCache implements ApiCache {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
