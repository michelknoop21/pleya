import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_entitlement.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_theme.dart';
import '../../widgets/big_p/big_p_avatar.dart';
import 'big_p_mobile_session.dart';

/// Whether an action bar gives Big P a slot at all. A slot for a button that
/// shrinks to nothing would still take keyboard and D-pad focus, so a bar
/// leaves it out without the rollout flag and while he is hidden.
bool showsBigPAction({required bool rolloutEnabled, required AssistantAvailability? availability}) =>
    rolloutEnabled && availability != null && availability != AssistantAvailability.hidden;

/// Big P's face in the mobile page header (39 A), between search and the
/// profile avatar. A tap brings him out; while he is out the button is an
/// empty ring (39 B). A confirmation that came in while he was parked shows
/// a dot: he never comes out by himself.
class BigPFaceButton extends StatefulWidget {
  const BigPFaceButton({super.key});

  @override
  State<BigPFaceButton> createState() => _BigPFaceButtonState();
}

class _BigPFaceButtonState extends State<BigPFaceButton> {
  @override
  void initState() {
    super.initState();
    // R1: one light read when the header first shows, and none without the flag.
    if (AssistantEntitlement.rolloutEnabled) {
      final session = context.read<BigPMobileSession?>();
      if (session != null) unawaited(session.controller.refreshAvailability());
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<BigPMobileSession?>();
    if (session == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: session.controller,
      builder: (context, _) {
        if (session.controller.availability == AssistantAvailability.hidden) return const SizedBox.shrink();
        final out = session.stage == BigPStage.out;
        return AutomationNode(
          id: AutomationIds.bigpFaceButton,
          role: 'button',
          state: () => {'active': out, 'waiting': session.waiting},
          // Out reads as on; a waiting card is said, not only dotted.
          child: MergeSemantics(
            child: Semantics(
              toggled: out,
              value: session.waiting ? t.assistant.mobile.notConfirmedYet : null,
              child: IconButton(
                tooltip: t.assistant.mobile.faceButton,
                onPressed: out ? session.park : session.summon,
                icon: _Face(out: out, waiting: session.waiting),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.out, required this.waiting});

  final bool out;
  final bool waiting;

  static const _size = 40.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: out
                    ? null
                    : const RadialGradient(center: Alignment(0, -0.3), colors: [Color(0xFF3A1210), Color(0xFF1A0605)]),
                border: Border.all(
                  color: out ? const Color(0xB3FFB020) : const Color(0x38FFFFFF),
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: out
                  ? null
                  : ClipOval(
                      child: OverflowBox(
                        maxWidth: 56,
                        maxHeight: 56,
                        alignment: const Alignment(0, -0.2),
                        child: const BigPPortrait(focused: false, size: 56),
                      ),
                    ),
            ),
          ),
          if (waiting)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                key: const ValueKey('bigp-face-waiting'),
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: kAccentAlt,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 2, strokeAlign: BorderSide.strokeAlignOutside),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
