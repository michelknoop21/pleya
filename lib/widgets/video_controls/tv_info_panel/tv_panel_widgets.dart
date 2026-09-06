import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/card_focus_scope.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../app_icon.dart';
import 'tv_panel_value_row_scope.dart';

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

  /// A value Select enters, after which LEFT and RIGHT step it (DEC-102);
  /// shows ‹ value › while entered and the bare value at rest.
  value,

  /// On/off; shows a switch glyph.
  toggle,
}

int _indexOfValue<T>(List<T> values, T current, bool Function(T a, T b)? equals) {
  final eq = equals ?? (T a, T b) => a == b;
  final index = values.indexWhere((v) => eq(v, current));
  return index < 0 ? 0 : index;
}

/// The neighbour [delta] steps away, or null when [current] already sits at
/// that end of [values].
///
/// A step past the end does nothing rather than wrapping: RIGHT on +200%
/// dropping the volume boost back to Off was the old behaviour and it surprised
/// people. Leaving the column sideways is no longer this null's job — a row at
/// rest never takes LEFT or RIGHT at all (DEC-102) — but the clamp still holds
/// the ring inside an entered row.
T? stepValueClamped<T>(List<T> values, T current, int delta, {bool Function(T a, T b)? equals}) {
  final next = _indexOfValue(values, current, equals) + delta;
  return next < 0 || next >= values.length ? null : values[next];
}

/// The LEFT/RIGHT callbacks of a value row, clamped at both ends.
({VoidCallback? left, VoidCallback? right}) clampedSteps<T>(
  List<T> values,
  T current,
  void Function(T value) apply, {
  bool Function(T a, T b)? equals,
}) {
  final previous = stepValueClamped(values, current, -1, equals: equals);
  final next = stepValueClamped(values, current, 1, equals: equals);
  return (left: previous == null ? null : () => apply(previous), right: next == null ? null : () => apply(next));
}

/// A single focusable row in a TV panel section.
///
/// Two lines: [title] and an optional [subtitle] (the second line of a
/// `TrackLabel`, or the explanation of why a row is inert). The trailing
/// follows [kind]. Vertical D-pad movement between rows is the enclosing
/// [FocusScope]'s directional traversal; only the first row of a tab wires
/// [onNavigateUp] to return to the pill bar.
///
/// A row with [onStepLeft] or [onStepRight] is *entered* before it steps
/// (DEC-102): Select enters it, and only then do LEFT and RIGHT reach the row.
/// At rest the traversal gets them, so the ring leaves the column wherever the
/// value happens to sit. Select on an entered row leaves it again; so does
/// Menu, and so does any move that takes the focus elsewhere. Entering is
/// tracked by [TvPanelValueRowController] one level up, so at most one row in
/// the panel is entered.
class TvPanelRow extends StatefulWidget {
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

  /// Whether Select enters this row before LEFT and RIGHT step it (DEC-102).
  /// The sync sub-view opts out: it is a single row on its own page with its
  /// own footer promising a direct 100 ms step, so there is no column to leave
  /// and nothing for the two-state model to buy.
  final bool entersOnSelect;
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
    this.entersOnSelect = true,
    this.kind = TvPanelRowKind.action,
    this.automationId,
    this.automationInstance,
    this.automationState,
  });

  /// A row Select enters, after which LEFT and RIGHT step its value.
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
    this.entersOnSelect = true,
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
       entersOnSelect = true,
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
       entersOnSelect = true,
       value = null,
       selected = false,
       showChevron = false,
       highlighted = false,
       trailing = null,
       leading = null,
       onStepLeft = null,
       onStepRight = null;

  /// Whether Select enters this row instead of activating it.
  bool get stepsValue => entersOnSelect && (onStepLeft != null || onStepRight != null);

  @override
  State<TvPanelRow> createState() => _TvPanelRowState();
}

class _TvPanelRowState extends State<TvPanelRow> {
  TvPanelValueRowController? _values;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _values = TvPanelValueRowScope.maybeOf(context);
  }

  @override
  void dispose() {
    // After the frame: a tab switch disposes its rows while the tree is being
    // rebuilt, and notifying listeners there would rebuild during a build.
    // The token keeps its identity, so a row that was already left does
    // nothing and one that was entered cannot clear a newer entry.
    final values = _values;
    if (values != null && values.isEntered(this)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => values.leave(this));
    }
    super.dispose();
  }

  bool get _entered => _values?.isEntered(this) ?? false;

  /// Select. On a stepping row this is the enter/leave toggle and nothing
  /// else: DEC-102 (2) drops the old "Select cycles forward", because one key
  /// cannot do both. Only [handleOneShotSelect] runs it, so it fires on the
  /// key-down and the release is consumed by the wrapper — there is no second
  /// suppressor to arm, and arming one would be the pin-open leak that
  /// `handleBackKeyAction` documents.
  VoidCallback? get _onSelect {
    final values = _values;
    if (!widget.stepsValue || values == null) return widget.onSelect;
    return () => values.toggle(this);
  }

  Object? _state() {
    final extra = widget.automationState?.call();
    return {
      'kind': widget.kind.name,
      if (widget.value != null) 'value': widget.value,
      if (widget.kind == TvPanelRowKind.choice) 'selected': widget.selected,
      if (widget.kind == TvPanelRowKind.toggle) 'on': widget.toggled,
      if (widget.dimmed) 'dimmed': true,
      if (widget.stepsValue) 'entered': _entered,
      if (extra is Map) ...extra.cast<String, Object?>(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final entered = _entered;
    // A row outside the two-state model (the sync sub-view, and any row whose
    // steps are both absent) keeps its horizontal keys at all times.
    final takesSteps = entered || !widget.stepsValue;
    // A dimmed row stays focusable unless the caller says otherwise, so a
    // column never loses its focus when a setting elsewhere makes it inert.
    return FocusableWrapper(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.canRequestFocus,
      onSelect: _onSelect,
      // Only an entered row takes the horizontal keys; at rest they belong to
      // the traversal so the ring can cross to the other column (PLR5).
      onNavigateLeft: takesSteps ? widget.onStepLeft : null,
      onNavigateRight: takesSteps ? widget.onStepRight : null,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      // A move that takes the focus away leaves the row in the same press.
      onFocusChange: (hasFocus) {
        if (!hasFocus) _values?.leave(this);
      },
      borderRadius: TvPanelTheme.rowRadius,
      autoScroll: true,
      // The row paints its own focus (white fill, dark ink): the wrapper's
      // translucent fill cannot recolour the text underneath it.
      mode: FocusIndicatorMode.delegated,
      disableScale: true,
      automationId: widget.automationId,
      automationInstance: widget.automationInstance,
      automationRole: widget.kind.name,
      automationState: widget.automationId == null ? null : _state,
      child: Builder(
        builder: (context) {
          final focused = CardFocusScope.maybeOf(context) ?? false;
          return _TvPanelRowBody(row: widget, focused: focused, entered: entered);
        },
      ),
    );
  }
}

class _TvPanelRowBody extends StatelessWidget {
  const _TvPanelRowBody({required this.row, required this.focused, this.entered = false});

  final TvPanelRow row;
  final bool focused;

  /// A stepping row that Select has entered. The arrows are the only thing
  /// that says so: without them the state works and nothing shows it, which is
  /// the [DEC-053] failure again.
  final bool entered;

  Color get _ink => focused ? TvPanelTheme.focusInk : (row.dimmed ? TvPanelTheme.textMuted : Colors.white);
  Color get _inkMuted =>
      focused ? TvPanelTheme.focusInkMuted : (row.dimmed ? TvPanelTheme.textDim : TvPanelTheme.textFaint);
  Color get _inkValue => focused
      ? TvPanelTheme.focusInk
      : (row.dimmed ? TvPanelTheme.textFaint : (row.highlighted ? Colors.white : TvPanelTheme.textMuted));

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
          if (row.icon != null) ...[AppIcon(row.icon!, fill: 1, color: _ink, size: 22), const SizedBox(width: 14)],
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
        if (!entered) return _valueText();
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
            decoration: BoxDecoration(shape: BoxShape.circle, color: focused ? TvPanelTheme.focusInk : Colors.white),
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
          child: Text(
            value!,
            style: TextStyle(color: valueColor, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
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

/// The round back control of a sub-view header. A bare Material [IconButton]
/// would be the one focusable in the panel drawing no focus of its own: under
/// `monoTheme` its overlay is a 10% wash on an already dark surface (DEC-053).
class TvPanelBackButton extends StatelessWidget {
  const TvPanelBackButton({super.key, required this.onPressed, this.focusNode});

  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return FocusableWrapper(
      focusNode: focusNode,
      onSelect: onPressed,
      focusShape: BoxShape.circle,
      autoScroll: false,
      mode: FocusIndicatorMode.delegated,
      disableScale: true,
      child: Builder(
        builder: (context) {
          final focused = CardFocusScope.maybeOf(context) ?? false;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: focused ? TvPanelTheme.focusFill : TvPanelTheme.inactivePill,
              ),
              child: AppIcon(
                Symbols.arrow_back_ios_new_rounded,
                fill: 1,
                color: focused ? TvPanelTheme.focusInk : Colors.white,
                size: 18,
              ),
            ),
          );
        },
      ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
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
