import 'dart:convert';

// A tool call the model wrote into its message text instead of the tool
// calls field. Such text is never an answer: it is not shown, not kept as a
// turn and not executed (a call parsed from prose would skip the checks of
// the normal tool path).

/// Tags some models use for written-out calls: `<function_calls>`,
/// `<atem:function_calls>`, `<invoke name="…">`, `<tool_call>`,
/// `<function=name>` and GLM's `<arg_key>`/`<arg_value>`. A bare `<invoke>`
/// or `<Title>` in prose is no match.
final _markupTag = RegExp(
  r'<\s*/?\s*(?:[\w-]+:)?(?:function_calls?|tool_calls?|tool_use)\s*/?>'
  r'|<\s*/?\s*(?:[\w-]+:)?function_calls?\b[^>\n]*>'
  r'|<\s*(?:[\w-]+:)?invoke\s+name\s*='
  r'|<\s*function\s*=\s*[\w.*-]+\s*>'
  r'|</?\s*arg_(?:key|value)\s*>',
  caseSensitive: false,
);

/// Special tokens: `<|tool_call|>`, `<|python_tag|>`, DeepSeek's full-width
/// `<｜tool▁calls▁begin｜>`, Mistral's `[TOOL_CALLS]` and Gemma 4's
/// `<|tool_call>call:fn{…}<tool_call|>` (ai.google.dev/gemma/docs/capabilities/
/// text/function-calling-gemma4).
final _markupToken = RegExp(
  r'<[|｜][^>\n]{0,40}(?:tool|function|python_tag)[^>\n]{0,40}[|｜]>'
  r'|<\|tool_call>|<tool_call\|>|\[TOOL_CALLS\]',
  caseSensitive: false,
);

/// The fenced block Gemma and Llama write their pythonic calls in.
final _toolCodeFence = RegExp(r'```\s*tool_(?:code|calls?)\b', caseSensitive: false);

// One keyword-argument call, `find_title(q="Up")`. Positional or prose-like
// arguments do not match, so "Up (2009)" and "find_title(q)" stay text.
const _arg = r'''\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^,()\s][^,()]*)''';
const _call = '[A-Za-z_][\\w.]*\\(\\s*(?:$_arg(?:\\s*,\\s*$_arg)*)?\\s*\\)';
final _pythonicCalls = RegExp('^\\[\\s*$_call(?:\\s*,\\s*$_call)*\\s*\\]\$');

final _fence = RegExp(r'^```[\w-]*\s*\n?([\s\S]*?)\n?```$');

bool _hasKeys(Map value, Set<String> allowed) => value.keys.every(allowed.contains);

bool _isCall(Object? value) {
  if (value is! Map) return false;
  if (value['function'] is Map && _hasKeys(value, const {'function', 'type', 'id'})) {
    return _isCall(value['function']);
  }
  if (value['tool_calls'] is List && value.length == 1) {
    final calls = value['tool_calls'] as List;
    return calls.isNotEmpty && calls.every(_isCall);
  }
  if (value['function_call'] is Map && value.length == 1) return _isCall(value['function_call']);
  final hasArgs = value.containsKey('arguments') || value.containsKey('parameters');
  if (value['name'] is String && hasArgs && _hasKeys(value, const {'name', 'arguments', 'parameters', 'type', 'id'})) {
    return true;
  }
  // {"tool": "x", "args": {...}}
  return value['tool'] is String &&
      (value.containsKey('args') || hasArgs) &&
      _hasKeys(value, const {'tool', 'args', 'arguments', 'parameters'});
}

bool _isCallJson(String body) {
  if (!(body.startsWith('{') || body.startsWith('['))) return false;
  try {
    final decoded = jsonDecode(body);
    if (decoded is List) return decoded.isNotEmpty && decoded.every(_isCall);
    return _isCall(decoded);
  } on FormatException {
    return false;
  }
}

/// True when [text] holds a tool call written as text: markup tags or
/// tokens anywhere, a pythonic call, or a call as JSON that is the whole
/// reply or its tail after some prose (`{"name": …, "arguments"|"parameters":
/// …}`, `{"tool_calls": […]}`, `{"function_call": …}`, `{"tool": …, "args":
/// …}`), fenced or not.
bool assistantLooksLikeToolMarkup(String text) {
  if (_markupTag.hasMatch(text) || _markupToken.hasMatch(text) || _toolCodeFence.hasMatch(text)) return true;
  var body = text.trim();
  if (_fence.firstMatch(body) case final m?) body = m[1]!.trim();
  if (_pythonicCalls.hasMatch(body) || _isCallJson(body)) return true;
  // Prose followed by a bare call at the end: try each object start, latest
  // first, in the tail only.
  if (body.endsWith('```')) body = body.substring(0, body.length - 3).trimRight();
  if (!body.endsWith('}')) return false;
  final tail = body.length > 4000 ? body.substring(body.length - 4000) : body;
  var tried = 0;
  for (var i = tail.lastIndexOf('{'); i > 0 && tried < 30; i = tail.lastIndexOf('{', i - 1), tried++) {
    if (_isCallJson(tail.substring(i))) return true;
  }
  return false;
}
