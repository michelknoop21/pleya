/// A viewer who walks the tabs faster than a slow server answers. Whatever comes
/// back in whatever order, the tab under the remote ends up with its episodes or
/// with a way to ask again, and never with a Play button that stays off.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_cards.dart';
import 'package:pleya/screens/media_detail/tv/tv_detail_tab_pill.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../../../test_helpers/notice_layer.dart';
import '../../../test_helpers/prefs.dart';
import 'tv_detail_loading_harness.dart';

Map<String, List<MediaItem>> _episodes(int seasons) => {
  for (var season = 1; season <= seasons; season++)
    'season_$season': [for (var i = 1; i <= 3; i++) loadingEpisode(season, i)],
};

LoadingClient _fiveSeasons() =>
    LoadingClient(seasons: [for (var i = 1; i <= 5; i++) loadingSeason(i)], episodes: _episodes(5));

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

  /// Serie, 1, 2, 3, 4 and back on 3, with 2, 3 and 4 on their way.
  Future<void> walkToThreeAndBack(WidgetTester tester, LoadingClient client) async {
    for (final id in ['season_2', 'season_3', 'season_4']) {
      client.gates[id] = Completer<void>();
    }
    await pumpDetail(tester, client);
    await pressKey(tester, LogicalKeyboardKey.arrowRight);
    await stepKey(tester, LogicalKeyboardKey.arrowRight);
    await stepKey(tester, LogicalKeyboardKey.arrowRight);
    await stepKey(tester, LogicalKeyboardKey.arrowRight);
    await stepKey(tester, LogicalKeyboardKey.arrowLeft);
    expect(episodeRow(tester), ['season_3']);
  }

  Future<void> release(WidgetTester tester, LoadingClient client) async {
    for (final gate in client.gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('back on a season whose answer was overtaken: the answer still counts', (tester) async {
    final client = _fiveSeasons();
    await walkToThreeAndBack(tester, client);

    await release(tester, client);

    expect(episodeRow(tester), ['season_3', 'e3-1', 'e3-2', 'e3-3']);
    expect(playButton(tester).onTap, isNotNull);
  });

  testWidgets('the same answer failing leaves a way to try again', (tester) async {
    final client = _fiveSeasons()..failOnce.add('season_3');
    await walkToThreeAndBack(tester, client);

    await release(tester, client);

    expect(episodeRow(tester), ['season_3', 'retry']);
    tester.widget<TvDetailViewAllCard>(find.byType(TvDetailViewAllCard)).onSelect();
    await tester.pumpAndSettle();
    expect(episodeRow(tester), ['season_3', 'e3-1', 'e3-2', 'e3-3']);
  });

  testWidgets('an answer for the tab the viewer left is kept for when they come back', (tester) async {
    final client = _fiveSeasons();
    await walkToThreeAndBack(tester, client);
    await release(tester, client);

    await stepKey(tester, LogicalKeyboardKey.arrowRight);

    expect(episodeRow(tester), ['season_4', 'e4-1', 'e4-2', 'e4-3']);
    expect(client.pages.where((page) => page == 'season_4@0'), hasLength(1), reason: 'it came in, so ask it once');
  });

  testWidgets('out through Menu and back in by the poster: the same season loads', (tester) async {
    final client = _fiveSeasons();
    await walkToThreeAndBack(tester, client);

    await stepKey(tester, LogicalKeyboardKey.escape);
    await release(tester, client);
    expect(tester.widget<TvDetailTabPill>(find.widgetWithText(TvDetailTabPill, t.discover.seriesTab)).active, isTrue);
    expect(detailFocus, 'TvDetailCard_seasons(season_3)');

    await pressKey(tester, LogicalKeyboardKey.enter);

    expect(episodeRow(tester), ['season_3', 'e3-1', 'e3-2', 'e3-3']);
    expect(playButton(tester).onTap, isNotNull);
  });

  group('a series without seasons of its own', () {
    testWidgets('retry keeps the tab, and the focus on it', (tester) async {
      final client = LoadingClient(seasons: [loadingSeason(1)])..failOnce.add('season_1');
      await pumpDetail(tester, client);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      await pressKey(tester, LogicalKeyboardKey.arrowDown);
      client.gates['season_1'] = Completer<void>();

      await stepKey(tester, LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.widgetWithText(TvDetailTabPill, 'Episodes'), findsOneWidget);
      expect(detailFocus, 'detail_tab_episodes');
      await release(tester, client);
      expect(episodeRow(tester), ['e1-1', 'e1-2', 'e1-3']);
    });
  });

  group('a season without episodes', () {
    LoadingClient emptySecond() =>
        LoadingClient(episodes: {'season_1': _episodes(1)['season_1']!, 'season_2': const []});

    testWidgets('Play says why instead of doing nothing', (tester) async {
      await pumpDetail(tester, emptySecond());
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      expect(episodeRow(tester), ['season_2']);

      playButton(tester).onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(t.messages.noEpisodesFoundGeneral), findsOneWidget);
    });

    testWidgets('a page still on its way is no such reason', (tester) async {
      final client = emptySecond()..gates['season_2'] = Completer<void>();
      await pumpDetail(tester, client);
      await pressKey(tester, LogicalKeyboardKey.arrowRight);
      await stepKey(tester, LogicalKeyboardKey.arrowRight);

      expect(playButton(tester).onTap, isNull);
      await release(tester, client);
    });
  });
}
