import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../big_p_scale.dart';
import 'big_p_edge_fade.dart';

export 'big_p_edge_fade.dart';

/// The model's answer, set as mockup 38 G sets it: the first sentence as
/// the headline, what follows as running text under it. The headline stays
/// put. Running text longer than its box scrolls by whole lines: its lower
/// edge fades, Up gives it the focus (a thumb in the margin shows where you
/// are), and Up and Down move through it; at either end the key moves the
/// focus on as usual.
class BigPAnswer extends StatefulWidget {
  const BigPAnswer({
    super.key,
    required this.text,
    required this.style,
    this.bodyLines,
    this.readLines = 3,
    this.lead = true,
    this.focusNode,
  });

  final String text;
  final TextStyle style;

  /// False for one task's answer among several: no headline, the whole text
  /// reads as running text in [style], which then carries a size and a
  /// height. With the focus on it no line is faded.
  final bool lead;

  /// The owner's node for the reading stop, when a panel holds more than
  /// one answer and hands the remote from one to the next itself.
  final FocusNode? focusNode;

  /// How many lines of running text show at once; null takes the height
  /// the parent leaves. Zero shows the lead alone, in two lines at most:
  /// above cards, which are the answer and need the height.
  final int? bodyLines;

  /// Above cards (zero [bodyLines]): how many lines a lead that is too long
  /// for a headline gets as running text before it scrolls.
  final int readLines;

  @override
  State<BigPAnswer> createState() => _BigPAnswerState();
}

// A bare list has no lead: its first item is not a headline.
final _startsWithItem = RegExp(r'^\s*(?:\d{1,2}[.)]|•)\s');

// A sentence end, or the end of the first line. Not the dot of a list
// number ("1.") or of a one-letter abbreviation ("o.a.").
final _leadEnd = RegExp(r'(?<!(?:^|\n)\s*\d{1,2})(?<!\b[A-Za-z])[.!?…](?=\s)|(?=\n)');

/// The running-text style: callout size, regular weight, the line height
/// the scroll step and the box measure are built on.
TextStyle _runningStyle(MonoTokens tk, double pt) => TextStyle(
  color: tk.text.withValues(alpha: 0.86),
  fontSize: TvHig.callout * pt,
  fontWeight: FontWeight.w400,
  height: _runningHeight,
);

const _runningHeight = 1.36;

/// What one more line of running text costs at scale [pt].
double bigPRunningLineHeight(double pt) => TvHig.callout * pt * _runningHeight;

bool _fitsLines(BuildContext context, String text, TextStyle style, int lines, double width) {
  if (!width.isFinite) return true;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: lines,
  )..layout(maxWidth: width);
  final fits = !painter.didExceedMaxLines;
  painter.dispose();
  return fits;
}

class _BigPAnswerState extends State<BigPAnswer> {
  final _scroll = ScrollController();
  FocusNode? _own;
  late final FocusNode _node = widget.focusNode ?? (_own = FocusNode(debugLabel: 'assistant.answer'));
  bool _overflows = false;
  double _line = 1;

  @override
  void initState() {
    super.initState();
    _node.addListener(_changed);
  }

  @override
  void dispose() {
    _node.removeListener(_changed);
    _own?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final overflows = _scroll.position.maxScrollExtent > 0.5;
    if (overflows != _overflows) setState(() => _overflows = overflows);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (event is KeyUpEvent || (!up && event.logicalKey != LogicalKeyboardKey.arrowDown)) {
      return KeyEventResult.ignored;
    }
    final position = _scroll.position;
    // Whole lines, one short of a page, so the eye keeps its place.
    final lines = (position.viewportDimension / _line).floor() - 1;
    final step = _line * (lines < 1 ? 1 : lines);
    // Snapped to a line, so a press during the previous glide still lands on one.
    final target = (((position.pixels + (up ? -step : step)) / _line).round() * _line).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return KeyEventResult.ignored;
    final duration = reduceMotion(context, const Duration(milliseconds: 240));
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      unawaited(_scroll.animateTo(target, duration: duration, curve: Curves.easeOutCubic));
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    // One sentence is a headline. More than that: the first sentence leads,
    // the rest reads as running text.
    // ponytail: a sentence end is punctuation plus a space, at least 24
    // characters in, so "Mr." or "1." never leads. An abbreviation further
    // on can still split early; a sentence segmenter is the upgrade.
    final end = _leadEnd
        .allMatches(widget.text)
        // A line end always ends the lead, however short the line.
        .where((m) => m.end > 0 && (m.end >= 24 || (m.end == m.start && !_startsWithItem.hasMatch(widget.text))))
        .map((m) => m.end)
        .firstOrNull;
    final split = widget.lead && end != null && end <= 140 && end < widget.text.length;
    final rest = split ? widget.text.substring(end).trim() : '';
    // One long sentence is no headline: it reads as running text.
    final bodyStyle =
        !widget.lead || rest.isEmpty && widget.text.length <= 140 && !_startsWithItem.hasMatch(widget.text)
        ? widget.style
        : _runningStyle(tk, pt);
    _line = bodyStyle.fontSize! * bodyStyle.height!;

    // The box holds whole lines only, so no line is ever cut in half.
    // A cap, not a size: a short answer keeps the panel short.
    Widget body(double maxHeight) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight.isFinite ? (maxHeight / _line).floor() * _line : double.infinity,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // In the panel's margin, so the text keeps the full measure and
          // its right edge stays on the cards' edge.
          Positioned.fill(
            right: -20 * pt,
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                // Dim while resting: the sign that the text goes on.
                opacity: !_overflows ? 0 : (_node.hasFocus ? 1 : 0.45),
                duration: const Duration(milliseconds: 160),
                child: _ReadingThumb(controller: _scroll),
              ),
            ),
          ),
          BigPEdgeFade(
            controller: _scroll,
            // A hint at the edge; the last line stays readable. A task's
            // answer under the remote is read whole: the thumb says the rest.
            extent: !widget.lead && _node.hasFocus ? 0 : _line * 0.25,
            builder: (controller) => SingleChildScrollView(
              controller: controller,
              child: Text(
                rest.isEmpty ? widget.text : rest,
                key: const ValueKey('assistant.answer.body'),
                style: bodyStyle,
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.bodyLines == 0) {
      final lead = split ? widget.text.substring(0, end) : widget.text;
      // Above cards the lead is a headline only while it fits two lines.
      // A longer sentence moves into the reading box as running text: three
      // lines high, the whole sentence reachable by scrolling, nothing cut.
      return LayoutBuilder(
        builder: (context, box) {
          if (_fitsLines(context, lead, widget.style, 2, box.maxWidth)) {
            return Text(lead, key: const ValueKey('assistant.answer'), maxLines: 2, style: widget.style);
          }
          return BigPAnswer(
            text: lead,
            style: _runningStyle(tk, pt),
            lead: false,
            bodyLines: widget.readLines,
            focusNode: widget.focusNode,
          );
        },
      );
    }

    return Focus(
      focusNode: _node,
      canRequestFocus: _overflows,
      onKeyEvent: _onKey,
      child: Column(
        key: const ValueKey('assistant.answer'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rest.isNotEmpty) ...[Text(widget.text.substring(0, end), style: widget.style), SizedBox(height: 12 * pt)],
          if (widget.bodyLines case final lines?)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: lines * _line),
              child: body(double.infinity),
            )
          else
            Flexible(child: LayoutBuilder(builder: (context, box) => body(box.maxHeight))),
        ],
      ),
    );
  }
}

/// A results list with nothing in it to focus (a ranking whose titles are
/// in no library, a comparison): when it runs past its box it takes the
/// focus itself, and Up and Down scroll it; at either end the key moves the
/// focus on. A list with cards needs none of this: the focus scrolls it.
class BigPReadableList extends StatefulWidget {
  const BigPReadableList({super.key, required this.child, this.controller, this.focusNode});

  final Widget child;

  /// The owner's controller, when it scrolls the list itself too.
  final ScrollController? controller;

  /// The owner's node for the list's reading stop, when it hands the remote
  /// on to a reading stop inside the list itself. While the list is a stop,
  /// the D-pad then finds the list and not what is inside it.
  final FocusNode? focusNode;

  @override
  State<BigPReadableList> createState() => _BigPReadableListState();
}

class _BigPReadableListState extends State<BigPReadableList> {
  ScrollController? _own;
  ScrollController get _scroll => widget.controller ?? (_own ??= ScrollController());
  FocusNode? _ownNode;
  late final FocusNode _node = widget.focusNode ?? (_ownNode = FocusNode(debugLabel: 'assistant.results'));
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_changed);
  }

  @override
  void dispose() {
    _node.removeListener(_changed);
    _ownNode?.dispose();
    _own?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final overflows = _scroll.position.maxScrollExtent > 0.5;
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
    if ((target - position.pixels).abs() < 0.5) return KeyEventResult.ignored;
    final duration = reduceMotion(context, const Duration(milliseconds: 240));
    if (duration == Duration.zero) {
      _scroll.jumpTo(target);
    } else {
      unawaited(_scroll.animateTo(target, duration: duration, curve: Curves.easeOutCubic));
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Focus(
      focusNode: _node,
      canRequestFocus: _overflows,
      descendantsAreTraversable: widget.focusNode == null || !_overflows,
      onKeyEvent: _onKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            right: -20 * pt,
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: !_overflows ? 0 : (_node.hasFocus ? 1 : 0.45),
                duration: const Duration(milliseconds: 160),
                child: _ReadingThumb(controller: _scroll),
              ),
            ),
          ),
          BigPEdgeFade(
            controller: _scroll,
            builder: (controller) => SingleChildScrollView(controller: controller, child: widget.child),
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
    final pt = BigPScale.of(context);
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
          if (total <= 0 || track < 24 * pt) return SizedBox(width: 4 * pt);
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
