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
    };
    for (final MapEntry(key: name, value: text) in negatives.entries) {
      test('passes: $name', () => expect(assistantLooksLikeToolMarkup(text), isFalse, reason: text));
    }
  });
}
