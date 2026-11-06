import 'package:flutter/material.dart';

import '../services/hero_focus_points.dart';

/// Builds the hero image with the plain top-centre crop straight away, then
/// slides the crop to the image's salient point once [HeroFocusPoints] has
/// it. Never waits on it for the first paint.
class HeroFocusCrop extends StatefulWidget {
  const HeroFocusCrop({
    super.key,
    required this.imageUrl,
    required this.cacheKey,
    required this.boxAspect,
    required this.builder,
    this.points,
  });

  final String imageUrl;
  final String cacheKey;

  /// Width / height of the box the image covers.
  final double boxAspect;
  final Widget Function(Alignment alignment) builder;

  /// Defaults to [HeroFocusPoints.instance].
  final HeroFocusPoints? points;

  @override
  State<HeroFocusCrop> createState() => _HeroFocusCropState();
}

class _HeroFocusCropState extends State<HeroFocusCrop> {
  HeroFocus? _focus;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant HeroFocusCrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _focus = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final key = widget.cacheKey;
    if (widget.imageUrl.isEmpty) return;
    final focus = await (widget.points ?? HeroFocusPoints.instance).resolve(url: widget.imageUrl, key: key);
    if (mounted && focus != null && key == widget.cacheKey) setState(() => _focus = focus);
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Alignment>(
      tween: AlignmentTween(end: heroFocusAlignment(_focus, boxAspect: widget.boxAspect)),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, alignment, _) => widget.builder(alignment),
    );
  }
}
