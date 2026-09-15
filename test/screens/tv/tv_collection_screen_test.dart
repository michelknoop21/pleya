/// MOC-24 (PB-13): the TV-native collection surface. Presentation only — see
/// `docs/tvos-redesign-register.md`'s MOC-24 row for what stays open
/// (Verify scenario, hardware run).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/tv/tv_collection_screen.dart';
import 'package:pleya/theme/mono_theme.dart';

MediaItem _collection() => MediaItem(
  id: 'col-1',
  backend: MediaBackend.plex,
  kind: MediaKind.collection,
  title: 'Dune Collection',
  serverId: 'nas',
  libraryTitle: 'Films 4K',
  summary: "Denis Villeneuve's adaptation, in two parts.",
);

MediaItem _movie(String id, String title, {int? year}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, serverId: 'nas', year: year);

Widget _harness(Widget child) => TranslationProvider(
  child: MaterialApp(
    theme: monoTheme(dark: true),
    home: Scaffold(body: SizedBox(height: 900, child: child)),
  ),
);

void main() {
  testWidgets('renders the collection title, source breadcrumb and description', (tester) async {
    await tester.pumpWidget(
      _harness(
        TvCollectionScreen(
          collection: _collection(),
          items: [_movie('m1', 'Dune'), _movie('m2', 'Dune: Part Two')],
          totalSize: 2,
          isLoading: false,
          isLoadingMore: false,
          errorMessage: null,
          client: null,
          backendLabel: 'Plex',
          onRetry: () {},
          onLoadMore: () {},
          onPlay: () {},
          onShuffle: () {},
          onDelete: () {},
          onSelectItem: (_) {},
          onRemoveItem: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dune Collection'), findsOneWidget);
    expect(find.textContaining('Plex'), findsOneWidget);
    expect(find.textContaining('Films 4K'), findsOneWidget);
    expect(find.text("Denis Villeneuve's adaptation, in two parts."), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text(t.collections.inThisCollection), findsOneWidget);
  });

  testWidgets('shows the empty state when the collection has no items', (tester) async {
    await tester.pumpWidget(
      _harness(
        TvCollectionScreen(
          collection: _collection(),
          items: const [],
          totalSize: 0,
          isLoading: false,
          isLoadingMore: false,
          errorMessage: null,
          client: null,
          backendLabel: 'Plex',
          onRetry: () {},
          onLoadMore: () {},
          onPlay: () {},
          onShuffle: () {},
          onDelete: () {},
          onSelectItem: (_) {},
          onRemoveItem: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(t.collections.empty), findsOneWidget);
  });

  testWidgets('shows the error state with a retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _harness(
        TvCollectionScreen(
          collection: _collection(),
          items: const [],
          totalSize: 0,
          isLoading: false,
          isLoadingMore: false,
          errorMessage: 'No server answered',
          client: null,
          backendLabel: 'Plex',
          onRetry: () => retried = true,
          onLoadMore: () {},
          onPlay: () {},
          onShuffle: () {},
          onDelete: () {},
          onSelectItem: (_) {},
          onRemoveItem: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No server answered'), findsOneWidget);
    expect(find.text(t.common.retry), findsOneWidget);
    expect(retried, isFalse);
  });
}
