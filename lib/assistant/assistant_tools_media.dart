part of 'assistant_tools.dart';

/// Per-title chores: downloads for offline viewing and subtitles.
///
/// Wired into [AssistantToolContext] by the UI layer; absent services keep
/// these tools out of the run.
class AssistantMediaServices {
  const AssistantMediaServices();
}

final List<AssistantTool> _mediaTools = [];
