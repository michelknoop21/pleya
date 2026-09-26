import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../diagnostics/select_trace_recorder.dart';
import '../utils/app_logger.dart';
import '../utils/key_event_simulator.dart' as key_sim;
import '../utils/native_input_session.dart';
import 'gamepad_service.dart';

enum _SwipeAxis { horizontal, vertical }

/// Free-scrub travel: [dx] in UIKit view points, [speed] in points per
/// millisecond (0 when unknown).
typedef ScrubPanHandler = void Function(double dx, double speed);

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

  /// NAV2 (docs/tvos-fysieke-correctieronde.md): station 3 of
  /// docs/tvos-remote-press-pipeline.md as an app-log line. `AppDelegate`'s
  /// `tvosHandlePress(fromUIEvent:)` sends one message per call: read-only,
  /// no reply, no filtering, because its NSLog line never reaches a relay
  /// log.
  static const String _pressDiagChannelName = 'nl.michelknoop.pleya/tvos_press_diag';
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
  // How long after a swipe-driven directional key widgets may still attribute
  // that key to a swipe. Synthetic keys are dispatched a frame after they are
  // tagged, so this has to be a window, not a momentary flag.
  static const Duration defaultSwipeAttributionWindow = Duration(milliseconds: 250);
  // Pan distance since touch-start above which a *native* directional key that
  // reached the app is attributed to a swipe instead of a clickpad press (a
  // press keeps the finger nearly still). Tuning knob; the verdict is logged.
  static const double defaultNativeSwipeClassifyDistance = 60;
  // Finger travel before a free-scrub pan starts moving the cursor, so the
  // jitter of a click (the commit click included) does not shift it.
  static const double scrubPanSlop = 20;
  // After the slop, travel is forwarded in chunks of at least this much, so
  // the jitter of the commit click in the middle of a pan stays put.
  static const double scrubPanDeadZone = 4;
  // Horizontal travel, in the same UIKit view points as [swipeThreshold], that
  // counts as one full swipe across the surface. Tuning knob for the hardware
  // round: measure a full physical swipe in the log (`touch type=move`).
  static const double scrubPanFullTravel = 1920;
  // Pan speed is averaged over this window, and never over less than
  // [scrubPanMinSpeedInterval]: channel messages that land in one frame are
  // microseconds apart and would otherwise read as a flick.
  static const Duration scrubPanSpeedWindow = Duration(milliseconds: 50);
  static const Duration scrubPanMinSpeedInterval = Duration(milliseconds: 8);

  static final AppleTvRemoteTouchService _instance = AppleTvRemoteTouchService();
  static AppleTvRemoteTouchService? _debugInstanceOverride;
  static AppleTvRemoteTouchService get instance => _debugInstanceOverride ?? _instance;

  @visibleForTesting
  static set debugInstanceOverride(AppleTvRemoteTouchService? service) => _debugInstanceOverride = service;

  final BasicMessageChannel<dynamic> _channel;
  final BasicMessageChannel<dynamic> _pressDiagChannel;
  final void Function(LogicalKeyboardKey logicalKey) _simulateKeyPress;
  final void Function(LogicalKeyboardKey logicalKey) _simulateKeyDown;
  final void Function(LogicalKeyboardKey logicalKey) _simulateKeyUp;
  final VoidCallback _scheduleFrame;
  final DateTime Function() _now;
  final GamepadDuplicateInputGuard _duplicateInputGuard;
  final SelectTraceRecorder _traceRecorder;
  final StreamController<AppleTvRemotePlayPauseAction> _playPauseController =
      StreamController<AppleTvRemotePlayPauseAction>.broadcast();
  final double swipeThreshold;
  final double axisSwitchDominanceRatio;
  final Duration swipeRepeatInterval;
  final Duration clickAfterDirectionSuppression;
  final Duration gestureOwnershipGrace;
  final Duration swipeAttributionWindow;
  final double nativeSwipeClassifyDistance;

  bool _listening = false;
  bool _nativeKeyHandlerRegistered = false;
  bool _touchActive = false;
  final ValueNotifier<bool> _touchActiveNotifier = ValueNotifier<bool>(false);
  double _startX = 0;
  double _startY = 0;
  double _anchorX = 0;
  double _anchorY = 0;
  double _lastTouchX = 0;
  double _lastTouchY = 0;
  _SwipeAxis? _lastSwipeAxis;
  DateTime? _lastSwipeAt;
  DateTime? _lastDirectionalInputAt;
  DateTime? _lastSyntheticSelectAt;
  DateTime? _lastAcceptedNativeSelectDownAt;
  DateTime? _lastAcceptedNativeSelectUpAt;
  int _suppressedNativeSelectDowns = 0;
  bool _nativeSelectPressed = false;

  /// Correlation id of the Select press that is currently down.
  ///
  /// Deliberately separate from [_nativeSelectPressed]: that flag is
  /// duplicate-suppression bookkeeping and gets cleared on paths that have
  /// nothing to do with the press reaching a widget. Overloading it as the
  /// correlation carrier would tie the trace's lifetime to the wrong rule.
  String? _openSelectTraceId;
  bool _selectPressedFromClick = false;
  _DirectionalOwner _directionalOwner = _DirectionalOwner.none;
  DateTime? _directionalOwnerExpiresAt;
  // Separate from the gesture-ownership bookkeeping above, which decides which
  // path may move the focus: this one answers "was this direction a swipe?"
  // for widgets that treat a swipe and a clickpad press differently.
  final Map<LogicalKeyboardKey, DateTime> _lastSwipeDirectionalAt = {};

  /// SCRUB1: set while the player's free scrub owns the touch surface. The
  /// pan then goes here as horizontal travel instead of being quantised into
  /// arrow keys (one per [swipeThreshold], at most one per
  /// [swipeRepeatInterval]), which is what made each swipe move one step.
  ScrubPanHandler? _scrubPanHandler;
  bool _scrubPanEngaged = false;
  double _scrubPanPending = 0;
  final List<(DateTime, double)> _scrubPanSamples = [];
  // Set when the scrub lets go of the pan while the finger is still down (the
  // commit or Menu click): the rest of that touch must not turn into arrows.
  bool _swallowGestureTail = false;

  AppleTvRemoteTouchService({
    BasicMessageChannel<dynamic>? channel,
    BasicMessageChannel<dynamic>? pressDiagChannel,
    void Function(LogicalKeyboardKey logicalKey)? simulateKeyPress,
    void Function(LogicalKeyboardKey logicalKey)? simulateKeyDown,
    void Function(LogicalKeyboardKey logicalKey)? simulateKeyUp,
    VoidCallback? scheduleFrame,
    DateTime Function()? now,
    GamepadDuplicateInputGuard? duplicateInputGuard,
    SelectTraceRecorder? traceRecorder,
    Duration duplicateSuppressionWindow = GamepadDuplicateInputGuard.defaultSuppressionWindow,
    this.swipeThreshold = defaultSwipeThreshold,
    this.axisSwitchDominanceRatio = defaultAxisSwitchDominanceRatio,
    this.swipeRepeatInterval = defaultSwipeRepeatInterval,
    this.clickAfterDirectionSuppression = defaultClickAfterDirectionSuppression,
    this.gestureOwnershipGrace = defaultGestureOwnershipGrace,
    this.swipeAttributionWindow = defaultSwipeAttributionWindow,
    this.nativeSwipeClassifyDistance = defaultNativeSwipeClassifyDistance,
  }) : assert(axisSwitchDominanceRatio >= 1),
       _channel = channel ?? const BasicMessageChannel<dynamic>(_channelName, JSONMessageCodec()),
       _pressDiagChannel =
           pressDiagChannel ?? const BasicMessageChannel<dynamic>(_pressDiagChannelName, JSONMessageCodec()),
       _simulateKeyPress = simulateKeyPress ?? key_sim.simulateKeyPress,
       _simulateKeyDown = simulateKeyDown ?? key_sim.simulateKeyDown,
       _simulateKeyUp = simulateKeyUp ?? key_sim.simulateKeyUp,
       _scheduleFrame = scheduleFrame ?? key_sim.scheduleFrameIfIdle,
       _now = now ?? DateTime.now,
       _traceRecorder = traceRecorder ?? SelectTraceRecorder.instance,
       _duplicateInputGuard =
           duplicateInputGuard ?? GamepadDuplicateInputGuard(now: now, suppressionWindow: duplicateSuppressionWindow);

  Stream<AppleTvRemotePlayPauseAction> get playPauseActions => _playPauseController.stream;

  /// Whether a Siri-remote touch gesture is currently in progress (finger down).
  /// Cleared when the touch ends or cancels. tvOS-only; `false` elsewhere.
  bool get isTouchActive => _touchActive;

  /// Listenable mirror of [isTouchActive] so widgets can react when the active
  /// touch gesture ends (used to extend Home-rail select suppression).
  ValueListenable<bool> get touchActiveListenable => _touchActiveNotifier;

  /// Whether [key] was most recently produced by a touch-surface swipe rather
  /// than a directional clickpad press. True only within
  /// [swipeAttributionWindow] of the swipe, because synthetic keys reach
  /// widgets a frame after they are tagged. tvOS-only; `false` elsewhere.
  bool isSwipeDirectional(LogicalKeyboardKey key) {
    final taggedAt = _lastSwipeDirectionalAt[key];
    if (taggedAt == null) return false;
    return _now().difference(taggedAt).abs() <= swipeAttributionWindow;
  }

  /// Route horizontal touch-surface travel to [handler] instead of
  /// synthesising arrows. The gesture is re-anchored on the finger, so travel
  /// from before the scrub began is not replayed into the cursor.
  void setScrubPanHandler(ScrubPanHandler handler) {
    _scrubPanHandler = handler;
    _swallowGestureTail = false;
    _reanchorGesture();
    _log('scrub pan on');
  }

  /// Hand the touch surface back to swipe-to-arrow, but only when [handler] is
  /// still the registered one. The rest of a touch that is still down is
  /// swallowed, so the commit click never becomes a seek arrow.
  void releaseScrubPanHandler(ScrubPanHandler handler) {
    if (!identical(_scrubPanHandler, handler)) return;
    _scrubPanHandler = null;
    _swallowGestureTail = _touchActive;
    _reanchorGesture();
    _log('scrub pan off swallowTail=$_swallowGestureTail');
  }

  void _reanchorGesture() {
    _startX = _anchorX = _lastTouchX;
    _startY = _anchorY = _lastTouchY;
    _lastSwipeAxis = null;
    _lastSwipeAt = null;
    _scrubPanEngaged = false;
    _scrubPanPending = 0;
    _scrubPanSamples
      ..clear()
      ..add((_now(), _lastTouchX));
  }

  bool get isScrubPanActive => _scrubPanHandler != null;

  void start() {
    if (_listening) return;
    _channel.setMessageHandler(handleMessage);
    _pressDiagChannel.setMessageHandler(_handlePressDiagnostic);
    _registerNativeKeyHandler();
    _listening = true;
    appLogger.i('AppleTvRemoteTouchService: Listening for tvOS touch remote events');
  }

  void stop() {
    if (!_listening) return;
    _channel.setMessageHandler(null);
    _pressDiagChannel.setMessageHandler(null);
    _unregisterNativeKeyHandler();
    _duplicateInputGuard.clear();
    _resetNativeSelectBurstState();
    _directionalOwner = _DirectionalOwner.none;
    _directionalOwnerExpiresAt = null;
    _lastSwipeDirectionalAt.clear();
    _releaseSelectFromClick(source: 'stop');
    _resetTouch();
    _listening = false;
  }

  /// Every key this handler decided to swallow, so [blockConsumedKeyEvent] can
  /// swallow the same one where it counts. Identity, not a copy of the key:
  /// both hooks are handed the very same [KeyEvent] instance out of one
  /// `KeyMessage`, and a key-based match would also block the honest second
  /// press of the same direction.
  KeyEvent? _consumedEvent;

  /// The early key handler, and the only place a consumed press actually
  /// stops.
  ///
  /// Returning `true` from [handleNativeKeyEvent] does not stop anything.
  /// `KeyEventManager.handleKeyData` (SDK 3.44,
  /// `services/hardware_keyboard.dart:1118`) reads
  ///
  /// ```dart
  /// _hardwareKeyboard.handleKeyEvent(event);
  /// _dispatchKeyMessage(<KeyEvent>[event], null);
  /// ```
  ///
  /// — the result of the first line is discarded, and the message goes to
  /// `FocusManager` regardless. Log `3zsde` of 5 September 2026 (build 252)
  /// shows both halves one millisecond apart: `consume native keydown
  /// reason=repeated-pair-without-touch age=99ms`, and directly under it
  /// `FocusableWrapper: result=KeyEventResult.handled reason=onNavigateLeft`.
  /// The duplicate was recognised and moved the focus anyway, so NAV1 stayed
  /// open with a fix that logged success.
  ///
  /// `FocusManager._handleKeyMessage` runs its early handlers before it walks
  /// the focus tree and returns straight away on `handled`
  /// (`widgets/focus_manager.dart:2233-2256`), which is what
  /// `AppleTvNativeTextEntry` already relies on for the keyboard session.
  KeyEventResult blockConsumedKeyEvent(KeyEvent event) {
    if (!identical(event, _consumedEvent)) return KeyEventResult.ignored;
    _consumedEvent = null;
    _log('block consumed ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)}');
    return KeyEventResult.handled;
  }

  bool handleNativeKeyEvent(KeyEvent event) {
    final consumed = _decideNativeKeyEvent(event);
    if (consumed) _consumedEvent = event;
    return consumed;
  }

  bool _decideNativeKeyEvent(KeyEvent event) {
    _log('native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)}');
    if (event is KeyDownEvent && _isSelectKey(event.logicalKey)) _scrubPanPending = 0;
    if (_isMediaPlaybackKey(event.logicalKey)) {
      _log('consume native media key reason=direct-playback-action');
      return true;
    }
    // Unreachable while the native press hook works, and kept for the day it
    // does not.
    //
    // `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)` answers
    // `false` for the whole session, so the engine claims no press and Dart
    // never receives a key event to gate. The one exception is the tail of the
    // press that opened the keyboard: its key-down came before the session
    // existed, and the key-up arrives here afterwards. That is also why
    // `_releaseSelectOwnershipForNativeSession()` below still has work to do.
    //
    // Anything beyond that means the hook stopped yielding, and then this is
    // only a first line anyway: answering "handled" here does not stop
    // FocusManager from walking the focus tree. The layer that actually stops
    // the press is the early key handler in AppleTvNativeTextEntry, which logs
    // the same failure.
    if (NativeInputSession.isActive) {
      _releaseSelectOwnershipForNativeSession();
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
      // Only keys that actually reach the app need an attribution: a consumed
      // one never gets to a widget that could ask about it.
      if (event is KeyDownEvent) _tagNativeDirectionalAttribution(event.logicalKey);
    }
    return _duplicateInputGuard.handleNativeKeyEvent(event);
  }

  /// NAV2: logs station 3 of the press pipeline into the app log. Read-only:
  /// no state changes, nothing consumed, no reply.
  Future<dynamic> _handlePressDiagnostic(dynamic arguments) async {
    if (arguments is! Map) return null;
    _log(
      'native press=${arguments['press']} phase=${arguments['phase']} '
      'uipress=${arguments['uipress']} t=${arguments['systemUptimeMs']} ts=${arguments['uikitMs']}'
      '${arguments['hw'] is String ? ' ${arguments['hw']}' : ''}',
    );
    return null;
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
      _releaseSelectOwnershipForNativeSession();
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
        // A click is no pan: a saved remainder must not add up with the
        // click's jitter into one last cursor step.
        _scrubPanPending = 0;
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
    // A new touch is a new physical gesture: whatever native pair completed
    // before it may legitimately repeat now.
    _startX = x;
    _startY = y;
    _anchorX = x;
    _anchorY = y;
    _lastTouchX = x;
    _lastTouchY = y;
    _lastSwipeAxis = null;
    _lastSwipeAt = null;
    _swallowGestureTail = false;
    _scrubPanEngaged = false;
    _scrubPanPending = 0;
    _scrubPanSamples
      ..clear()
      ..add((_now(), x));
    // A claim still under its post-lift grace belongs to a gesture that is
    // very probably this one, so carry it in and hold it for as long as the
    // finger is down. Which path made the claim does not change that.
    //
    // For a swipe claim this is the old rule: consecutive fast swipes must not
    // let the previous gesture's trailing native arrow in. For a *native*
    // claim it is the physical Apple TV finding. A click on the remote's ring
    // is a touch and a press at once, and tvOS reports the two over separate
    // paths; the press regularly reaches Flutter a few milliseconds before the
    // touch stream does. Dropping the claim here — on the reasoning that a
    // ring click starts a fresh gesture — meant the travel of that same finger
    // crossed the swipe threshold with nobody owning the gesture, and the
    // click moved the focus twice. One press, two steps, one destination
    // skipped: LEFT on Series landed on Search, and DOWN on a landing walked
    // past the first rail. What had been hiding it is the per-key duplicate
    // window, which is 120 ms and only ever catches the second arrow when it
    // happens to be the same key.
    if (_currentDirectionalOwner() != _DirectionalOwner.none) {
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

    if (_swallowGestureTail) {
      _lastTouchX = x;
      _lastTouchY = y;
      return;
    }

    final scrubPan = _scrubPanHandler;
    if (scrubPan != null) {
      _moveScrubPan(scrubPan, x, y);
      return;
    }

    // Track the live position before any early return, so moves swallowed by
    // the repeat cooldown or by the native path owning this gesture still build
    // up travel distance for the classifier.
    _lastTouchX = x;
    _lastTouchY = y;

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

  void _moveScrubPan(ScrubPanHandler scrubPan, double x, double y) {
    final now = _now();
    final previousX = _lastTouchX;
    _lastTouchX = x;
    _lastTouchY = y;
    _scrubPanSamples
      ..add((now, x))
      ..removeWhere((sample) => now.difference(sample.$1) > scrubPanSpeedWindow);
    final travelX = (x - _startX).abs();
    final travelY = (y - _startY).abs();
    // A horizontal pan owns the gesture, so tvOS' own swipe arrow (and its
    // trailing copy after the lift, see [gestureOwnershipGrace]) does not also
    // step the timeline. A ring click keeps the finger still and stays a
    // press; a vertical swipe still leaves the scrub as before.
    if (travelX >= nativeSwipeClassifyDistance &&
        travelX > travelY &&
        _currentDirectionalOwner() != _DirectionalOwner.swipe) {
      _claimDirectionalOwner(_DirectionalOwner.swipe);
    }
    if (!_scrubPanEngaged) {
      if (travelX < scrubPanSlop) return;
      _scrubPanEngaged = true;
      // The slop travel happened over an unknown stretch: no speed, gain 1.
      scrubPan(x - _startX, 0);
      return;
    }
    _scrubPanPending += x - previousX;
    if (_scrubPanPending.abs() < scrubPanDeadZone) return;
    final dx = _scrubPanPending;
    _scrubPanPending = 0;
    scrubPan(dx, _scrubPanSpeed(now, x));
  }

  /// Average horizontal speed in points per millisecond over
  /// [scrubPanSpeedWindow].
  double _scrubPanSpeed(DateTime now, double x) {
    final (oldestAt, oldestX) = _scrubPanSamples.first;
    final minMs = scrubPanMinSpeedInterval.inMicroseconds / 1000;
    final elapsedMs = now.difference(oldestAt).inMicroseconds / 1000;
    return (x - oldestX).abs() / (elapsedMs < minMs ? minMs : elapsedMs);
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
    _openSelectTraceId = _beginSelectTrace('click_s');
    _log('emit keydown=${_keyName(LogicalKeyboardKey.enter)} source=click_s');
    _simulateKeyDown(LogicalKeyboardKey.enter);
  }

  /// Releases whichever half of select ownership was in flight when a native
  /// surface took over the remote — the click-driven synthetic press and the
  /// native-press burst-tracking flags are separate state machines, and a
  /// session can interrupt either one.
  ///
  /// A click-driven press arrives as `click_s` → key-down → the button opens
  /// the keyboard, and the matching `click_e` then lands with the session
  /// already active and gets dropped; without releasing it,
  /// `_selectPressedFromClick` stays true and `_shouldConsumeNativeSelectDuplicate`
  /// eats the *next* real select as an in-flight duplicate. The synthetic
  /// key-up itself is swallowed by the gate in [key_sim.simulateKeyUp]; only
  /// the bookkeeping matters here.
  ///
  /// A native press (SEL1, `docs/tvos-fysieke-correctieronde.md:194`) sets
  /// `_nativeSelectPressed` on its key-down. If the session opens before that
  /// press's own key-up arrives, the up is routed here instead of to
  /// `_shouldConsumeNativeSelectDuplicate` — the only other place that clears
  /// the flag — so without resetting the native burst state too,
  /// `_nativeSelectPressed` stayed latched for the rest of the app run: every
  /// later Select logged `native-select-already-down` and did nothing until
  /// an app restart.
  void _releaseSelectOwnershipForNativeSession() {
    if (_selectPressedFromClick) {
      _releaseSelectFromClick(source: 'native-input-session');
    }
    _resetNativeSelectBurstState();
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
    // Capture the id before anything else is cleared, then hand it to the
    // recorder for the synchronous dispatch below. The row reads it there and
    // carries it onwards itself; nothing may look it up again afterwards.
    final traceId = _openSelectTraceId;
    _openSelectTraceId = null;
    _traceRecorder.dispatchSelect(traceId);
    _log('emit keyup=${_keyName(LogicalKeyboardKey.enter)} source=$source');
    _simulateKeyUp(LogicalKeyboardKey.enter);
  }

  /// Opens a trace for a press that is going down now.
  ///
  /// Drops whatever was still open first. A key-down whose key-up never arrives
  /// is normal here: a native text-input session can open over the press, and
  /// the release is then consumed rather than delivered. Left alone, that
  /// orphan would sit in the recorder until it got evicted, and eviction emits
  /// a warning about a press that simply never finished.
  String? _beginSelectTrace(String source) {
    _traceRecorder.abandon(_openSelectTraceId, 'select-down-superseded');
    _openSelectTraceId = null;
    return _traceRecorder.beginSelect(source: source);
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
      _openSelectTraceId = _beginSelectTrace('native');
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

      // Synchronously, and before the pressed flag is cleared: this method
      // returns false, so Flutter dispatches the release into the focus tree
      // right after and the latch has to be standing by then.
      final traceId = _openSelectTraceId;
      _openSelectTraceId = null;
      _traceRecorder.dispatchSelect(traceId);
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
  /// A duplicate directional press is **not** filtered here, deliberately.
  ///
  /// NAV1's second pair was first attacked from this side: track the last
  /// completed pair, veto a repeat of the same key that no new touch preceded.
  /// It shipped as build 254 and was wrong. Log `ld1t1` shows it swallowing 65
  /// real presses — the window does not slide, so one delivered press blacked
  /// out the next half second, and fast clicking through a rail lost four
  /// presses in five. Every discriminator available in Dart was measured
  /// against three device logs and each one failed on at least one of them: the
  /// gap (80-230 ms) overlaps how fast a viewer clicks, the keydown-to-keyup
  /// duration is 4 ms in one log and 120 ms in another for the *same* honest
  /// press, and the touch stream carries no event between the two pairs.
  ///
  /// The signal that does separate them exists one layer down. Log `wa6v9`
  /// (build 255) pinned NAV1's actual cause: landing on the Home tab enables
  /// the Menu passthrough, which makes the engine release every key it still
  /// holds (`releaseAllSynthesizedPresses`), and the arrow's own `.ended` then
  /// re-taps the released key as a fresh pair (`tapIfMissingKeyDown:YES`): one
  /// press, two steps. A phase filter in `AppDelegate.swift` was tried and
  /// measured worse than the defect on both sides (swallowing a phase hangs
  /// the engine's repeat timer, build 257; forwarding one crashes UIKit's
  /// `_verifyTrackingPresses:`, build 256) and is gone (`5c0db0a1`). The
  /// shipped fix sits at the sender instead: `TvosSystemNavigationService`
  /// parks the passthrough enable until `HardwareKeyboard.physicalKeysPressed`
  /// is empty (`7786a952`), so the release this comment describes has nothing
  /// left to re-tap by the time it goes out.
  ///
  /// That fix does not cover every path that can leave a stale entry in the
  /// engine's `synthesizedPressedKeys`; see `docs/tvos-remote-input-authority.md`
  /// for a fourth, still-open candidate (RAIL2) with no channel message
  /// involved at all. Do not reintroduce a timing rule here regardless; it
  /// cannot be made correct with what this layer can see, and a fix for
  /// whatever RAIL2 turns out to be belongs at the layer the evidence points
  /// to, not as a heuristic added to this function.
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

  /// Record whether a native directional key that reached the app came from a
  /// swipe or from a clickpad press, so [isSwipeDirectional] can answer for it.
  void _tagNativeDirectionalAttribution(LogicalKeyboardKey key) {
    if (_isNativeDirectionalFromSwipe(key)) {
      _lastSwipeDirectionalAt[key] = _now();
      return;
    }
    // Near-still finger means a clickpad press; drop any stale swipe tag so the
    // press wins the attribution.
    _lastSwipeDirectionalAt.remove(key);
  }

  /// Classify a native directional key that reached the app: a finger on the
  /// surface that has travelled along the key's axis is a swipe, a nearly
  /// still finger is a clickpad press.
  bool _isNativeDirectionalFromSwipe(LogicalKeyboardKey key) {
    if (!_touchActive) {
      _log('classify native logical=${_keyName(key)} verdict=press reason=no-active-touch');
      return false;
    }
    final isVertical = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown;
    final distance = isVertical ? (_startY - _lastTouchY).abs() : (_startX - _lastTouchX).abs();
    final isSwipe = distance >= nativeSwipeClassifyDistance;
    _log(
      'classify native logical=${_keyName(key)} verdict=${isSwipe ? 'swipe' : 'press'} '
      'distance=${_formatDouble(distance)} threshold=${_formatDouble(nativeSwipeClassifyDistance)}',
    );
    return isSwipe;
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
    _traceRecorder.abandon(_openSelectTraceId, 'native-select-state-reset');
    _openSelectTraceId = null;
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
        _lastSwipeDirectionalAt[logicalKey] = _lastDirectionalInputAt!;
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

  /// Both hooks, always together: the first decides, the second enforces.
  /// Registering only the [HardwareKeyboard] half is what NAV1 shipped as, and
  /// it silently does nothing — see [blockConsumedKeyEvent].
  void _registerNativeKeyHandler() {
    if (_nativeKeyHandlerRegistered) return;
    HardwareKeyboard.instance.addHandler(handleNativeKeyEvent);
    FocusManager.instance.addEarlyKeyEventHandler(blockConsumedKeyEvent);
    _nativeKeyHandlerRegistered = true;
  }

  void _unregisterNativeKeyHandler() {
    if (!_nativeKeyHandlerRegistered) return;
    HardwareKeyboard.instance.removeHandler(handleNativeKeyEvent);
    FocusManager.instance.removeEarlyKeyEventHandler(blockConsumedKeyEvent);
    _consumedEvent = null;
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
