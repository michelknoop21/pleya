import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/auth_error_banner.dart';

import '../test_helpers/prefs.dart';

class _StubClient implements MediaServerClient {
  _StubClient(String id, this._name) : serverId = ServerId(id);

  @override
  final ServerId serverId;
  final String _name;

  @override
  String? get serverName => _name;

  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.authError;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(resetSharedPreferencesForTest);

  Future<({MultiServerManager manager, MultiServerProvider provider, FocusNode content})> pumpBanner(
    WidgetTester tester, {
    bool appleTv = false,
  }) async {
    TvDetectionService.debugSetAppleTVOverride(appleTv ? true : null);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    final manager = MultiServerManager();
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    final content = FocusNode(debugLabel: 'content');
    addTearDown(content.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: Column(
                children: [
                  const AuthErrorBanner(),
                  Expanded(
                    child: Focus(focusNode: content, autofocus: true, child: const SizedBox.expand()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (manager: manager, provider: provider, content: content);
  }

  testWidgets('no auth error means no bar at all', (tester) async {
    await pumpBanner(tester);
    expect(find.byType(AuthErrorBanner), findsOneWidget);
    expect(find.text(t.connections.signInAgain), findsNothing);
  });

  testWidgets('an expired session asks for a sign-in, not for a reconnect', (tester) async {
    final harness = await pumpBanner(tester);

    harness.manager.debugRegisterClientForTesting(_StubClient('srv-1', 'Zolder'), online: false);
    harness.manager.debugMarkAuthErrorForTesting(ServerId('srv-1'));
    await tester.pumpAndSettle();

    expect(find.text(t.connections.sessionExpiredOne(name: 'Zolder')), findsOneWidget);
    expect(find.text(t.connections.signInAgain), findsOneWidget);
    expect(
      find.text(t.common.reconnect),
      findsNothing,
      reason: 'a rejected token cannot be repaired by trying the same token again',
    );
  });

  testWidgets('the bar does not take the focus on Apple TV', (tester) async {
    final harness = await pumpBanner(tester, appleTv: true);
    expect(harness.content.hasFocus, isTrue);

    harness.manager.debugRegisterClientForTesting(_StubClient('srv-1', 'Zolder'), online: false);
    harness.manager.debugMarkAuthErrorForTesting(ServerId('srv-1'));
    await tester.pumpAndSettle();

    expect(find.text(t.connections.signInAgain), findsOneWidget);
    expect(
      harness.content.hasFocus,
      isTrue,
      reason: 'a status bar appearing must not pull the remote off whatever the user was on',
    );
  });

  testWidgets('the bar is a strip at the top, not a screen', (tester) async {
    final harness = await pumpBanner(tester);
    harness.manager.debugRegisterClientForTesting(_StubClient('srv-1', 'Zolder'), online: false);
    harness.manager.debugMarkAuthErrorForTesting(ServerId('srv-1'));
    await tester.pumpAndSettle();

    final banner = tester.getRect(find.byType(AuthErrorBanner));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(banner.top, screen.top);
    expect(banner.height, lessThan(screen.height / 4), reason: 'compact and non-modal, not the primary screen action');
  });

  testWidgets('the bar goes as soon as the connection it belongs to is disconnected', (tester) async {
    final harness = await pumpBanner(tester);

    harness.manager.debugRegisterClientForTesting(_StubClient('srv-1', 'Zolder'), online: false);
    harness.manager.debugMarkAuthErrorForTesting(ServerId('srv-1'));
    await tester.pumpAndSettle();
    expect(find.text(t.connections.signInAgain), findsOneWidget);

    harness.manager.removeServer(ServerId('srv-1'));
    await tester.pumpAndSettle();

    expect(
      find.text(t.connections.signInAgain),
      findsNothing,
      reason: 'the bar must not outlive the connection it is about',
    );
  });

  testWidgets('one server failing does not describe the others', (tester) async {
    final harness = await pumpBanner(tester);

    harness.manager.debugRegisterClientForTesting(_StubClient('srv-bad', 'Zolder'), online: false);
    harness.manager.debugRegisterClientForTesting(_StubClient('srv-ok', 'Woonkamer'));
    harness.manager.debugMarkAuthErrorForTesting(ServerId('srv-bad'));
    await tester.pumpAndSettle();

    expect(find.text(t.connections.sessionExpiredOne(name: 'Zolder')), findsOneWidget);
    expect(harness.provider.onlineServerIds, contains('srv-ok'));
  });
}
