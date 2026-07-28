import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/widgets/tv_spotlight_background.dart';

MediaItem _movie({String? artPath, String? thumbPath}) => MediaItem(
  id: 'movie_1',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Test Movie',
  summary: 'A summary that should only show when the rail is down.',
  artPath: artPath,
  thumbPath: thumbPath,
);

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 1280, height: 720, child: child)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('railRevealed keeps the title but drops summary and actions', (tester) async {
    for (final revealed in [false, true]) {
      await tester.pumpWidget(
        _wrap(
          TvSpotlightBackground(
            item: _movie(artPath: '/art'),
            client: null,
            railRevealed: revealed,
            actions: const Text('ACTIONS'),
            showPrimaryAction: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Test Movie'), findsOneWidget, reason: 'title always identifies the focused item');
      expect(find.textContaining('only show when the rail is down'), revealed ? findsNothing : findsOneWidget);
      expect(find.text('ACTIONS'), revealed ? findsNothing : findsOneWidget);
    }
  });

  testWidgets('poster-only items are blurred into a fill, landscape art is not', (tester) async {
    // Local-artwork path: the only branch that renders a real image without a
    // server client. A 1x1 PNG is enough — nothing decodes it here.
    final file = File('${Directory.systemTemp.path}/pleya_spotlight_test.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        ),
      );
    addTearDown(() => file.deleteSync());
    String? resolver(String? path) => path == null ? null : file.path;

    await tester.pumpWidget(
      _wrap(
        TvSpotlightBackground(
          item: _movie(artPath: '/art'),
          client: null,
          localArtworkPathResolver: resolver,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ImageFiltered), findsNothing, reason: 'landscape art renders sharp');

    await tester.pumpWidget(
      _wrap(
        TvSpotlightBackground(
          item: _movie(thumbPath: '/poster'),
          client: null,
          localArtworkPathResolver: resolver,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ImageFiltered), findsOneWidget, reason: 'poster-only falls back to a blurred fill');
  });
}
