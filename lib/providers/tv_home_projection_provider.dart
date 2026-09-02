/// Profile-scoped owner of the fase-6 TV Home hero *data* (hoofdstuk 9.5 of
/// docs/tvos-unified-experience.md): which logical titles the billboard
/// shows, and which [UnifiedMediaGroup] each of those slides activates.
///
/// This is a data-layer swap, not a redesign. Fase 8 owns every bit of hero
/// *presentation* — the rounded billboard, the 8-second rotation of
/// hoofdstuk 9.6, artwork warm-up, the late-hero rules of 9.7 — and none of
/// that changes here. `DiscoverScreen`'s TV hero still rotates, autoplays,
/// follows rail focus and renders exactly as before this provider existed.
/// What changed in fase 6 is only *what it rotates over*.
///
/// ## One list, for both display and activation
///
/// [heroGroups] is **the** ordered hero list: it decides which slides exist,
/// in what order, and which group each visible slide belongs to. Before
/// DEC-067 the TV hero rotated over `DiscoverProvider.latestMovies`
/// (concrete items, only `data_aggregation_service`'s light guid/globalKey
/// dedup) while activation looked its group up in a separate pool — so one
/// title present on two servers under two guids took two rotation slots, and
/// display and activation could disagree about what "the current slide" was.
/// Both now read [heroGroups].
///
/// Presentation still renders a *representative* concrete `MediaItem` per
/// group — backdrop, clearlogo, title, metadata, the existing hero widget
/// API all take a `MediaItem`. That representative is presentation only; it
/// never decides activation (hoofdstuk 4.4/4.6).
///
/// ## Movies only, while there are any
///
/// [heroGroups] is [FeaturedSelector] over the projected
/// `DiscoverProvider.latestMovies` row alone — recent-released films, in
/// `DiscoverProvider`'s own release-date order, which this provider
/// re-projects through the identity pipeline but never re-ranks. Hubs (Top
/// Picks, recently added series, redactional/backend rows) do **not** pad a
/// non-empty hero: dedup is allowed to shrink the rotation, and a hero of
/// three genuinely-recent films is the correct answer to a library with
/// three (DEC-067). `FeaturedSelector.maxCount` still caps at hoofdstuk
/// 9.5's upper bound of eight; that is a cap, not a filler.
///
/// Continue Watching is not a hero input either — hoofdstuk 9.5's candidate
/// order never lists it, CW is its own rail below the hero.
///
/// ## The wider activation-lookup pool
///
/// When [heroGroups] is empty (no visible film library, or every recent film
/// filtered out as unreleased/untitled), `DiscoverScreen` keeps its existing
/// fallback of showing an on-deck or hub item as the billboard, and rail
/// focus can put any rail item there at any time. [featuredGroupFor] exists
/// for those: it searches every group this projection produced — CW and hubs
/// included — so even a billboard that is not a hero slide activates through
/// the fase-4 coordinator instead of the representative-source shortcut.
///
/// ## Lifecycle
///
/// Registered inside the profile-keyed subtree (`ProfileSessionScreen`)
/// beside `TvDiscoveryLandingProvider`, for the same reason: unified state is
/// profile-scoped (hoofdstuk 22). Lazy — building it starts no projection;
/// the first listener triggers `_project()` off whatever `DiscoverProvider`
/// already holds.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/unified/unified_media_group.dart';
import '../media/unified/unified_media_hub.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/unified_catalog/featured_selector.dart';
import '../services/unified_catalog/home_projection_service.dart';
import '../utils/app_logger.dart';
import '../utils/external_ids_fetcher.dart';
import 'discover_provider.dart';
import 'multi_server_provider.dart';

class TvHomeProjectionProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  TvHomeProjectionProvider({
    required DiscoverProvider discover,
    required MultiServerProvider multiServer,
    required String continueWatchingTitle,
    required String latestMoviesTitle,
    FeaturedSelector featuredSelector = const FeaturedSelector(),
  }) : _discover = discover,
       _continueWatchingTitle = continueWatchingTitle,
       _latestMoviesTitle = latestMoviesTitle,
       _service = HomeProjectionService(fetchExternalIds: externalIdsFetcherFor(multiServer)),
       _featuredSelector = featuredSelector {
    _discover.addListener(_onDiscoverChanged);
    _onDiscoverChanged();
  }

  static const _latestMoviesHubId = 'pleya:home:latest-movies';

  final DiscoverProvider _discover;
  final String _continueWatchingTitle;
  final String _latestMoviesTitle;
  final HomeProjectionService _service;
  final FeaturedSelector _featuredSelector;

  UnifiedMediaHub? _continueWatching;
  UnifiedMediaHub? _latestMoviesRow;
  List<UnifiedMediaGroup> _heroGroups = const [];
  List<UnifiedMediaHub> _hubs = const [];
  bool _hasProjectedHero = false;

  // The uncapped union of every group this projection produced — latest
  // movies, Continue Watching and hubs alike — so `featuredGroupFor` can find
  // whatever `DiscoverScreen`'s own fallback chain put on screen, independent
  // of `FeaturedSelector.maxCount`'s cap on the *ranked* candidate list.
  List<UnifiedMediaGroup> _allProjectedGroups = const [];

  // Coalescing, same as `TvDiscoveryLandingProvider`: a second
  // `DiscoverProvider` notification while one projection is in flight
  // (identity resolution awaits a network round trip) schedules exactly one
  // more run rather than racing two whose completion order is not guaranteed
  // to match the order they started in.
  bool _projecting = false;
  bool _projectionPending = false;

  // The `DiscoverProvider` inputs this projection actually reads, as of the
  // last completed run, so a notification that changed something it does not
  // read (`isRefreshing` flipping, a single on-deck item's watch-state patch)
  // does not re-run the whole external-id-fetching pipeline for no visible
  // change.
  //
  // Element identity, not list identity, and that distinction is the whole
  // reason this comment is long. The first version of this guard used
  // `identical()` on the lists and claimed all three were plain fields
  // `DiscoverProvider` reassigns wholesale. That is true of `latestMovies`
  // and `onDeck`. It is **false** of `hubs`, which is a computed getter:
  //
  //     List<MediaHub> get hubs => (_seedHubs.isEmpty && _personalizedHubs.isEmpty && _latestShowsHub == null)
  //         ? _hubs
  //         : [?_latestShowsHub, ..._seedHubs, ..._personalizedHubs, ..._hubs];
  //
  // In production the allocating branch is the normal one — `_latestShowsHub`
  // is assigned on every load and `ProfileSessionScreen` always passes a
  // `RecommendationService`, so `_seedHubs`/`_personalizedHubs` fill — which
  // made `identical(hubs, _lastHubs)` permanently false. The guard never
  // fired at all, and every `DiscoverProvider` notification (five per load,
  // plus every watch-state patch during playback) re-ran three projections
  // and their per-item external-id network fetches. The unit test missed it
  // because its fake populates none of those three fields, so the getter
  // returned the raw `_hubs` field — the one branch where `identical()`
  // works.
  //
  // `listEquals` compares element by element. `MediaHub` and `MediaItem` do
  // not override `==`, so each comparison is a reference check and a real
  // change — a replaced hub, a rebuilt item — always shows up. It costs a
  // walk of a few dozen references per notification, which is nothing beside
  // the pipeline it is guarding, and unlike `identical()` it does not depend
  // on whether the producer happened to hand back a field or a fresh list.
  // * `unansweredServerIds` is a *computed* `Set` (`onlineServerIds`
  //   difference `_loadedOnDeckServerIds ∩ _loadedHubServerIds`), so it is a
  //   new object on every read and `identical()` would be permanently false
  //   — defeating the guard entirely — while leaving it out altogether means
  //   a server coming online, dropping offline, or finishing its load never
  //   re-projects, and `failedServerIds` goes stale on rows that are still
  //   showing a partial-source state. It is a handful of server ids, so
  //   `setEquals` is the cheap correct answer, not a deep list walk.
  List<MediaItem>? _lastLatestMovies;
  List<MediaItem>? _lastOnDeck;
  List<MediaHub>? _lastHubs;
  Set<String>? _lastUnansweredServerIds;

  /// Unified Continue Watching, `null` when empty — same shape
  /// `TvDiscoveryLandingProvider` exposes, so fase 8 can reuse it directly.
  UnifiedMediaHub? get continueWatching => _continueWatching;

  /// Unified recommendation hubs (Top Picks, recently added series,
  /// redactional/backend rows), in `DiscoverProvider.hubs`' own order.
  ///
  /// Read by `TvContentFeed._rows` since fase 8, which is the phase
  /// `docs/tvos-unified-fase6-home-rows-deviation.md` moved "geen duplicate
  /// titel in één Home-rij" to — the one that replaced `tv_browse_rail.dart`
  /// with `tv_content_feed`/`tv_content_row`, and that named this getter and
  /// [continueWatching] as the data source those read.
  List<UnifiedMediaHub> get hubs => _hubs;

  /// The projected "Recently Released" row — the same films the hero is built
  /// from, deduplicated the same way, but **uncapped**: [heroGroups] is
  /// `FeaturedSelector` over this and stops at hoofdstuk 9.5's eight, while the
  /// row is a row and shows what there is.
  ///
  /// Two consumers of one projection rather than two projections of one input,
  /// so the row and the billboard can never disagree about which films are
  /// recent or about how many logical titles that is. `null` when empty.
  UnifiedMediaHub? get latestMovies => _latestMoviesRow;

  /// **The** ordered TV Home hero list: which slides exist, in what order,
  /// and which [UnifiedMediaGroup] each one activates (see class doc).
  ///
  /// Recent-released films only, deduped to logical titles, capped at
  /// hoofdstuk 9.5's eight. Empty until the first projection completes — use
  /// [hasProjectedHero] to tell "not projected yet" from "genuinely no
  /// eligible film", because the two need different fallbacks.
  List<UnifiedMediaGroup> get heroGroups => _heroGroups;

  /// Whether a projection has completed at least once, i.e. whether an empty
  /// [heroGroups] is an answer or just an unfinished load.
  bool get hasProjectedHero => _hasProjectedHero;

  /// The exact `DiscoverProvider.latestMovies` list [heroGroups] was built
  /// from, or `null` before the first projection completes.
  ///
  /// `DiscoverProvider` replaces that list wholesale on every real change, so
  /// a consumer can answer "is the hero caught up with what Home is showing?"
  /// with one `identical()` check — and, crucially, tell an *authoritative*
  /// empty [heroGroups] ("this library's recent films are all ineligible")
  /// from a transient one ("the films just landed, the projection is still
  /// resolving their identities"). The two need different fallbacks:
  /// `DiscoverScreen` shows on-deck/hub content for the first and keeps
  /// today's raw `latestMovies` hero for the second, so the billboard never
  /// blanks mid-load.
  List<MediaItem>? get projectedLatestMovies => _lastLatestMovies;

  bool get isProjecting => _projecting;

  /// The group whose sources include [item], matched on `globalKey`, across
  /// every group this projection produced — CW and hubs included, not only
  /// [heroGroups].
  ///
  /// [heroGroups] is what the hero rotates over, so a hero slide's group is
  /// known without a lookup. This exists for the billboards that are *not*
  /// hero slides: rail focus puts any rail item there, and when [heroGroups]
  /// is empty `DiscoverScreen` falls back to an on-deck or hub item. Those
  /// still activate through the group (hoofdstuk 4.4) instead of the concrete
  /// item shortcut. Matched across every source, not only
  /// [UnifiedMediaGroup.representativeSource] — a merged group's
  /// representative is not guaranteed to be the exact item `DiscoverProvider`
  /// handed to the projection.
  UnifiedMediaGroup? featuredGroupFor(MediaItem item) {
    for (final group in _allProjectedGroups) {
      for (final source in group.sources) {
        if (source.item.globalKey == item.globalKey) return group;
      }
    }
    return null;
  }

  void _onDiscoverChanged() {
    // See the `_last*` field docs: reference identity for the three lists
    // `DiscoverProvider` reassigns wholesale, set equality for the computed
    // `unansweredServerIds`.
    if (_lastUnansweredServerIds != null &&
        listEquals(_discover.latestMovies, _lastLatestMovies) &&
        listEquals(_discover.onDeck, _lastOnDeck) &&
        listEquals(_discover.hubs, _lastHubs) &&
        setEquals(_discover.unansweredServerIds, _lastUnansweredServerIds)) {
      return;
    }
    if (_projecting) {
      _projectionPending = true;
      return;
    }
    unawaited(_project());
  }

  Future<void> _project() async {
    _projecting = true;
    final latestMovies = _discover.latestMovies;
    final onDeck = _discover.onDeck;
    final hubs = _discover.hubs;
    try {
      final failedServerIds = _discover.unansweredServerIds;

      // A synthesized single-server-agnostic hub, exactly like
      // `TvDiscoveryLandingProvider`'s Continue Watching row: the one place
      // `latestMovies` becomes a `MediaHub` so it can go through the same
      // `projectHubs` identity pipeline as every other unified row, never a
      // second projection path.
      final latestMoviesHub = MediaHub(
        id: _latestMoviesHubId,
        title: _latestMoviesTitle,
        type: 'movie',
        items: latestMovies,
      );

      final results = await Future.wait([
        _service.projectContinueWatching(onDeck, title: _continueWatchingTitle, failedServerIds: failedServerIds),
        _service.projectHubs([latestMoviesHub], failedServerIds: failedServerIds),
        _service.projectHubs(hubs, failedServerIds: failedServerIds),
      ]);

      final continueWatching = results[0] as UnifiedMediaHub;
      final latestMoviesProjected = results[1] as List<UnifiedMediaHub>;
      final otherHubs = results[2] as List<UnifiedMediaHub>;

      _continueWatching = continueWatching.isEmpty ? null : continueWatching;
      final latestRow = latestMoviesProjected.isEmpty ? null : latestMoviesProjected.first;
      _latestMoviesRow = latestRow == null || latestRow.isEmpty ? null : latestRow;
      _hubs = otherHubs;
      // The hero, from the projected recent-films row and nothing else
      // (DEC-067). `FeaturedSelector` never re-ranks, so
      // `DiscoverProvider.latestMovies`' release-date order survives the
      // projection; what it does do is drop ineligible titles (loose
      // episodes, unreleased metadata, no usable title) and collapse two
      // servers' copies of one film into the single logical slide the old
      // `latestMovies`-driven rotation showed twice.
      //
      // Hubs are deliberately *not* appended. Padding a short hero with Top
      // Picks or recently-added series would make the billboard claim "newly
      // out" about titles that are not, and hoofdstuk 9.5's five-to-eight
      // band is an upper bound plus a preference, not a quota to fill with
      // whatever is at hand. Continue Watching is not an input either — it is
      // its own rail below the hero.
      _heroGroups = _featuredSelector.select(latestMoviesProjected);
      _hasProjectedHero = true;
      // The activation-lookup pool, uncapped and covering everything
      // `DiscoverScreen` can put in the billboard that is *not* a hero slide
      // (see `featuredGroupFor`): rail focus, and the empty-hero fallback to
      // Continue Watching or a hub item.
      _allProjectedGroups = [
        for (final hub in [continueWatching, ...latestMoviesProjected, ...otherHubs]) ...hub.groups,
      ];
      _lastLatestMovies = latestMovies;
      _lastOnDeck = onDeck;
      _lastHubs = hubs;
      _lastUnansweredServerIds = failedServerIds;
      safeNotifyListeners();
    } catch (error, stackTrace) {
      appLogger.e('TvHomeProjectionProvider: projection failed', error: error, stackTrace: stackTrace);
    } finally {
      _projecting = false;
      if (_projectionPending) {
        _projectionPending = false;
        unawaited(_project());
      }
    }
  }

  @override
  void dispose() {
    _discover.removeListener(_onDiscoverChanged);
    super.dispose();
  }
}
