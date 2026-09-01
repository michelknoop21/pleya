/// The horizontal root navigation of the TV shell (fase 7).
///
/// Replaces [SideNavigationRail] as the TV root, and only there — desktop keeps
/// the rail, mobile keeps its bottom bar (hoofdstuk 6.1). The composition is
/// the frozen north star's shared shell: a profile chip alone at the far left,
/// the search glyph and the labelled destinations as one horizontally centred
/// cluster, and the Pleya wordmark lockup at the far right.
///
/// Three states, and they are three (see [DEC-053], and hoofdstuk 33's
/// "Actieve bestemming = witte capsule"):
///
/// | state | treatment |
/// | --- | --- |
/// | active | white capsule, `#141414` label |
/// | focused | white ring, drawn outside the box with a gap |
/// | idle | quiet white text at [TvTopNavLayout.inactiveInk] |
///
/// Active and focused are independent: walking the bar with Left/Right moves
/// the ring and leaves the capsule where it is, which is what lets the remote
/// browse the destinations without tearing down the page behind them
/// (hoofdstuk 24). Red is not in this table at all — hoofdstuk 33 reserves
/// `#E5140F` for the progress line, so there is no red focus and no red pill.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focus_memory_tracker.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../navigation/tv/tv_destination.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_avatar.dart';
import '../../theme/mono_theme.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';

class TvTopNavigation extends StatelessWidget {
  const TvTopNavigation({
    super.key,
    required this.destinations,
    required this.active,
    required this.nodes,
    required this.onSelect,
    required this.onFocusDestination,
    this.needsAttention = false,
    required this.onNavigateDown,
    required this.onOpenProfiles,
    this.profile,
  });

  /// Left to right, as [buildTvDestinations] ordered them.
  final List<TvDestinationId> destinations;

  /// The destination whose content is on screen — the white capsule.
  final TvDestinationId active;

  /// Focus nodes keyed by [TvDestinationId.focusKey], owned by the shell so a
  /// rebuild of this bar cannot drop the focus it is holding.
  final FocusMemoryTracker nodes;

  final ValueChanged<TvDestinationId> onSelect;

  /// Reports the ring moving. Distinct from [onSelect] on purpose: the ring
  /// moving must not change the page.
  final ValueChanged<TvDestinationId> onFocusDestination;

  /// Whether something under Mijn Pleya is waiting on the user — today, a
  /// server whose token was rejected.
  ///
  /// Deliberately one boolean and not a count or a list. Hoofdstuk 18.4 allows
  /// "een klein statuspunt bij Mijn Pleya" and forbids "een permanente grote
  /// rode melding over content"; a number on the bar would start down the road
  /// the second half rules out, and the concrete servers already have a place
  /// to be named — the Servers screen this destination leads to.
  final bool needsAttention;

  /// Down from any bar item goes into the current destination's content
  /// (hoofdstuk 7.2).
  final VoidCallback onNavigateDown;

  final VoidCallback onOpenProfiles;

  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        TvTopNavLayout.pageInset * scale,
        TvTopNavLayout.topInset * scale,
        TvTopNavLayout.pageInset * scale,
        TvTopNavLayout.contentGap * scale,
      ),
      child: ConstrainedBox(
        // A floor, not a ceiling. Pinning the height exactly cost the first
        // render its own pills: the capsule plus its focus-ring gap is slightly
        // taller than the band, and a hard height clipped the labels against
        // the top edge instead of letting the bar grow the few pixels it
        // needed. A long locale with taller metrics would have done the same.
        constraints: BoxConstraints(minHeight: TvTopNavLayout.barHeight * scale),
        // A Stack, not a three-cell Row: hoofdstuk 33 centres the destination
        // cluster on the *screen*, not in the space left over between the
        // profile chip and the wordmark. Those two have different widths, so a
        // Row with a Spacer either side would push the cluster off-centre by
        // half their difference — and the offset would change with the
        // wordmark's locale-independent width against a chip that grows a lock
        // badge. Centring against the full width keeps Home where the eye
        // expects it whatever flanks it.
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _ProfileChip(
                profile: profile,
                node: nodes.get(_profileFocusKey, debugLabel: 'tvNav_profile'),
                scale: scale,
                onSelect: onOpenProfiles,
                onNavigateDown: onNavigateDown,
                onNavigateRight: destinations.isEmpty ? null : () => _focus(destinations.first),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < destinations.length; i++) ...[
                  if (i > 0)
                    SizedBox(key: ValueKey('${destinations[i].focusKey}_gap'), width: TvTopNavLayout.itemGap * scale),
                  _NavItem(
                    // Keyed on the destination, not on its position. Without
                    // this, a Live TV slot appearing shifts every later child
                    // by one and Flutter matches children by position: Mijn
                    // Pleya's element is reused for Live TV, the element
                    // holding the remote's focus is torn down, and the focus
                    // falls out of the bar entirely. Hoofdstuk 7.2's last
                    // bullet is precisely this — a new item "vervangt geen
                    // focusnode van een bestaand item".
                    key: ValueKey(destinations[i].focusKey),
                    destination: destinations[i],
                    isActive: destinations[i] == active,
                    node: nodes.get(destinations[i].focusKey, debugLabel: destinations[i].focusKey),
                    scale: scale,
                    // Hoofdstuk 18.4: the dot rides the destination that owns
                    // the resolution route, and only that one.
                    needsAttention: destinations[i] == TvDestinationId.myPleya && needsAttention,
                    onSelect: () => onSelect(destinations[i]),
                    onFocused: () => onFocusDestination(destinations[i]),
                    onNavigateDown: onNavigateDown,
                    // No wrap at either end (hoofdstuk 7.2). The first item
                    // hands Left to the profile chip, which is the only thing
                    // to its left; the last simply stops.
                    onNavigateLeft: i == 0 ? () => _focusKey(_profileFocusKey) : () => _focus(destinations[i - 1]),
                    onNavigateRight: i == destinations.length - 1 ? null : () => _focus(destinations[i + 1]),
                  ),
                ],
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              // Not focusable. The wordmark is branding, not a destination:
              // giving it a focus stop would put a dead end at the end of every
              // rightward walk. It is hidden from semantics for the same
              // reason — "Pleya" read out after the last destination tells a
              // VoiceOver user nothing about where they are.
              child: ExcludeSemantics(
                child: Image.asset(
                  'assets/branding/pleya_wordmark.png',
                  height: TvTopNavLayout.wordmarkHeight * scale,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _focus(TvDestinationId id) => _focusKey(id.focusKey);

  void _focusKey(String key) {
    final node = nodes.get(key);
    if (node.canRequestFocus) node.requestFocus();
  }
}

/// The profile chip's focus key. Its own constant rather than a
/// [TvDestinationId] value: the chip opens the profile picker on the *root*
/// navigator and never becomes an active destination, so it has no pill state
/// and no tab behind it.
const String _profileFocusKey = 'tvNav_profile';

class _NavItem extends StatelessWidget {
  const _NavItem({
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

    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      onFocusChange: (focused) {
        if (focused) onFocused();
      },
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      focusShapeBorder: shape,
      // The bar must not move. A scaling pill nudges its neighbours on every
      // Left/Right, and on a remote that is the difference between reading the
      // row and chasing it.
      disableScale: true,
      // Active and focused are separate facts, so they are announced
      // separately: the ring is focus and this word is the page you are on.
      // Without it VoiceOver would say the same thing on all six items.
      // Everything below is inside an `ExcludeSemantics`, so the dot cannot
      // carry a node of its own — it has to be said here or not at all. A
      // silent red mark is exactly the kind of state a screen-reader user is
      // left to guess at.
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
          // geometry is identical with the dot and without it — which is the
          // whole requirement: a token expiring must not move Films and Series
          // sideways under the remote.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                decoration: ShapeDecoration(shape: shape, color: isActive ? tk.text : Colors.transparent),
                padding: EdgeInsets.symmetric(
                  horizontal: destination.isCompact
                      ? TvTopNavLayout.pillPaddingVertical * scale
                      : TvTopNavLayout.pillPaddingHorizontal * scale,
                  vertical: TvTopNavLayout.pillPaddingVertical * scale,
                ),
                child: destination.isCompact
                    ? Icon(
                        Symbols.search_rounded,
                        size: TvTopNavLayout.searchIconSize * scale,
                        color: isActive ? tk.bg : tk.text.withValues(alpha: TvTopNavLayout.inactiveInk),
                      )
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
                          color: isActive ? tk.bg : tk.text.withValues(alpha: TvTopNavLayout.inactiveInk),
                        ),
                      ),
              ),
              if (needsAttention)
                Positioned(
                  top: -TvTopNavLayout.attentionDotInset * scale,
                  right: -TvTopNavLayout.attentionDotInset * scale,
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
          ),
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.profile,
    required this.node,
    required this.scale,
    required this.onSelect,
    required this.onNavigateDown,
    required this.onNavigateRight,
  });

  final Profile? profile;
  final FocusNode node;
  final double scale;
  final VoidCallback onSelect;
  final VoidCallback onNavigateDown;
  final VoidCallback? onNavigateRight;

  @override
  Widget build(BuildContext context) {
    final size = TvTopNavLayout.profileChipSize * scale;
    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      onNavigateDown: onNavigateDown,
      onNavigateRight: onNavigateRight,
      focusShape: BoxShape.circle,
      disableScale: true,
      // The avatar is an identity, not a label, so what pressing it does is
      // said out loud — the same reasoning as the mobile My Pleya header.
      semanticLabel: t.screens.switchProfile,
      child: Padding(
        padding: EdgeInsets.all(TvTopNavLayout.focusRingGap * scale),
        child: ExcludeSemantics(
          child: ProfileAvatar(profile: profile, size: size, showLockBadge: false),
        ),
      ),
    );
  }
}
