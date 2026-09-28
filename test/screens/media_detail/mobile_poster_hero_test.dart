import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/external_rating.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/media_detail/mobile/detail_ambient_background.dart';
import 'package:pleya/screens/media_detail/mobile/detail_score_row.dart';
import 'package:pleya/screens/media_detail/mobile/mobile_poster_hero.dart';
import 'package:pleya/screens/media_detail/mobile_detail_hero.dart';
import 'package:pleya/theme/mono_theme.dart';

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

  testWidgets('on a short page the glow runs on past the content, not cut at its height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: DetailAmbientBackground(
            image: MemoryImage(_onePixelPng),
            child: const SizedBox(height: 300, width: 390, child: Text('page')),
          ),
        ),
      ),
    );
    final outer = find.descendant(of: find.byType(DetailAmbientBackground), matching: find.byType(Stack)).first;
    expect(tester.widget<Stack>(outer).clipBehavior, Clip.none);
    expect(tester.getSize(outer).height, 300);
    final glow = find.descendant(of: outer, matching: find.byType(RepaintBoundary)).first;
    expect(tester.getSize(glow).height, 1500, reason: 'the glow keeps its full height below a 300 pt page');
  });

  // Light theme: the poster fades into a near-white page, so the meta line,
  // the rating frame and the score labels over the fade must be dark ink.
  group('hero foreground follows the theme', () {
    final item = MediaItem(
      id: 'm',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Sintel',
      year: 2010,
      contentRating: '12',
      serverId: 's',
      serverName: 'S',
    );

    Future<({Color? meta, Color? rating, Color? score})> pumpPoster(WidgetTester tester, ThemeData theme) async {
      tester.view.physicalSize = const Size(402, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Color? score;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MobilePosterHero(
                item: item,
                posterUrl: 'https://x/poster.jpg',
                fallbackArtUrl: null,
                scoreRow: Builder(
                  builder: (context) {
                    score = DefaultTextStyle.of(context).style.color;
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      return (
        meta: tester.widget<Text>(find.text('2010')).style?.color,
        rating: tester.widget<Text>(find.text('12')).style?.color,
        score: score,
      );
    }

    testWidgets('light theme: meta, rating and scores are dark ink', (tester) async {
      final theme = monoTheme(dark: false);
      final c = await pumpPoster(tester, theme);
      expect(c.meta, theme.colorScheme.onSurface);
      expect(c.rating, theme.colorScheme.onSurface);
      expect(c.score, theme.colorScheme.onSurface);
    });

    for (final oled in [false, true]) {
      testWidgets('dark theme (oled: $oled): meta, rating and scores stay white', (tester) async {
        final c = await pumpPoster(tester, monoTheme(dark: true, oled: oled));
        expect(c.meta, Colors.white);
        expect(c.rating, Colors.white);
        expect(c.score, Colors.white);
      });
    }

    Future<Color?> glyphOf(WidgetTester tester, ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: GlassCircleButton(icon: Icons.arrow_back_rounded, onPressed: () {}, tooltip: 'Back'),
          ),
        ),
      );
      // MaterialApp animates a theme change; let it land.
      await tester.pumpAndSettle();
      return tester.widget<Icon>(find.byIcon(Icons.arrow_back_rounded)).color;
    }

    testWidgets('glass circle glyph is dark ink in light theme, white in dark', (tester) async {
      final light = monoTheme(dark: false);
      expect(await glyphOf(tester, light), light.colorScheme.onSurface);
      expect(await glyphOf(tester, monoTheme(dark: true)), Colors.white);
      expect(await glyphOf(tester, monoTheme(dark: true, oled: true)), Colors.white);
    });
  });

  testWidgets('score row names each source for VoiceOver', (tester) async {
    final semantics = tester.ensureSemantics();
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
    expect(find.bySemanticsLabel('IMDb 7.4'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Rotten Tomatoes.* 92%$')), findsOneWidget);
    semantics.dispose();
  });

  // M-2: the bar owns the status bar style also before it collapses.
  for (final dark in [false, true]) {
    testWidgets('hero bar sets the status bar style from the theme at rest (dark: $dark)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: dark),
          home: Scaffold(body: MobileDetailHeroBar(leading: const SizedBox())),
        ),
      );
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(
          of: find.byType(MobileDetailHeroBar),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      expect(region.value, dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
    });
  }
}
