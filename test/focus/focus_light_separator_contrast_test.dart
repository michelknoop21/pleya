/// J10 on the light palette: the ring stays white, and the dark band outside
/// it is what a viewer sees on a white dialog or a light page.
///
/// A 1 px line at 55% ink was the whole indicator there, because the white
/// ring has 1.00:1 against a white dialog. These tests read the painted
/// pixels of a real confirm dialog, a button on the page and a player button
/// over black video, and ask two things of the band: at least 3:1 against the
/// surface it stands on (WCAG 2.2, 1.4.11), held over at least 2 logical
/// pixels (the perimeter thickness 2.4.13 measures a focus indicator by). On
/// the dark and OLED palettes there is no band and the ring is the indicator.
///
/// With `PLEYA_SHOT_DIR` set, every frame is kept as a 1920x1080 image.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/dialogs.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/video_controls/video_control_button.dart';

import '../test_helpers/focus_band.dart';
import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';

const _shot = ValueKey('shot');

/// The thickness a focus indicator has to hold its contrast over.
const _minThickness = 2.0;

const _sides = [AxisDirection.up, AxisDirection.right, AxisDirection.down, AxisDirection.left];

final _themes = [
  ('light', monoTheme(dark: false)),
  ('dark', monoTheme(dark: true)),
  ('oled', monoTheme(dark: true, oled: true)),
];

Widget _app(ThemeData theme, Widget home) => TranslationProvider(
  child: RepaintBoundary(
    key: _shot,
    // Around the app, as in `main.dart`: a dialog is a route beside `home`.
    child: InputModeTracker(
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: home),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _button(String label) => find.ancestor(of: find.text(label), matching: find.byType(FocusableButton)).first;

FocusNode _nodeOf(WidgetTester tester, Finder owner) =>
    tester.widget<Focus>(find.descendant(of: owner, matching: find.byType(Focus)).first).focusNode!;

void main() {
  setUpAll(loadAppFontsForGoldens);

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  /// Apple TV: 1920x1080 laid out at 1.85 (DEC-028).
  Future<void> tv(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.85;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.nl));
    addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
  }

  Future<void> openDialog(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(
      _app(
        theme,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showConfirmDialog(
                  context,
                  title: t.profiles.removePin,
                  message: t.profiles.deleteProfileButton,
                  confirmText: t.common.confirm,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(_nodeOf(tester, _button(t.common.cancel)).hasFocus, isTrue, reason: 'the dialog opens on Cancel');
  }

  for (final (name, theme) in _themes) {
    testWidgets('confirm dialog on $name: the focus indicator around both actions', (tester) async {
      await tv(tester);
      await openDialog(tester, theme);
      final surface = theme.extension<MonoTokens>()!.surface;

      // Both frames first, so a run on the old values still keeps both images.
      final frames = <(String, String, FocusFrame, Rect)>[];
      for (final (state, label) in [('secondary', t.common.cancel), ('primary', t.common.confirm)]) {
        if (state == 'primary') {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await _settle(tester);
        }
        expect(_nodeOf(tester, _button(label)).hasFocus, isTrue, reason: 'focus on "$label"');
        final frame = await FocusFrame.capture(tester, find.byKey(_shot));
        await frame.keep(tester, 'dialog-$name-focus-$state-1920x1080');
        frames.add((state, label, frame, tester.getRect(_button(label))));
      }

      for (final (state, _, frame, box) in frames) {
        for (final side in _sides) {
          // The two actions stand 8 px apart: start the scan short of the other one.
          final band = frame.band(box, side, outside: 5);
          debugPrint('measure dialog $name $state ${side.name}: $band');
          expect(contrastRatio(band.surface, surface), lessThan(1.05), reason: 'the scan starts on the dialog surface');
          expect(band.contrast, greaterThanOrEqualTo(3), reason: 'indicator against the dialog, $name $state $side');
          expect(
            band.thickness,
            greaterThanOrEqualTo(_minThickness),
            reason: 'indicator thickness, $name $state $side',
          );
          if (name == 'light') {
            // The band is the indicator; the ring inside it is still white.
            expect(contrastRatio(band.inner, Colors.white), lessThan(1.05), reason: 'white ring inside the band');
          } else {
            // No band: the white ring itself is the indicator.
            expect(contrastRatio(band.color, Colors.white), lessThan(1.05), reason: 'the indicator is the white ring');
          }
        }
      }
    });
  }

  testWidgets('a button on the light page: the band against the page background', (tester) async {
    await tv(tester);
    final theme = monoTheme(dark: false);
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      _app(
        theme,
        Scaffold(
          body: Center(
            child: FocusableButton(
              focusNode: node,
              onPressed: () {},
              child: OutlinedButton(onPressed: () {}, child: const Text('Meer informatie')),
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await _settle(tester);

    final frame = await FocusFrame.capture(tester, find.byKey(_shot));
    await frame.keep(tester, 'page-light-focus-1920x1080');
    final box = tester.getRect(find.byType(FocusableButton));
    for (final side in _sides) {
      final band = frame.band(box, side);
      debugPrint('measure page light ${side.name}: $band');
      expect(contrastRatio(band.surface, theme.scaffoldBackgroundColor), lessThan(1.05));
      expect(band.contrast, greaterThanOrEqualTo(3), reason: 'indicator against the page, $side');
      expect(band.thickness, greaterThanOrEqualTo(_minThickness), reason: 'indicator thickness, $side');
      expect(contrastRatio(band.inner, Colors.white), lessThan(1.05), reason: 'white ring inside the band');
    }
  });

  // The player has no theme of its own: its controls stand on the video, which
  // is dark whatever palette the app is in. A dark ring would vanish there, so
  // the ring stays white in every palette. The Light band is the theme ink,
  // so on video it can only darken the edge of the white focus glow next to
  // the ring; past its own width the frame is the Dark frame.
  testWidgets('player button over black video: the same white ring on every palette', (tester) async {
    await tv(tester);
    final frames = <String, (FocusFrame, Rect)>{};
    for (final (name, theme) in _themes) {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        _app(
          theme,
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: VideoControlButton(
                key: ValueKey(name),
                icon: Symbols.play_arrow_rounded,
                onPressed: () {},
                focusNode: node,
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await _settle(tester);
      expect(node.hasFocus, isTrue);
      final frame = await FocusFrame.capture(tester, find.byKey(_shot));
      await frame.keep(tester, 'player-$name-focus-1920x1080');
      frames[name] = (frame, tester.getRect(find.byType(FocusableWrapper)));
    }

    final (dark, box) = frames['dark']!;
    for (final name in ['light', 'oled']) {
      final (frame, other) = frames[name]!;
      expect(other, box, reason: 'the button does not move');
      for (final side in _sides) {
        final normal = switch (side) {
          AxisDirection.up => const Offset(0, -1),
          AxisDirection.down => const Offset(0, 1),
          AxisDirection.left => const Offset(-1, 0),
          AxisDirection.right => const Offset(1, 0),
        };
        final edge = switch (side) {
          AxisDirection.up => box.topCenter,
          AxisDirection.down => box.bottomCenter,
          AxisDirection.left => box.centerLeft,
          AxisDirection.right => box.centerRight,
        };
        // The ring: the same white run, of the same width, as on Dark.
        final ring = frame.band(box, side, outside: 8, inside: 8);
        final darkRing = dark.band(box, side, outside: 8, inside: 8);
        debugPrint('measure player $name ${side.name}: $ring; dark: $darkRing');
        expect(contrastRatio(ring.color, Colors.white), lessThan(1.05), reason: 'white ring on $name, $side');
        expect(ring.thickness, darkRing.thickness, reason: 'ring width on $name, $side');
        // Outside it: the band is the theme ink (#111111), at most 1.11:1
        // against black video, so it cannot draw the eye.
        // The focus scale (1.05) puts the ring's outer edge 1 px outside the
        // laid-out box; start past it and its anti-aliased pixel.
        for (var d = 2.0; d < 4; d += 0.5) {
          final here = frame.at(edge + normal * d), there = dark.at(edge + normal * d);
          expect(
            contrastRatio(here, there),
            lessThan(1.2),
            reason: '$d px out: ${hexOf(here)} against ${hexOf(there)}',
          );
        }
        // Past the band, everything is the Dark frame.
        for (final d in [5.0, 8.0, 16.0]) {
          expect(frame.at(edge + normal * d), dark.at(edge + normal * d), reason: '$name, $side, $d px out');
        }
      }
    }
  });

  // The decoration itself, without a widget around it: Dark and OLED carry a
  // transparent separator, so nothing this file measures can change there.
  for (final (name, theme) in _themes) {
    testWidgets('on $name the ring is white and the band is ${name == 'light' ? 'ink' : 'absent'}', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final rings = [
        FocusTheme.focusDecoration(ctx, isFocused: true).shape,
        FocusTheme.shapeFocusRing(ctx, isFocused: true, shape: const StadiumBorder()).shape,
      ].cast<FocusRingBorder>();
      for (final ring in rings) {
        expect(ring.ring.color, Colors.white);
        expect(ring.ring.width, FocusTheme.focusBorderWidth);
        if (name == 'light') {
          expect(ring.separator.color, theme.extension<MonoTokens>()!.text);
          expect(ring.separator.color.a, 1.0);
          expect(ring.separator.width, FocusTheme.focusBorderWidth);
        } else {
          expect(ring.separator.color.a, 0.0);
        }
      }
    });
  }
}
