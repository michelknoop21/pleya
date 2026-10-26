/// A-24 (Apple TV+ Studio) colours for the TV settings pages: the category
/// rail, the detail rows and the preview card.
///
/// One rule runs through all of it: the focus ring belongs to
/// `FocusableWrapper` and appears on exactly one control. The chosen category
/// says so with a secondary mark, a brand-red bar on its leading edge over a
/// warm fill, so it never reads as a second focus.
///
/// Every helper takes the palette's [MonoTokens], so Light, Dark and OLED each
/// get their own values. Fills are translucent and composite on the page.
/// The contrast test in `test/widgets/tv_settings_studio_contrast_test.dart`
/// measures these exact functions.
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import 'tv_unified_layout.dart';

/// Width of the selected category's leading bar, in HIG points.
const double kTvStudioMarkerWidthPt = 5;

/// Section heading ink in Light: the warm brick of the Studio anchors, the
/// same value the phone pages use (5.9:1 on the light page).
const Color kTvStudioEyebrowLight = Color(0xFFA0432A);

/// Section heading ink in Dark and OLED: a soft coral, the anchors' eyebrow.
const Color kTvStudioEyebrowDark = Color(0xFFF2937A);

bool _isOled(MonoTokens tk) => tk.bg.toARGB32() == 0xFF000000;

/// Fill of a category pill, translucent over whatever the shell paints.
///
/// Idle has none: the rail is a list, and a fill on every entry made it read
/// as a stack of buttons. An opaque `bg` would not do either: the shell's
/// page is a shade off the palette's `bg`, which showed as faint boxes.
/// Focused takes the hub's focused tile fill under the ring. Selected is the
/// warm Studio fill whether or not it is focused; the ring is what tells
/// focus apart.
Color tvStudioCategoryFill(MonoTokens tk, {required bool selected, required bool focused}) {
  if (selected) return tvStudioSelectedFill(tk);
  if (focused) return tk.text.withValues(alpha: TvMyPleyaLayout.tileFocusedFillAlpha);
  return Colors.transparent;
}

/// The chosen category's fill: brand red over the page in Light, over a
/// lifted surface in Dark and OLED so it still separates from black.
Color tvStudioSelectedFill(MonoTokens tk) {
  if (tk.isLight) return tk.accent.withValues(alpha: 0.11);
  final lift = tk.text.withValues(alpha: _isOled(tk) ? 0.10 : 0.08);
  return Color.alphaBlend(tk.accent.withValues(alpha: 0.12), lift);
}

/// The bar in Dark and OLED: the brand red one step lighter. The brand red
/// itself measures 2.98:1 on the dark selected fill, under the 3:1 a
/// non-text mark needs.
const Color kTvStudioMarkerDark = Color(0xFFFF4A3D);

/// The selected category's leading bar.
Color tvStudioMarkerColor(MonoTokens tk) => tk.isLight ? tk.accent : kTvStudioMarkerDark;

/// Label ink on the rail. The chosen and the focused entry are full ink; the
/// rest step back so the rail reads as an index next to the rows.
Color tvStudioCategoryLabel(MonoTokens tk, {required bool selected, bool focused = false}) =>
    selected || focused ? tk.text : tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary);

/// The eyebrow above the rows: the category name in the Studio accent ink.
Color tvStudioEyebrow(MonoTokens tk) => tk.isLight ? kTvStudioEyebrowLight : kTvStudioEyebrowDark;

/// Fill of a detail row. Rows sit on the page with a hairline between them;
/// the focused row lifts to white in Light (anchor 04) and to a light veil in
/// Dark and OLED, under the ring.
Color tvStudioRowFill(MonoTokens tk, {required bool focused}) {
  if (!focused) return Colors.transparent;
  if (tk.isLight) return tk.surface;
  return tk.text.withValues(alpha: _isOled(tk) ? 0.12 : 0.10);
}

/// Hairline between rows and between idle categories.
Color tvStudioSeparator(MonoTokens tk) => tk.outline;

/// The preview card: white on the light page, a faint veil in Dark, and one
/// step lighter on OLED, where a veil over black disappears.
Color tvStudioPreviewFill(MonoTokens tk) {
  if (tk.isLight) return tk.surface;
  return tk.text.withValues(alpha: _isOled(tk) ? 0.08 : 0.05);
}
