/// The one grey line under a search result — iOS Unified 2026 fase 4.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/unified_catalog/search_text.dart';

MediaItem _item({
  required MediaKind kind,
  String id = 'i1',
  String title = 'Title',
  String serverId = 's1',
  int? year,
  List<String>? genres,
  int? durationMs,
  int? childCount,
  String? grandparentTitle,
  int? parentIndex,
  int? index,
}) {
  return MediaItem(
    id: id,
    backend: MediaBackend.plex,
    kind: kind,
    title: title,
    serverId: serverId,
    year: year,
    genres: genres,
    durationMs: durationMs,
    childCount: childCount,
    grandparentTitle: grandparentTitle,
    parentIndex: parentIndex,
    index: index,
  );
}

UnifiedMediaGroup _group(List<MediaItem> items) {
  final sources = items.map(UnifiedMediaSource.fromItem).toList();
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: items.first.title, year: items.first.year),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
  );
}

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  group('searchMetaLineFor', () {
    test('a film reads year, genre, runtime — mockup 05', () {
      final line = searchMetaLineFor(_item(kind: MediaKind.movie, year: 2024, genres: ['Sci-fi'], durationMs: 9960000));
      expect(line, startsWith('2024 · Sci-fi · '));
    });

    test('a series reads year and how many seasons', () {
      final line = searchMetaLineFor(_item(kind: MediaKind.show, year: 2023, childCount: 2));
      expect(line, '2023 · 2 seasons');
    });

    test('one season is not "1 seasons"', () {
      expect(searchMetaLineFor(_item(kind: MediaKind.show, year: 2023, childCount: 1)), '2023 · 1 season');
    });

    test('an episode reads its show and its number, not a year', () {
      final line = searchMetaLineFor(
        _item(kind: MediaKind.episode, grandparentTitle: 'Driftwood', parentIndex: 1, index: 2, year: 2024),
      );
      expect(line, 'Driftwood · S1 E2');
    });

    test('a field the backend did not report contributes nothing, never a placeholder', () {
      expect(searchMetaLineFor(_item(kind: MediaKind.movie)), '');
      expect(searchMetaLineFor(_item(kind: MediaKind.movie, year: 2024)), '2024');
    });
  });

  group('searchSourceCountFor', () {
    test('two sources say so', () {
      final group = _group([
        _item(kind: MediaKind.movie, id: 'a', serverId: 's1'),
        _item(kind: MediaKind.movie, id: 'b', serverId: 's2'),
      ]);
      expect(searchSourceCountFor(group), '2 sources');
    });

    test('one source says nothing — it is not information', () {
      expect(searchSourceCountFor(_group([_item(kind: MediaKind.movie)])), isNull);
    });
  });
}
