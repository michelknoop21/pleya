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

void main() {
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
}
