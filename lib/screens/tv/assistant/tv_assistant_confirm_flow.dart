import 'package:flutter/material.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_run.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/apple_tv_native_text_entry.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/overlay_sheet_geometry.dart';
import 'tv_assistant_confirm_card.dart';

/// Shows the Pleya confirmation card for [pending] in the shell's overlay
/// host and hands the answer to [controller]: closing the card is
/// [AssistantController.cancelPending]. Shared by the surface and the
/// summoned Big P, so both raise the same card. [onSheet] receives the
/// sheet's context while it is open (null once closed), so the caller can
/// take the card away when the controller drops it. True when confirmed.
Future<bool> showTvAssistantConfirm(
  BuildContext context, {
  required AssistantController controller,
  required AssistantPendingAction pending,
  required FocusNode cancelNode,
  required AppleTvNativeTextEntry entry,
  required ValueChanged<BuildContext?> onSheet,
}) async {
  final result = await OverlaySheetController.showAdaptive<AssistantConfirmation>(
    context,
    presentation: OverlaySheetPresentation.panel,
    restoreLauncherFocus: true,
    initialFocusNode: cancelNode,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(maxWidth: 880 * TvHig.of(context)),
    builder: (sheetContext) {
      onSheet(sheetContext);
      return TvAssistantConfirmCard(
        action: pending,
        cancelNode: cancelNode,
        onCancel: () => OverlaySheetController.closeAdaptive(sheetContext),
        onConfirm: (password) =>
            OverlaySheetController.closeAdaptive(sheetContext, AssistantConfirmation(password: password)),
        readPassword: () => _readPassword(context, entry),
      );
    },
  );
  onSheet(null);
  if (!context.mounted || !identical(controller.pending, pending)) return false;
  if (result == null) {
    controller.cancelPending();
    return false;
  }
  controller.confirmPending(password: result.password);
  return true;
}

/// Pleya's secure field: the system keyboard with a masked field on Apple
/// TV. The value goes to the card, and from there to [confirmPending] only.
Future<String?> _readPassword(BuildContext context, AppleTvNativeTextEntry entry) async {
  if (PlatformDetector.isAppleTV()) {
    try {
      final result = await entry.edit(
        text: '',
        hint: t.assistant.confirm.passwordPlaceholder,
        obscure: true,
        autocorrect: false,
      );
      return result.submitted && result.text.isNotEmpty ? result.text : null;
    } catch (e) {
      appLogger.w('Big P: password entry failed', error: e);
      return null;
    }
  }
  if (!context.mounted) return null;
  // Elsewhere (Android TV) Pleya's own dialog, masked as well.
  return showTextInputDialog(
    context,
    title: t.assistant.confirm.password,
    labelText: t.assistant.confirm.password,
    hintText: t.assistant.confirm.passwordPlaceholder,
    obscureText: true,
  );
}
