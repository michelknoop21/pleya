import 'package:flutter/material.dart';

import '../../../utils/tv_hig.dart';
import '../../../widgets/big_p/assistant/big_p_assistant_widgets.dart';

/// Where summoned Big P stands: the screen behind dimmed, the 760 pt panel
/// and Big P bottom right, sliding in from the right and above the system
/// keyboard while listening (38-motion-0).
class TvAssistantSummonLayer extends StatelessWidget {
  const TvAssistantSummonLayer({
    super.key,
    required this.shown,
    required this.listening,
    required this.motion,
    required this.panel,
    required this.avatar,
  });

  final bool shown;
  final bool listening;
  final Duration motion;

  /// The conversation, or null when no controller is attached.
  final Widget? panel;
  final Widget avatar;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final panel = this.panel;
    return LayoutBuilder(
      builder: (context, box) => Stack(
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
            right: 40 * pt,
            bottom: (listening ? 430 : 60) * pt,
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
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: box.maxHeight - (listening ? 470 : 140) * pt),
                          child: BigPGlassPanel(child: panel),
                        ),
                      ),
                    RepaintBoundary(child: avatar),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
