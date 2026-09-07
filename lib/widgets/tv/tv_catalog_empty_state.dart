/// The empty, error and filtered-empty states of the Films/Series page
/// (hoofdstuk 29 of docs/tvos-unified-experience.md).
///
/// Centred title, body and one optional action — the shape all of hoofdstuk
/// 29's non-content states share, so they cannot drift apart. Extracted from
/// `tv_unified_catalog_screen.dart` unchanged when CAT5 gave that screen a rail
/// to wire.
library;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

class TvCatalogEmptyState extends StatelessWidget {
  const TvCatalogEmptyState({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onActionFocusNode,
    this.onActionNavigateLeft,
  });

  /// Drawn above the title when the state has one.
  ///
  /// Optional, and absent on the catalog: mockups 34 D and 36 C give the
  /// kijklijst and Zoeken a glyph because those two states are reached *while
  /// looking for something*, and the mark says at a glance which of the two
  /// searches came back empty — a filter or a query. The catalog's own states
  /// were approved without one and keep it that way.
  final IconData? icon;

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The action's node, so a caller can put the remote back on it.
  ///
  /// The button autofocuses on mount, which covers arriving at the state. It
  /// does not cover *coming back* to it: LEFT off the button opens CAT5's rail,
  /// and closing the rail again asks the grid for the focus — on a state with
  /// no grid that request lands nowhere, and on tvOS a page with the focus and
  /// no focused item is one you can neither move within nor leave, because the
  /// engine claims every press before UIKit's responder chain sees it.
  final FocusNode? onActionFocusNode;

  /// LEFT off the one action these states have.
  ///
  /// It is the *only* way into CAT5's rail on a page with no grid: the rail
  /// opens on LEFT from column 0, and a filtered-empty catalog has no column 0.
  /// Without this, the state that most needs the filter controls — "nothing
  /// matches these filters" — is the one state that cannot reach them.
  final VoidCallback? onActionNavigateLeft;

  /// The glyph's size, in the same scaled units as the rest of hoofdstuk 8:
  /// mockup 34 D's 88 reference pixels through DEC-028's render scale.
  static const double iconSize = 42;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: TvCatalogEmptyState.iconSize * scale,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkTertiary),
              ),
              SizedBox(height: TvSourcePickerLayout.headerGap * scale),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.titleFontSize * scale,
                fontWeight: FontWeight.w600,
                color: tk.text,
              ),
            ),
            SizedBox(height: TvCatalogLayout.cardFooterLineGap * scale * 2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
              TvPanelButton(
                scale: scale,
                label: actionLabel!,
                onPressed: onAction!,
                primary: true,
                autofocus: true,
                focusNode: onActionFocusNode,
                onNavigateLeft: onActionNavigateLeft,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
