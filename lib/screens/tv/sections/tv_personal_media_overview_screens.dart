import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../focus/focus_memory_tracker.dart';
import '../../../i18n/strings.g.dart';
import '../../../mixins/refreshable.dart';
import '../../../providers/personal_media_provider.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/layout_constants.dart';
import '../../../widgets/tv/tv_menu_grid.dart';
import '../../../widgets/tv/tv_page_surface.dart';
import '../../../widgets/tv/tv_panel_primitives.dart';

class TvCollectionsOverviewScreen extends StatefulWidget {
  const TvCollectionsOverviewScreen({super.key});

  @override
  State<TvCollectionsOverviewScreen> createState() => TvCollectionsOverviewScreenState();
}

class TvCollectionsOverviewScreenState extends State<TvCollectionsOverviewScreen> implements FocusableTab, Refreshable {
  final FocusMemoryTracker _nodes = FocusMemoryTracker(debugLabelPrefix: 'tvCollections');
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
    _nodes.dispose();
    _actionNode.dispose();
    super.dispose();
  }

  @override
  void focusActiveTabIfReady() {
    final provider = context.read<PersonalMediaProvider>();
    final keys = provider.collections.map(_collectionKey).toSet();
    final wanted = keys.contains(_nodes.lastFocusedKey) ? _nodes.lastFocusedKey : (keys.isEmpty ? null : keys.first);
    if (wanted != null) {
      final node = _nodes.get(wanted);
      if (node.canRequestFocus) {
        node.requestFocus();
        return;
      }
    }
    if (_actionNode.canRequestFocus) _actionNode.requestFocus();
  }

  @override
  void refresh() => unawaited(context.read<PersonalMediaProvider>().load());

  Future<void> _open(PersonalCollectionEntry entry) async {
    await navigateToMediaItem(context, entry.item);
    if (mounted) await context.read<PersonalMediaProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PersonalMediaProvider>();
    final entries = provider.collections;
    final grouped = <String, List<PersonalCollectionEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.library.globalKey, () => []).add(entry);
    }

    return TvPageSurface(
      title: t.collections.title,
      automationInstance: 'collections',
      trailing: _OverviewAction(
        node: _actionNode,
        retry: provider.state == PersonalMediaLoadState.error || provider.failedCollectionLibraryKeys.isNotEmpty,
        onPressed: provider.failedCollectionLibraryKeys.isNotEmpty ? provider.retryFailed : provider.load,
        onNavigateDown: focusActiveTabIfReady,
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
          TvMenuGrid(
            nodes: _nodes,
            columns: 2,
            automationInstance: 'collections',
            onExitUp: () => _actionNode.requestFocus(),
            sections: [
              for (final group in grouped.values)
                TvMenuSection(
                  label: group.first.sourceLabel,
                  items: [
                    for (final entry in group)
                      TvMenuItem(
                        key: _collectionKey(entry),
                        icon: Symbols.collections_bookmark_rounded,
                        title: entry.item.displayTitle,
                        value: entry.item.childCount == null
                            ? entry.library.title
                            : t.playlists.itemCount(count: entry.item.childCount!),
                        onSelect: () => unawaited(_open(entry)),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class TvPlaylistsOverviewScreen extends StatefulWidget {
  const TvPlaylistsOverviewScreen({super.key});

  @override
  State<TvPlaylistsOverviewScreen> createState() => TvPlaylistsOverviewScreenState();
}

class TvPlaylistsOverviewScreenState extends State<TvPlaylistsOverviewScreen> implements FocusableTab, Refreshable {
  final FocusMemoryTracker _nodes = FocusMemoryTracker(debugLabelPrefix: 'tvPlaylists');
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
    _nodes.dispose();
    _actionNode.dispose();
    super.dispose();
  }

  @override
  void focusActiveTabIfReady() {
    final provider = context.read<PersonalMediaProvider>();
    final keys = provider.playlists.map(_playlistKey).toSet();
    final wanted = keys.contains(_nodes.lastFocusedKey) ? _nodes.lastFocusedKey : (keys.isEmpty ? null : keys.first);
    if (wanted != null) {
      final node = _nodes.get(wanted);
      if (node.canRequestFocus) {
        node.requestFocus();
        return;
      }
    }
    if (_actionNode.canRequestFocus) _actionNode.requestFocus();
  }

  @override
  void refresh() => unawaited(context.read<PersonalMediaProvider>().load());

  Future<void> _open(PersonalPlaylistEntry entry) async {
    await navigateToMediaItem(context, entry.playlist);
    if (mounted) await context.read<PersonalMediaProvider>().load();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PersonalMediaProvider>();
    final entries = provider.playlists;
    final grouped = <String, List<PersonalPlaylistEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.serverId, () => []).add(entry);
    }

    return TvPageSurface(
      title: t.playlists.title,
      automationInstance: 'playlists',
      trailing: _OverviewAction(
        node: _actionNode,
        retry: provider.state == PersonalMediaLoadState.error || provider.failedPlaylistServerIds.isNotEmpty,
        onPressed: provider.failedPlaylistServerIds.isNotEmpty ? provider.retryFailed : provider.load,
        onNavigateDown: focusActiveTabIfReady,
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
          TvMenuGrid(
            nodes: _nodes,
            columns: 2,
            automationInstance: 'playlists',
            onExitUp: () => _actionNode.requestFocus(),
            sections: [
              for (final group in grouped.values)
                TvMenuSection(
                  label: group.first.serverName,
                  items: [
                    for (final entry in group)
                      TvMenuItem(
                        key: _playlistKey(entry),
                        icon: Symbols.playlist_play_rounded,
                        title: entry.playlist.title,
                        value: entry.playlist.leafCount == null
                            ? entry.serverName
                            : t.playlists.itemCount(count: entry.playlist.leafCount!),
                        onSelect: () => unawaited(_open(entry)),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ],
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
