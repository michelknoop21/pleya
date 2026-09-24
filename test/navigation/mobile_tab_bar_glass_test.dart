/// The floating glass tab bar (Liquid Glass Task 5, mockup LG-01).
///
/// (a) Setting off: the Task 4 bar, untouched, and the Scaffold does not
/// extend its body. (b) Setting on, iPhone-sized: one glass capsule, body
/// extended. (c) Review Focus 3: the last row of a tab root scrolls clear of
/// the floating bar. (d) Contrast of the bar's labels over the lightest real
/// fixture (Big Buck Bunny), fake tier, i.e. the floor.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/screens/main/mobile_tab_bar.dart';
import 'package:pleya/screens/main_screen.dart' show mainScreenBottomNavigationTabs;
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_discovery_shell.dart';
import 'package:provider/provider.dart';

import '../test_helpers/contrast.dart';
import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';

/// The iPhone bar as `MainScreen` builds it: Home, Series, Movies, My Pleya.
List<NavigationTab> _phoneTabs() => mainScreenBottomNavigationTabs(
  visibleTabs: NavigationTab.getVisibleTabs(isOffline: false, isMobile: true, isPhone: true),
  isMobile: true,
  isPhone: true,
  isOffline: false,
  currentTab: NavigationTabId.discover,
);

late final ui.Image _lightSceneImage;

const _kSceneKey = Key('scene');

/// iPhone 17 Pro: 393x852 logical at 3x with a 34pt home indicator. The
/// device pixel ratio matters: `PlatformDetector.isTablet` is diagonal-in-
/// inches based, and 393x852 at 1x reads as a 15" tablet (glass off).
Future<void> _phone(WidgetTester tester, {required bool glass}) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.runAsync(() => SettingsService.getInstance());
  await SettingsService.instance.write(SettingsService.liquidGlass, glass);
}

/// The main-screen shape: Scaffold keyed on [mobileTabBarFloats], [body] as
/// the tab root, [MobileTabBar] as the bottom bar.
Widget _shell(Widget Function(BuildContext) body, {int currentIndex = 0}) {
  final tabs = _phoneTabs();
  return MaterialApp(
    theme: monoTheme(dark: true),
    home: Provider<ActiveProfileProvider?>.value(
      value: null,
      child: Builder(
        builder: (context) => Scaffold(
          extendBody: mobileTabBarFloats(context),
          body: Builder(builder: body),
          bottomNavigationBar: MobileTabBar(
            tabs: tabs,
            currentIndex: currentIndex,
            onDestinationSelected: (_) {},
            hideLabels: false,
            presentation: TabBarPresentation.unified2026,
            onLibraryLongPress: (_) {},
          ),
        ),
      ),
    ),
  );
}

Widget _longList(BuildContext context, {bool tail = true}) => CustomScrollView(
  slivers: [
    SliverList.builder(
      itemCount: 40,
      itemBuilder: (_, i) => SizedBox(key: ValueKey('row-$i'), height: 120, child: Text('row $i')),
    ),
    if (tail) mobileDiscoveryTailSliver(context),
  ],
);

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    _lightSceneImage = (await codec.getNextFrame()).image;
  });
  setUp(() => resetSharedPreferencesForTest());

  testWidgets('(a) glas uit: de balk van vandaag, full-width, body niet eronder', (tester) async {
    await _phone(tester, glass: false);
    await tester.pumpWidget(_shell((_) => const SizedBox.expand()));
    await tester.pumpAndSettle();

    expect(find.byType(GlassSurface), findsNothing);
    final blurs = tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).toList();
    expect(blurs, hasLength(1));
    expect(blurs.single.filter, ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18));
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isFalse);

    // Edge to edge and flush with the bottom, the theme's own bar color.
    final bar = tester.getRect(find.byType(NavigationBar));
    expect(bar.left, 0);
    expect(bar.width, 393);
    expect(bar.bottom, 852);
    final theme = NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
    expect(theme.backgroundColor, const Color(0xE60F0F0F));
  });

  testWidgets('(b) glas aan: één glazen capsule, zwevend, body eronder', (tester) async {
    await _phone(tester, glass: true);
    await tester.pumpWidget(_shell((_) => const SizedBox.expand()));
    await tester.pumpAndSettle();

    expect(find.byType(GlassSurface), findsOneWidget);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).extendBody, isTrue);

    final plate = tester.getRect(find.byType(GlassSurface));
    expect(plate.left, 16);
    expect(plate.right, 393 - 16);
    expect(plate.height, 64);
    expect(plate.bottom, 852 - 34 - 10);
    final theme = NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
    expect(theme.backgroundColor, Colors.transparent);
  });

  testWidgets('(c) Review Focus 3: de laatste rij scrollt vrij boven de zwevende balk', (tester) async {
    await _phone(tester, glass: true);
    await tester.pumpWidget(_shell((context) => _longList(context)));
    await tester.pumpAndSettle();

    final last = find.byKey(const ValueKey('row-39'));
    await tester.scrollUntilVisible(last, 300);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    final barTop = tester.getTopLeft(find.byType(GlassSurface)).dy;
    expect(tester.getBottomLeft(last).dy, lessThanOrEqualTo(barTop));
  });

  testWidgets('(c) controle: zonder staart-padding verdwijnt de laatste rij achter de balk', (tester) async {
    await _phone(tester, glass: true);
    await tester.pumpWidget(_shell((context) => _longList(context, tail: false)));
    await tester.pumpAndSettle();

    final last = find.byKey(const ValueKey('row-39'));
    await tester.scrollUntilVisible(last, 300);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    final barTop = tester.getTopLeft(find.byType(GlassSurface)).dy;
    expect(tester.getBottomLeft(last).dy, greaterThan(barTop));
  });

  group('(d) contrast over Big Buck Bunny (nepglas = ondergrens)', () {
    // The real bar over the scene's lightest band (fur, sunlit bark), labels
    // painted transparent with their shadows kept, as the meter requires.
    Future<void> pumpBarOverScene(WidgetTester tester) async {
      await _phone(tester, glass: true);
      MobileTabBar.debugGlassLabelColor = Colors.transparent;
      addTearDown(() => MobileTabBar.debugGlassLabelColor = null);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _kSceneKey,
          child: _shell(
            (_) => Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.black)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 180,
                  child: RawImage(image: _lightSceneImage, fit: BoxFit.cover),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('inactief wit label haalt 4,5:1', (tester) async {
      await pumpBarOverScene(tester);
      final tabs = _phoneTabs();
      final ratios = <String, double>{};
      for (final tab in tabs.skip(1)) {
        ratios[tab.getLabel()] = await textContrastOverBackground(
          tester,
          area: find.text(tab.getLabel()),
          textColor: Colors.white,
          boundary: find.byKey(_kSceneKey),
        );
      }
      // ignore: avoid_print
      print('glass tab bar contrast, inactive white: $ratios');
      for (final ratio in ratios.values) {
        expect(ratio, greaterThanOrEqualTo(4.5));
      }
    });

    // kAccent (#E5140F) tops out at 4.36:1 even on pure black, so 4.5 is
    // out of reach for any plate; the classic bar has the same red. This
    // records the number and holds the 3:1 floor.
    testWidgets('actief rood label: gemeten, ondergrens 3:1', (tester) async {
      await pumpBarOverScene(tester);
      final label = _phoneTabs().first.getLabel();
      final ratio = await textContrastOverBackground(
        tester,
        area: find.text(label),
        textColor: kAccent,
        boundary: find.byKey(_kSceneKey),
      );
      // ignore: avoid_print
      print('glass tab bar contrast, active red "$label": $ratio');
      expect(ratio, greaterThanOrEqualTo(3.0));
    });
  });
}
