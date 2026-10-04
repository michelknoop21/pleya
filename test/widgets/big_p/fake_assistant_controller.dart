import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';

/// A controller the test drives by hand. Every action the surface can take
/// is recorded; state only changes where the real controller's would on
/// that call, or when the test sets it and calls [emit].
class FakeAssistantController extends AssistantController {
  FakeAssistantController() : super(buildContext: (_) => throw UnimplementedError(), rolloutEnabled: false);

  @override
  AssistantAvailability availability = AssistantAvailability.ready;
  @override
  AssistantSurfaceState state = AssistantSurfaceState.idle;
  @override
  bool resultIsError = false;
  @override
  AssistantRunEnd? lastEnd;
  @override
  String? prompt;
  @override
  String answer = '';
  @override
  List<AssistantStep> steps = [];
  @override
  List<AssistantActionRecord> actions = [];
  @override
  List<AssistantDisplay> displays = [];
  @override
  AssistantPendingAction? pending;
  @override
  bool stillChecking = false;

  final submitted = <String>[];
  final listenContexts = <AssistantScreenContext?>[];
  final confirmedPasswords = <String?>[];
  final picked = <AssistantRequestOption>[];
  var cancelledListening = 0;
  var cancelledPending = 0;
  var resets = 0;
  var aborts = 0;
  var refreshes = 0;

  void emit() => notifyListeners();

  /// Whether anything still listens, e.g. a session after a profile switch.
  bool get listened => hasListeners;

  @override
  Future<void> refreshAvailability() async => refreshes++;

  @override
  void beginListening({AssistantScreenContext? context}) {
    listenContexts.add(context);
    state = AssistantSurfaceState.listening;
    notifyListeners();
  }

  @override
  void cancelListening() {
    cancelledListening++;
    state = AssistantSurfaceState.idle;
    notifyListeners();
  }

  @override
  Future<void> submit(String prompt) async {
    submitted.add(prompt);
    this.prompt = prompt;
    state = AssistantSurfaceState.working;
    notifyListeners();
  }

  @override
  void confirmPending({String? password}) => confirmedPasswords.add(password);

  @override
  void cancelPending() => cancelledPending++;

  @override
  Future<void> pickRequestOption(AssistantRequestOption option, {bool fourK = false}) async => picked.add(option);

  @override
  void abort() => aborts++;

  @override
  void reset() => resets++;
}
