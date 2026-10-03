import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../i18n/strings.g.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/native_input_session.dart';
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
    Future<List<String>> Function()? clips,
    Future<void> Function(String asset)? play,
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
  final Future<List<String>> Function() _clips;
  final Future<void> Function(String asset) _play;
  final Future<void> Function() _stop;
  final Random _random;

  /// A run still working after this long gets one "still looking".
  final Duration workingAfter;

  late AssistantSurfaceState _state;
  bool _hadPending = false;
  Timer? _workingTimer;
  Future<List<String>>? _available;
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
    final List<String> all;
    try {
      all = await (_available ??= _clips());
    } catch (e) {
      _available = null;
      appLogger.d('Big P voice: no clip list', error: e.runtimeType);
      return null;
    }
    var options = all.where((a) => a.startsWith(start)).toList();
    if (options.length > 1) options.remove(_last[moment]);
    // The list load awaited: the user may have started dictating meanwhile.
    if (options.isEmpty || !_mayTalk) return null;
    final asset = options[_random.nextInt(options.length)];
    _last[moment] = asset;
    try {
      await _play(asset);
      // Dictation that began while the clip loaded sent its stop first.
      if (!_mayTalk) await _stopQuietly();
    } catch (e) {
      // No player on this platform, or the clip could not be decoded.
      appLogger.d('Big P voice: clip not played', error: e.runtimeType);
      return null;
    }
    return asset;
  }

  Future<void> _stopQuietly() async {
    try {
      await _stop();
    } catch (_) {
      // Nothing playing, or no player on this platform.
    }
  }

  static Future<List<String>> _bundledClips() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().where((a) => a.startsWith(_prefix) && a.endsWith('.m4a')).toList();
  }

  /// The clip goes over as bytes, so the native side needs no asset lookup.
  static Future<void> _playAsset(String asset) async {
    final data = await rootBundle.load(asset);
    await _channel.invokeMethod<void>('playClip', data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  static Future<void> _stopClip() => _channel.invokeMethod<void>('stopClip');
}
