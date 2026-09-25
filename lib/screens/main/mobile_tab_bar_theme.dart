import 'package:flutter/material.dart';

import '../../theme/glass/glass_text.dart';
import '../../theme/mono_theme.dart' show kAccent;

/// The mobile bottom bar's own selected-slot colour: the active label turns
/// [kAccent], matching the active glyph `_TabIcon` already draws. iOS Unified
/// 2026 fase 1, `docs/ios-unified-2026-fase1-plan.md` stap 9.
///
/// Applied at the bar rather than in `monoTheme` on purpose: the theme's
/// `navigationBarTheme` is inherited by every `NavigationBar` in the app, and
/// this red is a decision about this one bar.
NavigationBarThemeData mobileTabBarTheme(NavigationBarThemeData base) {
  final baseLabel = base.labelTextStyle;
  return base.copyWith(
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final style = baseLabel?.resolve(states) ?? const TextStyle();
      return states.contains(WidgetState.selected) ? style.copyWith(color: kAccent) : style;
    }),
  );
}

/// [mobileTabBarTheme] for the floating glass bar (mockup LG-01): labels and
/// glyphs full white with the glass drop shadow instead of the theme's 60%
/// grey. Only the active glyph stays [kAccent] (`_TabIcon` draws it); its
/// label is white too, since the red tops out at 4.36:1 even on black and a
/// label needs 4.5 (Michel, fixronde 1). The plate itself is the background,
/// so the bar paints none of its own. Keeps a caller's compact height (56
/// with hidden labels). [labelColor] is for the contrast test only.
NavigationBarThemeData mobileGlassTabBarTheme(NavigationBarThemeData base, {Color labelColor = Colors.white}) {
  final baseLabel = base.labelTextStyle;
  final baseIcon = base.iconTheme;
  return base.copyWith(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    indicatorColor: Colors.transparent,
    elevation: 0,
    height: base.height ?? 64,
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final style = baseLabel?.resolve(states) ?? const TextStyle();
      return glassText(style.copyWith(color: labelColor));
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final icon = baseIcon?.resolve(states) ?? const IconThemeData();
      return icon.copyWith(opacity: 1, color: Colors.white, shadows: kGlassIconShadows);
    }),
  );
}
