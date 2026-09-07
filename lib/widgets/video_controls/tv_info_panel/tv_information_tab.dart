import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../media/ids.dart';
import '../../../media/media_item.dart';
import '../../../mpv/mpv.dart';
import '../../../utils/formatters.dart';
import '../../../utils/provider_extensions.dart';
import '../../app_icon.dart';
import '../../tv/tv_unified_layout.dart';
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

    final m = TvPanelMetrics.of(context);
    final posterWidth = m.gap(120);
    final posterHeight = m.gap(180);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(m.rowPaddingHorizontal, m.gap(8), m.rowPaddingHorizontal, m.gap(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(m.gap(8)),
            child: SizedBox(
              width: posterWidth,
              height: posterHeight,
              child: poster != null
                  ? OptimizedMediaImage.poster(
                      client: client,
                      imagePath: poster,
                      width: posterWidth,
                      height: posterHeight,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => ColoredBox(
                        color: const Color(0x22FFFFFF),
                        child: AppIcon(Symbols.movie_rounded, fill: 1, color: Colors.white38, size: m.gap(40)),
                      ),
                    )
                  : ColoredBox(
                      color: const Color(0x22FFFFFF),
                      child: AppIcon(Symbols.movie_rounded, fill: 1, color: Colors.white38, size: m.gap(40)),
                    ),
            ),
          ),
          SizedBox(width: m.gap(20)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metadata.displayTitle,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: TvSourcePickerLayout.titleFontSize * m.scale,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (metadata.displaySubtitle != null && metadata.displaySubtitle!.isNotEmpty) ...[
                  SizedBox(height: m.gap(4)),
                  Text(
                    metadata.displaySubtitle!,
                    style: TextStyle(color: TvPanelTheme.textMuted, fontSize: m.titleFontSize),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (metaParts.isNotEmpty) ...[
                  SizedBox(height: m.gap(10)),
                  Text(
                    metaParts.join('  ·  '),
                    style: TextStyle(
                      color: TvPanelTheme.textFaint,
                      fontSize: m.subtitleFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (genres.isNotEmpty) ...[
                  SizedBox(height: m.gap(6)),
                  Text(
                    genres.join(', '),
                    style: TextStyle(color: TvPanelTheme.textFaint, fontSize: m.subtitleFontSize),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (metadata.summary != null && metadata.summary!.isNotEmpty) ...[
                  SizedBox(height: m.gap(14)),
                  Text(
                    metadata.summary!,
                    style: TextStyle(color: TvPanelTheme.textMuted, fontSize: m.markValueFontSize, height: 1.45),
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
