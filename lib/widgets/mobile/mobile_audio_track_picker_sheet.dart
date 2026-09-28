import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_source_info.dart';
import '../../theme/mono_tokens.dart';
import '../bottom_sheet_header.dart';
import '../overlay_sheet.dart';
import '../video_controls/helpers/track_selection_helper.dart';

/// Picks the audio track the detail page hands to the next playback
/// (D-02). Choosing only reports the track; the caller stores it.
Future<MediaAudioTrack?> showMobileAudioTrackPickerSheet(
  BuildContext context, {
  required List<MediaAudioTrack> tracks,
  int? selectedTrackId,
  String? scopeLabel,
  bool remembered = true,
}) {
  return OverlaySheetController.of(context).show<MediaAudioTrack>(
    showDragHandle: true,
    builder: (sheetContext) => MobileAudioTrackPickerSheet(
      tracks: tracks,
      selectedTrackId: selectedTrackId,
      scopeLabel: scopeLabel,
      remembered: remembered,
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

  /// Whether the pick is stored ("per serie onthouden"); picks the note.
  final bool remembered;

  const MobileAudioTrackPickerSheet({
    super.key,
    required this.tracks,
    this.selectedTrackId,
    this.scopeLabel,
    this.remembered = true,
    required this.onChosen,
  });

  @override
  Widget build(BuildContext context) {
    return MobileTrackPickerFrame(
      title: t.videoControls.audioLabel,
      icon: Symbols.audiotrack_rounded,
      scopeLabel: scopeLabel,
      remembered: remembered,
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
/// the note on what the pick does, shared by the audio and subtitle pickers
/// (D-02). With [remembered] off the pick is not stored and only rides along
/// when playback starts from the page, below the profile language.
class MobileTrackPickerFrame extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? scopeLabel;
  final bool remembered;
  final List<Widget> tiles;

  const MobileTrackPickerFrame({
    super.key,
    required this.title,
    required this.icon,
    this.scopeLabel,
    this.remembered = true,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    // Sized to its content, so a longer note never pushes a track row out
    // of view; a long list scrolls within 70% of the screen.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(title: title, subtitle: scopeLabel, icon: icon),
          Flexible(child: ListView(shrinkWrap: true, children: tiles)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Text(
              remembered ? t.discover.trackChoiceNote : t.discover.trackChoiceNoteOnce,
              style: TextStyle(fontSize: 13, color: tokens(context).textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
