import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/media_card.dart';

import '../test_helpers/prefs.dart';

/// The desktop card in Verder kijken (DEC-144, mockup 38 A / 40): one status
/// line, `S3 E4 · 18min left` or `S3 E5 · Next episode`, in the grid and in
/// the list, and never a second `S3 E4` under it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  MediaItem episode({required int episode, int? viewOffsetMs}) => MediaItem(
    id: 'bear-$episode',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.episode,
    title: 'Violet',
    grandparentTitle: 'The Bear',
    grandparentId: 'bear',
    parentId: 'bear-s3',
    parentIndex: 3,
    index: episode,
    durationMs: 48 * 60 * 1000,
    viewOffsetMs: viewOffsetMs,
  );

  Future<void> pump(WidgetTester tester, MediaItem item, {required bool list}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: SizedBox(
            width: list ? 600 : 200,
            height: list ? 160 : 330,
            child: MediaCard(
              item: item,
              forceGridMode: !list,
              forceListMode: list,
              isOffline: true,
              isInContinueWatching: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  for (final list in [false, true]) {
    final layout = list ? 'list' : 'grid';

    testWidgets('$layout: begonnen shows place and what is left, once', (tester) async {
      await pump(tester, episode(episode: 4, viewOffsetMs: 30 * 60 * 1000), list: list);
      expect(find.text('The Bear'), findsOneWidget);
      expect(find.text('S3 E4 · 18min left'), findsOneWidget);
      expect(find.textContaining('Violet'), findsNothing, reason: 'the episode title belongs to focus and overview');
      expect(find.text('S3 E4'), findsNothing, reason: 'no second place line under the status line');
      expect(find.text('S3'), findsNothing);
    });

    testWidgets('$layout: volgende aflevering is named, not only bar-less', (tester) async {
      await pump(tester, episode(episode: 5), list: list);
      expect(find.text('S3 E5 · Next episode'), findsOneWidget);
    });
  }

  testWidgets('with episode numbers off the line keeps the season only', (tester) async {
    await SettingsService.instance.write(SettingsService.showEpisodeNumberOnCards, false);
    await pump(tester, episode(episode: 5), list: false);
    expect(find.text('S3 · Next episode'), findsOneWidget);
  });
}
