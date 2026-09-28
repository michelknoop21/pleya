import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../mobile_detail_hero.dart';

/// One round icon under the play button (D-01 `.acts`).
class DetailActionItem {
  const DetailActionItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.semanticLabel,
  });

  final Key key;
  final IconData icon;
  final String label;

  /// Bekeken or on the kijklijst: a white circle with a dark glyph.
  final bool active;
  final VoidCallback onTap;

  /// What VoiceOver reads when the short [label] does not say what a tap does.
  final String? semanticLabel;
}

/// The play button, "play from start" beside it while there is progress, and
/// the icon row below (mockups D-01 and D-03, DEC-140).
class DetailPrimaryActions extends StatelessWidget {
  const DetailPrimaryActions({
    super.key,
    required this.playLabel,
    this.playDetail,
    this.onPlay,
    this.onPlayFromStart,
    required this.actions,
    this.glass = false,
  });

  final String playLabel;

  /// The muted tail after the label, like "· nog 8 min".
  final String? playDetail;
  final VoidCallback? onPlay;

  /// Null hides the restart button.
  final VoidCallback? onPlayFromStart;
  final List<DetailActionItem> actions;

  /// Liquid Glass on: the play button is the prominent glass capsule (LG-02).
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    // The page colour: the capsule inverts with the theme.
    final ink = theme.scaffoldBackgroundColor;
    final detail = playDetail;
    final label = detail == null ? playLabel : '$playLabel $detail';
    final Widget play = glass
        ? GlassCapsuleButton(
            key: const Key('media-detail.play'),
            prominent: true,
            icon: Icons.play_arrow_rounded,
            label: label,
            onPressed: onPlay,
          )
        : SizedBox(
            key: const Key('media-detail.play'),
            height: 52,
            child: FilledButton.icon(
              onPressed: onPlay,
              style: FilledButton.styleFrom(backgroundColor: onSurface, foregroundColor: ink),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text.rich(
                TextSpan(
                  text: playLabel,
                  children: [
                    if (detail != null)
                      TextSpan(
                        text: ' $detail',
                        style: TextStyle(fontWeight: .w400, color: ink.withValues(alpha: 0.62)),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: .ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: .w700),
              ),
            ),
          );

    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          children: [
            // Same id the TV/desktop play action registers (`action_buttons.dart`).
            Expanded(
              child: AutomationNode(id: AutomationIds.mediaDetailPlay, role: 'button', child: play),
            ),
            if (onPlayFromStart != null) ...[
              const SizedBox(width: 12),
              Tooltip(
                message: t.mediaMenu.playFromBeginning,
                child: Material(
                  key: const Key('media-detail.play-from-start'),
                  color: onSurface.withValues(alpha: 0.14),
                  shape: const CircleBorder(),
                  clipBehavior: .antiAlias,
                  child: InkWell(
                    onTap: onPlayFromStart,
                    child: SizedBox.square(
                      dimension: 52,
                      child: Icon(Icons.replay_rounded, size: 23, color: onSurface),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: .start,
            children: [for (final action in actions) Expanded(child: _ActionButton(action: action))],
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final DetailActionItem action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: action.active,
      label: action.semanticLabel ?? action.label,
      excludeSemantics: true,
      child: InkWell(
        key: action.key,
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: action.active ? onSurface : onSurface.withValues(alpha: 0.08),
                ),
                child: SizedBox.square(
                  dimension: 46,
                  child: Icon(action.icon, size: 22, color: action.active ? theme.scaffoldBackgroundColor : onSurface),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                action.label,
                maxLines: 1,
                overflow: .ellipsis,
                textAlign: .center,
                style: TextStyle(fontSize: 11.5, height: 1.2, color: onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
