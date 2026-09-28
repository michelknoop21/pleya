import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('six actions share the width equally, the active one is a white circle', (tester) async {
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
                as BoxDecoration)
            .color;
    expect(circleOf('watched'), Colors.white);
    expect(circleOf('rate'), isNot(Colors.white));

    expect(find.bySemanticsLabel('spoken watched'), findsOneWidget);
    await tester.tap(find.byKey(const Key('media-detail.action.more')));
    expect(tapped, ['more']);
  });

  testWidgets('light theme: the play capsule and the active circle invert, nothing white on white', (tester) async {
    final theme = monoTheme(dark: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: DetailPrimaryActions(
            playLabel: 'Afspelen',
            onPlay: () {},
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
    expect(play.style?.backgroundColor?.resolve({}), theme.colorScheme.onSurface);
    expect(play.style?.foregroundColor?.resolve({}), theme.scaffoldBackgroundColor);
    final circle = tester.widget<DecoratedBox>(
      find.descendant(of: find.byKey(const Key('media-detail.action.watched')), matching: find.byType(DecoratedBox)),
    );
    expect((circle.decoration as BoxDecoration).color, theme.colorScheme.onSurface);
  });
}
