import 'dart:async';

/// Reservations are synchronous: concurrent runs cannot overspend a question.
class AssistantQuestionBudget {
  int _models = 0;
  int _tools = 0;
  bool reserveModel() {
    if (_models >= 20) return false;
    _models++;
    return true;
  }

  bool reserveTool() {
    if (_tools >= 30) return false;
    _tools++;
    return true;
  }
}

/// Limits actual operations rather than whole runs: a confirmation holds no
/// slot. A cancelled nonabortable operation retains its slot until it settles.
class AssistantOperationPool {
  AssistantOperationPool(this.limit);
  final int limit;
  int _active = 0;
  final List<Completer<void>> _waiting = [];

  Future<T> run<T>(Future<T> Function() operation) async {
    if (_active >= limit) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _active++;
    }
    try {
      return await operation();
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeAt(0).complete();
      }
    }
  }
}
