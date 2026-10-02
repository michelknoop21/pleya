part of 'assistant_tools.dart';

/// Asking for a title that is not in any library, through Seerr.
///
/// Wired into [AssistantToolContext] by the UI layer; absent services keep
/// these tools out of the run.
class AssistantRequestServices {
  const AssistantRequestServices();
}

final List<AssistantTool> _requestTools = [];
