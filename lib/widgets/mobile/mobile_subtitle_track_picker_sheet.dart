import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_source_info.dart';
import '../overlay_sheet.dart';
import '../video_controls/helpers/track_selection_helper.dart';
import 'mobile_audio_track_picker_sheet.dart';

/// What the subtitle picker reports: a track, or `track: null` for "Uit".
typedef MobileSubtitleChoice = ({MediaSubtitleTrack? track});

/// Picks the subtitle track the detail page remembers for the next playback,
/// "Uit" on top. Null when the sheet is dismissed without a choice.
Future<MobileSubtitleChoice?> showMobileSubtitleTrackPickerSheet(
  BuildContext context, {
  required List<MediaSubtitleTrack> tracks,
  int? selectedTrackId,
  String? scopeLabel,
}) {
  return OverlaySheetController.of(context).show<MobileSubtitleChoice>(
    showDragHandle: true,
    builder: (sheetContext) => MobileSubtitleTrackPickerSheet(
      tracks: tracks,
      selectedTrackId: selectedTrackId,
      scopeLabel: scopeLabel,
      onChosen: (track) => OverlaySheetController.of(sheetContext).pop((track: track)),
    ),
  );
}

class MobileSubtitleTrackPickerSheet extends StatelessWidget {
  final List<MediaSubtitleTrack> tracks;

  /// Null means subtitles are off.
  final int? selectedTrackId;
  final String? scopeLabel;

  /// Null for "Uit".
  final ValueChanged<MediaSubtitleTrack?> onChosen;

  const MobileSubtitleTrackPickerSheet({
    super.key,
    required this.tracks,
    this.selectedTrackId,
    this.scopeLabel,
    required this.onChosen,
  });

  @override
  Widget build(BuildContext context) {
    return MobileTrackPickerFrame(
      title: t.discover.techSubtitles,
      icon: Symbols.subtitles_rounded,
      scopeLabel: scopeLabel,
      tiles: [
        TrackSelectionHelper.buildOffTile<MediaSubtitleTrack>(
          context: context,
          isSelected: selectedTrackId == null,
          onTap: () => onChosen(null),
        ),
        for (final track in tracks)
          TrackSelectionHelper.buildTrackTile<MediaSubtitleTrack>(
            context: context,
            label: track.label,
            isSelected: track.id == selectedTrackId,
            onTap: () => onChosen(track),
          ),
      ],
    );
  }
}
