import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/focusable_text_field.dart';
import '../../../i18n/strings.g.dart';
import '../../../profiles/household_kids_store.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/big_p/assistant/big_p_assistant_widgets.dart';
import '../../../widgets/overlay_sheet.dart';
import 'household_birth_picker.dart';
import 'household_kid_format.dart';

/// What the sheet hands back when the child is to be deleted.
class HouseholdKidDelete {
  const HouseholdKidDelete();
}

/// Kind toevoegen / Kind bewerken (45 D, E, F, K, L): one sheet for both.
/// Pops the saved [HouseholdKid], a [HouseholdKidDelete] after the
/// confirmation, or null for Annuleren. Rises as a bottom sheet on a phone and
/// as the centred panel on TV, where the picker is stepped with the remote.
Future<Object?> showHouseholdKidSheet(
  BuildContext context, {
  HouseholdKid? kid,
  bool onlyKid = false,
  DateTime? now,
  HouseholdPickerStyle? style,
}) => OverlaySheetController.showAdaptive<Object>(
  context,
  isScrollControlled: true,
  restoreLauncherFocus: true,
  builder: (_) => HouseholdKidSheet(
    kid: kid,
    onlyKid: onlyKid,
    now: now ?? DateTime.now(),
    style: style ?? (PlatformDetector.isTV() ? HouseholdPickerStyle.tv : HouseholdPickerStyle.wheel),
  ),
);

class HouseholdKidSheet extends StatefulWidget {
  const HouseholdKidSheet({super.key, this.kid, this.onlyKid = false, required this.now, required this.style});

  final HouseholdKid? kid;

  /// The only child: Verwijderen warns that Big P asks for the children again.
  final bool onlyKid;
  final DateTime now;
  final HouseholdPickerStyle style;

  @override
  State<HouseholdKidSheet> createState() => _HouseholdKidSheetState();
}

class _HouseholdKidSheetState extends State<HouseholdKidSheet> {
  late final _name = TextEditingController(text: widget.kid?.name ?? '');
  final _nameNode = FocusNode(debugLabel: 'household.name');
  final _monthNode = FocusNode(debugLabel: 'household.month');
  final _yearNode = FocusNode(debugLabel: 'household.year');
  final _saveNode = FocusNode(debugLabel: 'household.save');
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final birth = widget.kid?.birthMonth;
    _year = birth == null ? widget.now.year : int.parse(birth.substring(0, 4));
    _month = birth == null ? widget.now.month : int.parse(birth.substring(5, 7));
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _nameNode.dispose();
    _monthNode.dispose();
    _yearNode.dispose();
    _saveNode.dispose();
    super.dispose();
  }

  HouseholdKid get _draft => HouseholdKid(
    id: widget.kid?.id ?? newHouseholdKidId(),
    name: _name.text.trim(),
    birthMonth: householdBirthMonth(_year, _month),
  );

  /// "Wordt nu 3 jaar"; a newborn has no age to become yet.
  String get _preview {
    final h = t.assistant.household;
    final age = householdAgeLabel(_draft, widget.now);
    final months = _draft.monthsAt(widget.now);
    return months == null || months == 0 ? age : h.preview(age: age);
  }

  Future<void> _delete() async {
    final h = t.assistant.household;
    final sure = await showConfirmDialog(
      context,
      title: h.deleteTitle(name: widget.kid!.name),
      message: widget.onlyKid ? '${h.deleteBody} ${h.deleteLast}' : h.deleteBody,
      confirmText: h.delete,
      isDestructive: true,
    );
    if (sure && mounted) Navigator.of(context).pop(const HouseholdKidDelete());
  }

  @override
  Widget build(BuildContext context) {
    final h = t.assistant.household;
    final tk = tokens(context);
    final tv = widget.style == HouseholdPickerStyle.tv;
    final canSave = _name.text.trim().isNotEmpty;
    final label = TextStyle(color: tk.textMuted, fontSize: tv ? 22 : 14);
    return AutomationNode(
      id: AutomationIds.householdKidSheet,
      role: 'sheet',
      state: () => {'birthMonth': householdBirthMonth(_year, _month)},
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.kid == null ? h.add : h.edit,
                style: TextStyle(color: tk.text, fontSize: tv ? 36 : 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              Text(h.name, style: label),
              const SizedBox(height: 8),
              AutomationNode(
                id: AutomationIds.householdKidsField,
                role: 'field',
                focusNode: _nameNode,
                child: FocusableTextField(
                  focusNode: _nameNode,
                  controller: _name,
                  autofocus: widget.kid == null,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  maxLength: 40,
                  decoration: InputDecoration(border: const OutlineInputBorder(), counterText: '', hintText: h.name),
                  onNavigateDown: tv ? _monthNode.requestFocus : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(h.birth, style: label),
              const SizedBox(height: 8),
              HouseholdBirthPicker(
                year: _year,
                month: _month,
                now: widget.now,
                style: widget.style,
                monthNode: _monthNode,
                yearNode: _yearNode,
                onDone: _saveNode.requestFocus,
                onLeftFromMonth: _nameNode.requestFocus,
                onChanged: (y, m) => setState(() {
                  _year = y;
                  _month = m;
                }),
              ),
              const SizedBox(height: 12),
              Text(tv ? '${h.tvHint} $_preview' : _preview, style: label),
              const SizedBox(height: 20),
              if (widget.kid != null) ...[
                BigPButton(
                  label: h.delete,
                  restFill: tk.surfaceElevated,
                  automationId: AutomationIds.householdKidsButton,
                  automationInstance: 'delete',
                  onPressed: _delete,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: BigPButton(
                      label: t.common.cancel,
                      restFill: tk.surfaceElevated,
                      automationId: AutomationIds.householdKidsButton,
                      automationInstance: 'cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BigPButton(
                      label: h.save,
                      primary: true,
                      enabled: canSave,
                      focusNode: _saveNode,
                      automationId: AutomationIds.householdKidsButton,
                      automationInstance: 'save',
                      onPressed: () => Navigator.of(context).pop(_draft),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
