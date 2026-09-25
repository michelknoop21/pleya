import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_source_info.dart';
import '../../theme/mono_tokens.dart';
import '../app_icon.dart';
import '../bottom_sheet_header.dart';
import '../overlay_sheet.dart';
import '../video_controls/helpers/track_selection_helper.dart';

Future<MediaAudioTrack?> showMobileAudioTrackPickerSheet(
  BuildContext context, {
  required List<MediaAudioTrack> tracks,
  int? selectedTrackId,
}) {
  return OverlaySheetController.of(context).show<MediaAudioTrack>(
    showDragHandle: true,
    builder: (sheetContext) => MobileAudioTrackPickerSheet(
      tracks: tracks,
      selectedTrackId: selectedTrackId,
      onChosen: (track) => OverlaySheetController.of(sheetContext).pop(track),
    ),
  );
}

class MobileAudioTrackSelector extends StatelessWidget {
  final List<MediaAudioTrack> tracks;
  final int? selectedTrackId;
  final VoidCallback? onPressed;

  const MobileAudioTrackSelector({super.key, required this.tracks, this.selectedTrackId, this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final tk = tokens(context);
    final languages = <String>[];
    for (final track in tracks) {
      final label = track.label.primary;
      if (!languages.contains(label)) languages.add(label);
    }

    return Material(
      color: tk.surfaceElevated,
      borderRadius: BorderRadius.circular(tk.radiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(tk.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const AppIcon(Symbols.audiotrack_rounded, fill: 1),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.videoControls.audioLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      languages.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tk.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (onPressed != null) ...[const SizedBox(width: 8), const AppIcon(Symbols.chevron_right_rounded)],
            ],
          ),
        ),
      ),
    );
  }
}

class MobileAudioTrackPickerSheet extends StatelessWidget {
  final List<MediaAudioTrack> tracks;
  final int? selectedTrackId;
  final ValueChanged<MediaAudioTrack> onChosen;

  const MobileAudioTrackPickerSheet({super.key, required this.tracks, this.selectedTrackId, required this.onChosen});

  @override
  Widget build(BuildContext context) {
    final height = (80.0 + tracks.length * 64.0).clamp(180.0, MediaQuery.sizeOf(context).height * 0.7);
    return SizedBox(
      height: height,
      child: Column(
        children: [
          BottomSheetHeader(title: t.videoControls.audioLabel, icon: Symbols.audiotrack_rounded),
          Expanded(
            child: ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return TrackSelectionHelper.buildTrackTile<MediaAudioTrack>(
                  context: context,
                  label: track.label,
                  isSelected: track.id == selectedTrackId,
                  onTap: () => onChosen(track),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
