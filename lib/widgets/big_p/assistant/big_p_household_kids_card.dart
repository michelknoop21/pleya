import 'dart:async';

import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/focusable_text_field.dart';
import '../../../i18n/strings.g.dart';
import '../../../profiles/household_kids_store.dart';
import '../../../screens/settings/household_kids/household_birth_picker.dart';
import '../../../screens/settings/household_kids/household_kid_format.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/tv_hig.dart';
import '../../pleya_wordmark.dart';
import '../big_p_scale.dart';
import 'big_p_assistant_widgets.dart';

/// The Pleya card that asks which children there are (45 G, not a message
/// from Big P): name, birth month and year, "Nog een kind toevoegen" for
/// more, and Bewaar en zoek verder, which hands the children to [onSave] so
/// the question is asked again. Names stay on this device. It only shows on a
/// profile that is not a children's profile, so the store accepts the write.
class BigPHouseholdKidsCard extends StatefulWidget {
  const BigPHouseholdKidsCard({
    super.key,
    required this.onSave,
    this.firstNode,
    this.onClose,
    this.loadExisting,
    this.embedded = false,
    this.now,
    this.style,
  });

  final ValueChanged<List<HouseholdKid>> onSave;

  /// Gets the name field, for the surface's initial focus.
  final FocusNode? firstNode;

  /// Closes the card unanswered; the way out when the household is full.
  final VoidCallback? onClose;

  /// The children already stored, which the card adds to and never replaces.
  /// Tests inject it; the app reads the store.
  final Future<List<HouseholdKid>> Function()? loadExisting;

  /// Inside Big P's balloon (39 G): the balloon is the card.
  final bool embedded;
  final DateTime? now;
  final HouseholdPickerStyle? style;

  @override
  State<BigPHouseholdKidsCard> createState() => _BigPHouseholdKidsCardState();
}

class _BigPHouseholdKidsCardState extends State<BigPHouseholdKidsCard> {
  final _name = TextEditingController();
  final _kids = <HouseholdKid>[];
  int _existing = 0;
  bool _saved = false;
  final _monthNode = FocusNode(debugLabel: 'household.card.month');
  final _yearNode = FocusNode(debugLabel: 'household.card.year');
  final _saveNode = FocusNode(debugLabel: 'household.card.save');
  late final DateTime _now = widget.now ?? DateTime.now();
  late int _year = _now.year;
  late int _month = _now.month;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    unawaited(
      (widget.loadExisting ?? HouseholdKidsStore().read)().then((kids) {
        if (mounted) setState(() => _existing = kids.length);
      }),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _monthNode.dispose();
    _yearNode.dispose();
    _saveNode.dispose();
    super.dispose();
  }

  bool get _typed => _name.text.trim().isNotEmpty;
  bool get _room => _existing + _kids.length < HouseholdKidsStore.maxKids;

  HouseholdKid get _current =>
      HouseholdKid(id: newHouseholdKidId(), name: _name.text.trim(), birthMonth: householdBirthMonth(_year, _month));

  void _addAnother() {
    if (!_typed || !_room) return;
    setState(() {
      _kids.add(_current);
      _name.clear();
    });
  }

  void _save() {
    // A double tap must not ask the question twice.
    if (_saved) return;
    final all = [..._kids, if (_typed && _room) _current];
    if (all.isEmpty) return;
    _saved = true;
    widget.onSave(all);
  }

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    final h = t.assistant.household;
    final style = widget.style ?? (PlatformDetector.isTV() ? HouseholdPickerStyle.tv : HouseholdPickerStyle.dropdown);
    final muted = TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption1 * pt);
    final full = _existing >= HouseholdKidsStore.maxKids;
    final canSave = _kids.isNotEmpty || (_typed && _room);
    final save = BigPButton(
      label: full ? t.common.close : h.saveAndSearch,
      primary: true,
      enabled: full ? widget.onClose != null : canSave,
      focusNode: _saveNode,
      automationId: AutomationIds.householdKidsButton,
      automationInstance: 'cardSave',
      onPressed: full ? () => widget.onClose?.call() : _save,
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Image.asset(PleyaWordmark.markAsset, height: TvHig.caption1 * pt, filterQuality: FilterQuality.medium),
            SizedBox(width: 12 * pt),
            Expanded(child: Text(t.assistant.kids.header, style: muted)),
          ],
        ),
        SizedBox(height: 10 * pt),
        Text(
          h.cardTitle,
          style: TextStyle(color: tk.text, fontSize: TvHig.title3 * pt * 0.8, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8 * pt),
        Text(h.cardBody, style: muted.copyWith(height: 1.3)),
        SizedBox(height: 16 * pt),
        for (final kid in _kids)
          Container(
            margin: EdgeInsets.only(bottom: 8 * pt),
            padding: EdgeInsets.symmetric(horizontal: 16 * pt, vertical: 12 * pt),
            decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(16 * pt)),
            child: Row(
              children: [
                Text(
                  kid.name,
                  style: TextStyle(color: tk.text, fontWeight: FontWeight.w700),
                ),
                SizedBox(width: 12 * pt),
                Expanded(child: Text(householdMonthLabel(kid.birthMonth), style: muted)),
                Text(householdAgeLabel(kid, _now), style: muted),
              ],
            ),
          ),
        if (full)
          Text(h.cardFull, style: muted.copyWith(height: 1.3))
        else if (_room) ...[
          Text(h.name, style: muted),
          SizedBox(height: 6 * pt),
          FocusableTextField(
            controller: _name,
            focusNode: widget.firstNode,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 40,
            decoration: InputDecoration(border: const OutlineInputBorder(), counterText: '', hintText: h.name),
            onNavigateDown: style == HouseholdPickerStyle.tv ? _monthNode.requestFocus : null,
          ),
          SizedBox(height: 12 * pt),
          Text(h.birth, style: muted),
          SizedBox(height: 6 * pt),
          HouseholdBirthPicker(
            year: _year,
            month: _month,
            now: _now,
            style: style,
            monthNode: _monthNode,
            yearNode: _yearNode,
            onDone: _saveNode.requestFocus,
            onLeftFromMonth: widget.firstNode?.requestFocus,
            onChanged: (y, m) => setState(() {
              _year = y;
              _month = m;
            }),
          ),
          SizedBox(height: 8 * pt),
          BigPButton(
            label: h.addAnother,
            icon: Icons.add,
            enabled: _typed,
            restFill: Colors.transparent,
            automationId: AutomationIds.householdKidsButton,
            automationInstance: 'cardAdd',
            onPressed: _addAnother,
          ),
        ] else
          Text(h.limit, style: muted),
      ],
    );

    return AutomationNode(
      id: AutomationIds.assistantHouseholdKids,
      role: 'sheet',
      state: () => {'kids': _kids.length + (_typed ? 1 : 0)},
      child: Container(
        padding: widget.embedded ? null : EdgeInsets.all(48 * pt),
        decoration: widget.embedded
            ? null
            : BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(28 * pt)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // In the balloon the fields scroll and Bewaar stays put (39 G).
            Flexible(child: SingleChildScrollView(child: body)),
            SizedBox(height: 24 * pt),
            widget.embedded ? save : Align(alignment: Alignment.centerRight, child: save),
          ],
        ),
      ),
    );
  }
}
