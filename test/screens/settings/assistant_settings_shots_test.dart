// Instellingen > Big P with the Kinderprofiel switch, on an iPhone, for the
// review. Skipped unless BIGP_SHOT_DIR is set:
//   BIGP_SHOT_DIR=/tmp/bigp flutter test test/screens/settings/assistant_settings_shots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/screens/settings/assistant_settings_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

final _dir = Platform.environment['BIGP_SHOT_DIR'];

class _Store implements AssistantProviderStore {
  @override
  Future<AssistantProviderConfig?> load() async => const AssistantProviderConfig(
    kind: AssistantProviderKind.ollamaServer,
    baseUrl: 'http://nas.lan:11434',
    model: 'm',
  );

  @override
  Future<void> save(AssistantProviderConfig config, {bool replaceUnreadable = false}) async {}

  @override
  Future<void> clear() async {}
}

class _ActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  _ActiveProfile(this.active);
  @override
  final Profile? active;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    if (_dir == null) return;
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
  });

  for (final (name, restricted) in [('instellingen-kinderprofiel', false), ('instellingen-kinderprofiel-plex', true)]) {
    testWidgets(name, skip: _dir == null, (tester) async {
      await tester.runAsync(() async {
        resetSharedPreferencesForTest();
        SettingsService.resetForTesting();
        await (await StorageService.getInstance()).setActiveProfileId('p');
        await SettingsService.getInstance();
      });
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final profile = Profile.plexHome(
        id: 'p',
        displayName: 'Mila',
        plexRestricted: restricted,
        createdAt: DateTime(2026),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ChangeNotifierProvider<ActiveProfileProvider>(
            create: (_) => _ActiveProfile(profile),
            child: TranslationProvider(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: monoTheme(dark: true),
                home: AssistantSettingsScreen(
                  store: _Store(),
                  listModels: (_) async => const [],
                  autoLoadDelay: Duration.zero,
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
      final row = find.text(t.assistant.settings.kidsProfile);
      await tester.scrollUntilVisible(row, 200, scrollable: find.byType(Scrollable).first);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 250));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final bytes = await (await ro.toImage(pixelRatio: 3)).toByteData(format: ui.ImageByteFormat.png);
        await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      });
    });
  }
}
