import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_tools.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/pleya_wordmark.dart';
import 'tv_assistant_widgets.dart';
import 'tv_assistant_labels.dart';
import 'tv_assistant_results.dart';

/// The Pleya confirmation card (38 H, 38 I): an opaque Pleya card, never a
/// message from Big P. Every row comes from [action], which Pleya built
/// from validated server data; the model's words never reach it (DEC-142).
///
/// Focus opens on Annuleren: the Select that closed the keyboard is still in
/// the viewer's thumb, and a second press must not create an account. The
/// primary stays disabled while a required password is missing. The
/// password lives in this card and goes only to [onConfirm].
class TvAssistantConfirmCard extends StatefulWidget {
  const TvAssistantConfirmCard({
    super.key,
    required this.action,
    required this.cancelNode,
    required this.onCancel,
    required this.onConfirm,
    required this.readPassword,
  });

  final AssistantPendingAction action;
  final FocusNode cancelNode;
  final VoidCallback onCancel;
  final ValueChanged<String?> onConfirm;

  /// Opens Pleya's secure entry; null when the viewer backed out.
  final Future<String?> Function() readPassword;

  @override
  State<TvAssistantConfirmCard> createState() => _TvAssistantConfirmCardState();
}

class _TvAssistantConfirmCardState extends State<TvAssistantConfirmCard> {
  String _password = '';

  bool get _canConfirm => widget.action.password != AssistantPasswordMode.required || _password.isNotEmpty;

  bool get _userKind => switch (widget.action.kind) {
    AssistantActionKind.createUser || AssistantActionKind.setLibraryAccess || AssistantActionKind.removeUser => true,
    _ => false,
  };

  Future<void> _enterPassword() async {
    final value = await widget.readPassword();
    if (!mounted || value == null) return;
    setState(() => _password = value);
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final a = widget.action;
    final c = t.assistant.confirm;
    final labelStyle = TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.body * pt);
    final valueStyle = TextStyle(color: tk.text, fontSize: TvHig.body * pt, fontWeight: FontWeight.w500);
    final divider = Divider(height: 1, thickness: 1, color: tk.outline);

    Widget row(String label, Widget value) => Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 18 * pt),
          child: Row(
            children: [
              SizedBox(
                width: 220 * pt,
                child: Text(label, style: labelStyle),
              ),
              Expanded(child: value),
            ],
          ),
        ),
        divider,
      ],
    );
    Widget text(String value) => Text(value, style: valueStyle);

    final access = a.allLibraries ? c.allLibraries : a.libraryNames.join(', ');
    final note = assistantNoteLabel(a.note);
    final smallPrint = [?note, if (a.password != AssistantPasswordMode.none) c.passwordNote];
    final approveLabel = a.kind == AssistantActionKind.createUser ? c.create : c.approve;

    return AutomationNode(
      id: AutomationIds.assistantConfirm,
      role: 'sheet',
      state: () => {'kind': a.kind.name, 'password': a.password.name, 'canConfirm': _canConfirm},
      child: Container(
        padding: EdgeInsets.all(48 * pt),
        decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(28 * pt)),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Image.asset(
                    PleyaWordmark.markAsset,
                    height: TvHig.caption1 * pt,
                    filterQuality: FilterQuality.medium,
                  ),
                  SizedBox(width: 12 * pt),
                  Expanded(
                    child: Text(
                      c.header,
                      style: TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption1 * pt),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10 * pt),
              Text(
                assistantConfirmTitle(a.kind),
                style: TextStyle(color: tk.text, fontSize: TvHig.title3 * pt * 0.8, fontWeight: FontWeight.w700),
              ),
              if (!_userKind && a.subject.isNotEmpty) ...[SizedBox(height: 6 * pt), Text(a.subject, style: valueStyle)],
              SizedBox(height: 24 * pt),
              divider,
              if (_userKind && a.subject.isNotEmpty) row(c.user, text(a.subject)),
              if (a.serverName.isNotEmpty) row(c.server, text(a.serverName)),
              if (access.isNotEmpty) row(c.access, text(access)),
              if (a.kind == AssistantActionKind.createUser) row(c.admin, text(c.no)),
              if (a.items.isNotEmpty) row(c.titlesLabel, text(a.items.take(5).join(', '))),
              if (a.password != AssistantPasswordMode.none) row(c.password, _passwordField(pt, tk)),
              if (a.preview case final preview?) ...[
                SizedBox(height: 16 * pt),
                TvAssistantDisplayView(display: preview, onPickOption: (_) {}),
              ],
              for (final line in smallPrint) ...[
                SizedBox(height: 18 * pt),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Symbols.info_rounded, size: TvHig.caption1 * pt, color: tk.text.withValues(alpha: 0.6)),
                    SizedBox(width: 12 * pt),
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption1 * pt),
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 32 * pt),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TvAssistantButton(
                    label: t.assistant.result.cancel,
                    primary: false,
                    focusNode: widget.cancelNode,
                    automationId: AutomationIds.assistantConfirmButton,
                    automationInstance: 'cancel',
                    onPressed: widget.onCancel,
                  ),
                  SizedBox(width: 12 * pt),
                  TvAssistantButton(
                    label: approveLabel,
                    primary: true,
                    enabled: _canConfirm,
                    automationId: AutomationIds.assistantConfirmButton,
                    automationInstance: 'approve',
                    onPressed: () => widget.onConfirm(_password.isEmpty ? null : _password),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordField(double pt, MonoTokens tk) => FocusableWrapper(
    borderRadius: 14 * pt,
    disableScale: true,
    semanticLabel: t.assistant.confirm.password,
    automationId: AutomationIds.assistantConfirmButton,
    automationInstance: 'password',
    automationRole: 'button',
    automationState: () => {'filled': _password.isNotEmpty},
    onSelect: () {
      SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
      _enterPassword();
    },
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 22 * pt, vertical: 14 * pt),
      decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(14 * pt)),
      child: Row(
        children: [
          Icon(Symbols.lock_rounded, size: TvHig.caption1 * pt, color: tk.text.withValues(alpha: 0.6)),
          SizedBox(width: 14 * pt),
          Expanded(
            child: Text(
              _password.isEmpty ? t.assistant.confirm.passwordPlaceholder : '•' * _password.length.clamp(6, 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tk.text.withValues(alpha: _password.isEmpty ? 0.6 : 1),
                fontSize: TvHig.body * pt,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
