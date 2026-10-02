part of 'assistant_tools.dart';

/// Smart search over every library, rows on Home and collections, all from one query shape.
///
/// Wired into [AssistantToolContext] by the UI layer; absent services keep
/// these tools out of the run.
class AssistantCatalogServices {
  const AssistantCatalogServices();
}

final List<AssistantTool> _catalogTools = [];
