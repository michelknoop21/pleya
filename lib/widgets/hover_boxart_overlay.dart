import 'dart:async';

import 'package:flutter/material.dart';

/// Netflix-style desktop "boxart expand": after a short hover dwell over
/// [child], an elevated card grows out of it in an [Overlay], anchored to the
/// child via [CompositedTransformTarget]/[Follower]. The overlay content is
/// supplied by [overlayBuilder] so this widget stays presentation-agnostic and
/// reusable; it only owns the hover timing and overlay lifecycle.
///
/// Additive and desktop-only: when [enabled] is false it returns [child]
/// unchanged, so mobile/TV are completely unaffected and the existing
/// long-press / context-menu behaviour keeps working.
class HoverBoxartOverlay extends StatefulWidget {
  final Widget child;
  final bool enabled;

  /// Width of the expanded overlay card.
  final double overlayWidth;

  /// Dwell before the overlay appears.
  final Duration hoverDelay;

  /// Builds the expanded content. [close] dismisses the overlay (e.g. after the
  /// user clicks a quick action that navigates away).
  final Widget Function(BuildContext context, VoidCallback close) overlayBuilder;

  const HoverBoxartOverlay({
    super.key,
    required this.child,
    required this.overlayBuilder,
    this.enabled = true,
    this.overlayWidth = 300,
    this.hoverDelay = const Duration(milliseconds: 400),
  });

  @override
  State<HoverBoxartOverlay> createState() => _HoverBoxartOverlayState();
}

class _HoverBoxartOverlayState extends State<HoverBoxartOverlay> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _scheduleShow() {
    if (!widget.enabled || _entry != null) return;
    _timer?.cancel();
    _timer = Timer(widget.hoverDelay, _showOverlay);
  }

  // Leaving the source card cancels a pending show. If the overlay is already
  // up, schedule a short-grace removal — entering the overlay cancels it (so
  // moving the cursor onto the card's caption area, which the overlay doesn't
  // cover, doesn't leave a stuck preview).
  void _cancelShow() {
    _timer?.cancel();
    if (_entry != null) _scheduleRemove();
  }

  void _scheduleRemove() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 120), _removeOverlay);
  }

  void _cancelRemove() {
    _timer?.cancel();
  }

  void _showOverlay() {
    if (!mounted || _entry != null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    // Grow ~14% and centre the overlay over the card.
    final scaledW = widget.overlayWidth;
    final dx = (size.width - scaledW) / 2;

    _entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: scaledW,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            // Anchor overlay's top-centre a touch above the card's top-centre.
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.topCenter,
            offset: Offset(dx + scaledW / 2 - size.width / 2, -22),
            child: MouseRegion(
              onEnter: (_) => _cancelRemove(),
              onExit: (_) => _scheduleRemove(),
              child: Material(
                color: Colors.transparent,
                child: _GrowIn(child: widget.overlayBuilder(context, _removeOverlay)),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) {
          _cancelRemove(); // cursor returned to the card — keep the preview
          _scheduleShow();
        },
        onExit: (_) => _cancelShow(),
        child: widget.child,
      ),
    );
  }
}

class _GrowIn extends StatefulWidget {
  final Widget child;
  const _GrowIn({required this.child});

  @override
  State<_GrowIn> createState() => _GrowInState();
}

class _GrowInState extends State<_GrowIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(scale: Tween<double>(begin: 0.86, end: 1).animate(curved), child: widget.child),
    );
  }
}
