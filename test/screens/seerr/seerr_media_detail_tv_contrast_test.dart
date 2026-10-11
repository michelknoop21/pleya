/// The resting actions on the Seerr title page, read from the pixels a TV
/// would get. A resting action is dimmed to 60% by [FocusableButton]; with
/// Material's default label colour (the brand red) that left about 2:1 on the
/// page background. The bar is WCAG AA for text, 4.5:1.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_media.dart';
import 'package:pleya/screens/seerr/seerr_media_detail_screen.dart';
import 'package:pleya/services/companion_remote/companion_remote_receiver.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/seerr_fake.dart';

Finder _action(String id) => seerrNode(AutomationIds.requestsDetailAction, id);

Finder _label(String id) => find.descendant(of: _action(id), matching: find.byType(Text));

double _luminance(Color c) => c.computeLuminance();

double _ratio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

/// One frame of the whole screen, as the pixels that were painted.
class _Frame {
  _Frame(this.width, this.rgba, this.png);

  final int width;
  final Uint8List rgba;
  final Uint8List png;

  static Future<_Frame> of(WidgetTester tester) async {
    final frame = await tester.runAsync(() async {
      final image = await captureImage(tester.element(find.byType(SeerrMediaDetailScreen)));
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final frame = _Frame(image.width, rgba, png);
      image.dispose();
      return frame;
    });
    return frame!;
  }

  Color _at(int x, int y) {
    final i = (y * width + x) * 4;
    return Color(0xFF000000 | rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2]);
  }

  /// What the glyphs in [rect] stand on (the pixel just left of them, in the
  /// gap after the icon) and their ink: the pixel furthest from that, which is
  /// the solid core of a stroke and not its anti-aliased edge.
  ({Color background, Color ink}) read(Rect rect) {
    final background = _at(rect.left.floor() - 3, rect.center.dy.round());
    var ink = background;
    for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
      for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
        final pixel = _at(x, y);
        if (_ratio(pixel, background) > _ratio(ink, background)) ink = pixel;
      }
    }
    return (background: background, ink: ink);
  }
}

void main() {
  const fourK = SeerrPermission.request | SeerrPermission.request4kMovie;
  late FakeSeerr fake;

  setUpAll(loadAppFontsForGoldens);

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    fake = FakeSeerr()
      ..on('GET /movie/603/recommendations', {'results': []})
      ..on('GET /service/radarr', [
        {'id': 1, 'name': 'HD', 'is4k': false, 'isDefault': true},
        {'id': 2, 'name': '4K', 'is4k': true, 'isDefault': true},
      ])
      ..on('GET /movie/603', {
        'id': 603,
        'title': 'Glacier Run',
        'overview': 'A courier crosses the ice field before the thaw.',
        'mediaInfo': {'status': 5, 'requests': <Object>[]},
      });
  });

  /// The title page of an available film on a 1920x1080 TV: search in library
  /// (primary, focused), refresh status, request in 4K.
  Future<void> open(WidgetTester tester, ThemeData theme) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    CompanionRemoteReceiver.instance.onSearchAction = (_) {};
    addTearDown(() => CompanionRemoteReceiver.instance.onSearchAction = null);
    await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.nl));
    addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = await seerrProvider(fake, permissions: fourK);
    addTearDown(provider.dispose);
    await pumpSeerr(
      tester,
      provider,
      const SeerrMediaDetailScreen(
        media: SeerrMedia(tmdbId: 603, mediaType: 'movie', title: 'Glacier Run', year: '2024'),
      ),
      host: false,
      theme: theme,
    );
    await seerrSettle(tester);
    await tester.pumpAndSettle();
  }

  for (final (name, theme) in [('dark', monoTheme(dark: true)), ('oled', monoTheme(dark: true, oled: true))]) {
    testWidgets('a resting action reads at 4.5:1 or better on the $name theme', (tester) async {
      await open(tester, theme);
      expect(seerrHasFocus(tester, _action('search')), isTrue);

      final frame = await _Frame.of(tester);
      // Set PLEYA_SHOT_DIR to keep the frame as an image; nothing is written otherwise.
      if (Platform.environment['PLEYA_SHOT_DIR'] case final dir?) {
        final label = Platform.environment['PLEYA_SHOT_LABEL'] ?? 'shot';
        await tester.runAsync(() => File('$dir/$label-$name-1920x1080.png').writeAsBytes(frame.png));
      }
      for (final id in ['refresh', 'request4k']) {
        final text = frame.read(tester.getRect(_label(id)));
        final ratio = _ratio(text.ink, text.background);
        debugPrint('contrast $name $id: ${ratio.toStringAsFixed(2)}:1 (ink ${text.ink}, on ${text.background})');
        expect(ratio, greaterThanOrEqualTo(4.5), reason: 'resting label "$id" on the $name theme');
      }

      // The primary action in the ring is what it was: page background ink on the text colour.
      final primary = frame.read(tester.getRect(_label('search')));
      expect(primary.background, theme.colorScheme.onSurface);
      expect(primary.ink, theme.scaffoldBackgroundColor);
    });
  }

  testWidgets('the remote walks the actions in the same order, and the action in the ring keeps its colour', (
    tester,
  ) async {
    await open(tester, monoTheme(dark: true, oled: true));

    String focused() => ['search', 'refresh', 'request4k'].singleWhere((id) => seerrHasFocus(tester, _action(id)));
    Future<String> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      return focused();
    }

    expect(focused(), 'search');
    expect(await press(LogicalKeyboardKey.arrowRight), 'refresh');

    final ring = (await _Frame.of(tester)).read(tester.getRect(_label('refresh')));
    expect(ring.ink, kAccent, reason: 'the focused secondary action keeps the label colour it had');

    expect(await press(LogicalKeyboardKey.arrowRight), 'request4k');
    expect(await press(LogicalKeyboardKey.arrowRight), 'request4k', reason: 'the row ends here');
    expect(await press(LogicalKeyboardKey.arrowLeft), 'refresh');
    expect(await press(LogicalKeyboardKey.arrowLeft), 'search');
  });
}
