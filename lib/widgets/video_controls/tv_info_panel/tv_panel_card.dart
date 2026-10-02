import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../theme/glass/glass_settings.dart';
import '../../../theme/glass/glass_surface.dart';
import '../../../theme/glass/glass_text.dart';
import 'tv_panel_widgets.dart';

/// Blur behind the legacy card. Judged on hardware: a full-width blur over
/// playing video is the one cost of the glass look, and the Apple TV decides it.
const double kTvPanelBlurSigma = 24;

/// The surface of the TV player panel (mockup 33, DEC-101; LG-05 with glass).
///
/// Glass off: today's card, a 24-sigma blur under a 70% dark fill.
/// Glass on: a [GlassSurface] with [GlassTokens.tvPanel] and no backdrop.
/// mpv draws into a native layer under the FlutterView on tvOS, as on iOS
/// (`ios/Runner/MpvPlayer/MpvPlayerCore.swift`, shared via
/// `tvos/scripts/wire_mpv.rb`), so a Flutter backdrop cannot sample the video;
/// the tint and the rim carry the glass. Text on it inherits [kGlassTextShadows].
class TvPanelCard extends StatelessWidget {
  const TvPanelCard({
    super.key,
    required this.radius,
    required this.maxHeight,
    required this.padding,
    required this.child,
  });

  final double radius;
  final double maxHeight;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final legacy = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: kTvPanelBlurSigma, sigmaY: kTvPanelBlurSigma),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          padding: padding,
          decoration: BoxDecoration(
            color: TvPanelTheme.card,
            borderRadius: borderRadius,
            border: Border.all(color: TvPanelTheme.cardBorder),
            boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 60, offset: Offset(0, 30))],
          ),
          child: child,
        ),
      ),
    );
    return GlassSurface(
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      tokens: GlassTokens.tvFor(context, panel: true),
      backdrop: false,
      legacy: legacy,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: padding,
        child: DefaultTextStyle.merge(
          style: const TextStyle(shadows: kGlassTextShadows),
          child: child,
        ),
      ),
    );
  }
}

/// Whether the panel renders on glass; the pills pick their fill from it.
bool tvPanelGlassOn(BuildContext context) => glassTierFor(context) != GlassTier.off;
