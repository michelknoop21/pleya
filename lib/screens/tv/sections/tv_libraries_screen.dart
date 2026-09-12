/// Mijn Pleya ▸ Bibliotheken on TV — bronbeheer, not a second browsing screen
/// (LIB7, [DEC-092](../../../../docs/DECISIONS.md#dec-092), mockup 27 A/B/C/D).
///
/// The shared [LibrariesScreen] keeps serving desktop and mobile unchanged —
/// DEC-092 is TV-only. This screen replaces it on TV: a library is a
/// management row (kind, item count, visible/hidden), not a tab bar with its
/// own Aanbevolen/Bladeren/Collecties/Playlists. Browsing a library's content
/// now goes through the existing unified catalog with that library as a
/// source filter (state D), the same "Alle N" mechanism ROW1c already opens
/// with a preset filter.
///
/// **What this round deliberately does not build.** "Mappen bladeren"
/// (mockup 27 B) needs its own TV folder-tree navigator; none exists today
/// (`FolderTreeView` is a mode inside the mobile/desktop Browse tab that this
/// decision removes). Building one is a distinct workitem, not a silent
/// addition to LIB7's scope. Per-library item counts have no cheap existing
/// source either — no client method returns one without paging the library —
/// so this screen fetches them lazily, one bounded page per row, after the
/// page has already painted.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../focus/focus_memory_tracker.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/library_query.dart';
import '../../../media/media_backend.dart';
import '../../../media/media_kind.dart';
import '../../../media/media_library.dart';
import '../../../mixins/refreshable.dart';
import '../../../providers/hidden_libraries_provider.dart';
import '../../../providers/libraries_provider.dart';
import '../../../providers/unified_catalogs.dart';
import '../../../services/unified_catalog/unified_catalog_filters.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/content_utils.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/layout_constants.dart';
import '../../../utils/library_grouping.dart';
import '../../../utils/provider_extensions.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/tv/tv_catalog_sort_panel.dart';
import '../../../widgets/tv/tv_menu_grid.dart';
import '../../../widgets/tv/tv_page_surface.dart';
import '../../../widgets/tv/tv_panel_primitives.dart';
import '../tv_unified_catalog_screen.dart';
import 'tv_library_action_sheet.dart';

/// One admin action a library row's action sheet may offer (mockup 27 B).
enum TvLibraryAction { openInCatalog, refreshMetadata, scan, toggleVisibility, analyze, emptyTrash }

/// Which actions [library] offers, in the order mockup 27 B draws them.
///
/// Scan/Analyze/Prullenbak hit Plex-only endpoints — the same gate
/// `_getLibraryMenuItems` in the shared [LibrariesScreen] applies. Openen in
/// catalogus only makes sense for a library the unified catalog actually
/// browses; a music or photo library gets the admin actions and nothing else.
List<TvLibraryAction> tvLibraryActionsFor(MediaLibrary library) {
  final isCatalogable = library.kind == MediaKind.movie || library.kind == MediaKind.show;
  final isPlex = library.backend == MediaBackend.plex;
  return [
    if (isCatalogable) TvLibraryAction.openInCatalog,
    TvLibraryAction.refreshMetadata,
    if (isPlex) TvLibraryAction.scan,
    TvLibraryAction.toggleVisibility,
    if (isPlex) TvLibraryAction.analyze,
    if (isPlex) TvLibraryAction.emptyTrash,
  ];
}

class TvLibrariesScreen extends StatefulWidget {
  const TvLibrariesScreen({super.key});

  @override
  State<TvLibrariesScreen> createState() => TvLibrariesScreenState();
}

class TvLibrariesScreenState extends State<TvLibrariesScreen> implements FocusableTab, LibraryLoadable, Refreshable {
  final FocusMemoryTracker _nodes = FocusMemoryTracker(debugLabelPrefix: 'tvLibraries');
  final FocusNode _refreshAllNode = FocusNode(debugLabel: 'tvLibraries.refreshAll');
  final FocusNode _reorderNode = FocusNode(debugLabel: 'tvLibraries.reorder');

  /// `globalKey -> totalCount`. Absent while the row's own request is still in
  /// flight; a failed request leaves the row without a count rather than
  /// retrying in a loop.
  final Map<String, int> _counts = {};

  bool _reordering = false;

  /// Set by [loadLibraryByKey], consumed by the very next
  /// [focusActiveTabIfReady]. `main_screen.dart`'s `_selectLibrary` calls both
  /// back-to-back in the same postFrameCallback; `FocusMemoryTracker.lastFocusedKey`
  /// only updates once the focus manager applies the pending change (a
  /// microtask later), so reading it here would still see the *previous*
  /// row and this method would win the race and refocus that instead.
  String? _pendingExplicitFocusKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCounts());
  }

  @override
  void dispose() {
    _nodes.dispose();
    _refreshAllNode.dispose();
    _reorderNode.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    if (!mounted) return;
    final libraries = context.read<LibrariesProvider>().libraries;
    for (final library in libraries) {
      if (_counts.containsKey(library.globalKey)) continue;
      unawaited(_loadCountFor(library));
    }
  }

  Future<void> _loadCountFor(MediaLibrary library) async {
    try {
      final client = context.getMediaClientForLibrary(library);
      final page = await client.fetchLibraryPagedContent(
        library.id,
        query: const LibraryQuery(offset: 0, limit: 1),
        libraryKind: library.kind,
      );
      if (!mounted) return;
      setState(() => _counts[library.globalKey] = page.totalCount);
    } catch (e) {
      // No count for this row. Not retried: a library that cannot answer a
      // one-item page will not answer a retry either, and this screen has no
      // reason to hammer a server that is already struggling.
      appLogger.d('TvLibrariesScreen: count fetch failed for ${library.globalKey}: $e');
    }
  }

  @override
  void refresh() {
    _counts.clear();
    context.read<LibrariesProvider>().refresh();
    _loadCounts();
  }

  /// Where the remote lands on first entry: the last row it stood on, or —
  /// mockup 27 A draws the ring on the first row, not on a header action —
  /// the first library. Only when there is truly nothing to focus (the
  /// empty-libraries state) does this fall through to the header, which is
  /// also the one place a viewer can still act from there (Alles vernieuwen).
  @override
  void focusActiveTabIfReady() {
    final pending = _pendingExplicitFocusKey;
    _pendingExplicitFocusKey = null;
    final currentKeys = _currentLibraries().map((l) => l.globalKey).toSet();
    // A key naming a library that no longer exists (server offline, list
    // changed since this was last the focused row) is exactly the stale-node
    // trap CAT16/LAND5 already found elsewhere: `canRequestFocus` is true on
    // a detached node too, so `requestFocus()` silently no-ops and this
    // method must not `return` believing it worked.
    final key =
        [pending, _nodes.lastFocusedKey].firstWhere((k) => k != null && currentKeys.contains(k), orElse: () => null) ??
        _firstRowKey(groupLibrariesByFirstAppearance(_currentLibraries()));
    if (key != null) {
      final node = _nodes.get(key);
      if (node.canRequestFocus) {
        node.requestFocus();
        return;
      }
    }
    if (_refreshAllNode.canRequestFocus) _refreshAllNode.requestFocus();
  }

  List<MediaLibrary> _currentLibraries() => context.read<LibrariesProvider>().libraries;

  /// Hoofdstuk 6.4's compatibility adapter (see `main_screen.dart`'s
  /// `_selectLibrary`): puts the remote on the row for [libraryGlobalKey].
  ///
  /// A library row no longer opens content directly — DEC-092 replaced that
  /// with the action sheet's "Openen in catalogus" — so the honest equivalent
  /// of "load this library" here is "show me that row", not a route push.
  ///
  /// Synchronous, like `TvMyPleyaScreenState.focusKey` — no postFrameCallback
  /// of its own. The caller (`main_screen.dart`'s `_selectLibrary`) already
  /// wraps this whole call in one to let the section's own route mount first;
  /// a second, nested postFrameCallback here would defer the actual
  /// `requestFocus()` to a frame after the one the caller already waited for.
  @override
  void loadLibraryByKey(String libraryGlobalKey) {
    _pendingExplicitFocusKey = libraryGlobalKey;
    final node = _nodes.get(libraryGlobalKey);
    if (node.canRequestFocus) node.requestFocus();
  }

  void _openActionSheet(MediaLibrary library, {required bool isHidden}) {
    unawaited(
      showTvLibraryActionSheet(
        context,
        library: library,
        isHidden: isHidden,
        onOpenInCatalog: () => _openInCatalog(library),
        onRefreshMetadata: () => _refreshMetadata(library),
        onScan: () => _scan(library),
        onToggleVisibility: () => _toggleVisibility(library, isHidden: isHidden),
        onAnalyze: () => _analyze(library),
        onEmptyTrash: () => _emptyTrash(library),
      ),
    );
  }

  void _openInCatalog(MediaLibrary library) {
    final catalogs = context.read<UnifiedCatalogs>();
    final kind = library.kind == MediaKind.show ? MediaKind.show : MediaKind.movie;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvUnifiedCatalogScreen(
          catalog: catalogs.forKind(kind),
          title: kind == MediaKind.show ? t.unifiedCatalog.discovery.allSeries : t.unifiedCatalog.discovery.allMovies,
          initialFilterOverride: UnifiedCatalogPreferences(
            filters: UnifiedCatalogFilterSelection(libraryKeys: {library.globalKey}),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required Future<void> Function() action,
    required String successMessage,
    required String failureMessage,
  }) async {
    final confirmed = await showConfirmDialog(context, title: title, message: message, confirmText: t.common.confirm);
    if (!confirmed || !mounted) return;
    try {
      await action();
      if (mounted) showSuccessSnackBar(context, successMessage);
    } catch (e) {
      appLogger.w('TvLibrariesScreen: action failed: $e');
      if (mounted) showErrorSnackBar(context, failureMessage);
    }
  }

  Future<void> _refreshMetadata(MediaLibrary library) => _confirmAndRun(
    title: t.libraries.refreshMetadata,
    message: t.libraries.refreshMetadataConfirm(title: library.title),
    action: () => context.getMediaClientForLibrary(library).refreshLibraryMetadata(library.id),
    successMessage: t.messages.metadataRefreshStarted(title: library.title),
    failureMessage: t.libraries.failedToRefreshMetadata,
  );

  Future<void> _scan(MediaLibrary library) => _confirmAndRun(
    title: t.libraries.scanLibrary,
    message: t.libraries.scanLibraryConfirm(title: library.title),
    action: () => context.getPlexClientForLibrary(library).scanLibrary(library.id),
    successMessage: t.messages.libraryScanStarted(title: library.title),
    failureMessage: t.libraries.failedToScan,
  );

  Future<void> _analyze(MediaLibrary library) => _confirmAndRun(
    title: t.libraries.analyzeLibrary,
    message: t.libraries.analyzeLibraryConfirm(title: library.title),
    action: () => context.getPlexClientForLibrary(library).analyzeLibrary(library.id),
    successMessage: t.libraries.analysisStarted(title: library.title),
    failureMessage: t.libraries.failedToAnalyze,
  );

  Future<void> _emptyTrash(MediaLibrary library) => _confirmAndRun(
    title: t.libraries.emptyTrash,
    message: t.libraries.emptyTrashConfirm(title: library.title),
    action: () => context.getPlexClientForLibrary(library).emptyLibraryTrash(library.id),
    successMessage: t.libraries.trashEmptied(title: library.title),
    failureMessage: t.libraries.failedToEmptyTrash,
  );

  Future<void> _toggleVisibility(MediaLibrary library, {required bool isHidden}) async {
    final hidden = context.read<HiddenLibrariesProvider>();
    if (isHidden) {
      await hidden.unhideLibrary(library.globalKey);
    } else {
      await hidden.hideLibrary(library.globalKey);
    }
  }

  String _countLabel(MediaLibrary library) {
    final count = _counts[library.globalKey];
    if (count == null) return '…';
    return count == 1 ? t.libraries.oneItem : t.libraries.itemCount(count: count);
  }

  @override
  Widget build(BuildContext context) {
    final libraries = context.watch<LibrariesProvider>().libraries;
    final hiddenKeys = context.watch<HiddenLibrariesProvider>().hiddenLibraryKeys;

    if (libraries.isEmpty) {
      return TvPageSurface(
        title: t.libraries.title,
        automationInstance: 'libraries',
        children: [Text(t.libraries.noLibrariesFound, style: TextStyle(color: tokens(context).textMuted))],
      );
    }

    if (_reordering) {
      final reorderGroups = groupLibrariesByFirstAppearance(libraries);
      return TvPageSurface(
        title: t.libraries.title,
        automationInstance: 'libraries.reorder',
        trailing: TvPanelButton(
          scale: TvLayoutConstants.scaleOf(context),
          label: t.unifiedCatalog.homeRows.done,
          icon: Symbols.check_rounded,
          primary: false,
          focusNode: _reorderNode,
          onNavigateDown: () => _nodes.get(_firstRowKey(reorderGroups)!).requestFocus(),
          onPressed: () => setState(() => _reordering = false),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(t.libraries.reorderIntro, style: TextStyle(color: tokens(context).textMuted)),
          ),
          _TvLibraryReorderList(
            // Server-grouped, not the provider's raw order: `_groupBounds`
            // clamps a move to a contiguous run of the same `serverId`, and
            // the provider's own order is not guaranteed contiguous (a
            // library discovered after initial load is appended at the end,
            // interleaving servers). Seeding from the same grouping the
            // normal list already displays keeps every server's libraries
            // adjacent, so the clamp bounds mean what the numbering shows.
            libraries: [for (final serverKey in reorderGroups.serverOrder) ...reorderGroups.byServer[serverKey]!],
            hiddenKeys: hiddenKeys,
            nodes: _nodes,
            onExitUp: () => _reorderNode.requestFocus(),
            onReorder: (reordered) => context.read<LibrariesProvider>().updateLibraryOrder(reordered),
          ),
        ],
      );
    }

    final groups = groupLibrariesByFirstAppearance(libraries);
    final scale = TvLayoutConstants.scaleOf(context);

    return TvPageSurface(
      title: t.libraries.title,
      automationInstance: 'libraries',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TvPanelButton(
            scale: scale,
            label: t.libraries.refreshAllLibraries,
            icon: Symbols.refresh_rounded,
            primary: false,
            focusNode: _refreshAllNode,
            onNavigateRight: libraries.length > 1 ? () => _reorderNode.requestFocus() : null,
            onNavigateDown: () => _nodes.get(_firstRowKey(groups)!).requestFocus(),
            onPressed: refresh,
          ),
          if (libraries.length > 1) ...[
            const SizedBox(width: 12),
            TvPanelButton(
              scale: scale,
              label: t.libraries.reorder,
              icon: Symbols.swap_vert_rounded,
              primary: false,
              focusNode: _reorderNode,
              onNavigateLeft: () => _refreshAllNode.requestFocus(),
              onNavigateDown: () => _nodes.get(_firstRowKey(groups)!).requestFocus(),
              onPressed: () => setState(() => _reordering = true),
            ),
          ],
        ],
      ),
      children: [
        TvMenuGrid(
          nodes: _nodes,
          columns: 1,
          automationInstance: 'libraries',
          onExitUp: () => _refreshAllNode.requestFocus(),
          sections: [
            for (final serverKey in groups.serverOrder)
              TvMenuSection(
                label: groups.byServer[serverKey]!.first.serverName ?? t.libraries.fallbackTitle,
                items: [
                  for (final library in groups.byServer[serverKey]!)
                    TvMenuItem(
                      key: library.globalKey,
                      icon: ContentTypeHelper.getLibraryIcon(library.kind.id),
                      title: library.title,
                      toggled: !hiddenKeys.contains(library.globalKey),
                      value: hiddenKeys.contains(library.globalKey)
                          ? '${_countLabel(library)} · ${t.unifiedCatalog.homeRows.hiddenNote}'
                          : _countLabel(library),
                      onSelect: () => _openActionSheet(library, isHidden: hiddenKeys.contains(library.globalKey)),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  String? _firstRowKey(LibraryServerGroups groups) {
    for (final serverKey in groups.serverOrder) {
      final libs = groups.byServer[serverKey]!;
      if (libs.isNotEmpty) return libs.first.globalKey;
    }
    return null;
  }
}

/// A flat, movable list of every library (mockup 27 C). Movement is clamped to
/// the library's own server group — the numbering shown is a position within
/// that group, and letting a row cross into another server's block would make
/// that number lie.
class _TvLibraryReorderList extends StatefulWidget {
  const _TvLibraryReorderList({
    required this.libraries,
    required this.hiddenKeys,
    required this.nodes,
    required this.onReorder,
    required this.onExitUp,
  });

  final List<MediaLibrary> libraries;
  final Set<String> hiddenKeys;
  final FocusMemoryTracker nodes;
  final ValueChanged<List<MediaLibrary>> onReorder;
  final VoidCallback onExitUp;

  @override
  State<_TvLibraryReorderList> createState() => _TvLibraryReorderListState();
}

class _TvLibraryReorderListState extends State<_TvLibraryReorderList> {
  late List<MediaLibrary> _order = List.of(widget.libraries);
  int? _movingIndex;

  @override
  void didUpdateWidget(_TvLibraryReorderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The provider is the source of truth; a move outside this list (another
    // session, a profile switch) must not leave this screen showing a stale
    // order. A move made *by* this list already matches by the time this runs.
    if (!listEquals(oldWidget.libraries, widget.libraries)) _order = List.of(widget.libraries);
  }

  ({int start, int end}) _groupBounds(int index) {
    final serverId = _order[index].serverId;
    var start = index, end = index;
    while (start > 0 && _order[start - 1].serverId == serverId) {
      start--;
    }
    while (end < _order.length - 1 && _order[end + 1].serverId == serverId) {
      end++;
    }
    return (start: start, end: end);
  }

  void _move(int index, int delta) {
    final bounds = _groupBounds(index);
    final target = index + delta;
    if (target < bounds.start || target > bounds.end) return;
    setState(() {
      final item = _order.removeAt(index);
      _order.insert(target, item);
      _movingIndex = target;
    });
    widget.onReorder(_order);
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupLibrariesByFirstAppearance(_order);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final serverKey in groups.serverOrder) ...[
          TvPageGroupLabel(groups.byServer[serverKey]!.first.serverName ?? ''),
          for (final library in groups.byServer[serverKey]!) _row(library),
        ],
      ],
    );
  }

  Widget _row(MediaLibrary library) {
    final index = _order.indexOf(library);
    final position = _order.sublist(_groupBounds(index).start, index).length + 1;
    final isHidden = widget.hiddenKeys.contains(library.globalKey);
    final isMoving = _movingIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvCatalogOptionRow(
        key: ValueKey(library.globalKey),
        label: library.title,
        secondary: isHidden ? t.unifiedCatalog.homeRows.hiddenNote : '$position',
        isSelected: isMoving,
        scale: TvLayoutConstants.scaleOf(context),
        focusNode: widget.nodes.get(library.globalKey, debugLabel: library.globalKey),
        onNavigateUp: isMoving ? () => _move(index, -1) : () => _focusNeighbour(index, -1),
        onNavigateDown: isMoving ? () => _move(index, 1) : () => _focusNeighbour(index, 1),
        onPressed: () => setState(() => _movingIndex = isMoving ? null : index),
      ),
    );
  }

  void _focusNeighbour(int index, int delta) {
    final target = index + delta;
    if (target < 0) {
      widget.onExitUp();
      return;
    }
    if (target >= _order.length) return;
    widget.nodes.get(_order[target].globalKey).requestFocus();
  }
}
