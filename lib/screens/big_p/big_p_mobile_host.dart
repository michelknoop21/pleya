/// Big P out of his face button on iPhone (39 B, C, D): the screen dims, he
/// hops in bottom right above the tab bar and talks from a balloon above him,
/// with the question field under him. A tap on the dim parks him.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_controller.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../profiles/active_profile_provider.dart';
import '../../widgets/big_p/assistant/big_p_labels.dart';
import '../../widgets/big_p/assistant/big_p_voice_mouth.dart';
import '../../widgets/big_p/big_p_avatar.dart';
import '../../widgets/big_p/big_p_balloon.dart';
import '../../widgets/big_p/big_p_scale.dart';
import '../settings/assistant_settings_screen.dart';
import 'big_p_input_bar.dart';
import 'big_p_mobile_conversation.dart';
import 'big_p_mobile_session.dart';

/// Above the mobile main scaffold, tab bar included. Nothing without a
/// [BigPMobileSession] (Android, desktop, TV, the iOS app on a Mac), and
/// nothing mounted, so no ticker, while he is parked.
class BigPMobileHost extends StatefulWidget {
  const BigPMobileHost({super.key});

  /// The tab bar's height above the safe area (`mobile_tab_bar_theme.dart`).
  static const tabBarHeight = 64.0;

  @override
  State<BigPMobileHost> createState() => _BigPMobileHostState();
}

class _BigPMobileHostState extends State<BigPMobileHost> {
  bool _open = false;
  bool _shown = false;
  Timer? _leave;

  @override
  void dispose() {
    _leave?.cancel();
    super.dispose();
  }

  Duration _motion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : const Duration(milliseconds: 380);

  /// Follows the session's stage: in after one frame (so the slide runs),
  /// out over [_motion] before he is unmounted.
  void _follow(BigPMobileSession session) {
    final out = session.stage == BigPStage.out;
    final motion = _motion(context);
    if (out && !_open) {
      _leave?.cancel();
      _open = true;
      _shown = motion == Duration.zero;
      if (!_shown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _open) setState(() => _shown = true);
        });
      }
    } else if (out && !_shown) {
      _leave?.cancel();
      _shown = true;
    } else if (!out && _shown) {
      _shown = false;
      if (motion == Duration.zero) {
        _open = false;
      } else {
        _leave = Timer(motion, () {
          if (mounted) setState(() => _open = false);
        });
      }
    }
  }

  /// 39 C: one way on. Big P steps back into his button while the settings
  /// are open, and the gate is read again when they close.
  Future<void> _setup(BigPMobileSession session) async {
    session.park();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AssistantSettingsScreen()));
    await session.controller.refreshAvailability();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<BigPMobileSession?>();
    if (session == null) return const SizedBox.shrink();
    _follow(session);
    if (!_open) return const SizedBox.shrink();
    final motion = _motion(context);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom > 0;
    final bottom = keyboard ? media.viewInsets.bottom + 8 : BigPMobileHost.tabBarHeight + media.viewPadding.bottom;
    return ListenableBuilder(
      listenable: session.controller,
      builder: (context, _) {
        final c = session.controller;
        final ready = c.availability == AssistantAvailability.ready;
        // Above the Scaffold: the field and the ink need their own Material.
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('bigp-dim'),
                  behavior: HitTestBehavior.opaque,
                  // Ignored while a confirmation waits (session.park).
                  onTap: session.park,
                  child: AnimatedOpacity(
                    opacity: _shown ? 1 : 0,
                    duration: motion,
                    child: const ColoredBox(color: Color(0x99000000)),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                top: media.viewPadding.top + 40,
                bottom: bottom,
                child: AnimatedSlide(
                  offset: _shown ? Offset.zero : const Offset(0.35, 0),
                  duration: motion,
                  curve: _shown ? Curves.easeOutBack : Curves.easeIn,
                  child: AnimatedOpacity(
                    opacity: _shown ? 1 : 0,
                    duration: motion,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(child: _balloon(context, session)),
                        Align(
                          alignment: Alignment.centerRight,
                          child: RepaintBoundary(
                            child: BigPVoiceMouth(
                              controller: c,
                              builder: (line) => BigPAvatar(
                                mood: ready ? bigPMood(c) : BigPMood.attentive,
                                // 190 pt wide, as in 39 B.
                                size: 237,
                                talkingText: line,
                              ),
                            ),
                          ),
                        ),
                        if (ready) ...[const SizedBox(height: 4), BigPInputBar(session: session)],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _balloon(BuildContext context, BigPMobileSession session) {
    final c = session.controller;
    return AutomationNode(
      id: AutomationIds.bigpBalloon,
      role: 'region',
      state: () => {
        'shown': _shown,
        'availability': c.availability.name,
        'state': c.state.name,
        'error': c.resultIsError,
        'pending': c.pending != null,
      },
      child: BigPBalloon(
        // Over Big P's head, a little right of his middle.
        tailAt: 0.81,
        child: BigPScale(
          pt: 0.53,
          child: BigPMobileConversation(
            controller: c,
            name: context.watch<ActiveProfileProvider?>()?.active?.displayName ?? '',
            onExample: (question) {
              c.beginListening(context: session.pendingContext);
              unawaited(c.submit(question));
            },
            onSetup: () => unawaited(_setup(session)),
          ),
        ),
      ),
    );
  }
}
