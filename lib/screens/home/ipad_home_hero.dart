/// The iPad Home hero (A-17, Michel 31 October 2026): held in landscape it is
/// the tvOS billboard, held in portrait the iPhone card.
///
/// This file decides which of the two is on screen and keeps what they share;
/// it draws nothing itself. The rows below stay `DiscoverScreen`'s own.
///
/// ## One list of slides for both orientations
///
/// The pool of recently released films is empty on any source without a release
/// date and on any library without a recent film (DEC-097). tvOS then shows its
/// one stand-in slide; the old iPad tree had no such thing and drew no hero. The
/// slides here are therefore the tvOS answer in both orientations
/// ([homeBillboardGroups]), because a card that disappeared on a quarter turn
/// would be the same report again, and the slide could not be kept across it.
///
/// ## Turning the device
///
/// A turn swaps one widget for the other, so neither can remember the slide.
/// [IpadHomeHeroState] does, by group id, the way the TV feed already keeps it
/// across a destination switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:provider/provider.dart';

import '../../media/ids.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_route_context.dart';
import '../../providers/discover_provider.dart';
import '../../providers/home_custom_rows_provider.dart';
import '../../providers/home_extra_rows_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../services/settings_service.dart';
import '../../utils/home_hero_layout.dart';
import '../../utils/layout_constants.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/mobile/mobile_hero_card.dart';
import '../../widgets/tv/tv_hero_billboard_carousel.dart';
import '../../widgets/tv/tv_home_row_assembly.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import 'home_group_activation.dart';

/// Below this height a landscape window cannot hold the billboard's text column
/// under the app bar, so it gets the card, which sizes to what is left.
const double ipadBillboardMinHeight = 480;

/// Whether a window this size carries the billboard rather than the card.
bool ipadHeroIsBillboard(Size size) => size.width > size.height && size.height >= ipadBillboardMinHeight;

/// The slides the iPad hero shows right now; see [homeBillboardGroups].
({List<UnifiedMediaGroup> groups, bool settled}) ipadHomeHeroSlides(BuildContext context, {bool listen = true}) {
  final projection = Provider.of<TvHomeProjectionProvider>(context, listen: listen);
  return homeBillboardGroups(
    projection: projection,
    latestMovies: Provider.of<DiscoverProvider>(context, listen: listen).latestMovies,
    rows: tvHomeFeedRows(
      projection: projection,
      layout: Provider.of<HomeLayoutProvider?>(context, listen: listen),
      customRows: Provider.of<HomeCustomRowsProvider?>(context, listen: listen),
      extraRows: Provider.of<HomeExtraRowsProvider?>(context, listen: listen),
    ),
    idleIsSettled: true,
  );
}

class IpadHomeHero extends StatefulWidget {
  const IpadHomeHero({super.key, required this.firstRailHeight, this.onNavigateDown, this.onNavigateUp, this.onBack});

  /// The rail under the hero, for a width. Its shape is the screen's knowledge.
  final double Function(double width) firstRailHeight;

  /// A hardware keyboard's way out of the hero's two buttons.
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onBack;

  @override
  State<IpadHomeHero> createState() => IpadHomeHeroState();
}

class IpadHomeHeroState extends State<IpadHomeHero> {
  final _billboardKey = GlobalKey<TvHeroBillboardCarouselState>();
  final _cardKey = GlobalKey<MobileHeroCardState>();

  String? _activeGroupId;
  bool _heroHasFocus = false;
  bool? _wasBillboard;

  /// The hero's way in for a hardware keyboard, whichever of the two is on
  /// screen. False without a hero, so the caller can pick the next stop. Only
  /// for a key that was pressed: the focus is what stops the rotation.
  bool focusPlay() => _billboardKey.currentState?.focusPlay() ?? _cardKey.currentState?.focusPlay() ?? false;

  /// UP from the first row: the button last used on the billboard, Afspelen on
  /// the card.
  bool focusLastCta() => _billboardKey.currentState?.focusLastCta() ?? _cardKey.currentState?.focusPlay() ?? false;

  void _rememberSlide(String groupId) => _activeGroupId = groupId;

  Future<void> _activate(
    UnifiedMediaGroup group, {
    required UnifiedActivationIntent intent,
    required bool playDirectly,
  }) => playDirectly ? playHomeGroup(context, group) : openHomeGroupDetails(context, group);

  /// Clear of the overlaid app bar, the same top the page has without a hero.
  double _pageTop(BuildContext context) => kToolbarHeight + MediaQuery.paddingOf(context).top + 16;

  @override
  Widget build(BuildContext context) {
    final slides = ipadHomeHeroSlides(context);
    if (slides.groups.isEmpty && slides.settled) {
      return SliverToBoxAdapter(child: SizedBox(height: _pageTop(context)));
    }
    final size = MediaQuery.sizeOf(context);
    final billboard = ipadHeroIsBillboard(size);
    // A turn swaps the widget that held the keyboard's focus for another one.
    if (_heroHasFocus && _wasBillboard != null && billboard != _wasBillboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focusPlay();
      });
    }
    _wasBillboard = billboard;
    return SliverLayoutBuilder(
      builder: (context, constraints) => SliverToBoxAdapter(
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (has) => _heroHasFocus = has,
          child: billboard
              ? _billboard(context, slides.groups, constraints)
              : _card(context, slides.groups, constraints, size),
        ),
      ),
    );
  }

  /// Full bleed under the app bar, with the first rail's label and posters
  /// peeking below it, the tvOS landing on a page that scrolls by touch.
  Widget _billboard(BuildContext context, List<UnifiedMediaGroup> groups, SliverConstraints constraints) {
    final scale = TvLayoutConstants.scaleOf(context);
    final box = Size(
      constraints.crossAxisExtent,
      TvHomeLayout.heroBlockHeight(constraints.viewportMainAxisExtent, scale),
    );
    // Space, not a spinner, while the films that just landed are projected.
    if (groups.isEmpty) return SizedBox.fromSize(size: box);
    // Clipped like the TV feed clips it: a poster-only title's blurred wash
    // spreads past its box, and this sliver paints over the rail below it.
    return ClipRect(
      child: SizedBox.fromSize(
        size: box,
        child: TvHeroBillboardCarousel(
          key: _billboardKey,
          groups: groups,
          size: box,
          touchInput: true,
          textBottom: TvHomeLayout.heroTextRailGap * scale,
          clientFor: (serverId) => context.tryGetMediaClientWithFallback(serverIdOrNull(serverId)),
          // The same signal that stops the card's timer under another tab or a
          // pushed route, so both presentations pause on one rule.
          autoplayEnabled: TickerMode.valuesOf(context).enabled,
          hideSpoilers: SettingsService.instance.read(SettingsService.hideSpoilers),
          initialGroupId: _activeGroupId,
          onActiveGroupChanged: _rememberSlide,
          onActivate: _activate,
          onNavigateDown: widget.onNavigateDown,
          onNavigateUp: widget.onNavigateUp,
          onBack: widget.onBack,
        ),
      ),
    );
  }

  /// The iPhone card and the iPhone's height rule: what the hero, the gap and
  /// the first rail leave of the viewport, measured from under the app bar.
  Widget _card(BuildContext context, List<UnifiedMediaGroup> groups, SliverConstraints constraints, Size size) {
    final top = _pageTop(context);
    final height = homeHeroHeight(
      useSideNav: false,
      viewportExtent: constraints.viewportMainAxisExtent - constraints.precedingScrollExtent - top,
      screenHeight: size.height,
      screenWidth: size.width,
      statusBarHeight: MediaQuery.paddingOf(context).top,
      firstRailHeight: widget.firstRailHeight(size.width),
      heroToRailGap: homeHeroToRailGap,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top, 16, homeHeroToRailGap),
      child: groups.isEmpty
          ? SizedBox(height: height)
          : MobileHeroCard(
              key: _cardKey,
              groups: groups,
              width: constraints.crossAxisExtent - 32,
              height: height,
              onPlay: (group) => playHomeGroup(context, group),
              onSecondaryAction: (group) => openHomeGroupDetails(context, group),
              initialGroupId: _activeGroupId,
              onActiveGroupChanged: _rememberSlide,
              hideSpoilers: SettingsService.instance.read(SettingsService.hideSpoilers),
              keyboardRoute: MobileHeroKeyboardRoute(
                onNavigateUp: widget.onNavigateUp,
                onNavigateDown: widget.onNavigateDown,
                onBack: widget.onBack,
              ),
            ),
    );
  }
}
