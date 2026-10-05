// How much of the answer the TV surface shows without scrolling: the panel
// must not waste screen (IMG_8805, 4 Oct 2026). Laid out at Apple TV's 1038x584.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:provider/provider.dart';

import 'tv_assistant_test_support.dart';

AssistantTitleMatch _match(int i) => AssistantTitleMatch(
  matchId: 'm$i',
  title: 'Mission: Impossible $i',
  year: 1996 + i,
  kind: 'movie',
  confidence: 'high',
  targets: [
    (
      serverId: ServerId('zolder'),
      serverName: 'Zolder',
      item: MediaItem(
        id: 'i$i',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Mission: Impossible $i',
        year: 1996 + i,
        serverId: 'zolder',
        serverName: 'Zolder',
      ),
    ),
  ],
);

void main() {
  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('eight matches: five cards fit the panel without scrolling (four before the panel was widened)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1038, 584);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = FakeAssistantController()
      ..prompt = 'Een film over spionnen'
      ..state = AssistantSurfaceState.result
      ..answer = 'Dit zijn de beste kandidaten.'
      ..displays = [
        AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), [
          for (var i = 1; i <= 8; i++) _match(i),
        ]),
      ];
    addTearDown(c.dispose);
    final entry = AppleTvNativeTextEntry();
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<AssistantController>.value(
          value: c,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1038, 584), disableAnimations: true),
              child: InputModeTracker(
                child: Scaffold(
                  body: TvAssistantScreen(
                    speech: SpeechSearchService(textEntry: entry),
                    textEntry: entry,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final viewport = tester.getRect(find.byType(Scrollable).first);
    final cards = find.byType(BigPMatchCard);
    // Fully inside the list's own viewport, edges included.
    final visible = cards.evaluate().length == 0
        ? 0
        : [
            for (var i = 0; i < cards.evaluate().length; i++)
              if (tester.getRect(cards.at(i)).top >= viewport.top - 0.5 &&
                  tester.getRect(cards.at(i)).bottom <= viewport.bottom + 0.5)
                i,
          ].length;
    expect(visible, greaterThanOrEqualTo(5));
  });
}
