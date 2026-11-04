/// The horizontal root navigation of the TV shell (fase 7).
///
/// Replaces [SideNavigationRail] as the TV root, and only there — desktop keeps
/// the rail, mobile keeps its bottom bar (hoofdstuk 6.1). The composition is
/// the frozen north star's shared shell: a profile chip alone at the far left,
/// the search glyph and the labelled destinations as one horizontally centred
/// cluster, and the Pleya wordmark lockup at the far right.
///
/// Apple TV uses one moving GlassSurface selector for focus, resting on the
/// active destination when content owns focus (NAV-GLASS1). Other TV platforms
/// retain their existing active-pill and focus-ring presentation.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pleya_wordmark.dart';

import '../../focus/focus_memory_tracker.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../automation/automation_ids.dart';
import '../../navigation/tv/tv_destination.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_avatar.dart';
import '../../services/settings_service.dart';
import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_surface.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import 'tv_reconnect_item.dart';
import 'tv_top_nav_item.dart';
import 'tv_unified_layout.dart';

class TvTopNavigation extends StatefulWidget {
  const TvTopNavigation({
    super.key,
    required this.destinations,
    required this.active,
    required this.nodes,
    required this.onSelect,
    required this.onFocusDestination,
    this.needsAttention = false,
    required this.onNavigateDown,
    required this.onOpenProfiles,
    this.dimmed = false,
    this.profile,
    this.isOfflineMode = false,
    this.isReconnecting = false,
    this.onReconnect,
  });

  /// Left to right, as [buildTvDestinations] ordered them.
  final List<TvDestinationId> destinations;

  /// The destination whose content is on screen; the selector rests here.
  final TvDestinationId active;

  /// Focus nodes keyed by [TvDestinationId.focusKey], owned by the shell so a
  /// rebuild of this bar cannot drop the focus it is holding.
  final FocusMemoryTracker nodes;

  final ValueChanged<TvDestinationId> onSelect;

  /// Reports a focus preview separately from Select. The existing host owns
  /// explicit activation on every TV platform (A-24c).
  final ValueChanged<TvDestinationId> onFocusDestination;

  /// Whether something under Instellingen is waiting on the user — today, a
  /// server whose token was rejected.
  ///
  /// Deliberately one boolean and not a count or a list. Hoofdstuk 18.4 allows
  /// "een klein statuspunt" on the destination that resolves it and forbids
  /// "een permanente grote rode melding over content"; a number on the bar
  /// would start down the road the second half rules out, and the concrete
  /// servers already have a place to be named — the Servers screen this
  /// destination leads to (Instellingen ▸ Koppelingen ▸ Servers since A-24c;
  /// before that it rode Mijn Pleya, which no longer has a Servers tile).
  final bool needsAttention;

  /// Down from any bar item goes into the current destination's content
  /// (hoofdstuk 7.2).
  final VoidCallback onNavigateDown;

  /// Select on the profile avatar. Since A-24c that opens the small account
  /// menu (Wissel profiel, Uitloggen; northstar `A14-profiel-acties.png`)
  /// rather than the profile picker itself; the name stays because the shell
  /// and two dozen harnesses already pass it, and the menu's first action is
  /// still the profile picker.
  final VoidCallback onOpenProfiles;

  /// Fades the bar to [TvTopNavLayout.dimmedOpacity] while an overlay is open
  /// above the page (styling audit, divergentie 13; mockup 30 E). The nodes
  /// stay in the tree: the overlay owns the focus, and the bar comes back
  /// exactly where it was when it closes.
  final bool dimmed;

  final Profile? profile;

  /// Whether the shell is currently rendering offline mode (PB-12, OFF-1).
  ///
  /// Mirrors [SideNavigationRail.isOfflineMode]: TV had the same offline
  /// state as desktop and mobile but no affordance to act on it — the rail
  /// and the mobile bottom bar both grew a reconnect control, the bar never
  /// did.
  final bool isOfflineMode;

  /// Mirrors [SideNavigationRail.isReconnecting].
  final bool isReconnecting;

  /// Null hides the reconnect item even when [isOfflineMode] is true, same
  /// contract as the rail's `onReconnect`.
  final VoidCallback? onReconnect;

  @override
  State<TvTopNavigation> createState() => _TvTopNavigationState();
}

class _TvTopNavigationState extends State<TvTopNavigation> with WidgetsBindingObserver {
  static const _accessibility = MethodChannel('pleya/tvos_nav_accessibility');
  final _clusterKey = GlobalKey();
  final _itemKeys = <TvDestinationId, GlobalKey>{};
  Rect? _selectorRect;
  TvDestinationId? _selectorDestination;
  bool _layoutScheduled = false;
  // Conservative until UIKit answers; transparency is not a Flutter feature bit.
  bool _reduceTransparency = true;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleSelectorFocusChanged);
    if (PlatformDetector.isAppleTV()) {
      WidgetsBinding.instance.addObserver(this);
      _accessibility.setMethodCallHandler((call) async {
        if (call.method == 'reduceTransparencyChanged' && mounted) {
          setState(() => _reduceTransparency = call.arguments == true);
        }
      });
      unawaited(_readTransparency());
    }
  }

  Future<void> _readTransparency() async {
    try {
      final reduced = await _accessibility.invokeMethod<bool>('reduceTransparency') ?? true;
      if (mounted) setState(() => _reduceTransparency = reduced);
    } on MissingPluginException {
      // A bare Flutter test or an older host keeps the opaque fallback.
    } on PlatformException {
      // Keep the clear, opaque selector if UIKit cannot report the setting.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_readTransparency());
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleSelectorFocusChanged);
    if (PlatformDetector.isAppleTV()) {
      WidgetsBinding.instance.removeObserver(this);
      _accessibility.setMethodCallHandler(null);
    }
    super.dispose();
  }

  void _handleSelectorFocusChanged() {
    if (!mounted || !PlatformDetector.isAppleTV()) return;
    // Focus notifications precede paint. Hide the tab capsule in that frame,
    // before the separate profile/reconnect control can paint its own ring.
    if ((widget.nodes.nodeFor(tvNavProfileFocusKey)?.hasFocus ?? false) ||
        (widget.nodes.nodeFor(tvReconnectFocusKey)?.hasFocus ?? false)) {
      if (_selectorRect != null) {
        setState(() {
          _selectorRect = null;
          _selectorDestination = null;
        });
      }
    }
    _scheduleSelectorLayout();
  }

  void _scheduleSelectorLayout() {
    if (!PlatformDetector.isAppleTV() || _layoutScheduled) return;
    _layoutScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (!mounted) return;
      _itemKeys.removeWhere((id, _) => !widget.destinations.contains(id));
      final focused = widget.destinations.where((id) => widget.nodes.nodeFor(id.focusKey)?.hasFocus ?? false);
      // Profile/reconnect keep their own control focus treatment. Do not leave
      // a second tab selector visible beside that indicator.
      final controlFocused =
          (widget.nodes.nodeFor(tvNavProfileFocusKey)?.hasFocus ?? false) ||
          (widget.nodes.nodeFor(tvReconnectFocusKey)?.hasFocus ?? false);
      if (controlFocused) {
        if (_selectorRect != null) {
          setState(() {
            _selectorRect = null;
            _selectorDestination = null;
          });
        }
        return;
      }
      final target = focused.firstOrNull ?? widget.active;
      final cluster = _clusterKey.currentContext?.findRenderObject();
      final item = _itemKeys[target]?.currentContext?.findRenderObject();
      if (cluster is! RenderBox || item is! RenderBox || !cluster.hasSize || !item.hasSize) {
        if (_selectorRect != null) setState(() => _selectorRect = null);
        return;
      }
      final inset = FocusTheme.focusBorderWidth + TvTopNavLayout.focusRingGap * TvLayoutConstants.scaleOf(context);
      final rect = (item.localToGlobal(Offset.zero, ancestor: cluster) & item.size).deflate(inset);
      if (_selectorRect != rect || _selectorDestination != target) {
        setState(() {
          _selectorRect = rect;
          _selectorDestination = target;
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Duration _selectorDuration(BuildContext context) =>
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion
      ? Duration.zero
      : reduceMotion(context, TvTopNavLayout.focusDuration);

  Widget _appleTvCluster(BuildContext context, Widget cluster, double scale) {
    _scheduleSelectorLayout();
    final glass = glassTierFor(context) != GlassTier.off && !_reduceTransparency && !MediaQuery.highContrastOf(context);
    final selector = DecoratedBox(
      key: const ValueKey('tv_nav_selector'),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        shadows: glass ? const [BoxShadow(color: Color(0x30000000), blurRadius: 6, offset: Offset(0, 2))] : null,
      ),
      child: GlassSurface(
        shape: const StadiumBorder(),
        backdrop: glass,
        tokens: GlassTokens(
          blur: 12 * scale,
          saturation: 1.12,
          dim: 1,
          tint: glass ? const Color(0x16FFFFFF) : const Color(0xFF50545A),
          edge: glass ? 0.22 : 0.3,
          edgeWidth: 0.65 * scale,
        ),
        legacy: const DecoratedBox(
          decoration: ShapeDecoration(shape: StadiumBorder(), color: Color(0xFF50545A)),
          child: SizedBox.expand(),
        ),
        child: const SizedBox.expand(),
      ),
    );
    final track = Stack(
      key: _clusterKey,
      children: [
        if (_selectorRect case final rect?)
          AnimatedPositioned.fromRect(
            rect: rect,
            duration: _selectorDuration(context),
            curve: Curves.easeOutCubic,
            child: IgnorePointer(child: ExcludeSemantics(child: selector)),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: TvTopNavLayout.glassCapsuleInset * scale),
          child: cluster,
        ),
      ],
    );
    // The plate and moving selector use the existing BackdropFilter material.
    // A dark plate keeps white labels readable even over a white hero in Light.
    return GlassSurface(
      shape: const StadiumBorder(),
      backdrop: glass,
      tokens: GlassTokens(
        blur: 30,
        saturation: 1.2,
        dim: 0.8,
        tint: glass ? const Color(0xC2000000) : const Color(0xFF24272B),
        edge: 0.12,
        edgeWidth: 0.5 * scale,
      ),
      legacy: DecoratedBox(
        decoration: const ShapeDecoration(shape: StadiumBorder(), color: Color(0xFF24272B)),
        child: track,
      ),
      child: track,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The Liquid Glass switch flips the bar live, capsule and pills alike.
    // No service (a bare widget test) reads as glass off, see [glassTierFor].
    final settings = SettingsService.instanceOrNull;
    if (settings == null) return _buildBar(context);
    return ValueListenableBuilder<bool>(
      valueListenable: settings.listenable(SettingsService.liquidGlass),
      builder: (context, _, _) => _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    // Same gate as [NavRailDestination.reconnect]'s `c.isOfflineMode &&
    // c.canReconnect`: a null callback hides the item rather than wiring a
    // dead Select.
    final showReconnect = widget.isOfflineMode && widget.onReconnect != null;

    final cluster = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showReconnect) ...[
          TvReconnectItem(
            node: widget.nodes.get(tvReconnectFocusKey, debugLabel: tvReconnectFocusKey),
            scale: scale,
            isReconnecting: widget.isReconnecting,
            onSelect: widget.onReconnect!,
            onNavigateDown: widget.onNavigateDown,
            onNavigateLeft: () => _focusKey(tvNavProfileFocusKey),
            onNavigateRight: widget.destinations.isEmpty ? null : () => _focus(widget.destinations.first),
          ),
          if (widget.destinations.isNotEmpty)
            SizedBox(key: const ValueKey('reconnect_gap'), width: TvTopNavLayout.itemGap * scale),
        ],
        for (var i = 0; i < widget.destinations.length; i++) ...[
          if (i > 0)
            SizedBox(key: ValueKey('${widget.destinations[i].focusKey}_gap'), width: TvTopNavLayout.itemGap * scale),
          KeyedSubtree(
            key: _itemKeys.putIfAbsent(widget.destinations[i], GlobalKey.new),
            child: TvTopNavItem(
              // Keyed on the destination, not on its position. Without
              // this, a Live TV slot appearing shifts every later child
              // by one and Flutter matches children by position: Mijn
              // Pleya's element is reused for Live TV, the element
              // holding the remote's focus is torn down, and the focus
              // falls out of the bar entirely. Hoofdstuk 7.2's last
              // bullet is precisely this — a new item "vervangt geen
              // focusnode van een bestaand item".
              key: ValueKey(widget.destinations[i].focusKey),
              destination: widget.destinations[i],
              isActive: widget.destinations[i] == widget.active,
              isSelector: widget.destinations[i] == _selectorDestination,
              node: widget.nodes.get(widget.destinations[i].focusKey, debugLabel: widget.destinations[i].focusKey),
              scale: scale,
              // Hoofdstuk 18.4: the dot rides the destination that owns
              // the resolution route, and only that one.
              needsAttention: widget.destinations[i] == TvDestinationId.settings && widget.needsAttention,
              onSelect: () => widget.onSelect(widget.destinations[i]),
              onFocused: () => widget.onFocusDestination(widget.destinations[i]),
              onNavigateDown: widget.onNavigateDown,
              // No wrap at either end (hoofdstuk 7.2). The first item
              // hands Left to the reconnect item when offline shows
              // one, otherwise to the profile chip, the only other
              // thing to its left; the last simply stops.
              onNavigateLeft: i == 0
                  ? () => _focusKey(showReconnect ? tvReconnectFocusKey : tvNavProfileFocusKey)
                  : () => _focus(widget.destinations[i - 1]),
              onNavigateRight: i == widget.destinations.length - 1 ? null : () => _focus(widget.destinations[i + 1]),
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        TvTopNavLayout.pageInset * scale,
        TvTopNavLayout.topInset * scale,
        TvTopNavLayout.pageInset * scale,
        TvTopNavLayout.contentGap * scale,
      ),
      child: AnimatedOpacity(
        opacity: widget.dimmed ? TvTopNavLayout.dimmedOpacity : 1,
        duration: PlatformDetector.isAppleTV() ? _selectorDuration(context) : TvTopNavLayout.focusDuration,
        curve: Curves.easeOut,
        child: ConstrainedBox(
          // A floor, not a ceiling. Pinning the height exactly cost the first
          // render its own pills: the capsule plus its focus-ring gap is slightly
          // taller than the band, and a hard height clipped the labels against
          // the top edge instead of letting the bar grow the few pixels it
          // needed. A long locale with taller metrics would have done the same.
          constraints: BoxConstraints(minHeight: TvTopNavLayout.barHeight * scale),
          // A Stack, not a three-cell Row: hoofdstuk 33 centres the destination
          // cluster on the *screen*, not in the space left over between the
          // profile chip and the wordmark. Those two have different widths, so a
          // Row with a Spacer either side would push the cluster off-centre by
          // half their difference — and the offset would change with the
          // wordmark's locale-independent width against a chip that grows a lock
          // badge. Centring against the full width keeps Home where the eye
          // expects it whatever flanks it.
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _ProfileChip(
                  profile: widget.profile,
                  node: widget.nodes.get(tvNavProfileFocusKey, debugLabel: 'tvNav_profile'),
                  scale: scale,
                  onSelect: widget.onOpenProfiles,
                  onNavigateDown: widget.onNavigateDown,
                  onNavigateRight: showReconnect
                      ? () => _focusKey(tvReconnectFocusKey)
                      : (widget.destinations.isEmpty ? null : () => _focus(widget.destinations.first)),
                ),
              ),
              // LG-04: with glass on, search and the widget.destinations sit in one
              // capsule of fake glass. Glass off returns the bare row.
              if (PlatformDetector.isAppleTV())
                _appleTvCluster(context, cluster, scale)
              else if (glassTierFor(context) == GlassTier.off)
                cluster
              else
                GlassSurface(
                  shape: const StadiumBorder(),
                  tokens: GlassTokens.tvFor(context),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: TvTopNavLayout.glassCapsuleInset * scale),
                    child: cluster,
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                // Not focusable. The wordmark is branding, not a destination:
                // giving it a focus stop would put a dead end at the end of every
                // rightward walk. It is hidden from semantics for the same
                // reason — "Pleya" read out after the last destination tells a
                // VoiceOver user nothing about where they are.
                // The lettering follows the theme ink; the mark keeps its own
                // colours. See [PleyaWordmark] and [DEC-074].
                child: ExcludeSemantics(
                  child: PleyaWordmark(
                    height: TvTopNavLayout.wordmarkHeight * scale,
                    letteringColor: tokens(context).text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _focus(TvDestinationId id) => _focusKey(id.focusKey);

  void _focusKey(String key) {
    final node = widget.nodes.get(key);
    if (node.canRequestFocus) node.requestFocus();
  }
}

/// The profile chip's focus key. Its own constant rather than a
/// [TvDestinationId] value: the chip opens the profile picker on the *root*
/// navigator and never becomes an active destination, so it has no pill state
/// and no tab behind it.
///
/// Public since FOC1: [TvRootShell] prunes [FocusMemoryTracker] against the
/// keys this bar actually renders, and the chip is one of them.
const String tvNavProfileFocusKey = 'tvNav_profile';

/// Every focus key [TvTopNavigation] renders for [destinations], in the order
/// the bar walks them.
///
/// The one place that answers "which nodes does this bar own right now". A
/// second list somewhere else would drift the moment a destination is added,
/// and a pruner working from a stale list disposes a node that is on screen.
///
/// Takes the raw [isOfflineMode]/[onReconnect] inputs rather than a
/// pre-computed `showReconnect`, so the pruner in `tv_root_shell.dart` no
/// longer carries its own copy of `isOfflineMode && onReconnect != null` at
/// the call site. [TvTopNavigation.build] still evaluates that same
/// expression locally for its own render logic (chip visibility, focus-key
/// selection), which this function does not replace.
Set<String> tvTopNavFocusKeys({
  required List<TvDestinationId> destinations,
  required bool isOfflineMode,
  required VoidCallback? onReconnect,
}) => {
  tvNavProfileFocusKey,
  if (isOfflineMode && onReconnect != null) tvReconnectFocusKey,
  for (final destination in destinations) destination.focusKey,
};

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.profile,
    required this.node,
    required this.scale,
    required this.onSelect,
    required this.onNavigateDown,
    required this.onNavigateRight,
  });

  final Profile? profile;
  final FocusNode node;
  final double scale;
  final VoidCallback onSelect;
  final VoidCallback onNavigateDown;
  final VoidCallback? onNavigateRight;

  @override
  Widget build(BuildContext context) {
    final size = TvTopNavLayout.profileChipSize * scale;
    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      // The bar's leftmost focus stop, and therefore part of every walk over
      // it. Without an id the first hop of a leftward walk lands on a
      // `discovered` node the scenario cannot name, and the walk can only
      // count presses instead of stating where they go.
      automationId: AutomationIds.navProfile,
      automationRole: 'nav',
      onNavigateDown: onNavigateDown,
      onNavigateRight: onNavigateRight,
      focusShape: BoxShape.circle,
      disableScale: true,
      // The avatar is an identity, not a label, so what pressing it does is
      // said out loud — the same reasoning as the mobile My Pleya header.
      // A-24c: it opens the account menu, so that is what it is called.
      semanticLabel: t.tvAccountMenu.title,
      child: Padding(
        padding: EdgeInsets.all(TvTopNavLayout.focusRingGap * scale),
        child: ExcludeSemantics(
          child: ProfileAvatar(profile: profile, size: size, showLockBadge: false),
        ),
      ),
    );
  }
}
