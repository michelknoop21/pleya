import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../utils/key_event_simulator.dart';
import '../utils/native_input_session.dart';
import 'automation_event_log.dart';

/// Maps the `key` names `POST /v1/input/key` accepts to a
/// `LogicalKeyboardKey` — the same vocabulary as `scripts/tvos_sim.sh key`
/// (up/down/left/right/select/menu/delete), so a scenario author and a human
/// running the simulator script by hand share one vocabulary.
const Map<String, LogicalKeyboardKey> automationKeyNames = {
  'up': LogicalKeyboardKey.arrowUp,
  'down': LogicalKeyboardKey.arrowDown,
  'left': LogicalKeyboardKey.arrowLeft,
  'right': LogicalKeyboardKey.arrowRight,
  'select': LogicalKeyboardKey.select,
  'menu': LogicalKeyboardKey.escape,
  'delete': LogicalKeyboardKey.backspace,
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

enum AutomationInputResult { dispatched, blockedByNativeSession, unknownKey }

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
/// rather than calling a widget's callback directly.
AutomationInputResult dispatchAutomationPointerTap(Offset position) {
  if (NativeInputSession.isActive) return AutomationInputResult.blockedByNativeSession;
  AutomationInput.onPointerModeRequested?.call();
  scheduleFrameIfIdle();

  final pointer = _nextPointerId++;
  final binding = GestureBinding.instance;
  binding.handlePointerEvent(PointerAddedEvent(position: position));
  binding.handlePointerEvent(PointerDownEvent(pointer: pointer, position: position));
  binding.handlePointerEvent(PointerUpEvent(pointer: pointer, position: position));
  binding.handlePointerEvent(PointerRemovedEvent(position: position));
  AutomationEventLog.instance.emit('input.received', {'source': 'transport', 'x': position.dx, 'y': position.dy});
  return AutomationInputResult.dispatched;
}
