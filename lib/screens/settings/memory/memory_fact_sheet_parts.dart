import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/focusable_text_field.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import 'memory_labels.dart';
import 'memory_widgets.dart';

/// The text of a memory in its sheet: a field on a phone and a tablet. On TV,
/// and where the memory is only shown, a row; on TV it opens the system
/// keyboard through [onEdit].
class MemoryFactField extends StatelessWidget {
  const MemoryFactField({
    super.key,
    required this.text,
    required this.focusNode,
    required this.tv,
    required this.readOnly,
    required this.busy,
    required this.autofocus,
    this.onEdit,
    this.onNavigateDown,
  });

  final TextEditingController text;
  final FocusNode focusNode;
  final bool tv;
  final bool readOnly;
  final bool busy;
  final bool autofocus;

  /// TV: opens the system keyboard or dictation.
  final VoidCallback? onEdit;
  final VoidCallback? onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final s = t.assistant.memory.screen.sheet;
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    final style = memoryText(context, 16, height: 1.4);
    final box = BoxDecoration(
      color: tk.bg,
      borderRadius: BorderRadius.circular(12 * k),
      border: Border.all(color: focusNode.hasFocus ? tk.text.withValues(alpha: 0.55) : tk.outline),
    );
    if (tv || readOnly) {
      final empty = text.text.isEmpty;
      return MemoryPressable(
        radius: 12,
        focusNode: focusNode,
        // The remote starts on the text, the first thing to change.
        autofocus: tv && !readOnly,
        semanticLabel: empty ? s.hint : text.text,
        automationId: AutomationIds.settingsMemorySheetField,
        automationRole: 'field',
        onPressed: tv && !readOnly && !busy ? onEdit : null,
        onNavigateDown: onNavigateDown,
        child: Container(
          // One line on TV, where the text is typed on the system keyboard:
          // the panel keeps its buttons in view. It grows with a long memory.
          constraints: BoxConstraints(minHeight: (tv ? 50 : 88) * k),
          padding: EdgeInsets.all(12 * k),
          alignment: Alignment.topLeft,
          decoration: box,
          child: Text(empty ? s.hint : text.text, style: empty ? style.copyWith(color: memoryFaint(context)) : style),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(12),
      decoration: box,
      child: AutomationNode(
        id: AutomationIds.settingsMemorySheetField,
        role: 'field',
        focusNode: focusNode,
        child: FocusableTextField(
          controller: text,
          focusNode: focusNode,
          autofocus: autofocus,
          enabled: !busy,
          minLines: 3,
          maxLines: 3,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          // A memory is one line: Return closes the keyboard, it adds none.
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))],
          style: style,
          decoration: InputDecoration(
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: s.hint,
            hintStyle: style.copyWith(color: memoryFaint(context)),
          ),
          onSubmitted: (_) => focusNode.unfocus(),
        ),
      ),
    );
  }
}

/// Where a memory came from and when it was added and last changed.
class MemoryFactMeta extends StatelessWidget {
  const MemoryFactMeta({super.key, required this.fact, this.compact = false});

  final MemoryFact fact;

  /// TV: the three lines closer together, so the panel fits the screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = t.assistant.memory.screen.sheet;
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    final style = memoryText(context, 13.5, color: tk.textMuted, height: 1.35);
    Widget row(String name, String value) => Padding(
      padding: EdgeInsets.symmetric(vertical: (compact ? 2 : 7) * k),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: style),
          SizedBox(width: 16 * k),
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: style),
          ),
        ],
      ),
    );
    return Container(
      margin: EdgeInsets.only(top: (compact ? 10 : 16) * k),
      padding: EdgeInsets.only(top: (compact ? 6 : 4) * k),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tk.outline)),
      ),
      child: Column(
        children: [
          row(s.source, memorySourceLabel(fact.source)),
          row(s.created, memoryDate(fact.createdAt)),
          row(s.updated, memoryDate(fact.updatedAt)),
        ],
      ),
    );
  }
}
