/// Big P out of his face button on iPhone (39 B to G): the screen dims, he
/// hops in bottom right above the tab bar and talks from a balloon above him,
/// with the question field under him. On iPad (39 I) the balloon stands
/// beside him. A tap on the dim parks him, unless a confirmation waits.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_tools.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../navigation/profile_navigation_scope.dart';
import '../../profiles/active_profile_provider.dart';
import '../../utils/media_navigation_helper.dart';
import '../../widgets/big_p/assistant/big_p_labels.dart';
import '../../widgets/big_p/assistant/big_p_voice_mouth.dart';
import '../../widgets/big_p/big_p_avatar.dart';
import '../../widgets/big_p/big_p_balloon.dart';
import '../../widgets/big_p/big_p_scale.dart';
import '../main/mobile_main_scaffold.dart';
import '../settings/assistant_settings_screen.dart';
import 'big_p_input_bar.dart';
import 'big_p_mobile_conversation.dart';
import 'big_p_mobile_followups.dart';
import 'big_p_mobile_session.dart';

/// Above the mobile main scaffold, tab bar included. Nothing without a
/// [BigPMobileSession] (Android, desktop, TV, the iOS app on a Mac), and
/// nothing mounted, so no ticker, while he is parked.
class BigPMobileHost extends StatefulWidget {
  const BigPMobileHost({super.key});

  /// From here on the iPad layout (39 I): balloon beside Big P.
  static const regularWidth = 700.0;

  /// The share of Big P's box above his head (the rig's own margin).
  static const headroom = 0.14;

  /// Big P's height in [room]: 237 (190 pt wide, as in 39 B) when it fits.
  /// With the keyboard up he shrinks so the balloon keeps 220 pt, room for
  /// the three examples, but never under 120 (an iPhone SE).
  static double avatarSize(double room, {required bool withBar}) =>
      (room - 220 - (withBar ? 50 : 0)).clamp(120.0, 237.0);

  @override
  State<BigPMobileHost> createState() => _BigPMobileHostState();
}

class _BigPMobileHostState extends State<BigPMobileHost> with RouteAware {
  bool _open = false;
  bool _shown = false;
  Timer? _leave;
  RouteObserver<PageRoute<dynamic>>? _observer;
  PageRoute<dynamic>? _route;

  /// The host sits in MainScreen, the profile navigator's first route (a
  /// MaterialPageRoute that observer sees): a pop back onto it is the user
  /// coming back from the detail page.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = ProfileNavigationScope.maybeOf(context)?.routeObserver;
    final route = ModalRoute.of(context);
    final page = route is PageRoute<dynamic> ? route : null;
    // Keyboard frames change the MediaQuery, not the route.
    if (page == _route && observer == _observer) return;
    _observer?.unsubscribe(this);
    _route = page;
    _observer = observer;
    if (page != null) observer?.subscribe(this, page);
  }

  /// Back on Home from the detail page (39 H): Big P into his button, the
  /// answer kept.
  @override
  void didPopNext() {
    final session = context.read<BigPMobileSession?>();
    if (session?.stage == BigPStage.peek) session!.park();
  }

  @override
  void dispose() {
    _observer?.unsubscribe(this);
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
    _handOver(session);
    if (!_open) return const SizedBox.shrink();
    final motion = _motion(context);
    final media = MediaQuery.of(context);
    // The higher of the keyboard and the tab bar: no one-frame drop while
    // the keyboard comes up.
    final bottom = max(media.viewInsets.bottom + 8, mobileBottomBarExtent(context));
    return ListenableBuilder(
      listenable: session.controller,
      builder: (context, _) {
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
                // A long answer grows over the header (39 F).
                top: media.viewPadding.top + 4,
                bottom: bottom,
                child: AnimatedSlide(
                  offset: _shown ? Offset.zero : const Offset(0.35, 0),
                  duration: motion,
                  curve: _shown ? Curves.easeOutBack : Curves.easeIn,
                  child: AnimatedOpacity(
                    opacity: _shown ? 1 : 0,
                    duration: motion,
                    child: LayoutBuilder(
                      builder: (context, box) => media.size.width >= BigPMobileHost.regularWidth
                          ? _regular(context, session, box)
                          : _compact(context, session, box),
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

  /// No question field while a confirmation waits (39 G): only the card
  /// answers it.
  bool _asks(AssistantController c) => c.availability == AssistantAvailability.ready && c.pending == null;

  Widget _avatar(AssistantController c, double size) => RepaintBoundary(
    child: BigPVoiceMouth(
      controller: c,
      builder: (line) => BigPAvatar(
        mood: c.availability == AssistantAvailability.ready ? bigPMood(c) : BigPMood.attentive,
        size: size,
        talkingText: line,
      ),
    ),
  );

  /// iPhone (39 B to G): the balloon over Big P, the follow-ups floating
  /// left of him, the field under him.
  Widget _compact(BuildContext context, BigPMobileSession session, BoxConstraints box) {
    final c = session.controller;
    final asks = _asks(c);
    final size = BigPMobileHost.avatarSize(box.maxHeight, withBar: asks);
    // Laid out bottom up, so the balloon paints last: over the top of his
    // head, never his head over its buttons (39 G).
    return Column(
      verticalDirection: VerticalDirection.up,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (asks) ...[BigPInputBar(session: session), const SizedBox(height: 4)],
        // Both in the flow, so the row is as tall as the taller of the two
        // and every pill is hit-testable, also on an iPhone SE.
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Align(alignment: Alignment.bottomRight, child: _overlapped(c, size)),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ConstrainedBox(
                  // As far as his arm, as in 39 E.
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.66),
                  child: BigPMobileFollowUps(controller: c, floating: true, onAsk: (q) => _ask(session, q)),
                ),
              ),
            ),
          ],
        ),
        Flexible(child: _balloon(context, session)),
      ],
    );
  }

  /// The top of Big P's box is mostly air above his head: the balloon may
  /// hang into it, which gives a long answer (39 F) that room.
  /// Outside the laid-out box, so it takes no taps from the balloon.
  Widget _overlapped(AssistantController c, double size) => SizedBox(
    width: size * 0.8,
    height: size * (1 - BigPMobileHost.headroom),
    child: OverflowBox(alignment: Alignment.bottomCenter, minHeight: size, maxHeight: size, child: _avatar(c, size)),
  );

  /// iPad (39 I): a 620 pt balloon left of a 250 pt Big P, its tail to
  /// him; the follow-ups and the field inside it.
  Widget _regular(BuildContext context, BigPMobileSession session, BoxConstraints box) {
    final c = session.controller;
    final size = min(312.0, box.maxHeight);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: min(620, box.maxWidth - size * 0.8 - 8)),
          // Its tail at his head, not his feet.
          child: Padding(padding: const EdgeInsets.only(bottom: 45), child: _balloon(context, session, regular: true)),
        ),
        const SizedBox(width: 8),
        _avatar(c, size),
      ],
    );
  }

  /// A question handed over by Zoeken. Asked at once when he can, after this
  /// build (asking notifies the controller this subtree listens to). Still
  /// working, or a card waiting: it stays with the session and the question
  /// field picks it up when it shows. Not set up: the balloon says so and
  /// the question is let go.
  void _handOver(BigPMobileSession session) {
    final c = session.controller;
    if (session.stage != BigPStage.out) return;
    if (c.availability != AssistantAvailability.ready) {
      session.takeQuestion();
    } else if (c.pending == null && c.state != AssistantSurfaceState.working) {
      if (session.takeQuestion() case final question?) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ask(session, question);
        });
      }
    }
  }

  void _ask(BigPMobileSession session, String question) {
    session.controller.beginListening(context: session.pendingContext);
    unawaited(session.controller.submit(question));
  }

  /// A title from the answer opens on the profile navigator, from the
  /// host's own context (docs/agents/ui-and-tv.md); Big P goes to the peek.
  void _openTitle(BigPMobileSession session, AssistantTitleTarget target) {
    session.openedTitle(target.item.globalKey);
    unawaited(navigateToMediaItemDetails(context, target.item));
  }

  Widget _balloon(BuildContext context, BigPMobileSession session, {bool regular = false}) {
    final c = session.controller;
    final conversation = BigPScale(
      pt: 0.53,
      child: BigPMobileConversation(
        controller: c,
        regular: regular,
        name: context.watch<ActiveProfileProvider?>()?.active?.displayName ?? '',
        onExample: (question) => _ask(session, question),
        onSetup: () => unawaited(_setup(session)),
        onOpenTitle: (target) => _openTitle(session, target),
        resultTime: switch (session.resultAt) {
          final at? => MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(at),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          ),
          null => '',
        },
      ),
    );
    return AutomationNode(
      id: AutomationIds.bigpBalloon,
      role: 'region',
      state: () => {
        'shown': _shown,
        'availability': c.availability.name,
        'state': c.state.name,
        'error': c.resultIsError,
        'pending': c.pending != null,
        'regular': regular,
      },
      child: regular
          ? BigPBalloon(
              tail: AxisDirection.right,
              // At his head.
              tailAt: 0.7,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(child: conversation),
                  if (_asks(c)) ...[const SizedBox(height: 12), BigPInputBar(session: session)],
                ],
              ),
            )
          // Over Big P's head, a little right of his middle.
          : BigPBalloon(tailAt: 0.81, child: conversation),
    );
  }
}
