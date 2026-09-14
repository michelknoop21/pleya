/// The initial-focus bug this covers: the connected card mounts
/// `_historyPolicyFocus`/`_testFocus`, never `_saveFocus` (that node only ever
/// mounts inside the unconfigured form's Test-result block). Aiming initial
/// focus at `_saveFocus` while already configured landed on nothing — a
/// TV-only dead end, since a remote has no fallback the way a touch or mouse
/// input does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_text_field.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/tautulli_provider.dart';
import 'package:pleya/screens/settings/tautulli_settings_screen.dart';
import 'package:pleya/services/tautulli/tautulli_constants.dart';
import 'package:pleya/services/tautulli/tautulli_integration_store.dart';
import 'package:pleya/services/tautulli/tautulli_server_integration.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const _machine = 'pms-1';

void main() {
  setUp(resetSharedPreferencesForTest);

  Future<void> pump(WidgetTester tester, TautulliProvider provider) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<TautulliProvider>.value(
          value: provider,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: const TautulliSettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('unconfigured: initial focus lands on the URL field', (tester) async {
    final provider = TautulliProvider();
    addTearDown(provider.dispose);

    await pump(tester, provider);

    final urlField = tester.widget<FocusableTextFormField>(find.byType(FocusableTextFormField).first);
    expect(urlField.focusNode!.hasFocus, isTrue);
  });

  testWidgets('configured with the history switch present: initial focus lands there, not on Save', (tester) async {
    final provider = await tester.runAsync(() async {
      await TautulliIntegrationStore.instance.save(
        TautulliServerIntegration(
          machineIdentifier: _machine,
          baseUrl: 'https://tautulli.example',
          authMode: TautulliAuthMode.device,
          token: 'tok',
          connectionState: TautulliConnectionState.connected,
        ),
      );
      final p = TautulliProvider();
      p.attachServerResolvers(serverIds: () => [_machine], isOwnerOrAdmin: (_) => true);
      await p.onActiveProfileChanged('uuid-a');
      return p;
    });
    addTearDown(provider!.dispose);
    expect(provider.isConfigured, isTrue);
    expect(provider.adminStatus, isNotNull, reason: 'the fixture must resolve before the first frame for this case');

    await pump(tester, provider);

    final historySwitch = tester.widget<SettingSwitchRow>(find.byType(SettingSwitchRow));
    expect(historySwitch.focusNode!.hasFocus, isTrue);
    // Save never mounts in the connected card at all — it lives only in the
    // unconfigured form's post-Test block, so nothing should even be able to
    // claim it here.
    expect(find.text(t.tautulli.save), findsNothing);
  });
}
