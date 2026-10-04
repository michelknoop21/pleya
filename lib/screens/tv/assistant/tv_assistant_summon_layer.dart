import 'package:flutter/material.dart';

import '../../../utils/tv_hig.dart';
import '../../../widgets/big_p/big_p_balloon.dart';

/// Where summoned Big P stands: the screen behind dimmed, the 760 pt speech
/// balloon with its tail toward Big P bottom right (39 J), sliding in from
/// the right and above the system keyboard while listening (38-motion-0).
class TvAssistantSummonLayer extends StatelessWidget {
  const TvAssistantSummonLayer({
    super.key,
    required this.shown,
    required this.listening,
    required this.motion,
    required this.panel,
    required this.avatar,
    required this.avatarHeight,
  });

  final bool shown;
  final bool listening;
  final Duration motion;

  /// The conversation, or null when no controller is attached.
  final Widget? panel;
  final Widget avatar;

  /// Big P's height in pt, for where the tail points.
  final double avatarHeight;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final panel = this.panel;
    // The band the balloon may fill: its top 60 pt down (39 J), its bottom
    // level with Big P's feet, above the system keyboard while listening.
    const top = 60.0;
    final bottom = listening ? 430.0 : 130.0;
    return LayoutBuilder(
      builder: (context, box) {
        final band = box.maxHeight / pt - top - bottom;
        // The tail points at Big P's face, a third down his height.
        final tailAt = ((band - avatarHeight * 2 / 3) / band).clamp(0.15, 0.85);
        return Stack(
          children: [
            // The screen behind stays the context: dimmed, not hidden.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: shown ? 1 : 0,
                  duration: motion,
                  child: const ColoredBox(color: Color(0x66000000)),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: motion,
              curve: Curves.easeOutBack,
              top: top * pt,
              right: 40 * pt,
              bottom: bottom * pt,
              child: AnimatedSlide(
                offset: shown ? Offset.zero : const Offset(0.35, 0),
                duration: motion,
                curve: shown ? Curves.easeOutBack : Curves.easeIn,
                child: AnimatedOpacity(
                  opacity: shown ? 1 : 0,
                  duration: motion,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (panel != null)
                        SizedBox(
                          // 570 pt in mockup 38; widened on hardware feedback so
                          // results stay readable (3 Oct 2026).
                          width: 760 * pt,
                          // Aligned at the same fraction the tail sits at, the
                          // tail stays at one height whatever the balloon's.
                          child: Align(
                            alignment: Alignment(0, 2 * tailAt - 1),
                            child: BigPBalloon(
                              key: const ValueKey('assistant.summon.balloon'),
                              tail: AxisDirection.right,
                              tailAt: tailAt,
                              scale: 1.5 * pt,
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16) * (1.5 * pt),
                              child: panel,
                            ),
                          ),
                        ),
                      SizedBox(width: 24 * pt),
                      RepaintBoundary(child: avatar),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
