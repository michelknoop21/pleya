import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show EditableTextState, FocusManager;

import '../utils/key_event_simulator.dart';
import '../utils/native_input_session.dart';
import 'automation_event_log.dart';

/// Maps the `key` names `POST /v1/input/key` accepts to a
/// `LogicalKeyboardKey` — the same vocabulary as `scripts/tvos_sim.sh key`
/// (up/down/left/right/select/menu/delete/play_pause), so a scenario author
/// and a human running the simulator script by hand share one vocabulary.
///
/// `pleya_verify/runner/lib/src/scenario/remote_keys.dart` carries the same
/// list for the runner, which cannot import this file; a test in the runner
/// parses this map and fails when the two drift apart.
const Map<String, LogicalKeyboardKey> automationKeyNames = {
  'up': LogicalKeyboardKey.arrowUp,
  'down': LogicalKeyboardKey.arrowDown,
  'left': LogicalKeyboardKey.arrowLeft,
  'right': LogicalKeyboardKey.arrowRight,
  'select': LogicalKeyboardKey.select,
  'menu': LogicalKeyboardKey.escape,
  'delete': LogicalKeyboardKey.backspace,
  'play_pause': LogicalKeyboardKey.mediaPlayPause,
};

/// Static hook `InputModeTracker` registers, on the model of
/// `GamepadService.onGamepadInput`/`CompanionRemoteReceiver.onRemoteInput`: a
/// synthetic pointer event must force pointer mode first, or the app-wide
/// `IgnorePointer` that shields content from stray mouse input during D-pad
/// navigation would swallow it.
class AutomationInput {
  AutomationInput._();

  static VoidCallback? onPointerModeRequested;
}

enum AutomationInputResult { dispatched, blockedByNativeSession, unknownKey, noEditableTarget }

/// `POST /v1/input/key`. tvOS scenario steps must never call this — see the
/// tvOS-invoerroute-invariant in pleya_verify/contract/verify_api_v1.md;
/// `TvosSimulatorDriver` routes `press`/`tap`/`type` through idb HID instead.
AutomationInputResult dispatchAutomationKey(String key) {
  if (NativeInputSession.isActive) return AutomationInputResult.blockedByNativeSession;
  final logicalKey = automationKeyNames[key];
  if (logicalKey == null) return AutomationInputResult.unknownKey;
  simulateKeyPress(logicalKey);
  AutomationEventLog.instance.emit('input.received', {'source': 'transport', 'key': key});
  return AutomationInputResult.dispatched;
}

int _nextPointerId = 1;

/// `POST /v1/input/pointer`. Synthesizes a tap (down + up) at [position] in
/// logical pixels, going through the real gesture-binding hit-test pipeline
/// rather than calling a widget's callback directly. [hold] keeps the
/// pointer down between the two events — long enough (comfortably past
/// Flutter's `kLongPressTimeout`) and this is a real long press, dispatched
/// through the same `onLongPress` gesture recognizer a finger would trigger,
/// not a synthetic callback invocation.
Future<AutomationInputResult> dispatchAutomationPointerTap(Offset position, {Duration? hold}) async {
  if (NativeInputSession.isActive) return AutomationInputResult.blockedByNativeSession;
  AutomationInput.onPointerModeRequested?.call();
  scheduleFrameIfIdle();

  final pointer = _nextPointerId++;
  final binding = GestureBinding.instance;
  binding.handlePointerEvent(PointerAddedEvent(position: position));
  binding.handlePointerEvent(PointerDownEvent(pointer: pointer, position: position));
  if (hold != null) await Future<void>.delayed(hold);
  binding.handlePointerEvent(PointerUpEvent(pointer: pointer, position: position));
  binding.handlePointerEvent(PointerRemovedEvent(position: position));
  AutomationEventLog.instance.emit('input.received', {
    'source': 'transport',
    'x': position.dx,
    'y': position.dy,
    if (hold != null) 'holdMs': hold.inMilliseconds,
  });
  return AutomationInputResult.dispatched;
}

/// `POST /v1/input/text`. Inserts [text] into the currently focused text
/// field, on the model of `tv_virtual_keyboard.dart`'s `_insert`: a
/// synthetic `KeyEvent` (the [dispatchAutomationKey] path) never reaches an
/// `EditableText`'s platform IME channel, so character entry has to go
/// through the focused field's `TextEditingController` directly, the same
/// way the TV virtual keyboard edits a field without a real keyboard.
AutomationInputResult dispatchAutomationText(String text) {
  if (NativeInputSession.isActive) return AutomationInputResult.blockedByNativeSession;

  final focusContext = FocusManager.instance.primaryFocus?.context;
  final editableState = focusContext?.findAncestorStateOfType<EditableTextState>();
  if (editableState == null) return AutomationInputResult.noEditableTarget;

  final controller = editableState.widget.controller;
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid ? (selection.start < selection.end ? selection.start : selection.end) : null;
  final end = selection.isValid ? (selection.start > selection.end ? selection.start : selection.end) : null;
  final insertAt = start ?? value.text.length;
  final replaceEnd = end ?? value.text.length;

  controller.value = value.copyWith(
    text: value.text.replaceRange(insertAt, replaceEnd, text),
    selection: TextSelection.collapsed(offset: insertAt + text.length),
    composing: TextRange.empty,
  );
  AutomationEventLog.instance.emit('input.received', {'source': 'transport', 'text': text});
  return AutomationInputResult.dispatched;
}
