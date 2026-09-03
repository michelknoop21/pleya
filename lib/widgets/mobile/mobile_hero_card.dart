/// The mobile Home hero: a rounded, in-page billboard carousel over
/// `HomeHeroSharpPresentation.mobileFeatured`. iOS Unified 2026 fase 1,
/// `docs/ios-unified-2026-fase1-plan.md` stap 6.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
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

  const MobileHeroCard({
    super.key,
    required this.groups,
    required this.width,
    required this.height,
    required this.onPlay,
    required this.onSecondaryAction,
  });

  @override
  State<MobileHeroCard> createState() => _MobileHeroCardState();
}

class _MobileHeroCardState extends State<MobileHeroCard> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restartAutoAdvance();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartAutoAdvance() {
    _timer?.cancel();
    // Reduce Motion: hoofdstuk 9.6 — no unattended rotation. A single slide
    // has nothing to advance to either.
    if (widget.groups.length <= 1 || MediaQuery.disableAnimationsOf(context)) return;
    _timer = Timer.periodic(mobileHeroAutoAdvanceInterval, (_) => _advance());
  }

  void _advance() {
    if (!mounted || !_controller.hasClients) return;
    final next = (_page + 1) % widget.groups.length;
    _controller.animateToPage(next, duration: tokens(context).normal, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) return SizedBox(width: widget.width, height: widget.height);

    return AutomationNode(
      id: AutomationIds.discoverHero,
      role: 'hero',
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
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (context, index) => _MobileHeroSlide(
                    group: widget.groups[index],
                    width: widget.width,
                    height: widget.height,
                    onPlay: () => widget.onPlay(widget.groups[index]),
                    onSecondaryAction: () => widget.onSecondaryAction(widget.groups[index]),
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

  const _MobileHeroSlide({
    required this.group,
    required this.width,
    required this.height,
    required this.onPlay,
    required this.onSecondaryAction,
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
              if (item.summary != null && item.summary!.isNotEmpty) ...[
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
              ),
            ],
          ),
        ),
      ],
    );
  }
}
