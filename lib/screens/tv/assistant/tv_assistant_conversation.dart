import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../automation/automation_ids.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_theme.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import 'tv_assistant_answer.dart';
import 'tv_assistant_labels.dart';
import 'tv_assistant_results.dart';
import 'tv_assistant_widgets.dart';

/// What the glass panel holds in each stand (rust, luisteren, werken,
/// resultaat), newest at the bottom. Reads [controller]; the surface owns
/// the focus nodes and the actions.
class TvAssistantConversation extends StatelessWidget {
  const TvAssistantConversation({
    super.key,
    required this.controller,
    required this.name,
    required this.servers,
    required this.resultTime,
    required this.askNode,
    required this.cancelNode,
    required this.firstOptionNode,
    required this.onAsk,
    required this.onDone,
    required this.onCancelWork,
    required this.onExample,
    required this.onPickOption,
    required this.onOpenTitle,
    this.compact = false,
  });

  final AssistantController controller;
  final String name;

  /// The servers Big P can act on, already joined for the status line.
  final String servers;
  final String resultTime;
  final FocusNode askNode;
  final FocusNode cancelNode;
  final FocusNode firstOptionNode;
  final VoidCallback onAsk;
  final VoidCallback onDone;
  final VoidCallback onCancelWork;
  final ValueChanged<String> onExample;
  final ValueChanged<AssistantRequestOption> onPickOption;
  final ValueChanged<AssistantTitleTarget> onOpenTitle;

  /// The summoned panel (760 pt) rather than the surface.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final c = controller;
    final headlineStyle = TextStyle(
      color: tk.text,
      fontSize: TvHig.headline * pt,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    final gap = SizedBox(height: 24 * pt);

    Widget ask({bool primary = true}) => TvAssistantButton(
      label: t.assistant.idle.ask,
      icon: Symbols.mic_rounded,
      primary: primary,
      focusNode: askNode,
      automationId: AutomationIds.assistantButton,
      automationInstance: 'ask',
      onPressed: onAsk,
    );

    final children = switch (c.state) {
      AssistantSurfaceState.idle => <Widget>[
        if (servers.isNotEmpty) ...[
          TvAssistantStatusLine(
            text: t.assistant.idle.status(servers: servers),
            color: kSuccess,
          ),
          SizedBox(height: 14 * pt),
        ],
        Text(t.assistant.idle.greeting(name: name), style: headlineStyle),
        gap,
        Align(alignment: Alignment.centerLeft, child: ask()),
        gap,
        Text(
          t.assistant.idle.examplesHeader,
          style: TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption1 * pt),
        ),
        SizedBox(height: 12 * pt),
        for (final (i, example) in t.assistant.idle.examples.indexed) ...[
          TvAssistantChip(
            label: example,
            automationId: AutomationIds.assistantExample,
            automationInstance: '$i',
            onSelect: () => onExample(example),
          ),
          SizedBox(height: 12 * pt),
        ],
      ],
      AssistantSurfaceState.listening => <Widget>[
        TvAssistantStatusLine(text: t.assistant.listening.title, color: kSuccess),
        SizedBox(height: 14 * pt),
        Text(t.assistant.listening.body, style: headlineStyle),
      ],
      AssistantSurfaceState.working => <Widget>[
        if (c.stillChecking) ..._displays(pt, working: true),
        TvAssistantStepList(steps: c.steps),
        SizedBox(height: 16 * pt),
        Align(
          alignment: Alignment.centerLeft,
          child: TvAssistantButton(
            label: t.assistant.result.cancel,
            icon: Symbols.close_rounded,
            primary: false,
            focusNode: cancelNode,
            automationId: AutomationIds.assistantButton,
            automationInstance: 'cancel',
            onPressed: onCancelWork,
          ),
        ),
      ],
      AssistantSurfaceState.result => _result(context, pt),
    };

    // While working, the question and the status stay above the scrolling
    // part: four streamed results plus Cancel do not fit the panel, and the
    // status is the one line that says Big P is not done yet. Both are
    // bounded (3 lines, a fixed string); the model's answer is not, so the
    // result gives it a block of its own that opens at its first line and
    // scrolls by itself, above the results.
    // Title cards repeat what the answer lists. A ranking or a comparison
    // shows a few of its titles only, so there the text stays whole.
    final cards = c.displays.any(
      (d) =>
          !tvAssistantDisplayIsEmpty(d) &&
          (d is AssistantTitleMatches || d is AssistantMediaGrid || d is AssistantRequestOptions),
    );
    final answer = c.state == AssistantSurfaceState.result ? assistantHeadline(c) : '';
    final headline = cards ? assistantWithoutList(answer) : answer;
    final head = <Widget>[
      if (c.state == AssistantSurfaceState.result) ...[
        if (c.prompt case final prompt?) ...[TvAssistantQuestion(prompt: prompt, maxLines: compact ? 1 : 3), gap],
        if (headline.isNotEmpty) ...[
          // Above cards the lead alone: the cards are the answer. Above a
          // result card it shows three lines of what follows; alone, it reads
          // down the panel.
          if (children.isEmpty)
            Flexible(
              child: TvAssistantAnswer(text: headline, style: headlineStyle),
            )
          else
            TvAssistantAnswer(text: headline, style: headlineStyle, bodyLines: cards ? 0 : 3),
          gap,
        ],
      ],
      if (c.state == AssistantSurfaceState.working) ...[
        if (c.prompt case final prompt?) ...[TvAssistantQuestion(prompt: prompt, maxLines: compact ? 1 : 3), gap],
        // Results that are in show at once; the model is still composing.
        Text(c.stillChecking ? t.assistant.working.stillChecking : t.assistant.working.status, style: headlineStyle),
        gap,
      ],
    ];
    Widget column(List<Widget> items) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: items);
    // While working, anchored at the bottom: the newest stays in view. A
    // result opens at its first card.
    final result = c.state == AssistantSurfaceState.result;
    return column([
      ...head,
      // Nothing under the answer: the answer keeps the whole height.
      if (children.isNotEmpty || c.state != AssistantSurfaceState.result)
        Flexible(
          child: TvAssistantEdgeFade(
            // A new list per stand: the working list's offset does not carry.
            key: ValueKey(result),
            builder: (controller) =>
                SingleChildScrollView(controller: controller, reverse: !result, child: column(children)),
          ),
        ),
      // Under the scrolling part: always in view, whatever the results do.
      if (c.state == AssistantSurfaceState.result) ...[
        // No cards to walk through: the follow-ups stand above the buttons,
        // in view, and the list above them needs no focus to be read.
        if (!tvAssistantHasChoices(c.displays))
          if (_followUps(pt) case final followUps?) ...[followUps, SizedBox(height: 16 * pt)],
        // A button keeps 6 pt around its fill for the focus ring; pulled
        // back so the fill, not the ring, lines up with the text and cards.
        Transform.translate(
          offset: Offset(-6 * pt, 0),
          child: Wrap(
            spacing: 12 * pt,
            runSpacing: 12 * pt,
            children: [
              ask(),
              TvAssistantButton(
                label: t.assistant.result.done,
                primary: false,
                automationId: AutomationIds.assistantButton,
                automationInstance: 'done',
                onPressed: onDone,
              ),
            ],
          ),
        ),
      ],
    ]);
  }

  /// The run's displays. Only the result stand hands the first choice the
  /// surface's option node. While [working], a request card is shown but
  /// inert: the controller takes no pick before the run ends.
  List<Widget> _displays(double pt, {bool working = false}) {
    var optionOffset = 0;
    var firstOptionTaken = working;
    final displays = <Widget>[];
    for (final display in controller.displays.where((d) => !tvAssistantDisplayIsEmpty(d))) {
      final choices = tvAssistantChoiceCount(display);
      displays.add(
        Padding(
          padding: EdgeInsets.only(bottom: 16 * pt),
          child: TvAssistantDisplayView(
            display: display,
            onPickOption: working ? null : onPickOption,
            onOpenTitle: onOpenTitle,
            compact: compact,
            optionOffset: optionOffset,
            firstOptionNode: choices > 0 && !firstOptionTaken ? firstOptionNode : null,
          ),
        ),
      );
      if (choices > 0) {
        optionOffset += choices;
        firstOptionTaken = true;
      }
    }
    return displays;
  }

  /// What scrolls under the answer: the run's displays and its result card.
  List<Widget> _result(BuildContext context, double pt) {
    final c = controller;
    final results = [
      ..._displays(pt),
      if (c.resultIsError || c.actions.isNotEmpty) ...[
        TvAssistantResultCard(error: c.resultIsError, actions: c.actions, time: resultTime),
        SizedBox(height: 24 * pt),
      ],
    ];
    // After the cards, in the same list: the cards keep the height.
    return [
      ...results,
      if (tvAssistantHasChoices(c.displays))
        if (_followUps(pt) case final followUps?) ...[followUps, SizedBox(height: 16 * pt)],
    ];
  }

  /// Three follow-ups after an answer; an error or a gate is no answer.
  Widget? _followUps(double pt) {
    final c = controller;
    if (c.resultIsError) return null;
    return Wrap(
      spacing: 10 * pt,
      runSpacing: 10 * pt,
      children: [
        for (final (i, question) in assistantFollowUps(
          c.displays,
          jobs: c.actions.any((a) => a.job != null),
          prompt: c.prompt,
        ).indexed)
          TvAssistantChip(
            label: question,
            icon: Symbols.subdirectory_arrow_right_rounded,
            dense: true,
            automationId: AutomationIds.assistantFollowUp,
            automationInstance: '$i',
            onSelect: () => onExample(question),
          ),
      ],
    );
  }
}
