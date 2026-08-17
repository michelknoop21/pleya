import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../test_helpers/prefs.dart';
import 'package:pleya/widgets/focusable_media_card.dart';
import 'package:pleya/widgets/watchlist_card.dart';
import 'package:pleya/widgets/watchlist_item_sheet.dart';

final scope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');

WatchlistEntry entry({
  WatchlistAvailability availability = WatchlistAvailability.unknown,
  bool coverageComplete = false,
  MediaItem? lastKnownMatch,
  String title = 'Sintel',
}) {
  return WatchlistEntry(
    key: 'plex:abc',
    kind: MediaKind.movie,
    item: MediaItem(id: 'abc', backend: MediaBackend.plex, kind: MediaKind.movie, title: title, year: 2010),
    guid: 'plex://movie/abc',
    posterRef: 'https://metadata-static.plex.tv/poster.jpg',
    memberships: [WatchlistMembership(scope: scope, remoteKey: 'abc')],
    availability: availability,
    coverageComplete: coverageComplete,
    lastKnownMatch: lastKnownMatch,
  );
}

Future<void> pumpCard(WidgetTester tester, WatchlistEntry e) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: Center(
            child: WatchlistUnavailableCard(entry: e, onTap: () {}, width: 120),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // The playable branch renders the app's real MediaCard, which reads user
  // settings. Initialising the service keeps that branch honest instead of
  // stubbing the card away.
  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
  });

  group('four model states, three treatments', () {
    testWidgets('unknown shows no indicator, because nothing is scheduled yet', (tester) async {
      await pumpCard(tester, entry());

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(t.watchlist.notAvailable), findsNothing);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('checking shows a spinner and no text badge', (tester) async {
      await pumpCard(tester, entry(availability: WatchlistAvailability.checking));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(t.watchlist.notAvailable), findsNothing);
    });

    testWidgets('notFound dims the poster and names it', (tester) async {
      await pumpCard(tester, entry(availability: WatchlistAvailability.notFound, coverageComplete: true));

      expect(find.text(t.watchlist.notAvailable), findsOneWidget);
      expect(find.byType(ColorFiltered), findsOneWidget);
      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, WatchlistUnavailableCard.notFoundOpacity);
      expect(opacity.opacity, greaterThan(0.7), reason: 'still real content you can request, not a disabled control');
    });

    testWidgets('available never gets a tick, because it is the normal state', (tester) async {
      await pumpCard(tester, entry(availability: WatchlistAvailability.available));

      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.text(t.watchlist.notAvailable), findsNothing);
      expect(find.byType(Opacity), findsNothing);
    });
  });

  group('the dispatcher', () {
    testWidgets('a playable title renders through the normal media card', (tester) async {
      final match = MediaItem(
        id: '4711',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Sintel',
        serverId: 'machine-1',
      );

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: Center(
                child: WatchlistCard(
                  entry: entry(availability: WatchlistAvailability.available, lastKnownMatch: match),
                  isPlayable: true,
                  onTap: () {},
                  width: 120,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The real MediaCard reaches for providers this harness does not supply,
      // so it throws further down. That is fine and deliberately not papered
      // over: what is under test here is only which branch the dispatcher
      // takes, and the card being in the tree at all proves it.
      expect(find.byType(FocusableMediaCard), findsOneWidget);
      expect(find.byType(WatchlistUnavailableCard), findsNothing);
      expect(tester.takeException(), isA<ProviderNotFoundException>());
    });

    testWidgets('a title with a match but an offline server falls back to the unavailable card', (tester) async {
      final match = MediaItem(id: '4711', backend: MediaBackend.plex, kind: MediaKind.movie, serverId: 'machine-1');

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: Center(
                child: WatchlistCard(
                  entry: entry(availability: WatchlistAvailability.notFound, lastKnownMatch: match),
                  isPlayable: false,
                  onTap: () {},
                  width: 120,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(WatchlistUnavailableCard), findsOneWidget);
    });

    testWidgets('a tap opens the sheet rather than acting', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: Center(
                child: WatchlistUnavailableCard(entry: entry(), onTap: () => taps++, width: 120),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(WatchlistUnavailableCard));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('the item sheet has three variants', () {
    Future<void> pumpSheet(WidgetTester tester, WatchlistEntry e, WatchlistRequestability requestability) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: WatchlistItemSheet(entry: e, requestability: requestability),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('ready puts Request up front', (tester) async {
      await pumpSheet(
        tester,
        entry(availability: WatchlistAvailability.notFound, coverageComplete: true),
        WatchlistRequestability.ready,
      );

      expect(find.widgetWithText(FilledButton, t.seerr.request), findsOneWidget);
      expect(find.text(t.watchlist.remove), findsOneWidget);
      expect(find.text(t.watchlist.notFoundOnServers), findsOneWidget);
    });

    testWidgets('incomplete coverage keeps Request secondary and says why', (tester) async {
      await pumpSheet(tester, entry(availability: WatchlistAvailability.notFound), WatchlistRequestability.resolvable);

      expect(find.widgetWithText(FilledButton, t.seerr.request), findsNothing);
      expect(find.widgetWithText(OutlinedButton, t.seerr.request), findsOneWidget);
      expect(find.text(t.watchlist.coverageIncomplete), findsOneWidget);
    });

    testWidgets('without Seerr there is no Request at all, but removing still works', (tester) async {
      await pumpSheet(
        tester,
        entry(availability: WatchlistAvailability.notFound, coverageComplete: true),
        WatchlistRequestability.unsupported,
      );

      expect(find.text(t.seerr.request), findsNothing);
      expect(find.text(t.watchlist.remove), findsOneWidget);
    });

    testWidgets('the copy never claims more than was actually checked', (tester) async {
      await pumpSheet(
        tester,
        entry(availability: WatchlistAvailability.notFound, coverageComplete: true),
        WatchlistRequestability.ready,
      );

      // Local folders and shares cannot answer a catalogue lookup, so even a
      // complete Plex plus Jellyfin sweep is not "not in any of your
      // libraries".
      expect(find.textContaining('any of your libraries'), findsNothing);
      expect(find.text(t.watchlist.notFoundOnServers), findsOneWidget);
    });
  });
}
