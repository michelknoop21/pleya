import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../automation/automation_ids.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_theme.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
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

  /// The summoned panel (570 pt) rather than the surface.
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
        if (c.prompt case final prompt?) ...[TvAssistantQuestion(prompt: prompt), gap],
        Text(t.assistant.working.status, style: headlineStyle),
        gap,
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
      AssistantSurfaceState.result => _result(context, pt, headlineStyle, gap, ask),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }

  List<Widget> _result(
    BuildContext context,
    double pt,
    TextStyle headlineStyle,
    Widget gap,
    Widget Function({bool primary}) ask,
  ) {
    final c = controller;
    final headline = assistantHeadline(c);
    var optionOffset = 0;
    var firstOptionTaken = false;
    final displays = <Widget>[];
    for (final display in c.displays) {
      final choices = tvAssistantChoiceCount(display);
      displays.add(
        Padding(
          padding: EdgeInsets.only(bottom: 16 * pt),
          child: TvAssistantDisplayView(
            display: display,
            onPickOption: onPickOption,
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
    return [
      if (c.prompt case final prompt?) ...[TvAssistantQuestion(prompt: prompt), gap],
      if (headline.isNotEmpty) ...[Text(headline, style: headlineStyle), gap],
      ...displays,
      if (c.resultIsError || c.actions.isNotEmpty) ...[
        TvAssistantResultCard(error: c.resultIsError, actions: c.actions, time: resultTime),
        gap,
      ],
      Wrap(
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
    ];
  }
}
