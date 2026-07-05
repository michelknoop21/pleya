import 'dart:async';
import '../media/ids.dart';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, LogicalKeyboardKey;
import 'package:pleya/widgets/app_icon.dart';
import '../widgets/server_activities_button.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../focus/focusable_action_bar.dart';
import '../focus/focusable_button.dart';
import '../focus/focus_theme.dart';
import '../focus/input_mode_tracker.dart';
import '../focus/key_event_utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';

import '../services/apple_tv_remote_touch_service.dart';
import '../services/image_cache_service.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../media/media_hub.dart';
import '../utils/media_image_helper.dart';
import '../utils/content_utils.dart';
import '../widgets/optimized_media_image.dart' show blurArtwork;
import '../providers/discover_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/playback_state_provider.dart';
import '../providers/watch_state_store.dart';
import '../widgets/hub_section.dart';
import '../widgets/app_menu.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/skeletons.dart';
import '../widgets/state_view.dart';
import '../widgets/profile_switching_overlay.dart';
import 'profile/profile_switch_screen.dart';
import '../connection/connection_registry.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/plex_home_service.dart';
import '../profiles/profile.dart';
import '../profiles/profile_activation.dart';
import '../profiles/profile_avatar.dart';
import '../profiles/profile_connection_registry.dart';
import '../profiles/profile_registry.dart';
import '../providers/user_profile_provider.dart';
import '../services/storage_service.dart';
import '../services/settings_service.dart';
import '../widgets/settings_builder.dart';
import '../widgets/fitting_title_text.dart';
import '../widgets/tv_browse_rail.dart';
import '../widgets/tv_spotlight_background.dart';
import '../mixins/refreshable.dart';
import '../mixins/tab_visibility_aware.dart';
import '../i18n/strings.g.dart';
import '../utils/app_logger.dart';
import '../utils/dialogs.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/provider_extensions.dart';
import '../utils/video_player_navigation.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';
import '../navigation/top_nav_scope.dart';
import '../widgets/top_nav_bar.dart';
import '../services/fullscreen_state_manager.dart';
import '../utils/desktop_window_padding.dart';
import '../widgets/top_ten_row.dart';
import '../theme/mono_theme.dart' show kAccentAlt;
import '../theme/mono_tokens.dart';
import 'auth_screen.dart';
import 'libraries/content_state_builder.dart';
import 'main_screen.dart';
import 'settings/settings_screen.dart';
import '../watch_together/watch_together.dart';
import '../providers/companion_remote_provider.dart';
import '../widgets/companion_remote/remote_session_dialog.dart';
import 'companion_remote/mobile_remote_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

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
  static const double _tvHeroContentTopFraction = 0.075;
  // How much of the browse rail peeks at the bottom of the home screen when the
  // hero is focused (fraction of viewport height): enough for the hub label and
  // the poster tops. Focusing the rail slides the rest up into view.
  static const double _tvHomeRailPeekFraction = 0.16;
  static const double _tvHeroRailGap = 32;
  static const double _tvHeroMinInfoHeight = 96;

  /// Data + refresh policy live in [DiscoverProvider]; this state keeps only
  /// UI concerns (hero carousel, focus, spotlight). The proxy getters keep
  /// the build code reading naturally.
  late final DiscoverProvider _discover;
  int _seenLoadGeneration = 0;

  List<MediaItem> get _onDeck => _discover.onDeck;
  // Hero source: newest released films (release-date ordered), not on-deck.
  List<MediaItem> get _latestMovies => _discover.latestMovies;
  List<MediaHub> get _hubs => _discover.hubs;
  bool get _hasMoreContinueWatching => _discover.hasMoreContinueWatching;
  bool get _isLoading => _discover.isLoading;
  bool get _areHubsLoading => _discover.areHubsLoading;
  String? get _errorMessage {
    final raw = _discover.errorMessage;
    return raw == null ? null : t.errors.failedToLoad(context: t.discover.title, error: raw);
  }

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

  String _hubIdentity(MediaHub hub) => '${hub.serverId ?? ''}:${hub.identifier ?? hub.id}';

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
    hubs.addAll(_hubs.where((hub) => hub.items.isNotEmpty));
    return hubs;
  }

  MediaItem? get _effectiveSpotlightItem {
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
    if (_effectiveSpotlightItem != null && _tvHeroPlayFocusNode.canRequestFocus) {
      _tvHeroPlayFocusNode.requestFocus();
    } else {
      _focusTopActions();
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

  void _moveTvHero(int delta) {
    if (_latestMovies.length < 2) return;
    final current = _effectiveSpotlightItem;
    final currentIndex = current == null ? -1 : _latestMovies.indexWhere((m) => m.globalKey == current.globalKey);
    final baseIndex = currentIndex == -1 ? _currentHeroIndex.clamp(0, _latestMovies.length - 1).toInt() : currentIndex;
    final nextIndex = (baseIndex + delta) % _latestMovies.length;
    final normalizedIndex = nextIndex < 0 ? nextIndex + _latestMovies.length : nextIndex;
    setState(() => _currentHeroIndex = normalizedIndex);
    _spotlightItem.value = _latestMovies[normalizedIndex];
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
      onSelect: () {
        if (_latestMovies.isNotEmpty && _currentHeroIndex < _latestMovies.length) {
          navigateToMediaItem(context, _latestMovies[_currentHeroIndex], playDirectly: true);
        }
      },
    )(node, event);
  }

  @override
  void dispose() {
    _discover.removeListener(_onDiscoverChanged);
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollTimer?.cancel();
    _indicatorTimer?.cancel();
    _tvHeroManualPauseTimer?.cancel();
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
        final current = _spotlightItem.value ?? _defaultSpotlightItem;
        final idx = current == null ? -1 : _latestMovies.indexWhere((m) => m.globalKey == current.globalKey);
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
    final confirm = await showConfirmDialog(
      context,
      title: t.common.logout,
      message: t.messages.logoutConfirm,
      confirmText: t.common.logout,
      isDestructive: true,
    );

    if (confirm && mounted) {
      final navigator = Navigator.of(context, rootNavigator: true);
      // Use comprehensive logout through UserProfileProvider
      final userProfileProvider = Provider.of<UserProfileProvider>(context, listen: false);
      final multiServerProvider = context.read<MultiServerProvider>();
      final hiddenLibrariesProvider = context.read<HiddenLibrariesProvider>();
      final playbackStateProvider = context.read<PlaybackStateProvider>();
      final connectionRegistry = context.read<ConnectionRegistry>();
      final profileRegistry = context.read<ProfileRegistry>();
      final profileConnReg = context.read<ProfileConnectionRegistry>();
      final plexHome = context.read<PlexHomeService>();
      final companionRemote = context.read<CompanionRemoteProvider>();

      // Clear all user data and provider states
      await companionRemote.resetForLogout();
      await userProfileProvider.logout();
      multiServerProvider.clearAllConnections();
      // Drop the profile/connection rows so the next sign-in starts clean
      // and doesn't bind to stale tokens or orphaned profile rows.
      await profileConnReg.clear();
      await profileRegistry.clear();
      await connectionRegistry.clear();
      await plexHome.clearAll();
      final storage = await StorageService.getInstance();
      await storage.clearActiveProfileId();
      await storage.clearAllProfileLastUsed();
      await hiddenLibrariesProvider.refresh();
      playbackStateProvider.clearShuffle();

      if (navigator.mounted) {
        unawaited(
          navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const AuthScreen()), (route) => false),
        );
      }
    }
  }

  void _handleSwitchProfile(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (context) => const ProfileSwitchScreen()));
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
            : const AppIcon(Symbols.account_circle_rounded, fill: 1, size: 32, color: Colors.white),
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

  Widget _buildOverlaidAppBarBody() {
    final statusBarHeight = MediaQuery.paddingOf(context).top;
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
          colors: [
            overlayColor.withValues(alpha: 0.7),
            overlayColor.withValues(alpha: 0.5),
            overlayColor.withValues(alpha: 0.3),
            Colors.transparent,
          ],
          stops: const [0.0, 0.3, 0.6, 1.0],
        ),
      ),
      child: Padding(
        padding: .only(top: statusBarHeight, left: leftInset, right: 16, bottom: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              // Desktop Netflix nav (wordmark + tabs) replaces the page title,
              // staying transparent over the billboard. Expanded fills space up
              // to the actions so the action cluster stays flush right.
              // Phone/tablet (bottom nav) fall back to the brand mark + wordmark
              // per the navigation mockup; the sidebar already carries the brand
              // on desktop, so side-nav keeps the plain title.
              Expanded(
                child: TopNavScope.isActive(context)
                    ? const TopNavLeading()
                    : PlatformDetector.isTV()
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset('assets/branding/pleya_logo.png', width: 28, height: 28),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'PLEYA',
                            style: TextStyle(color: foregroundColor, fontSize: 14, fontWeight: .w800, letterSpacing: 3.6),
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
                        icon: Symbols.refresh_rounded,
                        iconColor: foregroundColor,
                        onPressed: _discover.load,
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
                      // User menu — profiles + sign out
                      _buildUserMenuAction(context),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBuilder(
      prefs: const [
        SettingsService.showServerNameOnHubs,
        SettingsService.showHeroSection,
        SettingsService.hideSpoilers,
        SettingsService.libraryDensity,
        SettingsService.episodePosterMode,
      ],
      builder: (context) => _buildContent(context),
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
          if (_switchingProfile) const ProfileSwitchingOverlay(),
        ],
      ),
    );
  }

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
          );
    final spotlightTop = (size.height * _tvHeroContentTopFraction).clamp(64.0 * scale, 120.0 * scale).toDouble();
    // Netflix landing: at rest the rail only peeks at the bottom (poster tops +
    // hub label), so the hero owns most of the screen. Focusing the rail reveals
    // it (see [_tvRailRevealed]); the reveal is a translate, so the hero content
    // keeps its resting position and the rail simply slides up over it.
    final railPeek = browseHubs.isEmpty
        ? 0.0
        : math.min(railHeight, size.height * _tvHomeRailPeekFraction);
    final railSafetyBottom = browseHubs.isEmpty ? 0.0 : railPeek + (_tvHeroRailGap * scale);
    final maxSpotlightBottom = (size.height - spotlightTop - (_tvHeroMinInfoHeight * scale))
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
                    final spotlight = _effectiveSpotlightItem;
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
                      compact: false,
                      showPrimaryAction: false,
                      deepBottomScrim: true,
                      kenBurns: true,
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
            Center(
              child: Column(
                mainAxisSize: .min,
                children: [
                  const AppIcon(Symbols.error_outline_rounded, fill: 1, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(_errorMessage!),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _discover.load, child: Text(t.common.retry)),
                ],
              ),
            ),
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
              // At rest the rail is slid down so only [railPeek] shows (poster
              // tops + hub label); focusing it slides the full rail up over the
              // hero's lower edge (Netflix landing). Slide fraction is relative to
              // the rail's own height, so no fixed height is forced on it.
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
                // Billboard is a fixed featured item (newest released) that
                // auto-rotates, decoupled from row focus — otherwise focusing the
                // Continue Watching row hijacks the hero. See _defaultSpotlightItem.
                // To restore focus-follow, re-add a debounced setter and pass it
                // to onFocusedItemChanged (the rail param is still available).
                onRefresh: _discover.updateItem,
                onRemoveFromContinueWatching: _discover.refreshContinueWatching,
                isContinueWatchingHub: (hub) => hub.isContinueWatchingHub,
                usesContinueWatchingAction: (hub) => hub.usesContinueWatchingAction,
                loadMoreItems: (hub) =>
                    hub.id == 'continue_watching' ? _discover.loadAllContinueWatching() : Future.value(hub.items),
                onNavigateUp: _focusTvHeroPlay,
                onNavigateToSidebar: _navigateToSidebar,
                tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
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
          if (_switchingProfile) const ProfileSwitchingOverlay(),
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
          // Solid-white focused pill fully covers the wrapper's background-focus
          // fill, so useBackgroundFocus suppresses the default white ring.
          useBackgroundFocus: true,
          onPressed: () => navigateToMediaItem(context, billboard, playDirectly: true),
          onNavigateDown: () => _focusTvBrowseRailWhenReady(immediate: true),
          onNavigateUp: _focusTopActions,
          onNavigateLeft: () => _moveTvHero(-1),
          onNavigateRight: () => _moveTvHero(1),
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
          useBackgroundFocus: true,
          onPressed: () => navigateToMediaItem(context, billboard),
          onNavigateDown: () => _focusTvBrowseRailWhenReady(immediate: true),
          onNavigateUp: _focusTopActions,
          onNavigateLeft: () => _moveTvHero(-1),
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
        final bg = showFocus ? cs.onSurface : cs.onSurface.withValues(alpha: 0.24);
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
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    final useSideNav = PlatformDetector.shouldUseSideNavigation(context);
    // TV runs through _buildTvContent, so this section is phone/tablet/desktop.
    // ~75vh everywhere, clamped per form factor.
    final h = MediaQuery.sizeOf(context).height;
    final heroHeight = useSideNav
        ? (h * 0.75).clamp(480.0, 900.0) // desktop / tablet
        : (h * 0.75).clamp(420.0, 680.0) + statusBarHeight; // phone
    return SliverToBoxAdapter(
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
                  }
                },
                itemBuilder: (context, index) {
                  return _buildHeroItem(_latestMovies[index], heroHeight);
                },
              ),
              // Page indicators with animated progress and pause/play button
              if (!InputModeTracker.isKeyboardMode(context))
                Positioned(
                  bottom: 16,
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
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
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
    );
  }

  Widget _buildHeroItem(MediaItem heroItem, double heroHeight) {
    final heroClient = _getMediaClientForItem(heroItem);
    final isEpisode = heroItem.isEpisode;
    final showName = heroItem.grandparentTitle ?? heroItem.displayTitle;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = ScreenBreakpoints.isWideTabletOrLarger(screenWidth);
    final isTv = PlatformDetector.isTV();
    // Phone hero uses a portrait 2:3 poster; wide/desktop/TV keep 16:9 backdrop.
    final portrait = !isTv && !isLargeScreen;
    final alignLeft = isTv || isLargeScreen;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final heroLogoWidth = isTv ? TvLayoutConstants.heroLogoWidth : 400.0;
    final heroLogoHeight = isTv ? TvLayoutConstants.heroLogoHeight : 120.0;
    final heroTitleStyle = theme.textTheme.displaySmall?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: .bold,
      fontSize: isTv ? 52 : null,
      shadows: [Shadow(color: colorScheme.surface.withValues(alpha: 0.8), blurRadius: 8)],
    );

    // Determine content type label for chip
    final contentTypeLabel = heroItem.isMovie ? t.discover.movie : t.discover.tvShow;

    // Spoiler protection
    final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
    final shouldHideSpoiler = hideSpoilers && heroItem.shouldHideSpoiler;

    // Build semantic label for hero item
    final heroLabel = isEpisode ? "${heroItem.grandparentTitle}, ${heroItem.title}" : heroItem.title;

    return Semantics(
      label: heroLabel,
      button: true,
      hint: t.accessibility.tapToPlay,
      child: ClickableCursor(
        child: GestureDetector(
          onTap: () {
            appLogger.d('Activating hero item: ${heroItem.title}');
            navigateToMediaItem(context, heroItem, playDirectly: true);
          },
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              // Background Image with fade/zoom animation and parallax
              if (heroItem.artPath != null ||
                  heroItem.backgroundSquarePath != null ||
                  heroItem.grandparentArtPath != null ||
                  (portrait && heroItem.posterThumb() != null))
                ClipRect(
                  child: AnimatedBuilder(
                    animation: _scrollController,
                    builder: (context, child) {
                      final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                      return Transform.translate(offset: Offset(0, scrollOffset * 0.3), child: child);
                    },
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: 1.0 + (0.1 * (1 - value)),
                          child: Opacity(opacity: value, child: child),
                        );
                      },
                      child: Builder(
                        builder: (context) {
                          // heroClient resolves to the actual server's client
                          // (Plex or Jellyfin) so each backend's transcoder
                          // builds sized URLs.
                          final size = MediaQuery.sizeOf(context);
                          final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);
                          final containerAspect = screenWidth / heroHeight;
                          // Effective art height: full 16:9 on wide billboards,
                          // floored at the box height on tall (mobile) ones.
                          // Drives both the fetch and the decode budget so a
                          // width-bound cover isn't upscaled from a short decode.
                          // Match screenWidth (used by containerAspect + the
                          // mem-cache displayWidth) so request, decode budget,
                          // and box width stay aligned even if content is ever
                          // narrower than the window.
                          // Portrait phone hero: the poster fills the tall box,
                          // so the art height is just the box height. Wide/TV
                          // billboards request the full 16:9 frame (floored at
                          // the box height) so the client top-anchors the crop.
                          final artHeight = portrait
                              ? heroHeight
                              : (screenWidth * 9 / 16).clamp(heroHeight, double.infinity).toDouble();
                          final imageUrl = MediaImageHelper.getOptimizedImageUrl(
                            client: heroClient,
                            thumbPath: portrait
                                ? heroItem.posterThumb()
                                : heroItem.heroArt(containerAspectRatio: containerAspect) ??
                                      heroItem.grandparentArtPath,
                            maxWidth: size.width,
                            // Plex crops server-side (minSize=1) from the CENTER,
                            // so a box-shaped request bakes in a centered crop
                            // that lops heads off the top before Flutter's
                            // Alignment.topCenter can act. Request the full 16:9
                            // frame on wide (desktop/TV) billboards so the client
                            // top-anchors the crop — but never below the box
                            // height, or a tall (mobile portrait) billboard would
                            // upscale a too-short image and blur.
                            maxHeight: artHeight,
                            devicePixelRatio: dpr,
                            imageType: ImageType.art,
                          );

                          final (_, memHeight) = MediaImageHelper.getMemCacheDimensions(
                            displayWidth: (screenWidth * dpr).round(),
                            displayHeight: (artHeight * dpr).round(),
                            imageType: ImageType.art,
                          );

                          return blurArtwork(
                            CachedNetworkImage(
                              imageUrl: imageUrl,
                              cacheManager: PlexImageCacheManager.instance,
                              fit: BoxFit.cover,
                              // Top-anchor the crop: hero art is taller than the
                              // wide billboard, so a centered cover clips faces/
                              // titles off the top. The bottom (under the scrim
                              // and title overlay) is the safe side to lose.
                              alignment: Alignment.topCenter,
                              memCacheHeight: memHeight,
                              placeholder: (context, url) =>
                                  ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                              errorBuilder: (context, error, stackTrace) =>
                                  ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
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
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, bgColor.withValues(alpha: 0.9), bgColor],
                            stops: isTv ? const [0.25, 0.78, 1.0] : const [0.5, 0.85, 1.0],
                          ),
                        ),
                      );
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
                        final bgColor = Theme.of(context).scaffoldBackgroundColor;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                bgColor.withValues(alpha: 0.92),
                                bgColor.withValues(alpha: 0.55),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.32, 0.62],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Content with responsive alignment
              Positioned(
                bottom: isTv
                    ? 88
                    : isLargeScreen
                    ? 80
                    : 50,
                left: 0,
                right: isTv
                    ? screenWidth * 0.36
                    : isLargeScreen
                    ? 200
                    : 0,
                child: Padding(
                  padding: .symmetric(
                    horizontal: isTv
                        ? TvLayoutConstants.horizontalInset
                        : isLargeScreen
                        ? 40
                        : 24,
                  ),
                  child: Align(
                    alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isTv ? TvLayoutConstants.heroContentMaxWidth : double.infinity,
                      ),
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
                                      cacheManager: PlexImageCacheManager.instance,
                                      filterQuality: FilterQuality.medium,
                                      fit: BoxFit.contain,
                                      memCacheWidth: (heroLogoWidth * dpr).clamp(200, isTv ? 1000 : 800).round(),
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

                          // Metadata: amber "XX% match" derived from the
                          // rating, then content type / age / year.
                          if (heroItem.year != null || heroItem.contentRating != null || heroItem.rating != null) ...[
                            const SizedBox(height: 16),
                            Wrap(
                              alignment: alignLeft ? WrapAlignment.start : WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 10,
                              children: [
                                if (heroItem.rating != null)
                                  Text(
                                    '${(heroItem.rating! * 10).round()}% match',
                                    style: TextStyle(
                                      color: kAccentAlt,
                                      fontSize: isTv ? 18 : 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                Text(
                                  [
                                    contentTypeLabel,
                                    if (heroItem.contentRating != null) formatContentRating(heroItem.contentRating!),
                                    if (heroItem.year != null) heroItem.year.toString(),
                                  ].join(' • '),
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: isTv ? 18 : 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // On small screens: show button before summary
                          if (!alignLeft) ...[const SizedBox(height: 20), _buildSmartPlayButton(heroItem)],

                          // Summary with episode info (Apple TV style)
                          if (heroItem.summary != null && !shouldHideSpoiler) ...[
                            const SizedBox(height: 12),
                            RichText(
                              maxLines: isTv ? 3 : 2,
                              overflow: .ellipsis,
                              textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                              text: TextSpan(
                                style: TextStyle(
                                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                                  fontSize: isTv ? 18 : 14,
                                  height: isTv ? 1.45 : 1.4,
                                ),
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
                            const SizedBox(height: 12),
                            Text(
                              'S${heroItem.parentIndex}, E${heroItem.index}: ${heroItem.title}',
                              maxLines: 2,
                              overflow: .ellipsis,
                              textAlign: alignLeft ? TextAlign.left : TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurface.withValues(alpha: 0.7),
                                fontSize: isTv ? 18 : 14,
                                height: isTv ? 1.45 : 1.4,
                              ),
                            ),
                          ],

                          // On large screens: show button after summary
                          if (alignLeft) ...[SizedBox(height: isTv ? 28 : 20), _buildSmartPlayButton(heroItem)],
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
        final isTv = PlatformDetector.isTV();

        final minutesLeft = hasProgress ? ((heroItem.durationMs! - heroItem.viewOffsetMs!) / 60_000).round() : 0;

        final progress = hasProgress ? heroItem.viewOffsetMs! / heroItem.durationMs! : 0.0;

        return ListenableBuilder(
          listenable: _heroFocusNode,
          builder: (context, _) {
            final showFocus = isTv && _heroFocusNode.hasFocus && InputModeTracker.isKeyboardMode(context);
            final colorScheme = Theme.of(context).colorScheme;
            final backgroundColor = showFocus ? colorScheme.primary : Colors.white;
            final foregroundColor = showFocus ? colorScheme.onPrimary : Colors.black;
            return InkWell(
              onTap: () {
                appLogger.d('Playing: ${heroItem.title}');
                navigateToVideoPlayer(context, metadata: heroItem);
              },
              borderRadius: BorderRadius.all(Radius.circular(isTv ? 32 : 24)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                padding: .symmetric(horizontal: isTv ? 34 : 24, vertical: isTv ? 16 : 12),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.all(Radius.circular(isTv ? 32 : 24)),
                  boxShadow: showFocus
                      ? [BoxShadow(color: colorScheme.primary.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: 4)]
                      : null,
                ),
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    AppIcon(Symbols.play_arrow_rounded, fill: 1, size: isTv ? 28 : 20, color: foregroundColor),
                    SizedBox(width: isTv ? 12 : 8),
                    if (hasProgress) ...[
                      // Progress bar
                      Container(
                        width: isTv ? 56 : 40,
                        height: isTv ? 8 : 6,
                        decoration: BoxDecoration(
                          color: foregroundColor.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.all(Radius.circular(isTv ? 4 : 3)),
                        ),
                        child: FractionallySizedBox(
                          alignment: .centerLeft,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: foregroundColor,
                              borderRadius: BorderRadius.all(Radius.circular(isTv ? 3 : 2)),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isTv ? 12 : 8),
                      Text(
                        t.discover.minutesLeft(minutes: minutesLeft),
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: isTv ? 18 : 14,
                          fontWeight: isTv ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ] else
                      Text(
                        t.common.play,
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: isTv ? 18 : 14,
                          fontWeight: isTv ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
