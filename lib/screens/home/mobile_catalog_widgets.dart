/// Pieces of `MobileCatalogScreen` that carry no screen state: the
/// translucent top panel, the edge fades and the skeleton and empty bodies.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../widgets/media_card_grid_layout.dart';
import '../../widgets/mobile/mobile_media_rail.dart' show mobileRailGutter, mobileRailInset;
import '../../widgets/skeleton_media_card.dart';

/// Lets tests find the top panel.
@visibleForTesting
const catalogTopMenuKey = ValueKey<String>('catalog.top_menu');

/// The catalogue's top panel (status bar inset, title row, chips, count line)
/// as a translucent layer over the grid, in the tab bar's frosted idiom: a
/// blur plus a tint of the page background, ending in a soft fade. It slides
/// off the top when [collapsed] and, being an overlay, never changes the
/// grid's viewport, so collapsing cannot move or re-clamp the scroll position.
class CatalogTopPanel extends StatelessWidget {
  const CatalogTopPanel({
    super.key,
    required this.collapsed,
    required this.background,
    required this.measureKey,
    required this.child,
  });

  final bool collapsed;
  final Color background;
  final GlobalKey measureKey;
  final Widget child;

  static const double _fadeTail = 14;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: collapsed ? const Offset(0, -1) : Offset.zero,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: ExcludeSemantics(
        excluding: collapsed,
        child: Column(
          key: catalogTopMenuKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: ColoredBox(
                  color: background.withValues(alpha: 0.78),
                  child: KeyedSubtree(key: measureKey, child: child),
                ),
              ),
            ),
            SizedBox(
              height: _fadeTail,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [background.withValues(alpha: 0.78), background.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A fade from the page background to transparent, for the status bar and
/// home indicator zones: the grid scrolls through it, the system chrome on top
/// stays readable.
class CatalogEdgeFade extends StatelessWidget {
  const CatalogEdgeFade({super.key, required this.color, required this.fromTop});

  final Color color;
  final bool fromTop;

  @override
  Widget build(BuildContext context) {
    final solid = color.withValues(alpha: 0.85);
    final clear = color.withValues(alpha: 0);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [solid, clear],
          ),
        ),
      ),
    );
  }
}

/// The 2:3 grid on its own geometry, before the first round of results
/// lands, same reasoning `TvCatalogSkeletonGrid` gives: the placeholder is
/// the page's own layout, not a centred spinner that gets replaced by a
/// differently-shaped wall of posters a frame later.
class CatalogSkeletonGrid extends StatelessWidget {
  const CatalogSkeletonGrid({super.key, required this.cardWidth});

  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final cardHeight = cardWidth / (2 / 3) + MediaCardGridLayout.textExtentFor(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowExtent = cardHeight + mobileRailGutter;
        final rows = constraints.maxHeight.isFinite ? (constraints.maxHeight / rowExtent).ceil().clamp(1, 6) : 3;
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: mobileRailInset, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var row = 0; row < rows; row++) ...[
                if (row > 0) const SizedBox(height: mobileRailGutter),
                Row(
                  children: [
                    for (var column = 0; column < 3; column++) ...[
                      if (column > 0) const SizedBox(width: mobileRailGutter),
                      SizedBox(width: cardWidth, height: cardHeight, child: const SkeletonMediaCard()),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class CatalogEmptyState extends StatelessWidget {
  const CatalogEmptyState({super.key, required this.title, required this.body, this.actionLabel, this.onAction});

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tk.text),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: tk.textMuted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
