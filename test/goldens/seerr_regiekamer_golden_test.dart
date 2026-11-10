/// Regiekamer on an iPhone (DEC-XXX, mockups C1, C2, C3): the requests list with
/// its count tiles and decision-first sections, the menu behind a row with its
/// facts, and a report with its conversation and quick replies.
///
/// The widget tests prove the behaviour (sections, ticks, swipes, counts). What
/// they cannot see is the composition the Regiekamer exists for: one column of
/// text per section, rows in one card, nothing loose on the right. That is
/// what these goldens guard. They render on Linux, like CI, and are not pixel
/// truth for iOS; the simulator run stays the acceptance.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/screens/seerr/seerr_issues_screen.dart';
import 'package:pleya/screens/seerr/seerr_requests_screen.dart';
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/seerr_request_row.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/seerr_fake.dart';

const _phone = Size(402, 874);

/// The app theme with Inter named on every text style. The theme sets Inter
/// once, at the top, and in the test binding some title styles do not pick it
/// up and fall back to the box font; on a device they do. Naming it here keeps
/// the goldens readable without changing what the app draws.
ThemeData _theme() {
  final theme = monoTheme(dark: true);
  return theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Inter'));
}

Map<String, dynamic> _req(
  int id,
  String title, {
  int status = 1,
  String type = 'movie',
  List<int> seasons = const [],
  bool is4k = false,
  int requestedBy = 9,
  String name = 'Ravi',
  int mediaStatus = 2,
  required String createdAt,
}) {
  final json = seerrRequestJson(
    id,
    status: status,
    type: type,
    seasons: seasons,
    is4k: is4k,
    requestedBy: requestedBy,
    mediaStatus: mediaStatus,
  );
  json['createdAt'] = createdAt;
  (json['media'] as Map)['title'] = title;
  (json['requestedBy'] as Map)['displayName'] = name;
  return json;
}

class _Profile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  String? get activeId => 'p1';

  @override
  bool get isBinding => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Seerr extends SeerrProvider {
  _Seerr(this._client);

  final SeerrClient _client;

  @override
  SeerrClient? get client => _client;
}

void main() {
  setUpAll(loadAppFontsForGoldens);

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  final now = DateTime.now().toUtc();
  String ago(Duration d) => now.subtract(d).toIso8601String();

  Future<void> pumpList(WidgetTester tester) async {
    setGoldenSurfaceSize(tester, size: _phone);
    final fake = FakeSeerr()
      ..on('GET /request/count', {'total': 389, 'pending': 27, 'approved': 108, 'available': 35})
      ..on(
        'GET /request',
        seerrPage([
          _req(1, 'Wadlopers', type: 'tv', seasons: [3, 4, 5], createdAt: ago(const Duration(days: 3))),
          _req(2, 'Tears of Steel', is4k: true, createdAt: ago(const Duration(days: 2))),
          _req(3, 'Dweebs', type: 'tv', seasons: [2], name: 'Noor', createdAt: ago(const Duration(days: 1))),
          _req(4, 'Elephants Dream', name: 'Sanne', createdAt: ago(const Duration(hours: 5))),
          _req(5, 'Charge', status: 2, name: 'Sanne', createdAt: ago(const Duration(days: 4))),
          _req(6, 'Sintel', status: 5, mediaStatus: 5, name: 'Michel', createdAt: ago(const Duration(days: 6))),
        ]),
      );
    final provider = await seerrProvider(fake, permissions: seerrPermManage);
    addTearDown(provider.dispose);
    await pumpSeerr(tester, provider, const SeerrRequestsScreen(), host: false, theme: _theme());
    await seerrSettle(tester);
    // Two ticked, so the one Goedkeuren for the batch is in the picture.
    for (final id in [1, 2]) {
      tester
          .widget<SeerrRequestRow>(find.byWidgetPredicate((w) => w is SeerrRequestRow && w.request.id == id))
          .onSelectedChanged!(true);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('Regiekamer list on an iPhone (C1)', (tester) async {
    await pumpList(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('seerr_regiekamer_list_dark.png'));
  });

  testWidgets('Regiekamer menu with facts on an iPhone (C2)', (tester) async {
    await pumpList(tester);
    await tester.tap(find.byWidgetPredicate((w) => w is SeerrRequestRow && w.request.id == 1));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('seerr_regiekamer_menu_dark.png'));
  });

  testWidgets('Regiekamer report with conversation on an iPhone (C3)', (tester) async {
    setGoldenSurfaceSize(tester, size: _phone);
    final client = SeerrClient(
      SeerrSession(
        baseUrl: 'https://seerr.example',
        authMode: SeerrAuthMode.local,
        cookie: 'connect.sid=fixture',
        userId: 7,
        permissions: SeerrPermission.manageIssues,
      ),
      httpClient: MockClient((request) async {
        final body = request.url.path.endsWith('/issue/128')
            ? {
                'id': 128,
                'status': 1,
                'issueType': 2,
                'problemSeason': 1,
                'problemEpisode': 3,
                'createdAt': ago(const Duration(days: 2)),
                'createdBy': {'id': 9, 'displayName': 'Ravi'},
                'media': {'tmdbId': 5, 'mediaType': 'tv'},
                'comments': [
                  {
                    'id': 1,
                    'message': 'Vanaf ongeveer 12 minuten loopt het geluid een halve seconde achter.',
                    'user': {'id': 9, 'displayName': 'Ravi'},
                    'createdAt': ago(const Duration(days: 2)),
                  },
                  {
                    'id': 2,
                    'message': 'Zie het ook. Ik heb een andere release aangevraagd.',
                    'user': {'id': 7, 'displayName': 'Michel'},
                    'createdAt': ago(const Duration(days: 1)),
                  },
                ],
              }
            : {'name': 'Nachttrein'};
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
      }),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _Profile()),
              ChangeNotifierProvider<SeerrProvider>(create: (_) => _Seerr(client)),
            ],
            child: SeerrIssuesScreen(client: client, profileId: 'p1', issueId: 128),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('seerr_regiekamer_issue_dark.png'));
  });
}
