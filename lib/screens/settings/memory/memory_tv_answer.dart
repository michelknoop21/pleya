import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../focus/focus_theme.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import 'memory_composer.dart';
import 'memory_screen_model.dart';

/// Big P's answer above the tiles on TV. It takes no more than [maxHeight],
/// so the tile under the remote stays in view whatever the length of the
/// answer. A longer answer becomes a stop that Up and Down scroll, as the
/// reading column does; at its end Down goes on to the tiles.
class MemoryTvAnswer extends StatefulWidget {
  const MemoryTvAnswer({
    super.key,
    required this.model,
    required this.node,
    required this.onStopChanged,
    required this.onLeave,
    required this.onLeft,
  });

  /// The most of the 1080 pt canvas the answer takes.
  static const double maxHeight = 300;

  final MemoryScreenModel model;
  final FocusNode node;

  /// Whether the answer is a focus stop: only when it is longer than its box.
  final ValueChanged<bool> onStopChanged;

  /// Down at the end of the answer: on to the first tile.
  final VoidCallback onLeave;
  final VoidCallback onLeft;

  @override
  State<MemoryTvAnswer> createState() => _MemoryTvAnswerState();
}

class _MemoryTvAnswerState extends State<MemoryTvAnswer> {
  final _scroll = ScrollController();
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    widget.node.canRequestFocus = false;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is KeyUpEvent || !_scroll.hasClients) return KeyEventResult.ignored;
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!down && event.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final position = _scroll.position;
    final target = (position.pixels + (down ? 1 : -1) * position.viewportDimension * 0.6).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      // At the top Up leaves for the top navigation, at the end Down for the tiles.
      if (!down) return KeyEventResult.ignored;
      widget.onLeave();
      return KeyEventResult.handled;
    }
    unawaited(
      position.animateTo(
        target,
        duration: reduceMotion(context, const Duration(milliseconds: 220)),
        curve: Curves.easeOut,
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MemoryTvAnswer.maxHeight * pt),
      child: FocusableWrapper(
        focusNode: widget.node,
        canRequestFocus: _overflows,
        disableScale: true,
        borderRadius: FocusTheme.ringRadiusAround(14 * pt, gap: 0),
        semanticLabel: t.assistant.memory.screen.title,
        onKeyEvent: (_, event) => _onKey(event),
        onNavigateLeft: widget.onLeft,
        onNavigateRight: () {},
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (metrics) {
            final overflows = metrics.metrics.maxScrollExtent > 0;
            if (overflows != _overflows) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                widget.node.canRequestFocus = overflows;
                setState(() => _overflows = overflows);
                widget.onStopChanged(overflows);
              });
            }
            return false;
          },
          // The answer fades out at the bottom where more follows.
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.8, 1],
              colors: [Colors.white, Colors.white, _overflows ? Colors.transparent : Colors.white],
            ).createShader(rect),
            child: MemoryAnswerPanel(model: widget.model, remote: true, scroll: _scroll),
          ),
        ),
      ),
    );
  }
}
