import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_theme.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import 'tv_assistant_widgets.dart';
import '../../../widgets/big_p/big_p_avatar.dart';
import '../../../widgets/tv/tv_page_surface.dart';

/// 38 B (no access) and 38 C1 (no AI provider): Big P stands there, still,
/// beside one explanation and one way on. Locked has no ask button, no
/// price and no shop link.
class TvAssistantGate extends StatelessWidget {
  const TvAssistantGate({
    super.key,
    required this.locked,
    required this.primaryNode,
    required this.onSetup,
    required this.onBack,
  });

  final bool locked;
  final FocusNode primaryNode;
  final VoidCallback onSetup;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final l = t.assistant.locked;
    final s = t.assistant.setup;
    final body = TextStyle(color: tk.text.withValues(alpha: 0.8), fontSize: TvHig.callout * pt, height: 1.35);

    return TvPageSurface(
      title: t.assistant.tileTitle,
      automationInstance: 'assistant',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Calm on purpose (motion spec): no ticker, so no breathing.
            TickerMode(
              enabled: false,
              child: BigPAvatar(mood: BigPMood.idle, size: 440 * pt, entrance: false),
            ),
            SizedBox(width: 60 * pt),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 40 * pt),
                  Row(
                    children: [
                      if (locked)
                        Icon(Symbols.lock_rounded, size: TvHig.caption1 * pt, color: tk.text.withValues(alpha: 0.6))
                      else
                        Container(
                          width: 12 * pt,
                          height: 12 * pt,
                          decoration: const BoxDecoration(color: kAccentAlt, shape: BoxShape.circle),
                        ),
                      SizedBox(width: 12 * pt),
                      Text(
                        locked ? l.badge : s.badge,
                        style: TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption1 * pt),
                      ),
                    ],
                  ),
                  SizedBox(height: 14 * pt),
                  Text(
                    locked ? l.title : s.title,
                    style: TextStyle(color: tk.text, fontSize: TvHig.title3 * pt, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 18 * pt),
                  Text(locked ? l.body : s.body, style: body),
                  if (locked) ...[
                    SizedBox(height: 18 * pt),
                    Text(
                      l.note,
                      style: body.copyWith(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption1 * pt),
                    ),
                  ],
                  SizedBox(height: 32 * pt),
                  Row(
                    children: [
                      TvAssistantButton(
                        label: locked ? l.back : s.action,
                        icon: locked ? Symbols.arrow_back_rounded : Symbols.settings_rounded,
                        primary: true,
                        focusNode: primaryNode,
                        automationId: AutomationIds.assistantButton,
                        automationInstance: locked ? 'back' : 'setup',
                        onPressed: locked ? onBack : onSetup,
                      ),
                      if (!locked) ...[
                        SizedBox(width: 12 * pt),
                        TvAssistantButton(
                          label: s.back,
                          primary: false,
                          automationId: AutomationIds.assistantButton,
                          automationInstance: 'back',
                          onPressed: onBack,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
