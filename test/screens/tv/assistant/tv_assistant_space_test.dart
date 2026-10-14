// How much of the answer the TV surface shows without scrolling: the panel
// must not waste screen (IMG_8805, 4 Oct 2026). Laid out at Apple TV's 1038x584,
// and at 1920x935, the surface under the tab bar as the simulator runs it.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_suggestions.dart';
import 'package:provider/provider.dart';

import 'tv_assistant_test_support.dart';

AssistantTitleMatch _match(int i, {bool inLibrary = true}) => AssistantTitleMatch(
  matchId: 'm$i',
  title: 'Mission: Impossible $i',
  year: 1996 + i,
  kind: 'movie',
  confidence: 'high',
  targets: [
    if (inLibrary)
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

  // Fully inside the list's own viewport, edges included.
  Future<({int visible, int chips, double lead})> pump(
    WidgetTester tester,
    Size size, {
    required bool inLibrary,
    String answer = 'Dit zijn de beste kandidaten.',
    int matches = 8,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = FakeAssistantController()
      ..prompt = 'Een film over spionnen'
      ..state = AssistantSurfaceState.result
      ..answer = answer
      ..displays = [
        AssistantTitleMatches(AssistantToolContext(servers: MultiServerManager()), [
          for (var i = 1; i <= matches; i++) _match(i, inLibrary: inLibrary),
        ]),
      ];
    addTearDown(c.dispose);
    // The same three follow-ups every run, whatever the pool draws.
    BigPSuggestions.install(c, BigPSuggestions(random: Random(7)));
    final entry = AppleTvNativeTextEntry();
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<AssistantController>.value(
          value: c,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: MediaQuery(
              data: MediaQueryData(size: size, disableAnimations: true),
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
    final cards = find.byType(BigPMatchCard);
    final viewport = tester.getRect(find.ancestor(of: cards.first, matching: find.byType(Scrollable)).first);
    var visible = 0;
    for (var i = 0; i < cards.evaluate().length; i++) {
      final rect = tester.getRect(cards.at(i));
      if (rect.top >= viewport.top - 0.5 && rect.bottom <= viewport.bottom + 0.5) visible++;
    }
    final body = find.byKey(const ValueKey('assistant.answer.body'));
    final lead = body.evaluate().isEmpty
        ? tester.getSize(find.byKey(const ValueKey('assistant.answer'))).height
        : tester.getSize(find.ancestor(of: body, matching: find.byType(SingleChildScrollView)).first).height;
    return (visible: visible, chips: find.byType(BigPChip).evaluate().length, lead: lead);
  }

  testWidgets('eight matches: five cards fit the panel without scrolling (four before the panel was widened)', (
    tester,
  ) async {
    final shown = await pump(tester, const Size(1038, 584), inLibrary: true);
    expect(shown.chips, 3);
    expect(shown.visible, greaterThanOrEqualTo(5));
  });

  testWidgets('eight matches that cannot be opened: five still show with the follow-ups, not three', (tester) async {
    final shown = await pump(tester, const Size(1920, 935), inLibrary: false);
    expect(shown.chips, 3, reason: 'the follow-ups are in the tree, under the cards');
    expect(shown.visible, greaterThanOrEqualTo(5));
  });

  const longLead =
      'Right now the most popular are the film Dune: Part Two, the series Shogun and the series Carrie (2024), '
      'with Interstellar and Gravity close behind, and a lot more this week on every server you have connected';

  // A lead too long for a headline reads in a box of three lines. When the
  // cards leave a whole line over, the box grows to four; when they do not,
  // it stays at three and no card is lost to it.
  for (final size in const [Size(1038, 584), Size(1920, 935)]) {
    testWidgets('long lead, ${size.width.toInt()} wide: three lines when the cards need the room', (tester) async {
      final shown = await pump(tester, size, inLibrary: true, answer: longLead);
      await tester.pumpWidget(const SizedBox());
      final grown = await pump(tester, size, inLibrary: true, answer: longLead, matches: 3);
      expect(grown.visible, 3, reason: 'few cards: every one is in view');
      // Four lines against three: the room the cards left over went to the text.
      expect(grown.lead, closeTo(shown.lead * 4 / 3, 0.5));
    });
  }

  testWidgets('long lead keeps the fifth card of eight at 1920x935', (tester) async {
    final shown = await pump(tester, const Size(1920, 935), inLibrary: true, answer: longLead);
    expect(shown.visible, greaterThanOrEqualTo(5));
  });

  testWidgets('the follow-ups in the list stay reachable: Ask, the chips, Klaar and the list, no focus trap', (
    tester,
  ) async {
    await pump(tester, const Size(1920, 935), inLibrary: false);
    String where() {
      final f = FocusManager.instance.primaryFocus;
      final ctx = f?.context;
      if (ctx == null) return 'none';
      if (ctx.findAncestorWidgetOfExactType<BigPChip>() != null) return 'chip';
      return f?.debugLabel ?? '${f.runtimeType}';
    }

    // The traversal itself, not the list's key handler: what the focus order
    // allows, whichever way the remote leaves the list.
    final seen = <String>{where()};
    for (final direction in [TraversalDirection.up, TraversalDirection.down]) {
      for (var i = 0; i < 8; i++) {
        FocusManager.instance.primaryFocus!.focusInDirection(direction);
        await tester.pump(const Duration(milliseconds: 400));
        seen.add(where());
      }
    }
    // "Nieuw" sits between Vraag Big P and Klaar, so Down from the chips lands on it.
    expect(seen, containsAll(['assistant.ask', 'assistant.results', 'chip', t.assistant.mobile.newConversationShort]));

    // And Klaar is one step to the right of "Nieuw".
    for (var i = 0; i < 8 && where() != t.assistant.mobile.newConversationShort; i++) {
      FocusManager.instance.primaryFocus!.focusInDirection(TraversalDirection.down);
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(where(), t.assistant.mobile.newConversationShort);
    FocusManager.instance.primaryFocus!.focusInDirection(TraversalDirection.right);
    await tester.pump(const Duration(milliseconds: 400));
    expect(where(), t.assistant.result.done);
  });
}
