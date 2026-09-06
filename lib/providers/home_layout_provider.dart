import 'dart:async';

import 'package:flutter/foundation.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../media/media_hub.dart';
import '../services/preferences/preference_refresh.dart';
import '../services/storage_service.dart';
import '../services/unified_catalog/home_custom_row.dart';

/// Stable identity of a home row: server-scoped, prefers the backend's
/// human-readable identifier ('home.continue', 'tv.recentlyadded') over the
/// opaque id. Rows sharing an identity (e.g. several "Because you watched"
/// rows) are treated as one block.
String homeRowId(MediaHub hub) => '${hub.serverId ?? ''}:${hub.identifier ?? hub.id}';

/// User-defined layout of the home screen rows: which rows are hidden, in what
/// order they appear, and which of them the viewer defined themselves. Hero and
/// Continue Watching are not part of this — they are fixed slivers in
/// DiscoverScreen.
///
/// Rows are identified by their hub identity (`'serverId:identifier'`), see
/// `DiscoverScreen._hubIdentity`. A row the viewer defined (ROW1/DEC-100) has
/// no hub, so it carries an id of its own in the same space; see
/// [HomeCustomRow.layoutRowId] for why it cannot collide with one.
class HomeLayoutProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  StorageService? _storageService;
  final String? profileId;
  Set<String> _hidden = {};
  List<String> _order = [];
  List<HomeCustomRow> _customRows = [];
  bool _isInitialized = false;
  Future<void>? _initFuture;

  HomeLayoutProvider({StorageService? storageService, this.profileId, PreferenceRefreshBus? refreshBus}) {
    _storageService = storageService;
    _initFuture = _initialize();
    _refreshSub = (refreshBus ?? PreferenceRefreshBus.instance).changes.listen((families) {
      if (families.contains(PreferenceRefreshFamily.homeLayout)) unawaited(refresh());
    });
  }

  StreamSubscription<Set<PreferenceRefreshFamily>>? _refreshSub;

  /// Re-read the layout from storage.
  ///
  /// Separate from [_initialize] because that one returns early once
  /// `_isInitialized` is set, which is right for the constructor race it
  /// guards and wrong for every later reload: an import, a reset or a remote
  /// apply left new values in storage that this provider would never read.
  Future<void> refresh() async {
    final storage = _storageService ??= await StorageService.getInstance();
    _hidden = storage.getHiddenHomeRows(profileId);
    _order = storage.getHomeRowOrder(profileId);
    _customRows = _readCustomRows(storage);
    _isInitialized = true;
    safeNotifyListeners();
  }

  @override
  void dispose() {
    unawaited(_refreshSub?.cancel());
    _refreshSub = null;
    super.dispose();
  }

  Future<void> ensureInitialized() => _initFuture ?? _initialize();

  bool get isInitialized => _isInitialized;

  List<String> get order => List.unmodifiable(_order);
  Set<String> get hiddenRowIds => Set.unmodifiable(_hidden);

  /// The rows this profile defined itself, in creation order. Where they land
  /// on Home is [order]'s business, not this list's.
  List<HomeCustomRow> get customRows => List.unmodifiable(_customRows);

  HomeCustomRow? customRowById(String id) {
    for (final row in _customRows) {
      if (row.id == id) return row;
    }
    return null;
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;
    final storage = _storageService ??= await StorageService.getInstance();
    _hidden = storage.getHiddenHomeRows(profileId);
    _order = storage.getHomeRowOrder(profileId);
    _customRows = _readCustomRows(storage);
    _isInitialized = true;
    safeNotifyListeners();
  }

  /// Unreadable entries are dropped rather than repaired; see
  /// [HomeCustomRow.fromJson].
  List<HomeCustomRow> _readCustomRows(StorageService storage) => [
    for (final stored in storage.getHomeCustomRows(profileId)) ?HomeCustomRow.decode(stored),
  ];

  bool isRowHidden(String rowId) => _hidden.contains(rowId);

  Future<void> setRowHidden(String rowId, bool hidden) async {
    if (!_isInitialized) await _initialize();
    if (_hidden.contains(rowId) == hidden) return;
    _hidden = hidden ? (Set.from(_hidden)..add(rowId)) : (Set.from(_hidden)..remove(rowId));
    final storage = _storageService ??= await StorageService.getInstance();
    await storage.saveHiddenHomeRows(profileId, _hidden);
    safeNotifyListeners();
  }

  /// Adds [row], or replaces the one with the same id.
  ///
  /// New rows go to the front of the stored list, which is where a Home with no
  /// stored order draws them: directly under the fixed rows, as DEC-100 (5)
  /// asks.
  ///
  /// A stored order overrules that position, and used to overrule it wrongly
  /// (ROW1g). `applyHomeLayoutToUnifiedRows` ranks an id the order has never
  /// seen as `order.length`, which is last, and the panel's own `move` writes
  /// every id at the first reorder. So a viewer who had ever moved a row got
  /// the next new one at the bottom of Home, while the string next to the
  /// button said it would land directly under Verder kijken. A new row
  /// therefore claims the front of the order as well, and only a genuinely new
  /// one: an edit keeps its id and must keep its place.
  Future<void> saveCustomRow(HomeCustomRow row) async {
    if (!_isInitialized) await _initialize();
    final existing = _customRows.indexWhere((r) => r.id == row.id);
    final next = List.of(_customRows);
    if (existing >= 0) {
      if (next[existing] == row) return;
      next[existing] = row;
    } else {
      next.insert(0, row);
    }
    _customRows = next;
    await _persistCustomRows();
    // Only when there is an order to join. Writing one here where none existed
    // would turn "the viewer has never reordered" into "they have", which is
    // the flag the projection order still answers to.
    final rowId = row.layoutRowId;
    if (existing < 0 && _order.isNotEmpty && !_order.contains(rowId)) {
      await setOrder([rowId, ..._order]);
      return;
    }
    safeNotifyListeners();
  }

  /// Removes the row and every preference that named it.
  ///
  /// Leaving its id behind in [hiddenRowIds] or [order] would be an invisible
  /// preference: nothing on screen can clear it, and a later row that happened
  /// to reuse the id would inherit a hidden state nobody chose. The id is
  /// time-based so that reuse is not realistic, which is a reason not to rely
  /// on it rather than a reason to skip the cleanup.
  Future<void> removeCustomRow(String id) async {
    if (!_isInitialized) await _initialize();
    if (!_customRows.any((r) => r.id == id)) return;
    final rowId = HomeCustomRow.layoutRowIdFor(id);
    _customRows = [
      for (final row in _customRows)
        if (row.id != id) row,
    ];
    await _persistCustomRows();
    if (_hidden.remove(rowId)) {
      final storage = _storageService ??= await StorageService.getInstance();
      await storage.saveHiddenHomeRows(profileId, _hidden);
    }
    if (_order.contains(rowId)) {
      _order = [
        for (final id in _order)
          if (id != rowId) id,
      ];
      final storage = _storageService ??= await StorageService.getInstance();
      await storage.saveHomeRowOrder(profileId, _order);
    }
    safeNotifyListeners();
  }

  Future<void> _persistCustomRows() async {
    final storage = _storageService ??= await StorageService.getInstance();
    await storage.saveHomeCustomRows(profileId, [for (final row in _customRows) row.encode()]);
  }

  Future<void> setOrder(List<String> rowIds) async {
    if (!_isInitialized) await _initialize();
    _order = List.of(rowIds);
    final storage = _storageService ??= await StorageService.getInstance();
    await storage.saveHomeRowOrder(profileId, _order);
    safeNotifyListeners();
  }

  /// Apply the layout to [rows]: drop hidden rows, then sort by the stored
  /// order. Rows absent from the stored order keep their incoming relative
  /// order and land at the end, so newly appearing hubs show up automatically.
  ///
  /// Pass [dropHidden] `false` to only reorder — used by the settings screen,
  /// which must still list the rows the user switched off.
  List<T> apply<T>(List<T> rows, String Function(T) idOf, {bool dropHidden = true}) {
    if ((_hidden.isEmpty || !dropHidden) && _order.isEmpty) return rows;
    final visible = (_hidden.isEmpty || !dropHidden)
        ? List.of(rows)
        : rows.where((r) => !_hidden.contains(idOf(r))).toList();
    if (_order.isEmpty) return visible;
    final rank = {for (var i = 0; i < _order.length; i++) _order[i]: i};
    final indexed = [for (var i = 0; i < visible.length; i++) (visible[i], rank[idOf(visible[i])] ?? _order.length, i)];
    indexed.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3));
    return [for (final e in indexed) e.$1];
  }
}
