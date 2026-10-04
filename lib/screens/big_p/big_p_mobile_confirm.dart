import 'dart:async';

import 'package:flutter/material.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_tools.dart';
import '../../assistant/big_p_voice.dart';
import '../../i18n/strings.g.dart';
import '../../utils/dialogs.dart';
import '../../widgets/big_p/assistant/big_p_confirm_card.dart';

/// The Pleya card in Big P's balloon (39 G) while [pending] waits. The
/// host hides the question field and the dim no longer parks him: only
/// Annuleren or the primary ends it. A password is read in Pleya's own
/// masked dialog and goes to [AssistantController.confirmPending] only.
class BigPMobileConfirm extends StatefulWidget {
  const BigPMobileConfirm({super.key, required this.controller, required this.pending});

  final AssistantController controller;
  final AssistantPendingAction pending;

  @override
  State<BigPMobileConfirm> createState() => _BigPMobileConfirmState();
}

class _BigPMobileConfirmState extends State<BigPMobileConfirm> {
  final _cancel = FocusNode(debugLabel: 'bigp.confirm.cancel');

  /// This card was answered: a second tap neither answers nor nods again.
  bool _answered = false;

  /// The password dialog's navigator while it is open.
  NavigatorState? _dialog;

  @override
  void didUpdateWidget(BigPMobileConfirm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pending, widget.pending)) {
      _answered = false;
      _closeDialog();
    }
  }

  @override
  void dispose() {
    // The card went (answered elsewhere, timed out): its dialog goes too.
    _closeDialog();
    _cancel.dispose();
    super.dispose();
  }

  void _closeDialog() {
    final navigator = _dialog;
    if (navigator == null) return;
    // Not while the tree is being built or torn down.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_dialog, navigator) && navigator.mounted) navigator.pop();
    });
  }

  /// A card the controller already dropped (a newer one, or none) is not
  /// answered; nor is one twice. The answer names this card's own action, so
  /// the controller drops it too when its queue has moved on.
  bool _answer() {
    if (_answered || !identical(widget.controller.pending, widget.pending)) return false;
    _answered = true;
    return true;
  }

  void _confirm(String? password) {
    if (!_answer()) return;
    widget.controller.confirmPending(password: password, action: widget.pending);
    unawaited(BigPVoice.of(widget.controller)?.say(BigPMoment.nod));
  }

  Future<String?> _readPassword() async {
    _dialog = Navigator.of(context);
    try {
      return await showTextInputDialog(
        context,
        title: t.assistant.confirm.password,
        labelText: t.assistant.confirm.password,
        hintText: t.assistant.confirm.passwordPlaceholder,
        obscureText: true,
      );
    } finally {
      _dialog = null;
    }
  }

  @override
  Widget build(BuildContext context) => BigPConfirmCard(
    // A new card starts with an empty password.
    key: ObjectKey(widget.pending),
    action: widget.pending,
    cancelNode: _cancel,
    onCancel: () {
      if (_answer()) widget.controller.cancelPending(action: widget.pending);
    },
    onConfirm: _confirm,
    readPassword: _readPassword,
    embedded: true,
  );
}
