/// Shared A-24 (Apple TV+ Studio) values for the settings surfaces off TV.
/// Every helper here returns the unchanged TV value on TV.
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/platform_detector.dart';

/// Corner radius of a settings card off TV (A-24, Apple TV+ Studio). TV keeps
/// [MonoTokens.radiusMd], which its focus ring is drawn against.
const double kSettingsCardRadius = 14;

/// The card colour on OLED (A-24). The OLED surface (#141414) sits so close to
/// the pure black page that a card of grouped rows all but disappears; this is
/// one step lighter, still well below the dark theme's own surface.
const Color kSettingsOledCardColor = Color(0xFF1A1A1C);

/// Section headings in the light theme (A-24): a warm brick instead of grey,
/// the Studio direction's accent. 5.9:1 on the light page (#F7F7F8), so it
/// clears WCAG AA for small text.
const Color kSettingsSectionInkLight = Color(0xFFA0432A);

/// Widest share of the row a value label may take before it ellipsizes.
const double kSettingsValueMaxFraction = 0.4;

/// True for the OLED palette, the only one whose page is pure black.
bool _isOledPalette(MonoTokens t) => t.bg.toARGB32() == 0xFF000000;

/// Fill of a [SettingsGroup] card. TV keeps [MonoTokens.surface] unchanged.
Color settingsCardColor(BuildContext context) {
  final t = tokens(context);
  if (!PlatformDetector.isTV() && _isOledPalette(t)) return kSettingsOledCardColor;
  return t.surface;
}

/// Ink of a section heading and of the Studio header's eyebrow line: the warm
/// brick in light, the muted text colour in dark and OLED, and always the
/// muted colour on TV.
Color settingsSectionInk(BuildContext context) {
  final t = tokens(context);
  if (!PlatformDetector.isTV() && t.isLight) return kSettingsSectionInkLight;
  return t.textMuted;
}
