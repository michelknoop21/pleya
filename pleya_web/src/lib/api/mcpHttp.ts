/** MCP staat buiten OpenAPI, maar gebruikt dezelfde HTTP-authenticatie. */
export interface McpToolSummary {
  name: string;
  description?: string;
  annotations?: { readOnlyHint?: boolean };
}

export interface McpHttpPaths {
  '/mcp': {
    post: {
      requestBody: {
        content: {
          'application/json': { jsonrpc: '2.0'; id: number; method: 'tools/list'; params: Record<string, never> };
        };
      };
      responses: {
        200: { content: { 'application/json': { result?: { tools?: unknown }; error?: unknown } } };
      };
    };
  };
}

export function isMcpToolSummary(value: unknown): value is McpToolSummary {
  if (value === null || typeof value !== 'object') return false;
  const tool = value as Record<string, unknown>;
  if (typeof tool.name !== 'string' || tool.name.length === 0) return false;
  if (tool.description !== undefined && typeof tool.description !== 'string') return false;
  if (tool.annotations === undefined) return true;
  if (tool.annotations === null || typeof tool.annotations !== 'object') return false;
  const hint = (tool.annotations as Record<string, unknown>).readOnlyHint;
  return hint === undefined || typeof hint === 'boolean';
}
