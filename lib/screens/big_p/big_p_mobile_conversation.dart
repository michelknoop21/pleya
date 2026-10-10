import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_tools.dart';
import '../../automation/automation_ids.dart';
import '../../i18n/strings.g.dart';
import '../../services/pleya_keychain.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/big_p/assistant/big_p_assistant_widgets.dart';
import '../../widgets/big_p/assistant/big_p_kids_ages_card.dart';
import '../../widgets/big_p/assistant/big_p_labels.dart';
import '../../widgets/big_p/assistant/big_p_results.dart';
import '../../widgets/big_p/assistant/big_p_suggestions.dart';
import '../../widgets/big_p/big_p_scale.dart';
import 'big_p_mobile_confirm.dart';
import 'big_p_mobile_followups.dart';

// ponytail: ". ", "! " or "? " ends the lead, so "Dr. Strange" splits too.
// A sentence tokenizer is the upgrade if answers trip on it. Never past the
// first line: "Top drie:" above a list is the lead on its own.
final _firstSentence = RegExp(r'^[^\n]*?[.!?](?=[ \t]+\S)|^[^\n]+');

/// What Big P's balloon says on iPhone and iPad (39 B to G, I): the
/// greeting with example questions, the set-up and locked gates, listening,
/// the steps while he works, the answer with its cards, and the Pleya card
/// while a confirmation waits.
class BigPMobileConversation extends StatelessWidget {
  const BigPMobileConversation({
    super.key,
    required this.controller,
    required this.name,
    required this.onExample,
    required this.onSetup,
    required this.onOpenTitle,
    this.resultTime = '',
    this.regular = false,
  });

  final AssistantController controller;
  final String name;
  final ValueChanged<String> onExample;
  final VoidCallback onSetup;
  final ValueChanged<AssistantTitleTarget> onOpenTitle;

  /// When the answer came in, for the result card.
  final String resultTime;

  /// The iPad balloon (39 I): cards in two columns, follow-ups inside.
  final bool regular;

  /// Mockup 39's pills and buttons are 15 pt: caption 1 at this scale.
  static const _pillScale = 0.6;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final pending = c.pending;
    // A card with a primary action keeps it in view: the card scrolls its
    // own rows and the buttons stay under them (F3), so no outer scroll.
    if (pending != null) return _pinned([..._asked()], BigPMobileConfirm(controller: c, pending: pending));
    if (c.kidsAgesPrompt case final prompt? when c.availability == AssistantAvailability.ready) {
      return _pinned(
        _resultAbove(context),
        BigPKidsAgesCard(
          key: ObjectKey(prompt),
          embedded: true,
          onSave: (ages) => unawaited(c.saveKidsAgesAndRetry(ages)),
        ),
      );
    }
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

  /// [above] over [card], which keeps its primary action in view: [above]
  /// scrolls within two fifths of the balloon, the card takes the rest and
  /// scrolls its own rows. Without a bounded height the old single scroll.
  Widget _pinned(List<Widget> above, Widget card) => LayoutBuilder(
    builder: (context, box) {
      if (!box.hasBoundedHeight) {
        return SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...above, card]),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (above.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: box.maxHeight * 0.4),
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: above),
              ),
            ),
          Flexible(child: card),
        ],
      );
    },
  );

  List<Widget> _greet(BuildContext context) => [
    Text(assistantGreeting(name, greeting: t.assistant.mobile.greeting), style: _headline(context)),
    const SizedBox(height: 10),
    BigPScale(
      pt: _pillScale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, example) in BigPSuggestions.of(controller).examples(t.assistant.mobile.examples).indexed) ...[
            // Each chip is a 44 pt touch target: no gap on top of it.
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

  List<Widget> _asked() => [
    if (controller.prompt case final prompt?) ...[
      BigPQuestion(prompt: prompt, maxLines: 2, fill: true),
      const SizedBox(height: 12),
    ],
  ];

  /// The answer (or why the run ended), then the run's cards. Above title
  /// cards only the lead: the cards are the list, as on TV.
  List<Widget> _result(BuildContext context) => [
    ..._resultAbove(context),
    if (regular && controller.kidsAgesPrompt == null) ...[
      const SizedBox(height: 12),
      BigPMobileFollowUps(controller: controller, onAsk: onExample),
    ],
  ];

  /// The question, the answer and the run's cards, without the follow-ups.
  List<Widget> _resultAbove(BuildContext context) {
    final c = controller;
    final displays = c.displays.where((d) => !bigPDisplayIsEmpty(d)).toList();
    final cards =
        bigPHasChoices(displays) &&
        displays.any((d) => d is AssistantTitleMatches || d is AssistantMediaGrid || d is AssistantRequestOptions);
    final answer = assistantHeadline(c);
    final headline = cards && answer.isNotEmpty ? assistantCardsLead(c) : answer;
    final offsets = [0];
    for (final d in displays) {
      offsets.add(offsets.last + bigPChoiceCount(d));
    }
    return [
      ..._asked(),
      if (headline.isNotEmpty) ..._answer(context, headline),
      for (final (i, display) in displays.indexed) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: BigPDisplayView(
            display: display,
            compact: true,
            columns: regular ? 2 : 1,
            optionOffset: offsets[i],
            // A title in a library opens; one only Seerr knows is requested,
            // which can end in a confirmation.
            onOpenTitle: onOpenTitle,
            onPickOption: (option) => unawaited(c.pickRequestOption(option)),
          ),
        ),
      ],
      if (c.resultIsError || c.actions.isNotEmpty) ...[
        const SizedBox(height: 12),
        BigPResultCard(error: c.resultIsError, actions: c.actions, time: resultTime),
      ],
    ];
  }

  /// The answer's first sentence as the bold lead, the rest as body text: a
  /// long answer no longer fills the balloon in bold. A lead longer than two
  /// lines at the balloon's width is body text too.
  List<Widget> _answer(BuildContext context, String answer) {
    final lead = _firstSentence.firstMatch(answer)?[0] ?? answer;
    final rest = answer.substring(lead.length).trim();
    final bold = _headline(context).copyWith(fontSize: 19, height: 1.28);
    final body = TextStyle(color: tokens(context).text.withValues(alpha: 0.85), fontSize: 16, height: 1.35);
    return [
      LayoutBuilder(
        builder: (context, box) {
          final painter = TextPainter(
            // As Text draws it: merged with the theme's font.
            text: TextSpan(text: lead, style: DefaultTextStyle.of(context).style.merge(bold)),
            maxLines: 2,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: box.maxWidth);
          final tooLong = painter.didExceedMaxLines;
          painter.dispose();
          if (tooLong) return Text(answer, style: body);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lead, style: bold),
              if (rest.isNotEmpty) ...[const SizedBox(height: 6), Text(rest, style: body)],
            ],
          );
        },
      ),
    ];
  }

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
