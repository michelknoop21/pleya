import 'dart:async';

import 'package:flutter/material.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/speech_search_service.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/big_p/assistant/big_p_memory_card.dart' show assistantMemoryCategoryLabel;
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/overlay_sheet_geometry.dart';
import 'memory_dialogs.dart';
import 'memory_fact_sheet_parts.dart';
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
  final media = MediaQuery.of(context);
  return OverlaySheetController.showAdaptive<void>(
    context,
    backgroundColor: tokens(context).surface,
    isScrollControlled: true,
    // Up to the status bar instead of three quarters of a phone or 400 pt on
    // a tablet: the text stays in view above the keyboard of a small phone,
    // and a tablet shows the whole sheet.
    constraints: tv ? null : BoxConstraints(maxWidth: 700, maxHeight: media.size.height - media.padding.top - 8),
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
  final _cancelFocus = FocusNode(debugLabel: 'memory.sheet.cancel');
  final _saveFocus = FocusNode(debugLabel: 'memory.sheet.save');
  final _chipFocus = {
    for (final category in MemoryCategory.values) category: FocusNode(debugLabel: 'memory.sheet.chip.${category.id}'),
  };
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
    _cancelFocus.dispose();
    _saveFocus.dispose();
    for (final node in _chipFocus.values) {
      node.dispose();
    }
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
    // Gone already is gone: the list read the facts again and shows none.
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

  /// TV: the chip in the row under or above [from] that stands closest to it,
  /// or null where [from] is in the last or the first row.
  FocusNode? _chipBeside(MemoryCategory from, {required bool down}) {
    final here = _chipFocus[from]!.rect;
    FocusNode? best;
    var bestRow = double.infinity;
    var bestAcross = double.infinity;
    for (final node in _chipFocus.values) {
      final rect = node.rect;
      final row = down ? rect.top - here.top : here.top - rect.top;
      if (!node.canRequestFocus || row < here.height / 2) continue;
      final across = (rect.center.dx - here.center.dx).abs();
      if (row < bestRow - 1 || ((row - bestRow).abs() <= 1 && across < bestAcross)) {
        best = node;
        bestRow = row;
        bestAcross = across;
      }
    }
    return best;
  }

  /// TV: the arrows of a category chip. Left and Right walk all five in
  /// order, across the rows; Up and Down go a row at a time, so no chip is
  /// passed over on the way to the buttons.
  ({VoidCallback up, VoidCallback down, VoidCallback left, VoidCallback right}) _chipArrows(MemoryCategory category) {
    const all = MemoryCategory.values;
    final at = all.indexOf(category);
    return (
      up: () => (_chipBeside(category, down: false) ?? _fieldFocus).requestFocus(),
      down: () => (_chipBeside(category, down: true) ?? (_canSave ? _saveFocus : _cancelFocus)).requestFocus(),
      left: () {
        if (at > 0) _chipFocus[all[at - 1]]!.requestFocus();
      },
      right: () {
        if (at < all.length - 1) _chipFocus[all[at + 1]]!.requestFocus();
      },
    );
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
    // The remote walks the chips by hand; a keyboard on a tablet keeps the
    // focus traversal.
    final arrows = tv && !_readOnly;
    final toChosenChip = arrows ? () => _chipFocus[_category]!.requestFocus() : null;
    final media = MediaQuery.of(context);
    final keyboard = tv ? 0.0 : media.viewInsets.bottom;
    // The buttons stay under the scrolling content, so they are in view with
    // the keyboard open (iPhone SE) and in the TV panel. Where next to nothing
    // is left above the keyboard they scroll with the rest.
    final pinned = tv || media.size.height - keyboard - media.padding.top >= 360 * media.textScaler.scale(1);

    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MemoryButtonPair(
          first: MemoryPillButton(
            label: _readOnly ? t.common.close : t.common.cancel,
            autofocus: tv && _readOnly,
            focusNode: _cancelFocus,
            automationId: AutomationIds.settingsMemorySheetButton,
            automationInstance: 'cancel',
            onPressed: widget.onClose,
            onNavigateUp: toChosenChip,
          ),
          second: _readOnly
              ? null
              : MemoryPillButton(
                  label: t.common.save,
                  kind: MemoryPillKind.primary,
                  focusNode: _saveFocus,
                  automationId: AutomationIds.settingsMemorySheetButton,
                  automationInstance: 'save',
                  // Still a focus stop while it saves: the remote keeps a
                  // place to stand until the sheet closes.
                  onPressed: _canSave || _busy ? () => unawaited(_save()) : null,
                  onNavigateUp: toChosenChip,
                ),
        ),
        if (fact != null) ...[
          SizedBox(height: 4 * k),
          MemoryPillButton(
            label: t.common.delete,
            kind: MemoryPillKind.danger,
            automationId: AutomationIds.settingsMemorySheetButton,
            automationInstance: 'delete',
            onPressed: () => unawaited(_delete()),
          ),
        ],
      ],
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!tv) const MemorySheetGrab(),
        Text(fact == null ? s.addTitle : s.title, style: memoryText(context, 20, weight: FontWeight.w700)),
        SizedBox(height: (tv ? 12 : 16) * k),
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
        MemoryFactField(
          text: _text,
          focusNode: _fieldFocus,
          tv: tv,
          readOnly: _readOnly,
          busy: _busy,
          autofocus: fact == null,
          onEdit: () => unawaited(_editOnTv()),
          onNavigateDown: toChosenChip,
        ),
        SizedBox(height: (tv ? 12 : 16) * k),
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
                focusNode: _chipFocus[category],
                onNavigateUp: arrows ? _chipArrows(category).up : null,
                onNavigateDown: arrows ? _chipArrows(category).down : null,
                onNavigateLeft: arrows ? _chipArrows(category).left : null,
                onNavigateRight: arrows ? _chipArrows(category).right : null,
                onPressed: _readOnly || _busy
                    ? null
                    : () => setState(() {
                        _category = category;
                        _refused = null;
                      }),
              ),
          ],
        ),
        if (fact != null) MemoryFactMeta(fact: fact, compact: tv),
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
        if (!pinned) ...[SizedBox(height: 18 * k), buttons],
      ],
    );

    return AutomationNode(
      id: AutomationIds.settingsMemorySheet,
      role: 'sheet',
      state: () => {'mode': _mode, 'refused': _refused?.name},
      child: SafeArea(
        top: false,
        child: Padding(
          // Above the keyboard, where no page above has made room for it yet.
          padding: EdgeInsets.only(bottom: keyboard),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16 * k, 10 * k, 16 * k, (pinned ? 0 : 14) * k),
                  child: content,
                ),
              ),
              if (pinned)
                Padding(padding: EdgeInsets.fromLTRB(16 * k, (tv ? 14 : 18) * k, 16 * k, 14 * k), child: buttons),
            ],
          ),
        ),
      ),
    );
  }
}
