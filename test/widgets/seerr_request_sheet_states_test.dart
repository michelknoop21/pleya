/// The request form against a scripted Seerr (Requests 2.0, families 4, 5 and
/// 6). `seerr_request_sheet_test.dart` keeps the layout contract; this file is
/// about what the form sends, and what it refuses to send twice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/models/seerr/seerr_request.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/widgets/seerr_request_sheet.dart';

import '../test_helpers/seerr_fake.dart';

const _movie = SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Charge');
const _show = SeerrMedia(tmdbId: 1399, mediaType: 'tv', title: 'Wadlopers');

Finder _node(String id, String instance) =>
    find.byWidgetPredicate((w) => w is AutomationNode && w.id == id && w.instance == instance);

Finder _button(String instance) => _node(AutomationIds.requestsFormButton, instance);
Finder _notice(String kind) => _node(AutomationIds.requestsFormNotice, kind);
Finder _option(String instance) => _node(AutomationIds.requestsFormOption, instance);

bool _enabled(WidgetTester tester, String instance) =>
    tester
        .widget<FilledButton>(find.descendant(of: _button(instance), matching: find.byType(FilledButton)))
        .onPressed !=
    null;

bool _hasFocus(WidgetTester tester, Finder within) {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) return false;
  final target = tester.element(within);
  var found = false;
  focus.visitAncestorElements((e) {
    if (e == target) found = true;
    return !found;
  });
  return found;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

SeerrRequest request({int by = 7, bool is4k = false, SeerrRequestStatus status = SeerrRequestStatus.pending}) =>
    SeerrRequest(id: 3, status: status, mediaType: 'movie', requestedById: by, is4k: is4k);

void main() {
  late FakeSeerr fake;
  late SeerrProvider provider;
  var requested = 0;

  Map<String, dynamic> tvDetail({Map<int, List<int>> statuses = const {}}) => {
    'id': 1399,
    'name': 'Wadlopers',
    'seasons': [
      for (var n = 1; n <= 5; n++) {'seasonNumber': n, 'episodeCount': 8},
    ],
    'mediaInfo': {
      'status': statuses.isEmpty ? 1 : 4,
      'seasons': [
        for (final e in statuses.entries) {'seasonNumber': e.key, 'status': e.value[0], 'status4k': e.value[1]},
      ],
    },
  };

  var openedMine = 0;

  Future<void> open(
    WidgetTester tester,
    SeerrMedia media, {
    int permissions = seerrPermRequest,
    VoidCallback? onRequested,
    bool offerMine = false,
    bool initialIs4k = false,
    List<SeerrRequest> requests = const [],
  }) async {
    // Tall enough that a five-season form is laid out whole: the list is lazy.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    provider = await seerrProvider(fake, permissions: permissions);
    addTearDown(provider.dispose);
    requested = 0;
    openedMine = 0;
    await pumpSeerr(
      tester,
      provider,
      SeerrRequestSheet(
        media: media,
        onRequested: onRequested ?? () => requested++,
        onOpenMyRequests: offerMine ? () => openedMine++ : null,
        initialIs4k: initialIs4k,
        requests: requests,
      ),
    );
    await _settle(tester);
  }

  setUp(() {
    fake = FakeSeerr()
      ..on('GET /user/7/quota', {
        'movie': {'limit': 5, 'remaining': 3},
        'tv': {'limit': 0},
      })
      ..on('GET /tv/1399', tvDetail())
      ..on('POST /request', {'id': 1});
    // A requester's 4K goes to the default 4K instance, so there is one here.
    // `seerr_request_sheet_default_4k_test.dart` covers the server without.
    for (final service in ['radarr', 'sonarr']) {
      fake.on('GET /service/$service', [
        {'id': 1, 'name': 'HD', 'is4k': false, 'isDefault': true},
        {'id': 2, 'name': '4K', 'is4k': true, 'isDefault': true},
      ]);
    }
  });

  group('film', () {
    testWidgets('a request is sent once, however often Select lands while it is on the wire', (tester) async {
      final answer = fake.hold('POST /request');
      await open(tester, _movie);

      expect(find.text(t.seerr.quotaRemaining(remaining: '3', limit: '5')), findsOneWidget);
      await tester.tap(find.text(t.seerr.requestMovie));
      await tester.pump();
      await tester.tap(find.text(t.seerr.requestMovie), warnIfMissed: false);
      await tester.pump();

      expect(fake.sent('POST', '/request'), hasLength(1));
      expect(_enabled(tester, 'submit'), isFalse);

      answer.complete(FakeSeerr.json({'id': 1}));
      await _settle(tester);
      expect(_notice('done'), findsOneWidget);
      expect(requested, 1);
    });

    testWidgets('the focus stays on the submit button while the request is on the wire', (tester) async {
      final answer = fake.hold('POST /request');
      await open(tester, _movie);
      expect(_hasFocus(tester, _button('submit')), isTrue, reason: 'the primary action opens focused');

      await tester.tap(find.text(t.seerr.requestMovie));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_hasFocus(tester, _button('submit')), isTrue, reason: 'a busy form must still hold the focus');
      answer.complete(FakeSeerr.json({'id': 1}));
      await _settle(tester);
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      expect(_hasFocus(tester, _node(AutomationIds.requestsForm, 'create')), isTrue);
    });

    testWidgets('no 4K right for films is said, not hidden, and no switch is offered', (tester) async {
      await open(tester, _movie, permissions: SeerrPermission.request | SeerrPermission.request4kTv);

      expect(find.text(t.seerr.fourKNotAllowedMovie), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('an unknown limit is called unknown and does not block the request', (tester) async {
      fake.on('GET /user/7/quota', {'message': 'boom'}, 500);
      await open(tester, _movie);

      expect(find.text(t.seerr.quotaUnknown), findsOneWidget);
      expect(find.text(t.seerr.quotaUnlimited), findsNothing);
      expect(_enabled(tester, 'submit'), isTrue);
    });

    testWidgets('a reached limit turns the request off and leaves the focus on the way out', (tester) async {
      fake.on('GET /user/7/quota', {
        'movie': {'limit': 5, 'remaining': 0},
      });
      await open(tester, _movie);

      expect(_notice('quota'), findsOneWidget);
      expect(_enabled(tester, 'submit'), isFalse);
      expect(_hasFocus(tester, _button('close')), isTrue);
    });

    testWidgets('a profile without the request right gets the reason and no form', (tester) async {
      await open(tester, _movie, permissions: 0);

      expect(find.text(t.seerr.noRequestRight), findsOneWidget);
      expect(_button('submit'), findsNothing);
      expect(fake.sent('POST', '/request'), isEmpty);
    });

    testWidgets('a title that is already requested offers no second request', (tester) async {
      await open(
        tester,
        const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'x', status: SeerrMediaStatus.pending),
      );

      expect(find.text(t.seerr.alreadyRequested), findsOneWidget);
      expect(_button('submit'), findsNothing);
    });

    testWidgets("a title that someone else requested ends on the message and Sluiten, without Mijn aanvragen", (
      tester,
    ) async {
      const pending = SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'x', status: SeerrMediaStatus.pending);
      await open(tester, pending, offerMine: true, requests: [request(by: 9)]);
      expect(find.text(t.seerr.alreadyRequested), findsOneWidget);
      expect(_button('mine'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());

      await open(tester, pending, offerMine: true, requests: [request()]);
      expect(_button('mine'), findsOneWidget, reason: 'the viewer does hold this one');
    });

    testWidgets('a caller whose confirmation callback throws does not turn a confirmed request into an open one', (
      tester,
    ) async {
      Object? formState() => tester.widget<AutomationNode>(_node(AutomationIds.requestsForm, 'create')).state!();

      await open(tester, _movie);
      await tester.tap(find.text(t.seerr.requestMovie));
      await _settle(tester);
      final confirmed = formState();
      expect(confirmed, containsPair('phase', 'done'));
      await tester.pumpWidget(const SizedBox.shrink());

      await open(tester, _movie, onRequested: () => throw StateError('caller broke'));
      await tester.tap(find.text(t.seerr.requestMovie));
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(_notice('done'), findsOneWidget);
      expect(_notice('uncertain'), findsNothing);
      expect(formState(), confirmed, reason: 'the same confirmed form, with no open outcome set beside it');
    });

    group('a film that is there in HD', () {
      const fourK = SeerrPermission.request | SeerrPermission.request4kMovie;

      testWidgets('or pending in HD keeps the way to Mijn aanvragen beside the 4K choice', (tester) async {
        await open(
          tester,
          const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'x', status: SeerrMediaStatus.pending),
          permissions: fourK,
          offerMine: true,
          requests: [request()],
        );

        expect(find.text(t.seerr.alreadyRequested), findsOneWidget);
        expect(_button('mine'), findsOneWidget, reason: 'the request that exists stays one press away');
        expect(_button('submit'), findsNothing);

        await tester.tap(find.byType(Switch));
        await _settle(tester);
        expect(_button('mine'), findsNothing);
        expect(_enabled(tester, 'submit'), isTrue);

        await tester.tap(find.byType(Switch));
        await _settle(tester);
        await tester.tap(find.text(t.seerr.myRequests));
        await _settle(tester);
        expect(openedMine, 1);
      });

      testWidgets("pending in HD on someone else's request says so, and offers no way to a list it is not in", (
        tester,
      ) async {
        await open(
          tester,
          const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'x', status: SeerrMediaStatus.pending),
          permissions: fourK,
          offerMine: true,
          requests: [request(by: 9)],
        );

        expect(find.text(t.seerr.alreadyRequested), findsOneWidget);
        expect(_button('mine'), findsNothing);
        expect(_enabled(tester, 'submit'), isFalse);
        expect(_hasFocus(tester, _button('close')), isTrue);
      });

      testWidgets("pending in HD on someone else's request is not mine because of an own request in 4K", (
        tester,
      ) async {
        await open(
          tester,
          const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'x', status: SeerrMediaStatus.pending),
          permissions: fourK,
          offerMine: true,
          requests: [
            request(by: 9),
            request(is4k: true, status: SeerrRequestStatus.declined),
          ],
        );

        expect(_button('mine'), findsNothing, reason: 'the HD request on screen is not the viewer\'s');
        expect(_enabled(tester, 'submit'), isFalse);
      });

      testWidgets('can still be asked for in 4K by a profile that holds the 4K right', (tester) async {
        await open(
          tester,
          const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'x', status: SeerrMediaStatus.available),
          permissions: fourK,
        );

        expect(find.byType(Switch), findsOneWidget, reason: 'the 4K choice is offered, not replaced by an end state');
        expect(_notice('duplicate'), findsOneWidget, reason: 'the form says why HD cannot be sent');
        expect(_enabled(tester, 'submit'), isFalse);

        await tester.tap(find.byType(Switch));
        await _settle(tester);
        expect(_notice('duplicate'), findsNothing);
        expect(_enabled(tester, 'submit'), isTrue);

        await tester.tap(find.text(t.seerr.requestMovie));
        await _settle(tester);
        expect(fake.sent('POST', '/request').single.body, containsPair('is4k', true));
        expect(_notice('done'), findsOneWidget);
      });

      testWidgets('and in 4K as well has nothing left to ask for', (tester) async {
        await open(
          tester,
          const SeerrMedia(
            tmdbId: 603,
            mediaType: 'movie',
            title: 'x',
            status: SeerrMediaStatus.available,
            status4k: SeerrMediaStatus.available,
          ),
          permissions: fourK,
        );

        expect(find.text(t.seerr.available), findsOneWidget);
        expect(_button('submit'), findsNothing);
        expect(find.byType(Switch), findsNothing);
      });

      testWidgets('with a 4K request already running offers 4K as taken, not as open', (tester) async {
        await open(
          tester,
          const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'x', status4k: SeerrMediaStatus.pending),
          permissions: fourK,
        );
        expect(_enabled(tester, 'submit'), isTrue, reason: 'HD is open');

        await tester.tap(find.byType(Switch));
        await _settle(tester);
        expect(
          find.descendant(of: _notice('duplicate'), matching: find.text(t.seerr.alreadyRequested)),
          findsOneWidget,
        );
        expect(seerrFormHint(t.seerr.alreadyRequested), findsOneWidget, reason: 'and once more beside the button');
        expect(find.text(t.seerr.alreadyRequested), findsNWidgets(2), reason: 'and nowhere else');
        expect(_enabled(tester, 'submit'), isFalse);
      });
    });

    Map<String, dynamic> ownRequest({bool is4k = false, int by = 7, int status = 1, List<int> seasons = const []}) =>
        seerrRequestJson(3, is4k: is4k, requestedBy: by, status: status, seasons: seasons)..remove('media');

    Map<String, dynamic> movieDetail({int status = 2, List<Map<String, dynamic>>? requests}) => {
      'id': 603,
      'title': 'Charge',
      'mediaInfo': {'status': status, 'requests': ?requests},
    };

    testWidgets('a lost connection is read back, and only the request itself on the server confirms it', (
      tester,
    ) async {
      fake.fail('POST /request');
      fake.on('GET /movie/603', movieDetail(requests: [ownRequest()]));
      await open(tester, _movie);
      await tester.tap(find.text(t.seerr.requestMovie));
      await _settle(tester);

      expect(_notice('uncertain'), findsOneWidget);
      expect(_button('submit'), findsNothing, reason: 'no blind retry while the outcome is unknown');
      expect(_hasFocus(tester, _node(AutomationIds.requestsForm, 'create')), isTrue);

      await tester.tap(find.text(t.seerr.checkStatus));
      await _settle(tester);

      expect(fake.sent('POST', '/request'), hasLength(1), reason: 'the server had it: nothing is sent again');
      expect(_notice('done'), findsOneWidget);
      expect(requested, 1);
    });

    testWidgets('when the server turns out not to have it, the choices are intact and sending is back', (tester) async {
      fake.fail('POST /request');
      // A title nobody requested has no mediaInfo at all.
      fake.on('GET /movie/603', {'id': 603, 'title': 'Charge'});
      await open(tester, _movie, permissions: SeerrPermission.request | SeerrPermission.request4k);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.text(t.seerr.requestMovie));
      await _settle(tester);
      await tester.tap(find.text(t.seerr.checkStatus));
      await _settle(tester);

      expect(find.text(t.seerr.requestStillAbsent), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue, reason: 'the 4K choice survived');
      expect(_enabled(tester, 'submit'), isTrue);
    });

    group('an unknown outcome is not settled by weak evidence (B04)', () {
      Future<void> sendIntoTheVoid(WidgetTester tester, SeerrMedia media, {int permissions = seerrPermRequest}) async {
        fake.fail('POST /request');
        await open(tester, media, permissions: permissions);
      }

      void expectStillLocked(WidgetTester tester) {
        expect(_notice('done'), findsNothing);
        expect(requested, 0);
        expect(_notice('uncertain'), findsOneWidget);
        expect(_button('submit'), findsNothing, reason: 'sending stays off until the outcome is proven');
        expect(fake.sent('POST', '/request'), hasLength(1));
      }

      testWidgets('an answer without a request list confirms nothing, even if the title now reads as requested', (
        tester,
      ) async {
        await sendIntoTheVoid(tester, _movie);
        fake.on('GET /movie/603', movieDetail(status: 2));
        await tester.tap(find.text(t.seerr.requestMovie));
        await _settle(tester);
        await tester.tap(find.text(t.seerr.checkStatus));
        await _settle(tester);

        expectStillLocked(tester);
        expect(find.text(t.seerr.statusNotProven), findsOneWidget);
      });

      testWidgets('an HD request on the server is not the 4K request that was sent', (tester) async {
        await sendIntoTheVoid(tester, _movie, permissions: SeerrPermission.request | SeerrPermission.request4k);
        fake.on('GET /movie/603', movieDetail(status: 2, requests: [ownRequest(is4k: false)]));
        await tester.tap(find.byType(Switch));
        await tester.pump();
        await tester.tap(find.text(t.seerr.requestMovie));
        await _settle(tester);
        await tester.tap(find.text(t.seerr.checkStatus));
        await _settle(tester);

        expect(_notice('done'), findsNothing, reason: 'no 4K request exists on the server');
        expect(requested, 0);
        expect(find.text(t.seerr.requestStillAbsent), findsOneWidget);
      });

      testWidgets("someone else's request is not the one that was sent", (tester) async {
        await sendIntoTheVoid(tester, _movie);
        fake.on('GET /movie/603', movieDetail(requests: [ownRequest(by: 9)]));
        await tester.tap(find.text(t.seerr.requestMovie));
        await _settle(tester);
        await tester.tap(find.text(t.seerr.checkStatus));
        await _settle(tester);

        expect(_notice('done'), findsNothing);
        expect(requested, 0);
      });

      testWidgets('an empty series answer does not make every chosen season count as arrived', (tester) async {
        await sendIntoTheVoid(tester, _show);
        await tester.tap(find.text(t.seerr.requestSeasons(count: 5)));
        await _settle(tester);
        fake.on('GET /tv/1399', const <String, dynamic>{});
        await tester.tap(find.text(t.seerr.checkStatus));
        await _settle(tester);

        expectStillLocked(tester);
      });

      testWidgets('a series request that holds only some of the seasons sent is not the request that was sent', (
        tester,
      ) async {
        await sendIntoTheVoid(tester, _show);
        await tester.tap(find.text(t.seerr.requestSeasons(count: 5)));
        await _settle(tester);
        fake.on('GET /tv/1399', {
          ...tvDetail(),
          'mediaInfo': {
            'status': 2,
            'seasons': const [],
            'requests': [
              ownRequest(seasons: [1, 2]),
            ],
          },
        });
        await tester.tap(find.text(t.seerr.checkStatus));
        await _settle(tester);

        expect(_notice('done'), findsNothing);
        expect(requested, 0);
      });

      testWidgets('a listed request that says neither its status nor its quality confirms nothing (F-B2)', (
        tester,
      ) async {
        await sendIntoTheVoid(tester, _movie);
        // Parsing would fill this in as "pending, HD": exactly what was sent.
        fake.on('GET /movie/603', {
          'id': 603,
          'title': 'Charge',
          'mediaInfo': {
            'status': 2,
            'requests': [
              {
                'id': 3,
                'requestedBy': {'id': 7},
              },
            ],
          },
        });
        await tester.tap(find.text(t.seerr.requestMovie));
        await _settle(tester);
        await tester.tap(find.text(t.seerr.checkStatus));
        await _settle(tester);

        expectStillLocked(tester);
        expect(find.text(t.seerr.statusNotProven), findsOneWidget);
      });

      testWidgets('an entry that cannot be read does not turn into "the request is not there" (F-B2)', (tester) async {
        await sendIntoTheVoid(tester, _movie);
        fake.on('GET /movie/603', {
          'id': 603,
          'title': 'Charge',
          'mediaInfo': {
            'status': 2,
            'requests': ['not a request'],
          },
        });
        await tester.tap(find.text(t.seerr.requestMovie));
        await _settle(tester);
        await tester.tap(find.text(t.seerr.checkStatus));
        await _settle(tester);

        expectStillLocked(tester);
        expect(find.text(t.seerr.requestStillAbsent), findsNothing);
      });

      testWidgets('a status read that fails keeps the form locked', (tester) async {
        await sendIntoTheVoid(tester, _movie);
        fake.fail('GET /movie/603');
        await tester.tap(find.text(t.seerr.requestMovie));
        await _settle(tester);
        await tester.tap(find.text(t.seerr.checkStatus));
        await _settle(tester);

        expectStillLocked(tester);
        expect(find.text(t.seerr.statusCheckFailed), findsOneWidget);
      });

      testWidgets('the choices cannot be changed while the outcome is open, so the check is about what was sent', (
        tester,
      ) async {
        await sendIntoTheVoid(tester, _show);
        await tester.tap(find.text(t.seerr.season(number: 5)));
        await tester.pump();
        await tester.tap(find.text(t.seerr.requestSeasons(count: 4)));
        await _settle(tester);

        // Try to drop season 1 after sending: the server holds 2, 3 and 4 only,
        // which would then look like "everything chosen has arrived".
        await tester.tap(find.text(t.seerr.season(number: 1)), warnIfMissed: false);
        await tester.pump();
        fake.on('GET /tv/1399', {
          ...tvDetail(),
          'mediaInfo': {
            'status': 2,
            'seasons': const [],
            'requests': [
              ownRequest(seasons: [2, 3, 4]),
            ],
          },
        });
        await tester.tap(find.text(t.seerr.checkStatus));
        await _settle(tester);

        expect(_notice('done'), findsNothing, reason: 'seasons 1 to 4 were sent, and season 1 is not on the server');
        expect(requested, 0);
      });
    });

    for (final (status, body) in [(403, 'forbidden'), (409, 'duplicate')]) {
      testWidgets('a $status is shown as the server\'s answer and is not retried', (tester) async {
        fake.on('POST /request', {'message': 'no'}, status);
        await open(tester, _movie);
        await tester.tap(find.text(t.seerr.requestMovie));
        await _settle(tester);

        expect(_notice('refused'), findsOneWidget);
        expect(
          find.text(body == 'duplicate' ? t.seerr.requestRefusedDuplicate : t.seerr.requestRefusedForbidden),
          findsOneWidget,
        );
        expect(_enabled(tester, 'submit'), isFalse);
        await tester.tap(find.text(t.seerr.requestMovie), warnIfMissed: false);
        await _settle(tester);
        expect(fake.sent('POST', '/request'), hasLength(1));
      });
    }
  });

  group('series', () {
    testWidgets('every requestable season is chosen up front and the button says what it sends', (tester) async {
      fake.on(
        'GET /tv/1399',
        tvDetail(
          statuses: {
            1: [5, 1],
            2: [2, 1],
          },
        ),
      );
      await open(tester, _show);

      expect(find.text(t.seerr.requestSeasons(count: 3)), findsOneWidget);
      expect(find.text(t.seerr.quotaUnlimited), findsOneWidget);

      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.season(number: 5)));
      await tester.pump();
      expect(find.text(t.seerr.requestSeason(number: 3)), findsOneWidget);

      await tester.tap(find.text(t.seerr.requestSeason(number: 3)));
      await _settle(tester);
      final body = fake.sent('POST', '/request').single.body as Map;
      expect(body['seasons'], [3]);
      expect(body['is4k'], isFalse);
      expect(find.textContaining(t.seerr.season(number: 3)), findsWidgets);
      expect(_notice('done'), findsOneWidget);
    });

    testWidgets('4K judges the seasons on their 4K status, not on the HD one', (tester) async {
      fake.on(
        'GET /tv/1399',
        tvDetail(
          statuses: {
            1: [5, 1],
            2: [5, 5],
            3: [5, 1],
            4: [5, 1],
            5: [5, 1],
          },
        ),
      );
      await open(tester, _show, permissions: SeerrPermission.request | SeerrPermission.request4kTv);

      await tester.tap(find.byType(Switch));
      await _settle(tester);
      expect(find.text(t.seerr.requestSeasons(count: 4)), findsOneWidget, reason: 'season 2 is there in 4K already');

      await tester.tap(find.text(t.seerr.requestSeasons(count: 4)));
      await _settle(tester);
      final body = fake.sent('POST', '/request').single.body as Map;
      expect(body['is4k'], isTrue);
      expect(body['seasons'], [1, 3, 4, 5]);
    });

    testWidgets('a failed request keeps the chosen seasons', (tester) async {
      fake.on('POST /request', {'message': 'boom'}, 500);
      await open(tester, _show);
      await tester.tap(find.text(t.seerr.season(number: 1)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.requestSeasons(count: 4)));
      await _settle(tester);

      expect(_notice('error'), findsOneWidget);
      expect(find.text(t.seerr.requestSeasons(count: 4)), findsOneWidget);
      expect(_enabled(tester, 'submit'), isTrue);
    });
  });

  group('target (admin)', () {
    setUp(() {
      fake
        ..on('GET /service/radarr', [
          {
            'id': 1,
            'name': 'Radarr HD',
            'is4k': false,
            'isDefault': true,
            'activeProfileId': 4,
            'activeDirectory': '/hd',
          },
          {
            'id': 2,
            'name': 'Radarr 4K',
            'is4k': true,
            'isDefault': true,
            'activeProfileId': 8,
            'activeDirectory': '/4k',
          },
        ])
        ..on('GET /service/radarr/1', {
          'profiles': [
            {'id': 4, 'name': 'HD-1080p'},
          ],
          'rootFolders': [
            {'path': '/hd'},
          ],
        })
        ..on('GET /service/radarr/2', {
          'profiles': [
            {'id': 8, 'name': 'Ultra-HD'},
          ],
          'rootFolders': [
            {'path': '/4k'},
          ],
        });
    });

    testWidgets('a 4K request can only be pointed at a 4K server, and takes its defaults', (tester) async {
      await open(tester, _movie, permissions: seerrPermAdmin);
      await tester.tap(find.text(t.seerr.advancedOptions));
      await tester.pump();
      expect(_option('server.1'), findsOneWidget);
      expect(_option('server.2'), findsNothing);

      await tester.tap(find.byType(Switch));
      await _settle(tester);
      expect(_option('server.1'), findsNothing, reason: 'an HD server is not a choice for a 4K request');
      expect(_option('server.2'), findsOneWidget);

      await tester.tap(find.text(t.seerr.requestMovie));
      await _settle(tester);
      final body = fake.sent('POST', '/request').single.body as Map;
      expect(body, containsPair('is4k', true));
      expect(body, containsPair('serverId', 2));
      expect(body, containsPair('profileId', 8));
      expect(body, containsPair('rootFolder', '/4k'));
    });

    testWidgets('while the options of a new server load, nothing can be sent', (tester) async {
      final detail = fake.hold('GET /service/radarr/2');
      await open(tester, _movie, permissions: seerrPermAdmin);
      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(_enabled(tester, 'submit'), isFalse);
      detail.complete(FakeSeerr.json({'profiles': [], 'rootFolders': []}));
      await _settle(tester);
      expect(_enabled(tester, 'submit'), isTrue);
    });

    testWidgets('options that fail to load leave the request to the server default, and say so', (tester) async {
      fake.on('GET /service/radarr/1', {'message': 'boom'}, 500);
      await open(tester, _movie, permissions: seerrPermAdmin);

      expect(_notice('target'), findsOneWidget);
      await tester.tap(find.text(t.seerr.requestWithServerDefault));
      await _settle(tester);

      final body = fake.sent('POST', '/request').single.body as Map;
      expect(body.containsKey('serverId'), isFalse);
      expect(body.containsKey('profileId'), isFalse);
      expect(body.containsKey('rootFolder'), isFalse);
    });

    testWidgets('4K without a 4K server cannot be sent, and HD is the way out', (tester) async {
      fake.on('GET /service/radarr', [
        {'id': 1, 'name': 'Radarr HD', 'is4k': false, 'isDefault': true},
      ]);
      await open(tester, _movie, permissions: seerrPermAdmin);
      await tester.tap(find.byType(Switch));
      await _settle(tester);

      expect(find.text(t.seerr.no4kServerTitle), findsOneWidget);
      expect(_enabled(tester, 'submit'), isFalse);

      await tester.tap(find.byType(Switch));
      await _settle(tester);
      expect(_enabled(tester, 'submit'), isTrue);
    });

    testWidgets('a requester never sees the target section', (tester) async {
      await open(tester, _movie);
      expect(find.text(t.seerr.advancedOptions), findsNothing);
      expect(fake.sent('GET', '/service/radarr'), hasLength(1), reason: 'read once, to know where HD would go');
      expect(fake.sent('GET', '/service/radarr/1'), isEmpty, reason: 'and nothing is bound');
    });
  });

  testWidgets('a series form opened on 4K judges the seasons on their 4K status from the start', (tester) async {
    // Season 1 is there in HD and open in 4K; season 2 is taken in both.
    fake.on(
      'GET /tv/1399',
      tvDetail(
        statuses: {
          1: [5, 1],
          2: [5, 5],
        },
      ),
    );
    await open(tester, _show, permissions: SeerrPermission.request | SeerrPermission.request4kTv, initialIs4k: true);

    final form = tester.widget<AutomationNode>(_node(AutomationIds.requestsForm, 'create')).state!() as Map;
    expect(form['is4k'], isTrue);
    expect(form['seasons'], [1, 3, 4, 5], reason: 'season 1 is open in 4K, season 2 is not');
  });

  testWidgets('a form asked to open on 4K stays on HD for a profile without the 4K right', (tester) async {
    await open(tester, _movie, initialIs4k: true);
    final form = tester.widget<AutomationNode>(_node(AutomationIds.requestsForm, 'create')).state!() as Map;
    expect(form['is4k'], isFalse);
  });

  testWidgets('a season that is there in HD, with no 4K status at all, can still be asked for in 4K (B02)', (
    tester,
  ) async {
    fake.on('GET /tv/1399', {
      'id': 1399,
      'name': 'Wadlopers',
      'seasons': [
        for (var n = 1; n <= 2; n++) {'seasonNumber': n, 'episodeCount': 8},
      ],
      'mediaInfo': {
        'status': 5,
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
          {'seasonNumber': 2, 'status': 5},
        ],
      },
    });
    await open(tester, _show, permissions: SeerrPermission.request | SeerrPermission.request4kTv);
    await tester.tap(find.byType(Switch));
    await _settle(tester);

    expect(find.text(t.seerr.requestSeasons(count: 2)), findsOneWidget, reason: 'HD availability locks nothing in 4K');
    await tester.tap(find.text(t.seerr.requestSeasons(count: 2)));
    await _settle(tester);
    final body = fake.sent('POST', '/request').single.body as Map;
    expect(body['is4k'], isTrue);
    expect(body['seasons'], [1, 2]);
  });

  testWidgets('a request that completes after a profile switch confirms nothing for the new account (B07)', (
    tester,
  ) async {
    final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9);
    final answer = fake.hold('POST /request');
    provider = await seerrProvider(fake, store: store);
    addTearDown(provider.dispose);
    requested = 0;
    bool? result;
    var closed = false;
    await pumpSeerr(
      tester,
      provider,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await SeerrRequestSheet.show(context, media: _movie, onRequested: () => requested++);
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.seerr.requestMovie));
    await tester.pump();

    await provider.onActiveProfileChanged('user-2');
    await tester.pump();
    answer.complete(FakeSeerr.json({'id': 1}));
    await _settle(tester);
    await tester.pumpAndSettle();

    expect(requested, 0, reason: "the old account's request must not reload the new account's page");
    expect(closed, isTrue, reason: 'the form belongs to the previous account and goes away');
    expect(result, isNull);
  });

  testWidgets('a profile switch while the form is open sends nothing for the old account', (tester) async {
    final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9);
    provider = await seerrProvider(fake, store: store);
    addTearDown(provider.dispose);
    await pumpSeerr(tester, provider, const SeerrRequestSheet(media: _movie));
    await _settle(tester);

    await provider.onActiveProfileChanged('user-2');
    await tester.pump();
    await tester.tap(find.text(t.seerr.requestMovie), warnIfMissed: false);
    await _settle(tester);

    expect(fake.sent('POST', '/request'), isEmpty);
  });
}
