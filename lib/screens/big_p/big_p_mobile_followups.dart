import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../assistant/assistant_controller.dart';
import '../../automation/automation_ids.dart';
import '../../widgets/big_p/assistant/big_p_assistant_widgets.dart';
import '../../widgets/big_p/assistant/big_p_suggestions.dart';
import '../../widgets/big_p/big_p_balloon.dart';
import '../../widgets/big_p/big_p_scale.dart';

/// The three follow-ups after an answer (39 E, F, I). On iPhone they float
/// in a column left of Big P, opaque over the page; on iPad they wrap
/// inside the balloon. A tap asks the question as the user's own.
class BigPMobileFollowUps extends StatelessWidget {
  const BigPMobileFollowUps({super.key, required this.controller, required this.onAsk, this.floating = false});

  final AssistantController controller;
  final ValueChanged<String> onAsk;
  final bool floating;

  /// None while working, after an error or while a confirmation waits.
  static List<String> questions(AssistantController c) {
    if (c.state != AssistantSurfaceState.result || c.resultIsError || c.pending != null) return const [];
    return BigPSuggestions.of(c).followUps(c);
  }

  @override
  Widget build(BuildContext context) {
    final questions = BigPMobileFollowUps.questions(controller);
    if (questions.isEmpty) return const SizedBox.shrink();
    final pills = [
      for (final (i, question) in questions.indexed)
        _pill(
          BigPChip(
            label: question,
            icon: Symbols.subdirectory_arrow_right_rounded,
            dense: true,
            fill: floating ? const Color(0xFF2A2E2E) : null,
            automationId: AutomationIds.assistantFollowUp,
            automationInstance: '$i',
            onSelect: () => onAsk(question),
          ),
        ),
    ];
    // 14 pt pills, as `.fu .pill`.
    return BigPScale(
      pt: 0.6,
      child: floating
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, pill) in pills.indexed) ...[if (i > 0) const SizedBox(height: 8), pill],
              ],
            )
          : Wrap(spacing: 8, runSpacing: 8, children: pills),
    );
  }

  /// `.fu.float`: a rim and a shadow lift the pill off the page.
  Widget _pill(Widget chip) => !floating
      ? chip
      : DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: BigPBalloon.rim),
            boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 8))],
          ),
          child: chip,
        );
}
