import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../assistant/assistant_controller.dart';
import '../../automation/automation_ids.dart';
import '../../i18n/strings.g.dart';
import '../../services/pleya_keychain.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/big_p/assistant/big_p_assistant_widgets.dart';
import '../../widgets/big_p/assistant/big_p_labels.dart';
import '../../widgets/big_p/assistant/big_p_results.dart';
import '../../widgets/big_p/big_p_scale.dart';

/// What Big P's balloon says on iPhone (39 B, C, D): the greeting with
/// example questions, the set-up and locked gates, listening, the steps
/// while he works, and the answer's headline. Cards, follow-ups and the
/// confirmation are task 7's; they slot in under [_result].
class BigPMobileConversation extends StatelessWidget {
  const BigPMobileConversation({
    super.key,
    required this.controller,
    required this.name,
    required this.onExample,
    required this.onSetup,
  });

  final AssistantController controller;
  final String name;
  final ValueChanged<String> onExample;
  final VoidCallback onSetup;

  /// Mockup 39's pills and buttons are 15 pt: caption 1 at this scale.
  static const _pillScale = 0.6;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final children = switch (c.availability) {
      AssistantAvailability.locked => _locked(context),
      AssistantAvailability.needsSetup => _setup(context),
      _ => switch (c.state) {
        AssistantSurfaceState.idle => _greet(context),
        AssistantSurfaceState.listening => [
          _status(t.assistant.mobile.listening, kSuccess),
          const SizedBox(height: 8),
          Text(t.assistant.mobile.listeningHint, style: _body(context)),
        ],
        AssistantSurfaceState.working => [
          if (c.prompt case final prompt?) ...[BigPQuestion(prompt: prompt, maxLines: 1), const SizedBox(height: 12)],
          _status(t.assistant.working.status, kAccentAlt),
          const SizedBox(height: 10),
          BigPStepList(steps: c.steps),
        ],
        AssistantSurfaceState.result => _result(context),
      },
    };
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  List<Widget> _greet(BuildContext context) => [
    Text(assistantGreeting(name, greeting: t.assistant.mobile.greeting), style: _headline(context)),
    const SizedBox(height: 10),
    BigPScale(
      pt: _pillScale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, example) in t.assistant.mobile.examples.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            BigPChip(
              label: example,
              automationId: AutomationIds.assistantExample,
              automationInstance: '$i',
              onSelect: () => onExample(example),
            ),
          ],
        ],
      ),
    ),
  ];

  List<Widget> _setup(BuildContext context) {
    final m = t.assistant.mobile;
    return [
      _status(t.assistant.setup.badge, kAccentAlt),
      const SizedBox(height: 10),
      Text(m.noModelTitle, style: _headline(context)),
      const SizedBox(height: 8),
      Text(m.noModelBody, style: _body(context)),
      const SizedBox(height: 12),
      BigPScale(
        pt: _pillScale,
        child: BigPButton(
          label: m.setup,
          icon: Symbols.settings_rounded,
          primary: true,
          automationId: AutomationIds.assistantButton,
          automationInstance: 'setup',
          onPressed: onSetup,
        ),
      ),
      if (PleyaKeychain.supported) ...[
        const SizedBox(height: 10),
        Text(m.icloudNote, style: _body(context).copyWith(fontSize: 13)),
      ],
    ];
  }

  List<Widget> _locked(BuildContext context) => [
    _status(t.assistant.locked.badge, kAccentAlt),
    const SizedBox(height: 10),
    Text(t.assistant.locked.title, style: _headline(context)),
    const SizedBox(height: 8),
    Text(t.assistant.locked.note, style: _body(context)),
  ];

  /// The headline: the answer, or why the run ended (an error). Task 7 adds
  /// the cards and the follow-ups under it.
  List<Widget> _result(BuildContext context) => [
    if (controller.prompt case final prompt?) ...[
      BigPQuestion(prompt: prompt, maxLines: 1),
      const SizedBox(height: 12),
    ],
    Text(assistantHeadline(controller), style: _headline(context).copyWith(fontSize: 19, height: 1.28)),
  ];

  Widget _status(String text, Color dot) => BigPScale(
    pt: _pillScale,
    child: BigPStatusLine(text: text, color: dot),
  );

  TextStyle _headline(BuildContext context) => TextStyle(
    color: tokens(context).text,
    fontSize: 23,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.35,
  );

  TextStyle _body(BuildContext context) =>
      TextStyle(color: tokens(context).text.withValues(alpha: 0.65), fontSize: 15, height: 1.4);
}
