/// What a Seerr title page offers per status (Requests 2.0, family 3). The
/// rule under test is that the page never offers more than it knows: a status
/// it could not refresh is not acted on, and "available" is not a play button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/screens/seerr/seerr_media_detail_screen.dart';
import 'package:pleya/screens/seerr/seerr_requests_screen.dart';
import 'package:pleya/services/companion_remote/companion_remote_receiver.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

Finder _action(String id) => seerrNode(AutomationIds.requestsDetailAction, id);

void main() {
  late FakeSeerr fake;
  late SeerrProvider provider;
  final reported = <SeerrMediaStatus>[];

  Map<String, dynamic> movie(int status, {List<Map<String, dynamic>> requests = const []}) => {
    'id': 603,
    'title': 'Charge',
    'mediaInfo': {'status': status, 'requests': requests},
  };

  Map<String, dynamic> ownRequest({int status = 1, int by = 7}) =>
      seerrRequestJson(3, status: status, requestedBy: by)..remove('media');

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    reported.clear();
    CompanionRemoteReceiver.instance.onSearchAction = null;
    fake = FakeSeerr()..on('GET /movie/603/recommendations', {'results': []});
  });

  Future<void> open(
    WidgetTester tester,
    Map<String, dynamic> detail, {
    SeerrMediaStatus cardStatus = SeerrMediaStatus.unknown,
    String mediaType = 'movie',
    int permissions = seerrPermRequest,
  }) async {
    fake.on('GET /$mediaType/603', detail);
    fake.on('GET /$mediaType/603/recommendations', {'results': []});
    provider = await seerrProvider(fake, permissions: permissions);
    addTearDown(provider.dispose);
    await pumpSeerr(
      tester,
      provider,
      SeerrMediaDetailScreen(
        media: SeerrMedia(tmdbId: 603, mediaType: mediaType, title: 'Charge', status: cardStatus),
        onStatusChanged: reported.add,
      ),
      host: false,
    );
    await seerrSettle(tester);
  }

  testWidgets('a title nobody asked for offers Aanvragen', (tester) async {
    await open(tester, movie(1));

    expect(_action('request'), findsOneWidget);
    expect(seerrHasFocus(tester, _action('request')), isTrue);
    expect(reported, isEmpty, reason: 'the status is what the card already said');
  });

  testWidgets('a pending title opens the viewer\'s own request instead of a dead button', (tester) async {
    await open(tester, movie(2, requests: [ownRequest()]));

    expect(_action('request'), findsNothing);
    expect(find.text(t.seerr.myRequest), findsOneWidget);
    expect(seerrHasFocus(tester, _action('mine')), isTrue);
    expect(reported, [SeerrMediaStatus.pending], reason: 'the card it was opened from has to follow');
  });

  testWidgets('Mijn aanvraag opens the own list on the request for this title, not on the list in general', (
    tester,
  ) async {
    fake
      ..on('GET /request', seerrPage([seerrRequestJson(3)]))
      ..on('GET /request/count', const {});
    // Two own requests for the title: an older declined one and the pending one.
    final declined = ownRequest(status: 3)..['id'] = 2;
    await open(tester, movie(2, requests: [declined, ownRequest()]));

    await tester.tap(find.text(t.seerr.myRequest));
    await seerrSettle(tester);
    await tester.pumpAndSettle();

    final list = tester.widget<SeerrRequestsScreen>(find.byType(SeerrRequestsScreen));
    expect(list.mineOnly, isTrue);
    expect(list.focusRequestId, 3, reason: 'the pending request of this viewer for this title');
  });

  testWidgets("someone else's pending request is not called mine", (tester) async {
    await open(tester, movie(2, requests: [ownRequest(by: 9)]));

    expect(_action('mine'), findsNothing);
    expect(_action('refresh'), findsOneWidget);
  });

  testWidgets('a title being processed offers a refresh and no request', (tester) async {
    await open(tester, movie(3));

    expect(_action('request'), findsNothing);
    expect(seerrHasFocus(tester, _action('refresh')), isTrue);
  });

  testWidgets('a partly available series offers more seasons', (tester) async {
    await open(tester, {
      'id': 603,
      'name': 'Wadlopers',
      'mediaInfo': {'status': 4},
    }, mediaType: 'tv');

    expect(find.text(t.seerr.requestMoreSeasons), findsOneWidget);
  });

  testWidgets('an available title never offers playback, and without a proven match it searches by title', (
    tester,
  ) async {
    String? searched;
    CompanionRemoteReceiver.instance.onSearchAction = (query) => searched = query;
    addTearDown(() => CompanionRemoteReceiver.instance.onSearchAction = null);
    await open(tester, movie(5));

    expect(_action('library'), findsNothing, reason: 'no server item was matched by id');
    expect(_action('request'), findsNothing);
    expect(find.text(t.seerr.searchInLibrary), findsOneWidget);

    await tester.tap(find.text(t.seerr.searchInLibrary));
    await tester.pump();
    expect(searched, 'Charge');
  });

  group('a film whose HD copy is taken, for a profile with the 4K right', () {
    const fourK = SeerrPermission.request | SeerrPermission.request4kMovie;

    Map<String, dynamic> withFourK(Map<String, dynamic> detail, int status4k) =>
        detail..['mediaInfo'] = {...detail['mediaInfo'] as Map<String, dynamic>, 'status4k': status4k};

    testWidgets('that is available can be asked for in 4K, and the form opens on 4K', (tester) async {
      fake.on('POST /request', {'id': 9});
      await open(tester, movie(5), permissions: fourK);

      expect(_action('request'), findsNothing, reason: 'HD is there');
      expect(find.text(t.seerr.fourK), findsOneWidget);

      await tester.tap(_action('request4k'));
      await seerrSettle(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue, reason: 'the button said 4K');

      await tester.tap(find.text(t.seerr.requestMovie));
      await seerrSettle(tester);
      expect(fake.sent('POST', '/request').single.body, containsPair('is4k', true));
    });

    testWidgets('that is pending keeps Mijn aanvraag and adds the 4K request', (tester) async {
      await open(tester, movie(2, requests: [ownRequest()]), permissions: fourK);

      expect(seerrHasFocus(tester, _action('mine')), isTrue, reason: 'the own request stays the first action');
      expect(_action('request4k'), findsOneWidget);
    });

    testWidgets('that is being processed adds the 4K request', (tester) async {
      await open(tester, movie(3), permissions: fourK);
      expect(_action('request4k'), findsOneWidget);
    });

    for (final taken in [2, 3, 5]) {
      testWidgets('offers no 4K request when the 4K status is $taken', (tester) async {
        await open(tester, withFourK(movie(5), taken), permissions: fourK);
        expect(_action('request4k'), findsNothing);
      });
    }

    testWidgets('a profile without the 4K right sees what it saw before', (tester) async {
      await open(tester, movie(5));
      expect(_action('request4k'), findsNothing);
      expect(_action('request'), findsNothing);
    });

    testWidgets('a status that could not be refreshed offers no 4K request either', (tester) async {
      await open(tester, movie(5), permissions: fourK);
      fake.on('GET /movie/603', {'message': 'boom'}, 500);
      await tester.tap(find.text(t.seerr.refreshStatus));
      await seerrSettle(tester);
      expect(_action('request4k'), findsNothing);
    });
  });

  testWidgets('a declined own request is said, and asking again stays possible', (tester) async {
    await open(tester, movie(1, requests: [ownRequest(status: 3)]));

    expect(find.text(t.seerr.requestDeclinedNote), findsOneWidget);
    expect(_action('request'), findsOneWidget);
  });

  testWidgets('a status that could not be refreshed is neither requestable nor available', (tester) async {
    CompanionRemoteReceiver.instance.onSearchAction = (_) {};
    addTearDown(() => CompanionRemoteReceiver.instance.onSearchAction = null);
    await open(tester, movie(5));
    expect(_action('search'), findsOneWidget, reason: 'a fresh "available" does offer the library route');

    fake.on('GET /movie/603', {'message': 'boom'}, 500);
    await tester.tap(find.text(t.seerr.refreshStatus));
    await seerrSettle(tester);

    expect(find.text(t.seerr.statusNotRefreshed), findsOneWidget);
    expect(_action('request'), findsNothing);
    expect(_action('library'), findsNothing);
    expect(_action('search'), findsNothing);
    expect(seerrHasFocus(tester, _action('refresh')), isTrue, reason: 'the focus stays on the one action left');

    fake.on('GET /movie/603', movie(2, requests: [ownRequest()]));
    await tester.tap(find.text(t.seerr.refreshStatus));
    await seerrSettle(tester);
    expect(find.text(t.seerr.statusNotRefreshed), findsNothing);
    expect(_action('mine'), findsOneWidget);
  });

  testWidgets('while the first answer is on its way the page still holds the focus', (tester) async {
    final answer = fake.hold('GET /movie/603');
    provider = await seerrProvider(fake);
    addTearDown(provider.dispose);
    await pumpSeerr(
      tester,
      provider,
      const SeerrMediaDetailScreen(
        media: SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Charge'),
      ),
      host: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(seerrHasFocus(tester, _action('loading')), isTrue);
    expect(_action('request'), findsNothing, reason: 'nothing is offered on a status that is not known yet');

    answer.complete(FakeSeerr.json(movie(1)));
    await seerrSettle(tester);
    expect(seerrHasFocus(tester, _action('request')), isTrue, reason: 'the real action inherits the focus');
  });

  testWidgets('an answer for another account is dropped, and the page asks again for the new one', (tester) async {
    final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9);
    final slow = fake.hold('GET /movie/603');
    provider = await seerrProvider(fake, store: store);
    addTearDown(provider.dispose);
    await pumpSeerr(
      tester,
      provider,
      SeerrMediaDetailScreen(
        media: const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Charge'),
        onStatusChanged: reported.add,
      ),
      host: false,
    );
    await tester.pump();

    fake.on('GET /movie/603', movie(1));
    await provider.onActiveProfileChanged('user-2');
    await seerrSettle(tester);
    slow.complete(FakeSeerr.json(movie(2, requests: [ownRequest()])));
    await seerrSettle(tester);

    expect(reported, isEmpty);
    expect(_action('mine'), findsNothing);
    expect(_action('request'), findsOneWidget, reason: 'the new account sees its own answer');
  });

  group('after a profile switch (B07)', () {
    Future<MemorySeerrStore> openAsA(WidgetTester tester) async {
      final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9);
      fake.on('GET /movie/603', movie(1));
      provider = await seerrProvider(fake, store: store);
      addTearDown(provider.dispose);
      return store;
    }

    Future<void> pumpDetail(WidgetTester tester) => pumpSeerr(
      tester,
      provider,
      SeerrMediaDetailScreen(
        media: const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Charge'),
        onStatusChanged: reported.add,
      ),
      host: false,
    );

    testWidgets("the previous account's recommendations do not land on the new account's page", (tester) async {
      await openAsA(tester);
      final slow = fake.hold('GET /movie/603/recommendations');
      await pumpDetail(tester);
      await seerrSettle(tester);

      fake.on('GET /movie/603/recommendations', {'results': []});
      await provider.onActiveProfileChanged('user-2');
      await seerrSettle(tester);
      slow.complete(
        FakeSeerr.json({
          'page': 1,
          'totalPages': 1,
          'results': [
            {'id': 901, 'mediaType': 'movie', 'title': 'From account A'},
          ],
        }),
      );
      await seerrSettle(tester);

      expect(find.text('From account A'), findsNothing);
      expect(find.text(t.seerr.recommendations), findsNothing);
    });

    testWidgets("what the new account's server says is not written back to the old account's card", (tester) async {
      await openAsA(tester);
      await pumpDetail(tester);
      await seerrSettle(tester);
      expect(reported, isEmpty);

      // B's server has this title pending. The card that opened this page is
      // in A's list.
      fake.on('GET /movie/603', movie(2, requests: [ownRequest(by: 9)]));
      await provider.onActiveProfileChanged('user-2');
      await seerrSettle(tester);

      expect(_action('mine'), findsOneWidget, reason: 'the page itself does show the new account its own answer');
      expect(reported, isEmpty);
    });
  });
}
