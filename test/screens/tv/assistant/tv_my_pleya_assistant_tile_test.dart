/// Big P's entry in Mijn Pleya (mockup 38 A): first tile of the Pleya group,
/// a portrait instead of a line icon, only when the controller shows him,
/// and the route back that puts the remote on that tile.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/screens/tv/sections/tv_libraries_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_navigator.dart';
import 'package:pleya/screens/tv/tv_my_pleya_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:provider/provider.dart';

import 'tv_assistant_test_support.dart';

void main() {
  List<TvMyPleyaGroup> groups({required bool showAssistant}) => buildTvMyPleyaGroups(
    hasWatchlist: true,
    hasSeerr: true,
    showDownloads: false,
    showActivity: true,
    showCollections: true,
    showPlaylists: true,
    showAssistant: showAssistant,
  );

  test('Big P is the first tile of the Pleya group, and absent when hidden', () {
    final pleya = groups(showAssistant: true).last;
    expect(pleya.label, t.tvMyPleya.groupPleya);
    expect(pleya.tiles.first.section, TvMyPleyaSection.assistant);
    expect(pleya.tiles.first.title, t.assistant.tileTitle);
    expect(pleya.tiles.first.subtitle, t.assistant.tileSubtitle);

    final all = groups(showAssistant: false).expand((g) => g.tiles).map((tile) => tile.section);
    expect(all, isNot(contains(TvMyPleyaSection.assistant)));
  });

  test('the route back from Big P lands on his tile', () {
    final route = tvMyPleyaNestedRoute(TvMyPleyaSection.assistant);
    expect(route.id, 'tvMyPleya_assistant');
    expect(route.restoreFocusKey, TvMyPleyaSection.assistant.tileFocusKey);
    expect(route.screenKey, isNotNull, reason: 'the shell asks the surface where its focus belongs');
  });

  test('"Vraag Big P" is a library action only where Big P shows', () {
    const library = MediaLibrary(
      id: '1',
      backend: MediaBackend.plex,
      title: 'Films',
      kind: MediaKind.movie,
      serverId: 's',
    );
    expect(tvLibraryActionsFor(library, canManage: true, canAskBigP: true).last, TvLibraryAction.askBigP);
    expect(tvLibraryActionsFor(library, canManage: true), isNot(contains(TvLibraryAction.askBigP)));
  });

  group('on the hub', () {
    late MultiServerManager manager;
    late MultiServerProvider servers;
    late FakeAssistantController c;

    setUp(() {
      TvDetectionService.debugSetAppleTVOverride(true);
      manager = MultiServerManager();
      servers = MultiServerProvider(manager, DataAggregationService(manager));
      c = FakeAssistantController();
    });

    tearDown(() {
      servers.dispose();
      c.dispose();
      TvDetectionService.debugSetAppleTVOverride(null);
    });

    Future<void> pumpHub(WidgetTester tester) => pumpTvFrame(
      tester,
      c,
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: servers,
        child: TvMyPleyaScreen(onOpenSection: (_) {}, onSwitchProfile: () {}, onSignOut: () {}, onExitUp: () {}),
      ),
    );

    TvMyPleyaScreenState hub(WidgetTester tester) => tester.state<TvMyPleyaScreenState>(find.byType(TvMyPleyaScreen));

    testWidgets('asks the controller for availability and shows the portrait tile', (tester) async {
      await pumpHub(tester);

      expect(c.refreshes, 1);
      expect(find.text(t.assistant.tileTitle), findsOneWidget);
      expect(find.byType(BigPPortrait), findsOneWidget);
    });

    testWidgets('no tile while the controller hides Big P', (tester) async {
      c.availability = AssistantAvailability.hidden;
      await pumpHub(tester);

      expect(find.text(t.assistant.tileTitle), findsNothing);
      expect(hub(tester).availableSections, isNot(contains(TvMyPleyaSection.assistant)));
    });

    testWidgets('the restore key the shell hands back puts the remote on the tile', (tester) async {
      await pumpHub(tester);

      hub(tester).focusKey(TvMyPleyaSection.assistant.tileFocusKey);
      await tester.pump();

      expect(focusedLabel(), TvMyPleyaSection.assistant.tileFocusKey);
      // Left of Big P is the last tile of the group above; right is Instellingen.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focusedLabel(), TvMyPleyaSection.settings.tileFocusKey);
    });
  });

  testWidgets('the mood follows the stand, with the card winning', (tester) async {
    final c = FakeAssistantController();
    addTearDown(c.dispose);
    expect(tvAssistantMood(c), BigPMood.idle);
    c.state = AssistantSurfaceState.result;
    expect(tvAssistantMood(c), BigPMood.success);
    c.resultIsError = true;
    expect(tvAssistantMood(c), BigPMood.error);
  });
}
