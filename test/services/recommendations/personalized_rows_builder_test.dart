import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/services/recommendations/personalized_rows_builder.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';

const _nowMs = 1700000000000;
const _day = Duration.millisecondsPerDay;

final _titles = PersonalizedRowTitles(
  topPicks: 'Top Picks',
  becauseYouLike: (g) => 'Because you like $g',
  hiddenGems: 'Hidden Gems',
  moreWithActor: (n) => 'More with $n',
  moreFromDirector: (n) => 'More from $n',
);

MediaItem _movie({
  required String id,
  List<String> genres = const [],
  List<String> actors = const [],
  double? rating,
  int viewCount = 0,
  int? addedAtDaysAgo,
}) => MediaItem.plex(
  id: id,
  kind: MediaKind.movie,
  serverId: 's1',
  title: id,
  genres: genres,
  roles: [for (final a in actors) MediaRole(tag: a)],
  rating: rating,
  viewCount: viewCount,
  addedAt: addedAtDaysAgo == null ? null : (_nowMs - addedAtDaysAgo * _day) ~/ 1000,
);

AffinityVector _warmSciFiTaste() => AffinityVector.build([
  for (var i = 0; i < 12; i++) TasteEvent(weight: 1.0, occurredAtMs: _nowMs, genres: const ['Sci-Fi']),
], nowMs: _nowMs);

AffinityVector _warmTaste({
  List<String> genres = const ['Sci-Fi'],
  List<String> actors = const [],
  List<String> directors = const [],
}) => AffinityVector.build([
  for (var i = 0; i < 12; i++)
    TasteEvent(
      weight: 1.0,
      occurredAtMs: _nowMs,
      evidenceKey: 't$i',
      genres: genres,
      actors: actors,
      directors: directors,
    ),
], nowMs: _nowMs);

void main() {
  test('empty pool yields no rows', () {
    final rows = buildPersonalizedRows(AffinityVector.empty, const [], titles: _titles, nowMs: _nowMs);
    expect(rows, isEmpty);
  });

  test('cold start still produces Top Picks from quality/novelty', () {
    final pool = [for (var i = 0; i < 8; i++) _movie(id: 'm$i', rating: 8, addedAtDaysAgo: 3)];
    final rows = buildPersonalizedRows(AffinityVector.empty, pool, titles: _titles, nowMs: _nowMs);
    expect(rows.map((r) => r.id), contains('home.toppicks'));
    // No genre rows on a cold profile.
    expect(rows.any((r) => r.id.startsWith('home.becauselike')), isFalse);
  });

  test('warm taste emits a Because-you-like genre row', () {
    final pool = [
      for (var i = 0; i < 6; i++) _movie(id: 'sf$i', genres: const ['Sci-Fi'], rating: 7),
    ];
    final rows = buildPersonalizedRows(_warmSciFiTaste(), pool, titles: _titles, nowMs: _nowMs);
    final genreRow = rows.firstWhere((r) => r.id.startsWith('home.becauselike'), orElse: () => throw 'missing');
    expect(genreRow.title, 'Because you like Sci-fi');
  });

  test('watched items are excluded from the pool', () {
    final pool = [
      _movie(id: 'seen', genres: const ['Sci-Fi'], viewCount: 1),
      for (var i = 0; i < 6; i++) _movie(id: 'u$i', genres: const ['Sci-Fi']),
    ];
    final rows = buildPersonalizedRows(_warmSciFiTaste(), pool, titles: _titles, nowMs: _nowMs);
    final allItemIds = rows.expand((r) => r.items).map((i) => i.id).toSet();
    expect(allItemIds, isNot(contains('seen')));
  });

  test('excludeKeys drops already-shown items', () {
    final shown = _movie(id: 'dup', genres: const ['Sci-Fi'], rating: 8);
    final pool = [
      shown,
      for (var i = 0; i < 6; i++) _movie(id: 'x$i', genres: const ['Sci-Fi'], rating: 8),
    ];
    final rows = buildPersonalizedRows(
      _warmSciFiTaste(),
      pool,
      titles: _titles,
      nowMs: _nowMs,
      excludeKeys: {shown.globalKey},
    );
    final allItemIds = rows.expand((r) => r.items).map((i) => i.id).toSet();
    expect(allItemIds, isNot(contains('dup')));
  });

  test('Hidden Gems needs well-rated, old, unseen items', () {
    // Enough on-taste freshness to fill Top Picks, plus older catalogue depth
    // that scores below it. A pool smaller than one row cannot fill two rows
    // with different titles, which is the whole point of the exclusion below.
    final pool = [
      for (var i = 0; i < 24; i++) _movie(id: 'fresh$i', genres: const ['Sci-Fi'], rating: 8, addedAtDaysAgo: 2),
      for (var i = 0; i < 6; i++) _movie(id: 'gem$i', genres: const ['Western'], rating: 8.5, addedAtDaysAgo: 200),
    ];
    final rows = buildPersonalizedRows(_warmSciFiTaste(), pool, titles: _titles, nowMs: _nowMs);
    expect(rows.map((r) => r.id), contains('home.hiddengems'));
    final gems = rows.firstWhere((r) => r.id == 'home.hiddengems');
    expect(gems.items.map((i) => i.id), everyElement(startsWith('gem')));
  });

  test('Hidden Gems never repeats a title already in Top Picks', () {
    final pool = [
      for (var i = 0; i < 24; i++) _movie(id: 'fresh$i', genres: const ['Sci-Fi'], rating: 8, addedAtDaysAgo: 2),
      for (var i = 0; i < 6; i++) _movie(id: 'gem$i', genres: const ['Western'], rating: 8.5, addedAtDaysAgo: 200),
    ];
    final rows = buildPersonalizedRows(_warmSciFiTaste(), pool, titles: _titles, nowMs: _nowMs);
    final top = rows.firstWhere((r) => r.id == 'home.toppicks').items.map((i) => i.globalKey).toSet();
    final gems = rows.firstWhere((r) => r.id == 'home.hiddengems').items.map((i) => i.globalKey).toSet();
    expect(top.intersection(gems), isEmpty);
  });

  test('an old well-rated title that is itself a top pick does not also become a gem', () {
    // Six titles, all of them top picks. One row, not the same six twice.
    final pool = [
      for (var i = 0; i < 6; i++) _movie(id: 'gem$i', genres: const ['Sci-Fi'], rating: 8.5, addedAtDaysAgo: 200),
    ];
    final rows = buildPersonalizedRows(_warmSciFiTaste(), pool, titles: _titles, nowMs: _nowMs);
    expect(rows.any((r) => r.id == 'home.hiddengems'), isFalse);
  });

  test('fresh low-rated items do not form Hidden Gems', () {
    final pool = [
      for (var i = 0; i < 6; i++) _movie(id: 'new$i', genres: const ['Sci-Fi'], rating: 5, addedAtDaysAgo: 2),
    ];
    final rows = buildPersonalizedRows(_warmSciFiTaste(), pool, titles: _titles, nowMs: _nowMs);
    expect(rows.any((r) => r.id == 'home.hiddengems'), isFalse);
  });

  group('person rows', () {
    test('a strong actor gets a row named after the server spelling of the name', () {
      final pool = [
        for (var i = 0; i < 6; i++) _movie(id: 'h$i', actors: const ['Tom Hanks'], rating: 7),
      ];
      final rows = buildPersonalizedRows(
        _warmTaste(genres: const [], actors: const ['Tom Hanks']),
        pool,
        titles: _titles,
        nowMs: _nowMs,
      );
      final row = rows.singleWhere((r) => r.id.startsWith('home.becauselike.actor.'));
      expect(row.id, 'home.becauselike.actor.tom-hanks');
      expect(row.title, 'More with Tom Hanks');
    });

    test('a strong director gets a row too', () {
      final pool = [
        for (var i = 0; i < 6; i++)
          MediaItem.plex(
            id: 'r$i',
            kind: MediaKind.movie,
            serverId: 's1',
            title: 'r$i',
            directors: const ['Ridley Scott'],
            rating: 7,
          ),
      ];
      final rows = buildPersonalizedRows(
        _warmTaste(genres: const [], directors: const ['Ridley Scott']),
        pool,
        titles: _titles,
        nowMs: _nowMs,
      );
      final row = rows.singleWhere((r) => r.id.startsWith('home.becauselike.director.'));
      expect(row.id, 'home.becauselike.director.ridley-scott');
      expect(row.title, 'More from Ridley Scott');
    });

    test('genre, actor and director share two slots; genre wins a tie', () {
      // Each feature has titles of its own: affinity rows never repeat a
      // title, so a shared pool would starve the later rows.
      final pool = [
        for (var i = 0; i < 6; i++) _movie(id: 's$i', genres: const ['Sci-Fi'], rating: 7),
        for (var i = 0; i < 6; i++) _movie(id: 'd$i', genres: const ['Drama'], rating: 7),
        for (var i = 0; i < 6; i++) _movie(id: 'h$i', actors: const ['Tom Hanks'], rating: 7),
      ];
      // Every event carries both genres, one actor and one director: all four
      // features normalize to 1.0, so the tie-break decides.
      final taste = AffinityVector.build([
        for (var i = 0; i < 12; i++)
          TasteEvent(
            weight: 1.0,
            occurredAtMs: _nowMs,
            evidenceKey: 't$i',
            genres: const ['Sci-Fi', 'Drama'],
            actors: const ['Tom Hanks'],
            directors: const ['Ridley Scott'],
          ),
      ], nowMs: _nowMs);
      final rows = buildPersonalizedRows(taste, pool, titles: _titles, nowMs: _nowMs);
      final affinity = rows.where((r) => r.id.startsWith('home.becauselike.')).map((r) => r.id).toList();
      expect(affinity, hasLength(2));
      expect(affinity, everyElement(isNot(contains('.actor.'))), reason: 'two genres at 1.0 beat the actor at 1.0');
    });

    test('a strong actor beats a weak second genre', () {
      final pool = [
        for (var i = 0; i < 6; i++) _movie(id: 'a$i', genres: const ['Sci-Fi'], actors: const ['Tom Hanks'], rating: 7),
        // The Sci-Fi row takes the six above, so the actor row needs its own.
        for (var i = 0; i < 6; i++) _movie(id: 'h$i', actors: const ['Tom Hanks'], rating: 7),
        for (var i = 0; i < 6; i++) _movie(id: 'd$i', genres: const ['Drama'], rating: 7),
      ];
      final taste = AffinityVector.build([
        for (var i = 0; i < 10; i++)
          TasteEvent(
            weight: 1.0,
            occurredAtMs: _nowMs,
            evidenceKey: 's$i',
            genres: const ['Sci-Fi'],
            actors: const ['Tom Hanks'],
          ),
        for (var i = 0; i < 6; i++)
          TasteEvent(weight: 1.0, occurredAtMs: _nowMs, evidenceKey: 'd$i', genres: const ['Drama']),
      ], nowMs: _nowMs);
      final rows = buildPersonalizedRows(taste, pool, titles: _titles, nowMs: _nowMs);
      final affinity = rows.where((r) => r.id.startsWith('home.becauselike.')).map((r) => r.id).toList();
      expect(affinity, ['home.becauselike.sci-fi', 'home.becauselike.actor.tom-hanks']);
    });

    test('a cold taste gets no person row', () {
      final pool = [
        for (var i = 0; i < 6; i++) _movie(id: 'h$i', actors: const ['Tom Hanks'], rating: 8),
      ];
      final rows = buildPersonalizedRows(AffinityVector.empty, pool, titles: _titles, nowMs: _nowMs);
      expect(rows.any((r) => r.id.contains('.actor.')), isFalse);
    });
  });
}
