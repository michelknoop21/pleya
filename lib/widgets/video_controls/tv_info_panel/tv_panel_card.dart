import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../theme/glass/glass_settings.dart';
import '../../../theme/glass/glass_surface.dart';
import '../../../theme/glass/glass_text.dart';
import '../../../utils/platform_detector.dart';
import 'tv_panel_widgets.dart';

/// Blur behind the legacy card, on TVs other than Apple TV (see [TvPanelCard]).
const double kTvPanelBlurSigma = 24;

/// The surface of the TV player panel (mockup 33, DEC-101; LG-05 with glass).
///
/// Glass off: today's card, a 70% dark fill; a 24-sigma blur under it
/// everywhere but Apple TV (see [build]).
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
    final card = Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: padding,
      decoration: BoxDecoration(
        color: TvPanelTheme.card,
        borderRadius: borderRadius,
        border: Border.all(color: TvPanelTheme.cardBorder),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 60, offset: Offset(0, 30))],
      ),
      child: child,
    );
    // On Apple TV the blur would sample only the transparent FlutterView
    // (mpv draws under it), so it shows nothing, yet it costs a display-sized
    // offscreen pass on a 4K screen during 4K playback, where the kernel
    // already kills the app at panel open (PLR12). Same fill, rim and shadow.
    final legacy = ClipRRect(
      borderRadius: borderRadius,
      child: PlatformDetector.isAppleTV()
          ? card
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: kTvPanelBlurSigma, sigmaY: kTvPanelBlurSigma),
              child: card,
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
