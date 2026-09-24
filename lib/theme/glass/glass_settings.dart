import 'package:flutter/widgets.dart';

import '../../services/device_performance.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';

/// How a glass surface should render.
///
/// - [off]: the setting is disabled, or [glassAppliesTo] rules the device out
///   (the iPad: glass reads worse at that size and it has no real-glass
///   renderer target anyway; TV is never ruled out here).
/// - [real]: `liquid_glass_renderer` on Impeller: handheld iOS only, and
///   only when the device isn't on the reduced-performance tier.
/// - [fake]: every other case, including tvOS and Skia fallbacks. The hand
///   rolled `BackdropFilter` stack in [GlassSurface]: never a package widget.
enum GlassTier { real, fake, off }

/// Whether glass renders at all on this device, regardless of the setting.
///
/// TV always wins the tablet check: [PlatformDetector.isTablet]'s
/// diagonal-inches heuristic reads a real TV resolution (e.g. 1920x1080) as a
/// giant tablet, which silently turned every tvOS glass surface off before
/// this guard existed (Fixronde 1). Once TV is ruled out, only the iPad is
/// excluded.
bool glassAppliesTo(BuildContext context) => PlatformDetector.isTV() || !PlatformDetector.isTablet(context);

/// Resolves the tier for the current [context]. See [GlassTier] for the
/// rules; they are load-bearing for every glass surface in the app.
GlassTier glassTierFor(BuildContext context) {
  // Settings not loaded yet (a widget test without SettingsService) reads as
  // the pref's default: off.
  final enabled = SettingsService.instanceOrNull?.read(SettingsService.liquidGlass) ?? false;
  if (!enabled || !glassAppliesTo(context)) return GlassTier.off;
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

  /// iPhone glass: blur 12, saturation 1.5, dim 0.78. Fixronde 1 replaced the
  /// white 14% tint with a dark fill: white text on a *white*-tinted plate
  /// over the lightest real fixture (Big Buck Bunny's sky/fur, see
  /// `test/fixtures/glass/`) doesn't clear 4.5:1 no matter how strong
  /// `glassText`'s shadow is. Fixronde 2 re-measured with a corrected
  /// contrast meter (`textContrastOverBackground`, see the task report:
  /// Fixronde 1's meter counted glyph anti-aliasing as background and
  /// silently capped every reading) and found black 50% already clears
  /// 4.5:1 on that fixture, so the tint stayed at the Fixronde 1 starting
  /// point instead of climbing to the old ceiling. The white rim ([edge])
  /// and the subtle top highlight (`GlassSurface`'s own paint) stay: that's
  /// what still reads as glass instead of a flat dark chip.
  const GlassTokens.phone() : this(blur: 12, saturation: 1.5, dim: 0.78, tint: const Color(0x80000000), edge: 0);

  /// Apple TV nepglas: blur 30, saturation 1.2, dim 0.80, the same dark plate
  /// tint as [phone] (black 50%, Fixronde 1/2) for the same contrast reason,
  /// plus the 1.5px white-40% rim ([edge] holds the 40% alpha; the 1.5px
  /// width is fixed in [GlassSurface], since only this token draws a rim).
  const GlassTokens.tv() : this(blur: 30, saturation: 1.2, dim: 0.80, tint: const Color(0x80000000), edge: 0.40);

  /// Prominent white glass (e.g. the film-page Resume button): unchanged by
  /// Fixronde 1: same layers as [phone] but tint white 92% and no damping,
  /// so the plate stays white. Text on this tier is black and does not use
  /// [glassText]'s shadow.
  const GlassTokens.prominent() : this(blur: 12, saturation: 1.5, dim: 1.0, tint: const Color(0xEBFFFFFF), edge: 0);
}
