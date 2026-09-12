/// The action sheet a library row opens on TV (mockup 27 B, LIB7,
/// [DEC-092](../../../../docs/DECISIONS.md#dec-092)).
///
/// Same panel chrome as [showTvUnifiedContextMenu]'s `_ActionMenuPanel` —
/// [TvCatalogOptionRow], [tvPanelDecoration], [TvPanelButton] — so this is a
/// second consumer of the same option-row language rather than a new one.
/// One visible difference from mockup 27 B: that row widget draws no leading
/// icon and no inline trailing tag, so a backend-gated action's context
/// ("Plex") and "met deze bron als filter" both land as [TvCatalogOptionRow]'s
/// existing second line instead of beside the label.
library;

import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_library.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/layout_constants.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/overlay_sheet_geometry.dart';
import '../../../widgets/tv/tv_catalog_sort_panel.dart';
import '../../../widgets/tv/tv_panel_primitives.dart';
import '../../../widgets/tv/tv_unified_layout.dart';
import 'tv_libraries_screen.dart';

String _labelFor(TvLibraryAction action, MediaLibrary library, {required bool isHidden}) => switch (action) {
  TvLibraryAction.openInCatalog =>
    library.kind == MediaKind.show ? t.libraries.openInAllSeries : t.libraries.openInAllMovies,
  TvLibraryAction.refreshMetadata => t.libraries.refreshMetadata,
  TvLibraryAction.scan => t.libraries.scanLibraryFiles,
  TvLibraryAction.toggleVisibility => isHidden ? t.libraries.showLibrary : t.libraries.hideLibrary,
  TvLibraryAction.analyze => t.libraries.analyze,
  TvLibraryAction.emptyTrash => t.libraries.emptyTrash,
};

String? _secondaryFor(TvLibraryAction action) => switch (action) {
  TvLibraryAction.openInCatalog => t.libraries.openInCatalogSubtitle,
  _ => null,
};

/// Opens the sheet for [library]. Each `on*` callback fires after the sheet
/// has closed — none of them run while the panel is still on screen, the same
/// separation [showTvUnifiedContextMenu] keeps between choosing and doing.
Future<void> showTvLibraryActionSheet(
  BuildContext context, {
  required MediaLibrary library,
  required bool isHidden,
  required VoidCallback onOpenInCatalog,
  required VoidCallback onRefreshMetadata,
  required VoidCallback onScan,
  required VoidCallback onToggleVisibility,
  required VoidCallback onAnalyze,
  required VoidCallback onEmptyTrash,
}) async {
  final actions = tvLibraryActionsFor(library);
  if (actions.isEmpty) return;

  final chosen = await OverlaySheetController.showAdaptive<TvLibraryAction>(
    context,
    presentation: OverlaySheetPresentation.panel,
    restoreLauncherFocus: true,
    builder: (sheetContext) => _TvLibraryActionPanel(
      library: library,
      actions: actions,
      isHidden: isHidden,
      onChoose: (action) => OverlaySheetController.closeAdaptive(sheetContext, action),
      onClose: () => OverlaySheetController.closeAdaptive(sheetContext, null),
    ),
  );

  switch (chosen) {
    case TvLibraryAction.openInCatalog:
      onOpenInCatalog();
    case TvLibraryAction.refreshMetadata:
      onRefreshMetadata();
    case TvLibraryAction.scan:
      onScan();
    case TvLibraryAction.toggleVisibility:
      onToggleVisibility();
    case TvLibraryAction.analyze:
      onAnalyze();
    case TvLibraryAction.emptyTrash:
      onEmptyTrash();
    case null:
      break;
  }
}

class _TvLibraryActionPanel extends StatelessWidget {
  const _TvLibraryActionPanel({
    required this.library,
    required this.actions,
    required this.isHidden,
    required this.onChoose,
    required this.onClose,
  });

  final MediaLibrary library;
  final List<TvLibraryAction> actions;
  final bool isHidden;
  final ValueChanged<TvLibraryAction> onChoose;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final mono = tokens(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

    // The divider mockup 27 B draws before "Verbergen op dit profiel": every
    // action up to and including the visibility toggle sits above it, the
    // Plex-only admin actions below.
    final dividerIndex = actions.indexOf(TvLibraryAction.toggleVisibility) + 1;

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              library.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.titleFontSize * scale,
                fontWeight: FontWeight.w600,
                color: mono.text.withValues(alpha: TvSourcePickerLayout.inkPrimary),
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: actions.length,
                separatorBuilder: (_, index) {
                  if (index + 1 != dividerIndex || dividerIndex >= actions.length) {
                    return SizedBox(height: TvSourcePickerLayout.rowGap * scale);
                  }
                  return Container(
                    margin: EdgeInsets.symmetric(vertical: TvSourcePickerLayout.rowGap * scale),
                    height: 1,
                    color: mono.outline,
                  );
                },
                itemBuilder: (context, index) => TvCatalogOptionRow(
                  key: ValueKey(actions[index]),
                  label: _labelFor(actions[index], library, isHidden: isHidden),
                  secondary: _secondaryFor(actions[index]),
                  isSelected: false,
                  scale: scale,
                  onPressed: () => onChoose(actions[index]),
                ),
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.footerGap * scale),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [TvPanelButton(scale: scale, label: t.common.close, onPressed: onClose, primary: false)],
            ),
          ],
        ),
      ),
    );
  }
}
