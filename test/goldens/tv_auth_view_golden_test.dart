import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/auth_screen.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/pleya_logo.dart';

import '../test_helpers/golden.dart';

Future<void> _loadAuthGoldenFonts() async {
  await loadAppFontsForGoldens();
  final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Visual acceptance for the Apple TV first-start composition.
///
/// These goldens mount the real [AuthScreen] Apple TV path rather than a
/// facsimile of [TvAuthView]. A deterministic Plex endpoint keeps the QR
/// attempt open, so both pictures cover the production brand, panel content,
/// focus treatment and QR sizing. As with every TV golden in this suite, the
/// Linux image guards composition; Pleya Verify remains the tvOS-rendering
/// authority.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadAuthGoldenFonts);
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pumpAuth(WidgetTester tester, {required MockClient pinClient}) async {
    setGoldenSurfaceSize(tester);

    Future<PlexAuthService> serviceFor(MockClient client) async =>
        PlexAuthService.forTesting(http: MediaServerHttpClient(client: client));

    final theme = monoTheme(dark: true);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // Typography.englishLike2021 retains its platform family in widget
          // tests, where Flutter substitutes the block-shaped Ahem font. The
          // app's ThemeData declares Inter; apply that declaration explicitly
          // here so the Linux reference renders the intended production face.
          theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Inter')),
          home: AuthScreen(
            plexPinAuthServiceFactory: () => serviceFor(pinClient),
            plexConnectAuthServiceFactory: () => serviceFor(MockClient((_) async => http.Response('{}', 200))),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => precacheImage(const AssetImage('assets/branding/pleya_logo.png'), tester.element(find.byType(AuthScreen))),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('initial backend choice', (tester) async {
    await pumpAuth(tester, pinClient: MockClient((_) async => http.Response('{}', 200)));

    await expectMatchesGolden(find.byType(MaterialApp), 'tv_auth_initial');
  });

  testWidgets('Plex QR panel', (tester) async {
    final pollResponse = Completer<http.Response>();
    final pinClient = MockClient((request) async {
      if (request.method == 'POST') {
        return http.Response(
          jsonEncode({'id': 1, 'code': 'PLEYA'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return pollResponse.future;
    });
    await pumpAuth(tester, pinClient: pinClient);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    try {
      await expectMatchesGolden(find.byType(MaterialApp), 'tv_auth_qr');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      pollResponse.complete(
        http.Response(jsonEncode({'authToken': null}), 200, headers: {'content-type': 'application/json'}),
      );
      await tester.pump(const Duration(seconds: 2));
    }
  });
}
