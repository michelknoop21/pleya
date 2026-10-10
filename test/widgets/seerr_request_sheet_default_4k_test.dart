/// The request form for a request that names no server. The request server
/// routes that one to the default instance of the quality, so without such an
/// instance the request is approved and then goes nowhere. 4K needs the
/// default to be known; HD is only held back when the list says there is none.
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

  /// An HD and a 4K instance, each present when its flag says whether it is
  /// the default.
  void servers(String service, {bool? fourK, bool? hd = true}) => fake.on('GET /service/$service', [
    if (hd != null)
      {'id': 1, 'name': 'HD', 'is4k': false, 'isDefault': hd, 'activeProfileId': 4, 'activeDirectory': '/hd'},
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
      expect(seerrNode(AutomationIds.requestsFormNotice, 'route'), findsOneWidget, reason: 'and the form says why');

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

  Finder notice(String kind) => seerrNode(AutomationIds.requestsFormNotice, kind);

  group('HD without a default HD instance', () {
    for (final (media, service, label) in [(_movie, 'radarr', 'film'), (_show, 'sonarr', 'series')]) {
      testWidgets('$label: an HD instance that is not the default is said, and nothing can be sent', (tester) async {
        servers(service, hd: false);
        await open(tester, media, permissions: seerrPermRequest);

        expect(notice('route'), findsOneWidget);
        expect(find.text(t.seerr.noDefaultServerTitle), findsOneWidget);
        expect(_enabled(tester, 'submit'), isFalse);
        expect(fake.sent('GET', '/service/$service'), hasLength(1));
        expect(fake.sent('GET', '/service/$service/1'), isEmpty);
      });

      testWidgets('$label: with a default HD instance the request goes out, with no word about servers', (
        tester,
      ) async {
        servers(service);
        await open(tester, media, permissions: seerrPermRequest);

        expect(notice('route'), findsNothing);
        await tester.tap(find.descendant(of: _button('submit'), matching: find.byType(FilledButton)));
        await seerrSettle(tester);
        final body = fake.sent('POST', '/request').single.body as Map;
        expect(body, containsPair('is4k', false));
        expect(body.containsKey('serverId'), isFalse);
      });

      testWidgets('$label: no HD instance and a default 4K one leaves 4K open for a profile with the 4K right', (
        tester,
      ) async {
        servers(service, hd: null, fourK: true);
        await open(tester, media, permissions: _fourKMovie | _fourKTv);

        expect(notice('route'), findsOneWidget, reason: 'HD has nowhere to go');
        expect(find.text(t.seerr.no4kServerTitle), findsNothing, reason: 'that line is about an admin and 4K');
        expect(_enabled(tester, 'submit'), isFalse);

        await tester.tap(find.byType(Switch));
        await seerrSettle(tester);
        expect(notice('route'), findsNothing);
        await tester.tap(find.descendant(of: _button('submit'), matching: find.byType(FilledButton)));
        await seerrSettle(tester);
        expect(fake.sent('POST', '/request').single.body, containsPair('is4k', true));
      });

      for (final (why, answer) in <(String, void Function(String))>[
        ('refuses the list', (route) => fake.on(route, {'message': 'no'}, 403)),
        ('drops the connection', (route) => fake.fail(route)),
        ('answers with something that is not a list', (route) => fake.on(route, {'unexpected': true})),
        ('lists no instances', (route) => fake.on(route, <Object>[])),
      ]) {
        testWidgets('$label: a server that $why does not hold HD back, and offers no 4K', (tester) async {
          answer('GET /service/$service');
          await open(tester, media, permissions: _fourKMovie | _fourKTv);

          expect(find.byType(Switch), findsNothing);
          expect(notice('route'), findsNothing);
          await tester.tap(find.descendant(of: _button('submit'), matching: find.byType(FilledButton)));
          await seerrSettle(tester);
          expect(fake.sent('POST', '/request').single.body, containsPair('is4k', false));
        });
      }
    }
  });

  group('while the instance list is on its way', () {
    testWidgets('nothing can be sent, and the answer decides', (tester) async {
      final list = fake.hold('GET /service/radarr');
      await open(tester, _movie, permissions: seerrPermRequest);
      expect(_button('submit'), findsNothing, reason: 'the form is not there yet');

      list.complete(
        FakeSeerr.json([
          {'id': 1, 'name': 'HD', 'is4k': false, 'isDefault': false},
        ]),
      );
      await seerrSettle(tester);
      expect(_enabled(tester, 'submit'), isFalse);
      expect(notice('route'), findsOneWidget);
    });

    testWidgets('it is asked beside the series detail, not after it', (tester) async {
      final detail = fake.hold('GET /tv/1399');
      servers('sonarr');
      await open(tester, _show, permissions: seerrPermRequest);
      expect(fake.sent('GET', '/service/sonarr'), hasLength(1));
      detail.complete(FakeSeerr.json({'id': 1399, 'seasons': <Object>[]}));
      await seerrSettle(tester);
    });

    testWidgets('a list that takes too long frees HD, keeps 4K shut, and a late answer changes nothing', (
      tester,
    ) async {
      final list = fake.hold('GET /service/radarr');
      await open(tester, _movie, permissions: _fourKMovie);
      await tester.pump(const Duration(seconds: 2));
      expect(_button('submit'), findsNothing);

      await tester.pump(const Duration(seconds: 1, milliseconds: 100));
      await seerrSettle(tester);
      expect(_enabled(tester, 'submit'), isTrue);
      expect(find.byType(Switch), findsNothing);

      list.complete(
        FakeSeerr.json([
          {'id': 2, 'name': '4K', 'is4k': true, 'isDefault': true},
        ]),
      );
      await seerrSettle(tester);
      expect(find.byType(Switch), findsNothing, reason: 'the form does not change under the viewer');
      expect(notice('route'), findsNothing);
      expect(_enabled(tester, 'submit'), isTrue);
    });
  });

  testWidgets('a late answer that says there is no default HD instance does not shut a form that was opened', (
    tester,
  ) async {
    final list = fake.hold('GET /service/radarr');
    await open(tester, _movie, permissions: seerrPermRequest);
    await tester.pump(const Duration(seconds: 3, milliseconds: 100));
    await seerrSettle(tester);
    expect(_enabled(tester, 'submit'), isTrue);

    list.complete(
      FakeSeerr.json([
        {'id': 1, 'name': 'HD', 'is4k': false, 'isDefault': false},
      ]),
    );
    await seerrSettle(tester);
    expect(notice('route'), findsNothing);
    expect(_enabled(tester, 'submit'), isTrue, reason: 'past the bound the instances count as not known');

    await tester.tap(find.text(t.seerr.requestMovie));
    await seerrSettle(tester);
    expect(fake.sent('POST', '/request').single.body, containsPair('is4k', false));
  });

  group('an admin with nothing to choose from', () {
    testWidgets('an empty instance list: no 4K switch, and HD goes out', (tester) async {
      fake.on('GET /service/radarr', <Object>[]);
      await open(tester, _movie, permissions: seerrPermAdmin, initialIs4k: true);

      expect(find.byType(Switch), findsNothing);
      expect(_form(tester)['is4k'], isFalse);
      expect(_enabled(tester, 'submit'), isTrue);
    });

    testWidgets('a list that cannot be read: no 4K switch, and HD goes out on the server default', (tester) async {
      fake.on('GET /service/radarr', {'message': 'boom'}, 500);
      await open(tester, _movie, permissions: seerrPermAdmin, initialIs4k: true);

      expect(find.byType(Switch), findsNothing);
      await tester.tap(find.text(t.seerr.requestWithServerDefault));
      await seerrSettle(tester);
      expect(fake.sent('POST', '/request').single.body, containsPair('is4k', false));
    });

    testWidgets('an HD instance that is not the default is still his to choose, and the request names it', (
      tester,
    ) async {
      servers('radarr', hd: false);
      fake.on('GET /service/radarr/1', {'profiles': <Object>[], 'rootFolders': <Object>[]});
      await open(tester, _movie, permissions: seerrPermAdmin);

      expect(notice('route'), findsNothing);
      await tester.tap(find.text(t.seerr.requestMovie));
      await seerrSettle(tester);
      expect(fake.sent('POST', '/request').single.body, containsPair('serverId', 1));
    });
  });

  testWidgets('with the remote: Select on the switch brings and takes the line about the server, and keeps the focus', (
    tester,
  ) async {
    servers('sonarr', hd: null, fourK: true);
    await open(tester, _show, permissions: _fourKTv);
    expect(notice('route'), findsOneWidget);

    // Whatever holds the focus on a form that cannot send, UP ends on the switch.
    for (var i = 0; i < 4 && !seerrHasFocus(tester, _option('fourK')); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await seerrSettle(tester);
    }
    expect(seerrHasFocus(tester, _option('fourK')), isTrue);

    for (final shown in [false, true]) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await seerrSettle(tester);
      expect(notice('route'), shown ? findsOneWidget : findsNothing);
      expect(seerrHasFocus(tester, _option('fourK')), isTrue);
    }
  });
}
