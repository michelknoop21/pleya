import 'package:flutter/widgets.dart';

import '../../services/device_performance.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';

/// How a glass surface should render.
///
/// - [off]: the setting is disabled, or [glassAppliesTo] rules the device out
///   (everything but the iPhone and Apple TV).
/// - [real]: `liquid_glass_renderer` on Impeller: handheld iOS only, and
///   only when the device isn't on the reduced-performance tier.
/// - [fake]: Apple TV and the reduced-performance iPhone. The hand
///   rolled `BackdropFilter` stack in [GlassSurface]: never a package widget.
enum GlassTier { real, fake, off }

/// Whether glass renders at all on this device, regardless of the setting.
///
/// An explicit platform list: Apple TV, and the iPhone (handheld iOS that
/// isn't a tablet). The iPad, Android (phone and TV) and desktop never get
/// glass or its settings tile. A size-only rule let a phone-small desktop
/// window through (final review B4). Apple TV is checked on its own because
/// [PlatformDetector.isTablet]'s diagonal-inches heuristic reads a real TV
/// resolution as a giant tablet (Fixronde 1).
bool glassAppliesTo(BuildContext context) =>
    PlatformDetector.isAppleTV() || (PlatformDetector.isHandheldIOS(context) && !PlatformDetector.isTablet(context));

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

  /// `LiquidGlassSettings.glassColor` on the real tier; [tint] when null.
  final Color? realTint;

  const GlassTokens({
    required this.blur,
    required this.saturation,
    required this.dim,
    required this.tint,
    required this.edge,
    this.realTint,
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
  ///
  /// [realTint] is black 60% instead of 50% (final review B2): the package
  /// has no dim, so without the fake tier's 0.78 brightness step the real
  /// plate would be lighter than the one the contrast tests measure. A darker
  /// glass color stands in for that dim. The flutter test renderer cannot
  /// paint the real tier, so this is reasoning, not a measurement: confirm
  /// the real glass (the red active tab icon first) on a device.
  const GlassTokens.phone()
    : this(
        blur: 12,
        saturation: 1.5,
        dim: 0.78,
        tint: const Color(0x80000000),
        edge: 0,
        realTint: const Color(0x99000000),
      );

  /// Apple TV nepglas: blur 30, saturation 1.2, dim 0.80, the same dark plate
  /// tint as [phone] (black 50%, Fixronde 1/2) for the same contrast reason,
  /// plus the 1.5px white-40% rim ([edge] holds the 40% alpha; the 1.5px
  /// width is fixed in [GlassSurface], shared with [control]).
  const GlassTokens.tv() : this(blur: 30, saturation: 1.2, dim: 0.80, tint: const Color(0x80000000), edge: 0.40);

  /// The Apple TV player panel card (LG-05): [tv] with a black 70% tint, the
  /// old card's density (`TvPanelTheme.card`). The card has no backdrop over
  /// mpv, so the 50% of [tv] let the video through brighter than the blurred
  /// old card and the muted row values lost contrast (final review B3). The
  /// top bar and the search pill keep [tv].
  const GlassTokens.tvPanel() : this(blur: 30, saturation: 1.2, dim: 0.80, tint: const Color(0xB3000000), edge: 0.40);

  /// A small glass control on the app's black chrome (the search circle in
  /// the mobile header, LG-01). Over black the dark [phone] plate vanishes,
  /// so this one carries a light 25% fill and a 35% rim: it reads as a grey
  /// button, and a white glyph on it still clears 3:1 by a wide margin.
  const GlassTokens.control() : this(blur: 12, saturation: 1.5, dim: 0.78, tint: const Color(0x40FFFFFF), edge: 0.35);

  /// Prominent white glass (e.g. the film-page Resume button): unchanged by
  /// Fixronde 1: same layers as [phone] but tint white 92% and no damping,
  /// so the plate stays white. Text on this tier is black and does not use
  /// [glassText]'s shadow.
  const GlassTokens.prominent() : this(blur: 12, saturation: 1.5, dim: 1.0, tint: const Color(0xEBFFFFFF), edge: 0);
}
