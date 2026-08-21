import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/recommendations/personalized_rows_builder.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';

const _nowMs = 1700000000000;
const _day = Duration.millisecondsPerDay;

final _titles = PersonalizedRowTitles(
  topPicks: 'Top Picks',
  becauseYouLike: (g) => 'Because you like $g',
  hiddenGems: 'Hidden Gems',
);

MediaItem _movie({
  required String id,
  List<String> genres = const [],
  double? rating,
  int viewCount = 0,
  int? addedAtDaysAgo,
}) => MediaItem.plex(
  id: id,
  kind: MediaKind.movie,
  serverId: 's1',
  title: id,
  genres: genres,
  rating: rating,
  viewCount: viewCount,
  addedAt: addedAtDaysAgo == null ? null : (_nowMs - addedAtDaysAgo * _day) ~/ 1000,
);

AffinityVector _warmSciFiTaste() => AffinityVector.build([
  for (var i = 0; i < 12; i++) TasteEvent(weight: 1.0, occurredAtMs: _nowMs, genres: const ['Sci-Fi']),
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
}
