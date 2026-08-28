import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/season_episode_pager.dart';

void main() {
  MediaItem episode(String id, {String title = 'Episode'}) =>
      MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.episode, title: title);

  group('SeasonEpisodePager', () {
    test('completeFirstPage swaps items atomically and marks state present', () {
      final pager = SeasonEpisodePager();
      expect(pager.hasState('s1'), isFalse);

      pager.completeFirstPage('s1', [episode('e1'), episode('e2')], 2);

      expect(pager.hasState('s1'), isTrue);
      final state = pager.stateFor('s1');
      expect(state.items.map((e) => e.id), ['e1', 'e2']);
      expect(state.totalCount, 2);
      expect(state.isInitialLoading, isFalse);
      expect(state.hasMore, isFalse);
    });

    test('a later completeFirstPage fully replaces the earlier page (growth window)', () {
      final pager = SeasonEpisodePager();
      pager.completeFirstPage('s1', List.generate(10, (i) => episode('e$i')), 10);

      // Revalidation re-fetches a wider window and swaps in one call — never
      // an incremental append, so there is no intermediate state where the
      // new episode is missing from a rebuild.
      pager.completeFirstPage('s1', List.generate(11, (i) => episode('e$i')), 11);

      final state = pager.stateFor('s1');
      expect(state.items.length, 11);
      expect(state.items.last.id, 'e10');
      expect(state.totalCount, 11);
    });

    test('patchEpisode updates in place without changing length or order', () {
      final pager = SeasonEpisodePager();
      pager.completeFirstPage('s1', [episode('e1', title: 'Old'), episode('e2')], 2);

      pager.patchEpisode('e1', (existing) => existing.copyWith(title: 'New'));

      final state = pager.stateFor('s1');
      expect(state.items.length, 2);
      expect(state.items.map((e) => e.id), ['e1', 'e2']);
      expect(state.items.first.title, 'New');
    });

    test('patchEpisode reaches an episode regardless of which season holds it', () {
      final pager = SeasonEpisodePager();
      pager.completeFirstPage('s1', [episode('e1')], 1);
      pager.completeFirstPage('s2', [episode('e2', title: 'Old')], 1);

      pager.patchEpisode('e2', (existing) => existing.copyWith(title: 'New'));

      expect(pager.stateFor('s1').items.single.title, 'Episode');
      expect(pager.stateFor('s2').items.single.title, 'New');
    });

    test('removeEpisode drops the episode and decrements the total', () {
      final pager = SeasonEpisodePager();
      pager.completeFirstPage('s1', [episode('e1'), episode('e2')], 2);

      pager.removeEpisode('e1');

      final state = pager.stateFor('s1');
      expect(state.items.map((e) => e.id), ['e2']);
      expect(state.totalCount, 1);
    });

    test('resetSeason clears state, in-flight guards, and cache presence', () {
      final pager = SeasonEpisodePager();
      pager.completeFirstPage('s1', [episode('e1')], 1);
      // Simulate a load still in flight for this season at reset time.
      expect(pager.beginFirstPageLoad('s1'), isTrue);

      pager.resetSeason('s1');

      expect(pager.hasState('s1'), isFalse);
      expect(pager.stateFor('s1').items, isEmpty);
      // Reset must also clear the in-flight guard, or a fresh load right
      // after reset would be wrongly rejected as "already in flight".
      expect(pager.beginFirstPageLoad('s1'), isTrue);
    });

    test('beginFirstPageLoad guards against a concurrent first-page load', () {
      final pager = SeasonEpisodePager();
      expect(pager.beginFirstPageLoad('s1'), isTrue);
      expect(pager.beginFirstPageLoad('s1'), isFalse, reason: 'a second concurrent load must be rejected');

      pager.endFirstPageLoad('s1');
      expect(pager.beginFirstPageLoad('s1'), isTrue, reason: 'freed after the in-flight load ends');
    });

    test('beginMoreLoad is a separate guard from beginFirstPageLoad', () {
      final pager = SeasonEpisodePager();
      expect(pager.beginFirstPageLoad('s1'), isTrue);
      expect(pager.beginMoreLoad('s1'), isTrue);

      pager.endFirstPageLoad('s1');
      pager.endMoreLoad('s1');
    });

    test('completeMoreLoad appends only when the offset matches, else drops the page', () {
      final pager = SeasonEpisodePager();
      pager.completeFirstPage('s1', [episode('e1')], 3);

      // Stale response for an offset that no longer matches current length.
      pager.completeMoreLoad('s1', expectedOffset: 5, episodes: [episode('stale')], total: 6);
      expect(pager.stateFor('s1').items.map((e) => e.id), ['e1']);

      pager.completeMoreLoad('s1', expectedOffset: 1, episodes: [episode('e2'), episode('e3')], total: 3);
      expect(pager.stateFor('s1').items.map((e) => e.id), ['e1', 'e2', 'e3']);
      expect(pager.stateFor('s1').hasMore, isFalse);
    });
  });
}
