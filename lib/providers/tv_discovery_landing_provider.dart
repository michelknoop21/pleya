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
  TvDiscoveryLandingProvider({required DiscoverProvider discover, required MultiServerProvider multiServer})
    : _discover = discover,
      _service = HomeProjectionService(fetchExternalIds: externalIdsFetcherFor(multiServer)) {
    _discover.addListener(_onDiscoverChanged);
    _onDiscoverChanged();
  }

  final DiscoverProvider _discover;
  final HomeProjectionService _service;

  List<UnifiedMediaHub> _movieHubs = const [];
  List<UnifiedMediaHub> _seriesHubs = const [];

  // Coalesces overlapping projection runs: a second `DiscoverProvider`
  // notification while one projection is already in flight (identity
  // resolution awaits a network round trip) schedules exactly one more run
  // rather than racing two, whose completion order is not guaranteed to
  // match the order they started in.
  bool _projecting = false;
  bool _projectionPending = false;

  /// Films landing rows: every projected movie-kind row, in the order
  /// `DiscoverProvider` produced them.
  ///
  /// **No Continue Watching row, on either landing (DEC-086).** Home owns it,
  /// through [TvHomeProjectionProvider.continueWatching], and it is the only
  /// surface that does.
  ///
  /// Two separate reasons, and the second is why this is a fix rather than a
  /// preference. The first is the one that was reported: Verder kijken repeated
  /// at the top of Films and of Series is the same row three times on three
  /// pages, and it pushes the row each landing actually exists for below the
  /// fold. The second was found while removing it — the row was never
  /// kind-split. It was projected once over the whole of `DiscoverProvider.onDeck`
  /// and prepended to both landings, while the hubs beside it *were* sorted into
  /// movie and series. So the Films landing led with half-watched episodes and
  /// the Series landing with films, which is precisely what this class's own
  /// doc rules out ("split by [MediaKind] so a Films landing never shows a show
  /// and vice versa").
  ///
  /// This supersedes 33.3 and 33.4's "Continue Watching first when non-empty",
  /// which both bind for these two landings. The first row of a landing is a
  /// recommendation row now.
  List<UnifiedMediaHub> get movieRails => _movieHubs;

  /// Series landing rows, same shape.
  List<UnifiedMediaHub> get seriesRails => _seriesHubs;

  List<UnifiedMediaHub> get _bothKinds => [..._movieHubs, ..._seriesHubs];

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

      final results = await Future.wait([
        _service.projectHubs(movieBackendHubs, failedServerIds: failedServerIds),
        _service.projectHubs(seriesBackendHubs, failedServerIds: failedServerIds),
      ]);

      _movieHubs = results[0];
      _seriesHubs = results[1];
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
    return null;
  }

  @override
  void dispose() {
    _discover.removeListener(_onDiscoverChanged);
    super.dispose();
  }
}
