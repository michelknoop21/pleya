/// Content for the rows the viewer defined themselves (ROW1,
/// [DEC-100](../../docs/DECISIONS.md#dec-100)).
///
/// [HomeLayoutProvider] owns *which* rows exist and where they sit; this owns
/// what is in them. Splitting it that way keeps the preference provider free of
/// network work — it is read during startup, by the settings screen and by the
/// remote-apply path, none of which want a merge to start — and keeps the row
/// content in one place that Home, the customise panel and the wizard preview
/// all read the same answer from.
///
/// ## Loading is per row and never blocks the page
///
/// Each row's filter is its own question, answered by its own single-round
/// merge ([HomeCustomRowLoader]). A row with nothing yet simply is not drawn:
/// a Home that reserved space for four rows that might turn out empty would
/// push the backend hubs down the page and then pull them back up, which is
/// the jump hoofdstuk 9.7 forbids for the hero and is no better here.
///
/// ## Why a late server reloads everything
///
/// A server coming online, a library being hidden, or the library list itself
/// changing alters which cursors take part in every row at once, so there is no
/// per-row reload that would be correct. This mirrors
/// `UnifiedCatalogProvider._reconcileEligibleLibraries`, including its guard:
/// the reload only happens when the participating library keys actually
/// changed, so a provider that notifies on every poll does not restart four
/// merges a minute.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/ids.dart';
import '../media/media_kind.dart';
import '../media/unified/unified_media_hub.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/unified_catalog/home_custom_row.dart';
import '../services/unified_catalog/home_custom_row_loader.dart';
import '../utils/global_key_utils.dart';
import 'hidden_libraries_provider.dart';
import 'home_layout_provider.dart';
import 'libraries_provider.dart';
import 'multi_server_provider.dart';

/// How many cards one custom row loads.
///
/// A rail shows a handful and pages nothing — hoofdstuk 12's paging is the
/// catalog's job, and "Alle N" is the door to it. Twenty is the merge engine's
/// own default page in groups, so a row costs exactly one round of it.
const int kHomeCustomRowCardLimit = 20;

class HomeCustomRowsProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  HomeCustomRowsProvider({
    required HomeLayoutProvider layout,
    required MultiServerProvider multiServer,
    required LibrariesProvider libraries,
    required HiddenLibrariesProvider hiddenLibraries,
    HomeCustomRowLoader? loader,
  }) : _layout = layout,
       _multiServer = multiServer,
       _libraries = libraries,
       _hiddenLibraries = hiddenLibraries,
       _loader =
           loader ??
           CatalogHomeCustomRowLoader(
             libraries: () => libraries.libraries,
             isServerVisible: multiServer.serverManager.isServerVisible,
             hiddenLibraryKeys: () => hiddenLibraries.hiddenLibraryKeys,
             clientFor: multiServer.serverManager.getClient,
           ) {
    _layout.addListener(_onLayoutChanged);
    _libraries.addListener(_onSourcesChanged);
    _hiddenLibraries.addListener(_onSourcesChanged);
    _multiServer.addOnlineServersListener(_onOnlineServersChanged);
    _libraryKeys = _currentLibraryKeys();
    unawaited(_loadAll());
  }

  final HomeLayoutProvider _layout;
  final MultiServerProvider _multiServer;
  final LibrariesProvider _libraries;
  final HiddenLibrariesProvider _hiddenLibraries;
  final HomeCustomRowLoader _loader;

  final Map<String, HomeCustomRowContent> _content = {};

  /// Rows a load is in flight for, so a rebuild does not start a second one and
  /// a finished load can tell whether it is still the current answer.
  final Set<String> _inFlight = {};

  /// The row value each entry in [_content] was loaded for, so an edit is
  /// detectable. See [_onLayoutChanged].
  final Map<String, HomeCustomRow> _loadedFor = {};

  Set<String> _libraryKeys = const {};

  /// What [rowId]'s filter yielded, or null while it has never been asked.
  HomeCustomRowContent? contentFor(String rowId) => _content[rowId];

  bool isLoading(String rowId) => _inFlight.contains(rowId);

  /// Every saved row that has been asked at least once, as a feed row, empty
  /// ones included.
  ///
  /// [titleFor] supplies the label because this layer has no locale and an
  /// unnamed row is labelled after its filter; see `home_custom_row_labels.dart`.
  ///
  /// The customise panel needs the empty ones — DEC-100 (6): "een bewaarde rij
  /// die later leeg raakt verdwijnt in rust van Home en blijft in het paneel
  /// staan" — so the two audiences are two methods rather than one list and a
  /// flag at every call site.
  List<UnifiedMediaHub> allRows({required String Function(HomeCustomRow row) titleFor}) => [
    for (final row in _layout.customRows)
      if (_content[row.id] case final content?)
        UnifiedMediaHub.synthesized(
          slug: row.hubSlug,
          title: titleFor(row),
          kind: unifiedHubKindForCustomRow(row),
          groups: content.groups,
          isPartial: content.isPartial,
          // The row's name in `HomeLayoutProvider`'s space, stated rather than
          // left to `homeLayoutIdsOf`'s hubId fallback. Those are two different
          // strings for one row, and letting the fallback answer meant the
          // panel wrote `hub:pleya:custom:<id>` into the order while
          // `removeCustomRow` cleaned up `#custom:<id>` — a hide nothing could
          // undo, and an order entry that outlived its row.
          contributingRowIds: [row.layoutRowId],
        ),
  ];

  /// The saved rows Home actually draws: [allRows] minus the empty ones.
  List<UnifiedMediaHub> visibleRows({required String Function(HomeCustomRow row) titleFor}) => [
    for (final row in allRows(titleFor: titleFor))
      if (row.groups.isNotEmpty) row,
  ];

  /// Re-asks one row's filter. Called after an edit, where the row's id is the
  /// same and its content is not.
  Future<void> refreshRow(String rowId) {
    _loadedFor.remove(rowId);
    return _load(rowId);
  }

  Future<void> refreshAll() {
    _loadedFor.clear();
    return _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([for (final row in _layout.customRows) _load(row.id)]);
  }

  /// One round of the merge for one row.
  ///
  /// A load already in flight is not joined and not queued behind: it re-checks
  /// the stored row when it lands and starts the next round itself. That is the
  /// only shape that survives an edit made while a load is out — queueing here
  /// would let two rounds of the same merge run against one row, and skipping
  /// without the re-check would leave the row showing the answer to the
  /// question it used to be.
  Future<void> _load(String rowId) async {
    if (_inFlight.contains(rowId)) return;
    final row = _layout.customRowById(rowId);
    if (row == null) return;
    _inFlight.add(rowId);
    safeNotifyListeners();
    try {
      final content = await _loader.load(row, limit: kHomeCustomRowCardLimit);
      if (isDisposed) return;
      if (_layout.customRowById(rowId) == row) {
        _content[rowId] = content;
        _loadedFor[rowId] = row;
      }
    } finally {
      _inFlight.remove(rowId);
      if (!isDisposed) {
        final current = _layout.customRowById(rowId);
        if (current == null) {
          _content.remove(rowId);
          _loadedFor.remove(rowId);
        }
        safeNotifyListeners();
        if (current != null && _loadedFor[rowId] != current) unawaited(_load(rowId));
      }
    }
  }

  /// A row added, removed or edited.
  ///
  /// Compared against the row *value* this provider last loaded for, not
  /// against the set of ids: an edit keeps the id and changes the question, and
  /// an id-only comparison would leave the old answer on screen forever. A
  /// reorder or a hide notifies the same provider and changes no row value, so
  /// it starts nothing.
  void _onLayoutChanged() {
    final rows = _layout.customRows;
    final ids = {for (final row in rows) row.id};
    var changed = false;
    for (final id in _content.keys.toList()) {
      if (ids.contains(id)) continue;
      _content.remove(id);
      _loadedFor.remove(id);
      changed = true;
    }
    for (final row in rows) {
      if (_loadedFor[row.id] != row) unawaited(_load(row.id));
    }
    if (changed) safeNotifyListeners();
  }

  void _onSourcesChanged() => _reconcile();

  void _onOnlineServersChanged(Set<String> onlineServerIds) => _reconcile();

  void _reconcile() {
    if (_layout.customRows.isEmpty) return;
    final keys = _currentLibraryKeys();
    if (setEquals(keys, _libraryKeys)) return;
    _libraryKeys = keys;
    unawaited(refreshAll());
  }

  /// Every library any custom row could draw from, in one flat set. Per-kind
  /// eligibility is the loader's business; this only has to notice that the
  /// set of sources changed at all.
  Set<String> _currentLibraryKeys() => {
    for (final library in _libraries.libraries)
      if (library.serverId case final serverId?)
        if (serverId.isNotEmpty && !library.hidden)
          if (_multiServer.serverManager.isServerVisible(ServerId(serverId)))
            if (!_hiddenLibraries.hiddenLibraryKeys.contains(buildGlobalKey(ServerId(serverId), library.id)))
              buildGlobalKey(ServerId(serverId), library.id),
  };

  @override
  void dispose() {
    _layout.removeListener(_onLayoutChanged);
    _libraries.removeListener(_onSourcesChanged);
    _hiddenLibraries.removeListener(_onSourcesChanged);
    _multiServer.removeOnlineServersListener(_onOnlineServersChanged);
    super.dispose();
  }
}

/// The projection layer's word for a saved row's kind. Films and Series are
/// the only two a row can carry, so there is no `mixed` case to consider.
UnifiedHubKind unifiedHubKindForCustomRow(HomeCustomRow row) =>
    row.kind == MediaKind.movie ? UnifiedHubKind.movie : UnifiedHubKind.show;
