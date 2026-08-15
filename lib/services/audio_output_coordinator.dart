import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../mpv/models.dart' show AudioTrack, PlayerLog, TrackSelection;
import '../mpv/player/player.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import 'apple_audio_session_service.dart';
import 'audio_output_decision.dart';
import 'settings_service.dart';

/// Keeps the audio output path in step with the route, the track and the
/// user's setting.
///
/// Two things have to happen in order, which is the whole reason this is a
/// separate object rather than a few lines in the player screen:
///
/// 1. The Apple audio session opts into multichannel content *before* mpv
///    initialises its audio output. `ao_audiounit` samples the route once at
///    init; if it sees two channels it hard-downmixes and no later setting
///    recovers the missing channels.
/// 2. Only then are `audio-channels` and `audio-spdif` written, so the AO
///    comes up on a route that is already as wide as it will get.
///
/// Route changes (AirPods in/out, AirPlay, Spatial Audio toggled in Control
/// Centre) re-run the same sequence. Rewriting `audio-channels` forces an AO
/// reload, which is audible, so changes are debounced and skipped while the
/// player is buffering.
class AudioOutputCoordinator {
  AudioOutputCoordinator({required this.player, required this.settings, this.onPassthroughUnavailable});

  /// Called once when a bitstream attempt is abandoned, so the player can say
  /// so instead of silently degrading.
  final void Function()? onPassthroughUnavailable;

  /// Routes where bitstreaming was tried and demonstrably failed, keyed by
  /// port. Static so it survives one title ending and the next starting; an
  /// AVR that cannot take E-AC3 will not change its mind between episodes.
  ///
  /// Per route, not global: a receiver refusing a bitstream says nothing about
  /// AirPods, and blocking both would throw away Atmos where it does work.
  static final Set<String> _bitstreamBlocked = {};

  @visibleForTesting
  static void resetBitstreamBlocksForTest() => _bitstreamBlocked.clear();

  /// mpv's own verdict that the compressed path did not come up. The renderer
  /// failing is the one thing we cannot predict from the route, so this is the
  /// signal the whole fallback hangs on.
  ///
  /// Deliberately narrow. "audiounit does not support spdif formats" is *not*
  /// a failure — it is mpv falling through to the avfoundation AO, which is how
  /// the bitstream path is meant to start. Matching it would kill passthrough
  /// on every attempt.
  static final RegExp _passthroughFailure = RegExp(
    r'passthrough (disabled|failed)|renderer failure',
    caseSensitive: false,
  );

  @visibleForTesting
  static bool isPassthroughFailureLog(String text) => _passthroughFailure.hasMatch(text);

  /// mpv announcing that it has opened an audio output, as in
  /// `AO: [avfoundation] 192000Hz stereo 2ch spdif-eac3`.
  ///
  /// This is the moment the readback below becomes meaningful. A fixed timer
  /// misses it: on a device where the start ran long the AO only came up after
  /// four seconds and the probe logged three times `unknown`.
  static final RegExp _audioOutputOpened = RegExp(r'^\s*AO:\s*\[');

  @visibleForTesting
  static bool isAudioOutputOpenedLog(String text) => _audioOutputOpened.hasMatch(text);

  /// How long playback may sit still with a bitstream running before it counts
  /// as a stall. Long enough to survive a slow start, short enough that nobody
  /// reaches for the remote first.
  static const _stallTimeout = Duration(seconds: 3);

  /// How often the position is sampled while a bitstream is running.
  ///
  /// Separate from [_stallTimeout] on purpose. Sampling *at* the timeout meant
  /// two ticks were needed to see anything stand still, so a 5s timeout cost
  /// between 5 and 10 seconds of silence — measured at 14.5s on an Apple TV,
  /// because the AO also takes its time coming up before the first tick counts.
  /// Sampling every second and counting consecutive identical positions puts
  /// detection just over [_stallTimeout] instead of at twice it.
  static const _stallSampleInterval = Duration(seconds: 1);

  /// The coordinator for the playback session currently on screen, or null
  /// when nothing is playing.
  ///
  /// The player sheets sit four widget layers below the player screen, and
  /// they need two things from here: the resolved output path to show, and a
  /// way to re-apply after the user changes the mode. Threading a callback
  /// down every layer for that would be more plumbing than the feature is
  /// worth. Exactly one playback session exists at a time, which is what makes
  /// this safe — [dispose] only clears it if it is still the active one, so an
  /// old session tearing down cannot orphan a new one.
  static AudioOutputCoordinator? current;

  final Player player;
  final SettingsService settings;

  /// Channel layouts offered to mpv, widest first, on routes that accept more
  /// than stereo. mpv picks the first the output supports.
  static const _multichannelLayouts = '7.1,5.1,stereo';
  static const _stereoLayout = 'stereo';

  /// Long enough to coalesce the burst of notifications a single route change
  /// produces, short enough that the badge still feels immediate.
  static const _routeSettleDelay = Duration(milliseconds: 500);

  /// How long mpv gets to bring the new audio output up before we read back
  /// what it settled on, when no `AO:` log line arrives to say it is ready.
  static const _outputVerifyDelay = Duration(seconds: 2);

  /// How often the readback is retried while mpv still answers with nothing.
  static const _outputVerifyRetry = Duration(seconds: 1);

  /// How many times the readback may find an empty answer before it gives up
  /// and logs the emptiness. Bounded so a player that never opens an AO does
  /// not leave a timer running for the rest of the session.
  static const _maxOutputVerifyAttempts = 10;

  /// How many times a pending apply may wait for playback to stop buffering.
  ///
  /// Deferring while buffering avoids turning a hitch into a stall, but the
  /// route change is often what *caused* the buffering — AirPods dropped, the
  /// AirPlay target vanished, the receiver stopped accepting the bitstream. In
  /// that case waiting for a settled player waits forever and the fallback
  /// route never gets applied, which is the failure this bound exists to stop.
  static const _maxBufferingDeferrals = 6;

  StreamSubscription<AppleAudioRoute>? _routeSub;
  StreamSubscription<TrackSelection>? _trackSub;
  StreamSubscription<PlayerLog>? _logSub;
  Timer? _stallWatchdog;
  Duration? _lastSeenPosition;

  /// How long the position has stood still across consecutive samples.
  Duration _stalledFor = Duration.zero;
  Timer? _settleTimer;
  Timer? _verifyTimer;

  /// The decision whose output is still to be measured, or null when the
  /// measurement is done. Doubles as the de-duplication: an AO reload that
  /// belongs to no decision change is ignored.
  AudioOutputDecision? _pendingVerification;

  /// How often the readback found mpv still without an AO.
  int _verifyAttempts = 0;

  /// Bumped per output decision, so a late reading can tell whether it still
  /// describes the state that asked for it.
  int _verifyGeneration = 0;

  VerifiedAudioOutput? _verifiedOutput;

  /// What mpv was last measured to be doing, as opposed to what was asked of
  /// it. Ground truth for anything that has to report the real output.
  VerifiedAudioOutput? get verifiedOutput => _verifiedOutput;

  /// Re-entrancy guard. A route change can arrive while the previous apply is
  /// still awaiting mpv; without this the two interleave and can leave
  /// `audio-channels` and `audio-spdif` describing different routes.
  bool _applying = false;

  /// Set when something asks to apply while an apply is already in flight. The
  /// guard alone would drop that request — and the dropped one is usually the
  /// newer, more correct state (a second tap on the mode cycle, or the route
  /// change that `configure()` itself provokes), leaving the player on a stale
  /// decision with nothing scheduled to fix it.
  bool _applyPending = false;

  String? _lastChannels;
  AudioOutputDecision? _lastDecision;
  String? _audioCodec;
  int _deferrals = 0;
  bool _disposed = false;

  /// The decision currently in effect, for the player's rendering badge.
  AudioOutputDecision? get decision => _lastDecision;

  /// The route the last decision was made on.
  AppleAudioRoute get route => AppleAudioSessionService.instance.lastKnown;

  /// Configures the session and applies the initial output path. Must be
  /// awaited before `loadfile`.
  Future<void> prepare({String? audioCodec}) async {
    current = this;
    _audioCodec = audioCodec;
    if (AppleAudioSessionService.isAvailable) {
      // Diagnostic only, and deliberately first: the probe toggles the
      // multichannel opt-in off and back on to see whether the route widens,
      // so it has to run before the AO exists and before the configure below
      // has the last word on the session state. It measures once per app run
      // and changes no decision. Gated on the debug-logging setting because
      // the answer is only wanted when someone is reading the log.
      if (settings.read(SettingsService.enableDebugLogging)) {
        await AppleAudioSessionService.instance.logChannelNegotiation();
      }
      final route = await AppleAudioSessionService.instance.configure(multichannel: true);
      appLogger.i('Audio route at playback start: $route');
      // onError matters: on a host build without the plugin the EventChannel
      // itself errors, and an unhandled stream error would surface as a crash
      // rather than the stereo fallback the method path already degrades to.
      _routeSub ??= AppleAudioSessionService.instance.routeChanges.listen(
        _onRouteChanged,
        onError: (Object e) => appLogger.w('Audio route stream error: $e'),
      );
    }

    // The authoritative codec comes from the track mpv actually selected, not
    // from the caller's metadata hint. Watching the selection stream is the
    // only way to see every path: the screen's `onAudioTrackChanged` callback
    // only fires when the choice came from user navigation, so on the common
    // server-default and language-preference paths it never runs at all.
    _trackSub ??= player.streams.track.listen(_onTrackSelectionChanged);

    // mpv is the only party that knows the compressed renderer failed to come
    // up; nothing about the route predicts it. Without this the failure is
    // silence the user has to diagnose.
    _logSub ??= player.streams.log.listen(_onPlayerLog);

    await _apply();
  }

  /// The route bitstreaming is remembered against. Port type alone would lump
  /// every HDMI receiver together.
  String get _routeKey {
    final r = AppleAudioSessionService.instance.lastKnown;
    return '${r.portType}/${r.portName}';
  }

  void _onPlayerLog(PlayerLog log) {
    if (_disposed) return;
    if (isAudioOutputOpenedLog(log.text)) _onAudioOutputOpened();
    if (_lastDecision != AudioOutputDecision.passthrough) return;
    if (!isPassthroughFailureLog(log.text)) return;
    _abandonBitstream('mpv reported: ${log.text.trim()}');
  }

  /// Reads back the output the moment mpv says it has one, instead of waiting
  /// out the timer.
  ///
  /// mpv reloads the AO for reasons that are not a decision change (the
  /// `audio-channels` write above is one), so this only fires when a
  /// verification is actually outstanding.
  void _onAudioOutputOpened() {
    final pending = _pendingVerification;
    if (pending == null) return;
    _verifyTimer?.cancel();
    _verifyTimer = null;
    unawaited(_measureOutput(pending, _verifyGeneration));
  }

  /// Gives up on bitstreaming for this route and gets sound back.
  ///
  /// Both failure modes end here: mpv saying so, and mpv saying nothing while
  /// playback sits still. Remembering the route means the next episode starts
  /// on a path that works instead of stalling again.
  void _abandonBitstream(String reason) {
    if (!_bitstreamBlocked.add(_routeKey)) return; // already handled for this route
    appLogger.w('Bitstream unusable on $_routeKey, falling back to PCM — $reason');
    _stallWatchdog?.cancel();
    _stallWatchdog = null;
    onPassthroughUnavailable?.call();
    unawaited(_apply());
  }

  /// Watches for the renderer hanging silently. A stalled bitstream leaves the
  /// position frozen while the player believes it is playing, which no log line
  /// reports — this is what turns that into a recoverable second instead of a
  /// dead player.
  void _startStallWatchdog() {
    _stallWatchdog?.cancel();
    _lastSeenPosition = null;
    _stalledFor = Duration.zero;
    _stallWatchdog = Timer.periodic(_stallSampleInterval, (_) {
      if (_disposed || _lastDecision != AudioOutputDecision.passthrough) return;
      final state = player.state;
      if (!state.playing || state.buffering) {
        _lastSeenPosition = null;
        _stalledFor = Duration.zero;
        return;
      }
      final previous = _lastSeenPosition;
      _lastSeenPosition = state.position;
      if (previous == null || state.position != previous) {
        _stalledFor = Duration.zero;
        return;
      }
      _stalledFor += _stallSampleInterval;
      if (_stalledFor >= _stallTimeout) {
        _abandonBitstream('playback sat at ${state.position} for $_stalledFor');
      }
    });
  }

  /// Re-evaluates after the user picks another audio track — a DTS track and
  /// an E-AC3 track want different output paths. Redundant with the selection
  /// stream, but arrives a beat earlier on the navigation path.
  Future<void> onAudioTrackChanged(AudioTrack track) => _useCodec(track.codec);

  void _onTrackSelectionChanged(TrackSelection selection) => unawaited(_useCodec(selection.audio?.codec));

  Future<void> _useCodec(String? codec) async {
    // A track without codec metadata says nothing about the output path; keep
    // the hint rather than discarding a good decision for a null.
    if (codec == null || codec == _audioCodec) return;
    _audioCodec = codec;
    await _apply();
  }

  void _onRouteChanged(AppleAudioRoute route) {
    if (_disposed) return;
    appLogger.i('Audio route changed: $route');
    _settleTimer?.cancel();
    _deferrals = 0;
    _scheduleApply();
  }

  void _scheduleApply() {
    _settleTimer?.cancel();
    _settleTimer = Timer(_routeSettleDelay, () {
      if (_disposed) return;
      // Reloading the audio output mid-seek turns a hitch into a stall, so
      // defer while the player is busy — but only up to a point, because a
      // player stuck buffering *because of* the route change is exactly when
      // the new route matters most. Re-arming the timer rather than re-entering
      // [_onRouteChanged] keeps a long stall from logging the same line twice a
      // second.
      if (player.state.buffering && _deferrals < _maxBufferingDeferrals) {
        _deferrals++;
        _scheduleApply();
        return;
      }
      if (_deferrals >= _maxBufferingDeferrals) {
        appLogger.i('Applying audio output while still buffering — the route change may be what stalled playback');
      }
      unawaited(_apply());
    });
  }

  Future<void> _apply() async {
    if (_disposed) return;
    if (_applying) {
      _applyPending = true;
      return;
    }
    _applying = true;
    try {
      final mode = settings.read(SettingsService.audioOutputMode);
      final route = AppleAudioSessionService.instance.lastKnown;
      final decision = decideAudioOutput(
        mode: mode,
        route: route,
        audioCodec: _audioCodec,
        bitstreamCodecs: Platform.isIOS ? appleBitstreamCodecs : desktopBitstreamCodecs,
        bitstreamBlocked: _bitstreamBlocked.contains(_routeKey),
      );

      // Channel negotiation is Apple-only: elsewhere mpv already gets the real
      // layout from the OS, and writing the property would only cost an AO
      // reload.
      //
      // Keyed off the route, not the decision. Under passthrough mpv still
      // gates `audio-spdif` per track, so any track it cannot bitstream (an
      // AAC commentary, a format the receiver rejects) falls back to decoding —
      // and pinning stereo here would make that fallback narrower than mpv's
      // own default, on exactly the receiver route this feature is for.
      // The caches are written only after the native call returns. Recording
      // the value first would make a failed write look applied, and every later
      // apply would then skip it as "no change" — so a failed attempt to drop
      // passthrough or fall back to stereo would stick until some unrelated
      // event happened to move the value again.
      if (Platform.isIOS) {
        final channels = route.isMultichannelCapable ? _multichannelLayouts : _stereoLayout;
        if (channels != _lastChannels) {
          await player.setProperty('audio-channels', channels);
          _lastChannels = channels;
        }
      }

      // The mpv method channel is static — one native core for every player —
      // and the player screen disposes the outgoing player unawaited during a
      // player-to-player handoff. Without this second check, a continuation
      // resuming after the await above could write `audio-spdif` into the
      // core the *new* player has already taken over.
      if (_disposed) return;

      if (decision != _lastDecision) {
        if (PlatformDetector.supportsAudioPassthrough()) {
          await player.setAudioPassthrough(decision == AudioOutputDecision.passthrough);
        }
        _lastDecision = decision;
        if (decision == AudioOutputDecision.passthrough) {
          _startStallWatchdog();
        } else {
          _stallWatchdog?.cancel();
          _stallWatchdog = null;
        }
        appLogger.i('Audio output: ${decision.name} (mode: ${mode.name}, codec: $_audioCodec)');
        _scheduleOutputVerification(decision);
      }
    } catch (e, st) {
      appLogger.w('Applying audio output failed', error: e, stackTrace: st);
    } finally {
      _applying = false;
    }

    if (_applyPending && !_disposed) {
      _applyPending = false;
      await _apply();
    }
  }

  /// Reads back what mpv actually settled on, once the AO has had time to come
  /// up.
  ///
  /// The decision above is an intention, and on tvOS the two came apart
  /// silently: the route said multichannel, we logged `pcmMultichannel`, and
  /// mpv meanwhile initialised the stereo-capped AO and remixed 5.1 down. A
  /// bug report then showed a decision that looked right next to sound that
  /// was not. This logs the outcome so the next report says which of the two
  /// it was — the performance overlay reads the same properties live.
  void _scheduleOutputVerification(AudioOutputDecision decision) {
    _verifyTimer?.cancel();
    _pendingVerification = decision;
    _verifyAttempts = 0;
    // A generation rather than a decision comparison: two applies in a row can
    // land on the same decision, and a late reading from the first must not be
    // recorded as the outcome of the second.
    final generation = ++_verifyGeneration;
    // The `AO:` log line usually gets here first; this timer is what covers a
    // backend that logs nothing recognisable.
    _verifyTimer = Timer(_outputVerifyDelay, () => unawaited(_measureOutput(decision, generation)));
  }

  Future<void> _measureOutput(AudioOutputDecision intended, int generation) async {
    if (!_verificationCurrent(intended, generation)) return;
    try {
      final values = await Future.wait([
        player.getProperty('current-ao'),
        player.getProperty('audio-out-params/format'),
        player.getProperty('audio-out-params/hr-channels'),
      ]);
      // A decision that moved on while we waited makes this reading stale, and
      // a stale line here is worse than none: it would describe the output the
      // player just left.
      if (!_verificationCurrent(intended, generation)) return;

      // While the AO is still coming up mpv answers with an empty string rather
      // than null, which is why the old `?? 'unknown'` never caught it. The log
      // line and the property update do not have to arrive together either, so
      // an unfilled answer buys a few more tries instead of a line that says
      // nothing.
      final ao = _readback(values[0]);
      final format = _readback(values[1]);
      if ((ao == null || format == null) && _verifyAttempts < _maxOutputVerifyAttempts) {
        _verifyAttempts++;
        _verifyTimer?.cancel();
        _verifyTimer = Timer(_outputVerifyRetry, () => unawaited(_measureOutput(intended, generation)));
        return;
      }

      _pendingVerification = null;
      _verifyTimer?.cancel();
      _verifyTimer = null;
      _verifiedOutput = VerifiedAudioOutput(intended: intended, ao: ao, format: format, channels: _readback(values[2]));
      appLogger.i(
        'Audio output in effect: ao=${ao ?? 'unknown'}, format=${format ?? 'unknown'}, '
        'channels=${_readback(values[2]) ?? 'unknown'} (intended: ${intended.name})',
      );
    } catch (e) {
      appLogger.d('Reading back the audio output failed: $e');
    }
  }

  bool _verificationCurrent(AudioOutputDecision intended, int generation) =>
      !_disposed && generation == _verifyGeneration && _pendingVerification == intended && _lastDecision == intended;

  /// mpv reports "not there yet" as an empty string just as often as a null.
  static String? _readback(String? value) => (value == null || value.isEmpty) ? null : value;

  /// Re-applies after the user changes the setting in the player.
  ///
  /// Clears this route's block first: picking the mode by hand is the user
  /// asking to try again, and a remembered failure should never make that a
  /// no-op they cannot explain.
  Future<void> onModeChanged() {
    _bitstreamBlocked.remove(_routeKey);
    return _apply();
  }

  void dispose() {
    _disposed = true;
    if (identical(current, this)) current = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _verifyTimer?.cancel();
    _verifyTimer = null;
    _pendingVerification = null;
    unawaited(_routeSub?.cancel());
    _routeSub = null;
    unawaited(_trackSub?.cancel());
    _trackSub = null;
    unawaited(_logSub?.cancel());
    _logSub = null;
    _stallWatchdog?.cancel();
    _stallWatchdog = null;
  }
}

/// What mpv turned out to be doing, read back once its audio output was up.
///
/// The decision the coordinator made is an intention; this is the measurement.
/// `avfoundation` with a `spdif-` format is the only proof that a bitstream is
/// really running rather than merely requested. Fields are null where mpv had
/// nothing to say.
class VerifiedAudioOutput {
  const VerifiedAudioOutput({required this.intended, this.ao, this.format, this.channels});

  final AudioOutputDecision intended;
  final String? ao;
  final String? format;
  final String? channels;

  /// True when mpv is handing over a compressed stream, not decoded audio.
  bool get isBitstream => format?.startsWith('spdif') ?? false;

  @override
  String toString() => 'VerifiedAudioOutput(ao: $ao, format: $format, channels: $channels, intended: ${intended.name})';
}
