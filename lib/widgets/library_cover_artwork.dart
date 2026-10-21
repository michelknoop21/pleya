import 'dart:async';

import 'package:flutter/material.dart';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_playlist.dart';
import '../media/media_server_client.dart';
import '../utils/media_server_http_client.dart';
import 'optimized_media_image.dart';

/// Source-owned cover, otherwise the first four real list positions.
class LibraryCoverArtwork extends StatefulWidget {
  const LibraryCoverArtwork({super.key, required this.item, required this.client, required this.fallbackIcon});

  final Object item;
  final MediaServerClient? client;
  final IconData fallbackIcon;

  @override
  State<LibraryCoverArtwork> createState() => _LibraryCoverArtworkState();
}

class _LibraryCoverArtworkState extends State<LibraryCoverArtwork> {
  AbortController? _abort;
  List<MediaItem> _members = const [];
  int _generation = 0;

  (String, int?, String?) get _identity => switch (widget.item) {
    final MediaPlaylist item => (item.globalKey, item.updatedAt, item.thumbPath),
    final MediaItem item => (item.globalKey, item.updatedAt, item.thumbPath),
    _ => throw ArgumentError('A cover requires a collection or playlist'),
  };

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(LibraryCoverArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = switch (oldWidget.item) {
      final MediaPlaylist item => (item.globalKey, item.updatedAt, item.thumbPath),
      final MediaItem item => (item.globalKey, item.updatedAt, item.thumbPath),
      _ => null,
    };
    if (previous != _identity || oldWidget.client != widget.client) unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _abort?.abort();
    _members = const [];
    final client = widget.client;
    if (client == null || _identity.$3?.isNotEmpty == true) return;
    final abort = _abort = AbortController();
    try {
      final page = switch (widget.item) {
        final MediaPlaylist item => await client.fetchPlaylistPage(item.id, start: 0, size: 4, abort: abort),
        final MediaItem item when item.kind == MediaKind.playlist => await client.fetchPlaylistPage(
          item.id,
          start: 0,
          size: 4,
          abort: abort,
        ),
        final MediaItem item => await client.fetchCollectionPage(
          item.id,
          start: 0,
          size: 4,
          abort: abort,
          libraryId: item.libraryId,
          libraryTitle: item.libraryTitle,
        ),
        _ => throw ArgumentError('Unsupported cover'),
      };
      if (!mounted || abort.isAborted || generation != _generation) return;
      // Keep slots and duplicates: an unavailable poster is not a new order.
      setState(() => _members = page.items.take(4).toList());
    } catch (_) {
      // Decorative artwork failure never disables the collection's real action.
      if (!mounted || abort.isAborted || generation != _generation) return;
      setState(() => _members = const []);
    }
  }

  @override
  void dispose() {
    _abort?.abort();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final own = _identity.$3;
    if (own?.isNotEmpty == true || _members.isEmpty) {
      return OptimizedMediaImage(client: widget.client, imagePath: own, fallbackIcon: widget.fallbackIcon);
    }
    return LibraryCoverCollage(members: _members, client: widget.client, fallbackIcon: widget.fallbackIcon);
  }
}

/// The approved 1/2/3/4 composition; never pads a short list by repeating it.
class LibraryCoverCollage extends StatelessWidget {
  const LibraryCoverCollage({super.key, required this.members, required this.client, required this.fallbackIcon});

  final List<MediaItem> members;
  final MediaServerClient? client;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final count = members.length.clamp(0, 4);
      if (count == 0) return OptimizedMediaImage(client: client, imagePath: null, fallbackIcon: fallbackIcon);
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      return Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < count; i++)
            Positioned.fromRect(
              rect: switch (count) {
                1 => Rect.fromLTWH(0, 0, width, height),
                2 => Rect.fromLTWH(i * width / 2, 0, width / 2, height),
                3 when i == 0 => Rect.fromLTWH(0, 0, width * 2 / 3, height),
                3 => Rect.fromLTWH(width * 2 / 3, (i - 1) * height / 2, width / 3, height / 2),
                _ => Rect.fromLTWH((i % 2) * width / 2, (i ~/ 2) * height / 2, width / 2, height / 2),
              },
              child: ColoredBox(
                color: Colors.black,
                child: OptimizedMediaImage(
                  client: client,
                  imagePath: members[i].serverId != null && members[i].serverId != client?.serverId.value
                      ? null
                      : members[i].posterThumb(),
                  fit: count == 2 ? BoxFit.contain : BoxFit.cover,
                  requestSize: count == 2 ? Size(height * 2 / 3, height) : null,
                  fallbackIcon: fallbackIcon,
                ),
              ),
            ),
        ],
      );
    },
  );
}
