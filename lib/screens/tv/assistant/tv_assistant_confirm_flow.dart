import 'dart:async';

import 'package:flutter/material.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_run.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/apple_tv_native_text_entry.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/overlay_sheet_geometry.dart';
import 'tv_assistant_confirm_card.dart';

/// Shows the Pleya confirmation card for [confirmation] in the shell's
/// overlay host and hands the answer to [controller] under the card's own
/// task and confirmation id: closing the card declines that one action. A
/// card the queue has moved past answers nothing. [onSheet] receives the
/// sheet's context while it is open (null once closed). True when confirmed.
Future<bool> showTvAssistantConfirm(
  BuildContext context, {
  required AssistantController controller,
  required AssistantTaskConfirmation confirmation,
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
        action: confirmation.action,
        cancelNode: cancelNode,
        onCancel: () => OverlaySheetController.closeAdaptive(sheetContext),
        onConfirm: (password) =>
            OverlaySheetController.closeAdaptive(sheetContext, AssistantConfirmation(password: password)),
        readPassword: () => _readPassword(context, entry),
      );
    },
  );
  onSheet(null);
  if (!context.mounted || controller.pendingConfirmation?.id != confirmation.id) return false;
  if (result == null) {
    controller.cancelTaskConfirmation(confirmation.taskId, confirmation.id);
    return false;
  }
  controller.confirmTask(confirmation.taskId, confirmation.id, password: result.password);
  return true;
}

/// Runs [action] once the frame is out and the focus it asked for has landed.
void tvAssistantAfterFocusSettles(VoidCallback action) {
  WidgetsBinding.instance.addPostFrameCallback((_) => scheduleMicrotask(action));
  WidgetsBinding.instance.ensureVisualUpdate();
}

/// Keeps the card on screen in step with the head of the controller's
/// confirmation queue, one card at a time, for the surface and the summoned
/// Big P alike.
class TvAssistantConfirmPresenter {
  TvAssistantConfirmPresenter({required this.cancelNode});

  final FocusNode cancelNode;
  String? _shown;
  String? _answered;
  BuildContext? _sheet;

  /// The card owns the remote.
  bool get isOpen => _sheet != null;

  /// Called on every controller change. [onClosed] hears whether the viewer
  /// confirmed, each time a card goes.
  void sync(
    BuildContext context,
    AssistantController controller,
    AppleTvNativeTextEntry entry,
    ValueChanged<bool> onClosed,
  ) {
    final head = controller.pendingConfirmation;
    if (head?.id == _shown) return;
    if (_shown != null) {
      // Timed out, cancelled with its task or reset under the card: take it
      // away. Its return raises whatever is next in the queue.
      final sheet = _sheet;
      if (sheet != null && sheet.mounted) OverlaySheetController.closeAdaptive(sheet);
      return;
    }
    // A card that has had its answer is not raised twice.
    if (head == null || head.id == _answered) return;
    _shown = head.id;
    unawaited(
      showTvAssistantConfirm(
        context,
        controller: controller,
        confirmation: head,
        cancelNode: cancelNode,
        entry: entry,
        onSheet: (sheet) => _sheet = sheet,
      ).then((confirmed) {
        _shown = null;
        _answered = head.id;
        if (!context.mounted) return;
        onClosed(confirmed);
        // The next card comes after the launcher has the remote back, so it
        // returns there as well.
        tvAssistantAfterFocusSettles(() {
          if (context.mounted) sync(context, controller, entry, onClosed);
        });
      }),
    );
  }
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
