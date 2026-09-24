import 'package:flutter/widgets.dart';

import '../../services/device_performance.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';

/// How a glass surface should render.
///
/// - [off]: the setting is disabled, or the device is a tablet (glass reads
///   worse at that size and iPad has no real-glass renderer target anyway).
/// - [real]: `liquid_glass_renderer` on Impeller: handheld iOS only, and
///   only when the device isn't on the reduced-performance tier.
/// - [fake]: every other case, including tvOS and Skia fallbacks. The hand
///   rolled `BackdropFilter` stack in [GlassSurface]: never a package widget.
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
/// `docs/liquid-glass-mockups-2026-09.md` (De CSS-recepten) and DEC-122,
/// revised in Fixronde 1 (see below).
///
/// [edge] is an alpha fraction (0..1) of white for the plate's light rim:
/// the surface builds that color so both render paths stay in the same units
/// as `LiquidGlassSettings.glassColor`'s alpha channel. [tint] is the plate's
/// own fill color, alpha included.
@immutable
class GlassTokens {
  final double blur;
  final double saturation;
  final double dim;
  final Color tint;
  final double edge;

  const GlassTokens({
    required this.blur,
    required this.saturation,
    required this.dim,
    required this.tint,
    required this.edge,
  });

  /// iPhone glass: blur 12, saturation 1.5, dim 0.78. Fixronde 1: the plate
  /// tint went from white 14% to a dark fill (`Color(0xA6000000)`, black at
  /// 65%): measured against the lightest real fixture (Big Buck Bunny's
  /// sky/fur, see `test/fixtures/glass/`), white text on a *white*-tinted
  /// plate over that scene doesn't clear 4.5:1 no matter how strong
  /// `glassText`'s shadow is. Darkening the plate helps, but even 65% (the
  /// agreed ceiling for this round) doesn't reach 4.5:1 either; see the task
  /// report's Fixronde 1 section for the measured numbers and the open
  /// decision. The white rim ([edge]) and the subtle top highlight
  /// (`GlassSurface`'s own paint) stay: that's what still reads as glass
  /// instead of a flat dark chip.
  const GlassTokens.phone() : this(blur: 12, saturation: 1.5, dim: 0.78, tint: const Color(0xA6000000), edge: 0);

  /// Apple TV nepglas: blur 30, saturation 1.2, dim 0.80, the same dark plate
  /// tint as [phone] (black 65%, Fixronde 1) for the same contrast reason,
  /// plus the 1.5px white-40% rim ([edge] holds the 40% alpha; the 1.5px
  /// width is fixed in [GlassSurface], since only this token draws a rim).
  const GlassTokens.tv() : this(blur: 30, saturation: 1.2, dim: 0.80, tint: const Color(0xA6000000), edge: 0.40);

  /// Prominent white glass (e.g. the film-page Resume button): unchanged by
  /// Fixronde 1: same layers as [phone] but tint white 92% and no damping,
  /// so the plate stays white. Text on this tier is black and does not use
  /// [glassText]'s shadow.
  const GlassTokens.prominent() : this(blur: 12, saturation: 1.5, dim: 1.0, tint: const Color(0xEBFFFFFF), edge: 0);
}
