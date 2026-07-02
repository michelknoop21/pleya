import 'package:flutter/material.dart';
import 'gapped_track_shape.dart';
import 'mono_tokens.dart';

/// PlexFlix brand accent (Netflix-style red). Applied sparingly.
const Color kAccent = Color(0xFFE50914);

ThemeData monoTheme({required bool dark, bool oled = false}) {
  // Netflix-2026 palette. Dark is the design target (#141414); OLED stays pure
  // black; light remains functional with a neutral re-tint only.
  final ({Color bg, Color surface, Color surfaceElevated, Color outline, Color text, Color textMuted}) c;
  if (oled) {
    c = (
      bg: const Color(0xFF000000), // Pure black for OLED
      surface: const Color(0xFF141414), // Netflix dark as the elevated tier
      surfaceElevated: const Color(0xFF2F2F2F),
      outline: const Color(0x1FFFFFFF),
      text: const Color(0xFFFFFFFF),
      textMuted: const Color(0xB3FFFFFF),
    );
  } else if (dark) {
    c = (
      bg: const Color(0xFF141414),
      surface: const Color(0xFF1F1F1F),
      surfaceElevated: const Color(0xFF2F2F2F),
      outline: const Color(0x1FFFFFFF),
      text: const Color(0xFFFFFFFF),
      textMuted: const Color(0xB3FFFFFF),
    );
  } else {
    c = (
      bg: const Color(0xFFF7F7F8),
      surface: const Color(0xFFFFFFFF),
      surfaceElevated: const Color(0xFFEDEDED),
      outline: const Color(0x19000000),
      text: const Color(0xFF111111),
      textMuted: const Color(0x99111111),
    );
  }

  final isDark = dark || oled;
  final clickableCursor = WidgetStateProperty.resolveWith<MouseCursor>(
    (states) => states.contains(WidgetState.disabled) ? MouseCursor.defer : SystemMouseCursors.click,
  );

  // Netflix Play/More-Info buttons: square-ish corners (radius 4), primary is
  // white-on-black. Secondary actions get a translucent grey fill elsewhere.
  final buttonStyle = ButtonStyle(
    mouseCursor: clickableCursor,
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
    elevation: const WidgetStatePropertyAll(0),
    backgroundColor: WidgetStatePropertyAll(c.text),
    foregroundColor: WidgetStatePropertyAll(isDark ? c.bg : Colors.white),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
    ),
  );

  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    brightness: isDark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: c.text,
      onPrimary: isDark ? c.bg : Colors.white,
      secondary: c.text,
      onSecondary: c.bg,
      surface: c.surface,
      onSurface: c.text,
      error: const Color(0xFFB00020),
      onError: Colors.white,
      tertiary: c.text,
      onTertiary: c.bg,
      primaryContainer: c.surface,
      onPrimaryContainer: c.text,
      secondaryContainer: c.surface,
      onSecondaryContainer: c.text,
      surfaceContainerHighest: c.surface,
      surfaceContainerLow: c.bg,
      surfaceDim: c.bg,
      surfaceBright: c.surface,
      outline: c.outline,
      shadow: Colors.transparent,
      scrim: Colors.black,
      inverseSurface: c.text,
      onInverseSurface: c.bg,
      inversePrimary: c.bg,
    ),
    // remove "Material feel"
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: c.outline,
    scaffoldBackgroundColor: c.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: c.text,
      titleTextStyle: TextStyle(color: c.text, fontSize: 18, fontWeight: .w700, letterSpacing: -0.2),
    ),
    textTheme: Typography.englishLike2021
        .apply(bodyColor: c.text, displayColor: c.text)
        .copyWith(
          displayLarge: const TextStyle(fontWeight: .w700, letterSpacing: -0.5),
          titleMedium: const TextStyle(fontWeight: .w600),
          bodyMedium: TextStyle(color: c.text),
          bodySmall: TextStyle(color: c.textMuted),
        ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: .zero,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
    ),
    inputDecorationTheme: _inputDecorationTheme(c.text, c.textMuted),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
    sliderTheme: SliderThemeData(
      trackHeight: 16,
      trackGap: 6,
      thumbSize: const WidgetStatePropertyAll(Size(4, 20)),
      thumbShape: const HandleThumbShape(),
      trackShape: const GappedTrackShape(),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
      // ignore: deprecated_member_use — opting into the 2024 slider appearance until the default flips
      year2023: false,
    ),
    dividerTheme: DividerThemeData(space: 0, thickness: 1, color: c.outline),
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      iconColor: c.text,
      textColor: c.text,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg,
      elevation: 0,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(TextStyle(color: c.textMuted, fontSize: 11)),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return IconThemeData(opacity: active ? 1 : 0.6, size: 22, color: c.text);
      }),
    ),
    // Floating snackbars auto-offset above the Scaffold's bottom NavigationBar,
    // so they don't cover it on mobile. Background color tracks the theme to
    // avoid jarring brightness on HDR playback / dark mode.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surface,
      contentTextStyle: TextStyle(color: c.text),
      actionTextColor: c.text,
      elevation: 6,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      insetPadding: const EdgeInsets.all(16),
    ),
  );

  return base.copyWith(
    extensions: [
      MonoTokens(
        radiusSm: 8,
        radiusMd: 12,
        space: 12,
        fast: const Duration(milliseconds: 120),
        normal: const Duration(milliseconds: 200),
        slow: const Duration(milliseconds: 300),
        bg: c.bg,
        surface: c.surface,
        surfaceElevated: c.surfaceElevated,
        outline: c.outline,
        text: c.text,
        textMuted: c.textMuted,
        accent: kAccent,
        splashFactory: NoSplash.splashFactory,
      ),
    ],
  );
}

/// Brighter fill on focus so input focus is visible inside TV overscan.
InputDecorationTheme _inputDecorationTheme(Color text, Color textMuted) {
  final unfocusedFill = text.withValues(alpha: 0.08);
  final focusedFill = text.withValues(alpha: 0.18);
  const border = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide.none);
  return InputDecorationTheme(
    filled: true,
    fillColor: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.focused) ? focusedFill : unfocusedFill,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border,
    hintStyle: TextStyle(color: textMuted),
  );
}
