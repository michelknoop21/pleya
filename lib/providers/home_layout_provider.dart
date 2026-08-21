import 'dart:async';

import 'package:flutter/foundation.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../media/media_hub.dart';
import '../services/preferences/preference_refresh.dart';
import '../services/storage_service.dart';

/// Stable identity of a home row: server-scoped, prefers the backend's
/// human-readable identifier ('home.continue', 'tv.recentlyadded') over the
/// opaque id. Rows sharing an identity (e.g. several "Because you watched"
/// rows) are treated as one block.
String homeRowId(MediaHub hub) => '${hub.serverId ?? ''}:${hub.identifier ?? hub.id}';

/// User-defined layout of the home screen rows: which rows are hidden and in
/// what order they appear. Hero and Continue Watching are not part of this —
/// they are fixed slivers in DiscoverScreen.
///
/// Rows are identified by their hub identity (`'serverId:identifier'`), see
/// `DiscoverScreen._hubIdentity`.
class HomeLayoutProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  StorageService? _storageService;
  final String? profileId;
  Set<String> _hidden = {};
  List<String> _order = [];
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

  Future<void> _initialize() async {
    if (_isInitialized) return;
    final storage = _storageService ??= await StorageService.getInstance();
    _hidden = storage.getHiddenHomeRows(profileId);
    _order = storage.getHomeRowOrder(profileId);
    _isInitialized = true;
    safeNotifyListeners();
  }

  bool isRowHidden(String rowId) => _hidden.contains(rowId);

  Future<void> setRowHidden(String rowId, bool hidden) async {
    if (!_isInitialized) await _initialize();
    if (_hidden.contains(rowId) == hidden) return;
    _hidden = hidden ? (Set.from(_hidden)..add(rowId)) : (Set.from(_hidden)..remove(rowId));
    final storage = _storageService ??= await StorageService.getInstance();
    await storage.saveHiddenHomeRows(profileId, _hidden);
    safeNotifyListeners();
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
