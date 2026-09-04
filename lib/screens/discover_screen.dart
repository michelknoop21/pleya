import 'dart:async';
import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../automation/automation_screen.dart';
import '../media/ids.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, LogicalKeyboardKey;
import 'package:pleya/widgets/app_icon.dart';
import 'package:pleya/widgets/pleya_logo.dart';
import '../widgets/server_activities_button.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../focus/focusable_action_bar.dart';
import '../focus/focusable_button.dart';
import '../focus/focusable_wrapper.dart';
import '../focus/focus_theme.dart';
import '../focus/input_mode_tracker.dart';
import '../focus/key_event_utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';

import '../services/apple_tv_remote_touch_service.dart';
import '../services/download_artwork_helpers.dart';
import '../services/image_cache_service.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../media/media_hub.dart';
import 'discover_scope.dart';
import '../utils/media_image_helper.dart';
import '../widgets/optimized_media_image.dart' show blurArtwork;
import '../widgets/home_hero_artwork.dart';
import '../providers/discover_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/home_layout_provider.dart';
import '../providers/watch_state_store.dart';
import '../widgets/discover_refresh_action.dart';
import '../widgets/hub_section.dart';
import '../widgets/app_menu.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/skeletons.dart';
import '../widgets/state_view.dart';
import '../widgets/profile_switching_overlay.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile.dart';
import '../profiles/profile_activation.dart';
import '../profiles/profile_avatar.dart';
import '../services/account_ui_actions.dart';
import '../services/settings_service.dart';
import '../providers/now_watching_provider.dart';
import '../widgets/now_watching/now_watching_button.dart';
import '../widgets/settings_builder.dart';
import '../widgets/fitting_title_text.dart';
import '../widgets/tv_browse_rail.dart';
import '../widgets/tv_spotlight_background.dart';
import '../mixins/refreshable.dart';
import '../mixins/tab_visibility_aware.dart';
import '../i18n/strings.g.dart';
import '../navigation/navigation_tabs.dart';
import '../utils/app_logger.dart';
import '../utils/home_hero_layout.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/provider_extensions.dart';
import '../utils/video_player_navigation.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';
import '../services/fullscreen_state_manager.dart';
import '../utils/desktop_window_padding.dart';
import '../widgets/top_ten_row.dart';
import '../theme/mono_tokens.dart';
import '../utils/formatters.dart' show formatDurationTextual;
import 'libraries/content_state_builder.dart';
import 'main_screen.dart';
import 'settings/settings_screen.dart';
import '../watch_together/watch_together.dart';
import '../providers/companion_remote_provider.dart';
import '../widgets/companion_remote/remote_session_dialog.dart';
import 'companion_remote/mobile_remote_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.scope = DiscoverScope.all});

  /// Which slice of the catalog this instance shows. [DiscoverScope.all] is
  /// Home and the default, so every existing call site keeps its behaviour;
  /// Series and Films are the same screen with a type filter ([DEC-094]).
  final DiscoverScope scope;

  /// The hero's pagination-dot row, so tests can measure its real rect
  /// against the "Verder kijken" heading directly below the hero.
  static const Key heroPaginationKey = Key('home-hero-pagination');

  /// The overlaid appbar's control row (logo/title plus the action cluster),
  /// so tests can measure its real rect against the hero's sharp artwork
  /// layer directly below it.
  static const Key appBarControlsKey = Key('home-appbar-controls');

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with Refreshable, FullRefreshable, TabVisibilityAware, FocusableTab, WidgetsBindingObserver {
  static const Duration _heroAutoScrollDuration = Duration(seconds: 8);
  static const Duration _indicatorUpdateInterval = Duration(milliseconds: 200);
  // Home rows are a touch shorter than the shared compact scale so the billboard
  // hero gets more screen height (Netflix-style: big hero, one row peeking).
  // ponytail: single knob — lower for an even taller hero, raise to restore.
  // Home "Continue watching" rail uses the same poster size as every other TV
  // rail (compactTallPosterScale) and the same libraryDensity setting, so the
  // cards match the rest of the app and scale with the density preference. The
  // hero content always reserves `railHeight + gap` below it, so its action
  // buttons never slide behind the rail — the hero simply takes whatever height
  // the rail leaves.
  // Layout constants live in [MonoTokens] (tvHeroContentTopFraction,
  // tvHomeRailMaxPeekFraction, tvHeroRailGap, tvHeroMinInfoHeight).

  /// Data + refresh policy live in [DiscoverProvider]; this state keeps only
  /// UI concerns (hero carousel, focus, spotlight). The proxy getters keep
  /// the build code reading naturally.
  late final DiscoverProvider _discover;
  int _seenLoadGeneration = 0;

  List<MediaItem> get _onDeck => _scoped(_discover.onDeck);
  // Hero source: newest released films (release-date ordered), not on-deck.
  // Series filters it down to shows, so the Series landing does not open on a
  // film. An empty result is a hero-less landing, not a wrong one.
  List<MediaItem> get _latestMovies => _scoped(_discover.latestMovies);
  HomeLayoutProvider? _homeLayout;
  // User layout (hide + reorder) applied here, the single choke point both the
  // mobile sliver loop and the TV rail read from.
  List<MediaHub> get _hubs {
    final laidOut = _homeLayout?.apply(_discover.hubs, _hubIdentity) ?? _discover.hubs;
    if (!widget.scope.isFiltered) return laidOut;
    // Filter inside each row and drop the rows that empty out, rather than
    // keeping a row whose header promises items it no longer has.
    return [
      for (final hub in laidOut)
        if (_scoped(hub.items) case final items when items.isNotEmpty)
          hub.copyWith(items: items, size: items.length, more: false),
    ];
  }

  /// The scope filter, in one place so the hero, Continue Watching and the
  /// rails cannot disagree about what belongs on this landing.
  List<MediaItem> _scoped(List<MediaItem> items) {
    if (!widget.scope.isFiltered) return items;
    return items.where((item) => widget.scope.admitsKind(item.kind)).toList();
  }

  bool get _hasMoreContinueWatching => _discover.hasMoreContinueWatching;
  bool get _isLoading => _discover.isLoading;
  bool get _areHubsLoading => _discover.areHubsLoading;
  String? get _errorMessage => _discover.errorMessage;

  bool _switchingProfile = false;
  final PageController _heroController = PageController();
  final ScrollController _scrollController = ScrollController();
  int _currentHeroIndex = 0;
  Timer? _autoScrollTimer;
  Timer? _indicatorTimer;
  Timer? _tvHeroManualPauseTimer;
  final ValueNotifier<double> _indicatorProgress = ValueNotifier(0.0);
  bool _isAutoScrollPaused = false;
  bool _heroFocusPausedAutoScroll = false;
  // ValueNotifier (not setState) so a spotlight swap rebuilds only the
  // TvSpotlightBackground subtree, never the rail/rows.
  final ValueNotifier<MediaItem?> _spotlightItem = ValueNotifier(null);

  /// True once something other than the default pinned the spotlight (rail
  /// focus, manual hero navigation, auto-rotate). While false the hero keeps
  /// following [_defaultSpotlightItem] — a mount-time focus echo from the rail
  /// must not pin Continue Watching before the latest movies land.
  bool _spotlightUserDriven = false;

  /// Rail focus fires per D-pad step; without this every tile passed over
  /// would trigger a cross-fade and a backdrop fetch.
  Timer? _spotlightDebounce;
  bool _isTabVisible = true;

  // Track initial load so we can focus hero when content first appears
  bool _initialLoadComplete = false;
  bool _pendingTvBrowseRailFocus = false;

  // tvOS "Netflix landing": at rest the hero fills the screen and the browse
  // rail only peeks at the bottom. Focusing the rail reveals it (slides up over
  // the hero); focusing the hero actions hides it again.
  bool _tvRailRevealed = false;

  // Hub navigation keys
  GlobalKey<HubSectionState>? _continueWatchingHubKey;
  final Map<String, GlobalKey<HubSectionState>> _hubKeysByIdentity = {};
  List<GlobalKey<HubSectionState>> _orderedHubKeys = const [];
  final _tvBrowseRailKey = GlobalKey<TvBrowseRailState>();

  // Hero and app bar focus
  late FocusNode _heroFocusNode;
  // TV Netflix-style billboard action buttons (Play / More info).
  final FocusNode _tvHeroPlayFocusNode = FocusNode(debugLabel: 'tv_hero_play');
  final FocusNode _tvHeroInfoFocusNode = FocusNode(debugLabel: 'tv_hero_info');
  final _actionBarKey = GlobalKey<FocusableActionBarState>();
  final _serverActivitiesButtonKey = GlobalKey<ServerActivitiesButtonState>();
  final _nowWatchingButtonKey = GlobalKey<NowWatchingButtonState>();

  /// Held so the ambient poll can be released when Home goes away.
  NowWatchingProvider? _nowWatching;
  final _userMenuKey = GlobalKey<AppMenuButtonState<String>>();

  /// Backend-neutral hero client lookup. Returns the actual
  /// [MediaServerClient] for the item's server (Plex or Jellyfin) so
  /// [MediaImageHelper] uses the right transcoder for sized URLs.
  MediaServerClient? _getMediaClientForItem(MediaItem? item) {
    final serverId = item?.serverId;
    if (serverId == null) {
      return context.tryGetMediaClientForServer(null);
    }
    return context.tryGetMediaClientForServer(ServerId(serverId));
  }

  String _hubIdentity(MediaHub hub) => homeRowId(hub);

  /// Rebuild the per-hub focus keys, keyed by hub *identity* rather than
  /// list position so a row's focus memory follows it when the provider
  /// re-sorts hubs (library-order change). Existing keys are reused to avoid
  /// mass deep unmounts (ARM32 stack overflow during finalizeTree);
  /// duplicate identities get positional suffixes so two rows can never
  /// share a GlobalKey.
  void _updateHubKeys() {
    final occurrences = <String, int>{};
    final liveIdentities = <String>{};
    final ordered = <GlobalKey<HubSectionState>>[];
    for (final hub in _hubs) {
      var identity = _hubIdentity(hub);
      final occurrence = occurrences.update(identity, (n) => n + 1, ifAbsent: () => 0);
      if (occurrence > 0) identity = '$identity#$occurrence';
      liveIdentities.add(identity);
      ordered.add(_hubKeysByIdentity.putIfAbsent(identity, GlobalKey<HubSectionState>.new));
    }
    _hubKeysByIdentity.removeWhere((identity, _) => !liveIdentities.contains(identity));
    _orderedHubKeys = ordered;
    _continueWatchingHubKey ??= GlobalKey<HubSectionState>();
  }

  /// Get all hub states (continue watching + other hubs)
  List<GlobalKey<HubSectionState>> get _allHubKeys {
    final keys = <GlobalKey<HubSectionState>>[];
    if (_continueWatchingHubKey != null && _onDeck.isNotEmpty) {
      keys.add(_continueWatchingHubKey!);
    }
    keys.addAll(_orderedHubKeys);
    return keys;
  }

  bool get _isHeroSectionVisible => _latestMovies.isNotEmpty && context.settingsRead(SettingsService.showHeroSection);

  MediaItem? get _defaultSpotlightItem {
    if (_latestMovies.isNotEmpty) return _latestMovies.first;
    // Still loading: don't flash a Continue Watching item as the hero — the
    // latest-movies row usually lands a beat after on-deck.
    if (_areHubsLoading) return null;
    // Movies-empty libraries (e.g. show-only servers — latest movies is
    // films-only) still have Continue Watching + hubs; fall back to those so
    // the TV billboard is never blank while the rail shows content. _onDeck is
    // the first row on TV, so it precedes the generic hubs.
    if (_onDeck.isNotEmpty) return _onDeck.first;
    for (final hub in _hubs) {
      if (hub.items.isNotEmpty) return hub.items.first;
    }
    return null;
  }

  List<MediaHub> get _tvBrowseHubs {
    final hubs = <MediaHub>[];
    if (_onDeck.isNotEmpty) {
      hubs.add(
        MediaHub(
          id: 'continue_watching',
          title: t.discover.continueWatching,
          type: 'mixed',
          identifier: '_continue_watching_',
          size: _onDeck.length + (_hasMoreContinueWatching ? 1 : 0),
          more: _hasMoreContinueWatching,
          items: _onDeck,
        ),
      );
    }
    // Recently Added rail directly under Continue Watching — same set that feeds
    // the hero, surfaced as a browsable row.
    if (_latestMovies.isNotEmpty) {
      hubs.add(
        MediaHub(
          id: 'latest_movies',
          title: t.discover.recentlyReleased,
          type: 'movie',
          identifier: '_latest_movies_',
          size: _latestMovies.length,
          items: _latestMovies,
        ),
      );
    }
    hubs.addAll(_hubs.where((hub) => hub.items.isNotEmpty));
    return hubs;
  }

  MediaItem? get _effectiveSpotlightItem {
    // Until the user actually drives the spotlight (rail focus, manual hero
    // navigation, auto-rotate), keep tracking the default so the hero upgrades
    // itself the moment the latest-movies row arrives.
    if (!_spotlightUserDriven) return _defaultSpotlightItem;
    final current = _spotlightItem.value;
    if (current == null) return _defaultSpotlightItem;
    if (_latestMovies.any((item) => item.globalKey == current.globalKey)) return current;
    if (_onDeck.any((item) => item.globalKey == current.globalKey)) return current;
    for (final hub in _hubs) {
      if (hub.items.any((item) => item.globalKey == current.globalKey)) return current;
    }
    return _defaultSpotlightItem;
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _focusTopActions() {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final actionBar = _actionBarKey.currentState;
    if (actionBar != null) {
      actionBar.requestFocusOnFirst();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
      _actionBarKey.currentState?.requestFocusOnFirst();
    });
  }

  void _focusTopBoundary() {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    if (PlatformDetector.isTV()) {
      _focusTopActions();
    } else if (_isHeroSectionVisible) {
      _heroFocusNode.requestFocus();
    } else {
      _focusTopActions();
    }
    _scrollToTop();
  }

  void _focusContentFromAppBar() {
    if (PlatformDetector.isTV()) {
      _focusTvBrowseRailWhenReady(immediate: true);
      return;
    }

    if (_isHeroSectionVisible) {
      _heroFocusNode.requestFocus();
      return;
    }

    final keys = _allHubKeys;
    if (keys.isNotEmpty) {
      keys.first.currentState?.requestFocusFromMemory();
    }
  }

  void _focusTvBrowseRailWhenReady({bool immediate = false}) {
    if (!PlatformDetector.isTV()) return;
    final suppressSelectUntilKeyUp = _isSelectKeyPressed;
    if (!_isTabVisible || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      _pendingTvBrowseRailFocus = false;
      return;
    }

    _pendingTvBrowseRailFocus = true;
    if (immediate && _tvBrowseHubs.isNotEmpty) {
      final rail = _tvBrowseRailKey.currentState;
      if (rail != null) {
        _pendingTvBrowseRailFocus = false;
        rail.requestFocus();
        if (suppressSelectUntilKeyUp) rail.suppressSelectUntilKeyUp();
        return;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isTabVisible || !(ModalRoute.of(context)?.isCurrent ?? false)) {
        _pendingTvBrowseRailFocus = false;
        return;
      }
      if (_tvBrowseHubs.isEmpty) return;
      final rail = _tvBrowseRailKey.currentState;
      if (rail == null) return;
      _pendingTvBrowseRailFocus = false;
      rail.requestFocus();
      if (suppressSelectUntilKeyUp) rail.suppressSelectUntilKeyUp();
    });
  }

  bool get _isSelectKeyPressed {
    return HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.enter ||
          key.keyId == 0x0d ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.gameButtonA,
    );
  }

  void _applyPendingTvBrowseRailFocus() {
    if (_pendingTvBrowseRailFocus) _focusTvBrowseRailWhenReady();
  }

  /// Reveal (rail slides up over the hero) or hide (only peeks) the TV browse
  /// rail. Driven by focus: the rail focusing reveals it, a hero action focusing
  /// hides it.
  void _setTvRailRevealed(bool revealed) {
    if (!mounted || _tvRailRevealed == revealed) return;
    setState(() => _tvRailRevealed = revealed);
    if (revealed) {
      // Rail focus drives the hero now — stop auto-rotate so it doesn't fight
      // the focus-follow.
      _autoScrollTimer?.cancel();
      _stopIndicatorProgress();
    } else {
      // Focus left the rail (back to hero): restore the featured item and resume.
      // Skip the restart when a route is pushed over us (e.g. opening a detail
      // from a rail item) so the timer doesn't churn the hidden hero.
      _spotlightUserDriven = false;
      _spotlightItem.value = _defaultSpotlightItem;
      final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
      if (_isTabVisible && !_isAutoScrollPaused && isCurrent) _startAutoScroll();
    }
  }

  /// Handle vertical navigation between hubs
  /// Returns true if the navigation was handled
  bool _handleVerticalNavigation(int hubIndex, bool isUp) {
    final keys = _allHubKeys;
    if (keys.isEmpty) return false;

    // UP from first hub: navigate to hero when visible, otherwise app bar
    if (isUp && hubIndex == 0) {
      if (PlatformDetector.isTV()) {
        _focusTopActions();
        return true;
      }
      _focusTopBoundary();
      return true;
    }

    final targetIndex = isUp ? hubIndex - 1 : hubIndex + 1;

    // Check if target is valid
    if (targetIndex < 0 || targetIndex >= keys.length) {
      // At boundary, block navigation (return true to consume the event)
      return true;
    }

    // Navigate to target hub, clamping to available items
    final targetState = keys[targetIndex].currentState;
    if (targetState != null) {
      targetState.requestFocusFromMemory();
      return true;
    }

    return false;
  }

  /// Navigate focus to the sidebar
  void _navigateToSidebar() {
    MainScreenFocusScope.of(context, listen: false)?.focusSidebar();
  }

  /// Focus the TV billboard's primary (Play) action. Falls back to the top app
  /// bar when no billboard item is present (buttons not mounted).
  void _focusTvHeroPlay() {
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    if (_effectiveSpotlightItem == null) {
      _focusTopActions();
      return;
    }
    // While the rail is revealed the hero info is faded out and its actions sit
    // under an ExcludeFocus (see TvSpotlightBackground), so the Play node can't
    // take focus yet. Drop the reveal first, then focus once the rebuild
    // re-enables the node — otherwise UP from the top row falls through to the
    // app bar and the hero becomes unreachable.
    if (_tvRailRevealed) {
      _setTvRailRevealed(false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tvHeroPlayFocusNode.canRequestFocus) {
          _tvHeroPlayFocusNode.requestFocus();
        } else {
          _focusTopActions();
        }
      });
      return;
    }
    if (_tvHeroPlayFocusNode.canRequestFocus) {
      _tvHeroPlayFocusNode.requestFocus();
    } else {
      _focusTopActions();
    }
  }

  /// Move focus from the billboard's Play pill to the More-info pill. Falls
  /// back to advancing the hero carousel when the info node isn't mounted, so
  /// RIGHT never becomes a dead key.
  void _focusTvHeroInfoOrAdvance() {
    if (_tvHeroInfoFocusNode.canRequestFocus) {
      _tvHeroInfoFocusNode.requestFocus();
    } else {
      _moveTvHero(1);
    }
  }

  /// Mirror of [_focusTvHeroInfoOrAdvance] for LEFT from the More-info pill.
  void _focusTvHeroPlayOrAdvance() {
    if (_tvHeroPlayFocusNode.canRequestFocus) {
      _tvHeroPlayFocusNode.requestFocus();
    } else {
      _moveTvHero(-1);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _heroFocusNode = FocusNode(debugLabel: 'hero_section');
    _heroFocusNode.addListener(_onHeroFocusChanged);
    _tvHeroPlayFocusNode.addListener(_onTvHeroActionFocusChanged);
    _tvHeroInfoFocusNode.addListener(_onTvHeroActionFocusChanged);
    _discover = context.read<DiscoverProvider>();
    _seenLoadGeneration = _discover.loadGeneration;
    _discover.addListener(_onDiscoverChanged);
    _updateHubKeys();
    unawaited(_discover.load());
    _startAutoScroll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Home is the surface that carries the now-watching indicator, so it is
    // Home that asks Tautulli once a minute whether anyone is streaming. The
    // subscription cannot live in the button: the button only exists while
    // there is something to show, and a widget that unmounts when the answer
    // is "nobody" could never learn that the answer changed. Kept before the
    // early return below, which is about a different provider.
    final nowWatching = context.read<NowWatchingProvider?>();
    if (!identical(nowWatching, _nowWatching)) {
      _nowWatching?.releaseAmbient();
      _nowWatching = nowWatching?..watchAmbient();
    }

    // Resolve with listen: true so this rebinds when the provider instance is
    // swapped (profile switch / session subtree rebuild). Binding once in
    // initState left us listening to a stale notifier: the settings screen
    // wrote to the new one and home only caught up after an app restart.
    final layout = Provider.of<HomeLayoutProvider>(context);
    if (identical(layout, _homeLayout)) return;
    _homeLayout?.removeListener(_onHomeLayoutChanged);
    _homeLayout = layout..addListener(_onHomeLayoutChanged);
    _updateHubKeys();
  }

  void _onHomeLayoutChanged() {
    if (!mounted) return;
    setState(_updateHubKeys);
  }

  /// Mirror provider changes into this state's UI concerns: rebuild, apply
  /// pending TV-rail focus, and keep the hero carousel index in sync — a
  /// fresh [DiscoverProvider.load] resets it, a background Continue Watching
  /// refresh only clamps it.
  void _onDiscoverChanged() {
    if (!mounted) return;
    final generation = _discover.loadGeneration;
    final isNewLoad = generation != _seenLoadGeneration;
    _seenLoadGeneration = generation;
    final heroOutOfBounds = _currentHeroIndex >= _latestMovies.length;

    setState(() {
      if (isNewLoad || heroOutOfBounds) {
        _currentHeroIndex = 0;
      }
      _updateHubKeys();
    });
    _applyPendingTvBrowseRailFocus();

    // Row endpoints omit art/clearLogo, so the first hero page would render a
    // blurred poster until the user swipes. Prime the visible page + neighbours
    // once per load, off the build phase.
    if ((isNewLoad || heroOutOfBounds) && _latestMovies.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ensureHeroArt(_currentHeroIndex);
      });
    }

    if ((isNewLoad || heroOutOfBounds) && _heroController.hasClients && _latestMovies.isNotEmpty) {
      _heroController.jumpToPage(0);
    }
    // Focus hero when fresh content lands, but only if no modal route is on top
    if (isNewLoad &&
        !PlatformDetector.isTV() &&
        _latestMovies.isNotEmpty &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _heroFocusNode.requestFocus();
    }

    // On initial load, focus content so the user doesn't start on the toolbar
    if (!_initialLoadComplete) {
      if (PlatformDetector.isTV() && (_latestMovies.isNotEmpty || _onDeck.isNotEmpty || _hubs.isNotEmpty)) {
        _initialLoadComplete = true;
        // Netflix-style: land focus on the billboard Play button when a
        // spotlight item exists; otherwise fall back to the content rail.
        if (_effectiveSpotlightItem != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _focusTvHeroPlay();
          });
        } else {
          _focusTvBrowseRailWhenReady();
        }
      } else if (PlatformDetector.isTV() && !_isLoading && !_areHubsLoading) {
        // Genuinely empty account (no hero, no on-deck, no other hub) — the
        // branch above never fires because it waits for content that is
        // never coming, which otherwise leaves the remote with no focused
        // node at all: Left/Right/Down are silently swallowed because
        // nothing owns them (see CLAUDE.md's tvOS engine-swizzle gotcha).
        // Land on the top app bar instead, same as `_focusTvHeroPlay`'s own
        // no-spotlight fallback.
        _initialLoadComplete = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _focusTopActions();
        });
      } else if (!PlatformDetector.isTV() && _latestMovies.isNotEmpty) {
        _initialLoadComplete = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
          if (_heroFocusNode.canRequestFocus) {
            _heroFocusNode.requestFocus();
          }
        });
      }
    }
  }

  void _onHeroFocusChanged() {
    if (!PlatformDetector.isTV()) return;

    if (_heroFocusNode.hasFocus) {
      _heroFocusPausedAutoScroll = true;
      _autoScrollTimer?.cancel();
      _stopIndicatorProgress();
      return;
    }

    if (_heroFocusPausedAutoScroll) {
      _heroFocusPausedAutoScroll = false;
      if (_isTabVisible && !_isAutoScrollPaused) _startAutoScroll();
    }
  }

  void _onTvHeroActionFocusChanged() {
    if (!PlatformDetector.isTV()) return;
    if (_tvHeroPlayFocusNode.hasFocus || _tvHeroInfoFocusNode.hasFocus) {
      _autoScrollTimer?.cancel();
      _stopIndicatorProgress();
    } else if (_isTabVisible && !_isAutoScrollPaused) {
      _startAutoScroll();
    }
  }

  /// Settle the billboard on the item the user actually stopped on. Nulls
  /// apply immediately — that's a focus leave, not a scroll-through.
  void _setSpotlightDebounced(MediaItem? item) {
    _spotlightDebounce?.cancel();
    if (item == null) {
      _spotlightItem.value = null;
      return;
    }
    _spotlightDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _spotlightUserDriven = true;
      _spotlightItem.value = _spotlightArtCache[item.globalKey] ?? item;
      _enrichSpotlightArt(item);
    });
  }

  /// Row items come from list endpoints that often omit art/clearLogo the
  /// server does have. Fetch the full item (the show, for episodes) once and
  /// merge its art in, so the billboard shows real fitted artwork instead of
  /// the blurred poster fallback. Failures cache too — no fetch storms.
  final Map<String, MediaItem?> _spotlightArtCache = {};

  // Ask the same question the renderer asks: does this item already resolve to
  // a real 16:9 backdrop? `backgroundSquarePath` counts as art but *not* as a
  // backdrop, so counting it here would skip exactly the items that render as
  // a blurred stand-in.
  bool _hasBillboardArt(MediaItem item) => item.billboardArt()?.canRenderSharp == true;

  Future<void> _enrichSpotlightArt(MediaItem item) async {
    final key = item.globalKey;
    if (_spotlightArtCache.containsKey(key)) return;
    if (_hasBillboardArt(item) && (item.clearLogoPath?.isNotEmpty ?? false)) return;
    _spotlightArtCache[key] = null; // in-flight / failed marker
    try {
      final client = _getMediaClientForItem(item);
      if (client == null) return;
      // For episodes prefer the show: that's where the hero art + logo live.
      final fetchId = (item.isEpisode ? item.grandparentId : null) ?? item.id;
      final full = await client.fetchItem(fetchId);
      if (full == null) return;
      final enriched = item.copyWith(
        artPath: item.artPath ?? full.artPath,
        grandparentArtPath: item.grandparentArtPath ?? full.artPath,
        backgroundSquarePath: item.backgroundSquarePath ?? full.backgroundSquarePath,
        clearLogoPath: item.clearLogoPath ?? full.clearLogoPath,
      );
      _spotlightArtCache[key] = enriched;
      if (!mounted) return;
      // Still the focused item? Swap in place — the AnimatedSwitcher
      // crossfades from the blurred fill to the real artwork.
      if (_spotlightItem.value?.globalKey == key) {
        _spotlightItem.value = enriched;
      } else if (_latestMovies.any((m) => m.globalKey == key)) {
        // Phone hero: the PageView reads straight from _latestMovies through
        // the cache, so a rebuild is what swaps the blurred poster for the
        // real backdrop.
        setState(() {});
      }
    } catch (_) {
      // Cached null already prevents retries; art simply stays blurred.
    }
  }

  /// Enrich the hero page at [index] plus its immediate neighbours, so a swipe
  /// lands on already-fetched art. Bounded to 3 items — never the whole row.
  void _ensureHeroArt(int index) {
    for (var i = index - 1; i <= index + 1; i++) {
      if (i < 0 || i >= _latestMovies.length) continue;
      unawaited(_enrichSpotlightArt(_latestMovies[i]));
    }
  }

  void _moveTvHero(int delta) {
    if (_latestMovies.isEmpty) return;
    final current = _effectiveSpotlightItem;
    final currentIndex = current == null ? -1 : _latestMovies.indexWhere((m) => m.globalKey == current.globalKey);
    final baseIndex = currentIndex == -1 ? _currentHeroIndex.clamp(0, _latestMovies.length - 1).toInt() : currentIndex;
    final nextIndex = baseIndex + delta;
    // Finite carousel, same convention as the phone hero and the browse rails:
    // left off the first item exits into the sidebar, right off the last stays put.
    if (nextIndex < 0) {
      _navigateToSidebar();
      return;
    }
    if (nextIndex >= _latestMovies.length) return;
    setState(() => _currentHeroIndex = nextIndex);
    _spotlightUserDriven = true;
    _spotlightItem.value = _latestMovies[nextIndex];
    _pauseTvHeroAutoScrollForManualNavigation();
  }

  void _pauseTvHeroAutoScrollForManualNavigation() {
    if (!PlatformDetector.isTV()) return;
    _autoScrollTimer?.cancel();
    _tvHeroManualPauseTimer?.cancel();
    _tvHeroManualPauseTimer = Timer(_heroAutoScrollDuration, () {
      if (!mounted || !_isTabVisible || _isAutoScrollPaused) return;
      if (_tvHeroPlayFocusNode.hasFocus || _tvHeroInfoFocusNode.hasFocus) return;
      _startAutoScroll();
    });
  }

  /// Handle key events for the hero section.
  KeyEventResult _handleHeroKeyEvent(FocusNode node, KeyEvent event) {
    final backResult = handleBackKeyAction(event, _navigateToSidebar);
    if (backResult != KeyEventResult.ignored) return backResult;

    return dpadKeyHandler(
      onDown: () {
        final keys = _allHubKeys;
        if (keys.isNotEmpty) keys.first.currentState?.requestFocusFromMemory();
      },
      onUp: _focusTopActions,
      onLeft: () {
        if (_currentHeroIndex > 0) {
          _heroController.previousPage(duration: tokens(context).slow, curve: Curves.easeInOut);
        } else {
          _navigateToSidebar();
        }
      },
      onRight: () {
        if (_currentHeroIndex < _latestMovies.length - 1) {
          _heroController.nextPage(duration: tokens(context).slow, curve: Curves.easeInOut);
        }
      },
      // Enter follows the click. The element announces itself as "View
      // details", and an element that opens on click but plays on Enter is the
      // same invisible split that caused the bug. Playback stays one Tab away
      // on the pill itself.
      onSelect: () {
        if (_latestMovies.isNotEmpty && _currentHeroIndex < _latestMovies.length) {
          navigateToMediaItemDetails(context, _latestMovies[_currentHeroIndex]);
        }
      },
    )(node, event);
  }

  @override
  void dispose() {
    _discover.removeListener(_onDiscoverChanged);
    _homeLayout?.removeListener(_onHomeLayoutChanged);
    _nowWatching?.releaseAmbient();
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollTimer?.cancel();
    _indicatorTimer?.cancel();
    _tvHeroManualPauseTimer?.cancel();
    _spotlightDebounce?.cancel();
    _spotlightItem.dispose();
    _indicatorProgress.dispose();
    _heroController.dispose();
    _scrollController.dispose();
    _heroFocusNode.removeListener(_onHeroFocusChanged);
    _heroFocusNode.dispose();
    _tvHeroPlayFocusNode.removeListener(_onTvHeroActionFocusChanged);
    _tvHeroInfoFocusNode.removeListener(_onTvHeroActionFocusChanged);
    _tvHeroPlayFocusNode.dispose();
    _tvHeroInfoFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Restart auto-scroll only if discover tab is visible
      if (_isTabVisible && !_isAutoScrollPaused) _startAutoScroll();
      // Refresh continue watching on mobile only
      // (on desktop, "resumed" fires on every window focus gain)
      if (Platform.isIOS || Platform.isAndroid) {
        unawaited(_discover.refreshContinueWatching());
      }
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      // Stop animations to prevent scroll state corruption while backgrounded
      _autoScrollTimer?.cancel();
      _stopIndicatorProgress();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    if (_isAutoScrollPaused) return;

    if (PlatformDetector.isTV()) {
      // TV billboard cycles through the newest releases. Timer is created up
      // front (content loads async); each tick bails until items are present
      // and while the hero actions are focused, so the Play/Info target never
      // shifts under the user mid-press.
      _autoScrollTimer = Timer.periodic(_heroAutoScrollDuration, (timer) {
        if (!mounted || _isAutoScrollPaused || _latestMovies.length < 2) return;
        if (_tvHeroPlayFocusNode.hasFocus || _tvHeroInfoFocusNode.hasFocus) return;
        // Rail revealed → the hero follows rail focus; don't let auto-rotate
        // mutate the spotlight out from under it (order-independent guard so a
        // stray timer restart can't fight focus-follow).
        if (_tvRailRevealed) return;
        final current = _spotlightItem.value ?? _defaultSpotlightItem;
        final idx = current == null ? -1 : _latestMovies.indexWhere((m) => m.globalKey == current.globalKey);
        _spotlightUserDriven = true;
        _spotlightItem.value = _latestMovies[(idx + 1) % _latestMovies.length];
      });
      return;
    }

    _startIndicatorProgress();
    _autoScrollTimer = Timer.periodic(_heroAutoScrollDuration, (timer) {
      if (_latestMovies.isEmpty || !_heroController.hasClients || _isAutoScrollPaused) {
        return;
      }

      // Validate current index is within bounds before calculating next page
      if (_currentHeroIndex >= _latestMovies.length) {
        _currentHeroIndex = 0;
      }

      final nextPage = (_currentHeroIndex + 1) % _latestMovies.length;
      _heroController.animateToPage(nextPage, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      // Wait for page transition to complete before resetting progress
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_isAutoScrollPaused) {
          _startIndicatorProgress();
        }
      });
    });
  }

  void _startIndicatorProgress() {
    if (!mounted) return;
    _indicatorTimer?.cancel();
    _indicatorProgress.value = 0.0;
    final totalSteps = _heroAutoScrollDuration.inMilliseconds ~/ _indicatorUpdateInterval.inMilliseconds;
    int step = 0;
    _indicatorTimer = Timer.periodic(_indicatorUpdateInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      step++;
      _indicatorProgress.value = (step / totalSteps).clamp(0.0, 1.0);
      if (step >= totalSteps) {
        timer.cancel();
      }
    });
  }

  void _stopIndicatorProgress() {
    _indicatorTimer?.cancel();
  }

  void _resetAutoScrollTimer() {
    _autoScrollTimer?.cancel();
    _startAutoScroll();
  }

  void _pauseAutoScroll() {
    setState(() {
      _isAutoScrollPaused = true;
    });
    _autoScrollTimer?.cancel();
    _stopIndicatorProgress();
  }

  void _resumeAutoScroll() {
    setState(() {
      _isAutoScrollPaused = false;
    });
    _startAutoScroll();
  }

  @override
  void onTabHidden() {
    _isTabVisible = false;
    _pendingTvBrowseRailFocus = false;
    _autoScrollTimer?.cancel();
    _stopIndicatorProgress();
  }

  @override
  void onTabShown() {
    _isTabVisible = true;
    if (!_isAutoScrollPaused) {
      _startAutoScroll();
    }
  }

  @override
  void focusActiveTabIfReady() {
    if (PlatformDetector.isTV()) {
      _focusTvBrowseRailWhenReady();
      return;
    }
    _focusTopBoundary();
  }

  // Helper method to calculate visible dot range (max 5 dots)
  ({int start, int end}) _getVisibleDotRange() {
    final totalDots = _latestMovies.length;
    if (totalDots <= 5) {
      return (start: 0, end: totalDots - 1);
    }

    // Center the active dot when possible
    final center = _currentHeroIndex;
    final int start = (center - 2).clamp(0, totalDots - 5);
    final int end = start + 4; // 5 dots total (0-4 inclusive)

    return (start: start, end: end);
  }

  // Helper method to determine dot size based on position
  double _getDotSize(int dotIndex, int start, int end) {
    final totalDots = _latestMovies.length;

    // If we have 5 or fewer dots, all are full size (8px)
    if (totalDots <= 5) {
      return 8.0;
    }

    // First and last visible dots are smaller if there are more items beyond them
    final isFirstVisible = dotIndex == start && start > 0;
    final isLastVisible = dotIndex == end && end < totalDots - 1;

    if (isFirstVisible || isLastVisible) {
      return 5.0; // Smaller edge dots
    }

    return 8.0; // Normal size
  }

  // Public method to refresh content (for normal navigation)
  @override
  void refresh() {
    // Only refresh Continue Watching in background, not full screen reload
    unawaited(_discover.refreshContinueWatching());
  }

  // Public method to fully reload all content (for profile switches)
  @override
  void fullRefresh() {
    unawaited(_discover.load());
  }

  /// Header refresh action. Also the D-pad handler for it, which is why the
  /// in-flight guard lives here rather than in [DiscoverRefreshAction]: the
  /// action list is built outside that widget's rebuild.
  void _handleRefreshPressed() {
    if (_discover.isRefreshing) return;
    unawaited(_discover.load());
  }

  /// Get icon for hub based on its title
  IconData _getHubIcon(String title) {
    final lowerTitle = title.toLowerCase();

    // Trending/Popular content
    if (lowerTitle.contains('trending')) {
      return Symbols.trending_up_rounded;
    }
    if (lowerTitle.contains('popular') || lowerTitle.contains('imdb')) {
      return Symbols.whatshot_rounded;
    }

    // Seasonal/Time-based
    if (lowerTitle.contains('seasonal')) {
      return Symbols.calendar_month_rounded;
    }
    if (lowerTitle.contains('newly') || lowerTitle.contains('new release')) {
      return Symbols.new_releases_rounded;
    }
    if (lowerTitle.contains('recently released') || lowerTitle.contains('recent')) {
      return Symbols.schedule_rounded;
    }

    // Top/Rated content
    if (lowerTitle.contains('top rated') || lowerTitle.contains('highest rated')) {
      return Symbols.star_rounded;
    }
    if (lowerTitle.contains('top ')) {
      return Symbols.military_tech_rounded;
    }

    // Genre-specific
    if (lowerTitle.contains('thriller')) {
      return Symbols.warning_amber_rounded;
    }
    if (lowerTitle.contains('comedy') || lowerTitle.contains('comedier')) {
      return Symbols.mood_rounded;
    }
    if (lowerTitle.contains('action')) {
      return Symbols.flash_on_rounded;
    }
    if (lowerTitle.contains('drama')) {
      return Symbols.theater_comedy_rounded;
    }
    if (lowerTitle.contains('fantasy')) {
      return Symbols.auto_fix_high_rounded;
    }
    if (lowerTitle.contains('science') || lowerTitle.contains('sci-fi')) {
      return Symbols.rocket_launch_rounded;
    }
    if (lowerTitle.contains('horror') || lowerTitle.contains('skräck')) {
      return Symbols.nights_stay_rounded;
    }
    if (lowerTitle.contains('romance') || lowerTitle.contains('romantic')) {
      return Symbols.favorite_border_rounded;
    }
    if (lowerTitle.contains('adventure') || lowerTitle.contains('äventyr')) {
      return Symbols.explore_rounded;
    }

    // Watchlist/Playlists
    if (lowerTitle.contains('playlist') || lowerTitle.contains('watchlist')) {
      return Symbols.playlist_play_rounded;
    }
    if (lowerTitle.contains('unwatched') || lowerTitle.contains('unplayed')) {
      return Symbols.visibility_off_rounded;
    }
    if (lowerTitle.contains('watched') || lowerTitle.contains('played')) {
      return Symbols.visibility_rounded;
    }

    // Network/Studio
    if (lowerTitle.contains('network') || lowerTitle.contains('more from')) {
      return Symbols.tv_rounded;
    }

    // Actor/Director
    if (lowerTitle.contains('actor') || lowerTitle.contains('director')) {
      return Symbols.person_rounded;
    }

    // Year-based (80s, 90s, etc.)
    if (lowerTitle.contains('80') || lowerTitle.contains('90') || lowerTitle.contains('00')) {
      return Symbols.history_rounded;
    }

    // Rediscover/Start Watching
    if (lowerTitle.contains('rediscover') || lowerTitle.contains('start watching')) {
      return Symbols.play_arrow_rounded;
    }

    // Default icon for other hubs
    return Symbols.auto_awesome_rounded;
  }

  /// Whether the loaded hubs span more than one connected server.
  bool _hubsSpanMultipleServers() {
    final serverIds = _hubs.where((hub) => hub.serverId != null).map((hub) => hub.serverId).toSet();
    return serverIds.length > 1;
  }

  Future<void> _handleLogout() async {
    await AccountUiActions.logout(context);
  }

  void _handleSwitchProfile(BuildContext context) {
    AccountUiActions.openProfiles(context);
  }

  void _handleOpenSettings(BuildContext context) {
    final mainScope = MainScreenFocusScope.of(context, listen: false);
    if (mainScope != null) {
      mainScope.openSettings?.call();
      return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  /// Build the [FocusableAction] wrapping the user menu.
  /// Pulls live state from [ActiveProfileProvider]; the menu reuses
  /// [_userMenuItems] for the menu contents so d-pad and tap paths
  /// stay in sync.
  FocusableAction _buildUserMenuAction(BuildContext context) {
    final activeProvider = context.watch<ActiveProfileProvider>();
    final active = activeProvider.active;
    final profiles = activeProvider.profiles;

    return FocusableAction(
      onPressed: _switchingProfile ? null : () => _userMenuKey.currentState?.showButtonMenu(focusFirstItem: true),
      child: AppMenuButton<String>(
        key: _userMenuKey,
        enabled: !_switchingProfile,
        icon: active != null
            ? ProfileAvatar(profile: active, size: 32)
            // Theme ink, like every other action in this bar — a fixed white
            // glyph disappears on the light theme's app bar.
            : AppIcon(Symbols.account_circle_rounded, fill: 1, size: 32, color: tokens(context).text),
        tooltip: t.profiles.sectionTitle,
        anchorAlignment: AppMenuAnchorAlignment.end,
        onSelected: (value) => unawaited(_handleUserMenuAction(context, value)),
        entriesBuilder: (context) => _userMenuItems(context, activeProfile: active, profiles: profiles),
      ),
    );
  }

  List<AppMenuEntry<String>> _userMenuItems(
    BuildContext context, {
    required Profile? activeProfile,
    required List<Profile> profiles,
  }) {
    final theme = Theme.of(context);
    final switchable = profiles.where((p) => p.id != activeProfile?.id).toList();

    return [
      for (final p in switchable)
        AppMenuItem<String>(
          value: 'profile:${p.id}',
          leading: ProfileAvatar(profile: p, size: 24),
          label: p.displayName,
          trailing: p.isPinProtected
              ? AppIcon(Symbols.lock_rounded, fill: 1, size: 14, color: theme.colorScheme.onSurfaceVariant)
              : null,
        ),
      if (switchable.isNotEmpty) const AppMenuDivider(),
      AppMenuItem<String>(value: 'manage_profiles', icon: Symbols.group_rounded, label: t.profiles.sectionTitle),
      AppMenuItem<String>(value: 'settings', icon: Symbols.settings_rounded, label: t.common.settings),
      AppMenuItem<String>(value: 'logout', icon: Symbols.logout_rounded, label: t.common.logout),
    ];
  }

  Future<void> _handleUserMenuAction(BuildContext context, String value) async {
    if (_switchingProfile) return;
    if (value == 'logout') {
      unawaited(_handleLogout());
      return;
    }
    if (value == 'manage_profiles') {
      _handleSwitchProfile(context);
      return;
    }
    if (value == 'settings') {
      _handleOpenSettings(context);
      return;
    }
    if (value.startsWith('profile:')) {
      final id = value.substring('profile:'.length);
      final active = context.read<ActiveProfileProvider>();
      final target = active.profiles.where((p) => p.id == id).firstOrNull;
      if (target == null) return;
      await _switchProfileFromMenu(target);
    }
  }

  /// Drop the blocking overlay without waiting for the rebind. The switch
  /// itself keeps running in the background; the user just gets their UI back.
  void _cancelProfileSwitch() {
    if (mounted && _switchingProfile) setState(() => _switchingProfile = false);
  }

  Future<void> _switchProfileFromMenu(Profile profile) async {
    if (_switchingProfile) return;
    setState(() => _switchingProfile = true);
    try {
      await switchProfileFromUi(context, profile);
    } finally {
      if (mounted) {
        setState(() => _switchingProfile = false);
      }
    }
  }

  Widget _buildOverlaidAppBar() {
    // Rebuild on fullscreen toggle so the macOS traffic-light inset updates
    // (the singleton is a ChangeNotifier; nothing else in this subtree listens).
    return ListenableBuilder(listenable: FullscreenStateManager(), builder: (context, _) => _buildOverlaidAppBarBody());
  }

  /// De ene safe-area waar zowel de overlaid appbar als de scherpe hero-laag uit
  /// rekenen. `viewPadding`, niet `padding`: de hero zit in een Scaffold-body die
  /// `padding.top` kan nullen, en `viewPadding` blijft ook staan als het
  /// toetsenbord opengaat.
  double _statusBarInset(BuildContext context) => MediaQuery.viewPaddingOf(context).top;

  Widget _buildOverlaidAppBarBody() {
    final statusBarHeight = _statusBarInset(context);
    final colorScheme = Theme.of(context).colorScheme;
    final overlayColor = colorScheme.brightness == Brightness.dark ? Colors.black : colorScheme.surface;
    final foregroundColor = colorScheme.onSurface;
    // macOS floats the window controls over the content; clear them so the
    // wordmark doesn't sit under the traffic lights (only in windowed mode —
    // they auto-hide in fullscreen). Other platforms keep the 16px inset.
    final leftInset = Platform.isMacOS && !FullscreenStateManager().isFullscreen
        ? DesktopWindowPadding.macOSLeft
        : 16.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // This bar is overlaid on the billboard artwork and its icons are
          // theme-coloured. In light mode the veil is white, so it has to be
          // heavy enough to give that near-black ink something to sit on. Dark
          // needs nearly as much: white ink over a bright backdrop (snow, sky,
          // a blown-out title card) disappeared at the old 0.7/0.5/0.3.
          colors: [
            overlayColor.withValues(alpha: colorScheme.brightness == Brightness.dark ? 0.88 : 0.94),
            overlayColor.withValues(alpha: colorScheme.brightness == Brightness.dark ? 0.68 : 0.80),
            overlayColor.withValues(alpha: colorScheme.brightness == Brightness.dark ? 0.42 : 0.55),
            Colors.transparent,
          ],
          stops: const [0.0, 0.3, 0.6, 1.0],
        ),
      ),
      child: Padding(
        padding: .only(top: statusBarHeight, left: leftInset, right: 16, bottom: homeAppBarOuterBottomPadding),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: homeAppBarControlVerticalPadding),
          child: KeyedSubtree(
            key: DiscoverScreen.appBarControlsKey,
            child: Row(
              children: [
                // Desktop Netflix nav (wordmark + tabs) replaces the page title,
                // staying transparent over the billboard. Expanded fills space up
                // to the actions so the action cluster stays flush right.
                // Phone/tablet (bottom nav) fall back to the brand mark + wordmark
                // per the navigation mockup; the sidebar already carries the brand
                // on desktop, so side-nav keeps the plain title.
                Expanded(
                  child: PlatformDetector.isTV()
                      ? const SizedBox.shrink()
                      : PlatformDetector.shouldUseSideNavigation(context)
                      ? Text(
                          t.discover.title,
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(color: foregroundColor, fontWeight: .bold),
                        )
                      : Row(
                          mainAxisSize: .min,
                          children: [
                            const PleyaLogo(size: 28),
                            const SizedBox(width: 10),
                            Text(
                              'PLEYA',
                              style: TextStyle(
                                color: foregroundColor,
                                fontSize: 14,
                                fontWeight: .w800,
                                letterSpacing: 3.6,
                              ),
                            ),
                          ],
                        ),
                ),
                Consumer2<WatchTogetherProvider, CompanionRemoteProvider>(
                  builder: (context, watchTogether, companionRemote, _) {
                    final isDesktop = PlatformDetector.shouldActAsRemoteHost(context);

                    return FocusableActionBar(
                      key: _actionBarKey,
                      onNavigateLeft: _navigateToSidebar,
                      onNavigateDown: _focusContentFromAppBar,
                      actions: [
                        FocusableAction(
                          onPressed: _handleRefreshPressed,
                          child: DiscoverRefreshAction(color: foregroundColor, onPressed: _handleRefreshPressed),
                        ),
                        // Who is streaming right now. The action only exists
                        // while someone else is watching, so the bar keeps no
                        // empty slot. Not on TV: its panel is a pointer overlay,
                        // and there the sidebar carries this instead.
                        if (!PlatformDetector.isTV() && (context.watch<NowWatchingProvider?>()?.now.hasOthers ?? false))
                          FocusableAction(
                            onPressed: () => _nowWatchingButtonKey.currentState?.togglePanel(),
                            child: NowWatchingButton(key: _nowWatchingButtonKey),
                          ),
                        // Watch Together
                        FocusableAction(
                          onPressed: () =>
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchTogetherScreen())),
                          child: Stack(
                            children: [
                              IconButton(
                                icon: AppIcon(
                                  Symbols.group_rounded,
                                  fill: watchTogether.isInSession ? 1 : 0,
                                  color: watchTogether.isInSession ? colorScheme.primary : foregroundColor,
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const WatchTogetherScreen()),
                                ),
                                tooltip: t.watchTogether.title,
                              ),
                              if (watchTogether.isInSession && watchTogether.participantCount > 1)
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary,
                                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                                    ),
                                    child: Text(
                                      '${watchTogether.participantCount}',
                                      style: TextStyle(color: colorScheme.onPrimary, fontSize: 10, fontWeight: .bold),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Companion Remote
                        FocusableAction(
                          onPressed: () {
                            if (isDesktop) {
                              RemoteSessionDialog.show(context);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const MobileRemoteScreen()),
                              );
                            }
                          },
                          child: Stack(
                            children: [
                              IconButton(
                                icon: AppIcon(
                                  Symbols.phone_android_rounded,
                                  fill: companionRemote.isConnected ? 1 : 0,
                                  color: companionRemote.isConnected ? colorScheme.primary : foregroundColor,
                                ),
                                onPressed: () {
                                  if (isDesktop) {
                                    RemoteSessionDialog.show(context);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => const MobileRemoteScreen()),
                                    );
                                  }
                                },
                                tooltip: t.companionRemote.title,
                              ),
                              if (companionRemote.isConnected)
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                      border: Border.fromBorderSide(BorderSide(color: foregroundColor, width: 1)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Zoeken. Since [DEC-094] search is not a slot in the
                        // mobile bar but an icon here, so the five primary
                        // slots can be content destinations. Desktop and the
                        // TV rail still carry Zoeken as a destination of
                        // their own and are excluded by the same predicate.
                        //
                        // The gate goes through [showsHeaderSearchAction] on
                        // `isMobile` rather than asking `isPhone` here: the
                        // bar is composed on `isMobile`, and the two answers
                        // have to be complements. They were not — an iPad is
                        // `isMobile` and not `isPhone`, so it lost the slot
                        // without gaining the icon, and Zoeken does not live
                        // behind My Pleya to fall back on.
                        if (showsHeaderSearchAction(isMobile: PlatformDetector.isMobile(context)))
                          FocusableAction(
                            onPressed: _openSearch,
                            child: IconButton(
                              icon: AppIcon(Symbols.search_rounded, color: foregroundColor),
                              onPressed: _openSearch,
                              tooltip: t.common.search,
                            ),
                          ),
                        // Server Tasks — Plex-only (`/activities` API has no
                        // Jellyfin equivalent), hide the button entirely on
                        // Jellyfin-only profiles so the chrome doesn't show
                        // a permanently empty popover. Excluded on TV: the panel
                        // is a pointer/hover popover that can't be focused with
                        // the remote, so it read as a dead button on Apple TV
                        // (isDesktop is true there because isMobile excludes TV).
                        if (PlatformDetector.isDesktop(context) &&
                            !PlatformDetector.isTV() &&
                            context.select<MultiServerProvider, bool>((p) => p.hasOnlinePlexServers))
                          FocusableAction(
                            onPressed: () => _serverActivitiesButtonKey.currentState?.togglePanel(),
                            child: ServerActivitiesButton(key: _serverActivitiesButtonKey),
                          ),
                        // User menu: profiles and sign out. Gone on mobile, because the
                        // bottom bar's My Pleya slot is the personal destination
                        // there and carries the same three actions. Desktop and
                        // TV keep it, because their sidebar has no My Pleya.
                        // Same predicate that gates the tab, so the actions are
                        // never in two places and never in none.
                        if (showsHeaderAccountMenu(isMobile: PlatformDetector.isMobile(context)))
                          _buildUserMenuAction(context),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSearch() => MainScreenFocusScope.of(context, listen: false)?.openSearch?.call();

  AutomationReadiness _discoverReadiness() {
    if (_discover.isLoading) return const AutomationReadiness.loading('onDeck');
    if (_discover.areHubsLoading) return const AutomationReadiness.loading('hubs');
    return const AutomationReadiness.ready();
  }

  @override
  Widget build(BuildContext context) {
    return AutomationScreen(
      id: AutomationIds.screenDiscover,
      readiness: _discoverReadiness,
      child: SettingsBuilder(
        prefs: const [
          SettingsService.showServerNameOnHubs,
          SettingsService.showHeroSection,
          SettingsService.hideSpoilers,
          SettingsService.libraryDensity,
          SettingsService.episodePosterMode,
        ],
        builder: (context) => _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final svc = SettingsService.instance;
    final showHeroSection = svc.read(SettingsService.showHeroSection);

    if (PlatformDetector.isTV()) {
      return _buildTvContent(context);
    }

    final showServerNameOnHubs = svc.read(SettingsService.showServerNameOnHubs);
    final hubsSpanMultipleServers = _hubsSpanMultipleServers();

    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Hero Section (newest released films) - at top of screen
              Builder(
                builder: (context) {
                  if (_latestMovies.isNotEmpty && showHeroSection) {
                    return _buildHeroSection();
                  }
                  // Add top padding when hero is not shown
                  return SliverToBoxAdapter(
                    child: SizedBox(height: kToolbarHeight + MediaQuery.paddingOf(context).top + 16),
                  );
                },
              ),
              if (_isLoading)
                const SliverToBoxAdapter(
                  child: Column(children: [SkeletonHubRow(), SkeletonHubRow(), SkeletonHubRow()]),
                ),
              if (_errorMessage != null) SliverErrorState(message: _errorMessage!, onRetry: _discover.load),
              if (!_isLoading && _errorMessage == null) ...[
                // On Deck / Continue Watching
                if (_onDeck.isNotEmpty)
                  SliverToBoxAdapter(
                    child: HubSection(
                      key: _continueWatchingHubKey,
                      hub: MediaHub(
                        id: 'continue_watching',
                        title: t.discover.continueWatching,
                        type: 'mixed',
                        identifier: '_continue_watching_',
                        size: _onDeck.length + (_hasMoreContinueWatching ? 1 : 0),
                        more: _hasMoreContinueWatching,
                        items: _onDeck,
                      ),
                      icon: Symbols.play_circle_rounded,
                      onRefresh: _discover.updateItem,
                      onRemoveFromContinueWatching: _discover.refreshContinueWatching,
                      isInContinueWatching: true,
                      loadMoreItems: _discover.loadAllContinueWatching,
                      onVerticalNavigation: (isUp) => _handleVerticalNavigation(0, isUp),
                      onNavigateUp: _focusTopBoundary,
                      onNavigateToSidebar: _navigateToSidebar,
                    ),
                  ),

                // Recommendation Hubs (Trending, Top in Genre, etc.)
                for (int i = 0; i < _hubs.length; i++)
                  SliverToBoxAdapter(
                    // Ranked Top-10 row (big outlined numerals) for genuine
                    // top-10/trending hubs, non-TV only (TV keeps HubSection's
                    // locked d-pad focus).
                    child: !PlatformDetector.isTV() && TopTenRow.matches(_hubs[i])
                        ? TopTenRow(hub: _hubs[i], onRefresh: _discover.updateItem)
                        : HubSection(
                            key: i < _orderedHubKeys.length ? _orderedHubKeys[i] : null,
                            hub: _hubs[i],
                            icon: _getHubIcon(_hubs[i].title),
                            showServerName: showServerNameOnHubs || hubsSpanMultipleServers,
                            onRefresh: _discover.updateItem,
                            // Hub index is i + 1 if continue watching exists, otherwise i
                            onVerticalNavigation: (isUp) =>
                                _handleVerticalNavigation(_onDeck.isNotEmpty ? i + 1 : i, isUp),
                            onNavigateUp: (i == 0 && _onDeck.isEmpty) ? _focusTopBoundary : null,
                            onNavigateToSidebar: _navigateToSidebar,
                          ),
                  ),

                // Show loading skeleton for hubs while they're loading
                if (_areHubsLoading && _hubs.isEmpty)
                  for (int i = 0; i < 3; i++) const SliverToBoxAdapter(child: SkeletonHubRow()),

                if (_onDeck.isEmpty && _hubs.isEmpty && !_areHubsLoading)
                  SliverFillRemaining(
                    child: StateView.empty(
                      title: t.discover.noContentAvailable,
                      message: t.discover.addMediaToLibraries,
                      icon: Symbols.movie_rounded,
                    ),
                  ),

                SliverToBoxAdapter(child: SizedBox(height: 24 + bottomPadding)),
              ],
            ],
          ),
          // Overlaid app bar — excluded from default focus traversal so that
          // initial/tab-switch focus lands on content (hero/hubs), not the toolbar.
          // Toolbar buttons are still reachable via explicit UP from hero section.
          Positioned(top: 0, left: 0, right: 0, child: ExcludeFocusTraversal(child: _buildOverlaidAppBar())),
          if (_switchingProfile) ProfileSwitchingOverlay(onCancel: _cancelProfileSwitch),
        ],
      ),
    );
  }

  /// Tall-poster scale per hub on the TV home rail.
  ///
  /// Continue-watching sits under the resting hero and is the one row whose
  /// height decides how much backdrop survives, so it runs smaller than the
  /// hubs below it. Used for both the rail itself and the peek math, so the
  /// two always agree on how tall that first row is.
  static double _tvTallPosterScaleForHub(MediaHub hub) => hub.isContinueWatchingHub
      ? TvBrowseRailLayout.continueWatchingTallPosterScale
      : TvBrowseRailLayout.compactTallPosterScale;

  /// Wide-card (16:9) scale override for the home screen's continue-watching
  /// row — see [TvBrowseRailLayout.continueWatchingWidePosterScale]. Every
  /// other TV rail keeps the default 1.0.
  static double _tvWidePosterScaleForHub(MediaHub hub) =>
      hub.isContinueWatchingHub ? TvBrowseRailLayout.continueWatchingWidePosterScale : 1.0;

  Widget _buildTvContent(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final theme = Theme.of(context);
    final svc = SettingsService.instance;
    final hideSpoilers = svc.read(SettingsService.hideSpoilers);
    final showServerNameOnHubs = svc.read(SettingsService.showServerNameOnHubs);
    final hubsSpanMultipleServers = _hubsSpanMultipleServers();
    final browseHubs = _tvBrowseHubs;
    final scale = TvLayoutConstants.scaleForSize(size);
    // Only layout-aspect (flip-stable) scope values may be read here: an
    // offset-aspect read at this level would rebuild the whole screen on
    // every sidebar focus flip. Offset values are read in small Builders
    // around the widgets that position against them.
    final railSize = MainScreenFocusScope.foregroundSizeOf(context);
    final fullBleedWidth = MainScreenFocusScope.fullBleedWidthOf(context);
    final railHeight = browseHubs.isEmpty
        ? 0.0
        : TvBrowseRailLayout.estimateHeight(
            size: railSize,
            hubs: browseHubs,
            density: svc.read(SettingsService.libraryDensity),
            episodePosterMode: svc.read(SettingsService.episodePosterMode),
            fullCardLayout: svc.read(SettingsService.tvFullCardLayout),
            tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
            tallPosterScaleForHub: _tvTallPosterScaleForHub,
            widePosterScaleForHub: _tvWidePosterScaleForHub,
          );
    final spotlightTop = (size.height * MonoTokens.tvHeroContentTopFraction)
        .clamp(64.0 * scale, 120.0 * scale)
        .toDouble();
    // Netflix landing: at rest the rail shows its first hub in full — strip plus
    // one complete card row with its labels — so "continue watching" is readable
    // without moving. What stays below the fold is the next-hub peek and the
    // rail's own bottom margin; focusing the rail slides those up (see
    // [_tvRailRevealed]). The reveal is a translate, so the hero content keeps
    // its resting position and the rail slides up over it.
    //
    // The row's bottom focus-ring reserve (`focusExtra`) is deliberately left
    // out of the peek: nothing in the rail has focus while it rests, and the
    // reveal brings the reserve into view before any ring is drawn. Keeping it
    // would only pad dead space under the labels.
    //
    // The peek is derived from the same inputs as the estimateHeight call
    // above, so the two can't drift apart.
    final firstHubPeek = browseHubs.isEmpty
        ? 0.0
        : TvBrowseRailLayout.firstHubPeekHeight(
            hub: browseHubs.first,
            railSize: railSize,
            density: svc.read(SettingsService.libraryDensity),
            episodePosterMode: svc.read(SettingsService.episodePosterMode),
            fullCardLayout: svc.read(SettingsService.tvFullCardLayout),
            tallPosterScale: _tvTallPosterScaleForHub(browseHubs.first),
            widePosterScale: _tvWidePosterScaleForHub(browseHubs.first),
          );
    final railPeek = browseHubs.isEmpty
        ? 0.0
        : math.min(railHeight, math.min(firstHubPeek, size.height * MonoTokens.tvHomeRailMaxPeekFraction));
    final railSafetyBottom = browseHubs.isEmpty ? 0.0 : railPeek + (MonoTokens.tvHeroRailGap * scale);
    final maxSpotlightBottom = (size.height - spotlightTop - (MonoTokens.tvHeroMinInfoHeight * scale))
        .clamp(0.0, double.infinity)
        .toDouble();
    final spotlightBottom = railSafetyBottom.clamp(0.0, maxSpotlightBottom).toDouble();
    final spotlightLeft = (24 * scale).clamp(18.0, 40.0).toDouble();

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The animated -bleed mirrors the content-slide tween in MainScreen,
          // keeping the full-bleed background viewport-pinned while the
          // content box slides during sidebar expansion. The Builder scopes
          // the offset-aspect dependency to just this subtree.
          Builder(
            builder: (context) {
              final foregroundLeft = MainScreenFocusScope.foregroundLeftOf(context);
              return SideNavigationBleedBuilder(
                targetBleed: foregroundLeft,
                child: ValueListenableBuilder<MediaItem?>(
                  valueListenable: _spotlightItem,
                  builder: (context, _, _) {
                    final rawSpotlight = _effectiveSpotlightItem;
                    final spotlight = rawSpotlight == null ? null : context.withFreshWatchState(rawSpotlight);
                    // Netflix-style billboard: full hero treatment (large logo,
                    // metadata, summary) with focusable Play / More-info actions
                    // anchored just above the content rail. The billboard is a
                    // fixed featured item, decoupled from row focus.
                    return TvSpotlightBackground(
                      item: spotlight,
                      client: _getMediaClientForItem(spotlight),
                      hideSpoilers: hideSpoilers,
                      contentTop: spotlightTop,
                      contentBottom: spotlightBottom,
                      contentLeft: spotlightLeft + foregroundLeft,
                      // Compact presentation at rest as well: the first hub now
                      // claims real estate the full-size logo used to hold, and
                      // rail focus already rendered compact — so the resting
                      // hero no longer jumps in logo size when focus moves down.
                      compact: true,
                      showPrimaryAction: false,
                      deepBottomScrim: true,
                      kenBurns: true,
                      // Rail revealed → the billboard shrinks to logo + metadata
                      // for the focused row item and the backdrop dims; it never
                      // disappears, so the artwork keeps identifying the selection.
                      railRevealed: _tvRailRevealed,
                      actions: spotlight == null ? null : _buildTvHeroActions(context, spotlight, scale),
                    );
                  },
                ),
                builder: (context, animatedBleed, child) =>
                    Positioned(top: 0, bottom: 0, left: -animatedBleed, width: fullBleedWidth, child: child!),
              );
            },
          ),
          if (_isLoading || (_areHubsLoading && browseHubs.isEmpty)) const Center(child: CircularProgressIndicator()),
          if (_errorMessage != null)
            StateView.error(title: _errorMessage!, icon: Symbols.error_outline_rounded, onRetry: _discover.load),
          if (!_isLoading && _errorMessage == null && browseHubs.isEmpty && !_areHubsLoading)
            Center(
              child: Column(
                mainAxisAlignment: .center,
                children: [
                  const AppIcon(Symbols.movie_rounded, fill: 1, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(t.discover.noContentAvailable),
                  const SizedBox(height: 8),
                  Text(t.discover.addMediaToLibraries, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          if (browseHubs.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              // At rest the rail is slid down so [railPeek] shows: the first hub
              // complete, everything below it out of frame. Focusing it slides
              // the remainder up over the hero's lower edge (Netflix landing).
              // Slide fraction is relative to the rail's own height, so no fixed
              // height is forced on it.
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                offset: Offset(0, _tvRailRevealed || railHeight <= 0 ? 0.0 : 1 - (railPeek / railHeight)),
                // Reveal follows actual rail-subtree focus, not just the explicit
                // navigate-down call site — so restored focus, sidebar→content, or
                // internal traversal into the rail also reveals it.
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (hasFocus) => _setTvRailRevealed(hasFocus),
                  child: TvBrowseRail(
                    key: _tvBrowseRailKey,
                    hubs: browseHubs,
                    showServerName: showServerNameOnHubs || hubsSpanMultipleServers,
                    // Hero follows rail focus: as the user moves through rows the
                    // billboard becomes the focused item. Only the
                    // ValueListenableBuilder on _spotlightItem rebuilds, not the rows.
                    // Auto-rotate is paused while the rail is revealed (see
                    // _setTvRailRevealed) so it doesn't fight the focus-follow.
                    onFocusedItemChanged: _setSpotlightDebounced,
                    onRefresh: _discover.updateItem,
                    onRemoveFromContinueWatching: _discover.refreshContinueWatching,
                    isContinueWatchingHub: (hub) => hub.isContinueWatchingHub,
                    usesContinueWatchingAction: (hub) => hub.usesContinueWatchingAction,
                    loadMoreItems: (hub) =>
                        hub.id == 'continue_watching' ? _discover.loadAllContinueWatching() : Future.value(hub.items),
                    onNavigateUp: _focusTvHeroPlay,
                    onNavigateToSidebar: _navigateToSidebar,
                    tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
                    tallPosterScaleForHub: _tvTallPosterScaleForHub,
                    widePosterScaleForHub: _tvWidePosterScaleForHub,
                    selectSuppressionGestureSignal: PlatformDetector.isAppleTV()
                        ? AppleTvRemoteTouchService.instance.touchActiveListenable
                        : null,
                  ),
                ),
              ),
            ),
          Builder(
            builder: (context) => SideNavigationBleedBuilder(
              targetBleed: MainScreenFocusScope.sideNavigationBleedOf(context),
              child: ExcludeFocusTraversal(child: _buildOverlaidAppBar()),
              builder: (context, animatedBleed, child) =>
                  Positioned(top: 0, left: -animatedBleed, width: fullBleedWidth, child: child!),
            ),
          ),
          if (_switchingProfile) ProfileSwitchingOverlay(onCancel: _cancelProfileSwitch),
        ],
      ),
    );
  }

  /// Netflix-style billboard actions for the TV home hero: a primary
  /// Play/Resume pill and a secondary More-info pill, focus-wired to the rail
  /// (down), the app bar (up), and the sidebar (left/back).
  Widget _buildTvHeroActions(BuildContext context, MediaItem rawBillboard, double scale) {
    // Bridge the store patch so resume state / progress never lags the on-deck
    // snapshot (mirrors _buildSmartPlayButton).
    final billboard = context.withFreshWatchState(rawBillboard);
    final resume = billboard.hasActiveProgress;
    final progress = resume && billboard.durationMs != null && billboard.viewOffsetMs != null
        ? (billboard.viewOffsetMs! / billboard.durationMs!).clamp(0.0, 1.0).toDouble()
        : null;
    return Row(
      mainAxisSize: .min,
      children: [
        FocusableButton(
          focusNode: _tvHeroPlayFocusNode,
          autoScroll: false,
          // The pill draws its own focus fully (ListenableBuilder on the
          // focusNode below), so the wrapper delegates instead of drawing a
          // ring or fill of its own.
          mode: FocusIndicatorMode.delegated,
          onPressed: () => navigateToMediaItem(context, billboard, playDirectly: true),
          onNavigateDown: () => _focusTvBrowseRailWhenReady(immediate: true),
          onNavigateUp: _focusTopActions,
          onNavigateLeft: () => _moveTvHero(-1),
          onNavigateRight: _focusTvHeroInfoOrAdvance,
          onBack: _navigateToSidebar,
          child: _tvHeroPill(
            context,
            focusNode: _tvHeroPlayFocusNode,
            icon: Symbols.play_arrow_rounded,
            label: resume ? t.common.resume : t.common.play,
            scale: scale,
            progress: progress,
          ),
        ),
        SizedBox(width: 16 * scale),
        FocusableButton(
          focusNode: _tvHeroInfoFocusNode,
          autoScroll: false,
          mode: FocusIndicatorMode.delegated,
          onPressed: () => navigateToMediaItem(context, billboard),
          onNavigateDown: () => _focusTvBrowseRailWhenReady(immediate: true),
          onNavigateUp: _focusTopActions,
          onNavigateLeft: _focusTvHeroPlayOrAdvance,
          onNavigateRight: () => _moveTvHero(1),
          onBack: _navigateToSidebar,
          child: _tvHeroPill(
            context,
            focusNode: _tvHeroInfoFocusNode,
            icon: Symbols.info_rounded,
            label: t.mediaMenu.viewDetails,
            scale: scale,
          ),
        ),
      ],
    );
  }

  /// A Netflix-style billboard pill. Inverts on focus (solid white + dark
  /// content) and optionally embeds a resume progress bar.
  Widget _tvHeroPill(
    BuildContext context, {
    required FocusNode focusNode,
    required IconData icon,
    required String label,
    required double scale,
    double? progress,
  }) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final showFocus = focusNode.hasFocus && InputModeTracker.isKeyboardMode(context);
        final fg = showFocus ? cs.surface : cs.onSurface;
        // Unfocused, the pill is a translucent tint of the text colour. On a
        // dark surface that reads as a soft grey pill; on a light one it is
        // near-black text on a 24%-black veil over bright artwork, which is
        // the worst pairing on screen. Light mode fills the pill instead.
        final isLight = cs.brightness == Brightness.light;
        final bg = showFocus
            ? cs.onSurface
            : (isLight ? cs.surface.withValues(alpha: 0.92) : cs.onSurface.withValues(alpha: 0.24));
        return AnimatedContainer(
          duration: FocusTheme.getAnimationDuration(context),
          curve: Curves.easeOutCubic,
          padding: .symmetric(horizontal: 28 * scale, vertical: 15 * scale),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
          child: Row(
            mainAxisSize: .min,
            children: [
              AppIcon(icon, fill: 1, size: 27 * scale, color: fg),
              SizedBox(width: 10 * scale),
              if (progress != null) ...[
                Container(
                  width: 56 * scale,
                  height: 8 * scale,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4 * scale),
                  ),
                  child: FractionallySizedBox(
                    alignment: .centerLeft,
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(4 * scale)),
                    ),
                  ),
                ),
                SizedBox(width: 10 * scale),
              ],
              Text(
                label,
                style: TextStyle(color: fg, fontSize: 21 * scale, fontWeight: .w600),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroSection() {
    return SliverLayoutBuilder(
      builder: (context, constraints) => _buildHeroSectionSliver(constraints.viewportMainAxisExtent),
    );
  }

  /// Height of the first rail below the hero, so the hero can fill exactly what
  /// is left. Continue Watching is episodes (16:9, short); a hub of posters is
  /// 2:3 and much taller, so the two can't share one number.
  double _firstRailHeight(double width) {
    final episodeMode = SettingsService.instance.read(SettingsService.episodePosterMode);
    final firstRailItems = _onDeck.isNotEmpty ? _onDeck : (_hubs.isNotEmpty ? _hubs.first.items : const <MediaItem>[]);
    // Mirrors HubSection: a rail goes wide when it holds any episode at all,
    // whether it is episodes-only or mixed.
    final wide =
        episodeMode == EpisodePosterMode.episodeThumbnail &&
        firstRailItems.any((i) => i.usesWideAspectRatio(episodeMode));
    return HubSectionState.railHeight(context, width, wideLayout: wide);
  }

  /// Which content-layout tier the hero's info column uses for [screenWidth].
  ///
  /// `shortestSide >= ScreenBreakpoints.mobile` (not
  /// `ScreenBreakpoints.isWideTabletOrLarger`, which only starts at 900) is
  /// what catches iPad-portrait widths like 768/834 that sit below that
  /// 900pt threshold. In portrait, `shortestSide == screenWidth`, so this
  /// still excludes every phone (never wider than ~430pt in portrait).
  /// [PlatformDetector.isHandheldIOS] is `!isTV() && Theme.platform == iOS`,
  /// so this only ever fires for an iPad held in portrait: tvOS, desktop and
  /// macOS are excluded, and so is Android, which reports
  /// `TargetPlatform.android` and lands on [HomeHeroContentTier.phone] even on
  /// a large tablet. Landscape iPad and desktop keep
  /// [HomeHeroContentTier.wide] exactly as before.
  HomeHeroContentTier _heroContentTier(BuildContext context, double screenWidth) {
    final size = MediaQuery.sizeOf(context);
    final isTabletPortrait =
        PlatformDetector.isHandheldIOS(context) &&
        MediaQuery.orientationOf(context) == Orientation.portrait &&
        size.shortestSide >= ScreenBreakpoints.mobile;
    final isLargeScreen = ScreenBreakpoints.isWideTabletOrLarger(screenWidth) && !isTabletPortrait;
    return isLargeScreen
        ? HomeHeroContentTier.wide
        : (isTabletPortrait ? HomeHeroContentTier.tabletPortrait : HomeHeroContentTier.phone);
  }

  Widget _buildHeroSectionSliver(double viewportExtent) {
    // TV runs through _buildTvContent, so this section is phone/tablet/desktop.
    final w = MediaQuery.sizeOf(context).width;
    final heroHeight = homeHeroHeight(
      useSideNav: PlatformDetector.shouldUseSideNavigation(context),
      viewportExtent: viewportExtent,
      screenHeight: MediaQuery.sizeOf(context).height,
      screenWidth: w,
      statusBarHeight: MediaQuery.paddingOf(context).top,
      firstRailHeight: _firstRailHeight(w),
    );
    return SliverToBoxAdapter(
      child: AutomationNode(
        id: AutomationIds.discoverHero,
        role: 'hero',
        child: Focus(
          focusNode: _heroFocusNode,
          onKeyEvent: _handleHeroKeyEvent,
          child: SizedBox(
            height: heroHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                PageView.builder(
                  controller: _heroController,
                  itemCount: _latestMovies.length,
                  onPageChanged: (index) {
                    // Validate index is within bounds before updating
                    if (index >= 0 && index < _latestMovies.length) {
                      setState(() {
                        _currentHeroIndex = index;
                      });
                      _resetAutoScrollTimer();
                      _ensureHeroArt(index);
                    }
                  },
                  itemBuilder: (context, index) {
                    final item = _latestMovies[index];
                    return _buildHeroItem(_spotlightArtCache[item.globalKey] ?? item, heroHeight);
                  },
                ),
                // Page indicators with animated progress and pause/play button
                if (!InputModeTracker.isKeyboardMode(context))
                  Positioned(
                    key: DiscoverScreen.heroPaginationKey,
                    // The same 16 on every tier, so it is read straight from the
                    // constant: resolving the tier here would add a rotation
                    // rebuild to this sliver for a value that never varies.
                    bottom: homeHeroPaginationBottomInset,
                    left: -26,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: .center,
                      children: [
                        // Pause/Play button
                        ClickableCursor(
                          child: GestureDetector(
                            onTap: () {
                              if (_isAutoScrollPaused) {
                                _resumeAutoScroll();
                              } else {
                                _pauseAutoScroll();
                              }
                            },
                            child: AppIcon(
                              _isAutoScrollPaused ? Symbols.play_arrow_rounded : Symbols.pause_rounded,
                              fill: 1,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 18,
                              semanticLabel: '${_isAutoScrollPaused ? t.common.play : t.common.pause} auto-scroll',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ...() {
                          final range = _getVisibleDotRange();
                          return List.generate(range.end - range.start + 1, (i) {
                            final index = range.start + i;
                            final isActive = _currentHeroIndex == index;
                            final dotSize = _getDotSize(index, range.start, range.end);

                            return isActive
                                // Progress indicator for active page (~5fps via Timer)
                                ? ValueListenableBuilder<double>(
                                    valueListenable: _indicatorProgress,
                                    builder: (context, progress, child) {
                                      final maxWidth = dotSize * 3; // 24px for normal, 15px for small
                                      final fillWidth = dotSize + ((maxWidth - dotSize) * progress);
                                      final onSurface = Theme.of(context).colorScheme.onSurface;
                                      return Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        width: maxWidth,
                                        height: dotSize,
                                        decoration: BoxDecoration(
                                          color: onSurface.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(dotSize / 2),
                                        ),
                                        child: Align(
                                          alignment: .centerLeft,
                                          child: Container(
                                            width: fillWidth,
                                            height: dotSize,
                                            decoration: BoxDecoration(
                                              color: onSurface,
                                              borderRadius: BorderRadius.circular(dotSize / 2),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                // Static indicator for inactive pages
                                : AnimatedContainer(
                                    duration: tokens(context).slow,
                                    curve: Curves.easeInOut,
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    width: dotSize,
                                    height: dotSize,
                                    decoration: BoxDecoration(
                                      // Inactive dot, sitting on the billboard.
                                      // 40% ink is a visible hint white-on-dark
                                      // but disappears as black over artwork.
                                      color: tokens(context).onArtworkInk(dark: 0.4, light: 0.62),
                                      borderRadius: BorderRadius.circular(dotSize / 2),
                                    ),
                                  );
                          });
                        }(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroItem(MediaItem rawHeroItem, double heroHeight) {
    // Builder so the watch-state subscription happens in a real build pass.
    // The carousel feeds this through a SliverChildBuilderDelegate, whose
    // itemBuilder runs during *layout* — `context.select` asserts there (only
    // LayoutBuilder is exempt), and the State's own context would attach the
    // dependency to DiscoverScreen instead of this item. Mirrors
    // [_buildSmartPlayButton].
    return Builder(
      builder: (context) {
        // Fresh watch state so the hero shows (and live-updates) watched status.
        final heroItem = context.withFreshWatchState(rawHeroItem);
        return _buildHeroItemContent(context, heroItem, heroHeight);
      },
    );
  }

  Widget _buildHeroItemContent(BuildContext context, MediaItem heroItem, double heroHeight) {
    final heroClient = _getMediaClientForItem(heroItem);
    final isEpisode = heroItem.isEpisode;
    final showName = heroItem.grandparentTitle ?? heroItem.displayTitle;
    final screenWidth = MediaQuery.sizeOf(context).width;
    // TV never reaches this builder: `_buildDiscoverContent` returns
    // `_buildTvContent` (TvSpotlightBackground) before the hero sliver is
    // built, so this layout only ever serves desktop/tablet/phone.
    final tier = _heroContentTier(context, screenWidth);
    final isLargeScreen = tier == HomeHeroContentTier.wide;
    final alignLeft = isLargeScreen;
    final contentMetrics = homeHeroContentMetrics(tier: tier);
    // The sharp layer is top-anchored, so on an iPhone its top edge lands under
    // the Dynamic Island. Push it clear, and run it edge to edge, but only
    // there: this gate has to exclude iPad-portrait (which keeps the centred
    // island on a much wider canvas), iPhone-landscape (cutout on the side,
    // nothing to clear at the top), and every non-iOS platform.
    //
    // `isHandheldIOS` is `!isTV() && Theme.of(context).platform ==
    // TargetPlatform.iOS`, so Android reports `android` and macOS reports
    // `macOS` and both fall out here without a separate `Platform.isIOS`
    // check. In portrait `shortestSide` is the screen width, so the
    // `ScreenBreakpoints.mobile` (600) test keeps iPad's 768/834 out while
    // letting every phone width through. tvOS never reaches this builder at
    // all: `_buildDiscoverContent` branches to `_buildTvContent` first.
    final size = MediaQuery.sizeOf(context);
    final isIPhonePortrait =
        PlatformDetector.isHandheldIOS(context) &&
        MediaQuery.orientationOf(context) == Orientation.portrait &&
        size.shortestSide < ScreenBreakpoints.mobile;
    // Edge to edge on a phone. A centred island at 82% reads as a small card
    // there rather than a hero; iPad keeps the island, where the canvas is
    // wide enough for it to read as a composition.
    final sharpPresentation = isIPhonePortrait ? HomeHeroSharpPresentation.fullWidth : HomeHeroSharpPresentation.island;
    // The source choice follows that composition, which is why it is decided
    // after it: a square source is the calmer subject inside an island, but at
    // full width it becomes a block as tall as the screen is wide with the
    // clear-logo across it. See `MediaItem.billboardArt`. Null only when the
    // item has no artwork at all.
    final billboardArt = heroItem.billboardArt(
      containerAspectRatio: screenWidth / heroHeight,
      narrowBoxIsFullWidth: isIPhonePortrait,
    );
    // Same safe-area the overlaid appbar reads, so the two never drift apart.
    // The sharp layer's top sits at the safe area and runs behind the control
    // row, fading in across it: the appbar's title/actions row sits inside
    // that band, not below it.
    final statusBarInset = _statusBarInset(context);
    final artGeometry = billboardArt == null
        ? null
        : homeHeroArtGeometry(
            screenWidth: screenWidth,
            heroHeight: heroHeight,
            kind: billboardArt.kind,
            requestedSharpTop: isIPhonePortrait
                ? homeHeroSharpTopAnchors(statusBarHeight: statusBarInset)
                : HomeHeroSharpTopAnchors.none,
            presentation: sharpPresentation,
          );
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final heroLogoMetrics = homeHeroLogoConstraints(screenWidth: screenWidth, tier: tier);
    final heroLogoWidth = heroLogoMetrics.width;
    final heroLogoHeight = heroLogoMetrics.height;
    // No ad-hoc glow/shadow on the title: the scrim gradient already provides
    // contrast against the artwork.
    final heroTitleStyle = theme.textTheme.displaySmall?.copyWith(color: colorScheme.onSurface, fontWeight: .bold);
    // Metadata line and synopsis sit on the artwork. 70% ink reads as
    // "secondary" white-on-dark, but as washed-out black over bright artwork,
    // so light mode keeps far more of it.
    final heroMutedColor = tokens(context).onArtworkInk(dark: 0.7, light: 0.94);

    // Spoiler protection
    final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
    final shouldHideSpoiler = hideSpoilers && heroItem.shouldHideSpoiler;

    // Build semantic label for hero item
    final heroLabel = isEpisode ? "${heroItem.grandparentTitle}, ${heroItem.title}" : heroItem.title;

    return Semantics(
      label: heroLabel,
      button: true,
      hint: t.mediaMenu.viewDetails,
      child: ClickableCursor(
        child: GestureDetector(
          // The billboard opens the title; the Afspelen pill on top of it is the
          // only thing that starts playback. It used to be one big hidden play
          // button, so any stray click — a menu label missed by a few pixels, a
          // click that woke the window — started a film.
          //
          // Not `navigateToMediaItem(playDirectly: false)`: its episode branch
          // still hands off to the player while `episodeAction` is `play`, and
          // the hero shows episodes. `navigateToMediaItemDetails` resolves an
          // episode to its show with the right season and episode selected.
          onTap: () {
            appLogger.d('Activating hero item (details): ${heroItem.title}');
            navigateToMediaItemDetails(context, heroItem);
          },
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // Background Image with fade/zoom animation and parallax
              if (billboardArt != null && artGeometry != null)
                HomeHeroArtwork(
                  client: heroClient,
                  art: billboardArt,
                  geometry: artGeometry,
                  scrollController: _scrollController,
                )
              else
                ColoredBox(color: colorScheme.surfaceContainerHighest),

              // Gradient Overlay - blends into scaffold background
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: -4, // Extend past stack bounds to ensure coverage
                child: IgnorePointer(
                  child: Builder(
                    builder: (context) {
                      final bgColor = Theme.of(context).scaffoldBackgroundColor;
                      // On phone/tabletPortrait the ambient artwork layer
                      // already carries most of the darkening (see
                      // HomeHeroArtwork), so this gradient only needs to
                      // finish the job under the (now lower, more compact)
                      // content column — it starts earlier and stays
                      // partial through the middle so artwork colour keeps
                      // reading behind the text, instead of an early hard
                      // wall of scaffold colour. Wide/desktop keeps its
                      // original ramp: that layout has no ambient layer to
                      // share the work with.
                      final gradient = isLargeScreen
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, bgColor.withValues(alpha: 0.9), bgColor],
                              stops: const [0.5, 0.85, 1.0],
                            )
                          : LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, bgColor.withValues(alpha: 0.55), bgColor],
                              stops: const [0.30, 0.62, 1.0],
                            );
                      return Container(decoration: BoxDecoration(gradient: gradient));
                    },
                  ),
                ),
              ),

              // Netflix left-to-right scrim: darkens the text side of the
              // billboard so the title/synopsis stay legible over the art.
              if (alignLeft)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Builder(
                      builder: (context) {
                        // The wash is the page background, so in light mode it
                        // is white: it brightens the artwork instead of
                        // dimming it, while the title/synopsis on top stay
                        // near-black. Light therefore washes harder and holds
                        // it further across before releasing the image. Dark
                        // keeps its original ramp.
                        final scrim = tokens(context);
                        final bgColor = scrim.artworkScrim;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                bgColor.withValues(alpha: scrim.artworkScrimAlpha(dark: 0.92, light: 0.97)),
                                bgColor.withValues(alpha: scrim.artworkScrimAlpha(dark: 0.55, light: 0.78)),
                                Colors.transparent,
                              ],
                              stops: scrim.isLight ? const [0.0, 0.45, 0.80] : const [0.0, 0.32, 0.62],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Content with responsive alignment
              Positioned(
                bottom: contentMetrics.contentBottomInset,
                left: 0,
                right: isLargeScreen ? 200 : 0,
                child: Padding(
                  padding: .symmetric(horizontal: isLargeScreen ? 40.0 : 24.0),
                  child: Align(
                    alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentMetrics.maxContentWidth ?? double.infinity),
                      child: Column(
                        crossAxisAlignment: alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                        mainAxisSize: .min,
                        children: [
                          // Show logo or name/title
                          if (heroItem.clearLogoPath != null)
                            SizedBox(
                              height: heroLogoHeight,
                              width: heroLogoWidth,
                              child: Builder(
                                builder: (context) {
                                  final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);
                                  final logoUrl = MediaImageHelper.getOptimizedImageUrl(
                                    client: heroClient,
                                    thumbPath: heroItem.clearLogoPath,
                                    maxWidth: heroLogoWidth,
                                    maxHeight: heroLogoHeight,
                                    devicePixelRatio: dpr,
                                    imageType: ImageType.logo,
                                  );

                                  return blurArtwork(
                                    CachedNetworkImage(
                                      imageUrl: logoUrl,
                                      cacheKey: artworkStorageKey(logoUrl),
                                      cacheManager: PlexImageCacheManager.instance,
                                      filterQuality: FilterQuality.medium,
                                      fit: BoxFit.contain,
                                      memCacheWidth: (heroLogoWidth * dpr).clamp(200, 800).round(),
                                      alignment: alignLeft ? Alignment.bottomLeft : Alignment.bottomCenter,
                                      placeholder: (context, url) => const SizedBox.shrink(),
                                      errorBuilder: (context, error, stackTrace) {
                                        // Fallback to text if logo fails to load
                                        return FittingTitleText(
                                          showName,
                                          style: heroTitleStyle,
                                          textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                                          alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
                                        );
                                      },
                                    ),
                                    sigma: 10,
                                    clip: false,
                                  );
                                },
                              ),
                            )
                          else
                            SizedBox(
                              height: heroLogoHeight,
                              width: heroLogoWidth,
                              child: FittingTitleText(
                                showName,
                                style: heroTitleStyle,
                                textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                                alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
                              ),
                            ),

                          // One plain muted meta line: year · genre · duration.
                          // No chips/badges — just quiet supporting text.
                          if (heroItem.year != null ||
                              heroItem.genres?.isNotEmpty == true ||
                              heroItem.durationMs != null ||
                              heroItem.isWatched) ...[
                            SizedBox(height: contentMetrics.logoToMeta),
                            Text(
                              [
                                if (heroItem.year != null) heroItem.year.toString(),
                                if (heroItem.genres?.isNotEmpty == true) heroItem.genres!.first,
                                if (heroItem.durationMs != null) formatDurationTextual(heroItem.durationMs!),
                                if (heroItem.isWatched && !heroItem.hasActiveProgress) '\u2713 ${t.discover.watched}',
                              ].join(' • '),
                              style: theme.textTheme.bodySmall?.copyWith(color: heroMutedColor, fontSize: 14),
                            ),
                          ],

                          // On small screens: show button before summary
                          if (!alignLeft) ...[
                            SizedBox(height: contentMetrics.metaToButton),
                            _buildSmartPlayButton(heroItem),
                          ],

                          // Summary with episode info (Apple TV style)
                          if (heroItem.summary != null && !shouldHideSpoiler) ...[
                            SizedBox(height: contentMetrics.buttonToSummary),
                            RichText(
                              maxLines: 2,
                              overflow: .ellipsis,
                              textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                              text: TextSpan(
                                style: TextStyle(color: heroMutedColor, fontSize: 14, height: 1.4),
                                children: [
                                  if (isEpisode && heroItem.parentIndex != null && heroItem.index != null)
                                    TextSpan(
                                      text: 'S${heroItem.parentIndex}, E${heroItem.index}: ',
                                      style: TextStyle(fontWeight: .bold, color: colorScheme.onSurface),
                                    ),
                                  TextSpan(
                                    text: heroItem.summary?.isNotEmpty == true
                                        ? heroItem.summary!
                                        : t.messages.noDescriptionAvailable,
                                  ),
                                ],
                              ),
                            ),
                          ] else if (shouldHideSpoiler &&
                              isEpisode &&
                              heroItem.parentIndex != null &&
                              heroItem.index != null) ...[
                            SizedBox(height: contentMetrics.buttonToSummary),
                            Text(
                              'S${heroItem.parentIndex}, E${heroItem.index}: ${heroItem.title}',
                              maxLines: 2,
                              overflow: .ellipsis,
                              textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                              style: TextStyle(color: heroMutedColor, fontSize: 14, height: 1.4),
                            ),
                          ],

                          // On large screens: show button after summary
                          if (alignLeft) ...[
                            SizedBox(height: contentMetrics.metaToButton),
                            _buildSmartPlayButton(heroItem),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmartPlayButton(MediaItem rawHeroItem) {
    return Builder(
      builder: (context) {
        // The on-deck snapshot refetches shortly after a watch event; the store
        // patch bridges the gap so "minutes left" never lags.
        final heroItem = context.withFreshWatchState(rawHeroItem);
        final hasProgress = heroItem.hasActiveProgress;

        final minutesLeft = hasProgress ? ((heroItem.durationMs! - heroItem.viewOffsetMs!) / 60_000).round() : 0;

        final progress = hasProgress ? heroItem.viewOffsetMs! / heroItem.durationMs! : 0.0;

        // Fixed white pill: the TV focus ring that used to live here is now
        // TvSpotlightBackground's job, and desktop keyboard focus lands on the
        // hero itself (_heroFocusNode), not on this button.
        const foregroundColor = Colors.black;
        const textStyle = TextStyle(color: foregroundColor, fontSize: 14, fontWeight: FontWeight.w600);
        return AutomationNode(
          id: AutomationIds.discoverHeroPlay,
          role: 'button',
          child: InkWell(
            onTap: () {
              appLogger.d('Playing: ${heroItem.title}');
              navigateToVideoPlayer(context, metadata: heroItem);
            },
            borderRadius: const BorderRadius.all(Radius.circular(24)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(24))),
              child: Row(
                mainAxisSize: .min,
                children: [
                  const AppIcon(Symbols.play_arrow_rounded, fill: 1, size: 20, color: foregroundColor),
                  const SizedBox(width: 8),
                  if (hasProgress) ...[
                    // Progress bar
                    Container(
                      width: 40,
                      height: 6,
                      decoration: BoxDecoration(
                        color: foregroundColor.withValues(alpha: 0.25),
                        borderRadius: const BorderRadius.all(Radius.circular(3)),
                      ),
                      child: FractionallySizedBox(
                        alignment: .centerLeft,
                        widthFactor: progress,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: foregroundColor,
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(t.discover.minutesLeft(minutes: minutesLeft), style: textStyle),
                  ] else
                    Text(t.common.play, style: textStyle),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
