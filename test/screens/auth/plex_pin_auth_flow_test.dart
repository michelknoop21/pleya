import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/auth/plex_pin_auth_flow.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_server_http_client.dart';

/// App Review twice signed in through "Sign in with Plex" using Jellyfin demo
/// credentials. That PIN is never claimed, so the only signal was a timeout —
/// five minutes later. The way out has to be on screen while the PIN is still
/// outstanding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  /// Mounts the flow with a Plex API that hands out a PIN and never claims it,
  /// then starts the QR attempt so the widget sits in its polling state.
  Future<void> pumpPollingFlow(WidgetTester tester, {VoidCallback? onSwitchToJellyfin}) async {
    final client = MediaServerHttpClient(
      client: MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/pins')) {
          return http.Response(
            jsonEncode({'id': 1, 'code': 'ABCD'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        // Poll response for an unclaimed PIN.
        return http.Response(jsonEncode({'authToken': null}), 200, headers: {'content-type': 'application/json'});
      }),
    );
    addTearDown(client.close);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlexPinAuthFlow(
                onTokenReceived: (_) async {},
                autoStartQrOnTV: false,
                onSwitchToJellyfin: onSwitchToJellyfin,
                authServiceFactory: () async => PlexAuthService.forTesting(http: client),
              ),
            ),
          ),
        ),
      ),
    );
    // Let the injected service resolve, then start the QR attempt.
    await tester.pump();
    await tester.tap(find.text(t.auth.showQRCode));
    await tester.pump();
    await tester.pump();
  }

  /// Disposal cancels the attempt; one more tick drains the backoff delay so
  /// no timer outlives the test.
  Future<void> tearDownFlow(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('offers the Jellyfin way out while the PIN is still being polled', (tester) async {
    await pumpPollingFlow(tester, onSwitchToJellyfin: () {});

    expect(find.text(t.auth.usingJellyfinInstead), findsOneWidget);
    // Proves it is the polling-state hint, not the post-timeout error block.
    expect(find.text(t.auth.authenticationTimeout), findsNothing);
    expect(find.text(t.auth.tryAgain), findsNothing);

    await tearDownFlow(tester);
  });

  testWidgets('omits the Jellyfin way out when the parent offers no route', (tester) async {
    await pumpPollingFlow(tester);

    expect(find.text(t.auth.usingJellyfinInstead), findsNothing);

    await tearDownFlow(tester);
  });

  testWidgets('tapping the Jellyfin way out calls back to the parent and abandons the Plex attempt', (tester) async {
    var switched = 0;
    await pumpPollingFlow(tester, onSwitchToJellyfin: () => switched++);

    await tester.tap(find.text(t.auth.usingJellyfinInstead));
    await tester.pump();

    expect(switched, 1);
    // The parent pushes the Jellyfin route over this widget, so it keeps
    // living. Polling must stop, or a late PIN claim navigates out from
    // under the user mid-sign-in.
    expect(find.text(t.auth.showQRCode), findsOneWidget);
    expect(find.text(t.auth.waitingForAuth), findsNothing);

    await tearDownFlow(tester);
  });
}
