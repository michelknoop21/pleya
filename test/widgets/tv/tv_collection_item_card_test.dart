/// MOC-24 (PB-13): the per-item card on the TV-native collection surface.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_collection_item_card.dart';

MediaItem _movie({bool watched = false, int? viewOffsetMs, int? durationMs}) => MediaItem(
  id: 'movie-1',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Dune',
  serverId: 'nas',
  year: 2021,
  viewCount: watched ? 1 : 0,
  viewOffsetMs: viewOffsetMs,
  durationMs: durationMs,
);

Widget _harness(Widget child) => MaterialApp(
  theme: monoTheme(dark: true),
  home: Scaffold(
    body: Center(child: SizedBox(width: 200, child: child)),
  ),
);

void main() {
  testWidgets('shows the title and the 1-based position badge', (tester) async {
    await tester.pumpWidget(
      _harness(TvCollectionItemCard(item: _movie(), position: 2, width: 200, onSelect: () {}, onRemove: () {})),
    );

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('draws the watched badge for a watched item, not the resume bar', (tester) async {
    await tester.pumpWidget(
      _harness(
        TvCollectionItemCard(item: _movie(watched: true), position: 1, width: 200, onSelect: () {}, onRemove: () {}),
      ),
    );

    expect(find.byType(TvCatalogWatchedBadge), findsOneWidget);
    expect(find.byType(TvCatalogResumeBar), findsNothing);
  });

  testWidgets('draws the resume bar for a part-watched item, not the watched badge', (tester) async {
    await tester.pumpWidget(
      _harness(
        TvCollectionItemCard(
          item: _movie(viewOffsetMs: 600000, durationMs: 1200000),
          position: 1,
          width: 200,
          onSelect: () {},
          onRemove: () {},
        ),
      ),
    );

    expect(find.byType(TvCatalogResumeBar), findsOneWidget);
    expect(find.byType(TvCatalogWatchedBadge), findsNothing);
  });

  testWidgets('neither marker for an unwatched, never-started item', (tester) async {
    await tester.pumpWidget(
      _harness(TvCollectionItemCard(item: _movie(), position: 1, width: 200, onSelect: () {}, onRemove: () {})),
    );

    expect(find.byType(TvCatalogWatchedBadge), findsNothing);
    expect(find.byType(TvCatalogResumeBar), findsNothing);
  });
}
