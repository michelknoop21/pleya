/// The pickers behind Add to...: an existing playlist or collection, or a new one.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_button.dart';
import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_playlist.dart';
import '../media/media_server_client.dart';
import '../mixins/controller_disposer_mixin.dart';
import '../utils/error_message_utils.dart';
import '../utils/media_server_http_client.dart';
import 'app_icon.dart';
import 'focusable_list_tile.dart';
import 'pill_input_decoration.dart';

/// Dialog to select a playlist or create a new one.
class PlaylistSelectionDialog extends StatefulWidget {
  final MediaServerClient client;

  const PlaylistSelectionDialog({super.key, required this.client});

  @override
  State<PlaylistSelectionDialog> createState() => _PlaylistSelectionDialogState();
}

class _PlaylistSelectionDialogState extends State<PlaylistSelectionDialog> {
  static const int _pageSize = 100;

  final AbortController _abortController = AbortController();
  final ScrollController _scrollController = ScrollController();
  final List<MediaPlaylist> _playlists = [];
  bool _isLoading = false;
  String? _errorMessage;
  int? _totalCount;

  bool get _hasMore => _totalCount == null || _playlists.length < _totalCount!;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadNextPage());
  }

  @override
  void dispose() {
    _abortController.abort();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore || _isLoading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      unawaited(_loadNextPage());
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final page = await widget.client.fetchPlaylistsPage(
        playlistType: 'video',
        smart: false,
        start: _playlists.length,
        size: _pageSize,
        abort: _abortController,
      );
      if (!mounted) return;
      setState(() {
        _playlists.addAll(page.items);
        _totalCount = page.totalCount;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = friendlyError(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.playlists.selectPlaylist),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          controller: _scrollController,
          shrinkWrap: true,
          itemCount: _playlists.length + 1 + (_hasMore || _isLoading || _errorMessage != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              // Create new playlist option (always shown first)
              return ListTile(
                leading: const AppIcon(Symbols.add_rounded, fill: 1),
                title: Text(t.common.createNew),
                onTap: () => Navigator.pop(context, '_create_new'),
              );
            }

            if (index > _playlists.length) {
              if (_errorMessage != null) {
                return ListTile(
                  leading: const AppIcon(Symbols.error_rounded, fill: 1),
                  title: Text(_errorMessage!),
                  trailing: TextButton(onPressed: _loadNextPage, child: Text(t.common.retry)),
                );
              }
              if (_hasMore && !_isLoading) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) unawaited(_loadNextPage());
                });
              }
              return const Padding(
                padding: .all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final playlist = _playlists[index - 1];
            final leafCount = playlist.leafCount;
            final subtitleText = leafCount == 1 ? t.playlists.oneItem : t.playlists.itemCount(count: leafCount ?? 0);
            return ListTile(
              leading: playlist.smart
                  ? const AppIcon(Symbols.auto_awesome_rounded, fill: 1)
                  : const AppIcon(Symbols.playlist_play_rounded, fill: 1),
              title: Text(playlist.title),
              subtitle: playlist.leafCount != null ? Text(subtitleText) : null,
              onTap: playlist.smart
                  ? null // Disable smart playlists
                  : () => Navigator.pop(context, playlist.id),
              enabled: !playlist.smart,
            );
          },
        ),
      ),
      actions: [
        FocusableButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
        ),
      ],
    );
  }
}

/// Dialog to select a collection or create a new one
class CollectionSelectionDialog extends StatefulWidget {
  final MediaServerClient client;
  final String libraryId;

  const CollectionSelectionDialog({super.key, required this.client, required this.libraryId});

  @override
  State<CollectionSelectionDialog> createState() => _CollectionSelectionDialogState();
}

class _CollectionSelectionDialogState extends State<CollectionSelectionDialog> with ControllerDisposerMixin {
  static const int _pageSize = 100;

  late final _filterController = createTextEditingController();
  final _filterFocusNode = FocusNode(debugLabel: 'CollectionFilter');
  final _firstCollectionFocusNode = FocusNode(debugLabel: 'CollectionFirstItem');
  final AbortController _abortController = AbortController();
  final _scrollController = ScrollController();
  final List<MediaItem> _collections = [];
  List<MediaItem> _filteredCollections = [];
  bool _isLoading = false;
  String? _errorMessage;
  int? _totalCount;

  bool get _hasMore => _totalCount == null || _collections.length < _totalCount!;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadNextPage());
  }

  @override
  void dispose() {
    _abortController.abort();
    _scrollController.dispose();
    _filterFocusNode.dispose();
    _firstCollectionFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore || _isLoading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      unawaited(_loadNextPage());
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      while (mounted && _hasMore) {
        final page = await widget.client.fetchCollectionsPage(
          widget.libraryId,
          start: _collections.length,
          size: _pageSize,
          abort: _abortController,
        );
        if (!mounted) return;
        setState(() {
          _collections.addAll(page.items);
          _totalCount = page.totalCount;
          _applyFilter(_filterController.text);
        });
        if (_filterController.text.isEmpty || page.items.isEmpty) break;
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = friendlyError(e);
        _isLoading = false;
      });
    }
  }

  void _onFilterChanged(String query) {
    setState(() {
      _applyFilter(query);
    });
    if (query.isNotEmpty && _hasMore) {
      unawaited(_loadNextPage());
    }
  }

  void _applyFilter(String query) {
    final lower = query.toLowerCase();
    _filteredCollections = lower.isEmpty
        ? List.of(_collections)
        : _collections.where((c) => (c.title ?? '').toLowerCase().contains(lower)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.collections.selectCollection),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: .min,
          children: [
            if (_collections.length >= 10) ...[
              FocusableTextField(
                controller: _filterController,
                focusNode: _filterFocusNode,
                autofocus: true,
                onNavigateDown: _firstCollectionFocusNode.requestFocus,
                decoration: pillInputDecoration(
                  context,
                  hintText: t.collections.searchCollections,
                  prefixIcon: const Icon(Symbols.search_rounded, size: 20),
                ),
                onChanged: _onFilterChanged,
              ),
              const SizedBox(height: 8),
            ],
            Flexible(
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                itemCount: _filteredCollections.length + 1 + (_hasMore || _isLoading || _errorMessage != null ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return FocusableListTile(
                      focusNode: _firstCollectionFocusNode,
                      autofocus: _collections.length < 10,
                      leading: const AppIcon(Symbols.add_rounded, fill: 1),
                      title: Text(t.common.createNew),
                      onTap: () => Navigator.pop(context, '_create_new'),
                    );
                  }

                  if (index > _filteredCollections.length) {
                    if (_errorMessage != null) {
                      return FocusableListTile(
                        leading: const AppIcon(Symbols.error_rounded, fill: 1),
                        title: Text(_errorMessage!),
                        onTap: _loadNextPage,
                      );
                    }
                    if (_hasMore && !_isLoading) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) unawaited(_loadNextPage());
                      });
                    }
                    return const Padding(
                      padding: .all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final collection = _filteredCollections[index - 1];
                  return FocusableListTile(
                    leading: const AppIcon(Symbols.collections_rounded, fill: 1),
                    title: Text(collection.title ?? ''),
                    subtitle: collection.childCount != null
                        ? Text(t.playlists.itemCount(count: collection.childCount!))
                        : null,
                    onTap: () => Navigator.pop(context, collection.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        FocusableButton(
          onPressed: () => Navigator.pop(context),
          child: TextButton(onPressed: () => Navigator.pop(context), child: Text(t.common.cancel)),
        ),
      ],
    );
  }
}
