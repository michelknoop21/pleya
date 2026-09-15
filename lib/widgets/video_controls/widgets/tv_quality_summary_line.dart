import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../mpv/mpv.dart';
import '../../../utils/language_codes.dart';
import '../../../utils/player_utils.dart';
import '../../app_icon.dart';

/// The TV OSD's persistent quality line under the title (mockup 18):
/// resolution, video codec, audio channels, the active subtitle language and
/// a Direct play/Transcode pill.
///
/// Reads mpv's live properties and the live track selection rather than the
/// server-declared `MediaVersion`, the same choice [TvInformationTab] already
/// made for its own metadata line: a transcode can change what actually
/// reaches the player, so only the live values are guaranteed to match what
/// is on screen right now.
class TvQualitySummaryLine extends StatefulWidget {
  final Player player;
  final bool isTranscoding;

  const TvQualitySummaryLine({super.key, required this.player, required this.isTranscoding});

  @override
  State<TvQualitySummaryLine> createState() => _TvQualitySummaryLineState();
}

class _TvQualitySummaryLineState extends State<TvQualitySummaryLine> {
  String? _resolution;
  String? _videoCodec;

  @override
  void initState() {
    super.initState();
    _loadVideoProps();
  }

  @override
  void didUpdateWidget(covariant TvQualitySummaryLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) _loadVideoProps();
  }

  Future<void> _loadVideoProps() async {
    final quality = await readLiveVideoQuality(widget.player);
    if (!mounted) return;
    setState(() {
      _resolution = quality.resolution;
      _videoCodec = quality.videoCodec;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TrackSelection>(
      stream: widget.player.streams.track,
      initialData: widget.player.state.track,
      builder: (context, snapshot) {
        final selection = snapshot.data;
        final channels = selection?.audio?.channelsCount;
        final subtitleLanguage = languageDisplayName(selection?.subtitle?.language);

        final parts = <String>[
          ?_resolution,
          ?_videoCodec,
          if (channels != null && channels > 0) audioChannelLabel(channels),
        ];

        if (parts.isEmpty && subtitleLanguage == null) return const SizedBox.shrink();

        return Row(
          mainAxisSize: .min,
          children: [
            if (parts.isNotEmpty)
              Flexible(
                child: Text(
                  parts.join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
            if (subtitleLanguage != null) ...[
              const SizedBox(width: 10),
              const AppIcon(Symbols.closed_caption_rounded, fill: 1, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  subtitleLanguage,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
            ],
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white38),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.isTranscoding ? t.nowWatching.transcode : t.nowWatching.directPlay,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: .w600),
              ),
            ),
          ],
        );
      },
    );
  }
}
