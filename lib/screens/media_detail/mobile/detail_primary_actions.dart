import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import 'detail_dark_style.dart';

/// Fill of the solid play button: white in every theme (Plex look).
const Color kDetailPlayFill = Colors.white;

/// Label and icon colour on the play button.
const Color kDetailPlayInk = Colors.black;

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

  /// Bekeken or on the kijklijst. Read out as selected; the glyph shows it.
  final bool active;
  final VoidCallback onTap;

  /// What VoiceOver reads when the short [label] does not say what a tap does.
  final String? semanticLabel;
}

/// The play button, "play from start" beside it while there is progress, and
/// the icon row below (mockups D-01 and D-03, DEC-140), in the Plex look:
/// a solid white full-width button and loose dark translucent circles with
/// their label underneath, no plate behind them. The page around it is always
/// dark, so none of this follows the light theme.
class DetailPrimaryActions extends StatelessWidget {
  const DetailPrimaryActions({
    super.key,
    required this.playLabel,
    this.playDetail,
    this.onPlay,
    this.onPlayFromStart,
    required this.actions,
  });

  final String playLabel;

  /// The muted tail after the label, like "· nog 8 min".
  final String? playDetail;
  final VoidCallback? onPlay;

  /// Null hides the restart button.
  final VoidCallback? onPlayFromStart;
  final List<DetailActionItem> actions;

  @override
  Widget build(BuildContext context) {
    final detail = playDetail;
    final Widget play = SizedBox(
      key: const Key('media-detail.play'),
      height: 52,
      child: FilledButton.icon(
        onPressed: onPlay,
        style: FilledButton.styleFrom(backgroundColor: kDetailPlayFill, foregroundColor: kDetailPlayInk),
        icon: const Icon(Icons.play_arrow_rounded, size: 28),
        label: Text.rich(
          TextSpan(
            text: playLabel,
            children: [
              if (detail != null)
                TextSpan(
                  text: ' $detail',
                  style: TextStyle(fontWeight: .w400, color: kDetailPlayInk.withValues(alpha: 0.62)),
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
              AutomationNode(
                id: AutomationIds.mediaDetailPlayFromStart,
                role: 'button',
                child: Tooltip(
                  message: t.mediaMenu.playFromBeginning,
                  child: _RestartCircle(onTap: onPlayFromStart!),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // `media-detail.action.watched` becomes `media-detail.action[watched]`.
    final key = action.key;
    return AutomationNode(
      id: AutomationIds.mediaDetailAction,
      instance: key is ValueKey<String> ? key.value.split('.').last : null,
      role: 'button',
      child: Semantics(
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
                // The state shows in the glyph (a filled bookmark or check),
                // not in the circle, the way Plex does it.
                DecoratedBox(
                  decoration: const ShapeDecoration(
                    color: kDetailPillColor,
                    shape: CircleBorder(side: BorderSide(color: kDetailPillEdge)),
                  ),
                  child: SizedBox.square(dimension: 46, child: Icon(action.icon, size: 22, color: onSurface)),
                ),
                const SizedBox(height: 7),
                Text(
                  action.label,
                  maxLines: 2,
                  overflow: .ellipsis,
                  textAlign: .center,
                  style: TextStyle(fontSize: 11.5, height: 1.2, color: onSurface.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The round "play from start" button beside the play button: dark and
/// translucent like the action circles.
class _RestartCircle extends StatelessWidget {
  const _RestartCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Material(
      key: const Key('media-detail.play-from-start'),
      color: kDetailPillColor,
      shape: const CircleBorder(side: BorderSide(color: kDetailPillEdge)),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(dimension: 52, child: Icon(Icons.replay_rounded, size: 23, color: onSurface)),
      ),
    );
  }
}
