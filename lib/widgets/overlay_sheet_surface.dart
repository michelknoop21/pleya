import 'package:flutter/material.dart';

import '../theme/glass/glass_settings.dart';
import '../theme/glass/glass_surface.dart';
import '../theme/mono_theme.dart';
import '../theme/mono_tokens.dart';
import '../utils/platform_detector.dart';

/// Whether a sheet of the player's host draws as glass: the user turned Liquid
/// Glass on and this device gets it (`glassTierFor`), and it is not a
/// television, whose player overlays keep their own 10-foot panel. With glass
/// off the sheet is the flat surface it always was.
bool overlaySheetVideoGlassOn(BuildContext context) =>
    !PlatformDetector.isTV() && glassTierFor(context) != GlassTier.off;

/// The plate of a sheet over the player (A-23, Michel on 20 October 2026).
///
/// No backdrop, like every plate in the player (`GlassSurface.backdrop`): mpv
/// renders under the FlutterView on iOS, so a blur would paint black. The tint
/// alone carries the contrast, which makes it heavier than the 55% of the
/// control plates: a sheet holds rows of body text and muted detail lines, not
/// one icon. Black 72% with the controls' white rim, measured over the light
/// Big Buck Bunny frame in `overlay_sheet_video_glass_test.dart`.
const GlassTokens kOverlaySheetVideoGlassTokens = GlassTokens(
  blur: 0,
  saturation: 1,
  dim: 1,
  tint: Color(0xB8000000),
  edge: 0.3,
);

/// Barrier opacity behind an open sheet. Over the player with glass on it is
/// light, so the film stays visible next to the sheet; everywhere else the
/// long-standing 50%.
double overlaySheetBarrierOpacity({required bool videoGlass}) => videoGlass ? 0.2 : 0.5;

/// The sheet's own surface: a clipped [Material] in [color], or the glass plate
/// of [kOverlaySheetVideoGlassTokens] when [videoGlass] is set, with [shadows]
/// cast outside the clip.
///
/// The glass plate is always dark, also in the light theme: it sits over the
/// film like the player's own white-on-dark controls, and dark ink on a
/// translucent dark plate would be unreadable. So the light theme's sheet
/// content renders in the dark theme there; a white plate would need about 95%
/// opacity before muted text cleared 4.5:1 over a dark frame, which is no
/// longer glass.
class OverlaySheetSurface extends StatelessWidget {
  const OverlaySheetSurface({
    super.key,
    required this.borderRadius,
    required this.color,
    required this.shadows,
    required this.videoGlass,
    required this.child,
    this.materialKey,
  });

  final BorderRadius borderRadius;
  final Color color;
  final List<BoxShadow> shadows;
  final bool videoGlass;
  final Widget child;

  /// Key of the [Material]; the host measures the sheet's height through it.
  final Key? materialKey;

  @override
  Widget build(BuildContext context) {
    Widget material(Color fill) =>
        Material(key: materialKey, color: fill, borderRadius: borderRadius, clipBehavior: Clip.antiAlias, child: child);
    final surface = videoGlass
        ? GlassSurface(
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            tokens: kOverlaySheetVideoGlassTokens,
            backdrop: false,
            child: _darkInk(context, material(Colors.transparent)),
          )
        : material(color);
    return _CastShadow(shadows: shadows, borderRadius: borderRadius, child: surface);
  }
}

/// [child] in the dark theme when the app runs in the light one.
Widget _darkInk(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  final light = theme.extension<MonoTokens>()?.isLight ?? theme.brightness == Brightness.light;
  if (!light) return child;
  return Theme(
    data: monoTheme(dark: true).copyWith(platform: theme.platform),
    child: child,
  );
}

/// Paints [shadows] behind [child], or gets out of the way entirely when there
/// are none, which is every presentation except the centred 10-foot panel.
class _CastShadow extends StatelessWidget {
  const _CastShadow({required this.shadows, required this.borderRadius, required this.child});

  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (shadows.isEmpty) return child;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: child,
    );
  }
}
