import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fase-0 golden-test infrastructure for Pleya Unified TV 2026
/// (docs/tvos-unified-experience.md hoofdstuk 27, 29).
///
/// These goldens run on Linux, matching CI, and catch geometry, composition
/// and layout regressions on **existing** surfaces. Per hoofdstuk 29, this
/// harness is deliberately **not** pixel truth for tvOS: font rasterization,
/// render scale, HDR and platform rendering all differ from a real Apple TV.
/// A green golden here never replaces the mandatory Mac/Apple TV
/// verification pass; it only stops an accidental layout change on this
/// platform from going unnoticed.
///
/// Fase 0 baselines **existing** surfaces only — no new screen is golden-ed
/// ahead of the fase that builds it (hoofdstuk 27).
///
/// To (re)generate golden files after an intentional visual change, run:
/// `flutter test --update-goldens test/goldens/`

bool _fontsLoaded = false;

/// Loads the app's real bundled fonts (Inter, ArchivoBlack) into the test
/// binding so goldens render actual UI typography instead of the fallback
/// test font. Idempotent and cheap to call from every golden test's
/// `setUpAll` — later calls after the first are a no-op.
Future<void> loadAppFontsForGoldens() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  const fontsByFamily = {
    'Inter': ['assets/fonts/Inter-Regular.otf', 'assets/fonts/Inter-Medium.otf', 'assets/fonts/Inter-Bold.otf'],
    'ArchivoBlack': ['assets/fonts/ArchivoBlack-Regular.ttf'],
  };
  for (final entry in fontsByFamily.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}

/// tvOS logical canvas per DEC-028 (`_AppleTvScale._scale = 1.85`):
/// 1920x1080 / 1.85, rounded.
const kTvGoldenSurfaceSize = Size(1038, 584);

/// Fixes the test surface to [size] at device pixel ratio 1.0 for the
/// duration of the current test, restoring the previous values on teardown.
/// Call before `pumpWidget` so the first frame already renders at the fixed
/// size — a golden compares raster output, so an inconsistent surface size
/// between runs is a guaranteed false diff.
void setGoldenSurfaceSize(WidgetTester tester, {Size size = kTvGoldenSurfaceSize}) {
  final previousSize = tester.view.physicalSize;
  final previousRatio = tester.view.devicePixelRatio;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.physicalSize = previousSize;
    tester.view.devicePixelRatio = previousRatio;
  });
}

/// Thin, documented wrapper over `matchesGoldenFile` so every golden test in
/// this suite names its files the same way: `test/goldens/<name>.png`, next
/// to the test file that produced them (the default `LocalFileComparator`
/// resolves golden paths relative to the test file's own directory).
Future<void> expectMatchesGolden(Finder finder, String name) async {
  await expectLater(finder, matchesGoldenFile('$name.png'));
}
