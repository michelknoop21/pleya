/// Shared A-24 (Apple TV+ Studio) values for the settings surfaces off TV.
/// Every helper here returns the unchanged TV value on TV.
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/platform_detector.dart';
import 'settings_studio_theme.dart';

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
/// Inside [SettingsStudioTheme] the surface already is the Studio card, OLED
/// included (A-24b).
Color settingsCardColor(BuildContext context) {
  final t = tokens(context);
  if (SettingsStudioTheme.isActive(context)) return t.surface;
  if (!PlatformDetector.isTV() && _isOledPalette(t)) return kSettingsOledCardColor;
  return t.surface;
}

/// Ink of a section heading and of the Studio header's eyebrow line: the
/// muted text colour, as the Studio series draws it in both themes (A-24b);
/// the warm brick only on a light settings surface outside the Studio
/// palette, and always the muted colour on TV.
Color settingsSectionInk(BuildContext context) {
  final t = tokens(context);
  if (!PlatformDetector.isTV() && t.isLight && !SettingsStudioTheme.isActive(context)) {
    return kSettingsSectionInkLight;
  }
  return t.textMuted;
}

/// Whether a settings page opens on the A-24 Studio header, with its wash bar
/// and the filled search bar on the main page: on an iPhone only, the scope
/// of A-24 PR 1. iPad, the iOS app on a Mac, Android, desktop and TV keep the
/// plain bar. The shared row style above is not gated by this.
bool settingsStudioHeaderApplies(BuildContext context) =>
    !PlatformDetector.isTV() &&
    Theme.of(context).platform == TargetPlatform.iOS &&
    !TvDetectionService.isIOSAppOnMacSync() &&
    PlatformDetector.isPhone(context);

/// Ink of a destructive row's title (Cache wissen, Instellingen herstellen,
/// a source removed): the Studio coral inside Instellingen, as the series
/// draws it (#FF715A dark, #C94E3C light), the theme's error colour elsewhere.
Color settingsDestructiveInk(BuildContext context) {
  if (SettingsStudioTheme.isActive(context)) return settingsStudioSwitchColor(tokens(context));
  return Theme.of(context).colorScheme.error;
}

/// Ink of an accent label inside Instellingen ("Live voorbeeld"): the same
/// Studio coral the series uses for it, the brand accent elsewhere.
Color settingsAccentInk(BuildContext context) {
  if (SettingsStudioTheme.isActive(context)) return settingsStudioSwitchColor(tokens(context));
  return tokens(context).accent;
}
