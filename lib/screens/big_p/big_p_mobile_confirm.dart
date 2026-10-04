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

  @override
  void dispose() {
    _cancel.dispose();
    super.dispose();
  }

  /// A card the controller already dropped (a newer one, or none) is not
  /// answered twice.
  bool get _current => identical(widget.controller.pending, widget.pending);

  void _confirm(String? password) {
    if (!_current) return;
    widget.controller.confirmPending(password: password);
    unawaited(BigPVoice.of(widget.controller)?.say(BigPMoment.nod));
  }

  Future<String?> _readPassword() => showTextInputDialog(
    context,
    title: t.assistant.confirm.password,
    labelText: t.assistant.confirm.password,
    hintText: t.assistant.confirm.passwordPlaceholder,
    obscureText: true,
  );

  @override
  Widget build(BuildContext context) => BigPConfirmCard(
    // A new card starts with an empty password.
    key: ObjectKey(widget.pending),
    action: widget.pending,
    cancelNode: _cancel,
    onCancel: () {
      if (_current) widget.controller.cancelPending();
    },
    onConfirm: _confirm,
    readPassword: _readPassword,
  );
}
