/// MOC-25 (PB-14): the TV-native person surface. Presentation only — see
/// `docs/tvos-redesign-register.md`'s MOC-25 row for what stays open
/// (Verify scenario, hardware run).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/tv/tv_person_screen.dart';
import 'package:pleya/theme/mono_theme.dart';

MediaItem _movie(String id, String title, {int? year}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, serverId: 'nas', year: year);

Widget _harness(Widget child) => TranslationProvider(
  child: MaterialApp(
    theme: monoTheme(dark: true),
    home: Scaffold(body: SizedBox(height: 900, child: child)),
  ),
);

void main() {
  testWidgets('renders the actor name, character and loaded filmography', (tester) async {
    await tester.pumpWidget(
      _harness(
        TvPersonScreen(
          actorName: 'Timothée Chalamet',
          actorThumb: null,
          characterName: 'als Paul Atreides',
          items: [_movie('m1', 'Dune', year: 2021), _movie('m2', 'Dune: Part Two', year: 2024)],
          totalSize: 2,
          isLoading: false,
          isLoadingMore: false,
          errorMessage: null,
          client: null,
          onRetry: () {},
          onLoadMore: () {},
          onSelectItem: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Timothée Chalamet'), findsOneWidget);
    expect(find.textContaining('als Paul Atreides'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Dune: Part Two'), findsOneWidget);
    // MOC-25 scope trim: no "Volgen" / follow control anywhere on this surface.
    expect(find.textContaining('Volgen'), findsNothing);
  });

  testWidgets('shows the empty state when the person has no titles on this server', (tester) async {
    await tester.pumpWidget(
      _harness(
        TvPersonScreen(
          actorName: 'Nobody',
          actorThumb: null,
          characterName: null,
          items: const [],
          totalSize: 0,
          isLoading: false,
          isLoadingMore: false,
          errorMessage: null,
          client: null,
          onRetry: () {},
          onLoadMore: () {},
          onSelectItem: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(t.discover.noContentAvailable), findsOneWidget);
  });

  testWidgets('shows the error state with a retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _harness(
        TvPersonScreen(
          actorName: 'Nobody',
          actorThumb: null,
          characterName: null,
          items: const [],
          totalSize: 0,
          isLoading: false,
          isLoadingMore: false,
          errorMessage: 'No server answered',
          client: null,
          onRetry: () => retried = true,
          onLoadMore: () {},
          onSelectItem: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('No server answered'), findsOneWidget);
    expect(find.text(t.common.retry), findsOneWidget);
    expect(retried, isFalse);
  });
}
