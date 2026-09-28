import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/item_watcher.dart';
import 'package:pleya/screens/media_detail/mobile/detail_activity_card.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/watcher_avatar.dart';

void main() {
  setUp(() async => LocaleSettings.setLocale(AppLocale.nl));
  tearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

  Future<void> pump(WidgetTester tester, DetailActivityCard card) => tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true),
      home: Scaffold(body: card),
    ),
  );

  const watchers = [
    ItemWatcher(id: '1', displayName: 'Michel', isSelf: true),
    ItemWatcher(id: '2', displayName: 'Sam'),
  ];

  testWidgets('empty input draws nothing', (tester) async {
    await pump(
      tester,
      const DetailActivityCard(watchers: [], nowWatchingName: null, playCount: 7, viewerCount: 3, isSeries: false),
    );
    expect(find.descendant(of: find.byType(DetailActivityCard), matching: find.byType(SizedBox)), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('film: live viewer in white with a red dot, then the counts', (tester) async {
    await pump(
      tester,
      const DetailActivityCard(
        watchers: watchers,
        nowWatchingName: 'Robin',
        playCount: 7,
        viewerCount: 3,
        isSeries: false,
      ),
    );
    expect(find.text('Bekeken door Jij en Sam'), findsOneWidget);
    expect(find.textContaining('Robin kijkt dit nu · 7× afgespeeld · 3 kijkers', findRichText: true), findsOneWidget);

    final rich = tester.widget<RichText>(find.textContaining('Robin kijkt dit nu', findRichText: true));
    TextSpan? live;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == 'Robin kijkt dit nu') live = span;
      return live == null;
    });
    expect(live?.style?.color, Colors.white);
    final dot = tester.widget<Container>(find.byKey(const Key('media-detail.activity.live-dot')));
    expect((dot.decoration! as BoxDecoration).color, const Color(0xFFE5140F));
    expect(find.byType(WatcherAvatar), findsNWidgets(2));
  });

  testWidgets('series: second line leads with the own progress', (tester) async {
    await pump(
      tester,
      const DetailActivityCard(
        watchers: watchers,
        nowWatchingName: null,
        playCount: 9,
        viewerCount: null,
        isSeries: true,
        ownProgressLabel: 'Jij bent bij S1 A3',
      ),
    );
    expect(find.textContaining('Jij bent bij S1 A3 · 9× afgespeeld', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('media-detail.activity.live-dot')), findsNothing);
  });
}
