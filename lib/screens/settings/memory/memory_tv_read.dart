import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/focus_theme.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import 'memory_labels.dart';
import 'memory_overview_view.dart';
import 'memory_screen_model.dart';
import 'memory_tv_widgets.dart';

/// The left column of Geheugen on TV (43 M): what the screen reads out, in
/// tvOS body size. Longer than the screen, it becomes a stop the remote
/// scrolls with Up and Down; [node] can take the focus only then.
class MemoryTvReadColumn extends StatefulWidget {
  const MemoryTvReadColumn({super.key, required this.model, required this.node, required this.onRight});

  final MemoryScreenModel model;
  final FocusNode node;

  /// Right off the text: back to the tiles.
  final VoidCallback? onRight;

  @override
  State<MemoryTvReadColumn> createState() => _MemoryTvReadColumnState();
}

class _MemoryTvReadColumnState extends State<MemoryTvReadColumn> {
  final _read = ScrollController();
  bool _overflows = false;

  @override
  void initState() {
    super.initState();
    // The tiles ask the node itself whether the text is a stop.
    widget.node.canRequestFocus = false;
  }

  @override
  void dispose() {
    _read.dispose();
    super.dispose();
  }

  KeyEventResult _scrollRead(KeyEvent event) {
    if (event is KeyUpEvent || !_read.hasClients) return KeyEventResult.ignored;
    final down = event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!down && event.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final position = _read.position;
    final target = (position.pixels + (down ? 1 : -1) * position.viewportDimension * 0.6).clamp(
      0.0,
      position.maxScrollExtent,
    );
    // At the top Up leaves the text for the top navigation.
    if (target == position.pixels) return down ? KeyEventResult.handled : KeyEventResult.ignored;
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
    final s = t.assistant.memory.screen;
    final model = widget.model;
    final tk = tokens(context);
    final view = model.view;
    if (view == MemoryScreenView.loading || view == MemoryScreenView.writing) {
      return SizedBox(height: 620 * pt, child: const MemoryWritingDots());
    }
    final (String, String)? notice = switch (view) {
      MemoryScreenView.error => (s.error.title, s.error.body),
      MemoryScreenView.off => (s.off.title, s.off.body),
      MemoryScreenView.empty => (s.empty.title, s.empty.body),
      MemoryScreenView.kids => (s.kids.title, s.kids.body),
      _ => null,
    };
    final sections = view == MemoryScreenView.kids || notice == null ? memoryReadSections(model) : const [];
    final heading = TextStyle(color: tk.text, fontSize: TvHig.callout * pt, fontWeight: FontWeight.w700, height: 1.3);
    final overview = model.overview;
    final footer = notice != null
        ? null
        : (view == MemoryScreenView.overview && overview != null
              ? memoryFooter(overview, viaMenu: false)
              : s.fallbackNote);

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (notice != null) ...[
          Text(notice.$1, style: heading),
          SizedBox(height: 8 * pt),
          Text(notice.$2, style: memoryTvBody(context)),
        ],
        for (final (i, section) in sections.indexed) ...[
          if (i > 0 || notice != null) SizedBox(height: 34 * pt),
          Text(section.title, style: heading),
          SizedBox(height: 8 * pt),
          for (final line in section.lines) Text(line, style: memoryTvBody(context)),
        ],
        if (footer != null) ...[
          SizedBox(height: 34 * pt),
          Divider(height: 1, thickness: 1, color: tk.outline),
          SizedBox(height: 22 * pt),
          Text(footer, style: memoryTvSmall(context)),
        ],
        SizedBox(height: 40 * pt),
      ],
    );

    return AutomationNode(
      id: AutomationIds.settingsMemoryOverview,
      role: 'region',
      focusNode: widget.node,
      state: () => {'written': view == MemoryScreenView.overview, 'sections': sections.length},
      child: FocusableWrapper(
        focusNode: widget.node,
        canRequestFocus: _overflows,
        disableScale: true,
        autoScroll: false,
        borderRadius: FocusTheme.ringRadiusAround(16 * pt, gap: 6 * pt),
        semanticLabel: s.title,
        onKeyEvent: (_, event) => _scrollRead(event),
        onNavigateRight: widget.onRight,
        onNavigateLeft: () {},
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (metrics) {
            final overflows = metrics.metrics.maxScrollExtent > 0;
            if (overflows != _overflows) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                widget.node.canRequestFocus = overflows;
                setState(() => _overflows = overflows);
              });
            }
            return false;
          },
          // The text fades out at the bottom where more follows (43 M).
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.88, 1],
              colors: [Colors.white, Colors.white, _overflows ? Colors.transparent : Colors.white],
            ).createShader(rect),
            child: SingleChildScrollView(controller: _read, padding: EdgeInsets.all(6 * pt), child: text),
          ),
        ),
      ),
    );
  }
}
