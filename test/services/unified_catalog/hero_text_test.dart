import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/services/unified_catalog/hero_text.dart';

/// A field the representative source did not report contributes nothing to
/// the meta line, never a placeholder — the same "ontbrekende metadata wordt
/// weggelaten" rule the source picker's descriptor follows.

UnifiedMediaGroup _group(MediaItem representative, {List<MediaItem>? extraSources}) {
  final sources = [representative, ...?extraSources].map(UnifiedMediaSource.fromItem).toList();
  return UnifiedMediaGroup(
    groupId: representative.id,
    identity: CanonicalMediaIdentity.movie(title: representative.title, year: representative.year),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
  );
}

MediaItem _movie({
  String id = 'i1',
  String title = 'Dune',
  int? year = 2021,
  List<String>? genres,
  int? durationMs,
  String serverId = 'nas',
  MediaKind kind = MediaKind.movie,
  String? grandparentTitle,
}) => MediaItem(
  id: id,
  backend: .plex,
  kind: kind,
  title: title,
  year: year,
  genres: genres,
  durationMs: durationMs,
  serverId: serverId,
  serverName: serverId,
  grandparentTitle: grandparentTitle,
);

void main() {
  group('heroMetaLineFor', () {
    test('a film joins kind, genre, year and runtime in order', () {
      final group = _group(_movie(genres: const ['Science Fiction'], year: 2021, durationMs: 9360000));
      expect(heroMetaLineFor(group), 'Movie · Science Fiction · 2021 · 2h 36min');
    });

    test('a show uses the TV Show label', () {
      final group = _group(_movie(kind: MediaKind.show, genres: const ['Drama']));
      expect(heroMetaLineFor(group), startsWith('TV Show'));
    });

    test('a field the source never reported is omitted, not shown as unknown', () {
      final group = _group(_movie(genres: null, year: null, durationMs: null));
      expect(heroMetaLineFor(group), 'Movie');
    });

    test('a zero or negative runtime is treated as absent', () {
      final group = _group(_movie(durationMs: 0));
      expect(heroMetaLineFor(group), isNot(contains('h')));
    });

    test('the source count only appears once there is more than one source', () {
      final single = _group(_movie());
      final multi = _group(
        _movie(),
        extraSources: [_movie(id: 'i2', serverId: 'attic')],
      );

      expect(heroMetaLineFor(single), isNot(contains('sources')));
      expect(heroMetaLineFor(multi), contains('2 sources'));
    });
  });

  group('heroTitleFor', () {
    test('a film or show uses its own title', () {
      expect(heroTitleFor(_group(_movie(title: 'Dune'))), 'Dune');
    });

    test('an episode falls back to its show name', () {
      final episode = _movie(kind: MediaKind.episode, title: 'The Long Night', grandparentTitle: 'Game of Thrones');
      expect(heroTitleFor(_group(episode)), 'Game of Thrones');
    });
  });
}
