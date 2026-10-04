import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../widgets/big_p/assistant/big_p_assistant_widgets.dart';
import '../../widgets/big_p/big_p_balloon.dart';
import '../../widgets/big_p/big_p_rig.dart';
import '../../widgets/big_p/big_p_scale.dart';
import 'big_p_mobile_session.dart';

/// 39 H: after a title from the answer opened, Big P peeks in at the bottom
/// right of its detail page with what is left of the answer. A tap goes back
/// to the first route and brings him out with that answer. Over the detail
/// page only (mediaDetailRoute): the player is a route of its own on top, so
/// he never floats over video. Nothing without a [BigPMobileSession].
class BigPDetailPeek extends StatelessWidget {
  const BigPDetailPeek({super.key});

  /// The `.peek` box: flush with the bottom right corner, Big P cut off by it.
  static const size = Size(80, 82);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<BigPMobileSession?>();
    if (session == null) return const SizedBox.shrink();
    return ListenableBuilder(
      // A pick running on after the park can change the titles.
      listenable: session.controller,
      builder: (context, _) {
        final remaining = session.remainingTitles;
        if (session.stage != BigPStage.peek || remaining == 0) return const SizedBox.shrink();
        // Out first: the host's didPopNext then finds him out and does not
        // park him, which would abort titles still coming in.
        void back() {
          session.summon();
          Navigator.of(context).popUntil((r) => r.isFirst);
        }

        // Beside the page's Scaffold, not in it: the pill needs its own
        // Material for its text style and ink.
        return Material(
          type: MaterialType.transparency,
          child: Align(
            alignment: Alignment.bottomRight,
            child: AutomationNode(
              id: AutomationIds.bigpPeek,
              role: 'button',
              state: () => {'remaining': remaining},
              child: GestureDetector(
                // Only the pill and Big P's box take a tap; the air
                // around them is the page's.
                behavior: HitTestBehavior.deferToChild,
                onTap: back,
                // Big P first, so the pill paints over his edge: it
                // reaches 6 pt into his box (`.peek-tip` right: 74).
                child: Stack(
                  children: [
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: ClipRect(
                        child: SizedBox.fromSize(
                          size: size,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // 170 wide at (-30, -12), turned 14 degrees
                              // back about its middle, as the CSS transform.
                              Positioned(
                                left: -30,
                                top: -12,
                                width: 170,
                                height: 170 * 700 / 560,
                                child: Transform.rotate(
                                  angle: -14 * pi / 180,
                                  child: Image.asset(bigPAsset('still-zwaaien'), fit: BoxFit.fill),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 26 pt off the bottom, 14 pt, as the follow-ups.
                        Padding(
                          padding: const EdgeInsets.only(bottom: 26),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: BigPBalloon.rim),
                            ),
                            child: BigPScale(
                              pt: 0.6,
                              child: BigPChip(
                                label: t.assistant.mobile.moreTitles(n: remaining),
                                icon: Symbols.subdirectory_arrow_right_rounded,
                                dense: true,
                                fill: const Color(0xF71F2323),
                                onSelect: back,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: size.width - 6, height: size.height),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
