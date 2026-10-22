import 'package:flutter/material.dart';

import '../../../theme/mono_theme.dart';

/// Fill of the round action buttons, the restart circle and the pills on the
/// iPhone detail page: dark and translucent, so the page gradient shows
/// through (Plex look, variant B).
const Color kDetailPillColor = Color(0x59000000);

/// Hairline around the pills and circles, so they still read on the darkest
/// part of the gradient.
const Color kDetailPillEdge = Color(0x14FFFFFF);

/// The page ground under the poster glow, top to bottom. The glow
/// (`DetailAmbientBackground`) carries the poster's own colours at the top;
/// this fixed dark gradient runs on to the bottom of the page.
const List<Color> kDetailPageGradient = [Color(0xFF1B1420), Color(0xFF261B33), Color(0xFF1F2C4A)];

/// The iPhone detail page is always dark, also when the app runs the light
/// theme. A dark app theme (dark or OLED) is kept as it is.
ThemeData mobileDetailTheme(ThemeData app) => app.brightness == Brightness.dark ? app : monoTheme(dark: true);

/// A dark translucent pill (meta scores, the activity card).
class DetailPill extends StatelessWidget {
  const DetailPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const ShapeDecoration(
        color: kDetailPillColor,
        shape: StadiumBorder(side: BorderSide(color: kDetailPillEdge)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
