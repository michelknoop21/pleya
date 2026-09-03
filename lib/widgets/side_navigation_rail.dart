import '../providers/watchlist_provider.dart';
import 'dart:async';
import '../media/ids.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:pleya/widgets/pleya_logo.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../focus/dpad_navigator.dart';
import '../focus/focus_memory_tracker.dart';
import '../media/media_library.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../navigation/navigation_tabs.dart';
import '../screens/now_watching_screen.dart';
import '../providers/now_watching_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import '../services/settings_service.dart';
import '../utils/platform_detector.dart';
import '../utils/scroll_utils.dart';
import '../utils/library_grouping.dart';
import '../providers/multi_server_provider.dart';
import '../providers/seerr_provider.dart';
import '../services/fullscreen_state_manager.dart';
import '../theme/mono_tokens.dart';
import '../widgets/backend_badge.dart';
import 'side_navigation/nav_destinations.dart';
import '../i18n/strings.g.dart';

enum _LibraryNavSection { visible, hidden }

sealed class _LibraryNavRow {
  final _LibraryNavSection section;

  const _LibraryNavRow({required this.section});
}

final class _LibraryServerHeaderRow extends _LibraryNavRow {
  final String serverId;
  final String serverName;

  const _LibraryServerHeaderRow({required super.section, required this.serverId, required this.serverName});
}

final class _LibraryItemRow extends _LibraryNavRow {
  final MediaLibrary library;
  final bool showServerName;

  const _LibraryItemRow({required super.section, required this.library, this.showServerName = false});
}

/// Reusable navigation rail item widget that handles focus, selection, and interaction
class NavigationRailItem extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;

  /// Solid mockup nav glyph; falls back to [icon]/[selectedIcon] when null.
  final String? svgAsset;
  final Widget label;
  final bool isSelected;
  final bool isFocused;
  final bool isCollapsed;
  final bool useSimpleLayout;
  final VoidCallback onTap;
  final FocusNode focusNode;
  final bool autofocus;
  final BorderRadius borderRadius;
  final double iconSize;
  final double horizontalPadding;
  final bool suppressSelectedBackground;

  /// Called when RIGHT arrow is pressed to navigate to content area.
  final VoidCallback? onNavigateRight;

  /// Stable automation ID (see lib/automation/automation_ids.dart), null on
  /// items Pleya Verify doesn't need to address individually (reconnect,
  /// fullscreen toggle).
  final String? automationId;

  /// Disambiguates repeated [automationId]s across a list — the registered
  /// id becomes `automationId[automationInstance]`.
  final String? automationInstance;

  const NavigationRailItem({
    super.key,
    required this.icon,
    this.selectedIcon,
    this.svgAsset,
    required this.label,
    required this.isSelected,
    required this.isFocused,
    this.isCollapsed = false,
    this.useSimpleLayout = false,
    required this.onTap,
    required this.focusNode,
    this.autofocus = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.iconSize = 22,
    this.horizontalPadding = 17,
    this.suppressSelectedBackground = false,
    this.onNavigateRight,
    this.automationId,
    this.automationInstance,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final showSelectedBackground = isSelected && !suppressSelectedBackground;

    return AutomationNode(
      id: automationId,
      instance: automationInstance,
      role: 'nav.item',
      state: () => {'selected': isSelected, 'collapsed': isCollapsed},
      focusNode: focusNode,
      child: Focus(
        focusNode: focusNode,
        autofocus: autofocus,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey.isSelectKey) {
            onTap();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && onNavigateRight != null) {
            onNavigateRight!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: onTap,
            borderRadius: borderRadius,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: () {
                      // A neutral wash is white-on-dark in dark mode but
                      // black-on-white in light mode, and black at 6% is
                      // #F0F0F0 — indistinguishable from the rail. Light mode
                      // needs a heavier wash to read as the same cue.
                      if (isCollapsed) {
                        return isFocused ? t.onArtworkInk(dark: 0.12, light: 0.22) : null;
                      }
                      if (isFocused) return t.accent.withValues(alpha: showSelectedBackground ? 0.18 : 0.12);
                      // Netflix-style active row: subtle neutral wash, the
                      // red bar carries the accent.
                      if (showSelectedBackground) return t.onArtworkInk(dark: 0.06, light: 0.13);
                      return null;
                    }(),
                    borderRadius: borderRadius,
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: UnconstrainedBox(
                    alignment: .centerLeft,
                    constrainedAxis: Axis.vertical,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: SideNavigationRailState.expandedWidth - 24,
                      child: Padding(
                        padding: .symmetric(vertical: 12, horizontal: horizontalPadding),
                        child: Row(
                          children: [
                            NavGlyph(
                              svgAsset: svgAsset,
                              icon: isSelected && selectedIcon != null ? selectedIcon! : icon,
                              size: iconSize,
                              color: isSelected ? t.text : t.textMuted,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: () {
                                // Simple-layout items (library sub-rows) still must
                                // hide their label when the rail collapses, otherwise
                                // the text bleeds through the narrow clipped rail.
                                if (useSimpleLayout && !isCollapsed) return label;
                                final opacity = isCollapsed ? 0.0 : 1.0;
                                return AnimatedOpacity(
                                  opacity: opacity,
                                  duration: reduceMotion(context, t.fast),
                                  child: label,
                                );
                              }(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Solid red accent bar on the active item.
                if (showSelectedBackground)
                  Positioned(
                    left: 0,
                    top: 8,
                    bottom: 8,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Side navigation rail for Desktop and Android TV platforms
class SideNavigationRail extends StatefulWidget {
  final NavigationTabId selectedTab;
  final String? selectedLibraryKey;
  final bool isOfflineMode;
  final bool isSidebarFocused;
  final bool alwaysExpanded;
  final bool isReconnecting;
  final ValueChanged<NavigationTabId> onDestinationSelected;
  final ValueChanged<String> onLibrarySelected;

  /// Called when RIGHT arrow is pressed to navigate to content without selecting.
  final VoidCallback? onNavigateToContent;

  /// Called when hover/touch expansion changes, so the shell can reserve width.
  final ValueChanged<bool>? onInteractionExpandedChanged;

  /// Called when the user taps the reconnect button in offline mode.
  final VoidCallback? onReconnect;

  const SideNavigationRail({
    super.key,
    required this.selectedTab,
    this.selectedLibraryKey,
    this.isOfflineMode = false,
    this.isSidebarFocused = false,
    this.alwaysExpanded = false,
    this.isReconnecting = false,
    required this.onDestinationSelected,
    required this.onLibrarySelected,
    this.onNavigateToContent,
    this.onInteractionExpandedChanged,
    this.onReconnect,
  });

  @override
  State<SideNavigationRail> createState() => SideNavigationRailState();
}

class SideNavigationRailState extends State<SideNavigationRail> with MountedSetStateMixin {
  bool _isHovered = false;
  bool _isTouchExpanded = false;
  bool _lastReportedInteractionExpanded = false;
  Timer? _collapseTimer;

  /// Held so the ambient poll can be released when the rail goes away.
  NowWatchingProvider? _nowWatching;
  static const double collapsedWidth = 80.0;
  static const double tvCollapsedWidth = 48.0;
  static const double expandedWidth = 220.0;
  static const double _horizontalPadding = 12.0;
  static const double _itemHorizontalPadding = 17.0;
  static const double _defaultIconSize = 22.0;
  static const Duration _collapseDelay = Duration(milliseconds: 150);

  static double collapsedWidthForContext(BuildContext _) => PlatformDetector.isTV() ? tvCollapsedWidth : collapsedWidth;

  static double itemHorizontalPaddingForContext(BuildContext context, {required bool isCollapsed}) {
    if (isCollapsed && PlatformDetector.isTV()) {
      return ((tvCollapsedWidth - _defaultIconSize) / 2).clamp(0.0, _itemHorizontalPadding).toDouble();
    }
    return _itemHorizontalPadding;
  }

  static double horizontalPaddingForContext(BuildContext context, {required bool isCollapsed}) {
    if (!isCollapsed) return _horizontalPadding;
    final centeredPadding =
        ((collapsedWidthForContext(context) - _defaultIconSize) / 2) -
        itemHorizontalPaddingForContext(context, isCollapsed: isCollapsed);
    return centeredPadding.clamp(0.0, _horizontalPadding).toDouble();
  }

  // Focus keys come from the destination enum, so the rail cannot hold a key
  // that no destination owns.
  static final _kHome = NavRailDestination.home.ownFocusKey!;
  static final _kSearch = NavRailDestination.search.ownFocusKey!;
  static final _kRequests = NavRailDestination.requests.ownFocusKey!;
  static final _kWatchlist = NavRailDestination.watchlist.ownFocusKey!;
  static final _kDownloads = NavRailDestination.downloads.ownFocusKey!;
  static final _kSettings = NavRailDestination.settings.ownFocusKey!;
  static final _kNowWatching = NavRailDestination.nowWatching.ownFocusKey!;
  static final _kReconnect = NavRailDestination.reconnect.ownFocusKey!;
  static final _kFullscreen = NavRailDestination.fullscreen.ownFocusKey!;
  static final _kLiveTv = NavRailDestination.liveTv.ownFocusKey!;
  static const _kServerHeaderPrefix = 'serverHeader';
  static const _kLibraryItemPrefix = 'library';

  final Set<String> _collapsedServerGroupKeys = {};

  // Unified focus state tracker for all nav items (main + libraries)
  late final FocusMemoryTracker _focusTracker;

  /// The focus order of the previous build, so a row that disappears can be
  /// replaced by whatever now stands in its place rather than by a guess.
  List<String> _lastFocusOrder = const [];

  /// Where a scheduled focus recovery is currently aiming, or null when none
  /// is pending. A burst of rebuilds (rows arriving one provider at a time)
  /// queues one recovery, and the newest prune decides its target: the older
  /// aim may itself have been pruned in the meantime, and a recovery pointing
  /// at a node that no longer exists is the orphaned focus this exists to
  /// prevent.
  String? _pendingFocusRecoveryKey;

  /// A rail row can vanish under the focus that is on it: the reconnect entry
  /// the moment the server answers again, "now watching" when the last stream
  /// stops, Live TV or Requests when their server drops, a library while the
  /// list reloads. [FocusMemoryTracker.pruneExcept] disposes that node, and a
  /// disposed node hands primary focus up to the enclosing scope — the rail
  /// keeps the focus without any item holding it, so the shell still counts
  /// the sidebar as focused and the rail stays open with nothing on it. On a
  /// remote there is then no key that leads out.
  ///
  /// So focus moves to whatever took the row's place: same index in the new
  /// order, clamped to its end. When the row was not in the previous order at
  /// all — the first build of a rail that was rebuilt from scratch — the
  /// current selection is a better guess than the top of the list, which would
  /// silently move the remote to Home. Deferred to the next frame because
  /// pruning happens inside build, where requesting focus is not allowed.
  void _recoverFocusAfterPrune(String? prunedFocusedKey, List<String> focusOrder) {
    if (prunedFocusedKey == null || focusOrder.isEmpty) return;
    final previousIndex = _lastFocusOrder.indexOf(prunedFocusedKey);
    final targetKey = previousIndex < 0
        ? (_resolveSelectedFocusKey() ?? focusOrder.first)
        : focusOrder[previousIndex.clamp(0, focusOrder.length - 1)];
    final alreadyPending = _pendingFocusRecoveryKey != null;
    // Retarget rather than drop: a second prune in the same frame may have
    // taken the row the pending recovery was aiming at.
    _pendingFocusRecoveryKey = targetKey;
    if (alreadyPending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _pendingFocusRecoveryKey;
      _pendingFocusRecoveryKey = null;
      if (!mounted || key == null) return;
      // Only when the rail still owns the focus. If the shell has meanwhile
      // moved focus into the content — the far more common reason a rail row
      // disappears — pulling it back would be the late callback overwriting
      // the newer state.
      if (!widget.isSidebarFocused) return;
      final node =
          _mountedFocusNodeFor(key) ?? _mountedFocusNodeFor(_resolveSelectedFocusKey()) ?? _mountedFocusNodeFor(_kHome);
      if (node == null || node.hasFocus) return;
      _requestFocusAndReveal(node);
    });
  }

  /// Whether the sidebar should be expanded (always, hover, or focus)
  bool get _shouldExpand => widget.alwaysExpanded || _isHovered || _isTouchExpanded || widget.isSidebarFocused;

  bool get _interactionExpanded => _isHovered || _isTouchExpanded;

  bool get _showDownloads => !PlatformDetector.isAppleTV();

  /// macOS has the system green button; mobile/TV have no OS fullscreen toggle.
  bool get _showFullscreenToggle => Platform.isWindows || Platform.isLinux;

  /// TV only, and only while other people are streaming. Desktop reaches the
  /// same list from the presence control in the app bar, which a pointer can
  /// use and a remote cannot.
  bool _showNowWatching(BuildContext context) =>
      PlatformDetector.isTV() && (context.watch<NowWatchingProvider?>()?.now.hasOthers ?? false);

  @override
  void initState() {
    super.initState();
    _focusTracker = FocusMemoryTracker(
      onFocusChanged: () {
        // ignore: no-empty-block - setState triggers rebuild to update focus styling
        setStateIfMounted(() {});
      },
      debugLabelPrefix: 'nav',
    );
  }

  /// The rail is the surface that carries the now-watching entry on TV, so it
  /// is the rail that keeps the slow poll alive. It cannot live in the entry
  /// itself: that entry only exists while someone is streaming, so it could
  /// never be the thing that notices someone started.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nowWatching = context.read<NowWatchingProvider?>();
    if (identical(nowWatching, _nowWatching)) return;
    _nowWatching?.releaseAmbient();
    _nowWatching = nowWatching?..watchAmbient();
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _nowWatching?.releaseAmbient();
    _focusTracker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SideNavigationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-collapse after navigation (selection changed)
    if (oldWidget.selectedTab != widget.selectedTab || oldWidget.selectedLibraryKey != widget.selectedLibraryKey) {
      final wasInteractionExpanded = _interactionExpanded;
      _isTouchExpanded = false;
      if (wasInteractionExpanded != _interactionExpanded) {
        _scheduleInteractionExpandedNotification();
      }
    }
  }

  void _scheduleInteractionExpandedNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyInteractionExpandedIfNeeded();
    });
  }

  void _notifyInteractionExpandedIfNeeded() {
    final expanded = _interactionExpanded;
    if (_lastReportedInteractionExpanded == expanded) return;
    _lastReportedInteractionExpanded = expanded;
    widget.onInteractionExpandedChanged?.call(expanded);
  }

  void _onHoverEnter() {
    _collapseTimer?.cancel();
    if (_isHovered && !_isTouchExpanded) return;
    setState(() {
      _isTouchExpanded = false; // Mouse takes over
      _isHovered = true;
    });
    _notifyInteractionExpandedIfNeeded();
  }

  void _onHoverExit() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(_collapseDelay, () {
      if (mounted && _isHovered) {
        setState(() => _isHovered = false);
        _notifyInteractionExpandedIfNeeded();
      }
    });
  }

  void _expandForTouch() {
    if (_isTouchExpanded) return;
    setState(() => _isTouchExpanded = true);
    _notifyInteractionExpandedIfNeeded();
  }

  /// The key of the last focused sidebar item (for pre-capture before focus shifts).
  String? get lastFocusedKey => _focusTracker.lastFocusedKey;

  /// Focus the last focused nav item, or Home as fallback.
  /// If [targetKey] is provided, try it first (used when the caller captured
  /// the intended target before a focus-scope switch overwrote it).
  void focusActiveItem({String? targetKey}) {
    final node = _resolveFocusNode(targetKey) ?? _mountedFocusNodeFor(_kHome);
    if (node == null) return;
    _requestFocusAndReveal(node);
  }

  /// Resolve the best mounted focus node in priority order:
  /// 1. Explicit [targetKey] (captured before scope switch)
  /// 2. Last focused key still in the tracker
  /// 3. Currently selected navigation item (tab / library)
  /// 4. Home fallback
  FocusNode? _resolveFocusNode(String? targetKey) {
    return _mountedFocusNodeFor(targetKey) ??
        _mountedFocusNodeFor(_focusTracker.lastFocusedKey) ??
        _mountedFocusNodeFor(_resolveSelectedFocusKey());
  }

  FocusNode? _mountedFocusNodeFor(String? key) {
    if (key == null) return null;
    final node = _focusTracker.nodeFor(key);
    return node?.context == null ? null : node;
  }

  /// Derive a focus key from the current selection state (tab + library).
  /// Returns null if no meaningful selected item exists.
  String? _resolveSelectedFocusKey() {
    switch (widget.selectedTab) {
      case NavigationTabId.movies:
      case NavigationTabId.series:
        return null;
      case NavigationTabId.discover:
        return _kHome;
      case NavigationTabId.libraries:
        final libKey = widget.selectedLibraryKey;
        if (libKey != null) {
          final visibleKey = '$_kLibraryItemPrefix:${_LibraryNavSection.visible.name}:$libKey';
          if (_mountedFocusNodeFor(visibleKey) != null) return visibleKey;
        }
        return _kHome;
      case NavigationTabId.search:
        return _kSearch;
      case NavigationTabId.requests:
        return _kRequests;
      case NavigationTabId.watchlist:
        return _kWatchlist;
      case NavigationTabId.myPleya:
        // Mobile-only destination; the rail never renders it and has nothing
        // to restore focus to. Returning a key here would silently point the
        // focus restore at an item that is not mounted.
        return null;
      case NavigationTabId.downloads:
        return _showDownloads ? _kDownloads : null;
      case NavigationTabId.settings:
        return _kSettings;
      case NavigationTabId.liveTv:
        return _kLiveTv;
    }
  }

  /// Request focus on [node] and scroll it into view after the next frame.
  void _requestFocusAndReveal(FocusNode node) {
    node.requestFocus();
    scrollContextToCenter(node.context);
  }

  String _serverHeaderFocusKey(_LibraryNavSection section, ServerId serverId) =>
      '$_kServerHeaderPrefix:${section.name}:$serverId';

  String _libraryItemFocusKey(_LibraryNavSection section, MediaLibrary library) =>
      '$_kLibraryItemPrefix:${section.name}:${library.globalKey}';

  String _serverGroupStateKey(_LibraryNavSection section, ServerId serverId) => '${section.name}:$serverId';

  String _focusKeyForLibraryRow(_LibraryNavRow row) => switch (row) {
    _LibraryServerHeaderRow(:final section, :final serverId) => _serverHeaderFocusKey(section, ServerId(serverId)),
    _LibraryItemRow(:final section, :final library) => _libraryItemFocusKey(section, library),
  };

  Iterable<String> _focusKeysForLibraryRows(List<_LibraryNavRow> rows) => rows.map(_focusKeyForLibraryRow);

  /// The focus keys the rail currently owns, derived from the destinations it
  /// is rendering. Anything not in here has its node disposed by
  /// [FocusMemoryTracker.pruneExcept], so a key missing from this set is a row
  /// that gets a fresh node on every build and can never hold focus.
  Set<String> _buildValidFocusKeys(List<NavRailDestination> destinations, List<_LibraryNavRow> visibleRows) =>
      _buildFocusOrder(destinations, visibleRows).toSet();

  /// Build rendered rows inside one library section. This is the single source
  /// of truth for both widget rendering and D-pad focus ordering.
  List<_LibraryNavRow> _buildLibraryRows(
    List<MediaLibrary> libs, {
    required _LibraryNavSection section,
    required bool showServerHeaders,
  }) {
    if (!showServerHeaders) {
      final nonUniqueNames = _getNonUniqueLibraryNames(libs);
      return libs.map((lib) {
        return _LibraryItemRow(
          section: section,
          library: lib,
          showServerName: nonUniqueNames.contains(lib.title) && lib.serverName != null,
        );
      }).toList();
    }
    final grouped = groupLibrariesByFirstAppearance(libs);
    final result = <_LibraryNavRow>[];
    for (final serverKey in grouped.serverOrder) {
      final bucket = grouped.byServer[serverKey]!;
      if (serverKey.isNotEmpty) {
        result.add(
          _LibraryServerHeaderRow(
            section: section,
            serverId: serverKey,
            serverName: bucket.first.serverName ?? serverKey,
          ),
        );
      }
      if (serverKey.isEmpty ||
          !_collapsedServerGroupKeys.contains(_serverGroupStateKey(section, ServerId(serverKey)))) {
        for (final lib in bucket) {
          result.add(_LibraryItemRow(section: section, library: lib));
        }
      }
    }
    return result;
  }

  Set<String> _buildServerGroupStateKeys(
    List<MediaLibrary> visibleLibraries,
    List<MediaLibrary> hiddenLibraries, {
    required bool showServerHeaders,
  }) {
    if (!showServerHeaders) return {};

    return {
      for (final lib in visibleLibraries)
        if (lib.serverId != null) _serverGroupStateKey(_LibraryNavSection.visible, ServerId(lib.serverId!)),
      for (final lib in hiddenLibraries)
        if (lib.serverId != null) _serverGroupStateKey(_LibraryNavSection.hidden, ServerId(lib.serverId!)),
    };
  }

  /// Ordered list of focusable keys, in the same top-to-bottom order the
  /// destinations render in. The library entry expands into its own rows.
  List<String> _buildFocusOrder(List<NavRailDestination> destinations, List<_LibraryNavRow> visibleRows) => [
    for (final destination in destinations)
      if (destination.slot == NavRailSlot.libraries)
        ..._focusKeysForLibraryRows(visibleRows)
      else
        destination.ownFocusKey!,
  ];

  void _debugAssertFocusOrder(List<String> focusOrder, List<NavRailDestination> destinations) {
    assert(() {
      final seen = <String>{};
      for (final key in focusOrder) {
        if (!seen.add(key)) {
          throw FlutterError('SideNavigationRail focus order contains duplicate key: $key');
        }
      }
      // Every rendered destination must be walkable. This is true by
      // construction now that one list feeds both, and the assert is what keeps
      // it true if someone reintroduces a hand-written list.
      for (final destination in destinations) {
        final key = destination.ownFocusKey;
        if (key != null && !seen.contains(key)) {
          throw FlutterError('SideNavigationRail renders ${destination.name} but never focuses it');
        }
      }
      return true;
    }());
  }

  /// Handle D-pad UP/DOWN by explicitly moving focus to the next/previous item.
  KeyEventResult _handleVerticalNavigation(FocusNode _, KeyEvent event, List<String> focusOrder) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final isUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!isDown && !isUp) return KeyEventResult.ignored;

    final currentKey = _focusTracker.lastFocusedKey;
    if (currentKey == null) return KeyEventResult.ignored;

    final currentIndex = focusOrder.indexOf(currentKey);
    if (currentIndex == -1) return KeyEventResult.ignored;

    final nextIndex = isDown ? currentIndex + 1 : currentIndex - 1;
    if (nextIndex < 0 || nextIndex >= focusOrder.length) return KeyEventResult.handled;

    final nextNode = _focusTracker.nodeFor(focusOrder[nextIndex]);
    if (nextNode == null) return KeyEventResult.ignored;

    _requestFocusAndReveal(nextNode);
    return KeyEventResult.handled;
  }

  /// Collapse the sidebar (resets touch-expand state).
  void collapse() {
    if (_isTouchExpanded) {
      setState(() => _isTouchExpanded = false);
      _notifyInteractionExpandedIfNeeded();
    }
  }

  /// Reload libraries (called when servers change or profile switches)
  void reloadLibraries() {
    final librariesProvider = context.read<LibrariesProvider>();
    librariesProvider.refresh();
  }

  IconData _getLibraryIcon(String type) {
    switch (type.toLowerCase()) {
      case 'movie':
        return Symbols.movie_rounded;
      case 'show':
        return Symbols.tv_rounded;
      case 'artist':
        return Symbols.music_note_rounded;
      case 'photo':
        return Symbols.photo_rounded;
      case 'mixed':
        return Symbols.share_rounded;
      default:
        return Symbols.folder_rounded;
    }
  }

  String _getLibrarySvg(String type) {
    switch (type.toLowerCase()) {
      case 'movie':
        return NavGlyphs.libMovie;
      case 'show':
        return NavGlyphs.libShow;
      case 'artist':
        return NavGlyphs.libMusic;
      case 'photo':
        return NavGlyphs.libPhoto;
      case 'mixed':
        return NavGlyphs.libMixed;
      default:
        return NavGlyphs.libFolder;
    }
  }

  /// Calculate top padding for macOS traffic lights
  double _getTopPadding(BuildContext context) {
    double basePadding = MediaQuery.paddingOf(context).top + 16;

    // On macOS, add extra padding for traffic lights (when not fullscreen)
    if (Platform.isMacOS) {
      final isFullscreen = FullscreenStateManager().isFullscreen;
      if (!isFullscreen) {
        // Traffic lights area is approximately 52 pixels high
        basePadding = basePadding < 52 ? 52 : basePadding;
      }
    }

    return basePadding;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final librariesProvider = context.watch<LibrariesProvider>();
    final hiddenLibrariesProvider = context.watch<HiddenLibrariesProvider>();
    final hiddenKeys = hiddenLibrariesProvider.hiddenLibraryKeys;

    final allLibraries = librariesProvider.libraries;
    final visibleLibraries = <MediaLibrary>[];
    final hiddenLibraries = <MediaLibrary>[];
    final serverIds = <String>{};
    for (final lib in allLibraries) {
      if (lib.serverId != null) serverIds.add(lib.serverId!);
      if (hiddenKeys.contains(lib.globalKey)) {
        hiddenLibraries.add(lib);
      } else {
        visibleLibraries.add(lib);
      }
    }

    final isCollapsed = !_shouldExpand;
    final effectiveCollapsedWidth = collapsedWidthForContext(context);
    // The width the rail is heading for, flipped synchronously with
    // [_shouldExpand]; the panel below animates towards it over [panelMotion].
    final railTargetWidth = isCollapsed ? effectiveCollapsedWidth : expandedWidth;
    // The box the layers below are positioned in: wide enough to hold the rail
    // at full width. It is a container, not a claim. What the rail actually owns
    // at any moment is `owned` below, and while the rail sits shut that is the
    // collapsed rail and nothing more. On TV there is no pointer, so the box is
    // exactly the rail: nothing may hang over the spotlight.
    final bandWidth = PlatformDetector.isTV() ? railTargetWidth : expandedWidth;
    // One duration for the panel and for the mirror tween that tracks it. They
    // must not drift, or the hit box stops matching the pixels.
    final panelMotion = reduceMotion(context, t.normal);
    final horizontalPadding = horizontalPaddingForContext(context, isCollapsed: isCollapsed);
    final itemHorizontalPadding = itemHorizontalPaddingForContext(context, isCollapsed: isCollapsed);
    // Every condition is read once, here, and travels as data. Reading a
    // provider a second time deeper in the tree is how the rendered rows and
    // the focus lists drifted apart in the first place.
    final conditions = NavRailConditions(
      isOfflineMode: widget.isOfflineMode,
      canReconnect: widget.onReconnect != null,
      hasLiveTv: context.watch<MultiServerProvider>().hasLiveTv,
      hasSeerr: context.watch<SeerrProvider?>()?.isConfigured ?? false,
      hasWatchlist: context.watch<WatchlistProvider?>()?.hasWatchlist ?? false,
      showNowWatching: _showNowWatching(context),
      showDownloads: _showDownloads,
      showFullscreenToggle: _showFullscreenToggle,
    );
    final destinations = buildNavRailDestinations(conditions);

    // Listen to fullscreen + groupLibrariesByServer setting so the rail
    // rebuilds when the user toggles "Group libraries by server" in Appearance.
    return AutomationNode(
      id: AutomationIds.sidebarRail,
      role: 'sidebar',
      child: ListenableBuilder(
        listenable: Listenable.merge([
          FullscreenStateManager(),
          SettingsService.instance.listenable(SettingsService.groupLibrariesByServer),
        ]),
        builder: (context, _) {
          // Server grouping: only when multi-server AND the user-facing toggle is on.
          final groupByServerSetting = SettingsService.instance.read(SettingsService.groupLibrariesByServer);
          final showServerHeaders = serverIds.length > 1 && groupByServerSetting;
          _collapsedServerGroupKeys.retainAll(
            _buildServerGroupStateKeys(visibleLibraries, hiddenLibraries, showServerHeaders: showServerHeaders),
          );
          final visibleRows = _buildLibraryRows(
            visibleLibraries,
            section: _LibraryNavSection.visible,
            showServerHeaders: showServerHeaders,
          );
          final prunedFocusedKey = _focusTracker.pruneExcept(_buildValidFocusKeys(destinations, visibleRows));
          final focusOrder = _buildFocusOrder(destinations, visibleRows);
          _debugAssertFocusOrder(focusOrder, destinations);
          _recoverFocusAfterPrune(prunedFocusedKey, focusOrder);
          _lastFocusOrder = focusOrder;
          return TapRegion(
            onTapOutside: (_) {
              if (_isTouchExpanded) {
                setState(() => _isTouchExpanded = false);
                _notifyInteractionExpandedIfNeeded();
              }
            },
            // Mirrors the panel's width animation so every layer below can ask
            // "how wide is the rail *right now*" instead of reading a boolean
            // that flipped 200ms ago. A mirror tween rather than a latch released
            // by AnimatedContainer.onEnd: a missed onEnd (reduced motion, dispose
            // race) would freeze the band, and a frozen band is a dead zone over
            // the content — the opposite failure.
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: railTargetWidth),
              duration: panelMotion,
              curve: Curves.easeOutCubic,
              builder: (context, paintedWidth, _) {
                // What the rail owns right now, and the whole of the ownership
                // rule in one line. Shut and idle the target is the collapsed
                // rail, so this is 80 and the strip beside it belongs to the
                // content. Once a pointer has entered over the rail the target is
                // already the expanded width, so ownership jumps there on the
                // first frame and the pointer cannot outrun the easeOutCubic.
                // Collapsing, the target drops back while the paint lags, so the
                // pixels still on screen stay owned until they are gone.
                final owned = paintedWidth < railTargetWidth ? railTargetWidth : paintedWidth;
                // The rows are live for as long as they are visible. Keying this
                // off `isCollapsed` killed them the instant the collapse timer
                // fired, while the panel stood at full width for another 200ms.
                final panelInteractive = paintedWidth > effectiveCollapsedWidth + 0.5;
                return SizedBox(
                  width: bandWidth,
                  child: Stack(
                    children: [
                      // Layer 1 — the band, claimed for exactly as long as the rail
                      // owns it.
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: 0,
                        width: owned,
                        child: AbsorbPointer(absorbing: owned > effectiveCollapsedWidth + 0.5),
                      ),
                      // Layer 2 — the rail itself. No `width` on the Positioned: a
                      // tight constraint would kill the width animation.
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: 0,
                        child: MouseRegion(
                          // Cursor only. Hover *state* lives on layer 3, or moving
                          // from the panel into the empty band would fire onExit and
                          // start collapsing while the pointer is still in the band.
                          cursor: isCollapsed ? SystemMouseCursors.click : MouseCursor.defer,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: panelInteractive ? null : _expandForTouch,
                            child: AnimatedContainer(
                              duration: panelMotion,
                              curve: Curves.easeOutCubic,
                              width: railTargetWidth,
                              clipBehavior: Clip.hardEdge,
                              decoration: const BoxDecoration(),
                              child: Stack(
                                children: [
                                  // TV: left-to-right gradient scrim (Netflix-TV nav) so the
                                  // rail reads over the billboard without a hard panel.
                                  // Non-TV: solid surface panel.
                                  //
                                  // The labels on top are theme-coloured, so the scrim has to
                                  // follow: a black veil under near-black light-mode text is
                                  // unreadable. Dark keeps its original pure-black ramp;
                                  // light washes with the page background, harder and further
                                  // (the artwork stays bright, the ink does not).
                                  Positioned.fill(
                                    child: PlatformDetector.isTV()
                                        ? DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                                colors: t.isLight
                                                    ? [
                                                        t.artworkScrim.withValues(alpha: 0.97),
                                                        t.artworkScrim.withValues(alpha: 0.70),
                                                        const Color(0x00000000),
                                                      ]
                                                    : const [Color(0xE6000000), Color(0x00000000)],
                                                stops: t.isLight ? const [0.0, 0.62, 1.0] : null,
                                              ),
                                            ),
                                          )
                                        : ColoredBox(color: t.surface),
                                  ),
                                  IgnorePointer(
                                    // Live for as long as the row is visible.
                                    // Keying this off `isCollapsed` killed every
                                    // row the instant the collapse timer fired,
                                    // while the panel stood at full width for
                                    // another 200ms.
                                    ignoring: !panelInteractive,
                                    child: Focus(
                                      canRequestFocus: false,
                                      skipTraversal: true,
                                      onKeyEvent: (node, event) => _handleVerticalNavigation(node, event, focusOrder),
                                      child: Column(
                                        children: [
                                          SizedBox(height: _getTopPadding(context)),
                                          _buildBrandHeader(
                                            isCollapsed: isCollapsed,
                                            horizontalPadding: horizontalPadding,
                                            itemHorizontalPadding: itemHorizontalPadding,
                                          ),
                                          Expanded(
                                            child: ListView(
                                              padding: .symmetric(horizontal: horizontalPadding),
                                              clipBehavior: Clip.hardEdge,
                                              children: _buildScrollingDestinations(
                                                destinations,
                                                visibleRows,
                                                t,
                                                isCollapsed: isCollapsed,
                                              ),
                                            ),
                                          ),
                                          if (destinations.contains(NavRailDestination.fullscreen))
                                            Padding(
                                              padding: .fromLTRB(horizontalPadding, 0, horizontalPadding, 12),
                                              child: _buildFullscreenItem(isCollapsed: isCollapsed),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Layer 3 — watches what the rail owns and takes nothing. A
                      // translucent MouseRegion joins the hit path (so the
                      // MouseTracker fires enter/exit across the whole of it) while
                      // its hitTest returns false, so the Stack keeps walking down
                      // to the panel and out to the content. It registers no
                      // gesture recognizer, so nothing here competes with the hero.
                      //
                      // Sized to `owned`, never to [bandWidth]. A permanent
                      // expanded-width watcher turned every approach to a control
                      // beside the shut rail into an entry into the menu, which
                      // then swallowed the click and slid the control out from
                      // under the cursor: the Recommended tab on a library page
                      // became unclickable on macOS. Ownership is earned by
                      // entering over the rail, not reserved in advance.
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: 0,
                        width: owned,
                        child: MouseRegion(
                          opaque: false,
                          hitTestBehavior: HitTestBehavior.translucent,
                          onEnter: (_) => _onHoverEnter(),
                          onExit: (_) => _onHoverExit(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Brand row per the navigation mockup: logo mark with the PLEYA wordmark
  /// that fades in when the rail expands.
  Widget _buildBrandHeader({
    required bool isCollapsed,
    required double horizontalPadding,
    required double itemHorizontalPadding,
  }) {
    final t = tokens(context);
    const logoSize = 36.0;
    // Align the logo's center with the 22px nav icon column below it.
    final leftPadding = (horizontalPadding + itemHorizontalPadding - (logoSize - _defaultIconSize) / 2).clamp(
      0.0,
      double.infinity,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(leftPadding, 4, 0, 18),
      child: Align(
        alignment: Alignment.centerLeft,
        child: UnconstrainedBox(
          alignment: .centerLeft,
          constrainedAxis: Axis.vertical,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: expandedWidth - 24,
            child: Row(
              children: [
                const PleyaLogo(size: logoSize),
                const SizedBox(width: 12),
                AnimatedOpacity(
                  opacity: isCollapsed ? 0.0 : 1.0,
                  duration: reduceMotion(context, t.fast),
                  child: Text(
                    'PLEYA',
                    style: TextStyle(fontSize: 16, fontWeight: .w800, letterSpacing: 4.8, color: t.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The rows inside the scrolling list, one per destination, in list order.
  /// The gaps sit between entries, which is what the hand-written list did with
  /// a spacer after every row but the last.
  List<Widget> _buildScrollingDestinations(
    List<NavRailDestination> destinations,
    List<_LibraryNavRow> visibleRows,
    dynamic t, {
    required bool isCollapsed,
  }) {
    final rows = <Widget>[];
    for (final destination in destinations) {
      if (destination.slot == NavRailSlot.footer) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(_buildDestination(destination, visibleRows, t, isCollapsed: isCollapsed));
    }
    return rows;
  }

  /// One destination, one row. The switch is exhaustive on purpose: a new
  /// destination cannot be added to [NavRailDestination] without the compiler
  /// asking how it renders.
  Widget _buildDestination(
    NavRailDestination destination,
    List<_LibraryNavRow> visibleRows,
    dynamic t, {
    required bool isCollapsed,
  }) {
    final labels = Translations.of(context);
    return switch (destination) {
      NavRailDestination.reconnect => _buildReconnectItem(isCollapsed: isCollapsed),
      NavRailDestination.home => _buildTabNavItem(
        destination,
        icon: Symbols.home_rounded,
        svgAsset: NavGlyphs.home,
        label: labels.common.home,
        isCollapsed: isCollapsed,
      ),
      NavRailDestination.libraries => _buildLibrariesFlat(visibleRows, t, isCollapsed: isCollapsed),
      NavRailDestination.liveTv => _buildTabNavItem(
        destination,
        icon: Symbols.live_tv_rounded,
        svgAsset: NavGlyphs.liveTv,
        label: labels.navigation.liveTv,
        isCollapsed: isCollapsed,
      ),
      NavRailDestination.search => _buildTabNavItem(
        destination,
        icon: Symbols.search_rounded,
        svgAsset: NavGlyphs.search,
        label: labels.common.search,
        isCollapsed: isCollapsed,
      ),
      // Watchlist: only when this profile has a source or a snapshot for one.
      NavRailDestination.watchlist => _buildTabNavItem(
        destination,
        icon: Symbols.bookmark_add_rounded,
        svgAsset: NavGlyphs.watchlist,
        label: labels.navigation.watchlist,
        isCollapsed: isCollapsed,
      ),
      // Requests (Jellyseerr/Overseerr): only when configured.
      NavRailDestination.requests => _buildTabNavItem(
        destination,
        icon: Symbols.playlist_add_rounded,
        svgAsset: NavGlyphs.requests,
        label: labels.seerr.title,
        isCollapsed: isCollapsed,
      ),
      // Who is streaming right now, TV only: the app bar's overlay panel cannot
      // be reached with a remote, so the rail is the way in and the list opens
      // as a page. The push uses the rail's own context, which sits under
      // ProfileNavigationScope, so it lands on the nested navigator.
      NavRailDestination.nowWatching => _buildNavItem(
        icon: Symbols.sensors_rounded,
        selectedIcon: Symbols.sensors_rounded,
        label: labels.nowWatching.sidebarLabel,
        isSelected: false,
        isFocused: _focusTracker.isFocused(_kNowWatching),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NowWatchingScreen())),
        focusNode: _focusTracker.get(_kNowWatching),
        isCollapsed: isCollapsed,
      ),
      // Downloads is hidden on Apple TV: no user file storage there.
      NavRailDestination.downloads => _buildTabNavItem(
        destination,
        icon: Symbols.download_rounded,
        svgAsset: NavGlyphs.downloads,
        label: labels.navigation.downloads,
        isCollapsed: isCollapsed,
      ),
      NavRailDestination.settings => _buildTabNavItem(
        destination,
        icon: Symbols.settings_rounded,
        svgAsset: NavGlyphs.settings,
        label: labels.common.settings,
        isCollapsed: isCollapsed,
      ),
      NavRailDestination.fullscreen => _buildFullscreenItem(isCollapsed: isCollapsed),
    };
  }

  /// A destination that switches tabs. Selection, focus and activation all read
  /// the destination's own identity, never a position in a list.
  Widget _buildTabNavItem(
    NavRailDestination destination, {
    required IconData icon,
    String? svgAsset,
    required String label,
    required bool isCollapsed,
  }) {
    final focusKey = destination.ownFocusKey!;
    final tab = destination.tab!;
    return _buildNavItem(
      icon: icon,
      selectedIcon: icon,
      svgAsset: svgAsset,
      label: label,
      isSelected: widget.selectedTab == tab,
      isFocused: _focusTracker.isFocused(focusKey),
      onTap: () => widget.onDestinationSelected(tab),
      focusNode: _focusTracker.get(focusKey),
      isCollapsed: isCollapsed,
      automationId: AutomationIds.navTab(tab),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData selectedIcon,
    String? svgAsset,
    required String label,
    required bool isSelected,
    required bool isFocused,
    required VoidCallback onTap,
    required FocusNode focusNode,
    required bool isCollapsed,
    bool autofocus = false,
    String? automationId,
  }) {
    final t = tokens(context);
    final itemHorizontalPadding = itemHorizontalPaddingForContext(context, isCollapsed: isCollapsed);

    return NavigationRailItem(
      icon: icon,
      selectedIcon: selectedIcon,
      svgAsset: svgAsset,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? t.text : t.textMuted,
        ),
        overflow: .ellipsis,
        maxLines: 1,
      ),
      isSelected: isSelected,
      isFocused: isFocused,
      isCollapsed: isCollapsed,
      onTap: onTap,
      focusNode: focusNode,
      autofocus: autofocus,
      automationId: automationId,
      horizontalPadding: itemHorizontalPadding,
      suppressSelectedBackground: widget.isSidebarFocused,
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  Widget _buildReconnectItem({required bool isCollapsed}) {
    final t = tokens(context);
    final isFocused = _focusTracker.isFocused(_kReconnect);
    final itemHorizontalPadding = itemHorizontalPaddingForContext(context, isCollapsed: isCollapsed);

    return NavigationRailItem(
      icon: widget.isReconnecting ? Symbols.sync_rounded : Symbols.wifi_rounded,
      label: widget.isReconnecting
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.text))
          : Text(
              Translations.of(context).common.reconnect,
              style: TextStyle(fontSize: 14, fontWeight: .w400, color: t.textMuted),
              overflow: .ellipsis,
              maxLines: 1,
            ),
      isSelected: false,
      isFocused: isFocused,
      isCollapsed: isCollapsed,
      // ignore: no-empty-block - no-op tap handler while reconnecting
      onTap: widget.isReconnecting ? () {} : () => widget.onReconnect?.call(),
      focusNode: _focusTracker.get(_kReconnect),
      horizontalPadding: itemHorizontalPadding,
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  Widget _buildFullscreenItem({required bool isCollapsed}) {
    final t = tokens(context);
    final isFullscreen = FullscreenStateManager().isFullscreen;
    final isFocused = _focusTracker.isFocused(_kFullscreen);
    final itemHorizontalPadding = itemHorizontalPaddingForContext(context, isCollapsed: isCollapsed);

    return NavigationRailItem(
      icon: isFullscreen ? Symbols.fullscreen_exit_rounded : Symbols.fullscreen_rounded,
      label: Text(
        isFullscreen ? Translations.of(context).common.exitFullscreen : Translations.of(context).common.fullscreen,
        style: TextStyle(fontSize: 14, fontWeight: .w400, color: t.textMuted),
        overflow: .ellipsis,
        maxLines: 1,
      ),
      isSelected: false,
      isFocused: isFocused,
      isCollapsed: isCollapsed,
      onTap: () => unawaited(FullscreenStateManager().toggleFullscreen()),
      focusNode: _focusTracker.get(_kFullscreen),
      horizontalPadding: itemHorizontalPadding,
      onNavigateRight: widget.onNavigateToContent,
    );
  }

  /// Visible libraries pinned directly onto the rail as individual items (no
  /// collapsible "Media" header). Hidden libraries are managed in Settings →
  /// library visibility. In collapsed mode the items render icon-only, clipped
  /// by the rail width just like the other nav items.
  Widget _buildLibrariesFlat(List<_LibraryNavRow> visibleRows, dynamic t, {bool isCollapsed = false}) {
    final isLoading = context.watch<LibrariesProvider>().isLoading;
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: t.textMuted)),
        ),
      );
    }
    if (visibleRows.isEmpty) return const SizedBox.shrink();
    return _buildLibraryGroupedColumn(visibleRows, t, isCollapsed: isCollapsed);
  }

  /// Get set of library names that appear more than once (not globally unique)
  Set<String> _getNonUniqueLibraryNames(List<MediaLibrary> libraries) {
    final nameCounts = <String, int>{};
    for (final lib in libraries) {
      nameCounts[lib.title] = (nameCounts[lib.title] ?? 0) + 1;
    }
    return nameCounts.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
  }

  Widget _buildLibraryGroupedColumn(List<_LibraryNavRow> rows, dynamic t, {bool isCollapsed = false}) {
    return Column(
      crossAxisAlignment: .start,
      children: rows.map((row) {
        return switch (row) {
          _LibraryServerHeaderRow(:final section, :final serverId, :final serverName) => _buildServerHeader(
            section,
            ServerId(serverId),
            serverName,
            t,
            isCollapsed: isCollapsed,
          ),
          _LibraryItemRow(:final section, :final library, :final showServerName) => _buildLibraryItem(
            section,
            library,
            t,
            showServerName: showServerName,
            isCollapsed: isCollapsed,
          ),
        };
      }).toList(),
    );
  }

  Widget _buildServerHeader(
    _LibraryNavSection section,
    ServerId serverId,
    String serverName,
    dynamic t, {
    bool isCollapsed = false,
  }) {
    // Resolve backend per server so the badge matches the brand. Falls back
    // to the generic `dns` icon if the client isn't registered yet (rare —
    // can happen during a profile switch before the manager rehydrates).
    final backend = context.read<MultiServerProvider>().serverManager.getClient(serverId)?.backend;
    return _buildCollapsibleHeader(
      focusKey: _serverHeaderFocusKey(section, serverId),
      icon: Symbols.dns_rounded,
      iconSize: 14,
      leading: backend == null ? null : BackendBadge(backend: backend, size: 14, color: t.textMuted),
      label: serverName,
      labelStyle: TextStyle(fontSize: 11, fontWeight: .w600, letterSpacing: 0.4, color: t.textMuted),
      verticalPadding: 6,
      isExpanded: !_collapsedServerGroupKeys.contains(_serverGroupStateKey(section, serverId)),
      onToggle: () => _toggleServerCollapse(section, serverId),
      t: t,
      isCollapsed: isCollapsed,
    );
  }

  void _toggleServerCollapse(_LibraryNavSection section, ServerId serverId) {
    final groupKey = _serverGroupStateKey(section, serverId);
    setState(() {
      if (!_collapsedServerGroupKeys.add(groupKey)) {
        _collapsedServerGroupKeys.remove(groupKey);
      }
    });
  }

  Widget _buildCollapsibleHeader({
    required String focusKey,
    required IconData icon,
    required double iconSize,
    Widget? leading,
    required String label,
    required TextStyle labelStyle,
    required double verticalPadding,
    required bool isExpanded,
    required VoidCallback onToggle,
    required dynamic t,
    bool isCollapsed = false,
  }) {
    final isFocused = _focusTracker.isFocused(focusKey);
    final radius = BorderRadius.circular(tokens(context).radiusSm);
    // Match library-item indent when expanded; drop it when collapsed so the
    // icon lines up with the icon-only Home/Search rows on the narrow rail.
    return Padding(
      padding: EdgeInsets.only(left: isCollapsed ? 0 : 12),
      child: Focus(
        focusNode: _focusTracker.get(focusKey),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey.isSelectKey) {
            onToggle();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && widget.onNavigateToContent != null) {
            widget.onNavigateToContent!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: onToggle,
            borderRadius: radius,
            child: Container(
              decoration: BoxDecoration(
                color: isFocused ? t.onArtworkInk(dark: 0.08, light: 0.16) : null,
                borderRadius: radius,
              ),
              clipBehavior: Clip.hardEdge,
              child: UnconstrainedBox(
                alignment: .centerLeft,
                constrainedAxis: Axis.vertical,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: expandedWidth - 24,
                  child: Padding(
                    padding: .symmetric(vertical: verticalPadding, horizontal: 17),
                    child: Row(
                      children: [
                        leading ?? AppIcon(icon, fill: 1, size: iconSize, color: t.textMuted),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(label, style: labelStyle, overflow: .ellipsis),
                        ),
                        AppIcon(
                          isExpanded ? Symbols.expand_less_rounded : Symbols.expand_more_rounded,
                          fill: 1,
                          size: 16,
                          color: t.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLibraryItem(
    _LibraryNavSection section,
    MediaLibrary library,
    dynamic t, {
    bool showServerName = false,
    bool isCollapsed = false,
  }) {
    final isSelected =
        widget.selectedTab == NavigationTabId.libraries && widget.selectedLibraryKey == library.globalKey;
    final focusKey = _libraryItemFocusKey(section, library);
    final isFocused = _focusTracker.isFocused(focusKey);
    final focusNode = _focusTracker.get(focusKey);

    // Drop the sub-item indent when collapsed so the library icon aligns with
    // the icon-only Home/Search rows on the narrow rail.
    return Padding(
      padding: EdgeInsets.only(left: isCollapsed ? 0 : 12),
      child: NavigationRailItem(
        isCollapsed: isCollapsed,
        svgAsset: _getLibrarySvg(library.kind.id),
        icon: _getLibraryIcon(library.kind.id),
        selectedIcon: _getLibraryIcon(library.kind.id),
        label: Column(
          crossAxisAlignment: .start,
          mainAxisSize: .min,
          children: [
            Text(
              library.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? t.text : t.textMuted,
              ),
              overflow: .ellipsis,
            ),
            if (showServerName)
              Text(
                library.serverName!,
                // 40% ink is a legible hint as white-on-dark, but as
                // black-on-white it is #999 — under AA at this 9px size.
                style: TextStyle(fontSize: 9, color: t.textMuted.withValues(alpha: t.isLight ? 0.72 : 0.4)),
                overflow: .ellipsis,
              ),
          ],
        ),
        isSelected: isSelected,
        isFocused: isFocused,
        useSimpleLayout: true,
        onTap: () => widget.onLibrarySelected(library.globalKey),
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(tokens(context).radiusSm),
        iconSize: 18,
        suppressSelectedBackground: widget.isSidebarFocused,
        onNavigateRight: widget.onNavigateToContent,
        automationId: AutomationIds.sidebarLibraryRow,
        automationInstance: library.globalKey,
      ),
    );
  }
}
