/// The mobile Home hero: a rounded, in-page billboard carousel over
/// `HomeHeroSharpPresentation.mobileFeatured`. iOS Unified 2026 fase 1,
/// `docs/ios-unified-2026-fase1-plan.md` stap 6.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../media/unified/unified_media_group.dart';
import '../../services/unified_catalog/hero_text.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/home_hero_layout.dart';
import '../../utils/media_image_helper.dart' show ImageType;
import '../../utils/provider_extensions.dart';
import '../home_hero_artwork.dart';
import '../optimized_media_image.dart';
import 'mobile_hero_actions.dart';
import 'mobile_hero_indicator.dart';

/// How long one slide holds before the carousel auto-advances.
const Duration mobileHeroAutoAdvanceInterval = Duration(seconds: 8);

class MobileHeroCard extends StatefulWidget {
  final List<UnifiedMediaGroup> groups;
  final double width;
  final double height;
  final void Function(UnifiedMediaGroup group) onPlay;
  final void Function(UnifiedMediaGroup group) onSecondaryAction;

  /// The slide to open on, by group id: the iPad turns between this card and
  /// the billboard and keeps the slide. An id no longer in [groups] opens the
  /// first slide.
  final String? initialGroupId;

  final ValueChanged<String>? onActiveGroupChanged;

  /// Set where a slide can be an episode: the iPad's stand-in. Every slide on
  /// the iPhone is a film, where the rule has nothing to hide.
  final bool hideSpoilers;

  /// Where a hardware keyboard leaves this card. Null keeps the buttons plain.
  final MobileHeroKeyboardRoute? keyboardRoute;

  const MobileHeroCard({
    super.key,
    required this.groups,
    required this.width,
    required this.height,
    required this.onPlay,
    required this.onSecondaryAction,
    this.initialGroupId,
    this.onActiveGroupChanged,
    this.hideSpoilers = false,
    this.keyboardRoute,
  });

  @override
  State<MobileHeroCard> createState() => MobileHeroCardState();
}

/// See [MobileHeroCard.keyboardRoute].
class MobileHeroKeyboardRoute {
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onBack;

  const MobileHeroKeyboardRoute({this.onNavigateUp, this.onNavigateDown, this.onBack});
}

class MobileHeroCardState extends State<MobileHeroCard> {
  late final PageController _controller;
  Timer? _timer;
  int _page = 0;
  ValueListenable<TickerModeData>? _tickerModeNotifier;

  /// One pair per slide: the PageView holds two slides at once during a swipe,
  /// and one node cannot sit on two buttons.
  final Map<int, (FocusNode play, FocusNode secondary)> _focusNodes = {};

  (FocusNode, FocusNode) _nodesFor(int page) => _focusNodes.putIfAbsent(
    page,
    () => (FocusNode(debugLabel: 'mobileHeroPlay$page'), FocusNode(debugLabel: 'mobileHeroSecondary$page')),
  );

  bool get hasFocus => _focusNodes.values.any((nodes) => nodes.$1.hasFocus || nodes.$2.hasFocus);

  /// Puts the keyboard on Afspelen of the slide on screen.
  bool focusPlay() {
    if (widget.groups.isEmpty) return false;
    _nodesFor(_page).$1.requestFocus();
    return true;
  }

  /// LEFT and RIGHT off the buttons. Finite like the billboard's, and the focus
  /// lands on the same button of the next slide.
  void _stepSlide(int delta, {required bool toSecondary}) {
    final next = _page + delta;
    if (next < 0 || next >= widget.groups.length) return;
    _controller.jumpToPage(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nodes = _nodesFor(next);
      (toSecondary ? nodes.$2 : nodes.$1).requestFocus();
    });
  }

  MobileHeroActionFocus? _actionFocus(int page) {
    final route = widget.keyboardRoute;
    if (route == null) return null;
    final (play, secondary) = _nodesFor(page);
    return MobileHeroActionFocus(
      playNode: play,
      secondaryNode: secondary,
      onNavigateUp: route.onNavigateUp,
      onNavigateDown: route.onNavigateDown,
      onBack: route.onBack,
      onPreviousSlide: () => _stepSlide(-1, toSecondary: false),
      onNextSlide: () => _stepSlide(1, toSecondary: true),
    );
  }

  @override
  void initState() {
    super.initState();
    final restored = widget.groups.indexWhere((group) => group.groupId == widget.initialGroupId);
    _page = restored < 0 ? 0 : restored;
    _controller = PageController(initialPage: _page);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The IndexedStack tab this card lives under wraps its offstage children
    // in TickerMode(enabled: false) — the same signal that already pauses
    // this screen's animations. Ride it for the carousel timer too, instead
    // of a second, TickerMode-unaware notion of "visible".
    final notifier = TickerMode.getValuesNotifier(context);
    if (!identical(notifier, _tickerModeNotifier)) {
      _tickerModeNotifier?.removeListener(_onTickerModeChanged);
      _tickerModeNotifier = notifier..addListener(_onTickerModeChanged);
    }
    _restartAutoAdvance();
  }

  @override
  void didUpdateWidget(covariant MobileHeroCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A group count that grows past 1 after the first build (the catalogue
    // arriving late) has nothing else that restarts the carousel — only
    // didChangeDependencies and a manual swipe do.
    if (widget.groups.length != oldWidget.groups.length) {
      _restartAutoAdvance();
    }
  }

  @override
  void dispose() {
    _tickerModeNotifier?.removeListener(_onTickerModeChanged);
    _timer?.cancel();
    _controller.dispose();
    for (final nodes in _focusNodes.values) {
      nodes.$1.dispose();
      nodes.$2.dispose();
    }
    super.dispose();
  }

  void _onTickerModeChanged() {
    if (_tickerModeNotifier?.value.enabled == false) {
      _timer?.cancel();
    } else {
      _restartAutoAdvance();
    }
  }

  void _restartAutoAdvance() {
    _timer?.cancel();
    // Reduce Motion: hoofdstuk 9.6 — no unattended rotation. A single slide
    // has nothing to advance to either.
    if (widget.groups.length <= 1 || MediaQuery.disableAnimationsOf(context)) return;
    if (_tickerModeNotifier?.value.enabled == false) return;
    _timer = Timer.periodic(mobileHeroAutoAdvanceInterval, (_) => _advance());
  }

  void _advance() {
    // A slide must not roll away from under the keyboard's focus.
    if (!mounted || !_controller.hasClients || hasFocus) return;
    final next = (_page + 1) % widget.groups.length;
    _controller.animateToPage(next, duration: tokens(context).normal, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) return SizedBox(width: widget.width, height: widget.height);

    return AutomationNode(
      id: AutomationIds.discoverHero,
      role: 'hero',
      state: () => {'activeTitle': heroTitleFor(widget.groups[_page.clamp(0, widget.groups.length - 1)])},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: NotificationListener<ScrollNotification>(
            // Any interaction with the carousel itself pauses it: a manual
            // swipe schedules a fresh 8s window from where the user left it,
            // rather than fighting an auto-advance mid-gesture.
            onNotification: (notification) {
              if (notification is ScrollStartNotification) {
                _timer?.cancel();
              } else if (notification is ScrollEndNotification) {
                _restartAutoAdvance();
              }
              return false;
            },
            child: Stack(
              children: [
                PageView.builder(
                  controller: _controller,
                  itemCount: widget.groups.length,
                  onPageChanged: (index) {
                    setState(() => _page = index);
                    widget.onActiveGroupChanged?.call(widget.groups[index].groupId);
                  },
                  itemBuilder: (context, index) => _MobileHeroSlide(
                    group: widget.groups[index],
                    width: widget.width,
                    height: widget.height,
                    onPlay: () => widget.onPlay(widget.groups[index]),
                    onSecondaryAction: () => widget.onSecondaryAction(widget.groups[index]),
                    hideSpoilers: widget.hideSpoilers,
                    focus: _actionFocus(index),
                  ),
                ),
                if (widget.groups.length > 1)
                  Positioned(
                    left: 16,
                    bottom: 12,
                    child: MobileHeroIndicator(count: widget.groups.length, selectedIndex: _page),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileHeroSlide extends StatelessWidget {
  final UnifiedMediaGroup group;
  final double width;
  final double height;
  final VoidCallback onPlay;
  final VoidCallback onSecondaryAction;
  final bool hideSpoilers;
  final MobileHeroActionFocus? focus;

  const _MobileHeroSlide({
    required this.group,
    required this.width,
    required this.height,
    required this.onPlay,
    required this.onSecondaryAction,
    required this.hideSpoilers,
    this.focus,
  });

  @override
  Widget build(BuildContext context) {
    final item = group.representativeSource.item;
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId));
    final billboardArt = item.billboardArt(containerAspectRatio: width / height, narrowBoxIsFullWidth: true);
    final geometry = homeHeroArtGeometry(
      screenWidth: width,
      heroHeight: height,
      kind: billboardArt?.kind ?? BillboardArtKind.fallback,
      presentation: HomeHeroSharpPresentation.mobileFeatured,
    );
    final hasProgress = item.hasActiveProgress;
    final minutesLeft = hasProgress && item.durationMs != null && item.viewOffsetMs != null
        ? ((item.durationMs! - item.viewOffsetMs!) / 60000).round()
        : null;
    final metaLine = [heroMetaLineFor(group), ?item.contentRating].join(' · ');

    return Stack(
      fit: StackFit.expand,
      children: [
        if (billboardArt != null)
          HomeHeroArtwork(client: client, art: billboardArt, geometry: geometry)
        else
          ColoredBox(color: tokens(context).surfaceElevated),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, tokens(context).artworkScrim.withValues(alpha: 0.88)],
              stops: const [0.4, 1.0],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 44,
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              if (item.clearLogoPath != null)
                SizedBox(
                  height: 44,
                  child: OptimizedMediaImage(
                    client: client,
                    imagePath: item.clearLogoPath,
                    imageType: ImageType.logo,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomLeft,
                  ),
                )
              else
                Text(
                  heroTitleFor(group),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 6),
              Text(
                metaLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (item.summary != null && item.summary!.isNotEmpty && !(hideSpoilers && item.shouldHideSpoiler)) ...[
                const SizedBox(height: 6),
                Text(
                  item.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                ),
              ],
              const SizedBox(height: 12),
              MobileHeroActions(
                hasProgress: hasProgress,
                minutesLeft: minutesLeft,
                onPlay: onPlay,
                onSecondary: onSecondaryAction,
                focus: focus,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
