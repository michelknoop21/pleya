import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../utils/layout_constants.dart';
import '../../../utils/platform_detector.dart';
import '../../tv/tv_unified_layout.dart';
import '../film_frame_palette.dart';

/// Filmbeeld notice shown at the top of the video player.
/// Used for rate changes and other transient in-player notifications.
///
/// The zone is the one the presentation contract of DEC-109 lid 10 points at
/// and does not move: `video_controls.dart` puts it in a `Positioned.fill`
/// under an `IgnorePointer`, so it never takes focus and never swallows a
/// press, and subtitles live at the bottom under `sub-pos` where this cannot
/// reach them.
class PlayerToastIndicator extends StatelessWidget {
  const PlayerToastIndicator({super.key, required this.icon, required this.text, this.detail, this.accent = false});

  final IconData icon;
  final String text;

  /// The second line of mockups 31 C and 31 D: what the first line means for
  /// the next episode. Null keeps the one-line pill every existing caller
  /// shows.
  final String? detail;

  /// Warning tone for a playback change the viewer did not request.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final scale = isTv ? TvLayoutConstants.scaleOf(context) : 1.0;
    final tone = accent ? const Color(0xFFFFD18C) : kFilmFocus;
    return Align(
      alignment: .topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Semantics(
          liveRegion: true,
          child: Container(
            margin: EdgeInsets.only(
              top: isTv ? TvCatalogLayout.topSafeInset * scale : MediaQuery.paddingOf(context).top + 14,
            ),
            padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
            decoration: BoxDecoration(
              color: const Color(0xF716242B),
              border: Border.all(color: const Color(0x8A6C8C92)),
              borderRadius: BorderRadius.circular(12 * scale),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: Row(
              mainAxisSize: .min,
              crossAxisAlignment: .center,
              children: [
                Container(
                  width: 30 * scale,
                  height: 30 * scale,
                  alignment: .center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(7 * scale),
                  ),
                  child: AppIcon(accent ? Symbols.warning_rounded : icon, fill: 1, color: tone, size: 17 * scale),
                ),
                SizedBox(width: 8 * scale),
                Flexible(
                  child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        text,
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 14 * scale, fontWeight: .bold),
                      ),
                      if (detail case final detail?)
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: .ellipsis,
                          style: TextStyle(color: const Color(0xFFC9D7DB), fontSize: 12.5 * scale),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Owns the currently-displayed toast + auto-hide timer.
/// Created per video-player session; disposed with the screen.
class PlayerToastController extends ChangeNotifier {
  ({IconData icon, String text, String? detail, bool accent})? _current;
  Timer? _timer;

  ({IconData icon, String text, String? detail, bool accent})? get current => _current;

  /// [duration] defaults to the rate-change pill's 1.2 seconds. A toast with a
  /// [detail] line is a sentence to read rather than a value to glance at, so
  /// the language notices pass the three seconds mockups 31 C and 31 D ask
  /// for; that stays the caller's decision instead of a branch in here.
  void show(
    IconData icon,
    String text, {
    String? detail,
    bool accent = false,
    Duration duration = const Duration(milliseconds: 1200),
  }) {
    _timer?.cancel();
    _current = (icon: icon, text: text, detail: detail, accent: accent);
    notifyListeners();
    _timer = Timer(duration, () {
      _current = null;
      _timer = null;
      notifyListeners();
    });
  }

  void hide() {
    _timer?.cancel();
    _timer = null;
    if (_current != null) {
      _current = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
