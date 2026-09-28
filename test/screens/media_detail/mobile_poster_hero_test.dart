import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/external_rating.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/media_detail/mobile/detail_ambient_background.dart';
import 'package:pleya/screens/media_detail/mobile/detail_score_row.dart';
import 'package:pleya/screens/media_detail/mobile/mobile_poster_hero.dart';

// A 1x1 transparent PNG, so the test never touches the network.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('score row renders one icon per rating and no tap target', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailScoreRow(
          ratings: [
            ExternalRating(source: ExternalRatingSource.imdb, value: 7.4),
            ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 92),
          ],
        ),
      ),
    );
    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.text('7.4'), findsOneWidget);
    expect(find.text('92%'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets('score row is empty without ratings', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DetailScoreRow(ratings: [])));
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  // Review Focus 1.
  testWidgets('hero without poster falls back to the art image and a text title', (tester) async {
    final item = MediaItem(
      id: 'm',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Sintel',
      serverId: 's',
      serverName: 'S',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobilePosterHero(
            item: item,
            posterUrl: null,
            fallbackArtUrl: 'https://x/art.jpg',
            scoreRow: const SizedBox(),
          ),
        ),
      ),
    );
    expect(find.text('Sintel'), findsOneWidget);
    expect(find.byType(AspectRatio), findsOneWidget);
  });

  testWidgets('poster hero is 640 high at 402 wide and fades out through a dstIn mask', (tester) async {
    tester.view.physicalSize = const Size(402, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final item = MediaItem(
      id: 'm',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Sintel',
      year: 2010,
      genres: const ['Animation', 'Fantasy'],
      contentRating: '12',
      serverId: 's',
      serverName: 'S',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MobilePosterHero(
              item: item,
              posterUrl: 'https://x/poster.jpg',
              fallbackArtUrl: null,
              scoreRow: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(MobilePosterHero)).height, 640);
    expect(tester.widget<ShaderMask>(find.byType(ShaderMask)).blendMode, BlendMode.dstIn);
    expect(find.text('2010'), findsOneWidget);
    expect(find.text('Animation, Fantasy'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    // The poster carries the title; no second headline over it.
    expect(find.text('Sintel'), findsNothing);
  });

  testWidgets('ambient background blurs once and sits behind the child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DetailAmbientBackground(
          image: MemoryImage(_onePixelPng),
          child: const SizedBox(height: 100, child: Text('page')),
        ),
      ),
    );
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.text('page'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: DetailAmbientBackground(image: null, child: Text('page'))));
    expect(find.byType(ImageFiltered), findsNothing);
  });
}
