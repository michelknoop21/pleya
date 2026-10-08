/// Editing a pending request (Requests 2.0, 8E to 8J), against a scripted
/// Seerr that follows `PUT /request/{id}` as its source reads.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_request.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/widgets/seerr_request_edit_sheet.dart';

import '../test_helpers/seerr_fake.dart';

Finder _button(String instance) => seerrNode(AutomationIds.requestsFormButton, instance);
Finder _notice(String kind) => seerrNode(AutomationIds.requestsFormNotice, kind);
Finder _form() => seerrNode(AutomationIds.requestsForm, 'edit');

bool _enabled(WidgetTester tester, String instance) =>
    tester
        .widget<FilledButton>(find.descendant(of: _button(instance), matching: find.byType(FilledButton)))
        .onPressed !=
    null;

void main() {
  late FakeSeerr fake;
  late SeerrProvider provider;

  final tvDetail = {
    'id': 1012,
    'name': 'Wadlopers',
    'seasons': [
      for (var n = 1; n <= 5; n++) {'seasonNumber': n, 'episodeCount': 8},
    ],
    'mediaInfo': {
      'status': 4,
      'seasons': [
        {'seasonNumber': 1, 'status': 5},
        {'seasonNumber': 2, 'status': 2},
        {'seasonNumber': 3, 'status': 2},
        {'seasonNumber': 5, 'status': 2},
      ],
    },
  };

  /// What the list row said when the edit was opened: an older picture.
  SeerrRequest row({String type = 'tv', List<int> seasons = const [3, 5]}) =>
      SeerrRequest.tryFromJson(seerrRequestJson(12, type: type, seasons: seasons))!;

  Map<String, dynamic> fresh({
    int status = 1,
    List<int> seasons = const [3, 5],
    int requestedBy = 7,
    String type = 'tv',
    bool is4k = false,
    int? serverId = 2,
  }) => seerrRequestJson(
    12,
    type: type,
    status: status,
    seasons: type == 'tv' ? seasons : const [],
    requestedBy: requestedBy,
    is4k: is4k,
    serverId: serverId,
    profileId: 6,
    rootFolder: '/media/series',
    languageProfileId: 1,
    tags: [9],
  );

  Future<void> open(WidgetTester tester, {int permissions = seerrPermRequest, SeerrRequest? request}) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    provider = await seerrProvider(fake, permissions: permissions);
    addTearDown(provider.dispose);
    await pumpSeerr(tester, provider, SeerrRequestEditSheet(request: request ?? row()));
    await seerrSettle(tester);
  }

  /// What the scripted server holds for request 12. `PUT` follows the route:
  /// it stores the seasons and assigns the target fields from the body,
  /// present or not. `GET` answers what is stored.
  late Map<String, dynamic> stored;

  Map<String, dynamic> applyPut(Map<String, dynamic> row, Map body) => {
    ...row,
    'serverId': body['serverId'],
    'profileId': body['profileId'],
    'rootFolder': body['rootFolder'],
    if (body['seasons'] is List)
      'seasons': [
        for (final n in body['seasons'] as List) {'seasonNumber': n, 'status': 1},
      ],
  };

  setUp(() {
    stored = fresh();
    fake = FakeSeerr()..on('GET /tv/1012', tvDetail);
    fake.routes['GET /request/12'] = (_) => FakeSeerr.json(stored);
    fake.routes['PUT /request/12'] = (request) {
      stored = applyPut(stored, jsonDecode(request.body) as Map);
      return FakeSeerr.json(stored);
    };
  });

  /// Opens the sheet the way the list does, so its result can be read.
  Future<bool? Function()> openViaShow(WidgetTester tester, {int permissions = seerrPermRequest}) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    provider = await seerrProvider(fake, permissions: permissions);
    addTearDown(provider.dispose);
    bool? result;
    await pumpSeerr(
      tester,
      provider,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await SeerrRequestEditSheet.show(context, request: row()),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await seerrSettle(tester);
    await tester.pumpAndSettle();
    return () => result;
  }

  Future<void> tickSeason(WidgetTester tester, int n) async {
    await tester.ensureVisible(find.text(t.seerr.season(number: n)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.seerr.season(number: n)));
    await tester.pump();
  }

  testWidgets('a season edit carries the target the server holds now, and nothing that moves the request', (
    tester,
  ) async {
    await open(tester);

    expect(_enabled(tester, 'submit'), isFalse, reason: 'nothing has changed yet');
    await tester.tap(find.text(t.seerr.season(number: 4)));
    await tester.pump();
    await tester.tap(find.text(t.seerr.saveChange));
    await seerrSettle(tester);

    // The row the sheet was opened from had no target at all; the body carries
    // what GET /request/12 answered.
    expect(fake.sent('PUT', '/request/12').single.body, {
      'mediaType': 'tv',
      'serverId': 2,
      'profileId': 6,
      'rootFolder': '/media/series',
      'tags': [9],
      'languageProfileId': 1,
      'seasons': [3, 4, 5],
    });
  });

  testWidgets('seasons this request holds can be dropped; seasons someone else has cannot be taken', (tester) async {
    await open(tester);

    await tester.tap(find.text(t.seerr.season(number: 2)), warnIfMissed: false);
    await tester.tap(find.text(t.seerr.season(number: 1)), warnIfMissed: false);
    await tester.tap(find.text(t.seerr.season(number: 5)));
    await tester.pump();
    await tester.tap(find.text(t.seerr.saveChange));
    await seerrSettle(tester);

    expect((fake.sent('PUT', '/request/12').single.body as Map)['seasons'], [3]);
  });

  testWidgets('an empty selection cannot be saved: that is what cancelling is for', (tester) async {
    await open(tester);
    await tester.tap(find.text(t.seerr.season(number: 3)));
    await tester.tap(find.text(t.seerr.season(number: 5)));
    await tester.pump();

    expect(find.text(t.seerr.editKeepOneSeason), findsOneWidget);
    expect(_enabled(tester, 'submit'), isFalse);
  });

  testWidgets('the quality is shown as fixed and offers no switch', (tester) async {
    fake.on('GET /request/12', fresh(is4k: true));
    await open(tester, permissions: seerrPermAdmin);

    expect(find.text(t.seerr.qualityFourK), findsOneWidget);
    expect(find.text(t.seerr.editQualityFixed), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('a request that is no longer pending cannot be edited, and nothing is sent', (tester) async {
    fake.on('GET /request/12', fresh(status: 2));
    await open(tester);

    expect(find.text(t.seerr.editNotPendingTitle), findsOneWidget);
    expect(_notice('unsupported'), findsOneWidget);
    expect(_button('submit'), findsNothing);
    expect(seerrHasFocus(tester, _button('close')), isTrue);
    expect(fake.sent('PUT', '/request/12'), isEmpty);
  });

  testWidgets("a requester's own film has nothing to edit here", (tester) async {
    fake.on('GET /request/12', fresh(type: 'movie'));
    await open(
      tester,
      request: row(type: 'movie', seasons: const []),
    );

    expect(find.text(t.seerr.editNothingToEdit), findsOneWidget);
    expect(fake.sent('PUT', '/request/12'), isEmpty);
  });

  testWidgets("someone else's request is not editable for a requester, whatever the row said", (tester) async {
    fake.on('GET /request/12', fresh(requestedBy: 9));
    await open(tester);

    expect(find.text(t.seerr.editNothingToEdit), findsOneWidget);
    expect(fake.sent('PUT', '/request/12'), isEmpty);
  });

  for (final (status, title) in [(403, 'forbidden'), (409, 'unsupported')]) {
    testWidgets('a $status on save is shown as the server\'s answer', (tester) async {
      fake.on('PUT /request/12', {'message': 'no'}, status);
      await open(tester);
      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      expect(_notice(title), findsOneWidget);
      expect(_button('submit'), findsNothing);
      expect(seerrHasFocus(tester, _form()), isTrue);
      expect(fake.sent('PUT', '/request/12'), hasLength(1));
    });
  }

  testWidgets('a save is sent once and keeps the focus while it is on the wire', (tester) async {
    final answer = fake.hold('PUT /request/12');
    await open(tester);
    await tester.tap(find.text(t.seerr.season(number: 4)));
    await tester.pump();
    await tester.tap(find.text(t.seerr.saveChange));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(t.seerr.saving), findsOneWidget);
    expect(seerrHasFocus(tester, _form()), isTrue);
    await tester.tap(find.text(t.seerr.saving), warnIfMissed: false);
    await tester.tap(find.text(t.seerr.season(number: 3)), warnIfMissed: false);
    await tester.pump();
    expect(fake.sent('PUT', '/request/12'), hasLength(1));

    answer.complete(FakeSeerr.json(fresh(seasons: [3, 4, 5])));
    await seerrSettle(tester);
  });

  group('outcome unknown', () {
    Future<void> saveIntoTheVoid(WidgetTester tester) async {
      fake.fail('PUT /request/12');
      await open(tester);
      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);
    }

    testWidgets('the choice stays and the only way forward is reading the request back', (tester) async {
      await saveIntoTheVoid(tester);

      expect(_notice('uncertain'), findsOneWidget);
      expect(_button('submit'), findsNothing);
      expect(_button('status'), findsOneWidget);
      expect(seerrHasFocus(tester, _form()), isTrue);
      expect(tester.widget<Checkbox>(find.byType(Checkbox).at(2)).value, isTrue, reason: 'season 4 is still chosen');
    });

    testWidgets('when the server still has the old seasons, saving again is offered', (tester) async {
      await saveIntoTheVoid(tester);
      await tester.tap(find.text(t.seerr.checkStatus));
      await seerrSettle(tester);

      expect(find.text(t.seerr.editStillOld), findsOneWidget);
      expect(_enabled(tester, 'submit'), isTrue);
      expect(fake.sent('PUT', '/request/12'), hasLength(1), reason: 'reading back sends nothing');
    });

    testWidgets('when the change turns out to have landed, the edit closes as saved and nothing is sent again', (
      tester,
    ) async {
      fake.fail('PUT /request/12');
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      provider = await seerrProvider(fake);
      addTearDown(provider.dispose);
      bool? result;
      await pumpSeerr(
        tester,
        provider,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await SeerrRequestEditSheet.show(context, request: row()),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await seerrSettle(tester);
      // The sheet slides in; its rows are not where a tap lands until it has.
      await tester.pumpAndSettle();
      // Off TV the host caps a sheet at 400 high, so the season list scrolls.
      await tester.ensureVisible(find.text(t.seerr.season(number: 4)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      fake.on('GET /request/12', fresh(seasons: [3, 4, 5]));
      await tester.tap(find.text(t.seerr.checkStatus));
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(fake.sent('PUT', '/request/12'), hasLength(1));
      expect(result, isTrue);
      expect(_form(), findsNothing);
    });

    testWidgets('when it was approved in the meantime, the edit ends there', (tester) async {
      await saveIntoTheVoid(tester);
      fake.on('GET /request/12', fresh(status: 2));
      await tester.tap(find.text(t.seerr.checkStatus));
      await seerrSettle(tester);

      expect(find.text(t.seerr.editNotPendingTitle), findsOneWidget);
      expect(_button('submit'), findsNothing);
    });
  });

  group('target (admin)', () {
    setUp(() {
      fake
        ..on('GET /request/12', fresh(type: 'movie', requestedBy: 9, serverId: 1))
        ..on('GET /service/radarr', [
          {
            'id': 1,
            'name': 'Radarr HD',
            'is4k': false,
            'isDefault': true,
            'activeProfileId': 4,
            'activeDirectory': '/hd',
          },
          {'id': 3, 'name': 'Radarr Kids', 'is4k': false, 'activeProfileId': 5, 'activeDirectory': '/kids'},
          {'id': 2, 'name': 'Radarr 4K', 'is4k': true, 'isDefault': true},
        ])
        ..on('GET /service/radarr/1', {
          'profiles': [
            {'id': 4, 'name': 'HD-1080p'},
            {'id': 6, 'name': 'Any'},
          ],
          'rootFolders': [
            {'path': '/hd'},
            {'path': '/media/series'},
          ],
        })
        ..on('GET /service/radarr/3', {
          'profiles': [
            {'id': 5, 'name': 'Kids'},
          ],
          'rootFolders': [
            {'path': '/kids'},
          ],
        });
    });

    testWidgets('the form opens on what the request holds, and only offers servers of its quality', (tester) async {
      await open(
        tester,
        permissions: seerrPermAdmin,
        request: row(type: 'movie', seasons: const []),
      );

      expect(seerrNode(AutomationIds.requestsFormOption, 'server.2'), findsNothing, reason: '4K server, HD request');
      expect(_enabled(tester, 'submit'), isFalse, reason: 'the stored profile 6 and folder were kept, not reset');
    });

    testWidgets('another server replaces profile and folder with that server\'s own', (tester) async {
      await open(
        tester,
        permissions: seerrPermAdmin,
        request: row(type: 'movie', seasons: const []),
      );
      await tester.tap(find.text('Radarr Kids'));
      await seerrSettle(tester);
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      expect(fake.sent('PUT', '/request/12').single.body, {
        'mediaType': 'movie',
        'serverId': 3,
        'profileId': 5,
        'rootFolder': '/kids',
        'tags': [9],
      });
    });

    testWidgets('options that fail to load never replace a stored target with nothing', (tester) async {
      fake.on('GET /service/radarr/1', {'message': 'boom'}, 500);
      await open(
        tester,
        permissions: seerrPermAdmin,
        request: row(type: 'movie', seasons: const []),
      );

      expect(_notice('target'), findsOneWidget);
      expect(_enabled(tester, 'submit'), isFalse);
      expect(fake.sent('PUT', '/request/12'), isEmpty);
    });
  });

  group('a save is only a save once the server holds it (B03)', () {
    testWidgets('a change the server stored closes the edit as saved', (tester) async {
      final result = await openViaShow(tester);
      await tickSeason(tester, 4);
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(result(), isTrue);
      expect(_form(), findsNothing);
      expect(fake.sent('GET', '/request/12'), hasLength(2), reason: 'once to open, once to prove the save');
    });

    testWidgets('a 200 that kept fewer seasons than it was sent is not reported as saved', (tester) async {
      // Upstream drops seasons another request holds and still answers 200.
      fake.routes['PUT /request/12'] = (request) => FakeSeerr.json(stored);
      final result = await openViaShow(tester);
      await tickSeason(tester, 4);
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(result(), isNull, reason: 'the server still holds seasons 3 and 5');
      expect(_form(), findsOneWidget);
      expect(find.text(t.seerr.editNotAllSaved), findsOneWidget);
      expect(_enabled(tester, 'submit'), isTrue, reason: 'the state is known, so saving again is honest');
    });

    testWidgets('a 200 with no proof to read leaves the edit locked, not saved', (tester) async {
      final result = await openViaShow(tester);
      await tickSeason(tester, 4);
      fake.fail('GET /request/12');
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(result(), isNull);
      expect(_notice('uncertain'), findsOneWidget);
      expect(_button('submit'), findsNothing);
      expect(_button('status'), findsOneWidget);
    });

    testWidgets('a 200 whose body cannot be read is an unknown outcome, not an error to retry', (tester) async {
      await open(tester);
      fake.routes['PUT /request/12'] = (_) =>
          http.Response('<html>proxy</html>', 200, headers: const {'content-type': 'application/json'});
      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      expect(_notice('uncertain'), findsOneWidget);
      expect(_button('submit'), findsNothing, reason: 'a status code is not proof that nothing was stored');
    });
  });

  group('an unknown outcome stays about what was sent (B04)', () {
    testWidgets('the selection cannot be edited back to what the server has and then pass as saved', (tester) async {
      fake.fail('PUT /request/12');
      final result = await openViaShow(tester);
      await tickSeason(tester, 4);
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);
      expect(_notice('uncertain'), findsOneWidget);

      // Seasons 3, 4 and 5 were sent. Unticking 4 now would make the form match
      // the old server state, and the old check compared the form.
      await tester.tap(find.text(t.seerr.season(number: 4)), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.text(t.seerr.checkStatus));
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(result(), isNull, reason: 'the server holds 3 and 5; 3, 4 and 5 were sent');
      expect(_form(), findsOneWidget);
      expect(find.text(t.seerr.editStillOld), findsOneWidget);
      expect(fake.sent('PUT', '/request/12'), hasLength(1));
    });

    testWidgets('a status read that fails keeps the edit locked', (tester) async {
      fake.fail('PUT /request/12');
      await open(tester);
      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);
      fake.fail('GET /request/12');
      await tester.tap(find.text(t.seerr.checkStatus));
      await seerrSettle(tester);

      expect(_notice('uncertain'), findsOneWidget);
      expect(_button('submit'), findsNothing);
      expect(find.text(t.seerr.statusCheckFailed), findsOneWidget);
    });
  });

  group('half a request is not a readback (F-B2)', () {
    Map<String, dynamic> withoutTarget(Map<String, dynamic> row) =>
        {...row}..removeWhere((key, _) => key == 'serverId' || key == 'profileId' || key == 'rootFolder');

    testWidgets('a readback without the target keys settles nothing and never replaces the stored target', (
      tester,
    ) async {
      fake.fail('PUT /request/12');
      await open(tester);
      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      // Pending, right seasons count, but nothing about where it points.
      fake.on('GET /request/12', withoutTarget(fresh()));
      await tester.tap(find.text(t.seerr.checkStatus));
      await seerrSettle(tester);
      expect(_notice('uncertain'), findsOneWidget, reason: 'an answer without the target is not the request');
      expect(_button('submit'), findsNothing);

      // The whole request arrives, unchanged: now saving again is honest, and
      // it still carries the target the server held all along.
      fake.routes['GET /request/12'] = (_) => FakeSeerr.json(stored);
      fake.routes['PUT /request/12'] = (request) {
        stored = applyPut(stored, jsonDecode(request.body) as Map);
        return FakeSeerr.json(stored);
      };
      await tester.tap(find.text(t.seerr.checkStatus));
      await seerrSettle(tester);
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      final body = fake.sent('PUT', '/request/12').last.body as Map;
      expect(body['serverId'], 2);
      expect(body['profileId'], 6);
      expect(body['rootFolder'], '/media/series');
      expect(body['tags'], [9]);
    });

    testWidgets('a request that opens without its target keys is not editable from that answer', (tester) async {
      stored = withoutTarget(fresh());
      await open(tester);

      expect(find.text(t.seerr.editLoadFailed), findsOneWidget);
      expect(find.text(t.seerr.season(number: 3)), findsNothing);
      expect(fake.sent('PUT', '/request/12'), isEmpty);
    });

    testWidgets('a readback without a status does not unlock the edit', (tester) async {
      fake.fail('PUT /request/12');
      await open(tester);
      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      fake.on('GET /request/12', fresh()..remove('status'));
      await tester.tap(find.text(t.seerr.checkStatus));
      await seerrSettle(tester);

      expect(_notice('uncertain'), findsOneWidget);
      expect(_button('submit'), findsNothing);
    });
  });

  group('R4 proof boundary', () {
    final invalidFields = <String, Object>{
      'serverId': 'unreadable',
      'profileId': 6.5,
      'rootFolder': {'path': '/wrong'},
      'tags': [9, 'unreadable'],
      'languageProfileId': 'unreadable',
    };
    for (final entry in invalidFields.entries) {
      testWidgets('R4 malformed ${entry.key} blocks initial edit', (tester) async {
        stored = {...fresh(), entry.key: entry.value};
        await open(tester);
        expect(find.text(t.seerr.editLoadFailed), findsOneWidget);
        expect(_button('submit'), findsNothing);
        expect(fake.sent('PUT', '/request/12'), isEmpty);
      });
      testWidgets('R4 malformed ${entry.key} recovery retains trustworthy fields', (tester) async {
        fake.fail('PUT /request/12');
        await open(tester);
        await tester.tap(find.text(t.seerr.season(number: 4)));
        await tester.pump();
        await tester.tap(find.text(t.seerr.saveChange));
        await seerrSettle(tester);
        fake.on('GET /request/12', {...fresh(), entry.key: entry.value});
        await tester.tap(find.text(t.seerr.checkStatus));
        await seerrSettle(tester);
        expect(_notice('uncertain'), findsOneWidget);
        expect(_button('submit'), findsNothing);
        fake.routes['GET /request/12'] = (_) => FakeSeerr.json(stored);
        fake.routes['PUT /request/12'] = (request) {
          stored = applyPut(stored, jsonDecode(request.body) as Map);
          return FakeSeerr.json(stored);
        };
        await tester.tap(find.text(t.seerr.checkStatus));
        await seerrSettle(tester);
        await tester.tap(find.text(t.seerr.saveChange));
        await seerrSettle(tester);
        final body = fake.sent('PUT', '/request/12').last.body as Map;
        expect(body['serverId'], 2);
        expect(body['profileId'], 6);
        expect(body['rootFolder'], '/media/series');
        expect(body['tags'], [9]);
        expect(body['languageProfileId'], 1);
      });
    }
  });

  group('a stored target is only replaced by an edit (B05)', () {
    setUp(() {
      fake
        ..on('GET /service/sonarr', [
          {
            'id': 1,
            'name': 'Sonarr HD',
            'is4k': false,
            'isDefault': true,
            'activeProfileId': 4,
            'activeDirectory': '/hd',
          },
        ])
        ..on('GET /service/sonarr/1', {
          'profiles': [
            {'id': 4, 'name': 'HD-1080p'},
          ],
          'rootFolders': [
            {'path': '/hd'},
          ],
        })
        ..on('GET /service/sonarr/2', {'message': 'gone'}, 404);
    });

    testWidgets('a server the service list no longer names is not swapped for the default', (tester) async {
      // The request points at server 2; only server 1 is offered.
      await open(tester, permissions: seerrPermAdmin);
      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      final body = fake.sent('PUT', '/request/12').single.body as Map;
      expect(body['serverId'], 2);
      expect(body['profileId'], 6);
      expect(body['rootFolder'], '/media/series');
      expect(body['tags'], [9]);
      expect(body['languageProfileId'], 1);
    });

    testWidgets('a profile and folder the options no longer list are passed back as stored', (tester) async {
      stored = fresh(serverId: 1);
      await open(tester, permissions: seerrPermAdmin);
      await tester.tap(find.text(t.seerr.season(number: 4)));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      final body = fake.sent('PUT', '/request/12').single.body as Map;
      expect(body['serverId'], 1);
      expect(body['profileId'], 6, reason: 'not the server default 4');
      expect(body['rootFolder'], '/media/series', reason: 'not the server default /hd');
    });

    testWidgets('an explicit choice does replace it', (tester) async {
      stored = fresh(serverId: 1);
      await open(tester, permissions: seerrPermAdmin);
      await tester.tap(find.text(t.seerr.advancedOptions));
      await tester.pump();
      await tester.tap(find.text('HD-1080p'));
      await tester.pump();
      await tester.tap(find.text(t.seerr.saveChange));
      await seerrSettle(tester);

      final body = fake.sent('PUT', '/request/12').single.body as Map;
      expect(body['profileId'], 4);
      expect(body['rootFolder'], '/media/series', reason: 'the folder was not touched');
    });
  });

  group('another account (B07)', () {
    testWidgets('a request that loads after a profile switch is not shown, and the form goes away', (tester) async {
      final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9, permissions: seerrPermAdmin);
      final slow = fake.hold('GET /request/12');
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      provider = await seerrProvider(fake, store: store);
      addTearDown(provider.dispose);
      var closed = false;
      bool? result;
      await pumpSeerr(
        tester,
        provider,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await SeerrRequestEditSheet.show(context, request: row());
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();

      await provider.onActiveProfileChanged('user-2');
      await tester.pump();
      // Request 12 of the previous account, answered once the admin is active.
      slow.complete(FakeSeerr.json(fresh(requestedBy: 9)));
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, isNull);
      expect(
        find.text(t.seerr.saveChange),
        findsNothing,
        reason: "no form for the new account on the old account's request",
      );
      expect(fake.sent('PUT', '/request/12'), isEmpty);
    });

    testWidgets('a save that completes after a profile switch is not reported as saved', (tester) async {
      final store = MemorySeerrStore()..sessions['user-2'] = seerrSession(userId: 9);
      final result = await () async {
        tester.view.physicalSize = const Size(900, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        provider = await seerrProvider(fake, store: store);
        addTearDown(provider.dispose);
        bool? value;
        await pumpSeerr(
          tester,
          provider,
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => value = await SeerrRequestEditSheet.show(context, request: row()),
              child: const Text('open'),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await seerrSettle(tester);
        await tester.pumpAndSettle();
        return () => value;
      }();
      await tickSeason(tester, 4);
      final answer = fake.hold('PUT /request/12');
      await tester.tap(find.text(t.seerr.saveChange));
      await tester.pump();

      await provider.onActiveProfileChanged('user-2');
      await tester.pump();
      answer.complete(FakeSeerr.json(fresh(seasons: [3, 4, 5])));
      await seerrSettle(tester);
      await tester.pumpAndSettle();

      expect(result(), isNull);
    });
  });

  testWidgets('a request that cannot be read offers a retry, not a form built on the old row', (tester) async {
    fake.on('GET /request/12', {'message': 'boom'}, 500);
    await open(tester);

    expect(find.text(t.seerr.editLoadFailed), findsOneWidget);
    expect(_button('retry'), findsOneWidget);
    expect(find.text(t.seerr.season(number: 3)), findsNothing);
  });
}
