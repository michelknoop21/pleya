import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_text_field.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/add_local_folder_screen.dart';
import 'package:pleya/screens/settings/pleya_share_join_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../../test_helpers/prefs.dart';

/// Both screens shipped with bare [TextField]s, which on TV means no keyboard
/// at all: nothing wires the TV OSK up, so a remote simply cannot enter a host
/// address or a folder name. Guard against that regressing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
  });

  testWidgets('Pleya Share join fields are TV-capable and focusable', (tester) async {
    await _pumpTv(tester, const PleyaShareJoinScreen());

    // Host + pairing code.
    final fields = tester.widgetList<FocusableTextField>(find.byType(FocusableTextField)).toList();
    expect(fields, hasLength(2));
    for (final field in fields) {
      expect(field.tvKeyboardAutoOpenBehavior, TvKeyboardAutoOpenBehavior.afterFirstFocus);
      expect(field.focusNode, isNotNull);
    }

    fields.first.focusNode!.requestFocus();
    await tester.pump();
    expect(fields.first.focusNode!.hasFocus, isTrue);

    // This screen starts LAN discovery in initState; let its timers drain so
    // the harness doesn't flag them as leaked.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('Add local folder name field is TV-capable and focusable', (tester) async {
    await _pumpTv(tester, const AddLocalFolderScreen());

    final field = tester.widget<FocusableTextField>(find.byType(FocusableTextField));
    expect(field.tvKeyboardAutoOpenBehavior, TvKeyboardAutoOpenBehavior.afterFirstFocus);
    expect(field.focusNode, isNotNull);

    field.focusNode!.requestFocus();
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);
  });
}

Future<void> _pumpTv(WidgetTester tester, Widget screen) async {
  TvDetectionService.debugSetAppleTVOverride(null);
  await TvDetectionService.getInstance(forceTv: true);
  TvDetectionService.setForceTVSync(true);
  await tester.binding.setSurfaceSize(const Size(1280, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(TranslationProvider(child: MaterialApp(home: screen)));
  await tester.pump();
}
