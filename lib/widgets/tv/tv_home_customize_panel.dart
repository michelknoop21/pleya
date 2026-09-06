/// "Home aanpassen": one panel over the dimmed Home in which every row can be
/// moved, hidden, edited or removed (ROW1, mockup 32 B,
/// [DEC-100](../../../docs/DECISIONS.md#dec-100) (4)).
///
/// ## Why moving is two buttons and not a lift
///
/// A drag handle is unreachable on a remote, and the obvious substitute — a
/// "lifted" row that the D-pad then carries — has no visible resting place: the
/// viewer has to remember they are in a mode. A focused button is always
/// findable and always says what it does, so a move is one press per step and
/// the row travels under the ring. The settings screen made the same call for
/// the same reason, three years earlier, and this is the TV-native form of it.
///
/// ## A disabled arrow keeps its focus stop
///
/// Up on the first movable row and down on the last do nothing, and they are
/// still focusable. Removing them would shorten those rows by a column, so
/// walking down the panel with the ring on "hide" would shunt sideways every
/// time it passed the last row. A stop that plainly does nothing costs one
/// press; a column that moves under the viewer costs the whole mental model.
///
/// ## The fixed rows are in the list and out of the traversal
///
/// Uitgelicht and Verder kijken are drawn at the top with a lock, because their
/// being fixed is a fact about Home the viewer should be able to see rather than
/// discover by trying. They are not focusable, so DOWN from the header lands on
/// the first row that can actually take an action.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_hub.dart';
import '../../services/unified_catalog/home_custom_row.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../overlay_sheet.dart';
import '../overlay_sheet_geometry.dart';
import 'tv_home_row_tiles.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

/// Finds the open panel. Public so a test can say *which* surface it is
/// looking at rather than that something modal is up.
const Key tvHomeCustomizePanelKey = ValueKey('tvHomeCustomizePanel');

/// One movable row, as the panel needs it.
class TvHomeRowEntry {
  const TvHomeRowEntry({
    required this.row,
    required this.layoutIds,
    required this.isHidden,
    this.custom,
    this.subtitle,
  });

  final UnifiedMediaHub row;

  /// Every name this row answers to in `HomeLayoutProvider`'s space. A merged
  /// row carries all of its contributors, so writing the order back keeps them
  /// adjacent and the row's rank exact.
  final List<String> layoutIds;

  final bool isHidden;

  /// Non-null when the viewer defined this row, which is what decides whether
  /// it offers Edit and Remove or Hide.
  final HomeCustomRow? custom;

  /// The second tier: the filter and the count for an own row, the servers for
  /// a backend one.
  final String? subtitle;

  bool get isCustom => custom != null;
}

/// A row that is drawn and cannot be touched: Uitgelicht, Verder kijken.
class TvHomeFixedRow {
  const TvHomeFixedRow({required this.title, required this.subtitle, required this.groups});

  final String title;
  final String subtitle;
  final List<UnifiedMediaGroup> groups;
}

/// Opens the panel. Returns when it closes; every change it makes has already
/// been written by then, since DEC-100 (4) gives it no save step.
///
/// The rows arrive as builders behind a [Listenable] rather than as a list.
/// There is no save step, so a move, a hide and a delete all land in the
/// providers while the panel is up, and a snapshot taken at open would leave
/// the viewer looking at the list they had before their first press.
Future<void> showTvHomeCustomizePanel(
  BuildContext context, {
  required Listenable listenable,
  required List<TvHomeFixedRow> Function() fixedRows,
  required List<TvHomeRowEntry> Function() entries,
  required void Function(int index, int delta) onMove,
  required void Function(TvHomeRowEntry entry) onToggleHidden,
  required void Function(HomeCustomRow row) onEdit,
  required void Function(HomeCustomRow row) onRemove,
  required Future<bool> Function() onNewRow,
  MediaServerClient? Function(String serverId)? clientFor,
}) {
  final initialFocusNode = FocusNode(debugLabel: 'TvHomeCustomizeInitialFocus');
  return OverlaySheetController.showAdaptive<void>(
    context,
    presentation: OverlaySheetPresentation.panel,
    constraints: tvWidePanelConstraints(MediaQuery.sizeOf(context)),
    initialFocusNode: initialFocusNode,
    restoreLauncherFocus: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => TvHomeCustomizePanel(
        key: tvHomeCustomizePanelKey,
        fixedRows: fixedRows(),
        entries: entries(),
        initialFocusNode: initialFocusNode,
        clientFor: clientFor,
        onMove: onMove,
        onToggleHidden: onToggleHidden,
        onEdit: onEdit,
        onRemove: onRemove,
        onNewRow: onNewRow,
        onClose: () => OverlaySheetController.closeAdaptive(sheetContext, null),
      ),
    ),
  );
}

class TvHomeCustomizePanel extends StatefulWidget {
  const TvHomeCustomizePanel({
    super.key,
    required this.fixedRows,
    required this.entries,
    required this.onMove,
    required this.onToggleHidden,
    required this.onEdit,
    required this.onRemove,
    required this.onNewRow,
    required this.onClose,
    this.initialFocusNode,
    this.clientFor,
  });

  final List<TvHomeFixedRow> fixedRows;
  final List<TvHomeRowEntry> entries;
  final void Function(int index, int delta) onMove;
  final void Function(TvHomeRowEntry entry) onToggleHidden;
  final void Function(HomeCustomRow row) onEdit;
  final void Function(HomeCustomRow row) onRemove;

  /// Runs the wizard and answers whether a row was actually added, because
  /// DEC-100 (5) closes the panel on Home only in that case — a viewer who
  /// cancelled the wizard is still in the middle of tidying their Home.
  final Future<bool> Function() onNewRow;
  final VoidCallback onClose;
  final FocusNode? initialFocusNode;
  final MediaServerClient? Function(String serverId)? clientFor;

  @override
  State<TvHomeCustomizePanel> createState() => _TvHomeCustomizePanelState();
}

/// Column identity, shared by every row so UP and DOWN can hold it.
///
/// A hub row has three columns and an own row four; a step onto a shorter row
/// clamps to its last column and a step back finds the same one again, because
/// the meaning of a column is its index and not its label.
enum TvHomeRowColumn { up, down, primary, remove }

class _TvHomeCustomizePanelState extends State<TvHomeCustomizePanel> {
  /// One node per (row, column), kept for the panel's life and addressed by the
  /// row's *layout id* rather than by its index: a move renumbers the list, and
  /// index-keyed nodes would hand the ring to whichever row slid into the slot.
  final Map<String, FocusNode> _nodes = {};
  FocusNode? _doneNode;
  FocusNode? _newRowNode;

  /// Where the ring should be after a move, so the button the viewer pressed
  /// travels with its row instead of staying on the row that took its place.
  String? _pendingFocusKey;

  /// Not a row key: `_key` always carries a layout id, so nothing can collide
  /// with this.
  static const String _newRowFocusKey = '#newRow';

  /// The `_nodes` key that ended up holding the host's node, if a row took it.
  String? _borrowedKey;

  /// Nieuwe rij took it instead, which is what happens when there is no row to
  /// give it to.
  bool _newRowBorrowedInitial = false;

  @override
  void dispose() {
    for (final entry in _nodes.entries) {
      if (entry.key != _borrowedKey) entry.value.dispose();
    }
    _doneNode?.dispose();
    if (!_newRowBorrowedInitial) _newRowNode?.dispose();
    // Exactly once, whoever ended up holding it, and also when nobody did
    // (ROW1l). The host creates this node and hands it over; `_nodes` used to
    // be the only thing that ever disposed it, so a panel with no movable rows
    // never adopted it and it was simply dropped. Same ownership as
    // `tv_catalog_sort_panel`.
    widget.initialFocusNode?.dispose();
    super.dispose();
  }

  String _key(String layoutId, TvHomeRowColumn column) => '$layoutId#${column.name}';

  /// The control the panel opens on: the first movable row's own up arrow.
  ///
  /// Null when there is no such row, and then Nieuwe rij takes the node
  /// instead. Stated rather than "whichever key asks first" (ROW1m): that rule
  /// was only ever answered from `_entryRow`, so a profile with nothing movable
  /// left the node unattached, the overlay fell through to its first descendant
  /// and the ring opened on Klaar. One Select and the panel the viewer had just
  /// opened was gone again.
  String? get _initialRowKey =>
      widget.entries.isEmpty ? null : _key(widget.entries.first.layoutIds.first, TvHomeRowColumn.up);

  bool get _initialTaken => _borrowedKey != null || _newRowBorrowedInitial;

  FocusNode _nodeFor(String layoutId, TvHomeRowColumn column) {
    final key = _key(layoutId, column);
    final initial = widget.initialFocusNode;
    if (initial != null && !_initialTaken && key == _initialRowKey) {
      _borrowedKey = key;
      return _nodes[key] = initial;
    }
    return _nodes.putIfAbsent(key, () => FocusNode(debugLabel: 'TvHomeCustomize.$key'));
  }

  FocusNode get _done => _doneNode ??= FocusNode(debugLabel: 'TvHomeCustomize.done');

  FocusNode get _newRow {
    final existing = _newRowNode;
    if (existing != null) return existing;
    final initial = widget.initialFocusNode;
    // The entry rows are built before this one, so by now a row has taken the
    // node if there was a row to take it.
    if (initial != null && !_initialTaken && _initialRowKey == null) {
      _newRowBorrowedInitial = true;
      return _newRowNode = initial;
    }
    return _newRowNode = FocusNode(debugLabel: 'TvHomeCustomize.newRow');
  }

  List<TvHomeRowColumn> _columnsOf(TvHomeRowEntry entry) => entry.isCustom
      ? const [TvHomeRowColumn.up, TvHomeRowColumn.down, TvHomeRowColumn.primary, TvHomeRowColumn.remove]
      : const [TvHomeRowColumn.up, TvHomeRowColumn.down, TvHomeRowColumn.primary];

  /// A vertical step that keeps the column, clamped to what the target row has.
  void _step(int fromIndex, TvHomeRowColumn column, int delta) {
    final target = fromIndex + delta;
    if (target < 0) {
      _done.requestFocus();
      return;
    }
    if (target >= widget.entries.length) {
      _newRow.requestFocus();
      return;
    }
    final columns = _columnsOf(widget.entries[target]);
    final wanted = columns.contains(column) ? column : columns.last;
    _nodeFor(widget.entries[target].layoutIds.first, wanted).requestFocus();
  }

  /// Where the ring goes when the row under it is about to disappear (ROW1k).
  ///
  /// The row that slides up into this place, or the one above when there is
  /// nothing below, or Nieuwe rij when the list runs out entirely. Clamped to a
  /// column the target actually has, the same way [_step] is: only an own row
  /// carries Verwijderen, and that is the button being pressed.
  void _remove(int index, HomeCustomRow row) {
    final entries = widget.entries;
    final neighbour = index + 1 < entries.length ? entries[index + 1] : (index > 0 ? entries[index - 1] : null);
    if (neighbour == null) {
      _pendingFocusKey = _newRowFocusKey;
    } else {
      final columns = _columnsOf(neighbour);
      final wanted = columns.contains(TvHomeRowColumn.remove) ? TvHomeRowColumn.remove : columns.last;
      _pendingFocusKey = _key(neighbour.layoutIds.first, wanted);
    }
    widget.onRemove(row);
  }

  void _move(int index, int delta, TvHomeRowColumn column) {
    // The row is about to change places, so remember the control rather than
    // the position: after the rebuild the ring belongs on the same button of
    // the same row, one line further along.
    _pendingFocusKey = _key(widget.entries[index].layoutIds.first, column);
    widget.onMove(index, delta);
  }

  void _restorePendingFocus() {
    final key = _pendingFocusKey;
    if (key == null) return;
    _pendingFocusKey = null;
    if (key == _newRowFocusKey) {
      _newRow.requestFocus();
      return;
    }
    _nodes[key]?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));
    // Runs after the list has been rebuilt in its new order, which is the only
    // moment at which the moved row's node is attached where the viewer expects
    // to find the ring.
    if (_pendingFocusKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restorePendingFocus();
      });
    }

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(mono, scale),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final fixed in widget.fixedRows) ...[
                      TvHomeFixedRowTile(fixed: fixed, scale: scale, clientFor: widget.clientFor),
                      SizedBox(height: TvHomeRowsLayout.rowGap * scale),
                    ],
                    for (var i = 0; i < widget.entries.length; i++) ...[
                      _entryRow(i, scale),
                      SizedBox(height: TvHomeRowsLayout.rowGap * scale),
                    ],
                    TvHomeNewRowTile(
                      scale: scale,
                      focusNode: _newRow,
                      onPressed: () async {
                        if (await widget.onNewRow() && mounted) widget.onClose();
                      },
                      onNavigateUp: () => widget.entries.isEmpty
                          ? _done.requestFocus()
                          : _step(widget.entries.length, TvHomeRowColumn.primary, -1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(MonoTokens mono, double scale) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.unifiedCatalog.homeRows.customize,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.titleFontSize * scale,
                fontWeight: FontWeight.w700,
                color: mono.text,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: TvHomeRowsLayout.titleGap * scale),
            Text(
              t.unifiedCatalog.homeRows.customizeIntro,
              style: TextStyle(fontSize: TvSourcePickerLayout.subtitleFontSize * scale, color: mono.textMuted),
            ),
          ],
        ),
      ),
      // UP from the first row lands here, and Menu does the same thing — see
      // the overlay host, which closes on Back without this button's help.
      TvPanelButton(
        scale: scale,
        label: t.unifiedCatalog.homeRows.done,
        icon: Symbols.check_rounded,
        primary: false,
        focusNode: _done,
        onPressed: widget.onClose,
      ),
    ],
  );

  Widget _entryRow(int index, double scale) {
    final entry = widget.entries[index];
    final id = entry.layoutIds.first;
    final custom = entry.custom;
    return TvHomeEntryRowTile(
      entry: entry,
      scale: scale,
      clientFor: widget.clientFor,
      upNode: _nodeFor(id, TvHomeRowColumn.up),
      downNode: _nodeFor(id, TvHomeRowColumn.down),
      primaryNode: _nodeFor(id, TvHomeRowColumn.primary),
      removeNode: custom == null ? null : _nodeFor(id, TvHomeRowColumn.remove),
      canMoveUp: index > 0,
      canMoveDown: index < widget.entries.length - 1,
      onMoveUp: () => _move(index, -1, TvHomeRowColumn.up),
      onMoveDown: () => _move(index, 1, TvHomeRowColumn.down),
      onPrimary: custom == null ? () => widget.onToggleHidden(entry) : () => widget.onEdit(custom),
      onRemove: custom == null ? null : () => _remove(index, custom),
      onNavigateUp: (column) => _step(index, column, -1),
      onNavigateDown: (column) => _step(index, column, 1),
    );
  }
}
