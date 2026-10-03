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
              // Room for the lead and a few lines; the rest scrolls inside
              // the block, so the results keep most of the panel.
              constraints: BoxConstraints(maxHeight: 240 * pt),
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
      Flexible(
        child: _EdgeFade(
          builder: (controller) =>
              SingleChildScrollView(controller: controller, reverse: true, child: column(children)),
        ),
      ),
      // Under the scrolling part: always in view, whatever the results do.
      if (c.state == AssistantSurfaceState.result)
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

/// Content that runs past an edge fades out there instead of being cut:
/// the fade is the sign that there is more, and it goes when the end is
/// reached.
class _EdgeFade extends StatefulWidget {
  const _EdgeFade({required this.builder, this.controller});

  /// Builds the scroll view around the controller it is given.
  final Widget Function(ScrollController controller) builder;

  /// The owner's controller, when it scrolls the content itself.
  final ScrollController? controller;

  @override
  State<_EdgeFade> createState() => _EdgeFadeState();
}

class _EdgeFadeState extends State<_EdgeFade> {
  ScrollController? _own;
  ScrollController get _scroll => widget.controller ?? (_own ??= ScrollController());
  bool _above = false;
  bool _below = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
  }

  @override
  void dispose() {
    _scroll.removeListener(_measure);
    _own?.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final up = position.axisDirection == AxisDirection.up;
    final above = (up ? position.extentAfter : position.extentBefore) > 0.5;
    final below = (up ? position.extentBefore : position.extentAfter) > 0.5;
    if (above != _above || below != _below) {
      setState(() {
        _above = above;
        _below = below;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final fade = (44 * pt / rect.height).clamp(0.0, 0.5);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _above ? const Color(0x00000000) : const Color(0xFF000000),
            const Color(0xFF000000),
            const Color(0xFF000000),
            _below ? const Color(0x00000000) : const Color(0xFF000000),
          ],
          stops: [0, fade, 1 - fade, 1],
        ).createShader(rect);
      },
      child: widget.builder(_scroll),
    );
  }
}

/// The model's answer, set as mockup 38 G sets it: the first sentence as
/// the headline, what follows in a lighter voice. Opens at its first line.
/// When it is longer than its box the lower edge fades, Up gives it the
/// focus (a thumb at its side shows where you are), and Up and Down scroll
/// it; at either end the key moves the focus on as usual.
class _AnswerBlock extends StatefulWidget {
  const _AnswerBlock({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_AnswerBlock> createState() => _AnswerBlockState();
}

final _leadEnd = RegExp(r'[.!?…](?=\s)');

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
    unawaited(_scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    // One sentence is a headline. More than that: the first sentence leads,
    // the rest reads as running text.
    final end = _leadEnd.firstMatch(widget.text)?.end;
    final split = end != null && end <= 140 && end < widget.text.length;
    final lead = split ? widget.text.substring(0, end) : widget.text;
    final rest = split ? widget.text.substring(end).trim() : '';
    return Focus(
      focusNode: _node,
      canRequestFocus: _overflows,
      onKeyEvent: _onKey,
      // The thumb hangs in the panel's margin, so the text keeps the full
      // measure and its right edge stays on the cards' edge.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            right: -20 * pt,
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: _overflows && _node.hasFocus ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: _ReadingThumb(controller: _scroll),
              ),
            ),
          ),
          _EdgeFade(
            controller: _scroll,
            builder: (controller) => SingleChildScrollView(
              controller: controller,
              child: Column(
                key: const ValueKey('assistant.answer'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lead, style: widget.style),
                  if (rest.isNotEmpty) ...[
                    SizedBox(height: 12 * pt),
                    Text(
                      rest,
                      style: TextStyle(
                        color: tk.text.withValues(alpha: 0.78),
                        fontSize: TvHig.callout * pt,
                        fontWeight: FontWeight.w500,
                        height: 1.32,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A slim track with a thumb for the part of the answer in view.
class _ReadingThumb extends StatelessWidget {
  const _ReadingThumb({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.hasClients || !controller.position.hasContentDimensions || !constraints.hasBoundedHeight) {
            return SizedBox(width: 4 * pt);
          }
          final position = controller.position;
          final total = position.maxScrollExtent + position.viewportDimension;
          final track = constraints.maxHeight;
          final thumb = (track * position.viewportDimension / total).clamp(24 * pt, track);
          final offset = position.maxScrollExtent <= 0
              ? 0.0
              : (track - thumb) * position.pixels / position.maxScrollExtent;
          return SizedBox(
            width: 4 * pt,
            height: track,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tk.text.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(2 * pt),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: EdgeInsets.only(top: offset.clamp(0.0, track - thumb)),
                  height: thumb,
                  decoration: BoxDecoration(color: tk.text, borderRadius: BorderRadius.circular(2 * pt)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
