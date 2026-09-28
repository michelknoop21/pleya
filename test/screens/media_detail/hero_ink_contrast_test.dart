/// In the light theme the meta line, the score labels and the action row are
/// dark ink over the poster fade and its glow. That ink has to bring its own
/// backing: contrast may not depend on the artwork (DEC-140). Each case is
/// pumped over a solid black and a solid white scene and measured on the
/// pixels painted behind the text, with the ink itself made transparent
/// (the theme's `onSurface` at alpha 0; tints derived through `withValues`
/// keep their own alpha, so they stay part of the measured background).
/// Dark and OLED keep the old look: no plate of their own.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/external_rating.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/media_detail/mobile/detail_primary_actions.dart';
import 'package:pleya/screens/media_detail/mobile/detail_score_row.dart';
import 'package:pleya/screens/media_detail/mobile/mobile_poster_hero.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../../test_helpers/contrast.dart';

const _sceneKey = Key('scene');

final _item = MediaItem(
  id: 'm',
  backend: MediaBackend.jellyfin,
  kind: MediaKind.movie,
  title: 'Sintel',
  year: 2010,
  contentRating: '12',
  serverId: 's',
  serverName: 'S',
);

const _ratings = [
  ExternalRating(source: ExternalRatingSource.imdb, value: 7.4),
  ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: 92),
];

/// [theme] with its ink painted fully transparent.
ThemeData _invisibleInk(ThemeData theme) =>
    theme.copyWith(colorScheme: theme.colorScheme.copyWith(onSurface: theme.colorScheme.onSurface.withAlpha(0)));

Future<void> _pumpScene(WidgetTester tester, ThemeData theme, Color scene, Widget child) async {
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: RepaintBoundary(
        key: _sceneKey,
        child: Material(color: scene, child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _hero() => SingleChildScrollView(
  child: MobilePosterHero(
    item: _item,
    artUrl: null,
    posterUrl: 'https://x/poster.jpg',
    logoUrl: null,
    scoreRow: const DetailScoreRow(ratings: _ratings),
  ),
);

Widget _actions() => Padding(
  padding: const EdgeInsets.all(16),
  child: DetailPrimaryActions(
    playLabel: 'Hervatten',
    onPlay: () {},
    onPlayFromStart: () {},
    actions: [
      DetailActionItem(
        key: const Key('media-detail.action.rate'),
        icon: Icons.star_border_rounded,
        label: 'Beoordeel',
        onTap: () {},
      ),
      DetailActionItem(
        key: const Key('media-detail.action.more'),
        icon: Icons.more_vert_rounded,
        label: 'Meer',
        onTap: () {},
      ),
    ],
  ),
);

Future<double> _measure(WidgetTester tester, Finder area, Color ink, {double inset = 0}) => textContrastOverBackground(
  tester,
  area: area,
  textColor: ink,
  percentile: 0.05,
  boundary: find.byKey(_sceneKey),
  inset: inset,
);

void main() {
  // The poster's image cache asks for a directory once the capture lets real
  // async work run; the poster itself never loads (no network in tests).
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
  });

  final light = monoTheme(dark: false);
  final ink = light.colorScheme.onSurface;

  group('light theme: the ink owns its contrast', () {
    for (final scene in [Colors.black, Colors.white]) {
      final name = scene == Colors.black ? 'black' : 'white';

      testWidgets('meta line and score labels >= 4.5:1 over a $name scene', (tester) async {
        await _pumpScene(tester, _invisibleInk(light), scene, _hero());
        for (final text in ['2010', '12', '7.4', '92%']) {
          final ratio = await _measure(tester, find.text(text), ink);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '"$text" over $name: $ratio');
        }
      });

      testWidgets('action glyphs, labels and restart glyph >= 4.5:1 over a $name scene', (tester) async {
        await _pumpScene(tester, _invisibleInk(light), scene, _actions());
        // Icons fill their 46/52 pt circle box; the inset keeps the sample
        // to the 22/23 pt glyph in the middle.
        final areas = {
          'rate glyph': (find.byIcon(Icons.star_border_rounded), 12.0),
          'more glyph': (find.byIcon(Icons.more_vert_rounded), 12.0),
          'restart glyph': (find.byIcon(Icons.replay_rounded), 14.5),
          'rate label': (find.text('Beoordeel'), 0.0),
          'more label': (find.text('Meer'), 0.0),
        };
        for (final MapEntry(:key, value: (area, inset)) in areas.entries) {
          final ratio = await _measure(tester, area, ink, inset: inset);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$key over $name: $ratio');
        }
      });
    }
  });

  for (final oled in [false, true]) {
    final dark = monoTheme(dark: true, oled: oled);
    testWidgets('dark (oled: $oled): no plates, old circle tints', (tester) async {
      await _pumpScene(
        tester,
        dark,
        Colors.black,
        Column(
          children: [
            Expanded(child: _hero()),
            _actions(),
          ],
        ),
      );
      final surface = dark.colorScheme.surface;
      final plates = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((b) {
        final d = b.decoration;
        return d is BoxDecoration && d.color != null && d.color!.withAlpha(255) == surface.withAlpha(255);
      });
      expect(plates, isEmpty);
      final restart = tester.widget<Material>(find.byKey(const Key('media-detail.play-from-start')));
      expect(restart.color, Colors.white.withValues(alpha: 0.14));
    });
  }
}
