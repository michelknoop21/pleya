import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tool_markup.dart';

// BP-11: a tool call the model wrote as text is recognised, ordinary answers
// (also with angle brackets or braces in them) are not.

void main() {
  group('tool-call markup', () {
    const positives = {
      'the tvOS report (16 Oct 2026)':
          '<atem:function_calls>\n<atem:invoke name="my_watching.*">\n</atem:invoke>\n</atem:function_calls>',
      'plain function_calls': '<function_calls><invoke name="find_title"></invoke></function_calls>',
      'invoke alone': '<invoke name="find_title">\n<parameter name="q">Up</parameter>\n</invoke>',
      'namespaced invoke, single quotes': "<x:invoke name='list_servers'>",
      'Hermes tool_call': '<tool_call>\n{"name": "find_title", "arguments": {"q": "Up"}}\n</tool_call>',
      'closing tag only': 'Even kijken.\n</tool_call>',
      'tool_calls wrapper': '<tool_calls>[]</tool_calls>',
      'markup after prose': 'Ik zoek het op. <function_calls><invoke name="x"></invoke></function_calls>',
      'Llama function tag': '<function=find_title>{"q": "Up"}</function>',
      'pipe token': '<|tool_call|>{"name": "find_title"}',
      'python tag': '<|python_tag|>find_title.call(q="Up")',
      'DeepSeek token': '<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>function',
      'Mistral token': '[TOOL_CALLS] [{"name": "find_title", "arguments": {}}]',
      'bare JSON with arguments': '{"name": "find_title", "arguments": {"q": "Up"}}',
      'bare JSON with parameters': '  {"name": "my_watching", "parameters": {}}  ',
      'JSON list of calls': '[{"name": "a", "arguments": {}}, {"name": "b", "arguments": "{}"}]',
      'fenced JSON': '```json\n{"name": "find_title", "arguments": {"q": "Up"}}\n```',
      'OpenAI-shaped function wrapper': '{"type": "function", "function": {"name": "x", "arguments": "{}"}}',
      'upper case tag': '<TOOL_CALL>{}</TOOL_CALL>',
      'Gemma/Llama tool_code block': 'Ik zoek het op.\n```tool_code\nfind_title(q="Up")\n```',
      'bare pythonic bracket call': '[find_title(q="Up")]',
      'pythonic call with two calls': "[a(x='1', y=2), b()]",
      // Gemma 4 raw format, ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4
      'Gemma 4 tool call': '<|tool_call>call:find_title{q:<|"|>Up<|"|>}<tool_call|>',
      'Gemma 4 closing token only': 'call:find_title{q:1}<tool_call|>',
      'GLM arg_key/arg_value': 'find_title\n<arg_key>q</arg_key>\n<arg_value>Up</arg_value>',
      'prose then a bare call object': 'Ik zoek het op.\n{"name":"x","arguments":{}}',
      'prose then a fenced call': 'Ik zoek het op.\n```json\n{"name":"x","parameters":{"q":"Up"}}\n```',
      'tool_calls object': '{"tool_calls":[{"name":"x","arguments":{}}]}',
      'tool_calls object, OpenAI items':
          '{"tool_calls":[{"id":"1","type":"function","function":{"name":"x","arguments":"{}"}}]}',
      'function_call object': '{"function_call":{"name":"x","arguments":"{}"}}',
      'tool/args object': '{"tool":"find_title","args":{"q":"Up"}}',
    };
    for (final MapEntry(key: name, value: text) in positives.entries) {
      test('flags: $name', () => expect(assistantLooksLikeToolMarkup(text), isTrue, reason: text));
    }

    const negatives = {
      'plain answer': 'Kijk «Toy Story» (1995).',
      'empty': '',
      'a title in angle brackets': 'De film <Untitled> uit 2020 staat op je server.',
      'a title called Invoke': 'Probeer <Invoke> (2019), een thriller.',
      'comparison signs': 'Films < 90 minuten: drie. Langer dan 2 uur > vijf.',
      'the words in prose': 'Ik kan geen function calls doen, maar ik heb tool calls gebruikt om te zoeken.',
      'invoke without tag': 'invoke name="x" staat in de log, zei je.',
      'HTML-ish emphasis': 'Kijk <b>Up</b> en <i>Coco</i>.',
      'JSON with only a name': '{"name": "Up"}',
      'JSON with extra keys': '{"name": "Up", "arguments": {}, "year": 2009}',
      'JSON inside a sentence': 'Het antwoord was {"name": "x", "arguments": {}} zei de server.',
      'broken JSON': '{"name": "find_title", "arguments": ',
      'empty JSON list': '[]',
      'list of titles': '[Up, Coco, Toy Story]',
      'a pipe in prose': 'Server a | server b: beide online.',
      'markdown code without a call': '```\nflutter run\n```',
      'number list': '1. Up (2009)\n2. Coco (2017)',
      'a function name in parentheses': 'Gebruik find_title(q) om te zoeken, of list_servers().',
      'a bracketed title list with years': '[Up (2009), Coco (2017)]',
      'a bracket with a call-like word': '[Zie find_title(Up) voor meer]',
      'JSON in a code block that is no call': 'Zo ziet het eruit:\n```json\n{"title": "Up", "year": 2009}\n```',
      'prose then a JSON object that is no call': 'Het resultaat is\n{"servers": 2, "online": true}',
      'a name key without arguments, after prose': 'Je profiel is\n{"name": "Michel", "role": "admin"}',
      'tool_calls key with other keys': '{"tool_calls": [], "note": "geen"}',
      'a tool key without args': '{"tool": "hamer"}',
      'a tool_code mention in prose': 'Een tool_code block bestaat niet in jouw bibliotheek.',
    };
    for (final MapEntry(key: name, value: text) in negatives.entries) {
      test('passes: $name', () => expect(assistantLooksLikeToolMarkup(text), isFalse, reason: text));
    }
  });
}
