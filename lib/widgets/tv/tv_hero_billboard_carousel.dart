/// The fase-8 Home featured carousel (hoofdstuk 9.5/9.6 of
/// docs/tvos-unified-experience.md, north star 33.1): a rounded in-page
/// billboard that rotates over `TvHomeProjectionProvider.heroGroups`.
///
/// ## The one thing this phase exists to change
///
/// **Hero state is not row-focus state.** Until fase 8 the TV Home billboard
/// *was* the focused row item: `TvBrowseRail.onFocusedItemChanged` fed
/// `DiscoverScreen._setSpotlightDebounced`, and moving along a row replaced the
/// hero 180ms later. Hoofdstuk 7.3 and 31.9 forbid that, DEC-066 punt 3 and
/// DEC-067 punt 3 deferred removing it to this phase, and this widget is where
/// it stops being possible rather than merely unused: the active slide is
/// [_index], private state of this carousel, and the only things that move it
/// are its own left/right keys and its own timer. There is no input for "the
/// row focused something", and a content row has no reference to this widget
/// to call one with.
///
/// ## Presentation and activation are two lists that happen to be one
///
/// `heroGroups` decides which slides exist, in what order, and which
/// [UnifiedMediaGroup] each one is (DEC-067). The card renders that group's
/// *representative* source — backdrop, clearlogo, title, runtime — and both
/// CTAs hand the **group** to [onActivate], never the item. So a title on two
/// servers is one slide, and pressing Afspelen on it reaches the fase-4
/// coordinator, which resolves preferred → direct → picker exactly as every
/// other surface does. `Afspelen` and `Meer info` differ only in intent; they
/// share one resolution boundary, and neither has a picker of its own.
///
/// ## Autoplay, and the clause that makes it possible
///
/// Hoofdstuk 9.6 asks for an 8-second rotation, then lists the states that
/// hold the timer paused — among them "een hero-CTA focus heeft". Taken
/// literally that is a carousel that never advances, because a hero CTA is
/// exactly where Home's focus rests (hoofdstuk 7.1: topnav → hero actions).
/// The same paragraph carries its own resolution — "Na echte inactiviteit mag
/// de carousel hervatten" — and that is what is implemented here and recorded
/// in [DEC-070]: every interaction stops the rotation and arms an inactivity
/// window of the same eight seconds; the rotation resumes only after that
/// window passes with no input, and only while [autoplayEnabled] holds. The
/// states 9.6 lists that are *not* about the viewer's hands — Home not
/// active, the app backgrounded, an overlay or picker open, the feed scrolled
/// off the top, a content row holding the focus — are the feed's to report,
/// and it reports them through that one flag.
///
/// Reduced motion switches the rotation off entirely rather than speeding it
/// up or hard-cutting between slides: an automatic change of the largest
/// element on the screen is precisely the motion the setting is asking not to
/// see (hoofdstuk 25, fase-8 brief §24). Manual left/right keeps working.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focus_theme.dart';
import '../../focus/focusable_button.dart';
import '../../focus/focusable_wrapper.dart';
import '../../focus/input_mode_tracker.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_route_context.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../app_icon.dart';
import 'tv_hero_artwork.dart';
import 'tv_hero_billboard_card.dart';
import 'tv_unified_layout.dart';
import 'tv_unified_media_card.dart' show resumeFractionFor;

class TvHeroBillboardCarousel extends StatefulWidget {
  const TvHeroBillboardCarousel({
    super.key,
    required this.groups,
    required this.size,
    required this.onActivate,
    this.clientFor,
    this.autoplayEnabled = true,
    this.textOpacity = 1.0,
    this.hideSpoilers = false,
    this.initialGroupId,
    this.onActiveGroupChanged,
    this.onNavigateDown,
    this.onNavigateUp,
    this.onBack,
  });

  /// `TvHomeProjectionProvider.heroGroups`, already deduplicated, already
  /// ordered by release date, already capped at hoofdstuk 9.5's eight. This
  /// widget selects nothing and pads nothing (DEC-067): if the projection
  /// produced three slides, three is the answer.
  final List<UnifiedMediaGroup> groups;

  /// The card's box, from [TvHomeLayout.heroWidth] / [TvHomeLayout.heroHeight].
  final Size size;

  /// The fase-4 coordinator, passed in rather than reached for, so this widget
  /// stays a presentation surface with no `MultiServerProvider` of its own.
  final void Function(UnifiedMediaGroup group, {required UnifiedActivationIntent intent, required bool playDirectly})
  onActivate;

  final MediaServerClient? Function(String serverId)? clientFor;

  /// Every hoofdstuk 9.6 pause condition the *feed* owns, folded into one flag
  /// — see the library doc for why the CTA-focus condition is not among them.
  final bool autoplayEnabled;

  /// 33.2's faded hero text once a content row holds the focus.
  final double textOpacity;

  final bool hideSpoilers;

  /// Restoration (hoofdstuk 7.6/19): the slide to come back to after a
  /// destination switch. Ignored when that group is no longer in [groups] — a
  /// title that left the recent-films pool cannot be restored, and slide zero
  /// is the honest fallback. **By id, never by index**, so a re-projection that
  /// shortened the row cannot restore the viewer to a different film.
  final String? initialGroupId;

  final ValueChanged<String>? onActiveGroupChanged;

  /// DOWN out of either CTA, into the first content row (hoofdstuk 7.3).
  final VoidCallback? onNavigateDown;

  /// UP out of either CTA, into the active top-navigation destination.
  final VoidCallback? onNavigateUp;

  final VoidCallback? onBack;

  @override
  State<TvHeroBillboardCarousel> createState() => TvHeroBillboardCarouselState();
}

class TvHeroBillboardCarouselState extends State<TvHeroBillboardCarousel> {
  final _playFocus = FocusNode(debugLabel: 'tvHeroPlay');
  final _infoFocus = FocusNode(debugLabel: 'tvHeroMoreInfo');

  int _index = 0;

  /// Rotation timer. Null whenever the carousel is not currently rotating, for
  /// any of the reasons in the library doc.
  Timer? _advance;

  /// The inactivity window 9.6's last sentence buys. Non-null means "the
  /// viewer touched something recently"; it fires once and re-arms [_advance].
  Timer? _idle;

  /// The short segment indicator 9.6 allows during manual navigation, and
  /// forbids as a permanent row of dots.
  Timer? _indicatorHold;
  bool _showIndicator = false;

  /// Which CTA to return to when the viewer comes back up from a row
  /// (hoofdstuk 7.3: "Up vanaf de eerste rij gaat terug naar de laatst
  /// gebruikte hero-CTA").
  bool _lastCtaWasInfo = false;

  @override
  void initState() {
    super.initState();
    _index = _restoredIndex();
  }

  @override
  void didUpdateWidget(TvHeroBillboardCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A re-projection can shorten, lengthen or reorder the slide list under a
    // carousel that is sitting on one of them. Follow the *group*, not the
    // index: hoofdstuk 7.6's "group krijgt een extra bron → geen focussprong"
    // is the same rule one level up, and an index kept across a shortened list
    // silently changes which film the viewer was about to press play on.
    if (!identical(oldWidget.groups, widget.groups)) {
      final wanted = oldWidget.groups.isEmpty || _index >= oldWidget.groups.length
          ? null
          : oldWidget.groups[_index].groupId;
      final moved = wanted == null ? -1 : widget.groups.indexWhere((g) => g.groupId == wanted);
      _index = moved >= 0 ? moved : _restoredIndex();
    }

    if (widget.autoplayEnabled != oldWidget.autoplayEnabled || widget.groups.length != oldWidget.groups.length) {
      _syncAutoplay();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAutoplay();
  }

  @override
  void dispose() {
    _advance?.cancel();
    _idle?.cancel();
    _indicatorHold?.cancel();
    _playFocus.dispose();
    _infoFocus.dispose();
    super.dispose();
  }

  int _restoredIndex() {
    final wanted = widget.initialGroupId;
    if (wanted == null) return 0;
    final found = widget.groups.indexWhere((g) => g.groupId == wanted);
    return found < 0 ? 0 : found;
  }

  /// The slide currently on screen, or `null` for an empty hero.
  UnifiedMediaGroup? get activeGroup =>
      widget.groups.isEmpty ? null : widget.groups[_index.clamp(0, widget.groups.length - 1)];

  /// Puts the focus back on the CTA the viewer last used — hoofdstuk 7.3's
  /// "Up vanaf de eerste rij gaat terug naar de laatst gebruikte hero-CTA".
  /// Reports failure rather than approximating, so the feed can decide what UP
  /// means on a Home with no hero at all.
  bool focusLastCta() {
    final node = _lastCtaWasInfo ? _infoFocus : _playFocus;
    if (!node.canRequestFocus) return false;
    node.requestFocus();
    return true;
  }

  /// DOWN out of the top navigation lands here (hoofdstuk 7.3: "Down vanaf
  /// topnav gaat naar Afspelen/Hervatten").
  bool focusPlay() {
    if (!_playFocus.canRequestFocus) return false;
    _playFocus.requestFocus();
    return true;
  }

  bool get hasFocus => _playFocus.hasFocus || _infoFocus.hasFocus;

  // ---------------------------------------------------------------- autoplay

  bool get _canRotate =>
      widget.autoplayEnabled &&
      widget.groups.length > 1 &&
      mounted &&
      !MediaQuery.disableAnimationsOf(context) &&
      _idle == null;

  void _syncAutoplay() {
    if (!_canRotate) {
      _advance?.cancel();
      _advance = null;
      return;
    }
    _advance ??= Timer.periodic(TvHomeLayout.heroAutoAdvance, (_) => _autoAdvance());
  }

  void _autoAdvance() {
    if (!_canRotate) {
      _advance?.cancel();
      _advance = null;
      return;
    }
    setState(() => _index = (_index + 1) % widget.groups.length);
    _notifyActive();
  }

  /// Any deliberate act by the viewer: a slide change, a press, arriving on a
  /// CTA. Stops the rotation and starts the inactivity window; nothing else in
  /// this file restarts [_advance].
  void _noteInteraction() {
    _advance?.cancel();
    _advance = null;
    _idle?.cancel();
    _idle = Timer(TvHomeLayout.heroAutoAdvance, () {
      _idle = null;
      if (mounted) _syncAutoplay();
    });
  }

  // ------------------------------------------------------------- navigation

  /// Hoofdstuk 7.3's manual slide navigation. Finite, not wrapping: LEFT on the
  /// first slide and RIGHT on the last stay put, the same convention the topnav
  /// ("geen wrap van laatste naar eerste") and the rails already use. The
  /// alternative — wrapping — makes a two-slide hero oscillate under a held
  /// key with no way to tell you have reached the end.
  void _move(int delta) {
    if (widget.groups.length < 2) return;
    final next = _index + delta;
    if (next < 0 || next >= widget.groups.length) return;
    setState(() {
      _index = next;
      _showIndicator = true;
    });
    _notifyActive();
    _noteInteraction();
    _indicatorHold?.cancel();
    _indicatorHold = Timer(TvHomeLayout.heroSegmentIndicatorHold, () {
      if (mounted) setState(() => _showIndicator = false);
    });
  }

  void _notifyActive() {
    final group = activeGroup;
    if (group != null) widget.onActiveGroupChanged?.call(group.groupId);
  }

  void _activate({required UnifiedActivationIntent intent, required bool playDirectly}) {
    final group = activeGroup;
    if (group == null) return;
    _noteInteraction();
    widget.onActivate(group, intent: intent, playDirectly: playDirectly);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final group = activeGroup;
    if (group == null) return SizedBox(width: widget.size.width, height: widget.size.height);

    final scale = TvLayoutConstants.scaleOf(context);
    final item = group.representativeSource.item;
    final client = widget.clientFor?.call(item.serverId ?? '');

    return AutomationNode(
      // The existing `discover.hero` id, adopted on TV.
      //
      // It was registered only in `DiscoverScreen._buildHeroSectionSliver`,
      // whose own comment reads "TV runs through _buildTvContent, so this
      // section is phone/tablet/desktop" — so `/v1/ui_tree` on tvOS reported
      // the nav and the rails and nothing of the hero, on the platform where
      // the hero *is* the landing. `tvos.sidebar.collapse` records that gap in
      // its own comments; `tvos.home.hero-return` is the scenario that needs it
      // closed, because "the billboard came back into view" is a statement
      // about a rect. No new id: the same one, on the second surface that draws
      // the thing it names.
      id: AutomationIds.discoverHero,
      role: 'hero',
      label: heroTitleFor(group),
      child: Semantics(
        container: true,
        label: widget.groups.length > 1
            ? '${t.unifiedCatalog.home.featured}: ${heroTitleFor(group)}, '
                  '${t.unifiedCatalog.discovery.semantics.position(position: _index + 1, count: widget.groups.length)}'
            : '${t.unifiedCatalog.home.featured}: ${heroTitleFor(group)}',
        child: Stack(
          children: [
            TvHeroBillboardCard(
              group: group,
              size: widget.size,
              client: client,
              hideSpoilers: widget.hideSpoilers,
              textOpacity: widget.textOpacity,
              artwork: AnimatedSwitcher(
                duration: reduceMotion(context, TvHomeLayout.heroCrossfade),
                // Both layers on screen at once during the fade, the outgoing one
                // underneath: the default `AnimatedSwitcher` layout stacks them,
                // which is exactly the dissolve 33.1 asks for and not the
                // fade-to-background-and-back a `SizeTransition` would give.
                child: TvHeroArtwork(key: ValueKey(group.groupId), item: item, size: widget.size, client: client),
              ),
              actions: _actions(context, group, scale),
            ),
            if (_showIndicator && widget.groups.length > 1)
              Positioned(
                right: (TvHomeLayout.heroContentInset * scale),
                bottom: (TvHomeLayout.heroContentBottom * scale),
                child: _SegmentIndicator(count: widget.groups.length, active: _index, scale: scale),
              ),
          ],
        ),
      ),
    );
  }

  /// The neighbour [step] places along the rendered CTA order, as a navigation
  /// callback. Falling off either end is the carousel's own edge: hoofdstuk 25
  /// keeps the slide tied to the visual direction, so LEFT off the leftmost
  /// pill is the previous slide and RIGHT off the rightmost one the next, in
  /// both directionalities.
  VoidCallback _stepFrom(List<FocusNode> rendered, FocusNode from, int step) {
    final at = rendered.indexOf(from) + step;
    if (at < 0 || at >= rendered.length) return () => _move(step);
    final node = rendered[at];
    return () => node.requestFocus();
  }

  /// The two CTAs, with LEFT and RIGHT wired to the geometry the [Row] actually
  /// renders rather than to the order this list is written in.
  ///
  /// A `Row` mirrors its children under an RTL [Directionality] — that *is*
  /// hoofdstuk 25's "CTA-volgorde logisch spiegelen" — so `Meer info` ends up
  /// physically left of `Afspelen`. Wiring Afspelen's RIGHT to Meer info by
  /// list position would then throw the focus backwards across the screen,
  /// which on a remote reads as broken. The directionality that positions the
  /// pills is therefore the single authority for their traversal, so the layout
  /// and the D-pad cannot drift apart again.
  ///
  /// Nothing else moves: the pills keep their order, their labels, their
  /// semantics and their actions — only which physical arrow reaches which one.
  Widget _actions(BuildContext context, UnifiedMediaGroup group, double scale) {
    final resume = resumeFractionFor(group);

    // Read inside the row's own subtree, not the carousel's, so the authority
    // stays whatever directionality the pills are actually laid out under.
    return Builder(
      builder: (context) {
        // Left to right on screen, once the row has resolved its own order.
        final rendered = Directionality.of(context) == TextDirection.rtl
            ? [_infoFocus, _playFocus]
            : [_playFocus, _infoFocus];

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `discover.hero.play` on the TV pill, the same id the
            // phone/desktop hero's play button already carries. Given the
            // carousel's own `_playFocus`, so a scenario can assert both where
            // the pill is and whether the remote is on it — which is the whole
            // of `tvos.home.hero-return`'s second half.
            AutomationNode(
              id: AutomationIds.discoverHeroPlay,
              role: 'button',
              focusNode: _playFocus,
              child: FocusableButton(
                focusNode: _playFocus,
                autoScroll: false,
                // The pill paints its own focus (it inverts), so the wrapper must not
                // also draw a ring around it.
                mode: FocusIndicatorMode.delegated,
                // 33.1 binds a *white* Afspelen capsule at rest, and the shared
                // button's unfocused 60% dim would render it grey until focused —
                // a state the north star does not have. The pill draws its own focus
                // (the ring on its reserved band, and the secondary's inversion), so
                // it owns the whole treatment.
                dimWhenUnfocused: false,
                onPressed: () => _activate(intent: UnifiedActivationIntent.play, playDirectly: true),
                onNavigateDown: widget.onNavigateDown,
                onNavigateUp: widget.onNavigateUp,
                onNavigateLeft: _stepFrom(rendered, _playFocus, -1),
                onNavigateRight: _stepFrom(rendered, _playFocus, 1),
                onBack: widget.onBack,
                child: _HeroPill(
                  focusNode: _playFocus,
                  icon: Symbols.play_arrow_rounded,
                  label: resume != null ? t.common.resume : t.common.play,
                  scale: scale,
                  primary: true,
                  progress: resume,
                  onGainedFocus: () {
                    _lastCtaWasInfo = false;
                    _noteInteraction();
                  },
                ),
              ),
            ),
            SizedBox(width: TvHomeLayout.heroActionGap * scale),
            FocusableButton(
              focusNode: _infoFocus,
              autoScroll: false,
              mode: FocusIndicatorMode.delegated,
              // 33.1 binds a *white* Afspelen capsule at rest, and the shared
              // button's unfocused 60% dim would render it grey until focused —
              // a state the north star does not have. The pill draws its own focus
              // (the ring on its reserved band, and the secondary's inversion), so
              // it owns the whole treatment.
              dimWhenUnfocused: false,
              onPressed: () => _activate(intent: UnifiedActivationIntent.details, playDirectly: false),
              onNavigateDown: widget.onNavigateDown,
              onNavigateUp: widget.onNavigateUp,
              onNavigateLeft: _stepFrom(rendered, _infoFocus, -1),
              onNavigateRight: _stepFrom(rendered, _infoFocus, 1),
              onBack: widget.onBack,
              child: _HeroPill(
                focusNode: _infoFocus,
                icon: Symbols.info_rounded,
                label: t.mediaMenu.viewDetails,
                scale: scale,
                primary: false,
                onGainedFocus: () {
                  _lastCtaWasInfo = true;
                  _noteInteraction();
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One CTA. 33.1: a white `▶ Afspelen` capsule and a dark `Meer info` one, and
/// white is reserved for focus — so the secondary pill inverts to white when
/// focused and the primary, already white, gains the ring instead.
class _HeroPill extends StatefulWidget {
  const _HeroPill({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.scale,
    required this.primary,
    required this.onGainedFocus,
    this.progress,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final double scale;
  final bool primary;
  final VoidCallback onGainedFocus;

  /// Resume fraction, drawn as a slim bar inside the primary pill when the
  /// featured title has real progress.
  final double? progress;

  @override
  State<_HeroPill> createState() => _HeroPillState();
}

class _HeroPillState extends State<_HeroPill> {
  bool _wasFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    final has = widget.focusNode.hasFocus;
    if (has && !_wasFocused) widget.onGainedFocus();
    _wasFocused = has;
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = widget.scale;

    return ListenableBuilder(
      listenable: widget.focusNode,
      builder: (context, _) {
        final showFocus = widget.focusNode.hasFocus && InputModeTracker.isKeyboardMode(context);
        // The primary is white at rest already, so focus cannot be "turn
        // white"; it is the ring. The secondary is dark at rest and inverts.
        final filled = widget.primary || showFocus;
        final bg = filled ? tk.text : tk.text.withValues(alpha: TvHomeLayout.heroSecondaryFillAlpha);
        final fg = filled ? tk.bg : tk.text;

        final ringGap = TvHomeLayout.heroActionFocusRingGap * scale;

        // The ring stands *off* the pill, on a band of artwork, and the band is
        // reserved whether or not the pill has the focus so the row's geometry
        // never moves. Without the gap the primary CTA is a white ring drawn
        // straight onto a white capsule: the two merge, and the one control
        // Home rests on stops saying where the remote is at three metres. It is
        // the same reason [TvDiscoveryLayout.cardFocusRingGap] exists for a
        // tile — bright surface, white ring, nothing to contrast with.
        return Container(
          padding: EdgeInsets.all(ringGap),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TvHomeLayout.heroActionRadius * scale + ringGap),
            border: Border.all(color: showFocus ? tk.text : Colors.transparent, width: FocusTheme.focusBorderWidth),
          ),
          child: AnimatedContainer(
            duration: reduceMotion(context, FocusTheme.getAnimationDuration(context)),
            curve: Curves.easeOutCubic,
            height: TvHomeLayout.heroActionHeight * scale,
            padding: EdgeInsets.symmetric(horizontal: TvHomeLayout.heroActionPaddingHorizontal * scale),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(TvHomeLayout.heroActionRadius * scale),
              boxShadow: showFocus
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: TvDiscoveryLayout.cardFocusShadowAlpha),
                        blurRadius: TvDiscoveryLayout.cardFocusShadowBlur * scale,
                        offset: Offset(0, TvDiscoveryLayout.cardFocusShadowOffsetY * scale),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(widget.icon, fill: 1, size: TvHomeLayout.heroActionIconSize * scale, color: fg),
                SizedBox(width: TvHomeLayout.heroActionIconLabelGap * scale),
                if (widget.progress != null) ...[
                  Container(
                    width: 40 * scale,
                    height: 4 * scale,
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(2 * scale),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: widget.progress,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(2 * scale)),
                      ),
                    ),
                  ),
                  SizedBox(width: TvHomeLayout.heroActionIconLabelGap * scale),
                ],
                Text(
                  widget.label,
                  style: TextStyle(color: fg, fontSize: TvHomeLayout.heroActionFontSize * scale, fontWeight: .w600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Hoofdstuk 9.6: "Geen permanente reeks kleine webachtige dots. Tijdens
/// handmatig wisselen verschijnt optioneel een korte segmentindicator, die na
/// twee seconden verdwijnt." Segments rather than dots, and excluded from
/// semantics — the slide position is already on the carousel's own label, and
/// announcing eight anonymous bars after it would be noise.
class _SegmentIndicator extends StatelessWidget {
  const _SegmentIndicator({required this.count, required this.active, required this.scale});

  final int count;
  final int active;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(width: TvHomeLayout.heroSegmentIndicatorGap * scale),
            Container(
              width: TvHomeLayout.heroSegmentIndicatorWidth * scale,
              height: TvHomeLayout.heroSegmentIndicatorHeight * scale,
              decoration: BoxDecoration(
                color: tk.text.withValues(alpha: i == active ? 1 : TvHomeLayout.heroSegmentIndicatorIdleAlpha),
                borderRadius: BorderRadius.circular(TvHomeLayout.heroSegmentIndicatorHeight * scale),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
