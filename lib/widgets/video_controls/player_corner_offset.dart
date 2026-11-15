import 'package:flutter/widgets.dart';

import '../../utils/platform_detector.dart';
import '../../utils/tv_hig.dart';
import '../tv/tv_page_surface.dart';
import 'film_frame_palette.dart';
import 'player_chrome_controller.dart';

/// Where the bottom-right player prompts sit: the skip intro/credits button,
/// the next-episode card and "still watching". One owner, so the card and the
/// skip button cannot drift apart again (DENS1, T7).
///
/// On a TV both keep the page inset at the side and the HIG's 60 pt title-safe
/// band at the bottom. With the chrome up they sit 10 above the bottom block
/// that the controls measured; on iPhone and iPad that is the Filmbeeld block,
/// so a card no longer lands on the footer buttons. Without a measurement
/// each prompt keeps its own [shownFallback].
///
/// `maxWidth` keeps a prompt clear of the centred transport group on a
/// landscape phone while the chrome is up: a 320 wide card reached over play
/// on an iPhone SE and over next on an 18 Pro Max (DENS1 review I3).
({double right, double bottom, double maxWidth}) playerCornerOffset(
  BuildContext context,
  PlayerChromeController chrome, {
  required bool controlsShown,
  double? shownFallback,
}) {
  final isTv = PlatformDetector.isTV();
  final isMobile = PlatformDetector.isMobile(context);
  final filmFrame = PlatformDetector.isHandheldIOS(context) && !TvDetectionService.isIOSAppOnMacSync();
  final padding = MediaQuery.paddingOf(context);

  final right = isTv ? tvPageInset(context) : 24.0 + (filmFrame ? padding.right : 0.0);

  double bottom() {
    if (!controlsShown) {
      if (isTv) return TvHig.titleSafeBottom * TvHig.of(context);
      return 24.0 + (filmFrame ? padding.bottom : 0.0);
    }
    if (!isMobile || filmFrame) {
      final block = chrome.subtitleLift * MediaQuery.sizeOf(context).height;
      if (block > 0) return block + 10;
    }
    if (chrome.contentStripVisible) return 180.0;
    return shownFallback ?? (isMobile ? 80.0 : 115.0);
  }

  var maxWidth = double.infinity;
  final size = MediaQuery.sizeOf(context);
  if (controlsShown && filmFrame && size.width > size.height) {
    const groupHalf = kFilmPlaySize / 2 + kFilmTransportGap + kFilmSkipSize;
    maxWidth = size.width / 2 - groupHalf - kFilmTransportGap - right;
  }

  return (right: right, bottom: bottom(), maxWidth: maxWidth);
}
