/// What "Home aanpassen" does to the stored layout on iPhone, iPad and Mac, kept
/// out of the widgets that offer it (HOME-R1).
///
/// The list it works on is `homeLayoutEntries`, the same rows Home draws. The
/// writes are the providers' own (`setOrder` with every id, `setRowHidden` for
/// every id of a row, `saveCustomRow`, `removeCustomRow`); this class only
/// turns a gesture into them. A second storage path would be a second system.
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../providers/discover_provider.dart';
import '../../../providers/home_custom_rows_provider.dart';
import '../../../providers/home_extra_rows_provider.dart';
import '../../../providers/home_layout_provider.dart';
import '../../../providers/tv_home_projection_provider.dart';
import '../../../services/unified_catalog/home_custom_row.dart';
import '../../../services/unified_catalog/home_layout_entries.dart';
import '../../../utils/platform_detector.dart';

class HomeRowActions {
  HomeRowActions({
    required this.layout,
    required this.unified,
    this.customRows,
    this.extraRows,
    this.projection,
    this.backendHubsOf,
  });

  final HomeLayoutProvider layout;
  final HomeCustomRowsProvider? customRows;
  final HomeExtraRowsProvider? extraRows;
  final TvHomeProjectionProvider? projection;

  /// iPhone draws unified rows, iPad and Mac one row per server hub (DEC-103,
  /// DEC-145). The edit list has to be the one Home draws.
  final bool unified;

  final DiscoverProvider? Function()? backendHubsOf;

  /// Reads the providers once, without subscribing: the caller that wants to
  /// rebuild watches them itself.
  static HomeRowActions of(BuildContext context) => HomeRowActions(
    layout: context.read<HomeLayoutProvider>(),
    customRows: context.read<HomeCustomRowsProvider?>(),
    extraRows: context.read<HomeExtraRowsProvider?>(),
    projection: context.read<TvHomeProjectionProvider?>(),
    unified: context.read<TvHomeProjectionProvider?>() != null && PlatformDetector.isPhone(context),
    backendHubsOf: () => context.read<DiscoverProvider?>(),
  );

  List<HomeLayoutEntry> entries() => homeLayoutEntries(
    layout: layout,
    customRows: customRows,
    extraRows: extraRows,
    projection: unified ? projection : null,
    backendHubs: unified ? const [] : (backendHubsOf?.call()?.hubs ?? const []),
  );

  bool isHidden(HomeLayoutEntry entry) => entry.ids.every(layout.isRowHidden);

  /// Index of the entry that answers to exactly [ids], or -1.
  int indexOfIds(List<HomeLayoutEntry> entries, List<String> ids) {
    for (var i = 0; i < entries.length; i++) {
      if (_sameIds(entries[i].ids, ids)) return i;
    }
    return -1;
  }

  /// The nearest row in [direction] that Home actually draws, so one press
  /// moves a row past something the viewer can see instead of past a hidden
  /// row and looks like nothing happened. -1 when there is none.
  int neighbourIndex(List<HomeLayoutEntry> entries, int index, int direction) {
    for (var i = index + direction; i >= 0 && i < entries.length; i += direction) {
      if (!isHidden(entries[i])) return i;
    }
    return -1;
  }

  /// Moves one row to the nearest drawn neighbour in [direction] (-1 or 1).
  Future<void> moveStep(List<HomeLayoutEntry> entries, int index, int direction) async {
    final target = neighbourIndex(entries, index, direction);
    if (target < 0) return;
    final next = homeLayoutEntriesAfterReorder(entries, index, target, previous: layout.order);
    if (next != null) await layout.setOrder(next);
  }

  /// Drag and drop: [to] is the index `onReorderItem` reports.
  Future<void> reorder(List<HomeLayoutEntry> entries, int from, int to) async {
    final next = homeLayoutEntriesAfterReorder(entries, from, to, previous: layout.order);
    if (next != null) await layout.setOrder(next);
  }

  /// Every id the row answers to: `home_row_layout.dart` only drops a row when
  /// all of its contributors are hidden, so hiding one of a merged row's two
  /// would leave it on Home while the switch says it is gone.
  Future<void> setHidden(HomeLayoutEntry entry, bool hidden) async {
    for (final id in entry.ids) {
      await layout.setRowHidden(id, hidden);
    }
  }

  Future<void> remove(HomeLayoutEntry entry) async {
    final id = entry.customRowId;
    if (id != null) await layout.removeCustomRow(id);
  }

  HomeCustomRow? customRowOf(HomeLayoutEntry entry) {
    final id = entry.customRowId;
    return id == null ? null : layout.customRowById(id);
  }

  /// Saves what the wizard returned, and asks the row's content again: an edit
  /// keeps its id, so nothing else would re-ask.
  Future<void> save(HomeCustomRow row) async {
    await layout.saveCustomRow(row);
    await customRows?.refreshRow(row.id);
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
