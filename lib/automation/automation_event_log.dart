import 'package:flutter/foundation.dart';

/// One entry of the monotone app-event stream `GET /v1/events?since=N` reads.
/// `seq` only ever increases, so a cursor never needs to look back — see
/// pleya_verify/contract/verify_api_v1.md for the event vocabulary.
@immutable
class AutomationEvent {
  final int seq;
  final String name;
  final Map<String, Object?> data;
  final DateTime at;

  const AutomationEvent({required this.seq, required this.name, required this.data, required this.at});

  Map<String, Object?> toJson() => {'seq': seq, 'name': name, 'data': data, 'at': at.toIso8601String()};
}

/// Process-wide, bounded event log. Pure and always active — like
/// `AutomationRegistry`, the `kPleyaVerify` gate lives at each *call site*
/// (e.g. `AutomationFocusLog` only calls [emit] once its own `start()` ran
/// under `kPleyaVerify`), not inside this primitive, so it stays directly
/// unit-testable without a build define.
class AutomationEventLog {
  AutomationEventLog._();

  static AutomationEventLog instance = AutomationEventLog._();

  @visibleForTesting
  static void debugSetInstance(AutomationEventLog? log) {
    instance = log ?? AutomationEventLog._();
  }

  static const int _maxEvents = 500;

  final List<AutomationEvent> _events = [];
  int _nextSeq = 1;

  void emit(String name, [Map<String, Object?> data = const {}]) {
    _events.add(AutomationEvent(seq: _nextSeq++, name: name, data: data, at: DateTime.now()));
    if (_events.length > _maxEvents) _events.removeAt(0);
  }

  /// Events with `seq > since`, oldest first.
  List<AutomationEvent> since(int since) => _events.where((e) => e.seq > since).toList();

  int get currentSeq => _nextSeq - 1;
}
