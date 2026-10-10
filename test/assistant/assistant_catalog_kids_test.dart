import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_title_facts.dart';
import 'package:pleya/assistant/assistant_title_facts_cache.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_results.dart';

import 'assistant_find_fakes.dart';

// search_catalog on a children's profile: the age gate and the title facts.

/// Facts per title, as the chain would have found them.
class _Facts extends TitleFactsService {
  _Facts() : super(cache: TitleFactsCache());
  static const byTitle = {
    'Deathly Hallows': TitleFacts(certifications: {'NL': '12'}),
    'Toy Story': TitleFacts(certifications: {'NL': 'AL'}),
  };
  @override
  Future<List<TitleFacts>> factsFor(List<TitleRef> refs) async => [
    for (final r in refs) byTitle[r.title] ?? const TitleFacts(),
  ];
}

class _Loader implements HomeCustomRowLoader {
  _Loader(this.groups);
  final List<UnifiedMediaGroup> groups;

  @override
  Future<HomeCustomRowContent> load(HomeCustomRow row, {required int limit}) async =>
      HomeCustomRowContent(groups: groups.take(limit).toList(), isExact: true, isPartial: false);
}

/// Item 1 on [server]: the same item id on every server.
UnifiedMediaGroup _on(String server, String title, {int? added}) {
  final source = UnifiedMediaSource.fromItem(
    MediaItem(
      id: '1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: title,
      year: 2001,
      serverId: server,
      libraryId: 'lib-films',
      addedAt: added,
    ),
  );
  return UnifiedMediaGroup(
    groupId: '$server-1',
    identity: CanonicalMediaIdentity.movie(title: title, year: 2001),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: source.sourceKey, isWatched: false),
  );
}

AssistantTool _tool(String name) => assistantTools.firstWhere((t) => t.name == name);

void main() {
  test('two servers with the same item id: the age filter and the facts keep them apart', () async {
    // Toy Story is a:1 and the 12+ film b:1: one item id, two servers.
    final servers = MultiServerManager();
    addTearDown(servers.dispose);
    servers
      ..debugRegisterClientForTesting(FakeServer('a'))
      ..debugRegisterClientForTesting(FakeServer('b'))
      ..setVisibleServerIds(null);
    final catalog = AssistantCatalogServices(
      rowLoader: _Loader([_on('a', 'Toy Story'), _on('b', 'Deathly Hallows')]),
      profileId: 'p1',
      activeProfileId: () => 'p1',
    );
    // kidsMode as a run on a children's profile sets it.
    AssistantToolContext ctx({bool kids = false}) => AssistantToolContext(
      servers: servers,
      catalog: catalog,
      titleFacts: _Facts(),
      kidsAges: () async => [8],
      region: () => 'NL',
    )..kidsMode = kids;

    final kids = await _tool('search_catalog').run(ctx(kids: true), null, {'kind': 'movie'}) as AssistantToolResult;
    final grid = kids.display! as AssistantMediaGrid;
    expect([for (final e in grid.entries) e.item.title], ['Toy Story']);
    expect(kids.data['count'], 1, reason: 'the filtered count');

    final all = await _tool('search_catalog').run(ctx(), null, {'kind': 'movie'}) as AssistantToolResult;
    final cards = bigPTitleMatches(all.display!);
    expect(
      {for (final c in cards) c.title: c.facts?.certifications['NL']},
      {'Toy Story': 'AL', 'Deathly Hallows': '12'},
    );
  });

  test('added window on a children profile: no whole-window figure and no count of unchecked titles', () async {
    final servers = MultiServerManager();
    addTearDown(servers.dispose);
    servers
      ..debugRegisterClientForTesting(FakeServer('a'))
      ..debugRegisterClientForTesting(FakeServer('b'))
      ..debugRegisterClientForTesting(FakeServer('c'))
      ..setVisibleServerIds(null);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final catalog = AssistantCatalogServices(
      rowLoader: _Loader([
        _on('a', 'Toy Story', added: now - 86400),
        _on('b', 'Deathly Hallows', added: now - 86400),
        _on('c', 'Undated'),
      ]),
      profileId: 'p1',
      activeProfileId: () => 'p1',
    );
    AssistantToolContext ctx(bool kids) => AssistantToolContext(
      servers: servers,
      catalog: catalog,
      titleFacts: _Facts(),
      kidsAges: () async => [8],
      region: () => 'NL',
    )..kidsMode = kids;
    final args = {'kind': 'movie', 'added_within_days': 7};
    final kids = await _tool('search_catalog').run(ctx(true), null, args) as AssistantToolResult;
    expect(kids.data.containsKey('total_matches'), isFalse);
    expect(kids.data.containsKey('added_unknown'), isFalse);
    expect(kids.data.containsKey('partial'), isFalse, reason: 'no hint at titles that were never checked');
    final adult = await _tool('search_catalog').run(ctx(false), null, args) as AssistantToolResult;
    expect(adult.data['total_matches'], 2);
    expect(adult.data['added_unknown'], 1);
  });
}
