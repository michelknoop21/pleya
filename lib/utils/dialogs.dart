import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../focus/focusable_button.dart';
import '../focus/focusable_text_field.dart';
import '../focus/input_mode_tracker.dart';
import '../i18n/strings.g.dart';
import '../mixins/controller_disposer_mixin.dart';
import '../widgets/app_icon.dart';
import '../widgets/dialog_action_button.dart';
import '../widgets/focusable_list_tile.dart';
import 'focus_utils.dart';

const _buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 14);

/// Shows a dialog on the nearest navigator instead of Flutter's default root
/// navigator. Use this for profile/session-owned modal routes so they are
/// disposed when the active profile session is replaced.
Future<T?> showScopedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    useRootNavigator: false,
  );
}

/// Shows a confirmation dialog with consistent button sizing and autofocus.
/// Returns true if user confirmed, false if cancelled.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmText,
  String? cancelText,
  bool isDestructive = false,
}) async {
  final confirmed = await showScopedDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FocusableButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: TextButton.styleFrom(padding: _buttonPadding),
              child: Text(cancelText ?? t.common.cancel),
            ),
          ),
          FocusableButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: isDestructive
                  ? FilledButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError)
                  : null,
              child: Text(confirmText),
            ),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}

/// Shows a non-dismissible loading-spinner dialog. Caller is responsible for
/// closing it via `Navigator.pop(context)` when the work completes.
///
/// Prefer [showCancellableLoadingDialog]: it owns its own route, always cleans
/// up, and gives the user a focusable way out.
void showLoadingDialog(BuildContext context) {
  showScopedDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
}

/// Runs [task] behind a blocking spinner that the user can always escape from.
///
/// Unlike [showLoadingDialog] this holds on to its own [Route] and removes
/// exactly that route when it is done — so a dialog pushed on top of it can no
/// longer turn the close into a silent no-op, and it can never pop somebody
/// else's route. It also always ends: on cancel (focusable button or BACK), on
/// [timeout], or when [task] settles.
///
/// Returns the task's value, or `null` when the user cancelled or the timeout
/// fired. Errors from [task] are rethrown after the dialog is closed, so
/// existing caller-side error handling keeps working.
Future<T?> showCancellableLoadingDialog<T>({
  required BuildContext context,
  required Future<T> task,
  Duration timeout = const Duration(seconds: 30),
  VoidCallback? onCancel,
  String? message,
  String? timeoutMessage,
}) async {
  final navigator = Navigator.of(context, rootNavigator: false);
  final messenger = ScaffoldMessenger.maybeOf(context);

  final gate = Completer<T?>();
  var timedOut = false;
  var closed = false;

  late final DialogRoute<void> route;
  void close() {
    if (closed) return;
    closed = true;
    // Unconditional: `route.isCurrent` would skip cleanup whenever anything
    // got pushed on top, which is exactly how these dialogs got stuck before.
    if (route.isActive) navigator.removeRoute(route);
  }

  void cancel() {
    if (!gate.isCompleted) gate.complete(null);
    onCancel?.call();
  }

  route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (_) => _CancellableLoadingDialog(message: message, onCancel: cancel),
  );

  // Attach handlers before the await so a task that is already complete (or
  // already failed) can never slip past the gate unobserved.
  unawaited(
    task.then(
      (value) {
        if (!gate.isCompleted) gate.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!gate.isCompleted) gate.completeError(error, stack);
      },
    ),
  );

  final timer = Timer(timeout, () {
    if (gate.isCompleted) return;
    timedOut = true;
    gate.complete(null);
  });

  unawaited(navigator.push(route));
  try {
    return await gate.future;
  } finally {
    timer.cancel();
    close();
    if (timedOut && timeoutMessage != null) {
      messenger?.showSnackBar(SnackBar(content: Text(timeoutMessage)));
    }
  }
}

class _CancellableLoadingDialog extends StatelessWidget {
  const _CancellableLoadingDialog({required this.message, required this.onCancel});

  final String? message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onCancel();
      },
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (message != null) ...[const SizedBox(height: 16), Text(message!, style: theme.textTheme.bodyMedium)],
                const SizedBox(height: 16),
                FocusableButton(
                  autofocus: true,
                  onPressed: onCancel,
                  child: TextButton(
                    onPressed: onCancel,
                    style: TextButton.styleFrom(padding: _buttonPadding),
                    child: Text(t.common.cancel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the server-side 500 modal (bandwidth/transcoding limit rejection).
///
/// When [canTryLowerQuality] is set, offers a "Try lower quality" action;
/// returns `true` if the user picked it (caller restarts one preset down),
/// `false` if they closed the dialog.
Future<bool> showServerLimitDialog(BuildContext context, {bool canTryLowerQuality = false}) async {
  final result = await showScopedDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(t.messages.serverLimitTitle),
      content: Text(t.messages.serverLimitBody),
      actions: [
        if (canTryLowerQuality)
          FocusableButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(padding: _buttonPadding),
              child: Text(t.videoSettings.tryLowerQuality),
            ),
          ),
        FocusableButton(
          autofocus: !canTryLowerQuality,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: canTryLowerQuality
              ? TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.common.close))
              : FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: FilledButton.styleFrom(padding: _buttonPadding),
                  child: Text(t.common.close),
                ),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows a delete confirmation dialog.
/// Convenience wrapper around [showConfirmDialog] with destructive styling.
Future<bool> showDeleteConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmText,
}) {
  return showConfirmDialog(
    context,
    title: title,
    message: message,
    confirmText: confirmText ?? t.common.delete,
    isDestructive: true,
  );
}

/// Shows a text input dialog for creating/naming items
/// Returns the entered text, or null if cancelled
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String labelText,
  required String hintText,
  String? initialValue,
  String? confirmText,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  String? Function(String)? validator,
  bool allowEmpty = false,
}) {
  return showScopedDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      labelText: labelText,
      hintText: hintText,
      initialValue: initialValue,
      confirmText: confirmText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      allowEmpty: allowEmpty,
    ),
  );
}

/// Shows a multiline text input dialog for editing longer text like summaries.
/// Returns the entered text, or null if cancelled.
/// Allows empty text to be submitted (for clearing fields).
Future<String?> showMultilineTextInputDialog(
  BuildContext context, {
  required String title,
  required String labelText,
  String? initialValue,
}) {
  return showScopedDialog<String>(
    context: context,
    builder: (context) => _MultilineTextInputDialog(title: title, labelText: labelText, initialValue: initialValue),
  );
}

/// Shared lifecycle for the two private text-input dialogs below: a single
/// [TextEditingController] seeded from [initialValue], plus a focus node for
/// the save button.
mixin _TextInputDialogStateMixin<T extends StatefulWidget> on State<T>, ControllerDisposerMixin<T> {
  late final TextEditingController _controller;
  final _fieldFocusNode = FocusNode();
  final _cancelFocusNode = FocusNode();
  final _saveFocusNode = FocusNode();

  String? get initialValue;

  @override
  void initState() {
    super.initState();
    _controller = createTextEditingController(text: initialValue);
  }

  @override
  void dispose() {
    _fieldFocusNode.dispose();
    _cancelFocusNode.dispose();
    _saveFocusNode.dispose();
    super.dispose();
  }
}

class _MultilineTextInputDialog extends StatefulWidget {
  final String title;
  final String labelText;
  final String? initialValue;

  const _MultilineTextInputDialog({required this.title, required this.labelText, this.initialValue});

  @override
  State<_MultilineTextInputDialog> createState() => _MultilineTextInputDialogState();
}

class _MultilineTextInputDialogState extends State<_MultilineTextInputDialog>
    with ControllerDisposerMixin, _TextInputDialogStateMixin<_MultilineTextInputDialog> {
  @override
  String? get initialValue => widget.initialValue;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: FocusableTextField(
          controller: _controller,
          focusNode: _fieldFocusNode,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.labelText),
          keyboardType: TextInputType.multiline,
          maxLines: 8,
          minLines: 3,
          onNavigateDown: _saveFocusNode.requestFocus,
        ),
      ),
      actions: [
        DialogActionButton(
          focusNode: _cancelFocusNode,
          onPressed: () => Navigator.pop(context),
          onNavigateRight: _saveFocusNode.requestFocus,
          label: t.common.cancel,
        ),
        DialogActionButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          label: t.common.save,
          focusNode: _saveFocusNode,
          onNavigateLeft: _cancelFocusNode.requestFocus,
        ),
      ],
    );
  }
}

class _TextInputDialog extends StatefulWidget {
  final String title;
  final String labelText;
  final String hintText;
  final String? initialValue;
  final String? confirmText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String)? validator;
  final bool allowEmpty;

  const _TextInputDialog({
    required this.title,
    required this.labelText,
    required this.hintText,
    this.initialValue,
    this.confirmText,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.allowEmpty = false,
  });

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog>
    with ControllerDisposerMixin, _TextInputDialogStateMixin<_TextInputDialog> {
  @override
  String? get initialValue => widget.initialValue;

  void _submit() {
    final text = _controller.text;
    if (text.isEmpty && !widget.allowEmpty) return;
    if (widget.validator != null && widget.validator!(text) != null) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: FocusableTextField(
        controller: _controller,
        focusNode: _fieldFocusNode,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.labelText, hintText: widget.hintText),
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        textInputAction: TextInputAction.done,
        onNavigateDown: _saveFocusNode.requestFocus,
        onSubmitted: (_) => _saveFocusNode.requestFocus(),
      ),
      actions: [
        DialogActionButton(
          focusNode: _cancelFocusNode,
          onPressed: () => Navigator.pop(context),
          onNavigateRight: _saveFocusNode.requestFocus,
          label: t.common.cancel,
        ),
        DialogActionButton(
          onPressed: _submit,
          label: widget.confirmText ?? t.common.save,
          focusNode: _saveFocusNode,
          onNavigateLeft: _cancelFocusNode.requestFocus,
        ),
      ],
    );
  }
}

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
    const rowPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const rowHorizontalTitleGap = 8.0;
    const rowMinLeadingWidth = 24.0;
    final toggle = widget.toggle;
    void updateToggle(bool value) {
      setState(() => _toggleValue = value);
      toggle?.onChanged(value);
    }

    return SimpleDialog(
      title: Text(widget.title),
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      constraints: const BoxConstraints(minWidth: 304),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (toggle != null)
          MergeSemantics(
            child: FocusableListTile(
              title: Row(
                children: [
                  if (toggle.icon != null) ...[
                    AppIcon(toggle.icon!, fill: 1, size: 24),
                    const SizedBox(width: rowHorizontalTitleGap),
                  ],
                  Expanded(
                    child: Text(
                      toggle.label,
                      style: Theme.of(context).textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: rowHorizontalTitleGap),
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
            leading: icon != null ? AppIcon(icon, fill: 1, size: 24) : null,
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
