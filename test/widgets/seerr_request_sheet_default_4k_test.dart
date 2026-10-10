/// 4K on the request form for a request that names no server. The request
/// server routes that one to the default instance of the quality, so a 4K
/// request without a default 4K instance is approved and then goes nowhere.
/// `seerr_request_sheet_states_test.dart` covers what the form sends when the
/// default 4K instance is there.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/widgets/seerr_request_sheet.dart';

import '../test_helpers/seerr_fake.dart';

const _movie = SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Charge');
const _show = SeerrMedia(tmdbId: 1399, mediaType: 'tv', title: 'Wadlopers');

const _fourKMovie = SeerrPermission.request | SeerrPermission.request4kMovie;
const _fourKTv = SeerrPermission.request | SeerrPermission.request4kTv;

Finder _button(String instance) => seerrNode(AutomationIds.requestsFormButton, instance);
Finder _option(String instance) => seerrNode(AutomationIds.requestsFormOption, instance);

bool _enabled(WidgetTester tester, String instance) =>
    tester
        .widget<FilledButton>(find.descendant(of: _button(instance), matching: find.byType(FilledButton)))
        .onPressed !=
    null;

Map _form(WidgetTester tester) =>
    tester.widget<AutomationNode>(seerrNode(AutomationIds.requestsForm, 'create')).state!() as Map;

void main() {
  late FakeSeerr fake;
  late SeerrProvider provider;

  /// One HD instance, and a 4K one when [fourK] says whether it is the default.
  void servers(String service, {bool? fourK}) => fake.on('GET /service/$service', [
    {'id': 1, 'name': 'HD', 'is4k': false, 'isDefault': true, 'activeProfileId': 4, 'activeDirectory': '/hd'},
    if (fourK != null)
      {'id': 2, 'name': '4K', 'is4k': true, 'isDefault': fourK, 'activeProfileId': 8, 'activeDirectory': '/4k'},
  ]);

  Future<void> open(WidgetTester tester, SeerrMedia media, {required int permissions, bool initialIs4k = false}) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    provider = await seerrProvider(fake, permissions: permissions);
    addTearDown(provider.dispose);
    await pumpSeerr(tester, provider, SeerrRequestSheet(media: media, initialIs4k: initialIs4k));
    await seerrSettle(tester);
  }

  setUp(() {
    fake = FakeSeerr()
      ..on('GET /user/7/quota', {
        'movie': {'limit': 0},
        'tv': {'limit': 0},
      })
      // Season 1 is there in HD and open in 4K, the 'more seasons' case.
      ..on('GET /tv/1399', {
        'id': 1399,
        'name': 'Wadlopers',
        'seasons': [
          for (var n = 1; n <= 3; n++) {'seasonNumber': n, 'episodeCount': 8},
        ],
        'mediaInfo': {
          'status': 4,
          'seasons': [
            {'seasonNumber': 1, 'status': 5, 'status4k': 1},
          ],
        },
      })
      ..on('POST /request', {'id': 1});
  });

  group('a requester, film', () {
    testWidgets('with a default 4K instance can switch to 4K, and the request names no server', (tester) async {
      servers('radarr', fourK: true);
      await open(tester, _movie, permissions: _fourKMovie);

      await tester.tap(find.byType(Switch));
      await seerrSettle(tester);
      await tester.tap(find.text(t.seerr.requestMovie));
      await seerrSettle(tester);

      final body = fake.sent('POST', '/request').single.body as Map;
      expect(body, containsPair('is4k', true));
      expect(body.containsKey('serverId'), isFalse, reason: 'a requester has no server to choose');
      expect(fake.sent('GET', '/service/radarr/2'), isEmpty);
      expect(fake.sent('GET', '/service/sonarr'), isEmpty);
    });

    testWidgets('with a 4K instance that is not the default gets no switch, and a form opened on 4K sends HD', (
      tester,
    ) async {
      servers('radarr', fourK: false);
      await open(tester, _movie, permissions: _fourKMovie, initialIs4k: true);

      expect(find.byType(Switch), findsNothing);
      expect(_option('fourK'), findsNothing);
      expect(find.text(t.seerr.fourKNotAllowedMovie), findsNothing, reason: 'the right is not what is missing');
      expect(_form(tester)['is4k'], isFalse);

      await tester.tap(find.text(t.seerr.requestMovie));
      await seerrSettle(tester);
      expect(fake.sent('POST', '/request').single.body, containsPair('is4k', false));
    });

    testWidgets('with no 4K instance gets no switch', (tester) async {
      servers('radarr');
      await open(tester, _movie, permissions: _fourKMovie);
      expect(find.byType(Switch), findsNothing);
      expect(_enabled(tester, 'submit'), isTrue);
    });

    testWidgets('with an instance list that cannot be read gets no switch, no error, and HD still goes out', (
      tester,
    ) async {
      fake.on('GET /service/radarr', {'message': 'boom'}, 500);
      await open(tester, _movie, permissions: _fourKMovie, initialIs4k: true);

      expect(find.byType(Switch), findsNothing);
      expect(seerrNode(AutomationIds.requestsFormNotice, 'error'), findsNothing);
      expect(seerrNode(AutomationIds.requestsFormNotice, 'target'), findsNothing);
      expect(find.text(t.seerr.requestWithServerDefault), findsNothing);

      await tester.tap(find.text(t.seerr.requestMovie));
      await seerrSettle(tester);
      expect(fake.sent('POST', '/request').single.body, containsPair('is4k', false));
    });

    testWidgets('that is there in HD has nothing left to ask for without a default 4K instance', (tester) async {
      servers('radarr', fourK: false);
      await open(
        tester,
        const SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'x', status: SeerrMediaStatus.available),
        permissions: _fourKMovie,
      );
      expect(find.text(t.seerr.available), findsOneWidget);
      expect(_button('submit'), findsNothing);
    });
  });

  group('a requester, series', () {
    testWidgets('with a default 4K Sonarr can ask for the season that is open in 4K', (tester) async {
      servers('sonarr', fourK: true);
      await open(tester, _show, permissions: _fourKTv, initialIs4k: true);

      expect(_form(tester)['is4k'], isTrue);
      expect(_form(tester)['seasons'], [1, 2, 3]);
      await tester.tap(find.text(t.seerr.requestSeasons(count: 3)));
      await seerrSettle(tester);

      final body = fake.sent('POST', '/request').single.body as Map;
      expect(body, containsPair('is4k', true));
      expect(body.containsKey('serverId'), isFalse);
      expect(fake.sent('GET', '/service/radarr'), isEmpty);
    });

    testWidgets('with a 4K Sonarr that is not the default: a form opened on 4K falls back to the HD seasons', (
      tester,
    ) async {
      servers('sonarr', fourK: false);
      await open(tester, _show, permissions: _fourKTv, initialIs4k: true);

      expect(find.byType(Switch), findsNothing);
      expect(_form(tester)['is4k'], isFalse);
      expect(_form(tester)['seasons'], [2, 3], reason: 'season 1 is there in HD');

      await tester.tap(find.text(t.seerr.requestSeasons(count: 2)));
      await seerrSettle(tester);
      final body = fake.sent('POST', '/request').single.body as Map;
      expect(body, containsPair('is4k', false));
      expect(body['seasons'], [2, 3]);
    });

    testWidgets('with a connection that drops on the instance list gets no switch, and HD still goes out', (
      tester,
    ) async {
      fake.fail('GET /service/sonarr');
      await open(tester, _show, permissions: _fourKTv);

      expect(find.byType(Switch), findsNothing);
      expect(seerrNode(AutomationIds.requestsFormNotice, 'error'), findsNothing);
      expect(_enabled(tester, 'submit'), isTrue);
    });
  });

  group('an admin', () {
    setUp(() {
      fake
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

    testWidgets('keeps the switch for a 4K instance that is not the default, and the request names it', (tester) async {
      servers('radarr', fourK: false);
      await open(tester, _movie, permissions: seerrPermAdmin);

      await tester.tap(find.byType(Switch));
      await seerrSettle(tester);
      await tester.tap(find.text(t.seerr.requestMovie));
      await seerrSettle(tester);

      final body = fake.sent('POST', '/request').single.body as Map;
      expect(body, containsPair('is4k', true));
      expect(body, containsPair('serverId', 2));
      expect(body, containsPair('profileId', 8));
    });

    testWidgets('whose 4K instance is not the default and will not show its options cannot send 4K', (tester) async {
      servers('radarr', fourK: false);
      fake.on('GET /service/radarr/2', {'message': 'boom'}, 500);
      await open(tester, _movie, permissions: seerrPermAdmin);

      await tester.tap(find.byType(Switch));
      await seerrSettle(tester);
      expect(_enabled(tester, 'submit'), isFalse, reason: 'no server goes along, and no default 4K takes it');

      await tester.tap(find.byType(Switch));
      await seerrSettle(tester);
      expect(_enabled(tester, 'submit'), isTrue, reason: 'HD is the way out');
    });

    testWidgets('whose default 4K instance will not show its options still sends 4K on the server default', (
      tester,
    ) async {
      servers('radarr', fourK: true);
      fake.on('GET /service/radarr/2', {'message': 'boom'}, 500);
      await open(tester, _movie, permissions: seerrPermAdmin);

      await tester.tap(find.byType(Switch));
      await seerrSettle(tester);
      await tester.tap(find.text(t.seerr.requestWithServerDefault));
      await seerrSettle(tester);

      final body = fake.sent('POST', '/request').single.body as Map;
      expect(body, containsPair('is4k', true));
      expect(body.containsKey('serverId'), isFalse);
    });
  });

  group('with the remote', () {
    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await seerrSettle(tester);
    }

    testWidgets('UP from the button lands on the last season when the switch is not there, and DOWN comes back', (
      tester,
    ) async {
      servers('sonarr', fourK: false);
      await open(tester, _show, permissions: _fourKTv, initialIs4k: true);
      expect(seerrHasFocus(tester, _button('submit')), isTrue);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(seerrHasFocus(tester, find.text(t.seerr.season(number: 3))), isFalse, reason: 'the tile holds the focus');
      expect(
        seerrHasFocus(tester, find.ancestor(of: find.text(t.seerr.season(number: 3)), matching: find.byType(ListTile))),
        isTrue,
      );

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(seerrHasFocus(tester, _button('submit')), isTrue);
    });

    testWidgets('UP from the button lands on the switch when it is there, and Select leaves the focus on it', (
      tester,
    ) async {
      servers('sonarr', fourK: true);
      await open(tester, _show, permissions: _fourKTv);
      expect(seerrHasFocus(tester, _button('submit')), isTrue);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(seerrHasFocus(tester, _option('fourK')), isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await seerrSettle(tester);
      expect(_form(tester)['is4k'], isTrue);
      expect(seerrHasFocus(tester, _option('fourK')), isTrue);
      expect(_form(tester)['seasons'], [1, 2, 3]);
    });
  });
}
