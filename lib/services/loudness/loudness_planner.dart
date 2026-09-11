import '../../media/loudness_evidence.dart';
import '../../mpv/models.dart' show AudioLoudness, ProgrammeGainLimit;

/// The canonical gain policy. Kotlin's `LoudnessDsp` carries the same numbers;
/// `scripts/loudness/prove.sh` is the proof that both land in the same place.
abstract final class LoudnessPolicy {
  static const targetLufs = -22.0;
  static const ceilingDbtp = -2.0;
  static const maxGainDb = 12.0;
  static const minGainDb = -30.0;

  /// How hard the limiter may be expected to work, in dB above the ceiling,
  /// before the gain gives way instead.
  static const maxLimiterLoadDb = 6.0;

  /// Below this the "programme" is silence or a broken measurement.
  static const minValidLufs = -60.0;
  static const maxValidTruePeakDbtp = 3.0;

  static const supportedMethodVersion = 1;

  /// The decode this client plays: native channel layout, AC-3/E-AC-3 with
  /// `target_level=-31` (video_player_screen) and mpv's default `ac3drc` of 0.
  /// A measurement taken on any other basis is a different figure.
  static const clientBasis = 'pcm-native-tl31-drc0';
}

bool _finite(double? v) => v != null && v.isFinite;

typedef ProgrammeGain = ({double gainDb, ProgrammeGainLimit limit});

/// The fixed programme gain for [evidence] and what held it down, or null when
/// the evidence may not be applied and the realtime fallback has to run.
///
/// `gain = clamp(-22 - I, -30, +12)`; when the true peak after that gain would
/// load the limiter by more than 6 dB, the gain drops by the excess. Without a
/// true peak a positive gain is held at 0 dB (DEC-111 (6)).
ProgrammeGain? planProgrammeGain(LoudnessEvidence? evidence) {
  if (evidence == null) return null;
  if (evidence.methodVersion != LoudnessPolicy.supportedMethodVersion) return null;
  if (evidence.basis != LoudnessPolicy.clientBasis) return null;
  switch (evidence.quality) {
    case LoudnessQuality.measuredFull:
      if (!evidence.coverageComplete) return null;
    case LoudnessQuality.tagTrusted:
      break;
    case LoudnessQuality.tagHint:
    case LoudnessQuality.estimated:
    case LoudnessQuality.unknown:
      return null;
  }
  if (evidence.source == LoudnessSource.realtimeEstimator || evidence.source == LoudnessSource.unknown) return null;

  final lufs = evidence.programmeLufs;
  if (!_finite(lufs) || lufs! < LoudnessPolicy.minValidLufs) return null;
  final peak = evidence.truePeakDbtp;
  if (peak != null && (!peak.isFinite || peak > LoudnessPolicy.maxValidTruePeakDbtp)) return null;

  var gain = (LoudnessPolicy.targetLufs - lufs).clamp(LoudnessPolicy.minGainDb, LoudnessPolicy.maxGainDb);
  var limit = ProgrammeGainLimit.none;
  if (peak != null) {
    final load = (peak + gain) - LoudnessPolicy.ceilingDbtp;
    if (load > LoudnessPolicy.maxLimiterLoadDb) {
      gain -= load - LoudnessPolicy.maxLimiterLoadDb;
      limit = ProgrammeGainLimit.truePeakLoad;
    }
  } else if (gain > 0) {
    // No true peak means no limiter load to check, so a boost has no vetted
    // ceiling to land under. A cut is safe either way.
    gain = 0;
    limit = ProgrammeGainLimit.missingTruePeak;
  }
  return (gainDb: gain, limit: limit);
}

/// Turns the user's switches plus whatever evidence there is into the one
/// [AudioLoudness] the audio-path arbiter applies.
///
/// Evidence only matters while levelling is on; with it off there is nothing to
/// level towards and no gain is carried.
AudioLoudness planLoudness(AudioLoudness prefs, LoudnessEvidence? evidence) {
  final programme = prefs.levelVolume ? planProgrammeGain(evidence) : null;
  return AudioLoudness(
    levelVolume: prefs.levelVolume,
    reduceLoudSounds: prefs.reduceLoudSounds,
    programmeGainDb: programme?.gainDb,
    gainLimit: programme?.limit ?? ProgrammeGainLimit.none,
  );
}
