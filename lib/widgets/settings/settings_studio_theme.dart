/// A-24b: the Apple TV+ Studio palette of Instellingen, and only of
/// Instellingen.
///
/// Michel's decision (24 October 2026): the warm off-white belongs to the
/// settings pages, their subpages included, and nowhere else. Home, Mijn
/// Pleya, the catalogue and the player keep `monoTheme`. So this is not a
/// fourth theme: it is a wrapper that re-tints the [MonoTokens] a settings
/// page reads, and [settingsStudioRoute] carries it to every page a settings
/// page opens.
///
/// Per palette, measured on the anchors (`01`-`04` of the Studio package):
///
/// * Light: page #F9F5F2, card #FFFDFB, a warm hairline, and a peach wash in
///   the top-right corner on TV.
/// * Dark: the page stays #141414 (the decision names light only; warm dark
///   is the wash and a warmer card, nothing more), the card warms to #251D23,
///   and a wine wash sits top right on TV.
/// * OLED: the page stays pure black and gets no wash; only the card warms.
///
/// Switches take the anchors' coral instead of the brand red, on every
/// platform; TV keeps its own off-state styling (`TvSwitchTheme`). Off TV the
/// rows draw line icons instead of badges ([SettingsIconStyle.line]).
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/platform_detector.dart';
import 'settings_icon_badge.dart';

/// Light page, card and raised fill (anchor `03`/`04`: #F9F5F2, #FFFDFB).
const Color kStudioLightPage = Color(0xFFF9F5F2);
const Color kStudioLightCard = Color(0xFFFFFDFB);
const Color kStudioLightElevated = Color(0xFFF1E8E3);

/// A warm brown hairline at the alpha of the light outline (10%), so cards
/// and rows separate on the off-white without a grey line.
const Color kStudioLightHairline = Color(0x1F5C3B2E);

/// Dark card and raised fill: the anchor's wine-tinted card (#231B22 on
/// #110C10) moved onto the unchanged #141414 page.
const Color kStudioDarkCard = Color(0xFF251D23);
const Color kStudioDarkElevated = Color(0xFF342930);
const Color kStudioDarkHairline = Color(0x1FFFE2D8);

/// OLED card: one step off black like `kSettingsOledCardColor`, now warm.
const Color kStudioOledCard = Color(0xFF1E171B);

/// Switch track when on: coral in Dark and OLED, a deeper coral in Light
/// (the anchors' #FF715A and #C94E3C). Off keeps the theme's own colours.
const Color kStudioSwitchDark = Color(0xFFFF715A);
const Color kStudioSwitchLight = Color(0xFFC94E3C);

/// The wash in the top-right corner of a TV settings page, and how far it
/// reaches. Light: peach, measured at #F5E6E0 on #F9F5F2. Dark: wine,
/// measured at #2B161B on the anchor's page. OLED: none.
const Color kStudioWashLight = Color(0x40E9B9A6);
const Color kStudioWashDark = Color(0x615C1F2B);
const double kStudioWashRadius = 1.1;

bool _isOled(MonoTokens tk) => tk.bg.toARGB32() == 0xFF000000;

/// The Studio version of [base]: same type, text, radii and timings; page,
/// card, raised fill and hairline re-tinted per palette.
MonoTokens settingsStudioTokens(MonoTokens base) {
  if (base.isLight) {
    return base.copyWith(
      bg: kStudioLightPage,
      surface: kStudioLightCard,
      surfaceElevated: kStudioLightElevated,
      outline: kStudioLightHairline,
    );
  }
  if (_isOled(base)) {
    return base.copyWith(surface: kStudioOledCard, outline: kStudioDarkHairline);
  }
  return base.copyWith(surface: kStudioDarkCard, surfaceElevated: kStudioDarkElevated, outline: kStudioDarkHairline);
}

/// The wash for [tk]'s palette, or null on OLED, whose page stays black.
Color? settingsStudioWash(MonoTokens tk) {
  if (tk.isLight) return kStudioWashLight;
  if (_isOled(tk)) return null;
  return kStudioWashDark;
}

/// Coral of an "on" switch track for [tk]'s palette.
Color settingsStudioSwitchColor(MonoTokens tk) => tk.isLight ? kStudioSwitchLight : kStudioSwitchDark;

/// Wraps a settings page in the Studio palette and paints its page: the
/// page colour, plus on TV the corner wash. Idempotent: inside another
/// [SettingsStudioTheme] it returns [child] unchanged.
class SettingsStudioTheme extends StatelessWidget {
  const SettingsStudioTheme({super.key, required this.child});

  final Widget child;

  /// Whether [context] sits inside a Studio settings page.
  static bool isActive(BuildContext context) => context.getInheritedWidgetOfExactType<_StudioScope>() != null;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final mono = base.extension<MonoTokens>();
    if (mono == null || isActive(context)) return child;
    final studio = settingsStudioTokens(mono);
    final wash = PlatformDetector.isTV() ? settingsStudioWash(studio) : null;
    // Ink (ListTile fills, ripples) paints on the nearest Material, so one sits
    // above the page paint; otherwise the page colour would hide it.
    // Off TV the rows take the Studio line icons (anchor `01`); TV keeps its
    // badges until its own rows are redrawn.
    final rows = PlatformDetector.isTV() ? child : SettingsIconStyleScope(style: SettingsIconStyle.line, child: child);
    final content = Material(type: MaterialType.transparency, child: rows);
    return _StudioScope(
      child: Theme(
        data: _studioThemeData(base, studio),
        child: DecoratedBox(
          decoration: BoxDecoration(color: studio.bg),
          position: DecorationPosition.background,
          child: wash == null
              ? content
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: kStudioWashRadius,
                      colors: [wash, wash.withValues(alpha: 0)],
                    ),
                  ),
                  child: content,
                ),
        ),
      ),
    );
  }
}

ThemeData _studioThemeData(ThemeData base, MonoTokens studio) {
  final coral = settingsStudioSwitchColor(studio);
  final inherited = base.switchTheme;
  bool on(Set<WidgetState> states) => states.contains(WidgetState.selected) && !states.contains(WidgetState.disabled);
  return base.copyWith(
    scaffoldBackgroundColor: studio.bg,
    appBarTheme: base.appBarTheme.copyWith(backgroundColor: studio.bg),
    // monoTheme maps every container role onto the surface (DEC-053); the
    // Studio surface takes the same roles, so nothing reads the old card.
    colorScheme: base.colorScheme.copyWith(
      surface: studio.surface,
      primaryContainer: studio.surface,
      secondaryContainer: studio.surface,
      surfaceContainerHighest: studio.surface,
      surfaceBright: studio.surface,
      outline: studio.outline,
    ),
    dividerColor: studio.outline,
    dividerTheme: base.dividerTheme.copyWith(color: studio.outline),
    cardTheme: base.cardTheme.copyWith(color: studio.surface),
    dialogTheme: base.dialogTheme.copyWith(backgroundColor: studio.surface),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(backgroundColor: studio.surface),
    switchTheme: inherited.copyWith(
      trackColor: WidgetStateProperty.resolveWith((s) => on(s) ? coral : inherited.trackColor?.resolve(s)),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => on(s) ? Colors.transparent : inherited.trackOutlineColor?.resolve(s),
      ),
      thumbColor: WidgetStateProperty.resolveWith((s) => on(s) ? Colors.white : inherited.thumbColor?.resolve(s)),
    ),
    extensions: [
      for (final extension in base.extensions.values)
        if (extension is! MonoTokens) extension,
      studio,
    ],
  );
}

class _StudioScope extends InheritedWidget {
  const _StudioScope({required super.child});

  @override
  bool updateShouldNotify(_StudioScope oldWidget) => false;
}

/// [builder] as a page that keeps the Studio palette when [context] has it:
/// a settings page opening another settings page. From anywhere else it is
/// the plain [builder], so a screen that Mijn Pleya also opens keeps
/// `monoTheme` there.
WidgetBuilder settingsStudioBuilder(BuildContext context, WidgetBuilder builder) {
  if (!SettingsStudioTheme.isActive(context)) return builder;
  return (context) => SettingsStudioTheme(child: builder(context));
}

/// The [MaterialPageRoute] for [builder], through [settingsStudioBuilder].
MaterialPageRoute<T> settingsStudioRoute<T>(BuildContext context, WidgetBuilder builder) =>
    MaterialPageRoute<T>(builder: settingsStudioBuilder(context, builder));
