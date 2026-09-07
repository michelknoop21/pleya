import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../test_helpers/notice_layer.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/profile_navigation.dart';

/// DEC-109: the "Meer lezen" action only exists on real synopsis overflow,
/// opens a scrollable panel with the untruncated text, and gives back the
/// focus contract UP (action row) → read more → UP (topnav), DOWN reverses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetNotices);

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  const longSummary =
      'A lonely young woman, Sintel, helps and befriends a dragon, whom she calls Scales. '
      'But when he is kidnapped by an adult dragon, Sintel decides to embark on a dangerous quest '
      'that takes her across the ashen plains and into the mountain caves where the old dragons '
      'still sleep, unaware that the journey is about to change everything she thought she knew.';

  MediaItem movie({required String? summary}) => MediaItem(
    id: 'movie_1',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.movie,
    title: 'Sintel',
    year: 2010,
    summary: summary,
    durationMs: 14 * 60 * 1000,
  );

  Future<void> pumpDetail(WidgetTester tester, MediaItem metadata, {Size size = const Size(1280, 720)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await SettingsService.getInstance();

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: monoTheme(dark: true),
          home: withProfileNavigationScope(child: MediaDetailScreen(metadata: metadata)),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// `FocusableWrapper` (and `FocusableAction`) attach the caller's
  /// `FocusNode` to an internal `Focus`, so this is how a test reaches a
  /// specific control's node without the app exposing a public accessor for
  /// every private `State`.
  FocusNode focusNodeWithLabel(WidgetTester tester, String label) {
    for (final element in tester.allElements) {
      final widget = element.widget;
      if (widget is Focus && widget.focusNode?.debugLabel == label) return widget.focusNode!;
    }
    throw StateError('No Focus with debugLabel "$label" found');
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('a long synopsis gets a focusable Read more action', (tester) async {
    await pumpDetail(tester, movie(summary: longSummary));

    expect(find.text(t.discover.readMore), findsOneWidget);

    final readMore = focusNodeWithLabel(tester, 'detail_read_more');
    readMore.requestFocus();
    await tester.pump();
    expect(readMore.hasPrimaryFocus, isTrue);
  });

  testWidgets('a short synopsis has no Read more action, and UP from the action row stays put', (tester) async {
    await pumpDetail(tester, movie(summary: 'A short film.'));

    expect(find.text(t.discover.readMore), findsNothing);

    final playButton = focusNodeWithLabel(tester, 'play_button');
    playButton.requestFocus();
    await tester.pump();

    await press(tester, LogicalKeyboardKey.arrowUp);

    // No overflow, no focus stop above the action row (DEC-109): the press
    // has nowhere to go, exactly as before the action existed.
    expect(playButton.hasPrimaryFocus, isTrue);
  });

  testWidgets('UP from the action row reaches Read more when it overflows, DOWN returns', (tester) async {
    await pumpDetail(tester, movie(summary: longSummary));

    final playButton = focusNodeWithLabel(tester, 'play_button');
    playButton.requestFocus();
    await tester.pump();

    await press(tester, LogicalKeyboardKey.arrowUp);
    final readMore = focusNodeWithLabel(tester, 'detail_read_more');
    expect(readMore.hasPrimaryFocus, isTrue);

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(playButton.hasPrimaryFocus, isTrue);
  });

  testWidgets('SELECT on Read more opens the full synopsis, Menu closes it and restores focus', (tester) async {
    await pumpDetail(tester, movie(summary: longSummary));

    final readMore = focusNodeWithLabel(tester, 'detail_read_more');
    readMore.requestFocus();
    await tester.pump();
    expect(readMore.hasPrimaryFocus, isTrue);

    await press(tester, LogicalKeyboardKey.select);

    // The compact hero already holds the full string behind an ellipsis
    // clip, so "the panel shows more" isn't provable by text content — the
    // panel opening (its title) and closing again is what these assert.
    expect(find.text(t.discover.overview), findsOneWidget);

    // `LogicalKeyboardKey.escape` is this suite's Menu/Back stand-in — see
    // `key_event_utils.dart`'s `isBackKey`.
    await press(tester, LogicalKeyboardKey.escape);

    expect(find.text(t.discover.overview), findsNothing);
    expect(readMore.hasPrimaryFocus, isTrue);
  });
}
