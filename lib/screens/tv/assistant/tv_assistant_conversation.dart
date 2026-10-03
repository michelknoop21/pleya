import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final headline = c.state == AssistantSurfaceState.result ? assistantHeadline(c) : '';
    final head = <Widget>[
      if (c.state == AssistantSurfaceState.result) ...[
        if (c.prompt case final prompt?) ...[TvAssistantQuestion(prompt: prompt, maxLines: compact ? 1 : 3), gap],
        if (headline.isNotEmpty) ...[
          if (children.isEmpty)
            Flexible(
              child: _AnswerBlock(text: headline, style: headlineStyle),
            )
          else
            ConstrainedBox(
              // Five lines; the rest scrolls inside the block.
              constraints: BoxConstraints(maxHeight: 5 * headlineStyle.fontSize! * headlineStyle.height!),
              child: _AnswerBlock(text: headline, style: headlineStyle),
            ),
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
    // Anchored at the bottom: the newest stays in view.
    return column([
      ...head,
      Flexible(child: SingleChildScrollView(reverse: true, child: column(children))),
      // Under the scrolling part: always in view, whatever the results do.
      if (c.state == AssistantSurfaceState.result)
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
    return [
      ..._displays(pt),
      if (c.resultIsError || c.actions.isNotEmpty) ...[
        TvAssistantResultCard(error: c.resultIsError, actions: c.actions, time: resultTime),
        SizedBox(height: 24 * pt),
      ],
    ];
  }
}

/// The model's answer. Opens at its first line. When it is longer than its
/// box it takes the focus on Up, shows a scroll thumb, and Up and Down
/// scroll it; at either end the key moves the focus on as usual.
class _AnswerBlock extends StatefulWidget {
  const _AnswerBlock({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_AnswerBlock> createState() => _AnswerBlockState();
}

class _AnswerBlockState extends State<_AnswerBlock> {
  final _scroll = ScrollController();
  final _node = FocusNode(debugLabel: 'assistant.answer');
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_changed);
  }

  @override
  void dispose() {
    _node
      ..removeListener(_changed)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final overflows = _scroll.position.maxScrollExtent > 0;
    if (overflows != _overflows) setState(() => _overflows = overflows);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (event is KeyUpEvent || (!up && event.logicalKey != LogicalKeyboardKey.arrowDown)) {
      return KeyEventResult.ignored;
    }
    final position = _scroll.position;
    final step = position.viewportDimension * 0.6;
    final target = (position.pixels + (up ? -step : step)).clamp(0.0, position.maxScrollExtent);
    if (target == position.pixels) return KeyEventResult.ignored;
    unawaited(_scroll.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Focus(
      focusNode: _node,
      canRequestFocus: _overflows,
      onKeyEvent: _onKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _node.hasFocus ? tk.text.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(12 * pt),
        ),
        child: RawScrollbar(
          controller: _scroll,
          thumbVisibility: _overflows,
          thumbColor: tk.text.withValues(alpha: _node.hasFocus ? 0.8 : 0.35),
          thickness: 4 * pt,
          radius: Radius.circular(2 * pt),
          child: SingleChildScrollView(
            controller: _scroll,
            child: Text(widget.text, style: widget.style),
          ),
        ),
      ),
    );
  }
}
