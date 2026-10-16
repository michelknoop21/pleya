import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import 'household_kid_format.dart';

/// How the birth month is chosen: wheels in the phone sheet (45 D), two
/// drop-downs in Big P's card (45 G), two cells the remote steps through on
/// TV (45 L).
enum HouseholdPickerStyle { wheel, dropdown, tv }

/// Month and year of birth. A future month cannot be chosen: the month falls
/// back to this month when the year is this year.
class HouseholdBirthPicker extends StatefulWidget {
  const HouseholdBirthPicker({
    super.key,
    required this.year,
    required this.month,
    required this.now,
    required this.style,
    required this.onChanged,
    this.monthNode,
    this.yearNode,
    this.onDone,
  });

  final int year;
  final int month;
  final DateTime now;
  final HouseholdPickerStyle style;
  final void Function(int year, int month) onChanged;

  /// TV: the two cells' focus nodes, and what OK does (jump to Bewaar).
  final FocusNode? monthNode;
  final FocusNode? yearNode;
  final VoidCallback? onDone;

  @override
  State<HouseholdBirthPicker> createState() => _HouseholdBirthPickerState();
}

class _HouseholdBirthPickerState extends State<HouseholdBirthPicker> {
  late final _monthWheel = FixedExtentScrollController(initialItem: widget.month - 1);
  late final _yearWheel = FixedExtentScrollController(initialItem: widget.year - _first);

  int get _first => householdFirstYear(widget.now);

  (int, int) _clamp(int year, int month) {
    final y = year.clamp(_first, widget.now.year);
    return (y, y == widget.now.year && month > widget.now.month ? widget.now.month : month.clamp(1, 12));
  }

  void _set(int year, int month) {
    final (y, m) = _clamp(year, month);
    if (widget.style == HouseholdPickerStyle.wheel) {
      // A wheel that stopped on a future month rolls back to this month.
      if (_monthWheel.hasClients && _monthWheel.selectedItem != m - 1) _monthWheel.jumpToItem(m - 1);
      if (_yearWheel.hasClients && _yearWheel.selectedItem != y - _first) _yearWheel.jumpToItem(y - _first);
    }
    if (y != widget.year || m != widget.month) widget.onChanged(y, m);
  }

  @override
  void dispose() {
    _monthWheel.dispose();
    _yearWheel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (widget.style) {
    HouseholdPickerStyle.wheel => _wheels(context),
    HouseholdPickerStyle.dropdown => _dropdowns(context),
    HouseholdPickerStyle.tv => _tv(context),
  };

  List<String> get _months => t.assistant.household.months;
  int get _years => widget.now.year - _first + 1;

  Widget _wheels(BuildContext context) {
    final tk = tokens(context);
    final style = TextStyle(color: tk.text, fontSize: 20);
    return Container(
      height: 150,
      decoration: BoxDecoration(color: tk.surfaceElevated, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: CupertinoPicker(
              scrollController: _monthWheel,
              itemExtent: 40,
              onSelectedItemChanged: (i) => _set(widget.year, i + 1),
              children: [for (final m in _months) Center(child: Text(m, style: style))],
            ),
          ),
          Expanded(
            child: CupertinoPicker(
              scrollController: _yearWheel,
              itemExtent: 40,
              onSelectedItemChanged: (i) => _set(_first + i, widget.month),
              children: [for (var i = 0; i < _years; i++) Center(child: Text('${_first + i}', style: style))],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdowns(BuildContext context) {
    final h = t.assistant.household;
    final last = widget.year == widget.now.year ? widget.now.month : 12;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<int>(
            initialValue: widget.month,
            decoration: InputDecoration(border: const OutlineInputBorder(), semanticCounterText: h.month),
            items: [for (var m = 1; m <= last; m++) DropdownMenuItem(value: m, child: Text(_months[m - 1]))],
            onChanged: (m) => m == null ? null : _set(widget.year, m),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<int>(
            initialValue: widget.year,
            decoration: InputDecoration(border: const OutlineInputBorder(), semanticCounterText: h.year),
            items: [for (var y = widget.now.year; y >= _first; y--) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (y) => y == null ? null : _set(y, widget.month),
          ),
        ),
      ],
    );
  }

  Widget _tv(BuildContext context) {
    final tk = tokens(context);
    Widget cell({
      required String label,
      required FocusNode? node,
      required VoidCallback up,
      required VoidCallback down,
      VoidCallback? left,
      VoidCallback? right,
      required String id,
    }) => Expanded(
      child: FocusableWrapper(
        focusNode: node,
        borderRadius: 16,
        disableScale: true,
        automationId: AutomationIds.householdKidsButton,
        automationInstance: id,
        automationRole: 'button',
        onNavigateUp: up,
        onNavigateDown: down,
        onNavigateLeft: left ?? () {},
        onNavigateRight: right,
        onSelect: widget.onDone,
        child: Container(
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tk.surfaceElevated, borderRadius: BorderRadius.circular(16)),
          child: Text(
            label,
            style: TextStyle(color: tk.text, fontSize: 28, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
    return Row(
      children: [
        cell(
          id: 'month',
          label: _months[widget.month - 1],
          node: widget.monthNode,
          // Up is the earlier month, down the later one.
          up: () => _set(widget.year, widget.month - 1),
          down: () => _set(widget.year, widget.month + 1),
          right: () => widget.yearNode?.requestFocus(),
        ),
        const SizedBox(width: 16),
        cell(
          id: 'year',
          label: '${widget.year}',
          node: widget.yearNode,
          up: () => _set(widget.year - 1, widget.month),
          down: () => _set(widget.year + 1, widget.month),
          left: () => widget.monthNode?.requestFocus(),
          right: () {},
        ),
      ],
    );
  }
}
