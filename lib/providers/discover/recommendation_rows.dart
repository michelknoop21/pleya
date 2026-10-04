import 'package:flutter/foundation.dart';

import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../services/recommendations/recommendation_service.dart';
import '../../utils/app_logger.dart';
import '../multi_server_provider.dart';
import 'seed_rows_loader.dart';

/// What Home already shows at the moment a recommendation step runs.
typedef DiscoverFeedView = ({List<MediaItem> onDeck, MediaHub? latestShowsHub, List<MediaHub> hubs});

/// The recommendation rows on Home: "Because you watched X" seed rows and the
/// on-device personalized rows (Top Picks, Because you like…, Hidden Gems).
/// Both are held apart from the regular hubs so library-order sorting, delta
/// merges and hub filtering can't touch them, and both are recomputed only
/// after a load, entirely off the counted aggregation paths.
class RecommendationRows {
  RecommendationRows({
    required this._recommendations,
    required this._multiServer,
    required this._feed,
    required this._generation,
    required this._isDisposed,
    required this._notify,
  });

  final RecommendationService? _recommendations;
  final MultiServerProvider _multiServer;

  /// Read fresh at each step, like the fields it replaces.
  final DiscoverFeedView Function() _feed;

  /// The owner's load generation; a step whose generation moved on is dropped.
  final int Function() _generation;
  final bool Function() _isDisposed;
  final VoidCallback _notify;

  late final SeedRowsLoader _seedRowsLoader = SeedRowsLoader(
    recommendations: _recommendations,
    clientFor: _multiServer.getClientForServer,
  );

  /// "Because you watched X" rows (up to 3, one per recent seed).
  List<MediaHub> _seedHubs = [];

  /// Related titles of the seeds that did not get a row (positions four to
  /// six). Free candidates for the personalized rows, never shown as a row.
  List<MediaItem> _seedCandidates = [];

  List<MediaHub> _personalizedHubs = [];

  List<MediaHub> get seedHubs => _seedHubs;
  List<MediaHub> get personalizedHubs => _personalizedHubs;

  /// Runs the two post-load recommendation surfaces in order: seed rows first
  /// so the personalized rows below them can exclude the seed items, avoiding
  /// the same title appearing in adjacent rows.
  Future<void> load() async {
    final generation = _generation();
    try {
      await _loadBecauseYouWatched();
    } catch (e) {
      appLogger.w('DiscoverProvider: seed rows failed', error: e);
    }
    // Show what is already known first. Pulling external history can take a
    // round trip or several, and the feed must never wait on it.
    await _loadPersonalizedRows();

    final service = _recommendations;
    if (service == null) return;
    try {
      // Rebuild only when the sync says the rows on screen are out of date:
      // new imported rows, or rows that were scored before the integration
      // store had answered. An unchanged warm profile costs one no-op call and
      // no extra notify, and this path never refetches a hub.
      if (await service.syncImportedHistory()) {
        if (_isDisposed() || generation != _generation()) return;
        await _loadPersonalizedRows();
      }
    } catch (e) {
      appLogger.w('DiscoverProvider: imported history sync failed', error: e);
    }
  }

  /// Build up to three "Because you watched X" rows via [SeedRowsLoader].
  /// Fully fault-tolerant: any failure or empty step simply leaves rows out
  /// (or keeps the previous set).
  Future<void> _loadBecauseYouWatched() async {
    try {
      // Only sources that can answer with related titles may seed; a seed on
      // any other source would take one of the three slots and yield nothing.
      final clients = _multiServer.serverManager.onlineClients.values
          .where((client) => client.capabilities.relatedHubs)
          .toList();
      if (clients.isEmpty) {
        // Rows of a server that just went offline must not stay behind.
        _seedCandidates = const [];
        if (_seedHubs.isEmpty) return;
        _seedHubs = [];
        _notify();
        return;
      }
      final generation = _generation();
      // Don't re-surface items already shown in Continue Watching, Recently
      // Added Shows or the hubs.
      final feed = _feed();
      final alreadyShown = <String>{
        for (final item in feed.onDeck) item.globalKey,
        for (final item in feed.latestShowsHub?.items ?? const <MediaItem>[]) item.globalKey,
        for (final hub in feed.hubs)
          for (final item in hub.items) item.globalKey,
      };

      final seeded = await _seedRowsLoader.load(clients: clients, alreadyShown: alreadyShown);
      if (_isDisposed() || generation != _generation()) return;
      _seedCandidates = seeded.candidates;
      final newSeedHubs = seeded.rows;

      // Assign even when empty so cleared history / changed watch state drops
      // stale "Because you watched…" rows instead of stranding them.
      if (_seedHubs.isEmpty && newSeedHubs.isEmpty) return;
      _seedHubs = newSeedHubs;
      _notify();
    } catch (e) {
      // Transient failure: keep whatever rows were already shown.
      appLogger.w('DiscoverProvider: because-you-watched rows failed (keeping previous)', error: e);
    }
  }

  /// Build the on-device personalized rows. No-op when personalization is
  /// unavailable/disabled. Guarded on the owner's load generation.
  Future<void> _loadPersonalizedRows() async {
    final service = _recommendations;
    if (service == null) return;
    final generation = _generation();
    try {
      final clients = _multiServer.serverManager.onlineClients.values.toList();

      // Items already on screen (Continue Watching, Recently Added Shows,
      // loaded hubs, seed rows) are free candidates and, via [excludeKeys],
      // must not be echoed by the personalized rows below them.
      final feed = _feed();
      final onScreen = <MediaItem>[
        ...feed.onDeck,
        ...?feed.latestShowsHub?.items,
        for (final hub in feed.hubs) ...hub.items,
        for (final hub in _seedHubs) ...hub.items,
      ];
      final excludeKeys = {for (final item in onScreen) item.globalKey};

      final rows = clients.isEmpty
          ? const <MediaHub>[]
          : await service.buildRows(clients, hubItems: [...onScreen, ..._seedCandidates], excludeKeys: excludeKeys);
      if (_isDisposed() || generation != _generation()) return;
      // Assign even when empty so disabling personalization or losing history
      // clears any previously-shown rows instead of stranding them.
      if (_personalizedHubs.isEmpty && rows.isEmpty) return;
      _personalizedHubs = rows;
      _notify();
    } catch (e) {
      // Transient failure: keep whatever rows were already shown.
      appLogger.w('DiscoverProvider: personalized rows failed (keeping previous)', error: e);
    }
  }
}
