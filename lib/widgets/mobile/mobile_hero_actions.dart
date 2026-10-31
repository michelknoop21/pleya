/// The mobile hero's CTA row: a white "Afspelen"/"Hervatten" pill plus a
/// secondary action. iOS Unified 2026 fase 1,
/// `docs/ios-unified-2026-fase1-plan.md` stap 6.
///
/// Which secondary action ships is DEC-090 §10's other open Home detail
/// (A): `+ Mijn lijst` (the Home comp) versus `Meer info` (the TV contract).
/// [mobileHeroSecondaryActionDefault] is a placeholder, not a decision — see
/// that constant's own doc.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focusable_button.dart';
import '../../i18n/strings.g.dart';
import '../app_icon.dart';

enum HeroSecondaryAction { moreInfo, addToList }

/// Placeholder default for [HeroSecondaryAction], **not a design decision**.
/// DEC-090 §10 (A) leaves the choice open pending Michel's review; this
/// constant only keeps `MobileHeroCard` compiling and visually reviewable in
/// the meantime.
const HeroSecondaryAction mobileHeroSecondaryActionDefault = HeroSecondaryAction.moreInfo;

/// A hardware keyboard's route through the two actions. Only the iPad passes
/// one; on a phone the row stays two plain Material buttons.
class MobileHeroActionFocus {
  final FocusNode playNode;
  final FocusNode secondaryNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onBack;

  /// LEFT off the first action and RIGHT off the last one: the slide next door.
  final VoidCallback onPreviousSlide;
  final VoidCallback onNextSlide;

  const MobileHeroActionFocus({
    required this.playNode,
    required this.secondaryNode,
    required this.onPreviousSlide,
    required this.onNextSlide,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onBack,
  });
}

class MobileHeroActions extends StatelessWidget {
  final bool hasProgress;
  final int? minutesLeft;
  final HeroSecondaryAction secondary;
  final VoidCallback onPlay;
  final VoidCallback onSecondary;
  final MobileHeroActionFocus? focus;

  const MobileHeroActions({
    super.key,
    required this.hasProgress,
    this.minutesLeft,
    this.secondary = mobileHeroSecondaryActionDefault,
    required this.onPlay,
    required this.onSecondary,
    this.focus,
  });

  /// [button] under the keyboard's focus. It stays the Material button a finger
  /// taps; `FocusableButton` adds Select, the arrows and a visible ring.
  Widget _focusable(
    MobileHeroActionFocus focus,
    Widget button, {
    required FocusNode node,
    required VoidCallback onPressed,
    required VoidCallback onLeft,
    required VoidCallback onRight,
  }) => FocusableButton(
    focusNode: node,
    autoScroll: false,
    dimWhenUnfocused: false,
    onPressed: onPressed,
    onNavigateUp: focus.onNavigateUp,
    onNavigateDown: focus.onNavigateDown,
    onNavigateLeft: onLeft,
    onNavigateRight: onRight,
    onBack: focus.onBack,
    child: button,
  );

  @override
  Widget build(BuildContext context) {
    final primaryLabel = hasProgress && minutesLeft != null
        ? t.discover.minutesLeft(minutes: minutesLeft!)
        : t.common.play;
    final secondaryLabel = secondary == HeroSecondaryAction.addToList ? t.watchlist.add : t.common.details;
    final secondaryIcon = secondary == HeroSecondaryAction.addToList ? Symbols.add_rounded : Symbols.info_rounded;

    final play = FilledButton.icon(
      onPressed: onPlay,
      icon: const AppIcon(Symbols.play_arrow_rounded, fill: 1, size: 20),
      label: Text(primaryLabel),
    );
    final details = OutlinedButton.icon(
      onPressed: onSecondary,
      icon: AppIcon(secondaryIcon, size: 18, color: Colors.white),
      label: Text(secondaryLabel, style: const TextStyle(color: Colors.white)),
      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
    );
    final focus = this.focus;
    // A Row mirrors under RTL, and the arrows follow what is on screen.
    final mirrored = Directionality.of(context) == TextDirection.rtl;
    return Row(
      children: [
        AutomationNode(
          id: AutomationIds.discoverHeroPlay,
          role: 'button',
          focusNode: focus?.playNode,
          child: focus == null
              ? play
              : _focusable(
                  focus,
                  play,
                  node: focus.playNode,
                  onPressed: onPlay,
                  onLeft: mirrored ? focus.secondaryNode.requestFocus : focus.onPreviousSlide,
                  onRight: mirrored ? focus.onPreviousSlide : focus.secondaryNode.requestFocus,
                ),
        ),
        const SizedBox(width: 12),
        if (focus == null)
          details
        else
          _focusable(
            focus,
            details,
            node: focus.secondaryNode,
            onPressed: onSecondary,
            onLeft: mirrored ? focus.onNextSlide : focus.playNode.requestFocus,
            onRight: mirrored ? focus.playNode.requestFocus : focus.onNextSlide,
          ),
      ],
    );
  }
}
