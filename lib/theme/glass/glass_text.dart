import 'package:flutter/widgets.dart';

/// Text/icon shadows for glass surfaces (`docs/liquid-glass-mockups-2026-09.md`,
/// De CSS-recepten): `text-shadow: 0 0 1px rgba(0,0,0,.45), 0 1px 8px rgba(0,0,0,.45)`.
/// Without these, white text on the lightest fixtures (Big Buck Bunny, Coffee
/// Run) drops under 3:1 contrast — see `glass_contrast_test.dart`.
const List<Shadow> kGlassTextShadows = [
  Shadow(blurRadius: 1, color: Color(0x73000000)),
  Shadow(offset: Offset(0, 1), blurRadius: 8, color: Color(0x73000000)),
];

/// [base] with [kGlassTextShadows] applied. Skip this for prominent-glass
/// text (`GlassTokens.prominent`), which is black on a near-opaque white
/// plate and needs no shadow.
TextStyle glassText(TextStyle base) => base.copyWith(shadows: kGlassTextShadows);

/// Same drop shadow as [kGlassTextShadows], for icons drawn directly on
/// glass (the CSS recipe applies one `text-shadow` to "tekst en iconen op
/// glas" alike).
List<Shadow> get kGlassIconShadows => kGlassTextShadows;
