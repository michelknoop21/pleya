import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';

import '../focus/focusable_chip_mixin.dart';
import '../focus/input_mode_tracker.dart';
import 'focus_builders.dart';
import '../theme/mono_shapes.dart';
import '../theme/mono_tokens.dart';

/// Drawn height of the [FilterChipVariant.filled] control pill, in logical
/// pixels. Fixed by the northstar, not derived from the label.
const double _filledPillHeight = 32;

/// Diameter of the count badge inside the control pill.
const double _badgeDiameter = 18;

/// How a [FocusableFilterChip] draws itself.
enum FilterChipVariant {
  /// Outlined pill with an icon. For chip rows that stand on their own, like
  /// the search filters.
  outlined,

  /// Muted label plus its current value in full colour, no outline. For a
  /// header line where the chips have to sit beside a page title without
  /// turning it into a toolbar.
  text,

  /// Gray filled stadium, no border, count folded into a badge rather than an
  /// accent tint. The control pill from the iOS northstar (Sources, Filters,
  /// Sort, season picker).
  filled,

  /// Same colour logic as [outlined] — including the accent tint on
  /// [selected] — but stadium-shaped. The scope chip from the iOS northstar
  /// (All/Movies/Shows toggles). Kept separate from [outlined] so shared
  /// surfaces (TV, desktop, iPad) that already render [outlined] do not
  /// change shape underneath them; see DEC-103.
  scope,
}

/// A focusable filter chip that shows a color change when focused.
///
/// Unlike FocusableWrapper which uses scale + border, this widget
/// uses a background color change to indicate focus state.
class FocusableFilterChip extends StatefulWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onPressed;

  /// Visual treatment. See [FilterChipVariant].
  final FilterChipVariant variant;

  /// Current value, shown after [label] in the [FilterChipVariant.text]
  /// variant ("Sort · Title"). Ignored by the outlined variant, which folds
  /// the value into [label].
  final String? value;

  /// When true, renders an accent-tinted "active" state (used for toggle
  /// filters like type/genre). Focus styling always takes precedence.
  final bool selected;

  /// Count shown as a small white badge folded into the pill, after the
  /// label. Only meaningful on [FilterChipVariant.filled] — the northstar
  /// control pill carries its active-filter count this way instead of an
  /// accent tint.
  final int badgeCount;

  /// Icon rendered after the label, e.g. the season-picker chevron. Separate
  /// from [icon], which is always leading.
  final IconData? trailingIcon;

  /// Optional external focus node for programmatic focus control.
  final FocusNode? focusNode;

  /// Called when the user presses DOWN from this chip.
  final VoidCallback? onNavigateDown;

  /// Called when the user presses UP from this chip.
  final VoidCallback? onNavigateUp;

  /// Called when the user presses LEFT from this chip.
  final VoidCallback? onNavigateLeft;

  /// Called when the user presses RIGHT from this chip.
  final VoidCallback? onNavigateRight;

  /// Called when the user presses BACK from this chip.
  final VoidCallback? onBack;

  const FocusableFilterChip({
    super.key,
    this.icon,
    required this.label,
    required this.onPressed,
    this.variant = FilterChipVariant.outlined,
    this.value,
    this.selected = false,
    this.badgeCount = 0,
    this.trailingIcon,
    this.focusNode,
    this.onNavigateDown,
    this.onNavigateUp,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
  });

  @override
  State<FocusableFilterChip> createState() => _FocusableFilterChipState();
}

class _FocusableFilterChipState extends State<FocusableFilterChip> with FocusableChipStateMixin<FocusableFilterChip> {
  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  String get debugLabel => 'filter_chip_${widget.label}';

  @override
  void initState() {
    super.initState();
    initFocusNode();
  }

  @override
  void didUpdateWidget(FocusableFilterChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateFocusNode(oldWidget.focusNode);
  }

  @override
  void dispose() {
    disposeFocusNode();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    return handleChipKeyEvent(
      node,
      event,
      ChipKeyCallbacks(
        onSelect: widget.onPressed,
        onNavigateDown: widget.onNavigateDown,
        onNavigateUp: widget.onNavigateUp,
        onNavigateLeft: widget.onNavigateLeft,
        onNavigateRight: widget.onNavigateRight,
        onBack: widget.onBack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only show focus effects during keyboard/d-pad navigation
    final showFocus = isFocused && InputModeTracker.isKeyboardMode(context);
    switch (widget.variant) {
      case FilterChipVariant.text:
        return _buildText(context, showFocus);
      case FilterChipVariant.filled:
        return _buildFilled(context, showFocus);
      case FilterChipVariant.outlined:
      case FilterChipVariant.scope:
        return _buildOutlinedOrScope(context, showFocus);
    }
  }

  /// Shared colour logic for [FilterChipVariant.outlined] and
  /// [FilterChipVariant.scope] — identical treatment, only the shape differs.
  /// These sit next to the segmented tab control, and two competing filled
  /// shapes made the header look like a toolbar of grey slabs. Active state
  /// keeps a soft accent tint so it still reads.
  Widget _buildOutlinedOrScope(BuildContext context, bool showFocus) {
    final tk = tokens(context);
    final Color backgroundColor;
    final Color foregroundColor;
    final Color borderColor;
    if (showFocus) {
      backgroundColor = tk.surfaceElevated;
      foregroundColor = tk.text;
      borderColor = tk.text.withValues(alpha: 0.75);
    } else if (widget.selected) {
      backgroundColor = tk.accent.withValues(alpha: 0.14);
      foregroundColor = tk.accent;
      borderColor = tk.accent.withValues(alpha: 0.55);
    } else {
      backgroundColor = Colors.transparent;
      foregroundColor = tk.textMuted;
      borderColor = tk.outline.withValues(alpha: 0.8);
    }

    final isScope = widget.variant == FilterChipVariant.scope;
    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      borderRadius: 10,
      shape: isScope ? MonoShapes.cta : null,
      hitTestBehavior: isScope ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      borderColor: borderColor,
      backgroundColor: backgroundColor,
      child: _buildContent(context, foregroundColor),
    );
  }

  /// The control pill: gray filled stadium, no border, no accent tint — the
  /// active count is carried by [badgeCount], not by [selected].
  ///
  /// The drawn surface is exactly [_filledPillHeight] tall. No vertical
  /// padding, a fixed-height content box: the northstar pill is a geometric
  /// shape, so its height must not drift with the label's font metrics or the
  /// platform text scale. The 44pt tap target lives in the wrapper around this
  /// surface (see `minTapHeight`) and does not enlarge it.
  Widget _buildFilled(BuildContext context, bool showFocus) {
    final tk = tokens(context);
    final foregroundColor = showFocus ? tk.text : tk.textMuted;
    final borderColor = showFocus ? tk.text.withValues(alpha: 0.75) : null;

    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      shape: MonoShapes.cta,
      hitTestBehavior: HitTestBehavior.opaque,
      minTapHeight: 44,
      borderColor: borderColor,
      backgroundColor: tk.surfaceElevated,
      child: SizedBox(height: _filledPillHeight, child: _buildContent(context, foregroundColor)),
    );
  }

  IconData? get icon => widget.icon;

  Widget _buildContent(BuildContext context, Color foregroundColor) {
    return Row(
      mainAxisSize: .min,
      children: [
        if (icon != null) ...[AppIcon(icon, fill: 1, size: 16, color: foregroundColor), const SizedBox(width: 6)],
        Text(widget.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foregroundColor)),
        if (widget.trailingIcon != null) ...[
          const SizedBox(width: 2),
          AppIcon(widget.trailingIcon, fill: 1, size: 16, color: foregroundColor),
        ],
        if (widget.badgeCount > 0) ...[const SizedBox(width: 6), _FilterChipBadge(count: widget.badgeCount)],
      ],
    );
  }

  /// Label in muted ink, current value in full ink, and nothing drawn around it.
  /// Focus lifts and brightens the text rather than adding a surface or a rule:
  /// this variant shares its line with the tab labels and their accent bar, and
  /// a second marker there would compete with the one that says which tab is
  /// open.
  Widget _buildText(BuildContext context, bool showFocus) {
    final tk = tokens(context);
    final theme = Theme.of(context);
    final labelColor = showFocus ? tk.text : tk.textMuted;
    final valueColor = widget.selected ? tk.accent : tk.text;

    return FocusBuilders.buildFocusableChip(
      context: context,
      focusNode: focusNode,
      onKeyEvent: _handleKeyEvent,
      onTap: widget.onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      borderRadius: 8,
      backgroundColor: Colors.transparent,
      child: AnimatedScale(
        duration: reduceMotion(context, tk.fast),
        scale: showFocus ? 1.05 : 1.0,
        child: Row(
          mainAxisSize: .min,
          children: [
            Text(widget.label, style: theme.textTheme.labelMedium?.copyWith(color: labelColor)),
            if (widget.value != null) ...[
              const SizedBox(width: 6),
              Text(
                widget.value!,
                style: theme.textTheme.labelMedium?.copyWith(color: valueColor, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The white circle with a bold black count, folded into
/// [FilterChipVariant.filled] after the label — the active-count badge from
/// the iOS northstar control pill.
///
/// Exactly [_badgeDiameter] square, like the pill it sits in: a circle whose
/// diameter followed the digit's font metrics would go oval as soon as the
/// count reached two digits or the text scale went up. The digit scales down
/// inside it instead of pushing it wider.
class _FilterChipBadge extends StatelessWidget {
  const _FilterChipBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: _badgeDiameter,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$count',
                style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
