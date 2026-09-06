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
    this.actionLabel,
    this.onAction,
    this.onActionNavigateLeft,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// LEFT off the one action these states have.
  ///
  /// It is the *only* way into CAT5's rail on a page with no grid: the rail
  /// opens on LEFT from column 0, and a filtered-empty catalog has no column 0.
  /// Without this, the state that most needs the filter controls — "nothing
  /// matches these filters" — is the one state that cannot reach them.
  final VoidCallback? onActionNavigateLeft;

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
                onNavigateLeft: onActionNavigateLeft,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
