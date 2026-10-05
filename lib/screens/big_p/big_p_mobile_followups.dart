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

  /// None while working, after an error or while a confirmation or the
  /// ages card waits.
  static List<String> questions(AssistantController c) {
    if (c.state != AssistantSurfaceState.result || c.resultIsError || c.pending != null || c.kidsAgesPrompt != null) {
      return const [];
    }
    return BigPSuggestions.of(c).followUps(c);
  }

  @override
  Widget build(BuildContext context) {
    final questions = BigPMobileFollowUps.questions(controller);
    if (questions.isEmpty) return const SizedBox.shrink();
    final pills = [
      for (final (i, question) in questions.indexed)
        BigPChip(
          label: question,
          icon: Symbols.subdirectory_arrow_right_rounded,
          dense: true,
          fill: floating ? const Color(0xFF2A2E2E) : null,
          lift: floating ? _lift : null,
          automationId: AutomationIds.assistantFollowUp,
          automationInstance: '$i',
          onSelect: () => onAsk(question),
        ),
    ];
    // 14 pt pills, as `.fu .pill`. Each is a 44 pt touch target around the
    // 34 pt pill, so no gap is added between them.
    return BigPScale(
      pt: 0.6,
      child: floating
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: pills)
          : Wrap(spacing: 8, children: pills),
    );
  }

  /// `.fu.float`: a rim and a shadow lift the pill off the page.
  static const _lift = BoxDecoration(
    borderRadius: BorderRadius.all(Radius.circular(24)),
    border: Border.fromBorderSide(BorderSide(color: BigPBalloon.rim)),
    boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 8))],
  );
}
