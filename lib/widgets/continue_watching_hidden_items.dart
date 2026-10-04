/// "Verborgen items" (mockup 38 D / 23, DEC-119 fase 3): the titles hidden from
/// Verder kijken on this device, each one press away from being put back.
///
/// One list on every platform. Choosing an entry restores it and closes the
/// list. The Home row and the projection-fed overviews (iPhone, TV) pick the
/// title up again on the refetch the restore triggers; a screen holding its own
/// copy of the list (the desktop detail) reloads after this returns.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../providers/continue_watching_hidden_provider.dart';
import '../theme/mono_tokens.dart';
import '../utils/layout_constants.dart';
import '../utils/platform_detector.dart';
import 'app_menu.dart';
import 'overlay_sheet.dart';
import 'overlay_sheet_geometry.dart';
import 'tv/tv_catalog_sort_panel.dart';
import 'tv/tv_panel_primitives.dart';
import 'tv/tv_unified_layout.dart';

/// `Verborgen items · 2`, the label every entry point shares.
String continueWatchingHiddenLabel(int count) => '${t.discover.hiddenItems} · $count';

Future<void> showContinueWatchingHiddenItems(BuildContext context) async {
  final hidden = context.read<ContinueWatchingHiddenProvider>();
  final entries = hidden.entries;
  if (entries.isEmpty) return;

  final String? chosen;
  if (PlatformDetector.isTV()) {
    chosen = await OverlaySheetController.showAdaptive<String>(
      context,
      presentation: OverlaySheetPresentation.panel,
      restoreLauncherFocus: true,
      builder: (sheetContext) => _TvHiddenPanel(
        entries: entries,
        onChoose: (key) => OverlaySheetController.closeAdaptive(sheetContext, key),
        onClose: () => OverlaySheetController.closeAdaptive(sheetContext, null),
      ),
    );
  } else {
    chosen = await OverlaySheetController.showAdaptive<String>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => AppMenuSheet<String>(
        title: t.discover.hiddenItems,
        entries: [
          for (final entry in entries)
            AppMenuItem<String>(
              value: entry.globalKey,
              icon: Symbols.visibility_rounded,
              label: entry.title,
              subtitle: [?entry.subtitle, t.discover.restoreHidden].join(' · '),
            ),
        ],
      ),
    );
  }
  if (chosen != null) await hidden.restore(chosen);
}

class _TvHiddenPanel extends StatelessWidget {
  const _TvHiddenPanel({required this.entries, required this.onChoose, required this.onClose});

  final List<HiddenContinueWatchingEntry> entries;
  final ValueChanged<String> onChoose;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final mono = tokens(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.discover.hiddenItems,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.titleFontSize * scale,
                fontWeight: FontWeight.w600,
                color: mono.text.withValues(alpha: TvSourcePickerLayout.inkPrimary),
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.rowGap * scale),
            Text(
              t.discover.hiddenItemsHint,
              style: TextStyle(fontSize: TvSourcePickerLayout.subtitleFontSize * scale, color: mono.textMuted),
            ),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: entries.length,
                separatorBuilder: (_, _) => SizedBox(height: TvSourcePickerLayout.rowGap * scale),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return TvCatalogOptionRow(
                    key: ValueKey(entry.globalKey),
                    label: [entry.title, ?entry.subtitle].join(' · '),
                    secondary: t.discover.restoreHidden,
                    leadingIcon: Symbols.visibility_rounded,
                    isSelected: false,
                    scale: scale,
                    onPressed: () => onChoose(entry.globalKey),
                  );
                },
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
