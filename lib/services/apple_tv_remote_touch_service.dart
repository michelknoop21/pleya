import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../focus/dpad_navigator.dart';
import '../utils/app_logger.dart';
import '../utils/key_event_simulator.dart' as key_sim;
import '../utils/native_input_session.dart';
import 'gamepad_service.dart';

enum _SwipeAxis { horizontal, vertical }

/// Which input source owns directional navigation for the current gesture.
///
/// tvOS delivers one touch-surface swipe over two independent paths: its own
/// swipe recognizer synthesizes `UIPress` arrows, and the engine separately
/// streams the raw touch coordinates that [AppleTvRemoteTouchService] turns
/// into arrows itself. Deduplicating those per key inside a short time window
/// is not reliable — the recognizer has gesture latency, so its arrow lands
/// outside the window on a busy frame and the focus takes two steps. It also
/// resolves the swipe axis independently, so a diagonal swipe could emit one
/// arrow per path in *different* directions.
///
/// Instead the first source to produce a direction owns the whole gesture and
/// the other one is muted until the gesture ends.
enum _DirectionalOwner { none, swipe, native }

class AppleTvRemotePlayPauseAction {
  final String source;
  final String? detail;

  const AppleTvRemotePlayPauseAction({required this.source, this.detail});
}

/// Bridges tvOS touch-surface events from Apple's iOS Remote app into the
/// focus-tree key events Plezy already handles for D-pad navigation.
class AppleTvRemoteTouchService {
  static const String _channelName = 'flutter/gamepadtouchevent';
  static const double defaultSwipeThreshold = 180;
  static const double defaultAxisSwitchDominanceRatio = 1.5;
  // Min time between accepted swipe-moves. Too low and one continuous trackpad
  // swipe skips several items; 190ms keeps single deliberate swipes responsive
  // while stopping the focus from over-running. Tune on-device if it feels slow.
  static const Duration defaultSwipeRepeatInterval = Duration(milliseconds: 190);
  static const Duration defaultClickAfterDirectionSuppression = Duration(milliseconds: 220);
  // How long a gesture's directional owner stays latched after the finger
  // lifts. tvOS' swipe recognizer regularly delivers its UIPress arrow only
  // *after* touchesEnded, so without this the trailing arrow would add a
  // second step to a gesture that already moved.
  static const Duration defaultGestureOwnershipGrace = Duration(milliseconds: 250);

  static final AppleTvRemoteTouchService instance = AppleTvRemoteTouchService();

  final BasicMessageChannel<dynamic> _channel;
  final void Function(LogicalKeyboardKey logicalKey) _simulateKeyPress;
  final void Function(LogicalKeyboardKey logicalKey) _simulateKeyDown;
  final void Function(LogicalKeyboardKey logicalKey) _simulateKeyUp;
  final VoidCallback _scheduleFrame;
  final DateTime Function() _now;
  final GamepadDuplicateInputGuard _duplicateInputGuard;
  final StreamController<AppleTvRemotePlayPauseAction> _playPauseController =
      StreamController<AppleTvRemotePlayPauseAction>.broadcast();
  final double swipeThreshold;
  final double axisSwitchDominanceRatio;
  final Duration swipeRepeatInterval;
  final Duration clickAfterDirectionSuppression;
  final Duration gestureOwnershipGrace;

  bool _listening = false;
  bool _nativeKeyHandlerRegistered = false;
  bool _touchActive = false;
  final ValueNotifier<bool> _touchActiveNotifier = ValueNotifier<bool>(false);
  double _startX = 0;
  double _startY = 0;
  double _anchorX = 0;
  double _anchorY = 0;
  _SwipeAxis? _lastSwipeAxis;
  DateTime? _lastSwipeAt;
  DateTime? _lastDirectionalInputAt;
  DateTime? _lastSyntheticSelectAt;
  DateTime? _lastAcceptedNativeSelectDownAt;
  DateTime? _lastAcceptedNativeSelectUpAt;
  int _suppressedNativeSelectDowns = 0;
  bool _nativeSelectPressed = false;
  bool _selectPressedFromClick = false;
  _DirectionalOwner _directionalOwner = _DirectionalOwner.none;
  DateTime? _directionalOwnerExpiresAt;

  AppleTvRemoteTouchService({
    BasicMessageChannel<dynamic>? channel,
    void Function(LogicalKeyboardKey logicalKey)? simulateKeyPress,
    void Function(LogicalKeyboardKey logicalKey)? simulateKeyDown,
    void Function(LogicalKeyboardKey logicalKey)? simulateKeyUp,
    VoidCallback? scheduleFrame,
    DateTime Function()? now,
    GamepadDuplicateInputGuard? duplicateInputGuard,
    Duration duplicateSuppressionWindow = GamepadDuplicateInputGuard.defaultSuppressionWindow,
    this.swipeThreshold = defaultSwipeThreshold,
    this.axisSwitchDominanceRatio = defaultAxisSwitchDominanceRatio,
    this.swipeRepeatInterval = defaultSwipeRepeatInterval,
    this.clickAfterDirectionSuppression = defaultClickAfterDirectionSuppression,
    this.gestureOwnershipGrace = defaultGestureOwnershipGrace,
  }) : assert(axisSwitchDominanceRatio >= 1),
       _channel = channel ?? const BasicMessageChannel<dynamic>(_channelName, JSONMessageCodec()),
       _simulateKeyPress = simulateKeyPress ?? key_sim.simulateKeyPress,
       _simulateKeyDown = simulateKeyDown ?? key_sim.simulateKeyDown,
       _simulateKeyUp = simulateKeyUp ?? key_sim.simulateKeyUp,
       _scheduleFrame = scheduleFrame ?? key_sim.scheduleFrameIfIdle,
       _now = now ?? DateTime.now,
       _duplicateInputGuard =
           duplicateInputGuard ?? GamepadDuplicateInputGuard(now: now, suppressionWindow: duplicateSuppressionWindow);

  Stream<AppleTvRemotePlayPauseAction> get playPauseActions => _playPauseController.stream;

  /// Whether a Siri-remote touch gesture is currently in progress (finger down).
  /// Cleared when the touch ends or cancels. tvOS-only; `false` elsewhere.
  bool get isTouchActive => _touchActive;

  /// Listenable mirror of [isTouchActive] so widgets can react when the active
  /// touch gesture ends (used to extend Home-rail select suppression).
  ValueListenable<bool> get touchActiveListenable => _touchActiveNotifier;

  void start() {
    if (_listening) return;
    _channel.setMessageHandler(handleMessage);
    _registerNativeKeyHandler();
    _listening = true;
    appLogger.i('AppleTvRemoteTouchService: Listening for tvOS touch remote events');
  }

  void stop() {
    if (!_listening) return;
    _channel.setMessageHandler(null);
    _unregisterNativeKeyHandler();
    _duplicateInputGuard.clear();
    _resetNativeSelectBurstState();
    _directionalOwner = _DirectionalOwner.none;
    _directionalOwnerExpiresAt = null;
    _releaseSelectFromClick(source: 'stop');
    _resetTouch();
    _listening = false;
  }

  bool handleNativeKeyEvent(KeyEvent event) {
    _log('native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)}');
    if (_isMediaPlaybackKey(event.logicalKey)) {
      _log('consume native media key reason=direct-playback-action');
      return true;
    }
    // The tvOS system keyboard owns the remote — anything that still leaks
    // through stops here rather than moving focus behind it.
    if (NativeInputSession.isActive) {
      _releaseSelectForNativeSession();
      // Back is the exception that still has to *do* something. It reaches Dart
      // only when the native escape hatch missed the press, and swallowing it
      // there is why the first Menu could appear to do nothing: the keyboard
      // stayed up until a later press happened to take the native path. Ask the
      // surface to close, then consume as usual so focus stays put either way.
      // KeyDown only — repeats and the key-up would ask again for one press.
      if (event is KeyDownEvent && event.logicalKey.isBackKey) {
        final asked = NativeInputSession.requestClose();
        _log('consume native key reason=native-input-session close=$asked');
        return true;
      }
      _log('consume native key reason=native-input-session');
      return true;
    }
    if (_shouldConsumeNativeSelectDuplicate(event)) {
      return true;
    }
    if (_isDirectionalKey(event.logicalKey)) {
      // Track this even for events we go on to consume: a directional input
      // from either path should still suppress a stray click that follows it.
      if (event is! KeyUpEvent) _lastDirectionalInputAt = _now();
      if (_shouldConsumeNativeDirectional(event)) return true;
    }
    return _duplicateInputGuard.handleNativeKeyEvent(event);
  }

  Future<void> handleMessage(dynamic arguments) async {
    if (arguments is! Map) {
      _log('ignore message reason=not-map valueType=${arguments.runtimeType}');
      return;
    }

    final type = arguments['type'];
    if (type is! String) {
      _log('ignore message reason=missing-type args=$arguments');
      return;
    }

    _logTouch(type, arguments);

    // play_pause still gets through: it is a direct playback action, not
    // navigation, and the native side forwards it during a session too.
    if (NativeInputSession.isActive && type != 'play_pause') {
      _log('ignore message reason=native-input-session type=$type');
      _releaseSelectForNativeSession();
      _resetTouch();
      return;
    }

    switch (type) {
      case 'started':
        final position = _positionFrom(arguments);
        if (position == null) return;
        _startTouch(position.$1, position.$2);
      case 'move':
        final position = _positionFrom(arguments);
        if (position == null) return;
        _moveTouch(position.$1, position.$2);
      case 'ended':
        // Drop the lift frame: the final position on touchesEnded is
        // unreliable on the Siri Remote — a natural finger pivot during
        // lift can register enough delta from the post-last-swipe anchor
        // to fire a stray opposite-direction swipe. In-gesture 'move'
        // events have already covered any legitimate swipe motion.
        _resetTouch();
      case 'cancelled':
        _resetTouch();
      case 'click_e':
        _releaseSelectFromClick(source: 'click_e');
      case 'click_s':
        _pressSelectFromClick();
      case 'play_pause':
        final source = arguments['source'] is String ? arguments['source'] as String : 'native';
        final detail = arguments['detail'] is String ? arguments['detail'] as String : null;
        _log('emit action=play_pause source=$source${detail == null ? '' : ' detail=$detail'}');
        _playPauseController.add(AppleTvRemotePlayPauseAction(source: source, detail: detail));
      case 'loc':
        break;
      default:
        break;
    }
  }

  (double, double)? _positionFrom(Map<dynamic, dynamic> arguments) {
    final x = _toDouble(arguments['x']);
    final y = _toDouble(arguments['y']);
    if (x == null || y == null) return null;
    return (x, y);
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return null;
  }

  void _startTouch(double x, double y) {
    _touchActive = true;
    _touchActiveNotifier.value = true;
    _startX = x;
    _startY = y;
    _anchorX = x;
    _anchorY = y;
    _lastSwipeAxis = null;
    _lastSwipeAt = null;
    // A swipe claim still under its post-lift grace belongs to a gesture the
    // accumulator already owned, so carry it into this one — consecutive fast
    // swipes must not let the previous gesture's trailing native arrow in.
    // Anything else (a directional-ring click) starts fresh.
    if (_currentDirectionalOwner() == _DirectionalOwner.swipe) {
      _directionalOwnerExpiresAt = null;
    } else {
      _directionalOwner = _DirectionalOwner.none;
      _directionalOwnerExpiresAt = null;
    }
  }

  void _moveTouch(double x, double y) {
    if (!_touchActive) {
      _log('ignore touch-move reason=no-active-touch x=${_formatDouble(x)} y=${_formatDouble(y)}');
      return;
    }

    if (_currentDirectionalOwner() == _DirectionalOwner.native) {
      _log('suppress swipe reason=gesture-owned-by-native x=${_formatDouble(x)} y=${_formatDouble(y)}');
      return;
    }

    final deltaX = _anchorX - x;
    final deltaY = _anchorY - y;
    final axis = _resolveSwipeAxis(x: x, y: y, deltaX: deltaX, deltaY: deltaY);
    if (axis == null) return;

    final now = _now();
    final lastSwipeAt = _lastSwipeAt;
    if (lastSwipeAt != null && now.difference(lastSwipeAt) < swipeRepeatInterval) {
      final age = now.difference(lastSwipeAt).inMilliseconds;
      _log(
        'suppress swipe reason=repeat-cooldown age=${age}ms dx=${_formatDouble(deltaX)} dy=${_formatDouble(deltaY)}',
      );
      return;
    }

    final logicalKey = axis == _SwipeAxis.horizontal
        ? (deltaX >= 0 ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)
        : (deltaY >= 0 ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown);

    _emitKey(logicalKey, source: 'swipe', detail: 'dx=${_formatDouble(deltaX)} dy=${_formatDouble(deltaY)}');
    // Advance the anchor by exactly one threshold along the axis we just
    // emitted on, rather than snapping it to the finger. Snapping throws away
    // whatever travel overshot the threshold, and how much overshoots depends
    // on the sample and frame timing — so the same physical swipe yields a
    // different number of steps run to run. Carrying the remainder keeps it at
    // floor(distance / threshold). The other axis still snaps: it did not
    // contribute a step.
    if (axis == _SwipeAxis.horizontal) {
      _anchorX = x + deltaX - swipeThreshold * (deltaX >= 0 ? 1 : -1);
      _anchorY = y;
    } else {
      _anchorX = x;
      _anchorY = y + deltaY - swipeThreshold * (deltaY >= 0 ? 1 : -1);
    }
    _lastSwipeAxis = axis;
    _lastSwipeAt = now;
  }

  _SwipeAxis? _resolveSwipeAxis({
    required double x,
    required double y,
    required double deltaX,
    required double deltaY,
  }) {
    final absX = deltaX.abs();
    final absY = deltaY.abs();
    if (absX < swipeThreshold && absY < swipeThreshold) return null;

    final candidate = absX >= absY ? _SwipeAxis.horizontal : _SwipeAxis.vertical;
    final lastAxis = _lastSwipeAxis;
    if (lastAxis == null || candidate == lastAxis) return candidate;

    final totalX = (_startX - x).abs();
    final totalY = (_startY - y).abs();
    final candidateTotal = _axisDistance(candidate, totalX, totalY);
    final lastAxisTotal = _axisDistance(lastAxis, totalX, totalY);
    final candidateSegment = _axisDistance(candidate, absX, absY);
    final lastAxisSegment = _axisDistance(lastAxis, absX, absY);
    if (candidateTotal >= lastAxisTotal * axisSwitchDominanceRatio &&
        candidateSegment >= lastAxisSegment * axisSwitchDominanceRatio) {
      return candidate;
    }

    return lastAxisSegment >= swipeThreshold ? lastAxis : null;
  }

  double _axisDistance(_SwipeAxis axis, double horizontal, double vertical) {
    return axis == _SwipeAxis.horizontal ? horizontal : vertical;
  }

  void _pressSelectFromClick() {
    final now = _now();
    final lastDirectionalInputAt = _lastDirectionalInputAt;
    if (lastDirectionalInputAt != null && now.difference(lastDirectionalInputAt) <= clickAfterDirectionSuppression) {
      final age = now.difference(lastDirectionalInputAt).inMilliseconds;
      _log('suppress key=${_keyName(LogicalKeyboardKey.enter)} source=click_s reason=recent-direction age=${age}ms');
      return;
    }

    final lastSyntheticSelectAt = _lastSyntheticSelectAt;
    if (lastSyntheticSelectAt != null && now.difference(lastSyntheticSelectAt).abs() <= duplicateSuppressionWindow) {
      final age = now.difference(lastSyntheticSelectAt).abs().inMilliseconds;
      _log(
        'suppress key=${_keyName(LogicalKeyboardKey.enter)} source=click_s reason=recent-synthetic-select age=${age}ms',
      );
      return;
    }

    if (_duplicateInputGuard.shouldSuppressSyntheticKey(LogicalKeyboardKey.enter)) {
      _log('suppress key=${_keyName(LogicalKeyboardKey.enter)} source=click_s reason=recent-native');
      return;
    }

    _setTraditionalFocusHighlight();
    _scheduleFrame();
    _selectPressedFromClick = true;
    _log('emit keydown=${_keyName(LogicalKeyboardKey.enter)} source=click_s');
    _simulateKeyDown(LogicalKeyboardKey.enter);
  }

  /// Close out the select press that opened the native surface.
  ///
  /// The press arrives as `click_s` → key-down → the button opens the keyboard,
  /// and the matching `click_e` then lands with the session already active and
  /// gets dropped. Without this, `_selectPressedFromClick` stays true and
  /// `_shouldConsumeNativeSelectDuplicate` eats the *next* real select as an
  /// in-flight duplicate — so the first press after every session did nothing.
  /// The synthetic key-up itself is swallowed by the gate in
  /// [key_sim.simulateKeyUp]; only the bookkeeping matters here.
  void _releaseSelectForNativeSession() {
    if (!_selectPressedFromClick) return;
    _releaseSelectFromClick(source: 'native-input-session');
  }

  void _releaseSelectFromClick({required String source}) {
    if (!_selectPressedFromClick) {
      _log('ignore keyup=${_keyName(LogicalKeyboardKey.enter)} source=$source reason=no-click-select-down');
      return;
    }

    _setTraditionalFocusHighlight();
    _scheduleFrame();
    _selectPressedFromClick = false;
    _lastSyntheticSelectAt = _now();
    _log('emit keyup=${_keyName(LogicalKeyboardKey.enter)} source=$source');
    _simulateKeyUp(LogicalKeyboardKey.enter);
  }

  bool _shouldConsumeNativeSelectDuplicate(KeyEvent event) {
    if (!_isSelectKey(event.logicalKey)) return false;

    final now = _now();
    if (_selectPressedFromClick) {
      _log(
        'consume native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)} '
        'reason=synthetic-select-in-flight',
      );
      if (event is KeyUpEvent) {
        _releaseSelectFromClick(source: 'native_select');
      }
      return true;
    }

    final lastSyntheticSelectAt = _lastSyntheticSelectAt;
    if (lastSyntheticSelectAt != null && now.difference(lastSyntheticSelectAt).abs() <= duplicateSuppressionWindow) {
      final age = now.difference(lastSyntheticSelectAt).abs().inMilliseconds;
      _log(
        'consume native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)} '
        'reason=recent-synthetic-select age=${age}ms',
      );
      return true;
    }

    if (event is KeyDownEvent) {
      final lastAcceptedNativeSelectUpAt = _lastAcceptedNativeSelectUpAt;
      final duplicateCompletedPress =
          lastAcceptedNativeSelectUpAt != null &&
          now.difference(lastAcceptedNativeSelectUpAt).abs() <= duplicateSuppressionWindow;
      if (_nativeSelectPressed || duplicateCompletedPress) {
        _suppressedNativeSelectDowns++;
        final reason = _nativeSelectPressed ? 'native-select-already-down' : 'recent-native-select';
        _log(
          'consume native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)} '
          'reason=$reason',
        );
        return true;
      }

      _nativeSelectPressed = true;
      _lastAcceptedNativeSelectDownAt = now;
      return false;
    }

    if (event is KeyRepeatEvent) {
      if (_nativeSelectPressed) return false;
      final lastAcceptedNativeSelectDownAt = _lastAcceptedNativeSelectDownAt;
      if (lastAcceptedNativeSelectDownAt != null &&
          now.difference(lastAcceptedNativeSelectDownAt).abs() <= duplicateSuppressionWindow) {
        _log(
          'consume native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)} '
          'reason=recent-native-select',
        );
        return true;
      }
      return false;
    }

    if (event is KeyUpEvent) {
      if (_suppressedNativeSelectDowns > 0) {
        _suppressedNativeSelectDowns--;
        _log(
          'consume native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)} '
          'reason=suppressed-native-select-down',
        );
        return true;
      }

      if (!_nativeSelectPressed) {
        final lastAcceptedNativeSelectUpAt = _lastAcceptedNativeSelectUpAt;
        if (lastAcceptedNativeSelectUpAt != null &&
            now.difference(lastAcceptedNativeSelectUpAt).abs() <= duplicateSuppressionWindow) {
          _log(
            'consume native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)} '
            'reason=recent-native-select-up',
          );
          return true;
        }
        return false;
      }

      _nativeSelectPressed = false;
      _lastAcceptedNativeSelectUpAt = now;
      return false;
    }

    return false;
  }

  /// Consume a native directional event when the touch-surface accumulator
  /// already owns this gesture, otherwise claim the gesture for the native
  /// path and let the event through.
  ///
  /// Deliberately unconditional on key and event type: the two paths resolve
  /// the swipe axis independently, so a diagonal swipe can produce a native
  /// arrow on a *different* axis than the synthetic one. Matching only the
  /// same key would let that through as a second, sideways move.
  bool _shouldConsumeNativeDirectional(KeyEvent event) {
    if (_currentDirectionalOwner() == _DirectionalOwner.swipe) {
      _log(
        'consume native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)} '
        'reason=gesture-owned-by-swipe',
      );
      return true;
    }

    if (event is! KeyUpEvent) {
      _claimDirectionalOwner(_DirectionalOwner.native);
    }
    return false;
  }

  /// The owner of the current gesture, expiring a stale claim first.
  _DirectionalOwner _currentDirectionalOwner() {
    final expiresAt = _directionalOwnerExpiresAt;
    if (expiresAt != null && _now().isAfter(expiresAt)) {
      _directionalOwner = _DirectionalOwner.none;
      _directionalOwnerExpiresAt = null;
    }
    return _directionalOwner;
  }

  void _claimDirectionalOwner(_DirectionalOwner owner) {
    if (_directionalOwner != owner) {
      _log('directional owner=${owner.name}');
    }
    _directionalOwner = owner;
    // A claim made while the finger is down lasts until the touch ends, at
    // which point [_resetTouch] arms the grace period. A claim made without an
    // active touch (a click on the directional ring) only gets the grace.
    _directionalOwnerExpiresAt = _touchActive ? null : _now().add(gestureOwnershipGrace);
  }

  void _resetNativeSelectBurstState() {
    _lastAcceptedNativeSelectDownAt = null;
    _lastAcceptedNativeSelectUpAt = null;
    _suppressedNativeSelectDowns = 0;
    _nativeSelectPressed = false;
  }

  bool _emitKey(LogicalKeyboardKey logicalKey, {required String source, String? detail}) {
    if (_duplicateInputGuard.shouldSuppressSyntheticKey(logicalKey)) {
      _log('suppress key=${_keyName(logicalKey)} source=$source reason=recent-native');
      return false;
    }

    _setTraditionalFocusHighlight();
    _scheduleFrame();
    _log('emit key=${_keyName(logicalKey)} source=$source${detail == null ? '' : ' $detail'}');
    if (_isDirectionalKey(logicalKey)) {
      _lastDirectionalInputAt = _now();
      if (source == 'swipe') {
        _claimDirectionalOwner(_DirectionalOwner.swipe);
      }
    }
    _simulateKeyPress(logicalKey);
    return true;
  }

  Duration get duplicateSuppressionWindow => _duplicateInputGuard.suppressionWindow;

  void _resetTouch() {
    _touchActive = false;
    _touchActiveNotifier.value = false;
    _lastSwipeAxis = null;
    _lastSwipeAt = null;
    if (_directionalOwner != _DirectionalOwner.none) {
      _directionalOwnerExpiresAt = _now().add(gestureOwnershipGrace);
    }
  }

  void _registerNativeKeyHandler() {
    if (_nativeKeyHandlerRegistered) return;
    HardwareKeyboard.instance.addHandler(handleNativeKeyEvent);
    _nativeKeyHandlerRegistered = true;
  }

  void _unregisterNativeKeyHandler() {
    if (!_nativeKeyHandlerRegistered) return;
    HardwareKeyboard.instance.removeHandler(handleNativeKeyEvent);
    _nativeKeyHandlerRegistered = false;
  }

  void _setTraditionalFocusHighlight() {
    if (FocusManager.instance.highlightStrategy != FocusHighlightStrategy.alwaysTraditional) {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    }
  }

  /// The touch remote reports a position several times per second, and every
  /// one of those used to land on debug. In an uploaded log from a playback
  /// session a third of all lines were touch coordinates, which is a third of
  /// the buffer not spent on whatever the report was about.
  ///
  /// So the continuous stream (`loc`, `move`) drops to trace, which the normal
  /// debug level filters out, while the events gestures are actually
  /// reconstructed from — the touch starting and ending, and every key emitted
  /// or suppressed below — stay on debug.
  static const _highFrequencyTouchTypes = {'loc', 'move'};

  void _logTouch(String type, Map<dynamic, dynamic> arguments) {
    final x = _toDouble(arguments['x']);
    final y = _toDouble(arguments['y']);
    final message = 'touch type=$type x=${_formatDouble(x)} y=${_formatDouble(y)} active=$_touchActive';
    if (_highFrequencyTouchTypes.contains(type)) {
      appLogger.t('AppleTvRemoteTouchService: $message');
      return;
    }
    _log(message);
  }

  void _log(String message) {
    appLogger.d('AppleTvRemoteTouchService: $message');
  }

  String _eventTypeName(KeyEvent event) {
    if (event is KeyDownEvent) return 'keydown';
    if (event is KeyRepeatEvent) return 'keyrepeat';
    if (event is KeyUpEvent) return 'keyup';
    return event.runtimeType.toString();
  }

  String _keyName(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return 'arrowUp';
    if (key == LogicalKeyboardKey.arrowDown) return 'arrowDown';
    if (key == LogicalKeyboardKey.arrowLeft) return 'arrowLeft';
    if (key == LogicalKeyboardKey.arrowRight) return 'arrowRight';
    if (key == LogicalKeyboardKey.enter) return 'enter';
    if (key.keyId == 0x0d) return 'rawEnter';
    if (key == LogicalKeyboardKey.numpadEnter) return 'numpadEnter';
    if (key == LogicalKeyboardKey.select) return 'select';
    if (key == LogicalKeyboardKey.gameButtonA) return 'gameButtonA';
    if (key == LogicalKeyboardKey.escape) return 'escape';
    if (key == LogicalKeyboardKey.mediaPlay) return 'mediaPlay';
    if (key == LogicalKeyboardKey.mediaPause) return 'mediaPause';
    if (key == LogicalKeyboardKey.mediaPlayPause) return 'mediaPlayPause';
    return '0x${key.keyId.toRadixString(16)}';
  }

  bool _isDirectionalKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key.keyId == 0x0d ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  bool _isMediaPlaybackKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause;
  }

  String _formatDouble(double? value) {
    if (value == null) return 'n/a';
    return value.toStringAsFixed(1);
  }
}
