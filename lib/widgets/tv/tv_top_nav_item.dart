/// One destination in [TvTopNavigation]: a pill that is white when active,
/// quiet text when idle, with a white ring for focus.
///
/// Glass on (LG-04): the pills sit on the bar's glass capsule. Idle text goes
/// to white 88% with [glassText]; the active pill stays white with black text
/// and no shadow. A white ring on a white pill disappears, so focus on the
/// active pill is a 1.08 scale plus a drop shadow instead of the ring. Focus on
/// an idle pill keeps the ring.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../focus/card_focus_scope.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../navigation/tv/tv_destination.dart';
import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_text.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import 'tv_unified_layout.dart';

/// Idle label ink on the glass capsule (LG-04): brighter than
/// [TvTopNavLayout.inactiveInk] because the glass, not the page, is behind it.
const double kTvNavGlassInactiveInk = 0.88;

/// Focus on the active pill with glass on: scale and shadow replace the ring.
const double kTvNavGlassActiveFocusScale = 1.08;
const BoxShadow kTvNavGlassActiveFocusShadow = BoxShadow(
  offset: Offset(0, 8),
  blurRadius: 22,
  color: Color(0x66000000),
);

class TvTopNavItem extends StatelessWidget {
  const TvTopNavItem({
    super.key,
    required this.destination,
    required this.isActive,
    required this.needsAttention,
    required this.node,
    required this.scale,
    required this.onSelect,
    required this.onFocused,
    required this.onNavigateDown,
    required this.onNavigateLeft,
    required this.onNavigateRight,
  });

  final TvDestinationId destination;
  final bool isActive;
  final bool needsAttention;
  final FocusNode node;
  final double scale;
  final VoidCallback onSelect;
  final VoidCallback onFocused;
  final VoidCallback onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    const shape = StadiumBorder();
    final glass = glassTierFor(context) != GlassTier.off;
    // The one place the ring gives way (docs/liquid-glass-mockups-2026-09.md,
    // Contrast): glass on, white pill. The child draws focus itself.
    final delegateFocus = glass && isActive;
    final idleInk = tk.text.withValues(alpha: glass ? kTvNavGlassInactiveInk : TvTopNavLayout.inactiveInk);
    final ink = isActive ? tk.bg : idleInk;
    // VIS-0925-D: the drop shadow keeps light ink legible on the dark plate.
    // On the Light plate the ink is dark and a dark shadow only smears it.
    final shadows = glass && !isActive && !tk.isLight ? kGlassTextShadows : null;

    Widget pill(bool activeFocused) => AnimatedContainer(
      duration: TvTopNavLayout.focusDuration,
      curve: Curves.easeOut,
      decoration: ShapeDecoration(
        shape: shape,
        color: isActive ? tk.text : Colors.transparent,
        shadows: activeFocused ? const [kTvNavGlassActiveFocusShadow] : null,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: destination.isCompact
            ? TvTopNavLayout.pillPaddingVertical * scale
            : TvTopNavLayout.pillPaddingHorizontal * scale,
        vertical: TvTopNavLayout.pillPaddingVertical * scale,
      ),
      child: destination.isCompact
          ? Icon(Symbols.search_rounded, size: TvTopNavLayout.searchIconSize * scale, color: ink, shadows: shadows)
          : Text(
              destination.label,
              maxLines: 1,
              // Long locales shrink inside the pill rather than truncating
              // or wrapping (hoofdstuk 25): a clipped destination is a
              // destination you cannot identify, and a second line would
              // change the height of the whole bar.
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                fontSize: TvTopNavLayout.itemFontSize * scale,
                fontWeight: FontWeight.w500,
                color: ink,
                shadows: shadows,
              ),
            ),
    );

    Widget body = Stack(
      clipBehavior: Clip.none,
      children: [
        if (delegateFocus)
          Builder(
            builder: (context) {
              final focused = CardFocusScope.maybeOf(context) ?? false;
              return AnimatedScale(
                scale: focused ? kTvNavGlassActiveFocusScale : 1,
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                child: pill(focused),
              );
            },
          )
        else
          pill(false),
        if (needsAttention)
          // Directional, not physical: `right` would keep the dot on the
          // physical right of the pill while the bar itself mirrors, so
          // under RTL it would sit on the wrong corner. Same mismatch
          // DEC-072 fixed for the hero CTAs.
          PositionedDirectional(
            top: -TvTopNavLayout.attentionDotInset * scale,
            end: -TvTopNavLayout.attentionDotInset * scale,
            child: Container(
              width: TvTopNavLayout.attentionDotSize * scale,
              height: TvTopNavLayout.attentionDotSize * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Amber, not the brand red. Hoofdstuk 14.7 keeps the two
                // apart everywhere else in this rewrite for the same
                // reason: an expired session is something the viewer can
                // fix from the couch, and amber is what the source picker
                // and Mijn Pleya already use to say so. Red here would
                // read as breakage.
                color: kAccentAlt,
                // A hairline of the bar's own ground, so the dot stays
                // legible where it overlaps the white active pill.
                border: Border.all(color: tk.bg, width: 1),
              ),
            ),
          ),
      ],
    );
    // The ring mode reserves its stroke width around the child; the delegated
    // mode does not. Reserving it here keeps the bar's geometry identical
    // whichever pill is active.
    if (delegateFocus) body = Padding(padding: const EdgeInsets.all(FocusTheme.focusBorderWidth), child: body);

    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      // `nav.<tab>`, the same ids the rail's own items carry — this bar is the
      // TV shell's navigation, so it answers to the same addresses. No new id
      // and no extra widget: `FocusableWrapper` already owns the registration.
      //
      // `state.active` is the destination's own white-capsule flag, so a
      // scenario can tell "Films is the page you are on" from "Films is where
      // the ring is" without inferring either from a screenshot.
      automationId: AutomationIds.navTab(destination.tab),
      automationRole: 'nav',
      automationState: () => {'active': isActive},
      onFocusChange: (focused) {
        if (focused) onFocused();
      },
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      mode: delegateFocus ? FocusIndicatorMode.delegated : FocusIndicatorMode.ring,
      focusShapeBorder: shape,
      // The bar must not move. A scaling pill nudges its neighbours on every
      // Left/Right, and on a remote that is the difference between reading the
      // row and chasing it. (The glass active pill scales its own paint only;
      // its layout box stays put.)
      disableScale: true,
      // Active and focused are separate facts, so they are announced
      // separately: the ring is focus and this word is the page you are on.
      // Everything below is inside an `ExcludeSemantics`, so the dot cannot
      // carry a node of its own — it has to be said here or not at all.
      semanticLabel: [
        destination.label,
        if (isActive) t.tvNavigation.activeDestination,
        if (needsAttention) t.tvNavigation.attentionRequired,
      ].join(', '),
      // The label above already names the destination. Leaving the glyph and
      // the pill's own Text in the tree as well would merge a second copy into
      // the same node, and VoiceOver would read "Films, current section, Films".
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvTopNavLayout.focusRingGap * scale),
          // The dot is an overlay, and `clipBehavior: none` lets it sit just
          // outside the pill. A `Stack` sizes to its largest non-positioned
          // child, and the pill is the only one of those, so the bar's
          // geometry is identical with the dot and without it.
          child: body,
        ),
      ),
    );
  }
}
