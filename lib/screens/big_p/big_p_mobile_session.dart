import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_tool_context.dart';
import '../../widgets/big_p/assistant/big_p_results.dart';
import '../../widgets/big_p/assistant/big_p_suggestions.dart';

/// Where Big P stands on iPhone and iPad (mockup 39): in the face button,
/// out with his balloon, or peeking in from the side of a title he opened.
enum BigPStage { parked, out, peek }

/// Big P's place on a phone or tablet, one per profile next to its
/// [AssistantController]. Only the user moves him: [summon] brings him out,
/// [park] puts him back, [openedTitle] sends him to the peek. The answer
/// stays across a park, until it is [keepAnswer] old at the next summon.
class BigPMobileSession extends ChangeNotifier {
  BigPMobileSession(this.controller, {DateTime Function()? now, this.keepAnswer = const Duration(minutes: 30)})
    : _now = now ?? DateTime.now,
      _lastState = controller.state {
    // Already answered when the session is first read: that answer's age
    // starts now.
    if (_lastState == AssistantSurfaceState.result) _resultAt = _now();
    controller.addListener(_onController);
  }

  final AssistantController controller;

  /// How long an answer waits in the face button before a summon starts
  /// over (39 H).
  final Duration keepAnswer;
  final DateTime Function() _now;

  BigPStage _stage = BigPStage.parked;
  AssistantScreenContext? _pendingContext;
  String? _question;
  DateTime? _resultAt;
  AssistantSurfaceState _lastState;

  /// Item keys of the titles opened from the current answer.
  final Set<String> _opened = {};

  BigPStage get stage => _stage;

  /// When the shown answer came in; null before any.
  DateTime? get resultAt => _resultAt;

  /// A confirmation waits while Big P is not out (a pick ran on after a
  /// park): the face button shows a dot, Big P stays put.
  bool get waiting => _stage != BigPStage.out && controller.pending != null;

  /// The screen Big P was summoned from, for [AssistantController.beginListening].
  AssistantScreenContext? get pendingContext => _pendingContext;

  /// True while the availability read a [summon] started is in flight: a
  /// handed-over question waits for it before needsSetup lets it go.
  bool get refreshing => _refresh != null;
  Future<void>? _refresh;
  bool _disposed = false;

  /// What the user typed and has not sent. The input bar goes away while a
  /// confirmation is open and comes back with this text; it is never
  /// submitted by itself and lives and dies with this (per profile) session.
  String draft = '';

  /// A question handed over by Zoeken; read once.
  String? takeQuestion() {
    final question = _question;
    _question = null;
    return question;
  }

  /// Titles in the answer that are in a library and not opened yet: what
  /// the peek offers to go back to.
  int get remainingTitles => {
    for (final display in controller.displays)
      for (final match in bigPTitleMatches(display))
        if (match.targets.firstOrNull case final target?) target.item.globalKey,
  }.difference(_opened).length;

  /// Brings Big P out. Never called by Pleya on its own. From the peek the
  /// answer is kept whatever its age: the peek shows it is still there.
  void summon({AssistantScreenContext? context, String? question}) {
    final resultAt = _resultAt;
    if (_stage != BigPStage.peek &&
        controller.state == AssistantSurfaceState.result &&
        resultAt != null &&
        _now().difference(resultAt) >= keepAnswer) {
      controller.reset();
    }
    // Short of ready it asks again: a keychain that failed may have recovered.
    if (controller.availability != AssistantAvailability.ready) {
      final refresh = _refresh = controller.refreshAvailability();
      unawaited(
        refresh.whenComplete(() {
          if (_refresh != refresh) return;
          _refresh = null;
          // The host reads the handed-over question again with the answer.
          if (!_disposed) notifyListeners();
        }),
      );
    }
    // From the peek the answer's own context stays, for its follow-ups.
    if (context == null && _stage != BigPStage.peek) controller.clearScreenContext();
    _pendingContext = context;
    _question = question;
    BigPSuggestions.of(controller).summoned();
    // Notifies even when already out: a new question or context is news.
    _stage = BigPStage.out;
    notifyListeners();
  }

  /// Back into the face button; the answer stays. An ask in flight is let
  /// go and the controller is back in rust, as TV's dismiss ends. A waiting
  /// confirmation card keeps him out until the user picks (39 G).
  void park() {
    if (controller.pending != null) return;
    // The field unmounts with him and never blurs: let the mic go here.
    if (controller.state == AssistantSurfaceState.listening) controller.cancelListening();
    // A picked option works on the answer's displays (an ask streaming its
    // own displays is stillChecking): it finishes in the background and its
    // result shows at the next summon.
    final picking = controller.displays.isNotEmpty && !controller.stillChecking;
    if (controller.state == AssistantSurfaceState.working && !picking) {
      controller.abort();
      // abort() alone leaves the controller in working and busy: the next
      // summon would show a run that never ends.
      controller.reset();
    }
    _setStage(BigPStage.parked);
  }

  /// A title from the answer opened: Big P peeks from its detail page.
  void openedTitle(String itemKey) {
    _opened.add(itemKey);
    _setStage(BigPStage.peek);
  }

  void _onController() {
    final state = controller.state;
    // Only a finished run or pick: a cancelled mic (listening -> result)
    // shows the same old answer and keeps its age.
    if (state == AssistantSurfaceState.result && _lastState == AssistantSurfaceState.working) _resultAt = _now();
    // A new ask starts with no displays; a picked option keeps them.
    if (state == AssistantSurfaceState.idle ||
        (state == AssistantSurfaceState.working && controller.displays.isEmpty)) {
      _opened.clear();
      if (state == AssistantSurfaceState.idle) _resultAt = null;
    }
    _lastState = state;
  }

  void _setStage(BigPStage stage) {
    if (_stage == stage) return;
    _stage = stage;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_onController);
    super.dispose();
  }
}
