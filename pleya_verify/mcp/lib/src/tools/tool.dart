/// One MCP tool: its declaration for `tools/list`, and its handler for
/// `tools/call`. A handler returns the tool's own result payload (already
/// JSON-safe) or throws. [McpServer] is the only place that turns either
/// into the MCP `content`/`isError` envelope.
class Tool {
  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final Future<Map<String, Object?>> Function(Map<String, Object?> arguments) handler;

  const Tool({required this.name, required this.description, required this.inputSchema, required this.handler});

  Map<String, Object?> toJson() => {'name': name, 'description': description, 'inputSchema': inputSchema};
}
