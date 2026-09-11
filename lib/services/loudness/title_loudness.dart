import '../../mpv/models.dart' show AudioLoudness;
import '../../mpv/player/player.dart';

/// Arms the loudness path for a title that is about to open.
///
/// DEC-111 (7): evidence belongs to one title. The new title's lookup only runs
/// on its first track-selection event, after loadfile, so the previous title's
/// evidence has to go first or [AudioLoudness] gets planned against it.
Future<void> startTitleLoudness(Player player, AudioLoudness prefs) async {
  await player.setLoudnessEvidence(null);
  await player.setAudioNormalization(prefs);
}
