import 'package:flutter/widgets.dart';

import '../../services/device_performance.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';

/// How a glass surface should render.
///
/// - [off]: the setting is disabled, or the device is a tablet (glass reads
///   worse at that size and iPad has no real-glass renderer target anyway).
/// - [real]: `liquid_glass_renderer` on Impeller — handheld iOS only, and
///   only when the device isn't on the reduced-performance tier.
/// - [fake]: every other case, including tvOS and Skia fallbacks. The hand
///   rolled `BackdropFilter` stack in [GlassSurface] — never a package widget.
enum GlassTier { real, fake, off }

/// Resolves the tier for the current [context]. See [GlassTier] for the
/// rules; they are load-bearing for every glass surface in the app.
GlassTier glassTierFor(BuildContext context) {
  final enabled = SettingsService.instance.read(SettingsService.liquidGlass);
  if (!enabled || PlatformDetector.isTablet(context)) return GlassTier.off;
  if (PlatformDetector.isHandheldIOS(context) && !PlatformDetector.isTV() && !DevicePerformance.isReduced) {
    return GlassTier.real;
  }
  return GlassTier.fake;
}

/// Visual recipe for one glass plate, shared by the real (`liquid_glass_renderer`)
/// and fake (`BackdropFilter`) render paths. Values come from
/// `docs/liquid-glass-mockups-2026-09.md` (De CSS-recepten) and DEC-122.
///
/// [tint] and [edge] are alpha fractions (0..1) of white, not [Color]s — the
/// surface builds the actual color so both render paths stay in the same
/// units as `LiquidGlassSettings.glassColor`'s alpha channel.
@immutable
class GlassTokens {
  final double blur;
  final double saturation;
  final double dim;
  final double tint;
  final double edge;

  const GlassTokens({
    required this.blur,
    required this.saturation,
    required this.dim,
    required this.tint,
    required this.edge,
  });

  /// iPhone glass: blur 12, tint `Color(0x24FFFFFF)` (36/255), saturation 1.5,
  /// dim 0.78, no tokenized rim (the real-glass rim comes from the shader).
  const GlassTokens.phone() : this(blur: 12, saturation: 1.5, dim: 0.78, tint: 36 / 255, edge: 0);

  /// Apple TV nepglas: blur 30, tint 12%, saturation 1.2, dim 0.80, a 1.5px
  /// white-40% rim ([edge] holds the 40% alpha; the 1.5px width is fixed in
  /// [GlassSurface], since only this token currently draws a rim).
  const GlassTokens.tv() : this(blur: 30, saturation: 1.2, dim: 0.80, tint: 0.12, edge: 0.40);

  /// Prominent white glass (e.g. the film-page Resume button): same layers
  /// as [phone] but tint 92% and no damping, so the plate stays white. Text
  /// on this tier is black and does not use [glassText]'s shadow.
  const GlassTokens.prominent() : this(blur: 12, saturation: 1.5, dim: 1.0, tint: 0.92, edge: 0);
}
