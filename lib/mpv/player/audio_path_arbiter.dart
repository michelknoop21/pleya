import '../models.dart' show AudioLoudness;

/// What the user (and the output coordinator) asked for.
class AudioPathRequest {
  const AudioPathRequest({this.passthrough = false, this.normalization = AudioLoudness.none, this.rate = 1.0});

  final bool passthrough;
  final AudioLoudness normalization;
  final double rate;

  AudioPathRequest copyWith({bool? passthrough, AudioLoudness? normalization, double? rate}) => AudioPathRequest(
    passthrough: passthrough ?? this.passthrough,
    normalization: normalization ?? this.normalization,
    rate: rate ?? this.rate,
  );
}

/// What actually applies once the requests have been arbitrated.
class AudioPathState {
  const AudioPathState({required this.passthrough, required this.normalization});

  final bool passthrough;
  final AudioLoudness normalization;
}

/// Resolves conflicting audio-path requests into the one state mpv can be in.
///
/// Two rules, and they point in opposite directions:
/// 1. A playback rate other than 1.0 takes the bitstream down, because mpv
///    cannot scaletempo a compressed stream and would silently keep playing at
///    1x. With PCM back in the chain, loudness normalization can run again.
/// 2. A running bitstream takes loudness normalization down, because `loudnorm`
///    is an `af` filter and only works on decoded audio. DEC-013 settles that
///    conflict in favour of the bitstream: the request is kept, its application
///    is suspended.
AudioPathState resolveAudioPath(AudioPathRequest request) {
  final passthrough = request.passthrough && request.rate == 1.0;
  return AudioPathState(
    passthrough: passthrough,
    normalization: passthrough ? AudioLoudness.none : request.normalization,
  );
}

/// The writes that take mpv from the state it is in to the resolved one, in the
/// order they have to happen.
class AudioPathTransition {
  const AudioPathTransition({
    required this.target,
    required this.togglePassthrough,
    required this.normalization,
    required this.normalizationFirst,
    required this.suspendsNormalization,
  });

  /// The resolved state this transition moves to.
  final AudioPathState target;

  /// Whether the bitstream has to be switched on or off.
  final bool togglePassthrough;

  /// The normalization mode still to be written, or null when mpv has it.
  final AudioLoudness? normalization;

  /// Whether the filter write comes before the bitstream toggle.
  ///
  /// Direction-dependent, and both directions are load-bearing. Going in, `af`
  /// has to be empty *before* `audio-spdif` is set: the other order makes mpv
  /// log a passthrough complaint, which the output coordinator reads as a
  /// receiver that cannot take the format and then remembers for the rest of
  /// the app run. Coming out, the bitstream has to be down before the filter
  /// goes back on, for the same reason.
  final bool normalizationFirst;

  /// True when this transition is the moment the user's loudness setting stops
  /// being applied. The one moment worth telling them about; a reconcile that
  /// changes nothing must stay quiet.
  final bool suspendsNormalization;
}

/// Holds the requested audio path, resolves it, and tracks what mpv was
/// actually given.
///
/// This lives next to the player rather than in the output coordinator because
/// passthrough is requested from two sides (the coordinator and `setRate`), and
/// only the player sees both.
class AudioPathArbiter {
  AudioPathRequest _requested = const AudioPathRequest();

  /// What mpv was last given, or null while that is unknown.
  ///
  /// Both start at null rather than at an assumed default: the mpv core is
  /// static and shared between player instances, so a fresh arbiter cannot
  /// assume the filter chain is empty or the bitstream off. They are filled
  /// only after a write has returned, so a failed write is retried instead of
  /// being skipped as "no change".
  AudioLoudness? _appliedNormalization;
  bool? _appliedPassthrough;

  AudioPathRequest get requested => _requested;

  /// The resolved state, whether or not mpv has it yet.
  AudioPathState get effective => resolveAudioPath(_requested);

  /// What mpv was last given for the bitstream.
  bool? get appliedPassthrough => _appliedPassthrough;

  /// True while the user asked for normalization and the bitstream is holding
  /// it back.
  bool get normalizationSuspended => _requested.normalization != effective.normalization;

  /// Records a new request and returns the transition that realises it.
  AudioPathTransition request({bool? passthrough, AudioLoudness? normalization, double? rate}) {
    final wasSuspended = normalizationSuspended;
    _requested = _requested.copyWith(passthrough: passthrough, normalization: normalization, rate: rate);
    final target = effective;
    return AudioPathTransition(
      target: target,
      togglePassthrough: target.passthrough != _appliedPassthrough,
      normalization: target.normalization == _appliedNormalization ? null : target.normalization,
      normalizationFirst: target.passthrough,
      suspendsNormalization: normalizationSuspended && !wasSuspended,
    );
  }

  /// Caches a normalization mode as written. Call only after the write
  /// returned.
  void markNormalizationApplied(AudioLoudness mode) => _appliedNormalization = mode;

  /// Caches the bitstream state as written. Call only after the write returned.
  void markPassthroughApplied(bool enabled) => _appliedPassthrough = enabled;
}
