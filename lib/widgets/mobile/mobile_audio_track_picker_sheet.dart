import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_source_info.dart';
import '../../theme/mono_tokens.dart';
import '../bottom_sheet_header.dart';
import '../overlay_sheet.dart';
import '../video_controls/helpers/track_selection_helper.dart';

/// Picks the audio track the detail page remembers for the next playback
/// (D-02). Choosing only reports the track; the caller stores it.
Future<MediaAudioTrack?> showMobileAudioTrackPickerSheet(
  BuildContext context, {
  required List<MediaAudioTrack> tracks,
  int? selectedTrackId,
  String? scopeLabel,
}) {
  return OverlaySheetController.of(context).show<MediaAudioTrack>(
    showDragHandle: true,
    builder: (sheetContext) => MobileAudioTrackPickerSheet(
      tracks: tracks,
      selectedTrackId: selectedTrackId,
      scopeLabel: scopeLabel,
      onChosen: (track) => OverlaySheetController.of(sheetContext).pop(track),
    ),
  );
}

class MobileAudioTrackPickerSheet extends StatelessWidget {
  final List<MediaAudioTrack> tracks;
  final int? selectedTrackId;

  /// "Sintel · geldt voor deze film": which title the choice is kept for.
  final String? scopeLabel;
  final ValueChanged<MediaAudioTrack> onChosen;

  const MobileAudioTrackPickerSheet({
    super.key,
    required this.tracks,
    this.selectedTrackId,
    this.scopeLabel,
    required this.onChosen,
  });

  @override
  Widget build(BuildContext context) {
    return MobileTrackPickerFrame(
      title: t.videoControls.audioLabel,
      icon: Symbols.audiotrack_rounded,
      scopeLabel: scopeLabel,
      tiles: [
        for (final track in tracks)
          TrackSelectionHelper.buildTrackTile<MediaAudioTrack>(
            context: context,
            label: track.label,
            isSelected: track.id == selectedTrackId,
            onTap: () => onChosen(track),
          ),
      ],
    );
  }
}

/// Header with the scope line, the track rows (checkmark on the right) and
/// the "remembered, not played" note, shared by the audio and subtitle
/// pickers (D-02).
class MobileTrackPickerFrame extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? scopeLabel;
  final List<Widget> tiles;

  const MobileTrackPickerFrame({
    super.key,
    required this.title,
    required this.icon,
    this.scopeLabel,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    final height = (140.0 + tiles.length * 64.0).clamp(220.0, MediaQuery.sizeOf(context).height * 0.7);
    return SizedBox(
      height: height,
      child: Column(
        children: [
          BottomSheetHeader(title: title, subtitle: scopeLabel, icon: icon),
          Expanded(child: ListView(children: tiles)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Text(t.discover.trackChoiceNote, style: TextStyle(fontSize: 13, color: tokens(context).textMuted)),
          ),
        ],
      ),
    );
  }
}
