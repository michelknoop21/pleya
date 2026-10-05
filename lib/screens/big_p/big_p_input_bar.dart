import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../assistant/assistant_controller.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/big_p/big_p_scale.dart';
import 'big_p_mobile_session.dart';
import 'big_p_new_conversation_button.dart';

/// The question field under Big P (39 B, D). Focus starts listening, so his
/// voice keeps quiet while the user types or dictates with the iOS
/// keyboard's mic; leaving it empty stops listening; send asks.
class BigPInputBar extends StatefulWidget {
  const BigPInputBar({super.key, required this.session, this.inline = false});

  final BigPMobileSession session;

  /// iPad: "Nieuw gesprek" sits inside the field. iPhone: a pill beside it.
  final bool inline;

  @override
  State<BigPInputBar> createState() => _BigPInputBarState();
}

class _BigPInputBarState extends State<BigPInputBar> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'bigp.input');

  AssistantController get _c => widget.session.controller;

  @override
  void initState() {
    super.initState();
    // A question from Zoeken that came while Big P was still busy waits here.
    _text.text = widget.session.takeQuestion() ?? widget.session.draft;
    // What the field shows is the draft from here on, a handed-over question
    // included, so a rebuild cannot swap it for an older one.
    widget.session.draft = _text.text;
    _focus.addListener(_onFocus);
    _text.addListener(() {
      widget.session.draft = _text.text;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      if (_c.state != AssistantSurfaceState.working) _c.beginListening(context: widget.session.pendingContext);
    } else if (_text.text.trim().isEmpty && _c.state == AssistantSurfaceState.listening) {
      _c.cancelListening();
    }
  }

  void _send() {
    final question = _text.text.trim();
    // Still working on the last one: the text stays for when he is done.
    if (question.isEmpty || _c.state == AssistantSurfaceState.working) return;
    _text.clear();
    unawaited(_c.submit(question));
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final ready = _text.text.trim().isNotEmpty;
    // bodyMedium, not the field's default bodyLarge: the theme gives only
    // bodyMedium and titleMedium the app's font.
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(color: tk.text, fontSize: 16);
    final showNew = _c.hasConversation;
    final field = Container(
      height: 46,
      // 1 + 4 around the 36 pt button: its 44 pt touch area ends 1 pt inside.
      padding: EdgeInsets.only(left: showNew && widget.inline ? 1 : 16, right: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Row(
        children: [
          if (showNew && widget.inline) ...[
            BigPNewConversationButton(session: widget.session, inline: true),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: AutomationNode(
              id: AutomationIds.bigpInput,
              role: 'field',
              focusNode: _focus,
              child: FocusableTextField(
                controller: _text,
                focusNode: _focus,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                style: style,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  // After an answer: ask on from it (39 E).
                  hintText: _c.state == AssistantSurfaceState.result
                      ? t.assistant.mobile.askFurther
                      : t.assistant.idle.ask,
                  hintStyle: style.copyWith(color: tk.text.withValues(alpha: 0.45)),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _send,
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              button: true,
              label: t.assistant.idle.ask,
              // A 44 pt touch area around the 36 pt button.
              child: SizedBox(
                width: kBigPMinTouch,
                height: kBigPMinTouch,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready ? Colors.white : const Color(0x24FFFFFF),
                    ),
                    child: Icon(
                      Symbols.arrow_upward_rounded,
                      size: 20,
                      weight: 600,
                      color: ready ? Colors.black : tk.text.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!showNew || widget.inline) return field;
    // iPhone: the pill and the field on one line, both 46 pt, centred.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BigPNewConversationButton(session: widget.session),
        const SizedBox(width: 8),
        Expanded(child: field),
      ],
    );
  }
}
