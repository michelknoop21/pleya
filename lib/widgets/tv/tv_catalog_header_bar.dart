/// The compact page header of hoofdstuk 10.2: the catalog's name, and the
/// three actions that change what is under it.
///
/// ```
/// Films                    [Alle bronnen] [Filters 2] [Titel A–Z]
/// ```
///
/// One line, which is a deliberate reading of two contract statements that
/// disagree on the page: hoofdstuk 10.2's own sketch puts the title and the
/// actions on one line, while `series-reference.png` stacks them. On the
/// canonical 584-logical-high canvas the stacked version costs a fifth of a
/// poster row for nothing — and hoofdstuk 10.2 is the binding half.
///
/// It shares [LibraryHeaderAction] with the Libraries and Requests headers,
/// because what those surfaces genuinely have in common is the *action* — its
/// label, its current value, whether it is narrowing anything, and the focus
/// node plus D-pad exits that make it reachable — and not the box it is drawn
/// in. `LibraryHeaderBar` draws that model as a dense desktop line with tabs
/// and a hairline; this draws it as 10-foot capsules. Forcing one widget to do
/// both would mean one of them inheriting the other's density, which is exactly
/// the "mobile app stretched over a TV" failure hoofdstuk 3 is against.
library;

import 'package:flutter/material.dart';

import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../screens/tv/tv_root_shell.dart';
import '../library_header_bar.dart';
import 'tv_unified_layout.dart';

class TvCatalogHeaderBar extends StatelessWidget {
  const TvCatalogHeaderBar({super.key, required this.title, required this.actions});

  final String title;

  /// In reading order. Each carries its own focus node and its own LEFT/RIGHT
  /// exits, wired by the screen — the header does not know what sits beside it.
  final List<TvCatalogHeaderAction> actions;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final grid = TvCatalogGrid.forWidth(width, scale: scale);
    final horizontalInset = grid.inset + TvCatalogLayout.cardContentInset(scale);

    return Padding(
      // The top inset is hoofdstuk 8.1's overscan rule — "geen tekst of
      // focusring binnen de buitenste 56 pixels" — and, like the horizontal
      // one, a fraction of the viewport rather than a `scale` multiple. On the
      // canonical canvas that is ~30 logical pixels; the first render used
      // `14 * scale`, twelve, and the page title sat visibly on the overscan
      // line.
      // The horizontal inset is the grid's, plus the same amount a card spends
      // inside its own column before its artwork starts. Without that second
      // term the page title began six logical pixels left of every poster and
      // every card title under it: on a page with no hero, no divider and no
      // change of background, that content column is the only vertical line the
      // composition has, and the heading sitting above it was the one element
      // off it.
      // The top inset is the page's overscan margin, and the fase-7 shell
      // already spent it on the top navigation and the gap under it. Spending
      // it again pushed the heading from thirteen to twenty-two per cent of the
      // canvas and the first grid row from eighteen to thirty-one, which is a
      // band of dead space the north star does not have. Standalone — a golden,
      // a focus test — this page still owns its own top margin.
      padding: EdgeInsets.fromLTRB(
        horizontalInset,
        TvShellSurface.isPresent(context)
            ? 0
            : MediaQuery.sizeOf(context).height * (TvCatalogLayout.topSafeInset / 1080),
        horizontalInset,
        TvCatalogLayout.headerContentGap * scale,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Hoofdstuk 33.5 is explicit that the controls sit *right* — the
          // heading owns the left edge and the quiet controls balance it
          // against the opposite page inset. `Expanded` is the *only* flex
          // child here (CAT3): the actions cluster below is a plain,
          // unflexed sibling, so Flutter lays it out first at its own
          // intrinsic width and hands the title everything that is left —
          // which is what actually pins the actions to the row's own right
          // edge. Wrapping the actions in `Flexible(fit: FlexFit.loose)`
          // looked identical on the canonical canvas (its intrinsic width
          // happens to be close to the 50/50 split flex gives two siblings
          // of equal weight), but on a real 1920×1080 surface — or with the
          // Bronnen action conditionally missing — the two widths diverge and
          // the loose flex only guarantees a *maximum*, not that the actions
          // reach the edge: it left them floating up to ~240 logical pixels
          // short of it. A plain child is not shrink-capped by a flex share
          // at all, so it always renders at its natural width and Row places
          // it flush against the content box's own right edge.
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvCatalogLayout.pageTitleFontSize * scale,
                fontWeight: FontWeight.w700,
                color: tk.text,
                // Tightened, because a 10-foot heading at default tracking
                // reads as a banner rather than as a title.
                letterSpacing: -0.6,
                height: 1.1,
              ),
            ),
          ),
          SizedBox(width: TvCatalogLayout.titleActionGap * scale),
          // Capped to the row's own content width, not left unbounded: a
          // non-flex Row child gets unconstrained main-axis constraints, and
          // without this cap a title squeezed to nothing plus an
          // over-wide action set would overflow instead of scrolling. The
          // cap is the same content box every other measurement on this page
          // already lines up against, not a screen-specific number.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width - horizontalInset * 2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) SizedBox(width: TvCatalogLayout.actionGap * scale),
                    _ActionCapsule(action: actions[i], scale: scale),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One header action, plus the two things a 10-foot capsule adds to
/// [LibraryHeaderAction]: a leading glyph and a count badge.
class TvCatalogHeaderAction {
  const TvCatalogHeaderAction({required this.action, required this.icon, this.badgeCount = 0});

  /// The shared model. Everything about *what this action is* lives here.
  final LibraryHeaderAction action;

  final IconData icon;

  /// Hoofdstuk 10.6's "Actieve filtercount verschijnt op de Filter-knop".
  /// Zero draws nothing — a badge reading 0 is a badge that should not be
  /// there.
  final int badgeCount;
}

class _ActionCapsule extends StatelessWidget {
  const _ActionCapsule({required this.action, required this.scale});

  final TvCatalogHeaderAction action;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    // An idle action carries no outline at all. Three outlined capsules in a row
    // are three objects competing with a one-word page title, which is the
    // desktop-toolbar feel the header is meant not to have; without the line
    // they settle into one quiet control cluster and "Movies" leads again. The
    // outline comes back the moment the action is *doing* something — a filter
    // count, a narrowed scope — because then it is information rather than
    // decoration.
    final shape = StadiumBorder(
      side: action.badgeCount > 0
          ? BorderSide(color: tk.text.withValues(alpha: TvCatalogLayout.cardOutline), width: 1)
          : BorderSide.none,
    );

    return FocusableWrapper(
      focusNode: action.action.focusNode,
      onSelect: action.action.onPressed,
      onNavigateUp: action.action.onNavigateUp,
      onNavigateDown: action.action.onNavigateDown,
      onNavigateLeft: action.action.onNavigateLeft,
      onNavigateRight: action.action.onNavigateRight,
      onBack: action.action.onBack,
      // The ring is the capsule's own shape, drawn outside it with a gap: a
      // white ring hugging a pale capsule reads as a slightly fatter capsule.
      focusShapeBorder: shape,
      disableScale: true,
      semanticLabel: _semanticLabel,
      child: Padding(
        padding: EdgeInsets.all(TvCatalogLayout.actionFocusRingGap * scale),
        child: Container(
          decoration: ShapeDecoration(
            shape: shape,
            color: tk.text.withValues(alpha: TvCatalogLayout.actionFill),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: TvCatalogLayout.actionPaddingHorizontal * scale,
            vertical: TvCatalogLayout.actionPaddingVertical * scale,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon,
                size: TvCatalogLayout.actionIconSize * scale,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
              ),
              SizedBox(width: TvCatalogLayout.actionIconGap * scale),
              Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TvCatalogLayout.actionFontSize * scale,
                  fontWeight: FontWeight.w600,
                  // Secondary ink while the action is idle. Full white on three
                  // labels next to a full-white title is four things shouting;
                  // the value is still perfectly readable at three metres one
                  // step down, and the title gets the top of the hierarchy back.
                  color: tk.text.withValues(
                    alpha: action.badgeCount > 0 ? TvCatalogLayout.inkPrimary : TvCatalogLayout.inkSecondary,
                  ),
                  height: 1.1,
                ),
              ),
              if (action.badgeCount > 0) ...[
                SizedBox(width: TvCatalogLayout.actionIconGap * scale),
                _CountBadge(count: action.badgeCount, scale: scale),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The capsule's text: the action's current value where it has one, the
  /// label otherwise.
  ///
  /// A capsule reading "Sort  Title A–Z" spends half a 10-foot line saying
  /// what the value already says. The label survives in the semantic label
  /// below, where the value alone would be ambiguous read out loud.
  String get _label => action.action.value ?? action.action.label;

  String get _semanticLabel {
    final value = action.action.value;
    final base = value == null ? action.action.label : '${action.action.label}: $value';
    return action.badgeCount > 0 ? '$base (${action.badgeCount})' : base;
  }
}

/// The count on the Filters action. Brand red, which hoofdstuk 8.2 and 34
/// allow for a badge — and it is the one place on this page where a colour
/// carries information that shape and position cannot.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.scale});

  final int count;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final size = TvCatalogLayout.actionBadgeSize * scale;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tk.accent, shape: BoxShape.circle),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: TvCatalogLayout.actionBadgeFontSize * scale,
          fontWeight: FontWeight.w700,
          // White on brand red regardless of theme: the badge is a fixed
          // colour, so its ink cannot follow the theme's.
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
