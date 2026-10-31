/// The artwork stands behind a page that rebuilds on every focus step. Two new
/// shader closures per build make [RenderShaderMask] repaint both masks over a
/// full screen of image, every step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_backdrop.dart';

void main() {
  testWidgets('a rebuild hands the masks the same callbacks, so neither repaints', (tester) async {
    final item = MediaItem(
      id: 'movie',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      artPath: '/art.jpg',
      serverId: 'server_1',
    );
    Widget art() => MaterialApp(home: TvDetailHeroArt(item: item, client: null));

    await tester.pumpWidget(art());
    final before = tester.widgetList<ShaderMask>(find.byType(ShaderMask)).map((mask) => mask.shaderCallback).toList();
    expect(before, hasLength(2));

    await tester.pumpWidget(art());
    final after = tester.widgetList<ShaderMask>(find.byType(ShaderMask)).map((mask) => mask.shaderCallback).toList();

    expect(after, before);
  });
}
