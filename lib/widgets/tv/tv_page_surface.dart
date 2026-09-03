/// The shared layout authority for every nested Mijn Pleya page on TV.
///
/// Before this existed, each section drew its own heading at its own inset and
/// let its own chrome decide the page's left edge. The audit of 2 September
/// 2026 measured twelve distinct content edges across nine pages: the hub and
/// Home sat on `TvTopNavLayout.pageInset`, Servers put its heading there but
/// its card 1.5% further in, Instellingen ran a heading at 1.67% over a card
/// centred by a desktop `maxWidth` at 9.14%, and Logs put its body text at
/// 1.22%, inside the overscan band `TvCatalogLayout.topSafeInset` reserves.
///
/// One frame, one edge. Everything a page varies is content; everything a page
/// shares is here:
///
/// * the canonical page inset, from the existing token rather than a literal;
/// * where the heading starts, and its type;
/// * the space under the top navigation, so nothing is drawn against it;
/// * bottom safe spacing for the overscan band;
/// * the scroll, so the heading travels with the content.
///
/// **The heading scrolls.** That is the structural half of the fix for content
/// being sliced by page chrome. `CustomAppBar` and `FocusedScrollScaffold`
/// pin a transparent title over a scrolling list, so a row passing behind it
/// is cut in half with nothing to read it against: the audit caught
/// "Library Visibility" severed mid-glyph on Instellingen and Over's tagline
/// severed under its own heading. A heading inside the scrollable cannot
/// overlap anything, so the defect is removed by construction rather than by
/// per-page top padding.
///
/// **Focus is not this widget's job.** [TvNestedSurface] already owns where the
/// remote lands in a nested route, and a second focus framework layered on top
/// of it is how two things end up disagreeing about the same question. This is
/// presentation only; the two share layout tokens and nothing else.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';

/// The canonical horizontal inset for a TV page, in logical pixels.
///
/// One expression, one token. A page that needs the number for something of
/// its own asks here instead of multiplying the constant again.
double tvPageInset(BuildContext context) => TvTopNavLayout.pageInset * TvLayoutConstants.scaleOf(context);

class TvPageSurface extends StatelessWidget {
  const TvPageSurface({
    super.key,
    required this.title,
    required this.children,
    this.automationInstance,
    this.controller,
    this.trailing,
    this.expanded,
  });

  /// The page heading. The section's own title, so the tile that opened it and
  /// the page it opened cannot name the same place differently.
  final String title;

  /// The page body, laid out in a column at the canonical inset.
  final List<Widget> children;

  /// Names the measurable content column in `/v1/ui_tree`, so alignment is a
  /// geometry assertion rather than a judgement about a screenshot. The
  /// instance is the section name.
  final String? automationInstance;

  final ScrollController? controller;

  /// Optional row of page-level controls, drawn on the heading's line.
  final Widget? trailing;

  /// A body that takes the page's remaining height instead of scrolling with
  /// the heading.
  ///
  /// Reserved for a lazily built list. `SingleChildScrollView` gives its child
  /// unbounded height, and a `ListView.builder` under an unbounded constraint
  /// builds every row it has — which on Logs is however many lines a long
  /// diagnostic session produced, laid out before the page can paint. The
  /// screen would get slowest exactly when there is most to read, which is the
  /// moment you open it; `logs_screen.dart` carries that reasoning already and
  /// this is the layout that keeps it true.
  ///
  /// A page with an [expanded] body does not scroll as a whole. It does not
  /// need to: the heading and [children] above it are fixed, so there is
  /// nothing for the body to slide underneath, and the body owns its own
  /// scrolling.
  final Widget? expanded;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    final inset = tvPageInset(context);

    final heading = Text(
      title,
      style: TextStyle(
        color: tk.text,
        fontSize: TvMyPleyaLayout.pageTitleFontSize * scale,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );

    final padding = EdgeInsets.only(
      left: inset,
      right: inset,
      top: TvTopNavLayout.contentGap * scale,
      // The overscan band at the bottom edge, the same reasoning
      // [TvCatalogLayout.bottomSafeInset] documents: a page laid out to the
      // nominal margin puts its last focus ring on the band rather than
      // clear of it.
      bottom: TvCatalogLayout.bottomSafeInset * scale,
    );

    final column = AutomationNode(
      id: AutomationIds.myPleyaSectionContent,
      instance: automationInstance,
      role: 'region',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trailing == null)
            heading
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: heading),
                trailing!,
              ],
            ),
          SizedBox(height: TvMyPleyaLayout.titleGap * scale),
          ...children,
          if (expanded != null) Expanded(child: expanded!),
        ],
      ),
    );

    if (expanded != null) return Padding(padding: padding, child: column);

    return SingleChildScrollView(controller: controller, padding: padding, child: column);
  }
}

/// A group label above a block of tiles, in the hub's own label type.
class TvPageGroupLabel extends StatelessWidget {
  const TvPageGroupLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    return Padding(
      padding: EdgeInsets.only(bottom: TvMyPleyaLayout.groupLabelGap * scale),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
          fontSize: TvMyPleyaLayout.groupLabelFontSize * scale,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Body type for matter a page shows rather than offers: a licence notice, a
/// warning, an empty state. One tier below the tile title, and never a control.
TextStyle tvPageBodyStyle(BuildContext context, {double? alpha}) {
  final scale = TvLayoutConstants.scaleOf(context);
  return TextStyle(
    color: tokens(context).text.withValues(alpha: alpha ?? TvMyPleyaLayout.inkTertiary),
    fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
    height: 1.45,
  );
}

/// A full-width, unfocusable surface in the tile's own material.
///
/// Pages carry matter that is not a destination — the GPL notice Over is
/// required to print, the relay warning on Samen Kijken, the line that says a
/// list is empty. Giving each of those its own card is how a page ends up with
/// a second visual language for everything that is not a control, which is
/// exactly what the audit measured on Over: two card insets over the shell's
/// own heading inset. Same fill, same radius, same edge as the tiles above it.
class TvPageBlock extends StatelessWidget {
  const TvPageBlock({super.key, required this.child});

  TvPageBlock.text(String text, {Key? key}) : this(key: key, child: _BlockText(text));

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tk.text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha),
        borderRadius: BorderRadius.circular(TvMyPleyaLayout.tileRadius * scale),
      ),
      child: Padding(padding: EdgeInsets.all(TvMyPleyaLayout.tilePadding * scale), child: child),
    );
  }
}

class _BlockText extends StatelessWidget {
  const _BlockText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: tvPageBodyStyle(context));
}
