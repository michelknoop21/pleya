import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.g.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/native_input_session.dart';
import '../widgets/big_p/big_p_rig.dart';
import 'assistant_controller.dart';

/// The moments Big P says something; each has a few clips per language,
/// named `assets/audio/bigp/<lang>_<moment>_<n>.m4a`.
enum BigPMoment { greet, result, confirm, error, working, nod }

/// Big P's short pre-recorded reactions, driven by [AssistantController].
///
/// A clip that would start while the user dictates (the native keyboard, or
/// the controller in `listening`) or while a video plays is dropped, never
/// queued. A newer clip cuts the one still playing. Missing clips, a platform
/// without the player (only iOS and tvOS have it) or the switch in the
/// Assistant settings turned off all mean silence.
class BigPVoice {
  BigPVoice(
    this._controller, {
    bool Function()? enabled,
    bool Function()? playbackActive,
    bool Function()? dictating,
    String Function()? language,
    Future<Map<String, String>> Function()? clips,
    Future<double?> Function(String asset)? play,
    Future<void> Function()? stop,
    Random? random,
    this.workingAfter = const Duration(seconds: 6),
  }) : _enabled = enabled ?? (() => SettingsService.instanceOrNull?.read(SettingsService.bigPVoice) ?? false),
       _playbackActive = playbackActive ?? (() => false),
       _dictating = dictating ?? (() => NativeInputSession.isActive),
       _language = language ?? (() => LocaleSettings.currentLocale == AppLocale.nl ? 'nl' : 'en'),
       _clips = clips ?? _bundledClips,
       _play = play ?? _playAsset,
       _stop = stop ?? _stopClip,
       _random = random ?? Random() {
    _state = _controller.state;
    _controller.addListener(_onChange);
    _byController[_controller] = this;
  }

  static final _byController = Expando<BigPVoice>();

  /// The voice attached to [controller], for moments only the UI sees.
  static BigPVoice? of(AssistantController controller) => _byController[controller];

  static const _channel = MethodChannel('com.pleya/audio_session');
  static const _prefix = 'assets/audio/bigp/';

  final AssistantController _controller;
  final bool Function() _enabled;
  final bool Function() _playbackActive;
  final bool Function() _dictating;
  final String Function() _language;
  final Future<Map<String, String>> Function() _clips;
  final Future<double?> Function(String asset) _play;
  final Future<void> Function() _stop;
  final Random _random;

  /// A run still working after this long gets one "still looking".
  final Duration workingAfter;

  late AssistantSurfaceState _state;
  bool _hadPending = false;
  Timer? _workingTimer;
  Future<Map<String, String>>? _available;
  Timer? _speakingTimer;

  /// The line Big P is saying right now, for his mouth; null when silent.
  final ValueNotifier<String?> speaking = ValueNotifier(null);
  final Map<BigPMoment, String> _last = {};

  void _onChange() {
    final c = _controller;
    final previous = _state;
    _state = c.state;
    if (c.pending != null && !_hadPending) unawaited(say(BigPMoment.confirm));
    _hadPending = c.pending != null;
    if (_state == previous) return;
    _workingTimer?.cancel();
    switch (_state) {
      case AssistantSurfaceState.listening:
        // The user is about to speak: whatever Big P was saying stops.
        unawaited(_stopQuietly());
      case AssistantSurfaceState.working:
        _workingTimer = Timer(workingAfter, () {
          if (!c.disposed && c.state == AssistantSurfaceState.working) unawaited(say(BigPMoment.working));
        });
      case AssistantSurfaceState.result:
        // Only a finished run: backing out of a follow-up question restores
        // the old answer, which was already said.
        if (previous == AssistantSurfaceState.working) {
          unawaited(say(c.resultIsError ? BigPMoment.error : BigPMoment.result));
        }
      case AssistantSurfaceState.idle:
        break;
    }
  }

  bool get _mayTalk =>
      !_controller.disposed &&
      _enabled() &&
      !_dictating() &&
      _controller.state != AssistantSurfaceState.listening &&
      !_playbackActive();

  /// Plays a random clip for [moment], never the one it played last time.
  /// Returns the asset played, or null when it was dropped.
  Future<String?> say(BigPMoment moment) async {
    if (!_mayTalk) return null;
    final start = '$_prefix${_language()}_${moment.name}_';
    final Map<String, String> all;
    try {
      all = await (_available ??= _clips());
    } catch (e) {
      _available = null;
      appLogger.d('Big P voice: no clip list', error: e.runtimeType);
      return null;
    }
    final options = all.keys.where((a) => a.startsWith(start)).toList();
    if (options.length > 1) options.remove(_last[moment]);
    // The list load awaited: the user may have started dictating meanwhile.
    if (options.isEmpty || !_mayTalk) return null;
    final asset = options[_random.nextInt(options.length)];
    _last[moment] = asset;
    try {
      final seconds = await _play(asset);
      // Dictation that began while the clip loaded sent its stop first.
      if (!_mayTalk) {
        await _stopQuietly();
        return null;
      }
      _speak(all[asset]!, seconds);
    } catch (e) {
      // No player on this platform, or the clip could not be decoded.
      appLogger.d('Big P voice: clip not played', error: e.runtimeType);
      return null;
    }
    return asset;
  }

  /// The mouth moves for as long as the clip plays.
  void _speak(String line, double? seconds) {
    _speakingTimer?.cancel();
    speaking.value = line;
    final ms = ((seconds ?? BigPTalkPlan.build(line).end) * 1000).round();
    _speakingTimer = Timer(Duration(milliseconds: ms), () => speaking.value = null);
  }

  Future<void> _stopQuietly() async {
    _speakingTimer?.cancel();
    speaking.value = null;
    try {
      await _stop();
    } catch (_) {
      // Nothing playing, or no player on this platform.
    }
  }

  /// Asset path to its spoken line, from the generator's `lines.json`.
  static Future<Map<String, String>> _bundledClips() async {
    final lines = jsonDecode(await rootBundle.loadString('${_prefix}lines.json')) as Map<String, dynamic>;
    return {for (final e in lines.entries) '$_prefix${e.key}.m4a': e.value as String};
  }

  /// The clip goes over as bytes, so the native side needs no asset lookup.
  /// Answers the clip's length in seconds.
  static Future<double?> _playAsset(String asset) async {
    final data = await rootBundle.load(asset);
    return _channel.invokeMethod<double>('playClip', data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  static Future<void> _stopClip() => _channel.invokeMethod<void>('stopClip');
}
