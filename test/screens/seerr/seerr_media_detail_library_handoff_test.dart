/// Requests 2.0, 3E: a title Seerr calls available, matched by TMDB id to an
/// item on one of the profile's own servers, opens that item's library detail.
///
/// On TV the library detail is a content route inside the shell, while the
/// Seerr title page is a route on the profile navigator drawn over the shell.
/// The handoff has to end with the detail visible, not opened underneath the
/// page the viewer is looking at.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_identity.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/screens/seerr/seerr_media_detail_screen.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/watchlist/watchlist_availability_resolver.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../../services/fake_favorites_client.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

/// A server client that answers the one call the identity pipeline makes, and
/// records what it was asked, so the test can hold the lookup to an id-only
/// match. Same pattern as `watchlist_availability_resolver_test.dart`.
class _MatchingClient extends FakeFavoritesClient {
  _MatchingClient(this.match) : super(favorites: const []);

  final MediaItem? match;
  final asked = <MediaIdentity>[];

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async {
    asked.add(identity);
    return match == null ? const [] : [match!];
  }
}

class _Watchlist extends Fake implements WatchlistProvider {
  _Watchlist(this.resolver);

  @override
  WatchlistAvailabilityResolver? resolver;
}

Finder _action(String id) => seerrNode(AutomationIds.requestsDetailAction, id);

void main() {
  late FakeSeerr fake;
  late SeerrProvider provider;
  final pushed = <TvNestedRoute>[];
  Future<Object?> shellPush(TvNestedRoute route) async {
    pushed.add(route);
    return null;
  }

  final match = MediaItem(
    id: 'plex-603',
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Charge',
    serverId: 'server-1',
  );

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(() => db.close());
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    Provider.debugCheckInvalidValueType = null;
    TvDetectionService.debugSetAppleTVOverride(true);
    pushed.clear();
    fake = FakeSeerr()
      ..on('GET /movie/603', {
        'id': 603,
        'title': 'Charge',
        'mediaInfo': {'status': 5},
      })
      ..on('GET /movie/603/recommendations', {'results': []});
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    tvContentRouteRegistry.detach(shellPush);
  });

  /// A stand-in for the shell page, with the Seerr title page pushed over it on
  /// the same navigator the app pushes it on. The match comes out of the real
  /// resolver, asked through a Plex server record of this profile.
  Future<_MatchingClient> openOverShell(WidgetTester tester, {bool matched = true}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    provider = await seerrProvider(fake);
    addTearDown(provider.dispose);
    final client = _MatchingClient(matched ? match : null);
    final resolver = WatchlistAvailabilityResolver(
      profileId: 'profile-1',
      serversFor: () => [(serverId: ServerId('server-1'), backend: MediaBackend.plex, client: client, online: true)],
      cache: PlexApiCache.instance,
    );
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<SeerrProvider>.value(value: provider),
            Provider<WatchlistProvider?>.value(value: _Watchlist(resolver)),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SeerrMediaDetailScreen(
                          media: const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Charge'),
                          // The app's own detail page needs the whole profile
                          // session to mount. What this test is about is where
                          // the route goes and what it is for, so the page is a
                          // marker that names the item it was opened with.
                          libraryDetailRoute: (item) => MaterialPageRoute<bool>(
                            builder: (_) => Scaffold(body: Text('library detail ${item.serverId}/${item.id}')),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('shell page'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('shell page'));
    // The lookup goes through the answer cache, which is real I/O.
    // so real time and frames have to alternate until it has answered.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    }
    await tester.pumpAndSettle();
    return client;
  }

  testWidgets('the match is asked for by TMDB id and kind only, never by title', (tester) async {
    final client = await openOverShell(tester);

    final identity = client.asked.single;
    expect(identity.externalIds.tmdb, 603);
    expect(identity.kind, MediaKind.movie);
    expect(identity.title, isNull, reason: 'a title would let a lookalike count as a match');
    expect(identity.guid, isNull);
  });

  testWidgets('a proven match makes the library detail the primary action, and no play action exists', (tester) async {
    await openOverShell(tester);

    expect(find.text(t.seerr.openInLibrary), findsOneWidget);
    expect(seerrHasFocus(tester, _action('library')), isTrue);
    expect(_action('search'), findsNothing, reason: 'the search route is for a title that was not matched');
    expect(_action('request'), findsNothing);
  });

  testWidgets('on TV the matched detail is what is on screen, for the item the resolver found', (tester) async {
    tvContentRouteRegistry.attach(shellPush);
    await openOverShell(tester);

    await tester.tap(find.text(t.seerr.openInLibrary));
    await tester.pumpAndSettle();

    expect(
      find.text('library detail server-1/plex-603'),
      findsOneWidget,
      reason: 'the detail of the matched server item is the visible route',
    );
    expect(pushed, isEmpty, reason: 'sent through the shell it would open underneath the page that covers the shell');
    expect(find.text(t.seerr.openInLibrary), findsNothing, reason: 'the Seerr page is under it, not over it');
  });

  testWidgets('Back from the library detail returns to the Seerr title, on the action that opened it', (tester) async {
    tvContentRouteRegistry.attach(shellPush);
    await openOverShell(tester);
    await tester.tap(find.text(t.seerr.openInLibrary));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('library detail server-1/plex-603'))).pop();
    await tester.pumpAndSettle();

    expect(find.byType(SeerrMediaDetailScreen), findsOneWidget, reason: 'the title the viewer came from is kept');
    expect(find.text('shell page'), findsNothing);
    expect(seerrHasFocus(tester, _action('library')), isTrue);
  });

  testWidgets('without a match the title page offers no library detail', (tester) async {
    tvContentRouteRegistry.attach(shellPush);
    await openOverShell(tester, matched: false);

    expect(_action('library'), findsNothing);
    expect(pushed, isEmpty);
  });
}
