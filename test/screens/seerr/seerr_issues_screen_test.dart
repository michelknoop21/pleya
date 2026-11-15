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
import 'package:pleya/services/seerr/seerr_client.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/seerr/seerr_session.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/focusable_filter_chip.dart';

class _Profile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  bool get isBinding => false;

  @override
  String? get activeId => 'p1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Seerr extends SeerrProvider {
  _Seerr(this._client);

  final SeerrClient _client;

  @override
  SeerrClient? get client => _client;
}

Future<void> _pump(WidgetTester tester, SeerrClient client) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _Profile()),
            ChangeNotifierProvider<SeerrProvider>(create: (_) => _Seerr(client)),
          ],
          child: SeerrIssuesScreen(client: client, profileId: 'p1'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a 404 on the list route says reports are unavailable and offers no retry', (tester) async {
    final client = SeerrClient(
      SeerrSession(
        baseUrl: 'https://seerr.example',
        authMode: SeerrAuthMode.local,
        cookie: 'connect.sid=fixture',
        userId: 7,
        permissions: SeerrPermission.manageIssues,
      ),
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    addTearDown(client.dispose);
    await _pump(tester, client);
    expect(find.text(t.seerrIssues.serverUnsupported), findsOneWidget);
    expect(find.text(t.common.retry), findsNothing);
  });

  testWidgets('the own-reports filter is a FocusableFilterChip, so monoTheme shows its selection', (tester) async {
    final client = SeerrClient(
      SeerrSession(
        baseUrl: 'https://seerr.example',
        authMode: SeerrAuthMode.local,
        cookie: 'connect.sid=fixture',
        userId: 7,
        permissions: SeerrPermission.manageIssues,
      ),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'results': [],
            'pageInfo': {'pages': 1},
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _Profile()),
              ChangeNotifierProvider<SeerrProvider>(create: (_) => _Seerr(client)),
            ],
            child: SeerrIssuesScreen(client: client, profileId: 'p1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilterChip), findsNothing);
    final chip = tester.widget<FocusableFilterChip>(find.byType(FocusableFilterChip));
    expect(chip.label, t.seerrIssues.mine);
    expect(chip.selected, isFalse);
  });

  testWidgets('tapping the own-reports chip toggles the createdBy filter', (tester) async {
    final queries = <Map<String, String>>[];
    final client = SeerrClient(
      SeerrSession(
        baseUrl: 'https://seerr.example',
        authMode: SeerrAuthMode.local,
        cookie: 'connect.sid=fixture',
        userId: 7,
        permissions: SeerrPermission.manageIssues,
      ),
      httpClient: MockClient((request) async {
        queries.add(request.url.queryParameters);
        return http.Response(
          '{"results":[],"pageInfo":{"pages":1}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await _pump(tester, client);
    expect(queries.last.containsKey('createdBy'), isFalse);

    await tester.tap(find.byType(FocusableFilterChip));
    await tester.pumpAndSettle();
    expect(queries.last['createdBy'], '7');
    expect(tester.widget<FocusableFilterChip>(find.byType(FocusableFilterChip)).selected, isTrue);

    await tester.tap(find.byType(FocusableFilterChip));
    await tester.pumpAndSettle();
    expect(queries.last.containsKey('createdBy'), isFalse);
  });

  testWidgets('a quick reply fills the answer and sends nothing until Reactie plaatsen', (tester) async {
    final posts = <String>[];
    final client = SeerrClient(
      SeerrSession(
        baseUrl: 'https://seerr.example',
        authMode: SeerrAuthMode.local,
        cookie: 'connect.sid=fixture',
        userId: 7,
        permissions: SeerrPermission.manageIssues,
      ),
      httpClient: MockClient((request) async {
        if (request.method == 'POST') posts.add(request.url.path);
        return http.Response(
          jsonEncode({
            'id': 42,
            'status': 1,
            'issueType': 2,
            'createdBy': {'id': 9, 'displayName': 'Ravi'},
            'media': {'tmdbId': 5, 'mediaType': 'movie'},
            'comments': [
              {
                'id': 1,
                'message': 'Het geluid loopt achter',
                'user': {'id': 9},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ActiveProfileProvider>(create: (_) => _Profile()),
              ChangeNotifierProvider<SeerrProvider>(create: (_) => _Seerr(client)),
            ],
            child: SeerrIssuesScreen(client: client, profileId: 'p1', issueId: 42),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.seerrIssues.quickLooking));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, t.seerrIssues.quickLooking), findsOneWidget);
    expect(posts, isEmpty, reason: 'a chip is easy to tap by accident, so it never sends');

    await tester.tap(find.text(t.seerrIssues.sendReply));
    await tester.pumpAndSettle();
    expect(posts, ['/api/v1/issue/42/comment']);
  });
}
