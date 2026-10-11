import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/big_p/assistant/big_p_memory_card.dart' show assistantMemoryCategoryLabel;
import 'memory_labels.dart';
import 'memory_screen_model.dart';
import 'memory_widgets.dart';

/// The sections of what the screen reads out: the written overview, or the
/// facts per category when there is none. Heading and text pairs, in the
/// order of the screen.
List<({String title, List<String> lines})> memoryReadSections(MemoryScreenModel model) {
  final overview = model.overview;
  final agesLine = model.kidsAges.isEmpty ? null : t.assistant.memory.screen.kidsAgesLine;
  if (overview != null && model.view == MemoryScreenView.overview) {
    final sections = [
      for (final entry in overview.sections.entries)
        (
          title: memorySectionTitle(entry.key),
          // The ages are never sent to the model: the app adds where they are.
          lines: [entry.key == 'household' && agesLine != null ? '${entry.value} $agesLine' : entry.value],
        ),
    ];
    if (agesLine != null && !overview.sections.containsKey('household')) {
      sections.add((title: memorySectionTitle('household'), lines: [agesLine]));
    }
    return sections;
  }
  final facts = model.facts ?? const <MemoryFact>[];
  return [
    for (final category in MemoryCategory.values)
      if (facts.any((fact) => fact.category == category))
        (
          title: assistantMemoryCategoryLabel(category),
          lines: [
            for (final fact in facts)
              if (fact.category == category) fact.value,
          ],
        ),
  ];
}

/// The reading column of the memory screen (43 A): headings and running
/// text. [bodySize] is 16 on a phone and 17 on a tablet.
class MemoryReadColumn extends StatelessWidget {
  const MemoryReadColumn({super.key, required this.model, this.bodySize = 16});

  final MemoryScreenModel model;
  final double bodySize;

  @override
  Widget build(BuildContext context) {
    final sections = memoryReadSections(model);
    final list = model.view != MemoryScreenView.overview;
    return AutomationNode(
      id: AutomationIds.settingsMemoryOverview,
      role: 'region',
      state: () => {'written': !list, 'sections': sections.length},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, section) in sections.indexed) ...[
            SizedBox(height: i == 0 ? 8 : 22),
            Text(section.title, style: memoryText(context, 17, weight: FontWeight.w700, height: 1.3)),
            const SizedBox(height: 6),
            for (final (j, line) in section.lines.indexed)
              Padding(
                padding: EdgeInsets.only(top: j == 0 ? 0 : 6),
                child: Text(
                  line,
                  style: memoryText(
                    context,
                    bodySize,
                    color: tokens(context).text.withValues(alpha: 0.92),
                    height: 1.55,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// "Duik dieper": the follow-up questions the model wrote under its overview
/// (43 A). A tap asks one as a follow-up, never as the user's own typed
/// words, so whatever it says it cannot store a fact without a card.
class MemoryFollowUps extends StatelessWidget {
  const MemoryFollowUps({super.key, required this.model, this.size = 16});

  final MemoryScreenModel model;
  final double size;

  @override
  Widget build(BuildContext context) {
    final questions = model.overview?.followUps ?? const <String>[];
    if (questions.isEmpty || model.view != MemoryScreenView.overview) return const SizedBox.shrink();
    final open = model.canAsk && !model.host.busy && model.host.proposal == null;
    final tk = tokens(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, question) in questions.indexed)
          MemoryPressable(
            radius: 10,
            semanticLabel: question,
            automationId: AutomationIds.settingsMemoryFollowUp,
            automationInstance: '$i',
            onPressed: open ? () => unawaited(model.host.askFollowUp(question)) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: AppIcon(Symbols.subdirectory_arrow_right_rounded, size: 18, color: memoryFaint(context)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        question,
                        style: memoryText(context, size, color: open ? tk.text : tk.textMuted, height: 1.4).copyWith(
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dotted,
                          decorationColor: tk.text.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The line under the overview: who wrote it and from how many memories.
class MemoryFooterLine extends StatelessWidget {
  const MemoryFooterLine({super.key, required this.model, required this.viaMenu});

  final MemoryScreenModel model;
  final bool viaMenu;

  @override
  Widget build(BuildContext context) {
    final overview = model.overview;
    final tk = tokens(context);
    final text = overview != null && model.view == MemoryScreenView.overview
        ? memoryFooter(overview, viaMenu: viaMenu)
        : t.assistant.memory.screen.fallbackNote;
    return Container(
      margin: const EdgeInsets.only(top: 22),
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tk.outline)),
      ),
      child: Text(text, style: memoryText(context, 13, color: tk.textMuted, height: 1.45)),
    );
  }
}

/// The loading state of 43 B: a field of dots that swells from the middle
/// while Big P writes. Still with reduced motion.
class MemoryWritingDots extends StatefulWidget {
  const MemoryWritingDots({super.key});

  @override
  State<MemoryWritingDots> createState() => _MemoryWritingDotsState();
}

class _MemoryWritingDotsState extends State<MemoryWritingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context, const Duration(seconds: 1)) == Duration.zero) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      unawaited(_pulse.repeat());
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: t.assistant.memory.screen.status.writing,
    child: RepaintBoundary(
      child: CustomPaint(painter: _DotsPainter(_pulse, tokens(context).text), size: Size.infinite),
    ),
  );
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.phase, this.ink) : super(repaint: phase);

  final Animation<double> phase;
  final Color ink;

  static const double _step = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final reach = min(size.width, size.height) * 0.62;
    if (reach <= 0) return;
    final paint = Paint();
    final wave = phase.value * 2 * pi;
    for (var y = centre.dy % _step; y < size.height; y += _step) {
      for (var x = centre.dx % _step; x < size.width; x += _step) {
        final distance = (Offset(x, y) - centre).distance / reach;
        if (distance >= 1) continue;
        final near = pow(1 - distance, 2).toDouble();
        final swell = 0.75 + 0.25 * sin(wave - distance * 5);
        paint.color = ink.withValues(alpha: (0.08 + 0.42 * near) * swell);
        canvas.drawCircle(Offset(x, y), (0.6 + 3 * near) * swell, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) => oldDelegate.ink != ink;
}
