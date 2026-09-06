/// What "Home aanpassen" does, kept out of the feed that offers it (ROW1,
/// [DEC-100](../../../docs/DECISIONS.md#dec-100)).
///
/// [TvContentFeed] draws Home. This assembles the customise panel's row list,
/// turns its four actions into provider writes, and runs the new-row wizard.
/// None of that is drawing, all of it needs five providers, and the feed was
/// already past the size at which one more responsibility stops being findable.
///
/// ## The order it writes back is every id, not one per row
///
/// A merged row answers to each of its contributors in `HomeLayoutProvider`'s
/// space (see `home_row_layout.dart`). Writing only the first would leave the
/// others ranked wherever they happened to be, so a merge could travel past a
/// row it should have stopped beside. Writing all of them, adjacent, keeps a
/// row's rank exactly its position — and keeps the list interoperable with the
/// settings screen, which writes the same legacy ids one per backend hub.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/home_custom_rows_provider.dart';
import '../../providers/home_layout_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/tv_home_projection_provider.dart';
import '../../services/unified_catalog/home_custom_row.dart';
import '../../services/unified_catalog/home_custom_row_loader.dart';
import '../../services/unified_catalog/home_row_layout.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../utils/home_custom_row_labels.dart';
import 'tv_home_customize_panel.dart';
import 'tv_home_row_assembly.dart';
import 'tv_home_row_wizard.dart';

/// Opens "Home aanpassen" over the page [context] belongs to. Both entries
/// A1a and A1b end here.
Future<void> openTvHomeCustomizePanel(
  BuildContext context, {
  MediaServerClient? Function(String serverId)? clientFor,
}) async {
  final controller = TvHomeCustomizeController.maybeOf(context, clientFor: clientFor);
  if (controller == null) return;
  await showTvHomeCustomizePanel(
    context,
    listenable: Listenable.merge([controller.layout, controller.customRows]),
    fixedRows: controller.fixedRows,
    entries: controller.entries,
    clientFor: clientFor,
    onMove: (index, delta) => unawaited(controller.move(index, delta)),
    onToggleHidden: (entry) => unawaited(controller.toggleHidden(entry)),
    onRemove: (row) => unawaited(controller.remove(row)),
    onEdit: (row) => unawaited(controller.runWizard(context, initial: row)),
    onNewRow: () async => await controller.runWizard(context) != null,
  );
}

class TvHomeCustomizeController {
  const TvHomeCustomizeController({
    required this.layout,
    required this.customRows,
    required this.projection,
    required this.librariesFor,
    required this.preview,
    this.clientFor,
  });

  final HomeLayoutProvider layout;
  final HomeCustomRowsProvider customRows;
  final TvHomeProjectionProvider projection;
  final List<CatalogLibrary> Function(MediaKind kind) librariesFor;
  final Future<HomeCustomRowContent> Function(HomeCustomRow draft) preview;
  final MediaServerClient? Function(String serverId)? clientFor;

  /// Built per opening rather than held: this is a view over five providers,
  /// and one kept across a profile switch would be a view over the wrong ones.
  ///
  /// Null when Home's own two providers are not in scope, which is the case on
  /// every surface that is not inside a profile session.
  static TvHomeCustomizeController? maybeOf(
    BuildContext context, {
    MediaServerClient? Function(String serverId)? clientFor,
  }) {
    final layout = context.read<HomeLayoutProvider?>();
    final customRows = context.read<HomeCustomRowsProvider?>();
    if (layout == null || customRows == null) return null;
    final multiServer = context.read<MultiServerProvider>();
    final libraries = context.read<LibrariesProvider>();
    final hiddenLibraries = context.read<HiddenLibrariesProvider>();
    final loader = CatalogHomeCustomRowLoader(
      libraries: () => libraries.libraries,
      isServerVisible: multiServer.serverManager.isServerVisible,
      hiddenLibraryKeys: () => hiddenLibraries.hiddenLibraryKeys,
      clientFor: multiServer.serverManager.getClient,
    );
    return TvHomeCustomizeController(
      layout: layout,
      customRows: customRows,
      projection: context.read<TvHomeProjectionProvider>(),
      clientFor: clientFor,
      librariesFor: (kind) => eligibleCatalogLibraries(
        libraries: libraries.libraries,
        kind: kind,
        isServerVisible: multiServer.serverManager.isServerVisible,
        hiddenLibraryKeys: hiddenLibraries.hiddenLibraryKeys,
      ),
      // The wizard's preview is the row's own question, asked early. Same
      // loader, same limit, so what C3 draws is what Home will draw.
      preview: (draft) => loader.load(draft, limit: kHomeCustomRowCardLimit),
    );
  }

  /// Every row the panel lists, in display order, hidden and empty ones
  /// included.
  ///
  /// Deliberately not the feed's own list. Home drops a hidden row and an empty
  /// own row, and the panel is the one place both have to be reachable: a row
  /// you cannot see is a row you cannot un-hide, and DEC-100 (6) says an own
  /// row that has gone empty "blijft in het paneel staan met 'leeg' als
  /// subregel".
  List<UnifiedMediaHub> orderedRows() => tvHomeOrderableRows(
    projection: projection,
    layout: layout,
    customRows: customRows,
    includeHidden: true,
    includeEmpty: true,
  );

  List<TvHomeRowEntry> entries() => [
    for (final row in orderedRows())
      TvHomeRowEntry(
        row: row,
        layoutIds: homeLayoutIdsOf(row),
        isHidden: homeLayoutIdsOf(row).every(layout.isRowHidden),
        custom: _customRowFor(row),
        subtitle: _subtitleFor(row),
      ),
  ];

  /// Uitgelicht and Verder kijken, drawn locked at the top of the panel.
  ///
  /// Uitgelicht has no row of its own on Home — it is the billboard — so its
  /// posters come from the hero pool. Showing it at all is the point: "why can
  /// I not move the top of my Home" is a question the panel should answer
  /// without being asked.
  List<TvHomeFixedRow> fixedRows() => [
    TvHomeFixedRow(
      title: t.unifiedCatalog.homeRows.featured,
      subtitle: t.unifiedCatalog.homeRows.alwaysFirst,
      groups: projection.heroGroups,
    ),
    if (projection.continueWatching case final cw?)
      TvHomeFixedRow(title: cw.title, subtitle: t.unifiedCatalog.homeRows.alwaysSecond, groups: cw.groups),
  ];

  HomeCustomRow? _customRowFor(UnifiedMediaHub row) {
    for (final custom in layout.customRows) {
      if (UnifiedMediaHub.synthesizedHubId(custom.hubSlug) == row.hubId) return custom;
    }
    return null;
  }

  /// The second tier of a panel row: what an own row is made of, or which
  /// servers a backend row came from.
  String? _subtitleFor(UnifiedMediaHub row) {
    final custom = _customRowFor(row);
    if (custom == null) {
      return row.isServerSpecific ? row.serverName : t.unifiedCatalog.homeRows.pleyaRow;
    }
    final content = customRows.contentFor(custom.id);
    return [
      t.unifiedCatalog.homeRows.ownRow,
      custom.kind == MediaKind.movie ? t.unifiedCatalog.moviesTitle : t.unifiedCatalog.seriesTitle,
      ...homeCustomRowFilterParts(custom),
      if (content != null && content.isEmpty)
        t.unifiedCatalog.homeRows.emptyNote
      else
        ?homeCustomRowCountLabel(content),
    ].join(' · ');
  }

  Future<void> move(int index, int delta) async {
    final rows = orderedRows();
    final target = index + delta;
    if (index < 0 || index >= rows.length || target < 0 || target >= rows.length) return;
    final reordered = List.of(rows);
    reordered.insert(target, reordered.removeAt(index));
    await layout.setOrder([for (final row in reordered) ...homeLayoutIdsOf(row)]);
  }

  /// Hides or shows every id the row answers to.
  ///
  /// Both halves in one go, because `home_row_layout.dart` only drops a row
  /// when *all* of its contributors are hidden: hiding one of a merged row's
  /// two would leave the row on screen and the button saying "Show".
  Future<void> toggleHidden(TvHomeRowEntry entry) async {
    final hide = !entry.isHidden;
    for (final id in entry.layoutIds) {
      await layout.setRowHidden(id, hide);
    }
  }

  Future<void> remove(HomeCustomRow row) => layout.removeCustomRow(row.id);

  /// Runs the wizard and saves what it returns.
  ///
  /// Returns the saved row so the caller can put the focus on it, which DEC-100
  /// (5) asks for on a new row: "het paneel sluit op Home met de focus op de
  /// eerste kaart van de nieuwe rij".
  Future<HomeCustomRow?> runWizard(BuildContext context, {HomeCustomRow? initial}) async {
    final row = await showTvHomeRowWizard(
      context,
      initial: initial,
      librariesFor: librariesFor,
      preview: preview,
      clientFor: clientFor,
    );
    if (row == null) return null;
    await layout.saveCustomRow(row);
    // An edit keeps the row's id, so nothing in the layout changed and the
    // content provider's own change detection is what reloads it. A brand new
    // row is loaded by the same path; this is here for the case the provider
    // has already seen this id — a re-save of an unchanged row — where nothing
    // would otherwise re-ask.
    await customRows.refreshRow(row.id);
    return row;
  }
}
