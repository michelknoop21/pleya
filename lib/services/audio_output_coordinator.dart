import 'dart:async';
import 'dart:io' show Platform;

import '../mpv/models.dart' show AudioTrack, TrackSelection;
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
  AudioOutputCoordinator({required this.player, required this.settings});

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
  Timer? _settleTimer;

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
      // Once per app run, and before anything is playing: flipping the
      // multichannel flag to read both sides of it would reload the audio
      // output if a stream were already up.
      await AppleAudioSessionService.instance.logChannelNegotiation();
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

    await _apply();
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
        appLogger.i('Audio output: ${decision.name} (mode: ${mode.name}, codec: $_audioCodec)');
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

  /// Re-applies after the user changes the setting in the player.
  Future<void> onModeChanged() => _apply();

  void dispose() {
    _disposed = true;
    if (identical(current, this)) current = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    unawaited(_routeSub?.cancel());
    _routeSub = null;
    unawaited(_trackSub?.cancel());
    _trackSub = null;
  }
}
