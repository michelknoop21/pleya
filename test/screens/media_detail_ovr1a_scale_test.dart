import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../test_helpers/notice_layer.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/profile_navigation.dart';

/// OVR1a on the detail surface (DEC-109): the ten-foot scale is a property of
/// the panel a viewer sits in front of, not of whatever content box a nested
/// TV route happens to receive. `media_detail_screen.dart` used to read
/// `TvLayoutConstants.scaleForSize` off its own (possibly shell-shortened)
/// content box; this pins it to `TvLayoutConstants.scaleOf`, which reads
/// `TvDisplayMetrics` — the full window a real `TvNestedSurface` publishes —
/// before ever falling back to `MediaQuery`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(resetNotices);

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('the fallback title scales off the published panel size, not a shorter nested content box', (
    tester,
  ) async {
    await SettingsService.getInstance();

    const title = 'A Fallback Title Long Enough To Prove The Point';
    final movie = MediaItem(id: 'movie_1', backend: MediaBackend.jellyfin, kind: MediaKind.movie, title: title);

    // The panel (`TvDisplayMetrics`) sits exactly at the reference height, so
    // its scale is 1.0; the nested content box a real `TvNestedSurface` would
    // hand this screen — shorter by the topnav band — floors to 0.85. If both
    // landed on the same number this test would prove nothing, which is
    // exactly the failure mode of testing this without a real nested shell.
    // 900 is still generous room for the foreground content, unlike a tiny
    // box that would starve the reveal entirely.
    const panelSize = Size(1038, 1080);
    const nestedBoxSize = Size(1038, 900);
    final panelScale = TvLayoutConstants.scaleForSize(panelSize);
    final boxScale = TvLayoutConstants.scaleForSize(nestedBoxSize);
    expect(panelScale, isNot(closeTo(boxScale, 0.001)));

    tester.view.physicalSize = panelSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: monoTheme(dark: true),
          home: withProfileNavigationScope(
            // Mirrors what `TvNestedSurface` actually does: `TvDisplayMetrics`
            // published around the full panel, a `MediaQuery` override inside
            // it narrowing what the nested route itself sees to its (shorter)
            // content box.
            child: TvDisplayMetrics(
              size: panelSize,
              child: TvNestedRouteScope(
                dismiss: ([_]) {},
                markResult: (_) {},
                child: MediaQuery(
                  data: MediaQueryData(size: nestedBoxSize),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox.fromSize(
                      size: nestedBoxSize,
                      child: MediaDetailScreen(metadata: movie),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final titleText = tester.widget<Text>(find.text(title));
    expect(titleText.style?.fontSize, isNotNull);
    expect(titleText.style!.fontSize, closeTo(56 * panelScale, 0.05));
  });
}
