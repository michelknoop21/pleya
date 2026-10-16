import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../i18n/strings.g.dart';
import '../../../mixins/refreshable.dart';
import '../../../providers/personal_media_provider.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/layout_constants.dart';
import '../../../widgets/tv/tv_catalog_card_grid.dart';
import '../../../widgets/tv/tv_catalog_card.dart';
import '../../../widgets/tv/tv_unified_layout.dart';
import '../../../widgets/library_cover_artwork.dart';
import '../../../widgets/library_atmosphere.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../widgets/tv/tv_page_surface.dart';
import '../../../widgets/tv/tv_panel_primitives.dart';

class TvCollectionsOverviewScreen extends StatefulWidget {
  const TvCollectionsOverviewScreen({super.key});

  @override
  State<TvCollectionsOverviewScreen> createState() => TvCollectionsOverviewScreenState();
}

class TvCollectionsOverviewScreenState extends State<TvCollectionsOverviewScreen> implements FocusableTab, Refreshable {
  final _gridKey = GlobalKey<TvCatalogCardGridState>();
  String? _lastFocusedId;
  final FocusNode _actionNode = FocusNode(debugLabel: 'tvCollections.action');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<PersonalMediaProvider>();
      if (provider.state == PersonalMediaLoadState.initial) unawaited(provider.load());
    });
  }

  @override
  void dispose() {
    _actionNode.dispose();
    super.dispose();
  }

  @override
  void focusActiveTabIfReady() {
    if (!TickerMode.valuesOf(context).enabled || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final provider = context.read<PersonalMediaProvider>();
    if (provider.collections.isNotEmpty && _gridKey.currentState != null) {
      _gridKey.currentState!.focusGrid();
      return;
    }
    if (_actionNode.canRequestFocus) _actionNode.requestFocus();
  }

  @override
  void refresh() => unawaited(context.read<PersonalMediaProvider>().load());

  Future<void> _open(PersonalCollectionEntry entry) async {
    await navigateToMediaItem(context, entry.item);
    if (!mounted) return;
    await context.read<PersonalMediaProvider>().load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusActiveTabIfReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PersonalMediaProvider>();
    final entries = provider.collections;
    return LibraryAtmosphere(
      automationInstance: 'tv_collections',
      child: TvPageSurface(
        title: t.collections.title,
        automationInstance: 'collections',
        trailing: _OverviewAction(
          node: _actionNode,
          retry: provider.state == PersonalMediaLoadState.error || provider.failedCollectionLibraryKeys.isNotEmpty,
          onPressed: provider.failedCollectionLibraryKeys.isNotEmpty ? provider.retryFailed : provider.load,
          onNavigateDown: focusActiveTabIfReady,
        ),
        expandedOwnsInsets: entries.isNotEmpty,
        expanded: entries.isEmpty
            ? null
            : TvCatalogCardGrid(
                key: _gridKey,
                itemIds: entries.map(_collectionKey).toList(),
                initialFocusedId: _lastFocusedId,
                onFocusedIdChanged: (id) => _lastFocusedId = id,
                nodeDebugLabel: 'tvcollections',
                hasMore: false,
                isLoadingMore: false,
                onLoadMore: () {},
                onExitTop: () => _actionNode.requestFocus(),
                cardHeight: (width) =>
                    TvCatalogLayout.cardHeight(width, TvLayoutConstants.scaleOf(context), extraMetaLines: 1),
                itemBuilder: (context, cell) {
                  final entry = entries[cell.index];
                  final count = entry.item.childCount;
                  final source = entry.sourceLabel;
                  return AutomationNode(
                    id: AutomationIds.myPleyaSectionTile,
                    instance: 'collections.${_collectionKey(entry)}',
                    role: 'grid.item',
                    focusNode: cell.focusNode,
                    state: () => <String, Object?>{
                      'title': entry.item.displayTitle,
                      'value': source,
                      'selected': false,
                    },
                    child: LibraryArtworkSelection(
                      item: entry.item,
                      child: TvCatalogCard(
                        width: cell.width,
                        artwork: TvCatalogArtworkFill(
                          child: LibraryCoverArtwork(
                            item: entry.item,
                            client: provider.clientForServer(entry.serverId),
                            fallbackIcon: Symbols.collections_bookmark_rounded,
                          ),
                        ),
                        title: entry.item.displayTitle,
                        meta: count == null ? '' : t.playlists.itemCount(count: count),
                        tertiary: source,
                        onSelect: () => unawaited(_open(entry)),
                        focusNode: cell.focusNode,
                        onFocusChange: cell.onFocusChange,
                        onNavigateUp: cell.onNavigateUp,
                        onNavigateDown: cell.onNavigateDown,
                        onNavigateLeft: cell.onNavigateLeft,
                        onNavigateRight: cell.onNavigateRight,
                        onBack: cell.onBack,
                        semanticLabel:
                            '${entry.item.displayTitle}. ${count == null ? '' : t.playlists.itemCount(count: count)}. $source',
                      ),
                    ),
                  );
                },
              ),
        children: [
          if (entries.isEmpty)
            _OverviewMessage(
              loading: provider.isLoading,
              failed: provider.failedCollectionLibraryKeys.isNotEmpty,
              emptyLabel: t.libraries.noCollections,
            )
          else ...[
            if (provider.failedCollectionLibraryKeys.isNotEmpty) const _PartialFailureMessage(),
          ],
        ],
      ),
    );
  }
}

class TvPlaylistsOverviewScreen extends StatefulWidget {
  const TvPlaylistsOverviewScreen({super.key});

  @override
  State<TvPlaylistsOverviewScreen> createState() => TvPlaylistsOverviewScreenState();
}

class TvPlaylistsOverviewScreenState extends State<TvPlaylistsOverviewScreen> implements FocusableTab, Refreshable {
  final _gridKey = GlobalKey<TvCatalogCardGridState>();
  String? _lastFocusedId;
  final FocusNode _actionNode = FocusNode(debugLabel: 'tvPlaylists.action');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<PersonalMediaProvider>();
      if (provider.state == PersonalMediaLoadState.initial) unawaited(provider.load());
    });
  }

  @override
  void dispose() {
    _actionNode.dispose();
    super.dispose();
  }

  @override
  void focusActiveTabIfReady() {
    if (!TickerMode.valuesOf(context).enabled || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final provider = context.read<PersonalMediaProvider>();
    if (provider.playlists.isNotEmpty && _gridKey.currentState != null) {
      _gridKey.currentState!.focusGrid();
      return;
    }
    if (_actionNode.canRequestFocus) _actionNode.requestFocus();
  }

  @override
  void refresh() => unawaited(context.read<PersonalMediaProvider>().load());

  Future<void> _open(PersonalPlaylistEntry entry) async {
    await navigateToMediaItem(context, entry.playlist);
    if (!mounted) return;
    await context.read<PersonalMediaProvider>().load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusActiveTabIfReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PersonalMediaProvider>();
    final entries = provider.playlists;
    return LibraryAtmosphere(
      automationInstance: 'tv_playlists',
      child: TvPageSurface(
        title: t.playlists.title,
        automationInstance: 'playlists',
        trailing: _OverviewAction(
          node: _actionNode,
          retry: provider.state == PersonalMediaLoadState.error || provider.failedPlaylistServerIds.isNotEmpty,
          onPressed: provider.failedPlaylistServerIds.isNotEmpty ? provider.retryFailed : provider.load,
          onNavigateDown: focusActiveTabIfReady,
        ),
        expandedOwnsInsets: entries.isNotEmpty,
        expanded: entries.isEmpty
            ? null
            : TvCatalogCardGrid(
                key: _gridKey,
                itemIds: entries.map(_playlistKey).toList(),
                initialFocusedId: _lastFocusedId,
                onFocusedIdChanged: (id) => _lastFocusedId = id,
                nodeDebugLabel: 'tvplaylists',
                hasMore: false,
                isLoadingMore: false,
                onLoadMore: () {},
                onExitTop: () => _actionNode.requestFocus(),
                cardHeight: (width) =>
                    TvCatalogLayout.cardHeight(width, TvLayoutConstants.scaleOf(context), extraMetaLines: 1),
                itemBuilder: (context, cell) {
                  final entry = entries[cell.index];
                  final count = entry.playlist.leafCount;
                  final source = entry.serverName;
                  return AutomationNode(
                    id: AutomationIds.myPleyaSectionTile,
                    instance: 'playlists.${_playlistKey(entry)}',
                    role: 'grid.item',
                    focusNode: cell.focusNode,
                    state: () => <String, Object?>{
                      'title': entry.playlist.displayTitle,
                      'value': source,
                      'selected': false,
                    },
                    child: LibraryArtworkSelection(
                      item: entry.playlist,
                      child: TvCatalogCard(
                        width: cell.width,
                        artwork: TvCatalogArtworkFill(
                          child: LibraryCoverArtwork(
                            item: entry.playlist,
                            client: provider.clientForServer(entry.serverId),
                            fallbackIcon: Symbols.playlist_play_rounded,
                          ),
                        ),
                        title: entry.playlist.displayTitle,
                        meta: count == null ? '' : t.playlists.itemCount(count: count),
                        tertiary: source,
                        onSelect: () => unawaited(_open(entry)),
                        focusNode: cell.focusNode,
                        onFocusChange: cell.onFocusChange,
                        onNavigateUp: cell.onNavigateUp,
                        onNavigateDown: cell.onNavigateDown,
                        onNavigateLeft: cell.onNavigateLeft,
                        onNavigateRight: cell.onNavigateRight,
                        onBack: cell.onBack,
                        semanticLabel:
                            '${entry.playlist.displayTitle}. ${count == null ? '' : t.playlists.itemCount(count: count)}. $source',
                      ),
                    ),
                  );
                },
              ),
        children: [
          if (entries.isEmpty)
            _OverviewMessage(
              loading: provider.isLoading,
              failed: provider.failedPlaylistServerIds.isNotEmpty,
              emptyLabel: t.playlists.noPlaylists,
            )
          else ...[
            if (provider.failedPlaylistServerIds.isNotEmpty) const _PartialFailureMessage(),
          ],
        ],
      ),
    );
  }
}

String _collectionKey(PersonalCollectionEntry entry) => '${entry.library.globalKey}:${entry.item.id}';
String _playlistKey(PersonalPlaylistEntry entry) => '${entry.serverId}:${entry.playlist.id}';

class _OverviewAction extends StatelessWidget {
  const _OverviewAction({
    required this.node,
    required this.retry,
    required this.onPressed,
    required this.onNavigateDown,
  });

  final FocusNode node;
  final bool retry;
  final Future<void> Function() onPressed;
  final VoidCallback onNavigateDown;

  @override
  Widget build(BuildContext context) => TvPanelButton(
    scale: TvLayoutConstants.scaleOf(context),
    label: retry ? t.common.retry : t.common.refresh,
    icon: retry ? Symbols.refresh_rounded : Symbols.sync_rounded,
    primary: false,
    focusNode: node,
    onNavigateDown: onNavigateDown,
    onPressed: () => unawaited(onPressed()),
  );
}

class _OverviewMessage extends StatelessWidget {
  const _OverviewMessage({required this.loading, required this.failed, required this.emptyLabel});

  final bool loading;
  final bool failed;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (loading) ...[
        const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 12),
      ],
      Flexible(
        child: Text(
          loading ? t.common.loading : (failed ? t.errors.somethingWentWrongTryAgain : emptyLabel),
          style: tvPageBodyStyle(context),
        ),
      ),
    ],
  );
}

class _PartialFailureMessage extends StatelessWidget {
  const _PartialFailureMessage();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(t.unifiedCatalog.discovery.partial, style: tvPageBodyStyle(context, alpha: 0.76)),
  );
}
