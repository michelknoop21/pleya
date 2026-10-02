import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/media_detail/mobile/detail_seasons_rail.dart';
import 'package:pleya/theme/mono_theme.dart';

MediaItem _season(int index, {int leafCount = 3, int viewed = 0}) => MediaItem(
  id: 'season-$index',
  backend: MediaBackend.plex,
  kind: MediaKind.season,
  title: index == 0 ? 'Specials' : 'Seizoen $index',
  index: index,
  leafCount: leafCount,
  viewedLeafCount: viewed,
);

Widget _host(List<MediaItem> seasons, void Function(MediaItem) onOpen) => MaterialApp(
  theme: monoTheme(dark: true),
  home: Scaffold(
    body: DetailSeasonsRail(seasons: seasons, onOpen: onOpen),
  ),
);

void main() {
  setUp(() async => LocaleSettings.setLocale(AppLocale.nl));

  testWidgets('two seasons: heading, two posters, tap opens the second', (tester) async {
    MediaItem? opened;
    await tester.pumpWidget(_host([_season(1, viewed: 2), _season(0, leafCount: 2)], (s) => opened = s));

    expect(find.text('2 seizoenen'), findsOneWidget);
    expect(find.byKey(const ValueKey('season-poster-season-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('season-poster-season-0')), findsOneWidget);
    // Partly watched: progress bar and what is left; untouched: a badge.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('3 afleveringen · 1 nog te zien'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('season-poster-season-0')));
    expect(opened?.id, 'season-0');
  });

  testWidgets('one season is one poster under "1 seizoen"', (tester) async {
    await tester.pumpWidget(_host([_season(1)], (_) {}));
    expect(find.text('1 seizoen'), findsOneWidget);
    expect(find.byKey(const ValueKey('season-poster-season-1')), findsOneWidget);
  });

  testWidgets('an empty list draws nothing', (tester) async {
    await tester.pumpWidget(_host(const [], (_) {}));
    expect(find.byType(Text), findsNothing);
  });
}
