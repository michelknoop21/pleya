/// Profile-scoped owner of the fase-6 discovery projection for the Films and
/// Series landings (hoofdstuk 10.2a and 27 fase 6 of
/// docs/tvos-unified-experience.md, [DEC-064]).
///
/// `DiscoverProvider` already fetches everything this needs — on-deck items,
/// backend hubs, which servers failed to answer — for Home. This provider
/// does no fetching of its own: it re-projects that same data through
/// `HomeProjectionService`, split by [MediaKind] so a Films landing never
/// shows a show and vice versa. Never a second fetch, never a second
/// projection architecture beside `HomeProjectionService` (DEC-064's
/// architectuurgrens).
///
/// ## Lifecycle
///
/// Registered inside the profile-keyed subtree (`ProfileSessionScreen`)
/// beside `UnifiedCatalogs`, for the same reason: unified state is
/// profile-scoped (hoofdstuk 22), so the `KeyedSubtree` there is this
/// provider's entire disposal mechanism. Lazy — building it starts no
/// projection; the first listener triggers `_project()` off whatever
/// `DiscoverProvider` already holds.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_hub.dart';
import '../media/unified/unified_media_hub.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/unified_catalog/home_projection_service.dart';
import '../utils/app_logger.dart';
import '../utils/external_ids_fetcher.dart';
import 'discover_provider.dart';
import 'multi_server_provider.dart';

class TvDiscoveryLandingProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  TvDiscoveryLandingProvider({
    required DiscoverProvider discover,
    required MultiServerProvider multiServer,
    required String continueWatchingTitle,
  }) : _discover = discover,
       _continueWatchingTitle = continueWatchingTitle,
       _service = HomeProjectionService(fetchExternalIds: externalIdsFetcherFor(multiServer)) {
    _discover.addListener(_onDiscoverChanged);
    _onDiscoverChanged();
  }

  final DiscoverProvider _discover;
  final String _continueWatchingTitle;
  final HomeProjectionService _service;

  UnifiedMediaHub? _continueWatching;
  List<UnifiedMediaHub> _movieHubs = const [];
  List<UnifiedMediaHub> _seriesHubs = const [];

  // Coalesces overlapping projection runs: a second `DiscoverProvider`
  // notification while one projection is already in flight (identity
  // resolution awaits a network round trip) schedules exactly one more run
  // rather than racing two, whose completion order is not guaranteed to
  // match the order they started in.
  bool _projecting = false;
  bool _projectionPending = false;

  /// Films landing rows: Continue Watching first (when non-empty), then every
  /// projected movie-kind row, in the order `DiscoverProvider` produced them.
  List<UnifiedMediaHub> get movieRails => _withContinueWatching(_movieHubs);

  /// Series landing rows, same shape.
  List<UnifiedMediaHub> get seriesRails => _withContinueWatching(_seriesHubs);

  List<UnifiedMediaHub> get _bothKinds => [..._movieHubs, ..._seriesHubs];

  List<UnifiedMediaHub> _withContinueWatching(List<UnifiedMediaHub> kindHubs) {
    final cw = _continueWatching;
    return cw == null ? kindHubs : [cw, ...kindHubs];
  }

  bool get isProjecting => _projecting;

  void _onDiscoverChanged() {
    if (_projecting) {
      _projectionPending = true;
      return;
    }
    unawaited(_project());
  }

  Future<void> _project() async {
    _projecting = true;
    try {
      final failedServerIds = _discover.unansweredServerIds;

      final movieBackendHubs = <MediaHub>[];
      final seriesBackendHubs = <MediaHub>[];
      for (final hub in _discover.hubs) {
        switch (UnifiedHubKind.fromHubType(hub.type)) {
          case UnifiedHubKind.movie:
            movieBackendHubs.add(hub);
          case UnifiedHubKind.show:
            seriesBackendHubs.add(hub);
          // Mixed/episode/other rows have no single Films-or-Series home and
          // are left for Home's own projection (hoofdstuk 17.1) rather than
          // guessed onto one landing.
          case UnifiedHubKind.episode:
          case UnifiedHubKind.mixed:
          case UnifiedHubKind.other:
            break;
        }
      }

      final onDeck = _discover.onDeck;
      final results = await Future.wait([
        _service.projectContinueWatching(onDeck, title: _continueWatchingTitle, failedServerIds: failedServerIds),
        _service.projectHubs(movieBackendHubs, failedServerIds: failedServerIds),
        _service.projectHubs(seriesBackendHubs, failedServerIds: failedServerIds),
      ]);

      final continueWatching = results[0] as UnifiedMediaHub;
      _continueWatching = continueWatching.isEmpty ? null : continueWatching;
      _movieHubs = results[1] as List<UnifiedMediaHub>;
      _seriesHubs = results[2] as List<UnifiedMediaHub>;
      safeNotifyListeners();
    } catch (error, stackTrace) {
      appLogger.e('TvDiscoveryLandingProvider: projection failed', error: error, stackTrace: stackTrace);
    } finally {
      _projecting = false;
      if (_projectionPending) {
        _projectionPending = false;
        unawaited(_project());
      }
    }
  }

  /// The row a caller's remembered `hubId` currently maps to, across both
  /// landings — used to resolve focus restoration after a group a row used
  /// to hold is gone (hoofdstuk 7.6).
  UnifiedMediaHub? hubById(String hubId) {
    for (final hub in _bothKinds) {
      if (hub.hubId == hubId) return hub;
    }
    final cw = _continueWatching;
    if (cw != null && cw.hubId == hubId) return cw;
    return null;
  }

  @override
  void dispose() {
    _discover.removeListener(_onDiscoverChanged);
    super.dispose();
  }
}
