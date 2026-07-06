import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../mpv/mpv.dart';
import '../../../utils/formatters.dart';
import '../../../utils/provider_extensions.dart';
import '../../app_icon.dart';
import '../../optimized_media_image.dart';
import 'tv_panel_widgets.dart';

/// "Information" tab: poster, title/subtitle, summary and a metadata line.
/// Shows only what the [MediaItem] and live mpv properties already provide —
/// no extra network fetches.
class TvInformationTab extends StatefulWidget {
  final Player player;
  final MediaItem metadata;

  const TvInformationTab({super.key, required this.player, required this.metadata});

  @override
  State<TvInformationTab> createState() => _TvInformationTabState();
}

class _TvInformationTabState extends State<TvInformationTab> {
  String? _resolution;
  String? _videoCodec;

  @override
  void initState() {
    super.initState();
    _loadVideoProps();
  }

  Future<void> _loadVideoProps() async {
    final height = await widget.player.getProperty('height');
    final codec = await widget.player.getProperty('video-codec');
    if (!mounted) return;
    final h = int.tryParse(height ?? '');
    setState(() {
      _resolution = h != null && h > 0 ? '${h}p' : null;
      _videoCodec = (codec != null && codec.trim().isNotEmpty) ? codec.trim().toUpperCase() : null;
    });
  }

  List<String> _metadataParts() {
    final parts = <String>[];
    final durationMs = widget.metadata.durationMs;
    if (durationMs != null && durationMs > 0) parts.add(formatDurationTextual(durationMs));
    final year = widget.metadata.year;
    if (year != null) parts.add('$year');
    if (_resolution != null) parts.add(_resolution!);
    if (_videoCodec != null) parts.add(_videoCodec!);

    final selectedAudio = widget.player.state.track.audio;
    final channels = selectedAudio?.channelsCount;
    if (channels != null && channels > 0) parts.add(_channelLabel(channels));

    final rating = widget.metadata.contentRating;
    if (rating != null && rating.isNotEmpty) parts.add(rating);
    return parts;
  }

  String _channelLabel(int channels) {
    return switch (channels) {
      1 => 'Mono',
      2 => 'Stereo',
      6 => '5.1',
      8 => '7.1',
      _ => '$channels ch',
    };
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.metadata;
    final client = context.tryGetMediaClientForServer(serverIdOrNull(metadata.serverId));
    final poster = metadata.posterThumb();
    final genres = metadata.genres ?? const <String>[];
    final metaParts = _metadataParts();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 120,
              height: 180,
              child: poster != null
                  ? OptimizedMediaImage.poster(
                      client: client,
                      imagePath: poster,
                      width: 120,
                      height: 180,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: Color(0x22FFFFFF),
                        child: AppIcon(Symbols.movie_rounded, fill: 1, color: Colors.white38, size: 40),
                      ),
                    )
                  : const ColoredBox(
                      color: Color(0x22FFFFFF),
                      child: AppIcon(Symbols.movie_rounded, fill: 1, color: Colors.white38, size: 40),
                    ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata.displayTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (metadata.displaySubtitle != null && metadata.displaySubtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    metadata.displaySubtitle!,
                    style: const TextStyle(color: TvPanelTheme.textMuted, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (metaParts.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    metaParts.join('  ·  '),
                    style: const TextStyle(color: TvPanelTheme.textFaint, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
                if (genres.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    genres.join(', '),
                    style: const TextStyle(color: TvPanelTheme.textFaint, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (metadata.summary != null && metadata.summary!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    metadata.summary!,
                    style: const TextStyle(color: TvPanelTheme.textMuted, fontSize: 14, height: 1.45),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
