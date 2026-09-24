import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/device_performance.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../../test_helpers/prefs.dart';

/// Phone-sized surface: [PlatformDetector.isTablet] is screen-diagonal based,
/// and the default test surface (~15") would read as a tablet and force the
/// `off` tier regardless of the setting under test.
Widget wrap(Widget child, {TargetPlatform? platform}) {
  var theme = monoTheme(dark: true);
  if (platform != null) theme = theme.copyWith(platform: platform);
  return MaterialApp(
    theme: theme,
    home: Center(child: child),
  );
}

void main() {
  setUp(() => resetSharedPreferencesForTest());

  testWidgets('setting uit rendert de legacy-widget', (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsService.getInstance());
    await SettingsService.instance.write(SettingsService.liquidGlass, false);

    await tester.pumpWidget(
      wrap(GlassSurface(shape: const StadiumBorder(), legacy: const Text('legacy'), child: const Text('glass'))),
    );

    expect(find.text('legacy'), findsOneWidget);
    expect(find.text('glass'), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('tvOS krijgt nepglas zonder LiquidGlass', (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsService.getInstance());
    await SettingsService.instance.write(SettingsService.liquidGlass, true);
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    await tester.pumpWidget(
      wrap(
        GlassLayer(
          child: GlassSurface(shape: const StadiumBorder(), child: const Text('glass')),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('LiquidGlass')), findsNothing);
  });

  testWidgets('reduced performance krijgt nepglas', (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => SettingsService.getInstance());
    await SettingsService.instance.write(SettingsService.liquidGlass, true);
    DevicePerformance.debugReset(autoReduced: true);
    addTearDown(DevicePerformance.debugReset);

    await tester.pumpWidget(
      wrap(
        GlassLayer(
          child: GlassSurface(shape: const StadiumBorder(), child: const Text('glass')),
        ),
        platform: TargetPlatform.iOS,
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('LiquidGlass')), findsNothing);
  });
}
