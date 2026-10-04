import 'assistant_provider.dart';
import 'assistant_run.dart';
import 'assistant_tools.dart';

enum AssistantTaskStatus { pending, running, waitingForConfirmation, completed, failed, cancelled }

/// An immutable view of one independent command. IDs are controller generated.
class AssistantTask {
  const AssistantTask({
    required this.id,
    required this.title,
    required this.intent,
    required this.status,
    required this.answer,
    required this.displays,
    required this.steps,
    required this.actions,
    this.error,
    this.lastEnd,
    this.providerError,
    this.modelMissing = false,
    this.pending,
  });
  final String id;
  final String title;
  final String intent;
  final AssistantTaskStatus status;
  final String answer;
  final List<AssistantDisplay> displays;
  List<AssistantDisplay> get results => displays;
  final List<AssistantStep> steps;
  final List<AssistantActionRecord> actions;

  /// Concrete failure code, independent of the model's closing words.
  final String? error;
  final AssistantRunEnd? lastEnd;
  final AssistantModelError? providerError;
  final bool modelMissing;
  final AssistantPendingAction? pending;
}

/// Identity of the visible confirmation. A response must name both IDs.
class AssistantTaskConfirmation {
  const AssistantTaskConfirmation({required this.id, required this.taskId, required this.action});
  final String id;
  final String taskId;
  final AssistantPendingAction action;
}
