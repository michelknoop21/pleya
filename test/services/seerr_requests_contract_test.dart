/// The Seerr request contract as `server/routes/request.ts` reads it (develop
/// at 53e45647). Source proof only: none of this says what an installed server
/// version does.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/models/seerr/seerr_request.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_request_rights.dart';

import '../test_helpers/seerr_fake.dart';

void main() {
  late FakeSeerr fake;
  late SeerrClient client;

  setUp(() {
    fake = FakeSeerr();
    client = SeerrClient(seerrSession(), httpClient: fake.client);
  });

  SeerrRequest parsed(Map<String, dynamic> json) => SeerrRequest.tryFromJson({
    'serverId': null,
    'profileId': null,
    'rootFolder': null,
    'tags': null,
    'languageProfileId': null,
    ...json,
  })!;

  group('PUT /request/{id}', () {
    test('a series edit names its type and passes the stored target back', () async {
      fake.on('PUT /request/12', {'id': 12});
      final current = parsed(
        seerrRequestJson(
          12,
          type: 'tv',
          seasons: [3, 4, 5],
          serverId: 2,
          profileId: 6,
          rootFolder: '/media/series',
          languageProfileId: 1,
          tags: [9],
        ),
      );

      final saved = await client.updateRequest(current, seasons: [5, 3]);

      expect(saved, isTrue);
      expect(fake.sent('PUT', '/request/12').single.body, {
        'mediaType': 'tv',
        'serverId': 2,
        'profileId': 6,
        'rootFolder': '/media/series',
        'tags': [9],
        'languageProfileId': 1,
        'seasons': [3, 5],
      });
    });

    test('nothing in the body can move the request or claim a quality change', () async {
      fake.on('PUT /request/12', {'id': 12});
      await client.updateRequest(
        parsed(seerrRequestJson(12, type: 'tv', seasons: [1], is4k: true)),
        seasons: [1],
      );

      final body = fake.sent('PUT', '/request/12').single.body as Map;
      expect(body.containsKey('userId'), isFalse);
      expect(body.containsKey('is4k'), isFalse);
    });

    test('a film edit sends no seasons, and a new target replaces all three fields together', () async {
      fake.on('PUT /request/4', {'id': 4});
      final current = parsed(seerrRequestJson(4, serverId: 1, profileId: 6, rootFolder: '/media/films'));

      await client.updateRequest(current, target: (serverId: 3, profileId: null, rootFolder: null));

      expect(fake.sent('PUT', '/request/4').single.body, {'mediaType': 'movie', 'serverId': 3});
    });

    test('a 202 is an accepted call that saved nothing', () async {
      fake.on('PUT /request/12', {'message': 'No seasons available to request'}, 202);
      final saved = await client.updateRequest(
        parsed(seerrRequestJson(12, type: 'tv', seasons: [1])),
        seasons: [2],
      );
      expect(saved, isFalse);
    });

    test('a refusal and a lost connection are different answers', () async {
      final current = parsed(seerrRequestJson(12, type: 'tv', seasons: [1]));

      fake.on('PUT /request/12', {'message': 'no'}, 403);
      await expectLater(
        client.updateRequest(current),
        throwsA(isA<SeerrException>().having((e) => e.outcomeUnknown, 'outcomeUnknown', isFalse)),
      );

      fake.on('PUT /request/12', {'message': 'Only pending requests can be modified.'}, 409);
      await expectLater(
        client.updateRequest(current),
        throwsA(isA<SeerrException>().having((e) => e.isConflict, 'isConflict', isTrue)),
      );

      fake.fail('PUT /request/12');
      await expectLater(
        client.updateRequest(current),
        throwsA(isA<SeerrException>().having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)),
      );
    });
  });

  group('R4 client trust boundary', () {
    for (final (name, payload) in <(String, Object)>[
      ('missing pages', {'results': <Object>[], 'pageInfo': {}}),
      for (final id in [-1, 0])
        (
          'nonpositive request id $id',
          {
            'results': [seerrRequestJson(id)],
            'pageInfo': {'pages': 1},
          },
        ),
      (
        'fractional pages',
        {
          'results': <Object>[],
          'pageInfo': {'pages': 1.5},
        },
      ),
      (
        'negative pages',
        {
          'results': <Object>[],
          'pageInfo': {'pages': -1},
        },
      ),
      (
        'zero pages with rows',
        {
          'results': [seerrRequestJson(1)],
          'pageInfo': {'pages': 0},
        },
      ),
      (
        'missing results',
        {
          'pageInfo': {'pages': 1},
        },
      ),
      (
        'unreadable row',
        {
          'results': ['unreadable'],
          'pageInfo': {'pages': 1},
        },
      ),
      (
        'missing request id',
        {
          'results': [<String, dynamic>{}],
          'pageInfo': {'pages': 1},
        },
      ),
      (
        'duplicate id',
        {
          'results': [seerrRequestJson(1), seerrRequestJson(1)],
          'pageInfo': {'pages': 1},
        },
      ),
    ]) {
      test('R4 rejects $name as list proof', () async {
        fake.on('GET /request', payload);
        await expectLater(client.getRequests(), throwsA(isA<SeerrException>()));
      });
    }
    test('R4 accepts explicitly empty zero-page and one-page lists', () async {
      for (final pages in [0, 1]) {
        fake.on('GET /request', {
          'results': <Object>[],
          'pageInfo': {'pages': pages},
        });
        final result = await client.getRequests();
        expect(result.items, isEmpty);
        expect(result.totalPages, pages);
      }
    });
    test('R4 refuses to PUT malformed stored advanced values', () async {
      fake.on('PUT /request/12', {'id': 12});
      final raw = seerrRequestJson(
        12,
        type: 'tv',
        seasons: [1],
        serverId: 2,
        profileId: 6,
        rootFolder: '/media/series',
        languageProfileId: 1,
        tags: [9],
      );
      for (final entry in <String, Object>{
        'serverId': 'bad',
        'tags': [9, 'bad'],
        'languageProfileId': 1.5,
      }.entries) {
        final request = SeerrRequest.tryFromJson({...raw, entry.key: entry.value})!;
        await expectLater(client.updateRequest(request), throwsA(isA<SeerrException>()));
      }
      expect(fake.sent('PUT', '/request/12'), isEmpty);
    });
  });

  group('GET /request/{id}', () {
    test('reads the target fields an edit has to pass back', () async {
      fake.on('GET /request/12', seerrRequestJson(12, serverId: 2, profileId: 6, rootFolder: '/m', tags: [1, 2]));
      final request = await client.getRequest(12);

      expect(request!.serverId, 2);
      expect(request.profileId, 6);
      expect(request.rootFolder, '/m');
      expect(request.tags, [1, 2]);
    });

    test('a payload without them leaves them unknown, and hydration keeps what was there', () {
      final bare = parsed(seerrRequestJson(1));
      expect(bare.serverId, isNull);
      expect(bare.tags, isNull);

      final hydrated = parsed(seerrRequestJson(1, serverId: 2, tags: [4])).withDisplayData(title: 'x');
      expect(hydrated.serverId, 2);
      expect(hydrated.tags, [4]);
    });
  });

  group('GET /request/count', () {
    test('a failed count is no count, not zeros', () async {
      fake.on('GET /request/count', {'message': 'boom'}, 500);
      expect(await client.getRequestCounts(), isNull);
    });

    test('a field the payload lacks is unknown, not zero', () async {
      fake.on('GET /request/count', {'total': 12, 'pending': 0});
      final counts = await client.getRequestCounts();

      expect(counts!.total, 12);
      expect(counts.pending, 0);
      expect(counts.approved, isNull);
    });
  });

  group('season availability per quality', () {
    final seasons = SeerrSeason.listFromDetail({
      'seasons': [
        {'seasonNumber': 1},
        {'seasonNumber': 2},
        {'seasonNumber': 3},
      ],
      'mediaInfo': {
        'seasons': [
          {'seasonNumber': 1, 'status': 5, 'status4k': 1},
          {'seasonNumber': 2, 'status': 5},
          {'seasonNumber': 3, 'status': 5, 'status4k': 2},
        ],
      },
    });

    test('a season available in HD can still be asked for in 4K', () {
      expect(seasons[0].statusFor(is4k: false), SeerrMediaStatus.available);
      expect(seasons[0].requestableIn(is4k: false), isFalse);
      expect(seasons[0].requestableIn(is4k: true), isTrue);
    });

    test('a missing 4K status is unknown, never the HD status (B02)', () {
      // Season 2 is there in HD and the payload says nothing about 4K.
      expect(seasons[1].status4k, isNull);
      expect(seasons[1].statusFor(is4k: true), isNull, reason: 'HD availability is not evidence about 4K');
      expect(seasons[1].requestableIn(is4k: true), isTrue, reason: 'nothing says it is taken; the server decides');
    });

    test('a 4K status that says it is taken takes it away', () {
      expect(seasons[2].requestableIn(is4k: true), isFalse);
    });
  });

  group('what a title payload proves about its requests', () {
    SeerrMediaDetail detail(Map<String, dynamic> json) => SeerrMediaDetail.fromJson(json, mediaType: 'movie');

    test('no mediaInfo on a real title is a known "never requested"', () {
      expect(detail({'id': 5, 'title': 'x'}).requestsKnown, isTrue);
    });

    test('a request list, empty or not, is known', () {
      expect(
        detail({
          'id': 5,
          'mediaInfo': {'status': 2, 'requests': []},
        }).requestsKnown,
        isTrue,
      );
    });

    test('an empty body, or mediaInfo without a request list, proves nothing', () {
      expect(detail(const {}).requestsKnown, isFalse);
      expect(
        detail({
          'id': 5,
          'mediaInfo': {'status': 2},
        }).requestsKnown,
        isFalse,
      );
    });
  });

  test('a body that cannot be read leaves the outcome of a write unknown, whatever the status code (B03)', () async {
    fake.routes['PUT /request/12'] = (_) =>
        http.Response('<html>proxy</html>', 200, headers: const {'content-type': 'application/json'});
    await expectLater(
      client.updateRequest(parsed(seerrRequestJson(12, type: 'tv', seasons: [1]))),
      throwsA(isA<SeerrException>().having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)),
    );
  });

  test('a request is fulfilled only when its media is there in the quality it asked for', () {
    Map<String, dynamic> row({required bool is4k, int status = 3, int? status4k}) {
      final json = seerrRequestJson(1, status: 2, is4k: is4k, mediaStatus: status);
      json['media'] = {...(json['media'] as Map), 'status4k': status4k};
      return json;
    }

    expect(parsed(row(is4k: false, status: 5)).isFulfilled, isTrue);
    expect(parsed(row(is4k: false, status: 3)).isFulfilled, isFalse);
    expect(parsed(row(is4k: true, status: 5)).isFulfilled, isFalse, reason: 'the HD copy is not the 4K one');
    expect(parsed(row(is4k: true, status: 5, status4k: 5)).isFulfilled, isTrue);
  });

  test('a title page carries the requests Seerr lists for it', () {
    final detail = SeerrMediaDetail.fromJson({
      'id': 5,
      'title': 'Charge',
      'mediaInfo': {
        'status': 2,
        'requests': [seerrRequestJson(3, requestedBy: 7)..remove('media')],
      },
    }, mediaType: 'movie');

    expect(detail.requests.single.requestedById, 7);
    expect(detail.requests.single.isPending, isTrue);
  });

  group('SeerrRequestRights', () {
    SeerrRequestRights rights(
      Map<String, dynamic> json, {
      int? own = 7,
      bool canManage = false,
      bool isAdmin = false,
    }) => SeerrRequestRights.of(parsed(json), ownUserId: own, canManage: canManage, isAdmin: isAdmin);

    test('a requester may change the seasons of their own pending series, and cancel it', () {
      final r = rights(seerrRequestJson(1, type: 'tv', seasons: [1]));
      expect(r.canEditSeasons, isTrue);
      expect(r.canCancel, isTrue);
      expect(r.canEditTarget, isFalse);
      expect(r.canApprove, isFalse);
    });

    test('a requester has nothing to edit on their own film', () {
      final r = rights(seerrRequestJson(1));
      expect(r.canEdit, isFalse);
      expect(r.canCancel, isTrue);
    });

    test("someone else's request offers a requester nothing", () {
      expect(rights(seerrRequestJson(1, type: 'tv', seasons: [1], requestedBy: 9)).hasAny, isFalse);
    });

    test('an unknown own user id owns nothing', () {
      expect(rights(seerrRequestJson(1, type: 'tv', seasons: [1]), own: null).hasAny, isFalse);
    });

    test('a manager decides and edits seasons, but the target stays with the admin', () {
      final manager = rights(seerrRequestJson(1, type: 'tv', seasons: [1], requestedBy: 9), canManage: true);
      expect(manager.canApprove && manager.canDecline && manager.canEditSeasons, isTrue);
      expect(manager.canEditTarget, isFalse);
      // The server would let a manager delete it. The list never offered that.
      expect(manager.canCancel, isFalse);

      final admin = rights(seerrRequestJson(1, requestedBy: 9), canManage: true, isAdmin: true);
      expect(admin.canEditTarget, isTrue);
    });

    test('nothing is on offer once a request is no longer pending', () {
      for (final status in [2, 3, 4, 5]) {
        final r = rights(seerrRequestJson(1, type: 'tv', seasons: [1], status: status), canManage: true, isAdmin: true);
        expect(r.hasAny, isFalse, reason: 'status $status');
      }
    });
  });
}
