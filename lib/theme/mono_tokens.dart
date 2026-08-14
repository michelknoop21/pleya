import 'dart:ui';
import 'package:flutter/material.dart';

MonoTokens tokens(BuildContext context) => Theme.of(context).extension<MonoTokens>()!;

/// Zero-duration when the user has "reduce motion" enabled (OS toggle), else [d].
/// Lets animations crossfade/snap instead of moving for accessibility.
Duration reduceMotion(BuildContext context, Duration d) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

@immutable
class MonoTokens extends ThemeExtension<MonoTokens> {
  // TV home hero layout (moved from DiscoverScreen — values unchanged).
  // Fraction of viewport height above the hero/spotlight content block.
  static const double tvHeroContentTopFraction = 0.075;
  // Upper bound on the browse-rail peek at the bottom of the TV home screen
  // when the hero is focused (fraction of viewport height). The peek itself is
  // content-driven — it's whatever the first hub needs to show in full — and
  // this cap only stops a very tall first hub from squeezing the hero below
  // roughly a third of the screen.
  static const double tvHomeRailMaxPeekFraction = 0.5;
  // Gap between the hero content and the peeking rail (logical px, pre-scale).
  static const double tvHeroRailGap = 16;
  // Minimum height reserved for the hero info block (logical px, pre-scale).
  static const double tvHeroMinInfoHeight = 96;

  final double radiusSm;
  final double radiusMd;
  final double space;
  final Duration fast;
  final Duration normal;
  final Duration slow;
  final Color bg;
  final Color surface;
  final Color surfaceElevated;
  final Color outline;
  final Color text;
  final Color textMuted;

  /// True for the light theme. Artwork does not flip with the theme, so any
  /// layer that sits on top of a poster/backdrop has to fork on this instead
  /// of using one set of values for both modes. See [artworkScrimAlpha] and
  /// [onArtwork].
  final bool isLight;

  /// Brand accent (red). Used sparingly: progress bars, badges,
  /// wordmark, selection highlights — not as general primary.
  final Color accent;

  /// Secondary brand accent (amber). Pairs with [accent] in [accentGradient].
  final Color accentAlt;
  final InteractiveInkFeatureFactory? splashFactory;

  const MonoTokens({
    required this.radiusSm,
    required this.radiusMd,
    required this.space,
    required this.fast,
    required this.normal,
    required this.slow,
    required this.bg,
    required this.surface,
    required this.surfaceElevated,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.isLight,
    required this.accent,
    required this.accentAlt,
    required this.splashFactory,
  });

  /// 135° red→amber brand gradient.
  LinearGradient get accentGradient =>
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [accent, accentAlt]);

  /// The wash colour for a scrim laid over artwork.
  ///
  /// Always [bg], never a hardcoded black: a scrim exists to carry
  /// theme-coloured text, so it has to end up on the same side of the contrast
  /// line as that text. Pair with [artworkScrimAlpha] for the opacity.
  Color get artworkScrim => bg;

  /// Opacity for an [artworkScrim] stop.
  ///
  /// Dark mode dims the backdrop, so a modest veil suffices. Light mode's veil
  /// is white — it *brightens* the artwork rather than dimming it, while the
  /// near-black text on top does not move. Light therefore needs to wash
  /// harder and further before releasing the image. Always pass the existing
  /// value as [dark] so the dark theme stays byte-identical.
  double artworkScrimAlpha({required double dark, required double light}) => isLight ? light : dark;

  /// Ink for text and icons that sit directly on artwork, or on an
  /// [artworkScrim] over it. Never hardcode `Colors.white` for this: on a
  /// light scrim white is invisible.
  Color get onArtwork => text;

  /// [onArtwork] at a mode-dependent opacity.
  ///
  /// Dimmed ink reads as "secondary" on a dark surface but as "washed out" on
  /// a light one — black at 66% over bright artwork loses far more contrast
  /// than white at 66% over a dark backdrop, so light mode keeps more ink.
  Color onArtworkInk({required double dark, required double light}) => text.withValues(alpha: isLight ? light : dark);

  @override
  MonoTokens copyWith({
    double? radiusSm,
    double? radiusMd,
    double? space,
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Color? bg,
    Color? surface,
    Color? surfaceElevated,
    Color? outline,
    Color? text,
    Color? textMuted,
    bool? isLight,
    Color? accent,
    Color? accentAlt,
    InteractiveInkFeatureFactory? splashFactory,
  }) => MonoTokens(
    radiusSm: radiusSm ?? this.radiusSm,
    radiusMd: radiusMd ?? this.radiusMd,
    space: space ?? this.space,
    fast: fast ?? this.fast,
    normal: normal ?? this.normal,
    slow: slow ?? this.slow,
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    outline: outline ?? this.outline,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    isLight: isLight ?? this.isLight,
    accent: accent ?? this.accent,
    accentAlt: accentAlt ?? this.accentAlt,
    splashFactory: splashFactory ?? this.splashFactory,
  );

  @override
  ThemeExtension<MonoTokens> lerp(covariant MonoTokens? other, double t) {
    if (other == null) return this;
    Color lerpC(Color a, Color b) => Color.lerp(a, b, t)!;
    return MonoTokens(
      radiusSm: lerpDouble(radiusSm, other.radiusSm, t)!,
      radiusMd: lerpDouble(radiusMd, other.radiusMd, t)!,
      space: lerpDouble(space, other.space, t)!,
      fast: Duration(
        milliseconds: lerpDouble(fast.inMilliseconds.toDouble(), other.fast.inMilliseconds.toDouble(), t)!.round(),
      ),
      normal: Duration(
        milliseconds: lerpDouble(normal.inMilliseconds.toDouble(), other.normal.inMilliseconds.toDouble(), t)!.round(),
      ),
      slow: Duration(
        milliseconds: lerpDouble(slow.inMilliseconds.toDouble(), other.slow.inMilliseconds.toDouble(), t)!.round(),
      ),
      bg: lerpC(bg, other.bg),
      surface: lerpC(surface, other.surface),
      surfaceElevated: lerpC(surfaceElevated, other.surfaceElevated),
      outline: lerpC(outline, other.outline),
      text: lerpC(text, other.text),
      textMuted: lerpC(textMuted, other.textMuted),
      // Not interpolatable: the artwork underneath never crossfades, so the
      // scrim has to commit to one mode. Snap at the halfway point.
      isLight: t < 0.5 ? isLight : other.isLight,
      accent: lerpC(accent, other.accent),
      accentAlt: lerpC(accentAlt, other.accentAlt),
      splashFactory: other.splashFactory,
    );
  }
}
