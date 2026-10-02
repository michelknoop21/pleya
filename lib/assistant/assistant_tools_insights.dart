part of 'assistant_tools.dart';

/// Admin insight across servers: what is missing where, what is being watched.
///
/// Wired into [AssistantToolContext] by the UI layer; absent services keep
/// these tools out of the run.
class AssistantInsightServices {
  const AssistantInsightServices();
}

final List<AssistantTool> _insightTools = [];
