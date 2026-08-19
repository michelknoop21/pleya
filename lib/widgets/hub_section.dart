import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../diagnostics/select_trace.dart';
import '../diagnostics/select_trace_recorder.dart';
import '../focus/dpad_navigator.dart';
import '../focus/focus_theme.dart';
import '../focus/input_mode_tracker.dart';
import '../focus/key_event_utils.dart';
import '../services/settings_service.dart';
import 'settings_builder.dart';
import '../utils/grid_size_calculator.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';
import '../theme/mono_tokens.dart';
import '../focus/locked_hub_controller.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../screens/hub_detail_screen.dart';
import '../utils/app_logger.dart';
import '../utils/media_navigation_helper.dart';
import 'focus_builders.dart';
import 'hub_activation.dart';
import 'media_card.dart';
import 'media_card_grid_layout.dart';
import '../utils/scroll_utils.dart';
import 'horizontal_scroll_with_arrows.dart';
import '../i18n/strings.g.dart';

/// Shared hub section widget used in both discover and library screens
/// Displays a hub title with icon and a horizontal scrollable list of items
///
/// Uses a "locked" focus pattern where:
/// - A single Focus widget at the hub level intercepts ALL arrow keys
/// - Visual focus index is tracked in state (not Flutter's focus system)
/// - Children render focus visuals based on the passed index
/// - Focus never "escapes" to random elements
class HubSection extends StatefulWidget {
  final MediaHub hub;
  final IconData icon;
  final void Function(String)? onRefresh;
  final VoidCallback? onRemoveFromContinueWatching;
  final bool isInContinueWatching;
  final bool usesContinueWatchingAction;
  final bool showServerName;
  final Future<List<MediaItem>> Function()? loadMoreItems;

  /// Reports the current focused media item. Used by TV spotlight layouts.
  final ValueChanged<MediaItem>? onFocusedItemChanged;

  /// Callback for vertical navigation (up/down). Return true if handled.
  final bool Function(bool isUp)? onVerticalNavigation;

  /// Called when the user presses BACK.
  /// Used to navigate focus back to the tab bar.
  final VoidCallback? onBack;

  /// Called when the user presses UP while at the topmost item (first hub).
  /// Used to navigate focus to the tab bar.
  final VoidCallback? onNavigateUp;

  /// Called when the user presses LEFT while at the leftmost item (index 0).
  /// Used to navigate focus to the sidebar.
  final VoidCallback? onNavigateToSidebar;

  /// When true, removes internal horizontal padding (header + list).
  /// Use when the parent already provides edge spacing (e.g. inside Padding(16)).
  final bool inset;

  /// Vertical viewport alignment when this hub is focused.
  final double focusScrollAlignment;

  const HubSection({
    super.key,
    required this.hub,
    required this.icon,
    this.onRefresh,
    this.onRemoveFromContinueWatching,
    this.isInContinueWatching = false,
    bool? usesContinueWatchingAction,
    this.showServerName = false,
    this.loadMoreItems,
    this.onFocusedItemChanged,
    this.onVerticalNavigation,
    this.onBack,
    this.onNavigateUp,
    this.onNavigateToSidebar,
    this.inset = false,
    this.focusScrollAlignment = 0.3,
  }) : usesContinueWatchingAction = usesContinueWatchingAction ?? isInContinueWatching;

  @override
  State<HubSection> createState() => HubSectionState();
}

class HubSectionState extends State<HubSection> with MountedSetStateMixin {
  static const _longPressDuration = Duration(milliseconds: 500);

  /// Episode cards are wider than poster cards by this much.
  static const double _wideCardMultiplier = 1.5;

  /// Added to the poster height to get the full card block on phone/tablet:
  /// the title and metadata labels under the artwork, the card's own padding,
  /// the focus ring the list reserves so a focused card isn't clipped, and 4
  /// of slack. The label block comes from [MediaCardGridLayout] rather than a
  /// number copied from the card, which is how the two used to drift.
  static double _cardBlockExtra(BuildContext context) =>
      MediaCardGridLayout.textExtentFor(context) + FocusTheme.focusBorderWidth * 2 + 4;

  /// The icon + title row above the cards, including both of its paddings.
  ///
  /// Fixed rather than measured: it is a single line of [titleLarge] with
  /// `maxLines: 1`, so it cannot grow. The value comes from a device
  /// screenshot (a 402pt-wide phone put it at 38.5–41.5pt, depending on the
  /// status bar inset assumed); the same measurement confirmed the artwork
  /// height below to the tenth of a point, so only this term carries any
  /// slack. Rounding up is the safe direction: a couple of points too much
  /// leaves a sliver of the next rail showing, too little clips the card
  /// labels.
  static const double _headerHeight = 41;

  /// Artwork height for one card in a phone/tablet rail [availableWidth] wide.
  ///
  /// Episode rails are 16:9 and therefore much shorter than the 2:3 poster
  /// rails, which is why callers have to say which kind they mean.
  static double posterHeightFor(BuildContext context, double availableWidth, {required bool wideLayout}) {
    final density = SettingsService.instanceOrNull?.read(SettingsService.libraryDensity) ?? LibraryDensity.defaultValue;
    final baseCardWidth = GridSizeCalculator.getCellWidth(availableWidth, context, density);
    final cardWidth = wideLayout ? baseCardWidth * _wideCardMultiplier : baseCardWidth;
    final posterWidth = MediaCardGridLayout.posterWidthFor(cardWidth);
    return wideLayout ? posterWidth * (9 / 16) : posterWidth * 1.5;
  }

  /// Total height one phone/tablet rail occupies: header, artwork and labels.
  ///
  /// The home hero sizes itself against this so the first rail lands exactly
  /// at the fold instead of a fraction of the screen that happens to look
  /// right on one device. It lives here, next to the layout it describes, and
  /// [build] uses the same constants — otherwise the two drift apart the first
  /// time a card size changes and the hero silently starts cropping the rail.
  static double railHeight(BuildContext context, double availableWidth, {required bool wideLayout}) =>
      _headerHeight + posterHeightFor(context, availableWidth, wideLayout: wideLayout) + _cardBlockExtra(context);

  late FocusNode _hubFocusNode;
  final ScrollController _scrollController = ScrollController();

  /// Current visual focus index (not tied to Flutter's focus system)
  int _focusedIndex = 0;

  /// What the cursor points at, as an identity rather than a slot.
  ///
  /// The index alone cannot survive a refresh: rows reload in place, and an
  /// item can move or drop out between the frame the user looked at and the
  /// moment they press. This is the source of truth for activation; the index
  /// stays in charge of painting and scrolling.
  HubFocusTarget _focusTarget = const HubFocusNone();

  double _itemExtent = 0;
  bool _headerHovering = false;
  double _leadingPaddingFor(bool isTv) => widget.inset
      ? 0.0
      : isTv
      ? TvLayoutConstants.shelfHorizontalInset
      : 12.0;
  double get _leadingPadding => _leadingPaddingFor(PlatformDetector.isTV());

  Timer? _longPressTimer;
  bool _isSelectKeyDown = false;
  bool _longPressTriggered = false;

  @override
  void initState() {
    super.initState();
    _hubFocusNode = FocusNode(debugLabel: 'hub_${widget.hub.id}');
    _hubFocusNode.addListener(_onFocusChange);
  }

  /// Total item count including the optional "View All" card
  int get _totalItemCount => widget.hub.items.length + (widget.hub.more ? 1 : 0);

  @override
  void didUpdateWidget(HubSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hub.id != oldWidget.hub.id) {
      _itemKeys.clear();
      _mediaCardKeys.clear();
    } else if (widget.hub.items.length != oldWidget.hub.items.length || widget.hub.more != oldWidget.hub.more) {
      _itemKeys.removeWhere((index, _) => index >= _totalItemCount);
      _mediaCardKeys.removeWhere((index, _) => index >= widget.hub.items.length);
    }

    // Rows refresh in place, and refreshing can reorder: finishing an episode
    // moves that title to the front of Continue Watching while the list stays
    // exactly as long. Length-only bookkeeping sees nothing, so the cursor
    // silently ends up on whatever slid into its slot — which is how "open
    // another series" replays the one you just watched. Follow the item.
    _followFocusedItemAcrossUpdate(oldWidget.hub.items);

    if (widget.hub.items.length != oldWidget.hub.items.length || widget.hub.more != oldWidget.hub.more) {
      final maxIndex = _totalItemCount == 0 ? 0 : _totalItemCount - 1;
      if (_focusedIndex > maxIndex) {
        _focusedIndex = maxIndex;
      }
    }

    // `hub.more` comes off the server on every refresh, so the trailing card can
    // disappear while the cursor is on it. The clamp above then moves the index
    // onto the last real card, which is what the user sees highlighted, while
    // the target still says "View All". Activation resolves that to `none` and
    // returns without re-pointing, so every following Select would be a no-op
    // until the user pressed left or right. Nothing was aimed at a title here,
    // so re-pointing costs no protection.
    if (_focusTarget is HubFocusViewAll && !widget.hub.more) {
      _setFocusTarget(_focusedIndex, report: false);
    }
  }

  /// Moves [_focusedIndex] to wherever the item it pointed at ended up.
  ///
  /// Does nothing when the focus sits on the trailing "View All" card, or when
  /// the item is gone — the length clamp in [didUpdateWidget] handles that.
  void _followFocusedItemAcrossUpdate(List<MediaItem> oldItems) {
    if (_focusedIndex < 0 || _focusedIndex >= oldItems.length) return;
    final focusedKey = hubItemIdentity(oldItems[_focusedIndex]);
    final moved = widget.hub.items.indexWhere((item) => hubItemIdentity(item) == focusedKey);
    final occupant = _focusedIndex < widget.hub.items.length
        ? hubItemIdentity(widget.hub.items[_focusedIndex])
        : 'none';
    if (moved < 0) {
      // The cursor and the item it stood on have come apart. Activation refuses
      // to guess from here (see [_resolveActivation]); this line says why.
      if (_hubFocusNode.hasFocus) {
        appLogger.w(
          'Hub focus lost its item across a refresh: hub=${widget.hub.id} index=$_focusedIndex '
          'was=$focusedKey occupant=$occupant items=${widget.hub.items.length}',
        );
      }
      _reportFocusedTargetChange(was: focusedKey, occupant: occupant, disposition: SelectTraceDisposition.removed);
      return;
    }
    if (moved == _focusedIndex) return;
    // Another item took the old slot, but the cursor follows the identity right
    // below, so this row corrects itself: benign, and only worth a timeline
    // line. A row that does *not* correct itself reports `replaced` instead.
    _reportFocusedTargetChange(was: focusedKey, occupant: occupant, disposition: SelectTraceDisposition.moved);
    _focusedIndex = moved;
    _rememberFocus(moved);
    _notifyFocusedItemChanged();
  }

  void _reportFocusedTargetChange({
    required String was,
    required String occupant,
    required SelectTraceDisposition disposition,
  }) {
    // Every row rebuilds on every refresh, and `_focusedIndex` defaults to 0, so
    // without this guard a background hub nobody is looking at would report a
    // change and mark somebody else's press abnormal.
    if (!_hubFocusNode.hasFocus) return;
    SelectTraceRecorder.instance.noteFocusedTargetChanged(
      surface: 'hub-section',
      hubId: widget.hub.id,
      index: _focusedIndex,
      was: was,
      occupant: occupant,
      disposition: disposition,
    );
  }

  /// Points [_focusTarget] at whatever sits at [index] right now.
  ///
  /// Called from every deliberate focus move, and from the recovery path after
  /// a dropped activation: re-pointing is what keeps a single stale item from
  /// blocking every following press.
  /// Set [report] to false for a mechanical re-point, where the cursor did not
  /// move because the user asked it to. Telling the trace recorder about those
  /// would overwrite the aim it is meant to remember.
  void _setFocusTarget(int index, {bool report = true}) {
    final items = widget.hub.items;
    if (index >= 0 && index < items.length) {
      _focusTarget = HubFocusItem(hubItemIdentity(items[index]));
      if (report) {
        SelectTraceRecorder.instance.noteFocus(
          surface: 'hub-section',
          hubId: widget.hub.id,
          index: index,
          item: items[index],
        );
      }
    } else if (index == items.length && widget.hub.more) {
      _focusTarget = const HubFocusViewAll();
    } else {
      _focusTarget = const HubFocusNone();
    }
  }

  String _describeTarget(HubFocusTarget target) => switch (target) {
    HubFocusItem(:final identity) => identity,
    HubFocusViewAll() => 'view-all',
    HubFocusNone() => 'none',
  };

  /// Resolves one activation and records what it landed on.
  ///
  /// Every key-driven entry point goes through here, so "select" and the
  /// context menu can never disagree about the target, and so there is exactly
  /// one line in the log per user action that resolved to something.
  HubActivation _resolveActivation(String action, {String? traceId}) {
    final items = widget.hub.items;
    final activation = resolveHubActivation(
      items: items,
      hasMore: widget.hub.more,
      focusedIndex: _focusedIndex,
      target: _focusTarget,
    );

    if (activation.strategy == HubActivationStrategy.staleDropped) {
      final occupant = _focusedIndex >= 0 && _focusedIndex < items.length
          ? hubItemIdentity(items[_focusedIndex])
          : 'none';
      appLogger.w(
        'Hub activation dropped, focused item gone after refresh: '
        'action=$action hub=${widget.hub.id} index=$_focusedIndex '
        'requested=${_describeTarget(_focusTarget)} occupant=$occupant items=${items.length}',
      );
      final recorder = SelectTraceRecorder.instance;
      recorder.noteActivationDropped(
        traceId,
        detail:
            'activation_dropped hub=${widget.hub.id} index=$_focusedIndex '
            'requested=${_describeTarget(_focusTarget)} occupant=$occupant',
      );
      recorder.close(traceId, SelectTraceOutcome.dropped);
      // Re-point at what is actually on screen. Without this the row would
      // refuse every following press for as long as the stale identity is held.
      //
      // Yes, that means the *second* press opens the card that took the slot.
      // That is the trade, not an oversight: the first press was aimed at a
      // title that no longer exists and is refused, and by the time a second
      // press arrives the user has been looking at the replacement. Re-pointing
      // straight away in [_followFocusedItemAcrossUpdate] instead would open the
      // replacement on the very press that was aimed at the old card, which is
      // the reported bug. `test/widgets/hub_section_activation_test.dart` pins
      // both halves.
      //
      // Not reported as a focus move: the recorder must keep the aim the user
      // actually had, so the next press still shows up as selected != activated.
      _setFocusTarget(_focusedIndex, report: false);
      return activation;
    }

    final item = activation.item;
    if (item != null) {
      // Debug, not info: this carries a media title, it fires on every platform
      // including desktop and mobile, and on TV the select trace already says
      // the same thing with the rest of the chain attached. Turn on debug
      // logging before reproducing and it comes back.
      appLogger.d(
        'Hub activation: action=$action hub=${widget.hub.id} index=${activation.index} '
        'requested=${_describeTarget(_focusTarget)} resolved=${hubItemIdentity(item)} '
        'title="${item.title}" backend=${item.backend.id} server=${item.serverId ?? 'none'} '
        'itemId=${item.id} strategy=${activation.strategy.name}',
      );
    }
    return activation;
  }

  /// Stores the focused position together with the item sitting there, so a
  /// later restore can go back to the item rather than to the slot.
  void _rememberFocus(int index) {
    HubFocusMemory.setForHub(
      widget.hub.id,
      index,
      itemKey: index >= 0 && index < widget.hub.items.length ? widget.hub.items[index].globalKey : null,
    );
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _hubFocusNode.removeListener(_onFocusChange);
    _hubFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // Reset long press state when focus is lost
    if (!_hubFocusNode.hasFocus) {
      _longPressTimer?.cancel();
      _isSelectKeyDown = false;
      _longPressTriggered = false;
    } else {
      _notifyFocusedItemChanged();
    }
    // ignore: no-empty-block - setState triggers rebuild to update focus styling
    setStateIfMounted(() {});
  }

  /// Request focus on this hub at a specific item index
  void requestFocusAt(int index) {
    if (_totalItemCount == 0) return;

    final clamped = index.clamp(0, _totalItemCount - 1).toInt();
    _focusedIndex = clamped;
    _setFocusTarget(clamped);
    // Remember this position for this specific hub
    _rememberFocus(clamped);
    _notifyFocusedItemChanged();
    _scrollToIndex(clamped);
    _hubFocusNode.requestFocus();
    // ignore: no-empty-block - setState triggers rebuild to update focus styling
    setStateIfMounted(() {});

    _scrollHubIntoView();
  }

  /// Request focus using the stored memory for this hub.
  ///
  /// Prefers the remembered *item* over the remembered slot: the row may have
  /// reordered while focus was elsewhere, and coming back to a position is how
  /// you end up on a title you never picked. Falls back to the index when the
  /// hub has no identity memory or the item has dropped out of the list.
  void requestFocusFromMemory() {
    final byItem = HubFocusMemory.rememberedItemIndex(widget.hub.id, [
      for (final item in widget.hub.items) item.globalKey,
    ]);
    requestFocusAt(byItem ?? HubFocusMemory.getForHub(widget.hub.id, _totalItemCount));
  }

  /// Scroll this hub into view in the parent scroll view
  void _scrollHubIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: widget.focusScrollAlignment,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Check if this hub currently has focus
  bool get hasFocusedItem => _hubFocusNode.hasFocus;

  /// Get the number of items in this hub
  int get itemCount => _totalItemCount;

  /// Scroll to center the item at the given index
  void _scrollToIndex(int index, {bool animate = true}) {
    scrollListToIndex(
      _scrollController,
      index,
      itemExtent: _itemExtent,
      leadingPadding: _leadingPadding,
      animate: animate,
    );
    if (index >= 0 && index < _totalItemCount) {
      scrollKeyedChildToHorizontalCenter(
        _scrollController,
        _itemKeyFor(index),
        animate: animate,
        isCurrent: () => _focusedIndex == index && index < _totalItemCount,
      );
    }
  }

  /// Handle ALL key events at the hub level
  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;

    if (key.isSelectKey) {
      if (event is KeyDownEvent) {
        if (!_isSelectKeyDown) {
          _isSelectKeyDown = true;
          _longPressTriggered = false;
          _longPressTimer?.cancel();
          _longPressTimer = Timer(_longPressDuration, () {
            if (!mounted) return;
            if (_isSelectKeyDown) {
              _longPressTriggered = true;
              SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
              _showContextMenuForCurrentItem();
            }
          });
        }
        return KeyEventResult.handled;
      } else if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        final timerWasActive = _longPressTimer?.isActive ?? false;
        _longPressTimer?.cancel();
        if (!_longPressTriggered && timerWasActive && _isSelectKeyDown) {
          _activateCurrentItem();
        }
        _isSelectKeyDown = false;
        _longPressTriggered = false;
        return KeyEventResult.handled;
      }
    }

    if (widget.onBack != null) {
      final backResult = handleBackKeyAction(event, widget.onBack!);
      if (backResult != KeyEventResult.ignored) {
        return backResult;
      }
    }

    // Handle key down and repeat events
    if (!event.isActionable) {
      return KeyEventResult.ignored;
    }

    final totalCount = _totalItemCount;
    if (totalCount == 0) return KeyEventResult.ignored;

    // Left: move to previous item, or navigate to sidebar at left edge
    if (key.isLeftKey) {
      if (_focusedIndex > 0) {
        setState(() {
          _focusedIndex--;
          _setFocusTarget(_focusedIndex);
        });
        _rememberFocus(_focusedIndex);
        _notifyFocusedItemChanged();
        _scrollToIndex(_focusedIndex);
      } else if (widget.onNavigateToSidebar != null) {
        // At leftmost item: navigate to sidebar
        widget.onNavigateToSidebar!();
      }
      // Always consume to prevent focus escape
      return KeyEventResult.handled;
    }

    // Right: move to next item, ALWAYS consume to prevent escape
    if (key.isRightKey) {
      if (_focusedIndex < totalCount - 1) {
        setState(() {
          _focusedIndex++;
          _setFocusTarget(_focusedIndex);
        });
        _rememberFocus(_focusedIndex);
        _notifyFocusedItemChanged();
        _scrollToIndex(_focusedIndex);
      }
      return KeyEventResult.handled;
    }

    // Up/Down: delegate to parent for vertical hub navigation, ALWAYS consume
    if (key.isUpKey) {
      final handled = widget.onVerticalNavigation?.call(true) ?? false;
      // If not handled (at top boundary) and we have onNavigateUp, call it
      if (!handled && widget.onNavigateUp != null) {
        widget.onNavigateUp!();
      }
      return KeyEventResult.handled;
    }
    if (key.isDownKey) {
      widget.onVerticalNavigation?.call(false);
      return KeyEventResult.handled;
    }

    // Context menu key: show context menu
    if (key.isContextMenuKey) {
      _showContextMenuForCurrentItem();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// GlobalKeys for MediaCards to access their state (for context menu)
  final Map<int, GlobalKey> _itemKeys = {};
  final Map<int, GlobalKey<MediaCardState>> _mediaCardKeys = {};

  GlobalKey _itemKeyFor(int index) {
    return _itemKeys.putIfAbsent(index, () => GlobalKey());
  }

  GlobalKey<MediaCardState> _getMediaCardKey(int index) {
    return _mediaCardKeys.putIfAbsent(index, () => GlobalKey<MediaCardState>());
  }

  void _notifyFocusedItemChanged() {
    if (_focusedIndex < 0 || _focusedIndex >= widget.hub.items.length) return;
    widget.onFocusedItemChanged?.call(widget.hub.items[_focusedIndex]);
  }

  void _activateCurrentItem() {
    // Read once, synchronously, at the moment of activation. From here the id
    // travels as a parameter; asking the recorder again after any await would
    // pick up whatever press is open by then.
    final recorder = SelectTraceRecorder.instance;
    final traceId = recorder.consumeActiveSelectTrace() ?? recorder.beginSelect(source: 'hub-section-fallback');
    final activation = _resolveActivation('select', traceId: traceId);
    if (activation.strategy == HubActivationStrategy.viewAll) {
      recorder.close(traceId, SelectTraceOutcome.hubDetail);
      _navigateToHubDetail(context);
      return;
    }
    final item = activation.item;
    if (item == null) {
      recorder.close(traceId, SelectTraceOutcome.none);
      // Recovery, same reason as the stale-drop branch: a target that resolves
      // to nothing must not leave the row unable to act on a following press.
      if (activation.strategy == HubActivationStrategy.none) {
        _setFocusTarget(_focusedIndex, report: false);
      }
      return;
    }
    recorder.link(traceId, SelectTraceLink.activatedTarget, item, note: 'strategy=${activation.strategy.name}');
    recorder.link(traceId, SelectTraceLink.expectedNavigationTarget, mediaDetailNavigationTargetFor(item).metadata);
    _navigateToItem(item, traceId: traceId);
  }

  void _showContextMenuForCurrentItem() {
    // Same resolution as select, so the menu can never belong to a different
    // card than the one an activation would have opened. No menu for "View All".
    final recorder = SelectTraceRecorder.instance;
    final traceId = recorder.consumeActiveSelectTrace();
    final activation = _resolveActivation('context-menu', traceId: traceId);
    if (!activation.opensItem) {
      recorder.close(traceId, SelectTraceOutcome.none);
      return;
    }
    recorder.close(traceId, SelectTraceOutcome.contextMenu);
    _mediaCardKeys[activation.index]?.currentState?.showContextMenu();
  }

  Future<void> _navigateToItem(MediaItem item, {String? traceId}) async {
    await navigateToMediaItem(
      context,
      item,
      onRefresh: widget.onRefresh,
      playDirectly: widget.usesContinueWatchingAction,
      traceId: traceId,
    );
  }

  void _navigateToHubDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HubDetailScreen(
          hub: widget.hub,
          loadItems: widget.loadMoreItems,
          isInContinueWatching: widget.isInContinueWatching,
          usesContinueWatchingAction: widget.usesContinueWatchingAction,
          onRemoveFromContinueWatching: widget.onRemoveFromContinueWatching,
        ),
      ),
    );
  }

  double _getTvCardWidth(double availableWidth, int density, double leadingPadding) {
    final f = LibraryDensity.factor(density);
    final targetCards = 7.0 - (f * 2.0);
    final usableWidth = (availableWidth - (leadingPadding * 2)).clamp(1.0, double.infinity);
    return (usableWidth / targetCards).clamp(210.0, 340.0);
  }

  @override
  Widget build(BuildContext context) {
    final hasFocus = _hubFocusNode.hasFocus;
    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);
    final isTv = PlatformDetector.isTV();
    final leadingPadding = _leadingPaddingFor(isTv);
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontSize: isTv ? 26 : null, fontWeight: isTv ? FontWeight.w700 : null);

    return Padding(
      padding: .only(bottom: isTv && !widget.inset ? TvLayoutConstants.shelfVerticalGap : 0),
      child: Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: [
          // Hub header (NOT focusable - titles should not be focusable)
          Padding(
            padding: widget.inset
                ? EdgeInsets.symmetric(vertical: isTv ? 6 : 2)
                : EdgeInsets.fromLTRB(leadingPadding - 4, isTv ? 6 : 2, 8, isTv ? 8 : 2),
            child: ExcludeFocus(
              child: MouseRegion(
                onEnter: (_) => setState(() => _headerHovering = true),
                onExit: (_) => setState(() => _headerHovering = false),
                child: InkWell(
                  mouseCursor: widget.hub.more ? SystemMouseCursors.click : MouseCursor.defer,
                  onTap: widget.hub.more ? () => _navigateToHubDetail(context) : null,
                  borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                  child: Padding(
                    padding: widget.inset
                        ? const EdgeInsets.symmetric(vertical: 2)
                        : const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        AppIcon(widget.icon, fill: 1, size: isTv ? 28 : null),
                        SizedBox(width: isTv ? 12 : 8),
                        Flexible(
                          child: Text(widget.hub.title, style: titleStyle, overflow: .ellipsis, maxLines: 1),
                        ),
                        if (widget.showServerName && widget.hub.serverName != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.hub.serverName!,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                        if (widget.hub.more && !isKeyboardMode) ...[
                          const SizedBox(width: 6),
                          // Netflix "Explore all >" — text reveals on hover (desktop),
                          // chevron always shows on TV.
                          if (!isTv)
                            AnimatedOpacity(
                              opacity: _headerHovering ? 1 : 0,
                              duration: tokens(context).fast,
                              child: Text(
                                t.common.viewAll,
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF54B9C5),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          AppIcon(Symbols.chevron_right_rounded, fill: 1, size: isTv ? 26 : 18),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (widget.hub.items.isNotEmpty)
            Focus(
              focusNode: _hubFocusNode,
              onKeyEvent: _handleKeyEvent,
              child: SettingsBuilder(
                prefs: const [SettingsService.libraryDensity, SettingsService.episodePosterMode],
                builder: (context) => LayoutBuilder(
                  builder: (context, constraints) {
                    final svc = SettingsService.instanceOrNull;
                    if (svc == null) return const SizedBox.shrink();
                    final density = svc.read(SettingsService.libraryDensity);
                    final baseCardWidth = isTv
                        ? _getTvCardWidth(constraints.maxWidth, density, leadingPadding)
                        : GridSizeCalculator.getCellWidth(constraints.maxWidth, context, density);

                    final episodePosterMode = svc.read(SettingsService.episodePosterMode);

                    final hasEpisodes = widget.hub.items.any((item) => item.usesWideAspectRatio(episodePosterMode));
                    final hasNonEpisodes = widget.hub.items.any((item) => !item.usesWideAspectRatio(episodePosterMode));

                    final isMixedHub = hasEpisodes && hasNonEpisodes;

                    final isEpisodeOnlyHub = hasEpisodes && !hasNonEpisodes;

                    // Use 16:9 for episode-only hubs OR mixed hubs (with episode thumbnail mode)
                    final useWideLayout =
                        episodePosterMode == EpisodePosterMode.episodeThumbnail && (isEpisodeOnlyHub || isMixedHub);

                    // Card dimensions based on hub type
                    final cardWidth = useWideLayout ? baseCardWidth * _wideCardMultiplier : baseCardWidth;
                    final posterWidth = MediaCardGridLayout.posterWidthFor(cardWidth);
                    final posterHeight = useWideLayout
                        ? posterWidth *
                              (9 / 16) // 16:9 for wide layout
                        : posterWidth * 1.5; // 2:3 for poster layout

                    final containerHeight = posterHeight + (isTv ? 48 : 33);
                    final focusBorderWidth = FocusTheme.focusBorderWidth;
                    // A focused card scales up and draws its ring *outside* its
                    // box, while the ListView paints item i+1 over item i. Too
                    // small a gap and the next card covers the focused card's
                    // ring, so size the gap to the actual overflow rather than
                    // a fixed 2px: half the scale growth, plus the ring.
                    final focusGrowX = cardWidth * (FocusTheme.focusScale - 1) / 2;
                    final focusGrowY = posterHeight * (FocusTheme.focusScale - 1) / 2;
                    final itemGap = isTv ? focusGrowX + focusBorderWidth : 2.0;
                    _itemExtent = cardWidth + itemGap * 2;

                    return SizedBox(
                      // Non-TV goes through [_cardBlockExtra] so [railHeight]
                      // — which the home hero measures itself against — can
                      // never disagree with what is actually laid out here.
                      height: isTv
                          ? containerHeight + (focusGrowY + focusBorderWidth) * 2
                          : posterHeight + _cardBlockExtra(context),
                      child: HorizontalScrollWithArrows(
                        controller: _scrollController,
                        builder: (scrollController) => ListView.builder(
                          controller: scrollController,
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          padding: widget.inset
                              ? EdgeInsets.symmetric(vertical: isTv ? 6 : 2)
                              : EdgeInsets.symmetric(horizontal: isTv ? leadingPadding : 8, vertical: isTv ? 6 : 2),
                          itemCount: isKeyboardMode ? _totalItemCount : widget.hub.items.length,
                          itemBuilder: (context, index) {
                            final isItemFocused = hasFocus && index == _focusedIndex;

                            if (index == widget.hub.items.length) {
                              return Padding(
                                key: _itemKeyFor(index),
                                padding: widget.inset
                                    ? EdgeInsets.only(right: itemGap * 2)
                                    : EdgeInsets.symmetric(horizontal: itemGap),
                                child: FocusBuilders.buildLockedFocusWrapper(
                                  context: context,
                                  isFocused: isItemFocused,
                                  onTap: () {
                                    _onItemTapped(index);
                                    _navigateToHubDetail(context);
                                  },
                                  child: SizedBox(
                                    width: isTv ? 118 : 80,
                                    height: containerHeight - 10,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: .min,
                                        children: [
                                          Icon(
                                            Symbols.arrow_forward_rounded,
                                            size: isTv ? 42 : 32,
                                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            t.common.viewAll,
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                              fontSize: isTv ? 16 : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final item = widget.hub.items[index];

                            return Padding(
                              key: _itemKeyFor(index),
                              padding: widget.inset
                                  ? EdgeInsets.only(right: itemGap * 2)
                                  : EdgeInsets.symmetric(horizontal: itemGap),
                              child: FocusBuilders.buildLockedFocusWrapper(
                                context: context,
                                isFocused: isItemFocused,
                                onTap: () => _onItemTapped(index),
                                onLongPress: () => _mediaCardKeys[index]?.currentState?.showContextMenu(),
                                delegateFocusBorder: true,
                                child: MediaCard(
                                  key: _getMediaCardKey(index),
                                  item: item,
                                  width: cardWidth,
                                  height: posterHeight,
                                  onRefresh: widget.onRefresh,
                                  onRemoveFromContinueWatching: widget.onRemoveFromContinueWatching,
                                  forceGridMode: true,
                                  isInContinueWatching: widget.isInContinueWatching,
                                  usesContinueWatchingAction: widget.usesContinueWatchingAction,
                                  mixedHubContext: isMixedHub,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          else
            Padding(
              padding: widget.inset
                  ? const EdgeInsets.symmetric(vertical: 8)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                t.messages.noItemsAvailable,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  void _onItemTapped(int index) {
    if (_totalItemCount == 0) return;
    final clamped = index.clamp(0, _totalItemCount - 1).toInt();
    setState(() {
      _focusedIndex = clamped;
      _setFocusTarget(clamped);
    });
    _rememberFocus(clamped);
    _notifyFocusedItemChanged();
    _scrollToIndex(clamped);
    _hubFocusNode.requestFocus();
  }
}
