import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../widgets/app_icon.dart';

/// Video, audio and subtitles of the item that plays next, as the `.tech`
/// table of D-01 (DEC-140). A row with a tap handler draws its value in white
/// with a chevron; a row without one (a single audio track) is plain text.
/// Rows without a label are left out, and no labels at all draws nothing.
class DetailTechTable extends StatelessWidget {
  const DetailTechTable({
    super.key,
    required this.videoLabel,
    required this.audioLabel,
    this.onAudioTap,
    required this.subtitleLabel,
    this.onSubtitleTap,
    this.heading,
  });

  final String? videoLabel;
  final String? audioLabel;
  final VoidCallback? onAudioTap;
  final String? subtitleLabel;
  final VoidCallback? onSubtitleTap;

  /// Names the episode the table describes on a season page.
  final String? heading;

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (videoLabel != null) _TechRow(name: t.fileInfo.video, value: videoLabel!),
      if (audioLabel != null) _TechRow(name: t.fileInfo.audio, value: audioLabel!, onTap: onAudioTap),
      if (subtitleLabel != null) _TechRow(name: t.discover.techSubtitles, value: subtitleLabel!, onTap: onSubtitleTap),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final divider = Divider(height: 1, thickness: 1, color: onSurface.withValues(alpha: 0.08));
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (heading != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(heading!, style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.5))),
          ),
        for (var i = 0; i < rows.length; i++) ...[if (i > 0) divider, rows[i]],
      ],
    );
  }
}

class _TechRow extends StatelessWidget {
  const _TechRow({required this.name, required this.value, this.onTap});

  final String name;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selectable = onTap != null;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // At least 44 pt high, the iOS minimum for a tap target.
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 124,
              child: Text(name, style: TextStyle(fontSize: 15, color: onSurface.withValues(alpha: 0.7))),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: .ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selectable ? FontWeight.w700 : FontWeight.w500,
                  color: onSurface,
                ),
              ),
            ),
            if (selectable) AppIcon(Symbols.chevron_right_rounded, size: 18, color: onSurface.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
    if (!selectable) return row;
    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
