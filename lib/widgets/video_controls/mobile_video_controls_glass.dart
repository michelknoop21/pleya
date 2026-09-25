import 'package:flutter/material.dart';

import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_surface.dart';
import '../../theme/glass/glass_text.dart';

/// Glass pieces of the mobile player controls (mockup LG-03). Every helper
/// returns the exact pre-glass widget when glass is off, so the controls of
/// today stay untouched behind the setting.
bool playerGlassOn(BuildContext context) => glassTierFor(context) != GlassTier.off;

/// Tint for the player's plates. They render without a backdrop (see
/// [GlassSurface.backdrop]: the video is a native layer Flutter cannot
/// sample), so the scene shows through sharp and this fill alone carries the
/// contrast; it was sized on the Big Buck Bunny fixture
/// (`mobile_video_controls_glass_test.dart`). The white rim keeps it reading
/// as glass rather than a flat chip.
const GlassTokens kPlayerGlassTokens = GlassTokens(blur: 0, saturation: 1, dim: 1, tint: Color(0x8C000000), edge: 0.3);

/// A player plate of [shape]: translucent, no backdrop. [legacy] is what
/// renders with glass off.
Widget playerGlassSurface(ShapeBorder shape, Widget child, {Widget? legacy}) =>
    GlassSurface(shape: shape, tokens: kPlayerGlassTokens, backdrop: false, legacy: legacy, child: child);

/// The glass drop shadow for every text and icon in the mobile controls that
/// does not set its own. No `GlassLayer`: nothing in the player samples a
/// backdrop.
Widget playerGlassScope(BuildContext context, Widget child) {
  if (!playerGlassOn(context)) return child;
  return DefaultTextStyle.merge(
    style: const TextStyle(shadows: kGlassTextShadows),
    child: IconTheme.merge(
      data: IconThemeData(shadows: kGlassIconShadows),
      child: child,
    ),
  );
}

/// The header's trailing button row (cast, tracks, settings) in a capsule.
/// No inner padding: the 40px buttons fill the capsule's round ends, so no
/// button moves. Its icons drop the glass shadow, a workaround with a
/// partly understood cause: on the iOS simulator the shadows of this row
/// stayed on screen at its portrait position (x 121, y 106 pt) after the
/// player turned landscape, as a dark copy over the video
/// (`player-ghost-repro.png`). Hiding and showing the controls, or a hot
/// reload, cleared it; so stale paint, not layout. Why only shadows go stale
/// is open. The capsule's tint alone clears the 3:1 icon bar
/// (`mobile_video_controls_glass_test.dart`).
Widget playerGlassCapsule(Widget trailing) => playerGlassSurface(
  const StadiumBorder(),
  IconTheme.merge(
    data: const IconThemeData(shadows: []),
    child: trailing,
  ),
  legacy: trailing,
);

/// Outer inset of the bottom bar with glass on: 10 outside + 6 inside keeps
/// the timeline at the old height. Horizontally the plate keeps the old 16 pt
/// margin and the timeline sits another 16 pt inside it (LG-03).
const double _kPlateInnerV = 6;
const double _kPlateInnerH = 16;
const double _kPlateRadius = 22;

/// Timeline and timestamps on one glass plate. [child] is the timeline bar.
/// The progress stays `kAccent` and opaque: the slider paints it on top of
/// the plate, never through it. [childPadded]: [child] brings its own 16 pt
/// inset (`LiveTimelineBar`'s vertical layout), so glass off returns it bare
/// and the plate adds no inner padding.
Widget playerGlassPlate(BuildContext context, Widget child, {bool childPadded = false}) {
  if (!playerGlassOn(context)) return childPadded ? child : Padding(padding: const EdgeInsets.all(16), child: child);
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16 - _kPlateInnerV),
    child: playerGlassSurface(
      const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(_kPlateRadius))),
      childPadded
          ? child
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kPlateInnerH, vertical: _kPlateInnerV),
              child: child,
            ),
    ),
  );
}

/// The OSD scrim behind the controls. Glass on (mobile only): the plates
/// carry their own tint, so the bottom half of the scrim goes and only a top
/// band stays for the title, which sits on the bare scene. The band holds 55%
/// black over the title's height before it fades: on the Big Buck Bunny
/// fixture a plain 35% fade measured 2.2:1 for the title, today's 70% fade
/// 2.8:1, this band 5.5:1 (`mobile_video_controls_glass_test.dart`).
BoxDecoration playerOverlayScrim({required bool hasFrame, required bool glass}) {
  if (!hasFrame) return const BoxDecoration(color: Colors.black);
  if (glass) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black.withValues(alpha: 0.55), Colors.black.withValues(alpha: 0.55), Colors.transparent],
        stops: const [0.0, 0.15, 0.4],
      ),
    );
  }
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.black.withValues(alpha: 0.7),
        Colors.transparent,
        Colors.transparent,
        Colors.black.withValues(alpha: 0.7),
      ],
      stops: const [0.0, 0.2, 0.8, 1.0],
    ),
  );
}
