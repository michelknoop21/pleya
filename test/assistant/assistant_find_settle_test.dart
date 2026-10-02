import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;
import 'package:pleya/assistant/assistant_find_match.dart';
import 'package:pleya/assistant/assistant_find_route.dart';
import 'package:pleya/assistant/assistant_plot_index.dart';
import 'package:pleya/assistant/assistant_web_lookup.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/utils/external_ids.dart';

import '../test_helpers/prefs.dart';
import 'assistant_find_fakes.dart';

/// External ids that arrive only after the route's deadline.
class _SlowIdsServer extends FakeServer {
  _SlowIdsServer(super.id, {super.libraries});

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const ExternalIds(tmdb: 194);
  }
}

FakeServer _amelie() => FakeServer(
  'zolder',
  libraries: {
    'films': [fakeItem('1', 'Amélie', summary: 'A shy waitress in Paris.')],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    resetSharedPreferencesForTest();
    AssistantWebCache.shared.clear();
  });

  test('a cancelled run aborts find_title at once and starts no new call', () async {
    final web = FakeWeb()..stall = Completer();
    final cancel = AbortController();
    final ctx = findCtx([_amelie()], libraries: [fakeLib('zolder', 'films')], web: web).fresh(cancel: cancel);
    final clock = Stopwatch()..start();
    final pending = findTitles(
      ctx,
      const FindQuery(variants: ['garage engineers time machine', 'tijdmachine']),
      budget: const Duration(seconds: 5),
      headStart: Duration.zero,
      plots: AssistantPlotIndexCache(),
      webCache: AssistantWebCache(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cancel.abort();
    await pending;

    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    await pumpEventQueue();
    expect(web.aborted, isNotEmpty);
    expect(web.search.queries, isEmpty);
    expect(web.hosts.where((h) => h == 'www.wikidata.org'), isEmpty);
  });

  test('a library answer that lands after the deadline writes nothing into the result', () async {
    final server = _SlowIdsServer(
      'zolder',
      libraries: {
        'films': [fakeItem('1', 'Amélie', summary: 'A shy waitress in Paris.')],
      },
    );
    final ctx = findCtx([server], libraries: [fakeLib('zolder', 'films')]);
    final result = await findTitles(
      ctx,
      const FindQuery(variants: ['shy waitress paris', 'serveerster']),
      budget: const Duration(milliseconds: 150),
      headStart: Duration.zero,
      plots: AssistantPlotIndexCache(),
    );
    final amelie = result.matches.firstWhere((m) => m.title == 'Amélie');
    expect(result.partial, isTrue);
    expect(amelie.ids.hasAny, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(amelie.ids.hasAny, isFalse, reason: 'the late fetchExternalIds answer is dropped');
  });

  test('an SxxEyy in a web snippet that no episode list holds adds no episode', () async {
    final web = FakeWeb();
    web.search.hits = [(title: 'Doctor Who S04E99 recap', url: 'https://tv.example', snippet: 'Statues.')];
    final server = FakeServer(
      'zolder',
      libraries: {
        'series': [fakeItem('dw', 'Doctor Who', kind: MediaKind.show, summary: 'A time traveller.')],
      },
      children: {
        'dw': [fakeItem('s3', 'Season 3', kind: MediaKind.season).copyWith(index: 3)],
        's3': [
          fakeItem(
            'e1',
            'Smith and Jones',
            kind: MediaKind.episode,
            summary: 'A hospital.',
          ).copyWith(index: 1, parentIndex: 3),
        ],
      },
    );
    final ctx = findCtx(
      [server],
      libraries: [fakeLib('zolder', 'series', kind: MediaKind.show)],
      web: web,
    );
    final rows = matchesOf(
      await runFind(ctx, const {
        'kind': 'episode',
        'series': 'Doctor Who',
        'variants': ['statues that move when you look away', 'beelden'],
      }),
    );

    expect(web.search.queries, isNotEmpty, reason: 'the web was asked and named S04E99');
    expect(rows.where((r) => r['kind'] == 'episode'), isEmpty);
    expect(rows.map((r) => r['title']), contains('Doctor Who'));
  });
}
