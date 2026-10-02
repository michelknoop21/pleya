/// What Pleya shows while and after Big P works: the live step list, the
/// result card (38 G, 38 J) and the displays a tool handed over.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_run.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_theme.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import 'tv_assistant_labels.dart';
import 'tv_assistant_option_card.dart';
import 'tv_assistant_widgets.dart';

Widget _statusIcon(BuildContext context, AssistantStepPhase phase) {
  final pt = TvHig.of(context);
  final size = 30 * pt;
  return switch (phase) {
    AssistantStepPhase.done => Icon(Symbols.check_circle_rounded, fill: 1, color: kSuccess, size: size),
    AssistantStepPhase.failed => Icon(Symbols.cancel_rounded, fill: 1, color: kNoticeErrorDark, size: size),
    AssistantStepPhase.started => Icon(
      Symbols.radio_button_unchecked_rounded,
      color: tokens(context).text.withValues(alpha: 0.6),
      size: size,
    ),
  };
}

/// The live step list (motion still 3): one dark row per tool call, label
/// from the tool name and Pleya's server name, icon from the phase.
class TvAssistantStepList extends StatelessWidget {
  const TvAssistantStepList({super.key, required this.steps});

  final List<AssistantStep> steps;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    return AutomationNode(
      id: AutomationIds.assistantSteps,
      role: 'list',
      state: () => {
        'count': steps.length,
        'done': steps.where((s) => s.phase == AssistantStepPhase.done).length,
        'failed': steps.where((s) => s.phase == AssistantStepPhase.failed).length,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final step in steps) ...[
            Container(
              padding: EdgeInsets.symmetric(horizontal: 22 * pt, vertical: 14 * pt),
              decoration: BoxDecoration(color: const Color(0xCC161616), borderRadius: BorderRadius.circular(14 * pt)),
              child: Row(
                children: [
                  _statusIcon(context, step.phase),
                  SizedBox(width: 18 * pt),
                  Expanded(
                    child: Text(
                      assistantStepLabel(step),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 8 * pt),
          ],
        ],
      ),
    );
  }
}

/// "Uitgevoerd door Pleya · 21:14" with one line per action (38 G), or the
/// red "Niet uitgevoerd" card when the run failed without doing anything
/// (38 J). A failure after some actions keeps the green lines: what Pleya
/// already did is never hidden.
class TvAssistantResultCard extends StatelessWidget {
  const TvAssistantResultCard({super.key, required this.error, required this.actions, required this.time});

  final bool error;
  final List<AssistantActionRecord> actions;
  final String time;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final done = actions.isNotEmpty;
    Widget line(Widget icon, String text) => Padding(
      padding: EdgeInsets.only(top: 16 * pt),
      child: Row(
        children: [
          icon,
          SizedBox(width: 18 * pt),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: tk.text, fontSize: TvHig.body * pt, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return AutomationNode(
      id: AutomationIds.assistantResult,
      role: 'region',
      state: () => {'error': error, 'actions': actions.length},
      child: TvAssistantCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${done ? t.assistant.result.doneBy : t.assistant.result.notDoneBy} · $time',
              style: TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption2 * pt),
            ),
            for (final action in actions)
              line(_statusIcon(context, AssistantStepPhase.done), assistantActionLabel(action)),
            if (!done) line(_statusIcon(context, AssistantStepPhase.failed), t.assistant.ends.nothingChanged),
          ],
        ),
      ),
    );
  }
}

/// A tool's display, drawn on the panel. Request options are the only
/// focusable kind; selecting one goes to [onPickOption].
class TvAssistantDisplayView extends StatelessWidget {
  const TvAssistantDisplayView({
    super.key,
    required this.display,
    required this.onPickOption,
    this.firstOptionNode,
    this.optionOffset = 0,
  });

  final AssistantDisplay display;
  final ValueChanged<AssistantRequestOption> onPickOption;

  /// Gets the first option card, for the surface's default focus (still 7).
  final FocusNode? firstOptionNode;

  /// Index of this display's first option across all displays, so automation
  /// instances stay unique.
  final int optionOffset;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final muted = TextStyle(color: tk.text.withValues(alpha: 0.65), fontSize: TvHig.caption2 * pt);
    final row = TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt);
    Widget card(String? header, List<String> lines) => TvAssistantCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[Text(header, style: muted), SizedBox(height: 10 * pt)],
          for (final l in lines)
            Padding(
              padding: EdgeInsets.only(top: 6 * pt),
              child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: row),
            ),
        ],
      ),
    );
    String titled(String title, int? year) => year == null ? title : '$title ($year)';
    return switch (display) {
      AssistantRequestOptions(:final options) => Column(
        children: [
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: 10 * pt),
              child: TvAssistantOptionCard(
                option: options[i],
                index: optionOffset + i,
                focusNode: i == 0 ? firstOptionNode : null,
                onSelect: () => onPickOption(options[i]),
              ),
            ),
        ],
      ),
      AssistantMediaGrid(:final entries) => card(null, [
        for (final e in entries.take(12)) titled(e.item.displayTitle, e.item.year),
      ]),
      final AssistantServerComparison c => card(
        t.assistant.displays.missing(count: c.missingTotal, server: c.serverName, other: c.otherServerName),
        [for (final item in c.missing.take(12)) titled(item.displayTitle, item.year)],
      ),
      final AssistantWatchStats s => card(t.assistant.displays.watchStats(server: s.serverName), [
        if (!s.available) t.assistant.displays.noSource(server: s.serverName),
        for (final session in s.sessions.take(8)) '${session.userName} · ${session.title}',
        for (final u in s.users.take(8)) '${u.name} · ${t.assistant.displays.plays(count: u.plays)}',
        for (final title in s.titles.take(8)) '${title.title} · ${t.assistant.displays.plays(count: title.plays)}',
      ]),
      _ => const SizedBox.shrink(),
    };
  }
}
