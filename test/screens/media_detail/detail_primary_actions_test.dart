import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/media_detail/mobile/detail_dark_style.dart';
import 'package:pleya/screens/media_detail/mobile/detail_primary_actions.dart';
import 'package:pleya/theme/mono_theme.dart';

void main() {
  testWidgets('play-from-start only shows while there is progress', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailPrimaryActions(playLabel: 'Afspelen', onPlay: () {}, actions: const []),
        ),
      ),
    );
    expect(find.byKey(const Key('media-detail.play-from-start')), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailPrimaryActions(
            playLabel: 'Hervatten',
            playDetail: 'nog 8 min',
            onPlay: () {},
            onPlayFromStart: () {},
            actions: const [],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('media-detail.play-from-start')), findsOneWidget);
  });

  testWidgets('six actions share the width equally, every circle is the same dark pill, active is only semantic', (
    tester,
  ) async {
    final tapped = <String>[];
    DetailActionItem item(String id, {bool active = false}) => DetailActionItem(
      key: Key('media-detail.action.$id'),
      icon: Icons.circle,
      label: id,
      active: active,
      semanticLabel: 'spoken $id',
      onTap: () => tapped.add(id),
    );
    tester.view.physicalSize = const Size(402, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: DetailPrimaryActions(
            playLabel: 'Afspelen',
            onPlay: () {},
            actions: [
              item('watchlist'),
              item('trailer'),
              item('rate'),
              item('watched', active: true),
              item('download'),
              item('more'),
            ],
          ),
        ),
      ),
    );

    final widths = [
      for (final id in ['watchlist', 'trailer', 'rate', 'watched', 'download', 'more'])
        tester.getSize(find.byKey(Key('media-detail.action.$id'))).width,
    ];
    expect(widths.toSet(), hasLength(1));
    expect(widths.first, moreOrLessEquals(402 / 6));
    expect(tester.takeException(), isNull);

    Color? circleOf(String id) =>
        ((tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byKey(Key('media-detail.action.$id')),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration)
                as ShapeDecoration)
            .color;
    // Plex look: no white circle for the active state, the glyph carries it.
    expect(circleOf('watched'), kDetailPillColor);
    expect(circleOf('rate'), kDetailPillColor);
    final watched = tester.getSemantics(find.byKey(const Key('media-detail.action.watched'))).getSemanticsData();
    expect(watched.flagsCollection.isSelected, ui.Tristate.isTrue);

    expect(find.bySemanticsLabel('spoken watched'), findsOneWidget);
    await tester.tap(find.byKey(const Key('media-detail.action.more')));
    expect(tapped, ['more']);
  });

  // Variant B: the page is always dark, so the play button is solid white
  // with a black label in every theme, and nothing sits on a plate.
  for (final dark in [false, true]) {
    testWidgets('play button is solid white with black ink (dark theme: $dark), no plate', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: dark),
          home: Scaffold(
            body: DetailPrimaryActions(
              playLabel: 'Afspelen',
              onPlay: () {},
              onPlayFromStart: () {},
              actions: [
                DetailActionItem(
                  key: const Key('media-detail.action.watched'),
                  icon: Icons.circle,
                  label: 'watched',
                  active: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      final play = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(play.style?.backgroundColor?.resolve({}), Colors.white);
      expect(play.style?.backgroundColor?.resolve({})?.a, 1.0);
      expect(play.style?.foregroundColor?.resolve({}), Colors.black);
      final restart = tester.widget<Material>(find.byKey(const Key('media-detail.play-from-start')));
      expect(restart.color, kDetailPillColor);
      expect(find.byType(BackdropFilter), findsNothing);
    });
  }
}
