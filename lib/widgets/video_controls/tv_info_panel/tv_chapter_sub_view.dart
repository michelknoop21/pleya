import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../media/media_source_info.dart';
import '../../../mpv/mpv.dart';
import '../../../services/download_storage_service.dart';
import '../../../utils/formatters.dart';
import '../../../utils/player_utils.dart';
import '../../../utils/provider_extensions.dart';
import '../../app_icon.dart';
import '../../optimized_media_image.dart';
import '../widgets/media_selector_thumbnail.dart';
import 'tv_panel_widgets.dart';

/// The chapter list as a panel sub-view: two columns of rows with a thumbnail,
/// the title and the start time; the running chapter is marked. Choosing one
/// seeks and returns to the Video tab; the panel stays open.
class TvChapterSubView extends StatelessWidget {
  final Player player;
  final List<MediaChapter> chapters;
  final String? serverId;
  final FocusNode firstFocusNode;
  final Future<void> Function(Duration)? onSeekToChapter;
  final VoidCallback onDone;

  const TvChapterSubView({
    super.key,
    required this.player,
    required this.chapters,
    required this.serverId,
    required this.firstFocusNode,
    required this.onSeekToChapter,
    required this.onDone,
  });

  Future<void> _jumpTo(Duration position) async {
    final clamped = clampSeekPosition(player, position);
    await (onSeekToChapter ?? player.seek)(clamped);
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty) {
      return Center(
        child: Text(t.videoControls.noChaptersAvailable, style: const TextStyle(color: TvPanelTheme.textMuted)),
      );
    }
    return StreamBuilder<Duration>(
      stream: player.streams.position,
      initialData: player.state.position,
      builder: (context, snapshot) {
        final current = MediaChapter.indexAtPosition(snapshot.data ?? Duration.zero, chapters);
        final half = (chapters.length / 2).ceil();
        final rows = List<Widget>.generate(chapters.length, (i) => _row(context, i, current == i));
        return TvPanelColumns(
          left: [TvPanelGroup(children: rows.sublist(0, half))],
          right: [if (half < chapters.length) TvPanelGroup(children: rows.sublist(half))],
        );
      },
    );
  }

  Widget _row(BuildContext context, int index, bool isCurrent) {
    final chapter = chapters[index];
    final localThumbPath = serverId != null && chapter.thumb != null
        ? DownloadStorageService.instance.getArtworkPathSync(ServerId(serverId!), chapter.thumb!)
        : null;
    final thumb = chapter.thumb == null
        ? null
        : MediaSelectorThumbnail(
            width: 72,
            height: 40,
            thumbnail: OptimizedMediaImage.thumb(
              client: context.tryGetMediaClientForServer(serverIdOrNull(serverId)),
              imagePath: chapter.thumb,
              localFilePath: localThumbPath,
              width: 72,
              height: 40,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) =>
                  const AppIcon(Symbols.image_rounded, fill: 1, color: Colors.white54, size: 24),
            ),
            isCurrent: isCurrent,
            borderColor: Colors.white,
          );
    return TvPanelRow.choice(
      // The first row of the list is the one the sub-view lands on; the
      // running chapter is scrolled to by its own column when off screen.
      focusNode: index == 0 ? firstFocusNode : null,
      leading: thumb,
      title: '${index + 1}. ${chapter.label}',
      subtitle: formatDurationTimestamp(chapter.startTime),
      selected: isCurrent,
      autofocus: false,
      onSelect: () => unawaited(_jumpTo(chapter.startTime)),
    );
  }
}
