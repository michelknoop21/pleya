/// The compact page header of hoofdstuk 10.2: the catalog's name, and a quiet
/// statement of what the page is currently narrowed to.
///
/// ```
/// Alle films                    [Niet bekeken] [Sciencefiction] ⌐Titel A-Z¬
/// ```
///
/// One line, which is a deliberate reading of two contract statements that
/// disagree on the page: hoofdstuk 10.2's own sketch puts the title and what
/// follows it on one line, while `series-reference.png` stacks them. On the
/// canonical 584-logical-high canvas the stacked version costs a fifth of a
/// poster row for nothing — and hoofdstuk 10.2 is the binding half.
///
/// **Nothing here is focusable, since CAT5.** Until 4 September 2026 the right
/// of this line held Bronnen, Filters and Sortering as three capsules, and
/// [DEC-093](../../../docs/DECISIONS.md#dec-093) moved them into the rail left
/// of the grid. Michel's words on the corner they vacated: "Graag die waarop
/// gefilterd mag dan wel rechtsboven getoond worden want nu hoeven die niet
/// meer bereikbaar te zijn en je hebt daar meer ruimte." So the corner now
/// carries the answer rather than the controls, and the reachability question
/// CAT3 and CAT4 were both about does not apply to it any more.
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../screens/tv/tv_root_shell.dart';
import 'tv_catalog_selection_tags.dart';
import 'tv_unified_layout.dart';

class TvCatalogHeaderBar extends StatelessWidget {
  const TvCatalogHeaderBar({super.key, required this.title, this.tags = const []});

  final String title;

  /// What the catalog is narrowed to, filters first and the sort last. Empty on
  /// a page with nothing applied, which draws nothing at all rather than an
  /// "Alles" that says the same as the absence would.
  final List<TvCatalogSelectionTag> tags;

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
          // Hoofdstuk 33.5 is explicit that what balances the heading sits
          // *right*, against the opposite page inset. `Expanded` is the *only*
          // flex child here, and that is what pins it there (CAT3): the tag row
          // below is a plain, unflexed sibling, so Flutter lays it out first at
          // its own intrinsic width and hands the title everything that is
          // left. Wrapping it in `Flexible(fit: FlexFit.loose)` looked
          // identical on the canonical canvas, but a loose flex only guarantees
          // a *maximum*, not that the child reaches the edge. On a real
          // 1920x1080 surface it left the cluster up to ~240 logical pixels
          // short of it. The finding was made against the old action capsules
          // and survives them: the geometry is about the Row, not about what
          // the second child happens to be.
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
          if (tags.isNotEmpty) ...[
            SizedBox(width: TvCatalogLayout.titleActionGap * scale),
            // Capped to the row's own content width, not left unbounded: a
            // non-flex Row child gets unconstrained main-axis constraints, and
            // without this cap a title squeezed to nothing plus an over-wide
            // tag row would overflow. The cap is the same content box every
            // other measurement on this page already lines up against.
            //
            // The tags themselves cannot overflow it in practice, because
            // [TvCatalogLayout.tagOverflowThreshold]
            // collapses a long selection into `+N`, and this is the backstop for the case that
            // cannot cover: a single very long genre name.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width - horizontalInset * 2),
              // Anchored to its right edge, so a row that does not fit loses
              // its *leading* tags. The sort tag is last and always present,
              // and it is the one that would otherwise disappear first, which
              // is backwards, because it is the only one that is always true.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                physics: const NeverScrollableScrollPhysics(),
                child: TvCatalogSelectionTagStrip(tags: tags, scale: scale),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
