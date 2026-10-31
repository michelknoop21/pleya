/// What a detail page does while its data is on its way or did not come: the
/// list under a tab, the way back from a failure, and a cast that names one
/// person twice. Through the real screen.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_file_info.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_source_info.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_action_panel.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_cards.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_tab_pill.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/prefs.dart';
import 'tv_detail_loading_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() {
    resetNotices();
    TvDetectionService.debugSetAppleTVOverride(null);
    MediaDetailScreen.debugOnPlayEpisode = null;
  });

  group('a cast that names one person twice', () {
    const hanks = MediaRole(id: 'p1', tag: 'Tom Hanks', role: 'Woody');
    const hanksAgain = MediaRole(id: 'p1', tag: 'Tom Hanks', role: 'Narrator');
    const allen = MediaRole(id: 'p2', tag: 'Tim Allen', role: 'Buzz');

    testWidgets('gets one row of their own, and the next person the second', (tester) async {
      await pumpDetail(tester, LoadingClient(item: loadingMovie(const [hanks, hanksAgain, allen])));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await pressKey(tester, LogicalKeyboardKey.arrowDown);

      expect(tester.takeException(), isNull);
      final ids = page(tester).sections.map((section) => section.id);
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, containsAll(['person:p1', 'person:p2']));
    });

    testWidgets('stands once in the cast, so RIGHT walks on instead of landing on itself', (tester) async {
      await pumpDetail(tester, LoadingClient(item: loadingMovie(const [hanks, allen, hanksAgain])));
      final cast = page(tester).sections.firstWhere((section) => section.id == 'cast');
      expect(cast.itemIds, ['p1', 'p2']);

      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      expect(detailFocus, 'TvDetailCard_cast(p1)');
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      expect(detailFocus, 'TvDetailCard_cast(p2)');
    });

    testWidgets('two people without an id both stay', (tester) async {
      await pumpDetail(
        tester,
        LoadingClient(
          item: loadingMovie(const [MediaRole(tag: 'One', role: 'A'), MediaRole(tag: 'Two', role: 'B')]),
        ),
      );

      expect(page(tester).sections.firstWhere((section) => section.id == 'cast').itemIds, ['role-0', 'role-1']);
    });
  });

  group('a season tab whose first page is on its way', () {
    testWidgets('shows only its own card, and Play waits for the page', (tester) async {
      final client = LoadingClient()..gates['season_2'] = Completer<void>();
      await pumpDetail(tester, client);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      expect(episodeRow(tester), ['season_1', 'e1-1', 'e1-2', 'e1-3']);

      await stepKey(tester, LogicalKeyboardKey.arrowRight);

      expect(episodeRow(tester), ['season_2']);
      expect(playButton(tester).onTap, isNull);

      client.gates['season_2']!.complete();
      await tester.pumpAndSettle();
      expect(episodeRow(tester), ['season_2', 'e2-1', 'e2-2', 'e2-3']);
      expect(playButton(tester).onTap, isNotNull);
    });

    testWidgets('a tab stepped back to has its cards at once', (tester) async {
      final client = LoadingClient();
      await pumpDetail(tester, client);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);

      await stepKey(tester, LogicalKeyboardKey.arrowLeft);

      expect(episodeRow(tester), ['season_1', 'e1-1', 'e1-2', 'e1-3']);
      await tester.pumpAndSettle();
    });
  });

  group('the retry card', () {
    List<MediaItem> oneSeason = const [];
    setUp(() => oneSeason = [loadingSeason(1)]);

    testWidgets('a series without seasons of its own: a first load that failed has a way back', (tester) async {
      final client = LoadingClient(seasons: oneSeason)..failOnce.add('season_1');
      await pumpDetail(tester, client);

      expect(find.text('Episodes'), findsOneWidget);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      expect(episodeRow(tester), ['retry']);

      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      await pressKey(tester, LogicalKeyboardKey.enter);

      expect(episodeRow(tester), ['e1-1', 'e1-2', 'e1-3']);
    });

    testWidgets('a series without seasons of its own: a later page is read again', (tester) async {
      final client = LoadingClient(seasons: oneSeason)
        ..totals['season_1'] = 3
        ..failNextLaterPage = true;
      await pumpDetail(tester, client);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      page(tester).sections.single.onLoadMore!();
      await tester.pumpAndSettle();
      expect(episodeRow(tester).last, 'retry');

      client.pages.clear();
      tester.widget<TvDetailViewAllCard>(find.byType(TvDetailViewAllCard)).onSelect();
      await tester.pumpAndSettle();

      expect(client.pages, ['season_1@2']);
      expect(episodeRow(tester), ['e1-1', 'e1-2', 'e1-3']);
    });

    testWidgets('a season: a later page is read again', (tester) async {
      final client = LoadingClient()
        ..totals['season_1'] = 3
        ..totals['season_2'] = 3
        ..failNextLaterPage = true;
      await pumpDetail(tester, client);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      page(tester).sections.single.onLoadMore!();
      await tester.pumpAndSettle();
      expect(episodeRow(tester).last, 'retry');

      client.pages.clear();
      tester.widget<TvDetailViewAllCard>(find.byType(TvDetailViewAllCard)).onSelect();
      await tester.pumpAndSettle();

      expect(client.pages, hasLength(1));
      expect(episodeRow(tester).last, isNot('retry'));
      expect(episodeRow(tester), hasLength(4));
    });

    testWidgets('a deep link while the seasons fail leaves a way to try again', (tester) async {
      final client = LoadingClient()..seasonsFail = true;
      await pumpDetail(tester, client, episode: 'e1-1');

      expect(find.text(t.common.retry), findsOneWidget);
      client.seasonsFail = false;
      tester.widget<TvDetailViewAllCard>(find.byType(TvDetailViewAllCard)).onSelect();
      await tester.pumpAndSettle();

      expect(page(tester).sections.single.itemIds, contains('e1-1'));
    });
  });

  testWidgets('a season tab reads the tracks of the episode Play starts there', (tester) async {
    final client = LoadingClient(
      onDeck: loadingEpisode(1, 2),
      episodes: {
        'season_1': [loadingEpisode(1, 1, viewCount: 1), loadingEpisode(1, 2), loadingEpisode(1, 3)],
        'season_2': [loadingEpisode(2, 1, viewCount: 1), loadingEpisode(2, 2), loadingEpisode(2, 3)],
      },
    );
    await pumpDetail(tester, client);
    expect(client.fileInfoFor.last, 'e1-2');

    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(tester.widget<TvDetailTabPill>(find.widgetWithText(TvDetailTabPill, 'Season 2')).active, isTrue);
    expect(client.fileInfoFor.last, 'e2-2');
  });

  testWidgets('Meer acties offers no tracks of another season while this one loads', (tester) async {
    final client = LoadingClient(
      fileInfo: MediaFileInfo(
        audioTracks: [MediaAudioTrack(id: 1, languageCode: 'eng', codec: 'eac3', channels: 6, selected: true)],
      ),
    )..gates['season_2'] = Completer<void>();
    await pumpDetail(tester, client);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    await pressKey(tester, LogicalKeyboardKey.arrowDown);
    for (var i = 0; i < 8 && detailFocus != 'detail_more'; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(detailFocus, 'detail_more');
    await pressKey(tester, LogicalKeyboardKey.enter);

    final rows = tester.widget<TvDetailActionPanel>(find.byType(TvDetailActionPanel).last).rows.map((row) => row.id);
    expect(rows, isNot(contains('audio')));
    client.gates['season_2']!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('✓ takes the restart button away, and the focus stays on ✓', (tester) async {
    final client = LoadingClient(item: loadingMovie(const []).copyWith(viewOffsetMs: 1000));
    await pumpDetail(tester, client);
    for (var i = 0; i < 6 && detailFocus != 'detail_watched'; i++) {
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(detailFocus, 'detail_watched');
    client.watched = true;

    await pressKey(tester, LogicalKeyboardKey.enter);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byIcon(Symbols.replay_rounded), findsNothing);
    expect(detailFocus, 'detail_watched');
  });
}
