/// Pieces of `MobileCatalogScreen` that carry no screen state: the
/// translucent top panel, the edge fades and the skeleton and empty bodies.
library;

import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../widgets/media_card_grid_layout.dart';
import '../../widgets/mobile/mobile_media_rail.dart' show mobileRailGutter, mobileRailInset;
import '../../widgets/skeleton_media_card.dart';

/// Lets tests find the top panel.
@visibleForTesting
const catalogTopMenuKey = ValueKey<String>('catalog.top_menu');

/// How long the top panel takes to leave and to come back (A-06). It leaves a
/// little slower than it returns, both on [Curves.easeOutCubic]: quick to
/// start, soft to settle, in either direction.
const catalogPanelHideDuration = Duration(milliseconds: 260);
const catalogPanelShowDuration = Duration(milliseconds: 200);

/// The catalogue's top panel (status bar inset, title row, chips, count line)
/// as a translucent layer over the grid, in the tab bar's frosted idiom: a
/// blur plus a tint of the page background. When [collapsed] it slides off
/// the top while its content, tint and blur fade out; reduce motion snaps it
/// instead. Being an overlay, it never changes the grid's viewport, so
/// collapsing cannot move or re-clamp the scroll position.
class CatalogTopPanel extends StatefulWidget {
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

  /// Height of the soft lower edge below the measured content, where the tint
  /// runs out over the grid.
  static const double fadeTail = 16;

  @override
  State<CatalogTopPanel> createState() => _CatalogTopPanelState();
}

class _CatalogTopPanelState extends State<CatalogTopPanel> with SingleTickerProviderStateMixin {
  /// 0 is fully shown, 1 is fully gone. Driven with `animateTo` from the
  /// current value, so a reversal mid-flight starts where the panel is: the
  /// position stays continuous, the speed changes at the flip.
  late final AnimationController _hidden = AnimationController(vsync: this, value: widget.collapsed ? 1 : 0);

  static const double _sigma = 18;

  /// Nearly opaque: when the panel returns mid-list it sits on top of
  /// posters, and the controls must not read against the artwork behind them.
  static const double _tintAlpha = 0.94;

  /// The blur does not stop at one line: it steps down across the content's
  /// last few pixels and the top of the tail, strongest first.
  static const List<double> _blurSteps = [0.7, 0.45, 0.25, 0.1];
  static const double _blurStepHeight = 4;

  @override
  void didUpdateWidget(CatalogTopPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed == oldWidget.collapsed) return;
    final target = widget.collapsed ? 1.0 : 0.0;
    final full = widget.collapsed ? catalogPanelHideDuration : catalogPanelShowDuration;
    final duration = reduceMotion(context, full * (target - _hidden.value).abs());
    if (duration == Duration.zero) {
      _hidden.value = target;
    } else {
      unawaited(_hidden.animateTo(target, duration: duration, curve: Curves.easeOutCubic));
    }
  }

  @override
  void dispose() {
    _hidden.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _hidden,
      child: KeyedSubtree(key: widget.measureKey, child: widget.child),
      builder: (context, content) {
        final visible = 1 - _hidden.value;
        return FractionalTranslation(
          translation: Offset(0, -_hidden.value),
          child: IgnorePointer(
            ignoring: widget.collapsed,
            child: ExcludeSemantics(
              excluding: widget.collapsed,
              child: Stack(
                key: catalogTopMenuKey,
                children: [
                  Positioned.fill(child: _blur(visible)),
                  Positioned.fill(child: _tint(visible)),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(opacity: visible, child: content),
                      const SizedBox(height: CatalogTopPanel.fadeTail),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _blur(double visible) {
    Widget layer(double strength) {
      final sigma = _sigma * strength * visible;
      return ClipRect(
        child: BackdropFilter(
          enabled: sigma > 0,
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: const SizedBox.expand(),
        ),
      );
    }

    // Half the ramp sits on the content's last pixels, half on the tail; the
    // rest of the tail is tint only.
    final rampIntoTail = _blurSteps.length * _blurStepHeight / 2;
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: layer(1)),
          for (final step in _blurSteps) SizedBox(height: _blurStepHeight, child: layer(step)),
          SizedBox(height: CatalogTopPanel.fadeTail - rampIntoTail),
        ],
      ),
    );
  }

  Widget _tint(double visible) {
    final color = widget.background;
    final alpha = _tintAlpha * visible;
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(color: color.withValues(alpha: alpha)),
          ),
          SizedBox(
            height: CatalogTopPanel.fadeTail,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Eased rather than linear, so the tint has no visible kink
                // where it starts to run out.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.2, 0.45, 0.7, 0.88, 1],
                  colors: [
                    for (final f in const [1.0, 0.72, 0.42, 0.18, 0.05, 0.0]) color.withValues(alpha: alpha * f),
                  ],
                ),
              ),
            ),
          ),
        ],
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
