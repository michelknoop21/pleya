import 'package:flutter/material.dart';

import '../focus/input_mode_tracker.dart';
import '../widgets/app_icon.dart';
import '../widgets/focusable_list_tile.dart';
import 'dialogs.dart';
import 'focus_utils.dart';
import 'layout_constants.dart';
import 'platform_detector.dart';

/// Shows a simple option picker dialog with focusable items for TV/keyboard navigation.
/// Returns the selected value, or null if cancelled. Each option's [icon] may
/// be `null` to render a label-only row (useful when the choices are variants
/// of the same thing and a repeated icon would just be noise).
/// Optional persistent toggle rendered above the option rows. Its state is held
/// by the dialog (toggling does not pop), and [onChanged] mirrors the new value
/// out so the caller can read it once an option row is picked.
typedef OptionPickerToggle = ({String label, IconData? icon, bool value, ValueChanged<bool> onChanged});

Future<T?> showOptionPickerDialog<T>(
  BuildContext context, {
  required String title,
  required List<({IconData? icon, String label, T value})> options,
  Future<T?> Function(T value)? onBeforeClose,
  OptionPickerToggle? toggle,
}) {
  final focusFirstItem = InputModeTracker.isKeyboardMode(context);
  return showScopedDialog<T>(
    context: context,
    builder: (context) => _OptionPickerDialog<T>(
      title: title,
      options: options,
      focusFirstItem: focusFirstItem,
      onBeforeClose: onBeforeClose,
      toggle: toggle,
    ),
  );
}

class _OptionPickerDialog<T> extends StatefulWidget {
  final String title;
  final List<({IconData? icon, String label, T value})> options;
  final bool focusFirstItem;
  final Future<T?> Function(T value)? onBeforeClose;
  final OptionPickerToggle? toggle;

  const _OptionPickerDialog({
    required this.title,
    required this.options,
    this.focusFirstItem = false,
    this.onBeforeClose,
    this.toggle,
  });

  @override
  State<_OptionPickerDialog<T>> createState() => _OptionPickerDialogState<T>();
}

class _OptionPickerDialogState<T> extends State<_OptionPickerDialog<T>> {
  late final FocusNode _initialFocusNode;
  late bool _toggleValue;

  @override
  void initState() {
    super.initState();
    _initialFocusNode = FocusNode(debugLabel: 'OptionPickerInitialFocus');
    _toggleValue = widget.toggle?.value ?? false;
    if (widget.focusFirstItem) {
      FocusUtils.requestFocusAfterBuild(this, _initialFocusNode);
    }
  }

  @override
  void dispose() {
    _initialFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Shared by phone, desktop and TV. On TV every literal here follows the
    // ten-foot scale (F-TV1): raw, only the global 1.85x TV wrapper touched
    // them and the dialog came out about 18% roomier than a tokened panel.
    // That includes the content padding and both icons, so the proportions
    // stay as tuned. Off TV the scale is 1 and nothing changes.
    final scale = PlatformDetector.isTV() ? TvLayoutConstants.scaleOf(context) : 1.0;
    final rowPadding = EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale);
    final rowHorizontalTitleGap = 8.0 * scale;
    final rowMinLeadingWidth = 24.0 * scale;
    final toggle = widget.toggle;
    void updateToggle(bool value) {
      setState(() => _toggleValue = value);
      toggle?.onChanged(value);
    }

    return SimpleDialog(
      title: Text(widget.title),
      insetPadding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 24 * scale),
      constraints: BoxConstraints(minWidth: 304 * scale),
      contentPadding: EdgeInsets.symmetric(vertical: 8 * scale),
      children: [
        if (toggle != null)
          MergeSemantics(
            child: FocusableListTile(
              title: Row(
                children: [
                  if (toggle.icon != null) ...[
                    AppIcon(toggle.icon!, fill: 1, size: 24 * scale),
                    SizedBox(width: rowHorizontalTitleGap),
                  ],
                  Expanded(
                    child: Text(
                      toggle.label,
                      style: Theme.of(context).textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: rowHorizontalTitleGap),
                  ExcludeFocus(
                    child: Switch(value: _toggleValue, onChanged: updateToggle),
                  ),
                ],
              ),
              contentPadding: rowPadding,
              onTap: () => updateToggle(!_toggleValue),
            ),
          ),
        ...List.generate(widget.options.length, (index) {
          final option = widget.options[index];
          final icon = option.icon;
          return FocusableListTile(
            focusNode: index == 0 && widget.focusFirstItem ? _initialFocusNode : null,
            leading: icon != null ? AppIcon(icon, fill: 1, size: 24 * scale) : null,
            title: Text(option.label, style: Theme.of(context).textTheme.bodyLarge),
            contentPadding: rowPadding,
            horizontalTitleGap: rowHorizontalTitleGap,
            minLeadingWidth: rowMinLeadingWidth,
            onTap: () async {
              if (widget.onBeforeClose != null) {
                final result = await widget.onBeforeClose!(option.value);
                if (context.mounted) Navigator.pop(context, result);
              } else {
                Navigator.pop(context, option.value);
              }
            },
          );
        }),
      ],
    );
  }
}
