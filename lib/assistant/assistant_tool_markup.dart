import 'dart:convert';

// A tool call the model wrote into its message text instead of the tool
// calls field. Such text is never an answer: it is not shown, not kept as a
// turn and not executed (a call parsed from prose would skip the checks of
// the normal tool path).

/// Tags some models use for written-out calls: `<function_calls>`,
/// `<atem:function_calls>`, `<invoke name="…">`, `<tool_call>`,
/// `<function=name>`. A bare `<invoke>` or `<Title>` in prose is no match.
final _markupTag = RegExp(
  r'<\s*/?\s*(?:[\w-]+:)?(?:function_calls?|tool_calls?|tool_use)\s*/?>'
  r'|<\s*/?\s*(?:[\w-]+:)?function_calls?\b[^>\n]*>'
  r'|<\s*(?:[\w-]+:)?invoke\s+name\s*='
  r'|<\s*function\s*=\s*[\w.*-]+\s*>',
  caseSensitive: false,
);

/// Special tokens: `<|tool_call|>`, `<|python_tag|>`, DeepSeek's full-width
/// `<｜tool▁calls▁begin｜>` and Mistral's `[TOOL_CALLS]`.
final _markupToken = RegExp(
  r'<[|｜][^>\n]{0,40}(?:tool|function|python_tag)[^>\n]{0,40}[|｜]>|\[TOOL_CALLS\]',
  caseSensitive: false,
);

final _fence = RegExp(r'^```[\w-]*\s*\n?([\s\S]*?)\n?```$');

const _callKeys = {'name', 'arguments', 'parameters', 'type', 'id'};

bool _isCall(Object? value) {
  if (value is! Map) return false;
  if (value['function'] is Map && value.keys.every((k) => k == 'function' || k == 'type' || k == 'id')) {
    return _isCall(value['function']);
  }
  return value['name'] is String &&
      (value.containsKey('arguments') || value.containsKey('parameters')) &&
      value.keys.every(_callKeys.contains);
}

/// True when [text] holds a tool call written as text: markup tags or
/// tokens anywhere, or a whole reply that is only `{"name": …,
/// "arguments"|"parameters": …}` (or a list of those), fenced or not.
bool assistantLooksLikeToolMarkup(String text) {
  if (_markupTag.hasMatch(text) || _markupToken.hasMatch(text)) return true;
  var body = text.trim();
  if (_fence.firstMatch(body) case final m?) body = m[1]!.trim();
  if (!(body.startsWith('{') || body.startsWith('['))) return false;
  try {
    final decoded = jsonDecode(body);
    if (decoded is List) return decoded.isNotEmpty && decoded.every(_isCall);
    return _isCall(decoded);
  } on FormatException {
    return false;
  }
}
