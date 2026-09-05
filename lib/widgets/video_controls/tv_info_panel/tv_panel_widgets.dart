import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/card_focus_scope.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../app_icon.dart';

/// Shared visual tokens for the TV player panel (mockup 33, DEC-101).
///
/// One card floating on the page inset, per section one surface with hairlines
/// between the rows, focus as a white fill with dark text. No red and no amber
/// as an "active" colour: an active value is plain white (TOK-1).
class TvPanelTheme {
  const TvPanelTheme._();

  /// The card behind the tabs; translucent so the picture shows through.
  static const Color card = Color(0xB3101010);

  /// Hairline around the card.
  static const Color cardBorder = Color(0x14FFFFFF);

  /// One section's surface.
  static const Color group = Color(0x0EFFFFFF);

  /// Divider between two rows of a group.
  static const Color hairline = Color(0x12FFFFFF);

  /// Pill background when inactive.
  static const Color inactivePill = Color(0x14FFFFFF);
  static const Color activePill = Colors.white;

  /// The focused row.
  static const Color focusFill = Color(0xEBFFFFFF);
  static const Color focusInk = Color(0xFF141414);
  static const Color focusInkMuted = Color(0x8C000000);

  static const Color textMuted = Color(0xB8FFFFFF);
  static const Color textFaint = Color(0x80FFFFFF);
  static const Color textDim = Color(0x4DFFFFFF);

  /// Legacy name kept for callers outside the panel; no longer painted here.
  static const Color accent = Colors.white;

  static const Color surface = card;

  static const double rowRadius = 14;
  static const double groupRadius = 18;
}

/// What a row does when it is selected, which also decides its trailing.
enum TvPanelRowKind {
  /// Runs an action or opens a sub-view; shows a value and a chevron.
  action,

  /// One of several exclusive choices; shows a radio or a check.
  choice,

  /// A value that LEFT/RIGHT step and Select cycles; shows ‹ value ›.
  value,

  /// On/off; shows a switch glyph.
  toggle,
}

/// Steps [current] through [values] by [delta], wrapping at both ends.
///
/// One helper rather than seven private modulo expressions: every value row in
/// the panel steps the same way, so a bug in the arithmetic is fixed once.
T stepValue<T>(List<T> values, T current, int delta, {bool Function(T a, T b)? equals}) {
  final eq = equals ?? (T a, T b) => a == b;
  var index = values.indexWhere((v) => eq(v, current));
  if (index < 0) index = 0;
  final next = (index + delta) % values.length;
  return values[next < 0 ? next + values.length : next];
}

/// A single focusable row in a TV panel section.
///
/// Two lines: [title] and an optional [subtitle] (the second line of a
/// `TrackLabel`, or the explanation of why a row is inert). The trailing
/// follows [kind]. Vertical D-pad movement between rows is the enclosing
/// [FocusScope]'s directional traversal; only the first row of a tab wires
/// [onNavigateUp] to return to the pill bar. LEFT and RIGHT reach the row only
/// when [onStepLeft]/[onStepRight] are set, so a choice row lets the traversal
/// cross into the other column.
class TvPanelRow extends StatelessWidget {
  final FocusNode? focusNode;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? value;
  final bool selected;
  final bool showChevron;
  final bool highlighted;
  final bool toggled;
  final bool dimmed;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onSelect;
  final VoidCallback? onStepLeft;
  final VoidCallback? onStepRight;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final bool autofocus;
  final bool canRequestFocus;
  final TvPanelRowKind kind;
  final String? automationId;
  final String? automationInstance;
  final Object? Function()? automationState;

  const TvPanelRow({
    super.key,
    this.focusNode,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.selected = false,
    this.showChevron = false,
    this.highlighted = false,
    this.toggled = false,
    this.dimmed = false,
    this.trailing,
    this.leading,
    this.onSelect,
    this.onStepLeft,
    this.onStepRight,
    this.onNavigateUp,
    this.onNavigateDown,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.kind = TvPanelRowKind.action,
    this.automationId,
    this.automationInstance,
    this.automationState,
  });

  /// A row whose value LEFT/RIGHT step and Select cycles.
  const TvPanelRow.value({
    super.key,
    this.focusNode,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.highlighted = false,
    this.dimmed = false,
    this.onSelect,
    this.onStepLeft,
    this.onStepRight,
    this.onNavigateUp,
    this.onNavigateDown,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.automationId,
    this.automationInstance,
    this.automationState,
  }) : kind = TvPanelRowKind.value,
       selected = false,
       showChevron = false,
       toggled = false,
       trailing = null,
       leading = null;

  /// One of several exclusive choices.
  const TvPanelRow.choice({
    super.key,
    this.focusNode,
    this.icon,
    this.leading,
    required this.title,
    this.subtitle,
    this.value,
    required this.selected,
    this.trailing,
    this.onSelect,
    this.onNavigateUp,
    this.onNavigateDown,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.automationId,
    this.automationInstance,
    this.automationState,
  }) : kind = TvPanelRowKind.choice,
       showChevron = false,
       highlighted = false,
       toggled = false,
       dimmed = false,
       onStepLeft = null,
       onStepRight = null;

  /// On/off.
  const TvPanelRow.toggle({
    super.key,
    this.focusNode,
    this.icon,
    required this.title,
    this.subtitle,
    required this.toggled,
    this.dimmed = false,
    this.onSelect,
    this.onNavigateUp,
    this.onNavigateDown,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.automationId,
    this.automationInstance,
    this.automationState,
  }) : kind = TvPanelRowKind.toggle,
       value = null,
       selected = false,
       showChevron = false,
       highlighted = false,
       trailing = null,
       leading = null,
       onStepLeft = null,
       onStepRight = null;

  Object? _state() {
    final extra = automationState?.call();
    return {
      'kind': kind.name,
      if (value != null) 'value': value,
      if (kind == TvPanelRowKind.choice) 'selected': selected,
      if (kind == TvPanelRowKind.toggle) 'on': toggled,
      if (dimmed) 'dimmed': true,
      if (extra is Map) ...extra.cast<String, Object?>(),
    };
  }

  @override
  Widget build(BuildContext context) {
    // A dimmed row stays focusable unless the caller says otherwise, so a
    // column never loses its focus when a setting elsewhere makes it inert.
    return FocusableWrapper(
      focusNode: focusNode,
      autofocus: autofocus,
      canRequestFocus: canRequestFocus,
      onSelect: onSelect,
      onNavigateLeft: onStepLeft,
      onNavigateRight: onStepRight,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      borderRadius: TvPanelTheme.rowRadius,
      autoScroll: true,
      // The row paints its own focus (white fill, dark ink): the wrapper's
      // translucent fill cannot recolour the text underneath it.
      mode: FocusIndicatorMode.delegated,
      disableScale: true,
      automationId: automationId,
      automationInstance: automationInstance,
      automationRole: kind.name,
      automationState: automationId == null ? null : _state,
      child: Builder(
        builder: (context) {
          final focused = CardFocusScope.maybeOf(context) ?? false;
          return _TvPanelRowBody(row: this, focused: focused);
        },
      ),
    );
  }
}

class _TvPanelRowBody extends StatelessWidget {
  const _TvPanelRowBody({required this.row, required this.focused});

  final TvPanelRow row;
  final bool focused;

  Color get _ink => focused ? TvPanelTheme.focusInk : (row.dimmed ? TvPanelTheme.textMuted : Colors.white);
  Color get _inkMuted => focused ? TvPanelTheme.focusInkMuted : (row.dimmed ? TvPanelTheme.textDim : TvPanelTheme.textFaint);
  Color get _inkValue =>
      focused ? TvPanelTheme.focusInk : (row.dimmed ? TvPanelTheme.textFaint : (row.highlighted ? Colors.white : TvPanelTheme.textMuted));

  @override
  Widget build(BuildContext context) {
    final trailing = row.trailing ?? _buildTrailing();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: focused ? TvPanelTheme.focusFill : Colors.transparent,
        borderRadius: BorderRadius.circular(TvPanelTheme.rowRadius),
      ),
      child: Row(
        children: [
          if (row.leading != null) ...[row.leading!, const SizedBox(width: 16)],
          if (row.icon != null) ...[
            AppIcon(row.icon!, fill: 1, color: _ink, size: 22),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 17,
                    fontWeight: row.selected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (row.subtitle != null && row.subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      row.subtitle!,
                      style: TextStyle(color: _inkMuted, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            // Cap the trailing width so a long value ellipsizes inside the row
            // instead of overflowing past the group's edge.
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 300), child: trailing),
          ],
        ],
      ),
    );
  }

  Widget? _buildTrailing() {
    switch (row.kind) {
      case TvPanelRowKind.choice:
        return _ChoiceMark(selected: row.selected, focused: focused, value: row.value, valueColor: _inkValue);
      case TvPanelRowKind.toggle:
        return _SwitchGlyph(on: row.toggled, focused: focused, dimmed: row.dimmed);
      case TvPanelRowKind.value:
        final chevronColor = focused ? TvPanelTheme.focusInk : TvPanelTheme.textDim;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(Symbols.chevron_left_rounded, fill: 1, color: chevronColor, size: 20),
            const SizedBox(width: 6),
            Flexible(child: _valueText()),
            const SizedBox(width: 6),
            AppIcon(Symbols.chevron_right_rounded, fill: 1, color: chevronColor, size: 20),
          ],
        );
      case TvPanelRowKind.action:
        final children = <Widget>[];
        if (row.value != null && row.value!.isNotEmpty) children.add(Flexible(child: _valueText()));
        if (row.showChevron) {
          if (children.isNotEmpty) children.add(const SizedBox(width: 8));
          children.add(
            AppIcon(
              Symbols.chevron_right_rounded,
              fill: 1,
              color: focused ? TvPanelTheme.focusInkMuted : TvPanelTheme.textDim,
              size: 20,
            ),
          );
        }
        if (children.isEmpty) return null;
        return Row(mainAxisSize: MainAxisSize.min, children: children);
    }
  }

  Widget _valueText() => Text(
    row.value ?? '',
    style: TextStyle(color: _inkValue, fontSize: 16),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.end,
  );
}

class _ChoiceMark extends StatelessWidget {
  const _ChoiceMark({required this.selected, required this.focused, this.value, required this.valueColor});

  final bool selected;
  final bool focused;
  final String? value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final mark = selected
        ? Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: focused ? TvPanelTheme.focusInk : Colors.white,
            ),
            child: AppIcon(
              Symbols.check_rounded,
              fill: 1,
              color: focused ? Colors.white : TvPanelTheme.focusInk,
              size: 15,
            ),
          )
        : Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: focused ? TvPanelTheme.focusInkMuted : TvPanelTheme.textFaint, width: 1.5),
            ),
          );
    if (value == null || value!.isEmpty) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(value!, style: TextStyle(color: valueColor, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 12),
        mark,
      ],
    );
  }
}

class _SwitchGlyph extends StatelessWidget {
  const _SwitchGlyph({required this.on, required this.focused, required this.dimmed});

  final bool on;
  final bool focused;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final track = on
        ? (focused ? TvPanelTheme.focusInk : Colors.white)
        : (focused ? const Color(0x2E000000) : const Color(0x24FFFFFF));
    final knob = on
        ? (focused ? Colors.white : TvPanelTheme.focusInk)
        : (focused ? TvPanelTheme.focusInkMuted : TvPanelTheme.textMuted);
    return Opacity(
      opacity: dimmed ? 0.5 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 46,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(999)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 120),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, color: knob),
          ),
        ),
      ),
    );
  }
}

/// A small uppercase section label, aligned with the row text.
class TvPanelSectionHeader extends StatelessWidget {
  final String label;
  const TvPanelSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: TvPanelTheme.textFaint,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// One section: a rounded surface holding rows separated by hairlines.
class TvPanelGroup extends StatelessWidget {
  const TvPanelGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(height: 1, child: ColoredBox(color: TvPanelTheme.hairline)),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TvPanelTheme.group,
        borderRadius: BorderRadius.circular(TvPanelTheme.groupRadius),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// A non-focusable pointer row: where a setting lives when it is not here.
class TvPanelStaticRow extends StatelessWidget {
  const TvPanelStaticRow({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TvPanelTheme.rowRadius),
        border: Border.all(color: TvPanelTheme.hairline, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(color: TvPanelTheme.textMuted, fontSize: 17, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(subtitle, style: const TextStyle(color: TvPanelTheme.textDim, fontSize: 13), maxLines: 2),
        ],
      ),
    );
  }
}

/// Two-column tab body: each column is its own traversal group and scrolls on
/// its own, so a long list on one side never pushes the other off the card.
class TvPanelColumns extends StatelessWidget {
  const TvPanelColumns({super.key, required this.left, required this.right});

  final List<Widget> left;
  final List<Widget> right;

  @override
  Widget build(BuildContext context) {
    Widget column(List<Widget> children) => FocusTraversalGroup(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: column(left)),
        const SizedBox(width: 28),
        Expanded(child: column(right)),
      ],
    );
  }
}
