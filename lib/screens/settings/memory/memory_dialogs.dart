import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/dialogs.dart';
import 'memory_widgets.dart';

/// Asks before something of the memory is removed for good (43 G). The focus
/// opens on the safe button, so the press that brought the user here cannot
/// also confirm; Back and a tap beside the dialog are a no. True only for the
/// explicit yes.
Future<bool> showMemoryConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
}) async {
  final yes = await showScopedDialog<bool>(
    context: context,
    builder: (dialogContext) =>
        MemoryScale.forPlatform(dialogContext, _MemoryConfirmDialog(title: title, body: body, confirm: confirm)),
  );
  return yes ?? false;
}

/// The confirmation of "Alle herinneringen wissen".
Future<bool> confirmClearMemory(BuildContext context) {
  final d = t.assistant.memory.screen.clearDialog;
  return showMemoryConfirm(context, title: d.title, body: d.body, confirm: d.confirm);
}

class _MemoryConfirmDialog extends StatelessWidget {
  const _MemoryConfirmDialog({required this.title, required this.body, required this.confirm});

  final String title;
  final String body;
  final String confirm;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => handleBackKeyAction(event, () => Navigator.of(context).pop(false)),
      child: Dialog(
        backgroundColor: tk.surface,
        insetPadding: EdgeInsets.symmetric(horizontal: 28 * k, vertical: 24 * k),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20 * k),
          side: BorderSide(color: tk.outline),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 420 * k),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20 * k, 22 * k, 20 * k, 18 * k),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: memoryText(context, 20, weight: FontWeight.w700, height: 1.25)),
                SizedBox(height: 8 * k),
                Text(body, style: memoryText(context, 15, color: tk.textMuted, height: 1.45)),
                SizedBox(height: 18 * k),
                MemoryButtonPair(
                  first: MemoryPillButton(
                    label: t.common.cancel,
                    kind: MemoryPillKind.primary,
                    autofocus: true,
                    automationId: AutomationIds.settingsMemoryDialogButton,
                    automationInstance: 'cancel',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  second: MemoryPillButton(
                    label: confirm,
                    kind: MemoryPillKind.danger,
                    automationId: AutomationIds.settingsMemoryDialogButton,
                    automationInstance: 'confirm',
                    onPressed: () => Navigator.of(context).pop(true),
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
