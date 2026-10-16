import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tools.dart';

// The token budget of the tool specs (BP-11a). Every model call carries the
// specs of the tools on offer; their size is paid on every step of every
// ask, and a small model loses the thread when they grow. This test measures
// the whole allow-list (the worst case: a profile that is offered every
// tool, one server id per spec) as JSON characters / 4, the usual token
// estimate. split_tasks (a private spec of the run, first step only) is not
// counted.
//
// Baseline measured on 16 October 2026 (main 403fcc36): 28109 characters,
// 7028 tokens. The specs may grow by the margin below; growing past it needs a
// deliberate new baseline in the same change, with the reason in the commit.

const _baselineTokens = 7028;
const _marginTokens = 500;

void main() {
  test('all tool specs together stay within the token budget', () {
    final specs = [
      for (final t in assistantTools) t.spec(const ['server-1']),
    ];
    final chars = jsonEncode(specs).length;
    final tokens = (chars / 4).ceil();
    expect(
      tokens,
      lessThanOrEqualTo(_baselineTokens + _marginTokens),
      reason:
          'Tool specs: $chars chars, about $tokens tokens; baseline $_baselineTokens + margin $_marginTokens. '
          'Shorten descriptions or move rules into code before raising the baseline.',
    );
  });
}
