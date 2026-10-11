import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../theme/mono_tokens.dart';
import '../../../widgets/app_icon.dart';
import 'memory_widgets.dart';

/// The card in the middle of the screen for a state without an overview: the
/// memory off (43 I), no memories yet (43 J), a children's profile, or facts
/// that could not be read.
class MemoryStateCard extends StatelessWidget {
  const MemoryStateCard({
    super.key,
    required this.title,
    required this.body,
    this.icon = Symbols.description_rounded,
    this.action,
    this.onAction,
    this.automationId,
    this.automationInstance,
  });

  final String title;
  final String body;
  final IconData icon;

  /// The label of the one button under the text, with [onAction].
  final String? action;
  final VoidCallback? onAction;
  final String? automationId;
  final String? automationInstance;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(22 * k, 30 * k, 22 * k, 26 * k),
      decoration: BoxDecoration(color: tk.surface, borderRadius: BorderRadius.circular(14 * k)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 52 * k,
              height: 52 * k,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: tk.outline),
              ),
              child: Center(
                child: AppIcon(icon, size: 24 * k, color: tk.textMuted),
              ),
            ),
          ),
          SizedBox(height: 14 * k),
          Text(
            title,
            textAlign: TextAlign.center,
            style: memoryText(context, 17, weight: FontWeight.w700, height: 1.3),
          ),
          SizedBox(height: 6 * k),
          Text(
            body,
            textAlign: TextAlign.center,
            style: memoryText(context, 15, color: tk.text.withValues(alpha: 0.9), height: 1.45),
          ),
          if (action != null) ...[
            SizedBox(height: 20 * k),
            MemoryPillButton(
              label: action!,
              kind: MemoryPillKind.primary,
              onPressed: onAction,
              automationId: automationId,
              automationInstance: automationInstance,
            ),
          ],
        ],
      ),
    );
  }
}
