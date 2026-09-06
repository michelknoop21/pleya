import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';

/// VLC-style dark pill shown at top-center of the video player.
/// Used for rate changes and other transient in-player notifications.
///
/// The zone is the one the presentation contract of DEC-096 lid 10 points at
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

  /// An amber dot instead of the glyph, for a notice about something the
  /// viewer did not ask for — the missing-language toast of 31 D. Deliberately
  /// a dot and not a colour on the text: the pill sits over a picture, and a
  /// tinted sentence is the first thing to lose against a bright frame.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final detailLine = detail;
    return Align(
      alignment: .topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          margin: const EdgeInsets.only(top: 20),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: detailLine == null ? 6 : 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: const BorderRadius.all(Radius.circular(20)),
          ),
          child: Row(
            mainAxisSize: .min,
            crossAxisAlignment: detailLine == null ? .center : .start,
            children: [
              if (accent)
                Container(
                  // Margin rather than a Padding wrapper; a Container lays the
                  // margin outside its own box, which is what the wrapper did.
                  margin: const EdgeInsets.only(top: 5, right: 2),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Color(0xFFF5A623), shape: BoxShape.circle),
                )
              else
                AppIcon(icon, fill: 1, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      text,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: .bold),
                    ),
                    if (detailLine != null)
                      Text(
                        detailLine,
                        maxLines: 2,
                        overflow: .ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5),
                      ),
                  ],
                ),
              ),
            ],
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
