import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/focusable_text_field.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/speech_search_service.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/big_p/assistant/big_p_memory_card.dart' show assistantMemoryCategoryLabel;
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/overlay_sheet_geometry.dart';
import 'memory_dialogs.dart';
import 'memory_labels.dart';
import 'memory_screen_model.dart';
import 'memory_tv_text.dart';
import 'memory_widgets.dart';

/// Opens the sheet of one memory (43 E), or the empty one to add a memory
/// (43 F) when [fact] is null. Every write goes through [model], as a manual
/// change of the user.
Future<void> showMemoryFactSheet(
  BuildContext context,
  MemoryScreenModel model, {
  MemoryFact? fact,
  SpeechSearchService? speech,
}) {
  final tv = PlatformDetector.isTV();
  return OverlaySheetController.showAdaptive<void>(
    context,
    backgroundColor: tokens(context).surface,
    isScrollControlled: true,
    restoreLauncherFocus: true,
    presentation: tv ? OverlaySheetPresentation.panel : OverlaySheetPresentation.sheet,
    builder: (sheetContext) => MemoryScale.forPlatform(
      sheetContext,
      MemoryFactSheet(
        model: model,
        fact: fact,
        speech: speech ?? SpeechSearchService.instance,
        onClose: () => OverlaySheetController.closeAdaptive(sheetContext),
      ),
    ),
  );
}

class MemoryFactSheet extends StatefulWidget {
  const MemoryFactSheet({super.key, required this.model, required this.onClose, required this.speech, this.fact});

  final MemoryScreenModel model;
  final MemoryFact? fact;
  final SpeechSearchService speech;
  final VoidCallback onClose;

  @override
  State<MemoryFactSheet> createState() => _MemoryFactSheetState();
}

class _MemoryFactSheetState extends State<MemoryFactSheet> {
  late final _text = TextEditingController(text: widget.fact?.value ?? '');
  final _fieldFocus = FocusNode(debugLabel: 'memory.sheet.field');
  late MemoryCategory _category = widget.fact?.category ?? MemoryCategory.preference;
  MemoryCode? _refused;
  bool _busy = false;

  MemoryFact? get _fact => widget.fact;

  /// A children's profile looks and wipes; it changes nothing.
  bool get _readOnly => widget.model.kids;

  String get _mode => _fact == null ? 'add' : (_readOnly ? 'view' : 'edit');

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _fieldFocus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() => _refused = null);
  }

  @override
  void dispose() {
    _text.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  bool get _canSave {
    final value = _text.text.trim();
    if (_busy || _readOnly || value.isEmpty) return false;
    final fact = _fact;
    return fact == null || value != fact.value || _category != fact.category;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _busy = true);
    final fact = _fact;
    final value = _text.text.trim();
    final result = fact == null
        ? await widget.model.add(value, _category)
        : await widget.model.update(fact, value: value, category: _category);
    if (!mounted) return;
    if (result.ok) return widget.onClose();
    // The fixed refusals, a sentence that is already there and a failed
    // write all stay in the sheet as one readable line.
    setState(() {
      _busy = false;
      _refused = result.code;
    });
  }

  Future<void> _delete() async {
    final fact = _fact;
    final s = t.assistant.memory.screen.sheet;
    if (fact == null || _busy) return;
    final yes = await showMemoryConfirm(context, title: s.deleteTitle, body: s.deleteBody, confirm: t.common.delete);
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    final result = await widget.model.delete(fact);
    if (!mounted) return;
    // Gone already is gone: the list no longer shows it either.
    if (result.ok || result.code == MemoryCode.notFound) return widget.onClose();
    setState(() {
      _busy = false;
      _refused = result.code;
    });
  }

  /// TV: the system keyboard or dictation, the path Big P's question takes.
  Future<void> _editOnTv() async {
    final text = await memoryTvCaptureText(
      context,
      widget.speech,
      prompt: t.assistant.memory.screen.sheet.text,
      initial: _text.text,
      action: 'done',
    );
    if (text != null && mounted) _text.text = text.replaceAll(RegExp(r'[\n\r]+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final s = t.assistant.memory.screen.sheet;
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    final tv = PlatformDetector.isTV();
    final fact = _fact;
    final length = _text.text.runes.length;
    final label = memoryText(context, 13, color: tk.textMuted);
    final refused = _refused;

    return AutomationNode(
      id: AutomationIds.settingsMemorySheet,
      role: 'sheet',
      state: () => {'mode': _mode, 'refused': _refused?.name},
      child: SafeArea(
        top: false,
        child: Padding(
          // Above the keyboard, where no page above has made room for it yet.
          padding: EdgeInsets.only(bottom: tv ? 0 : MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16 * k, 10 * k, 16 * k, 14 * k),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!tv) const MemorySheetGrab(),
                Text(fact == null ? s.addTitle : s.title, style: memoryText(context, 20, weight: FontWeight.w700)),
                SizedBox(height: 16 * k),
                Row(
                  children: [
                    Expanded(child: Text(s.text, style: label)),
                    Text(
                      '$length/$kMemoryValueMaxLength',
                      style: label.copyWith(color: length > kMemoryValueMaxLength ? tk.accent : null),
                    ),
                  ],
                ),
                SizedBox(height: 8 * k),
                _field(context, tv: tv),
                SizedBox(height: 16 * k),
                Text(s.category, style: label),
                SizedBox(height: 4 * k),
                Wrap(
                  spacing: 8 * k,
                  children: [
                    for (final category in MemoryCategory.values)
                      MemoryChoiceChip(
                        label: assistantMemoryCategoryLabel(category),
                        selected: category == _category,
                        onSurface: true,
                        automationId: AutomationIds.settingsMemorySheetChip,
                        automationInstance: category.id,
                        onPressed: _readOnly || _busy
                            ? null
                            : () => setState(() {
                                _category = category;
                                _refused = null;
                              }),
                      ),
                  ],
                ),
                if (fact != null) _meta(context, fact),
                if (fact == null || _readOnly) ...[
                  SizedBox(height: 12 * k),
                  Text(_readOnly ? s.readOnly : s.privacy, style: label.copyWith(height: 1.4)),
                ],
                if (refused != null) ...[
                  SizedBox(height: 12 * k),
                  Text(
                    memoryCodeMessage(refused),
                    style: memoryText(context, 14, color: tk.accent, weight: FontWeight.w500, height: 1.4),
                  ),
                ],
                SizedBox(height: 18 * k),
                Row(
                  children: [
                    Expanded(
                      child: MemoryPillButton(
                        label: _readOnly ? t.common.close : t.common.cancel,
                        autofocus: tv && _readOnly,
                        automationId: AutomationIds.settingsMemorySheetButton,
                        automationInstance: 'cancel',
                        onPressed: widget.onClose,
                      ),
                    ),
                    if (!_readOnly) ...[
                      SizedBox(width: 10 * k),
                      Expanded(
                        child: MemoryPillButton(
                          label: t.common.save,
                          kind: MemoryPillKind.primary,
                          automationId: AutomationIds.settingsMemorySheetButton,
                          automationInstance: 'save',
                          onPressed: _canSave ? () => unawaited(_save()) : null,
                        ),
                      ),
                    ],
                  ],
                ),
                if (fact != null) ...[
                  SizedBox(height: 4 * k),
                  MemoryPillButton(
                    label: t.common.delete,
                    kind: MemoryPillKind.danger,
                    automationId: AutomationIds.settingsMemorySheetButton,
                    automationInstance: 'delete',
                    onPressed: _busy ? null : () => unawaited(_delete()),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The text of the memory: a field on a phone and a tablet, on TV a row
  /// that opens the system keyboard.
  Widget _field(BuildContext context, {required bool tv}) {
    final s = t.assistant.memory.screen.sheet;
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    final style = memoryText(context, 16, height: 1.4);
    final box = BoxDecoration(
      color: tk.bg,
      borderRadius: BorderRadius.circular(12 * k),
      border: Border.all(color: _fieldFocus.hasFocus ? tk.text.withValues(alpha: 0.55) : tk.outline),
    );
    if (tv || _readOnly) {
      final empty = _text.text.isEmpty;
      return MemoryPressable(
        radius: 12,
        focusNode: _fieldFocus,
        // The remote starts on the text, the first thing to change.
        autofocus: tv && !_readOnly,
        semanticLabel: empty ? s.hint : _text.text,
        automationId: AutomationIds.settingsMemorySheetField,
        automationRole: 'field',
        onPressed: tv && !_readOnly && !_busy ? () => unawaited(_editOnTv()) : null,
        child: Container(
          constraints: BoxConstraints(minHeight: 88 * k),
          padding: EdgeInsets.all(12 * k),
          alignment: Alignment.topLeft,
          decoration: box,
          child: Text(empty ? s.hint : _text.text, style: empty ? style.copyWith(color: memoryFaint(context)) : style),
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
        focusNode: _fieldFocus,
        child: FocusableTextField(
          controller: _text,
          focusNode: _fieldFocus,
          autofocus: _fact == null,
          enabled: !_busy,
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
          onSubmitted: (_) => _fieldFocus.unfocus(),
        ),
      ),
    );
  }

  /// Where the memory came from and when it was added and last changed.
  Widget _meta(BuildContext context, MemoryFact fact) {
    final s = t.assistant.memory.screen.sheet;
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    final style = memoryText(context, 13.5, color: tk.textMuted, height: 1.35);
    Widget row(String name, String value) => Padding(
      padding: EdgeInsets.symmetric(vertical: 7 * k),
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
      margin: EdgeInsets.only(top: 16 * k),
      padding: EdgeInsets.only(top: 4 * k),
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
