/// A1a: "Home aanpassen" as one line under the last row of Home (ROW1, mockup
/// 32 A1a, [DEC-100](../../../docs/DECISIONS.md#dec-100) (3)).
///
/// ## Why it is a footer and not a button beside the hero
///
/// The first design put it at the right-hand end of the hero's CTA row, where
/// RIGHT from Meer info would reach it. That is where hoofdstuk 7.3 puts the
/// slide change, so the button would have cost the hero its own gesture, and
/// Michel's verdict was that it could not be reached on a TV at all. A full-width
/// line under the last row costs nothing horizontal: it is one DOWN from
/// wherever the ring already is in the bottom row, at the same place every time.
///
/// The trade is that a viewer with eight rows walks past eight of them to get
/// here, which is exactly why A1b exists as well — the context menu on any card
/// carries the same entry.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_wrapper.dart';
import '../../focus/dpad_navigator.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import 'tv_home_row_tiles.dart' show DottedRowBorder;
import 'tv_unified_layout.dart';

/// Finds the footer. Public so a test can prove the entry is on the page rather
/// than that some text is.
const Key tvHomeCustomizeFooterKey = ValueKey('tvHomeCustomizeFooter');

class TvHomeCustomizeFooter extends StatelessWidget {
  const TvHomeCustomizeFooter({
    super.key = tvHomeCustomizeFooterKey,
    required this.focusNode,
    required this.scale,
    required this.onPressed,
    this.onNavigateUp,
  });

  final FocusNode focusNode;
  final double scale;
  final VoidCallback onPressed;
  final VoidCallback? onNavigateUp;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: TvDiscoveryLayout.pageInset * scale),
      child: FocusableWrapper(
        focusNode: focusNode,
        semanticLabel: t.unifiedCatalog.homeRows.customize,
        onNavigateUp: onNavigateUp,
        // Hard stops on the three other directions. Left null they fall through
        // to Flutter's geometric traversal, and the nearest focusable to the
        // left of a full-width row at the foot of the page is a tile in the row
        // above it — so LEFT would climb a row and read as the remote having a
        // mind of its own. This is the last thing on the page; its ends are
        // ends.
        onNavigateDown: () {},
        onNavigateLeft: () {},
        onNavigateRight: () {},
        onSelect: () {
          SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
          onPressed();
        },
        child: Padding(
          padding: EdgeInsets.all(TvHomeRowsLayout.rowFocusRingGap * scale),
          child: DottedRowBorder(
            scale: scale,
            child: Row(
              children: [
                Icon(Symbols.edit_rounded, size: TvHomeRowsLayout.leadingIconSize * scale, color: mono.text),
                SizedBox(width: TvHomeRowsLayout.leadingGap * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.unifiedCatalog.homeRows.customize,
                        style: TextStyle(
                          fontSize: TvHomeRowsLayout.titleFontSize * scale,
                          fontWeight: FontWeight.w600,
                          color: mono.text,
                        ),
                      ),
                      SizedBox(height: TvHomeRowsLayout.titleGap * scale),
                      Text(
                        t.unifiedCatalog.homeRows.customizeSubtitle,
                        style: TextStyle(fontSize: TvHomeRowsLayout.subtitleFontSize * scale, color: mono.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
