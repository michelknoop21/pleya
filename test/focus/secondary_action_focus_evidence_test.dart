/// Which button has the focus, on four real surfaces where a text or outlined
/// button sits next to a filled one: the confirm dialog, sign-in, the Seerr
/// settings and the profile page.
///
/// A resting secondary button is labelled in the text colour and dimmed to
/// 60%; the focused one is the brand red at full strength, inside the white
/// ring. This file measures both from the painted pixels and, with
/// `PLEYA_SHOT_DIR` set, keeps every frame as a 1920x1080 image. It asserts
/// where the focus is and that the resting label stays readable on the dark
/// themes. Whether red-in-a-ring reads as "focused" is a design judgement the
/// numbers only inform, so nothing is asserted about the focused colour.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/screens/auth_screen.dart';
import 'package:pleya/screens/profile/profile_detail_screen.dart';
import 'package:pleya/screens/settings/seerr_settings_screen.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/dialogs.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/notice_layer.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/seerr_fake.dart';

const _physical = Size(1920, 1080);

/// Apple TV lays out at 1920x1080 / 1.85 (DEC-028); Android TV at 2.0.
const _appleTvScale = 1.85;
const _androidTvScale = 2.0;

final _shot = GlobalKey();

double _ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// One frame at 1920x1080, as the pixels that were painted.
class _Frame {
  _Frame(this.scale, this.width, this.rgba, this.png);

  final double scale;
  final int width;
  final Uint8List rgba;
  final Uint8List png;

  static Future<_Frame> of(WidgetTester tester) async {
    final scale = tester.view.devicePixelRatio;
    final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final frame = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: scale);
      final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final frame = _Frame(scale, image.width, rgba, png);
      image.dispose();
      return frame;
    });
    return frame!;
  }

  Color _at(double x, double y) {
    final i = ((y * scale).round() * width + (x * scale).round()) * 4;
    return Color(0xFF000000 | rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2]);
  }

  /// What the glyphs in [rect] stand on (the pixel just left of them) and
  /// their ink: the pixel furthest from that, the solid core of a stroke.
  ({Color background, Color ink}) label(Rect rect) {
    final background = _at(rect.left - 3, rect.center.dy);
    var ink = background;
    for (var y = rect.top + 1; y < rect.bottom - 1; y += 1 / scale) {
      for (var x = rect.left + 1; x < rect.right - 1; x += 1 / scale) {
        final pixel = _at(x, y);
        if (_ratio(pixel, background) > _ratio(ink, background)) ink = pixel;
      }
    }
    return (background: background, ink: ink);
  }

  /// The ring on the left edge of [button] and what lies just outside it.
  ({Color ring, Color outside}) ring(Rect button) =>
      (ring: _at(button.left + 1.2, button.center.dy), outside: _at(button.left - 4, button.center.dy));
}

Finder _button(String label) => find.ancestor(of: find.text(label), matching: find.byType(FocusableButton)).first;

Finder _label(String label) => find.descendant(of: _button(label), matching: find.text(label));

bool _hasFocus(WidgetTester tester, String label) => seerrHasFocus(tester, _button(label));

/// Moves the focus to the button labelled [label], the way a `requestFocus`
/// from the screen itself would. The app is in D-pad mode on a TV from the
/// first frame, so the ring and the dim follow.
Future<void> _focus(WidgetTester tester, String label) async {
  final element = tester.element(find.descendant(of: _button(label), matching: find.byType(Focus)).first);
  FocusManager.instance.rootScope.descendants.singleWhere((node) => node.context == element).requestFocus();
  await _settle(tester);
  expect(_hasFocus(tester, label), isTrue, reason: 'focus on "$label"');
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _app(ThemeData theme, Widget home, {List<InheritedProvider<dynamic>> providers = const []}) {
  final app = RepaintBoundary(
    key: _shot,
    // Around the app, as in `main.dart`: a dialog is a route beside `home`.
    child: InputModeTracker(
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: theme, builder: noticeLayer, home: home),
    ),
  );
  return TranslationProvider(
    child: providers.isEmpty ? app : MultiProvider(providers: providers, child: app),
  );
}

/// Measures the secondary button [secondary] focused and at rest (with the
/// focus on [primary]), prints both and keeps the two frames.
Future<void> _measure(
  WidgetTester tester, {
  required String group,
  required String theme,
  required String secondary,
  required String primary,
  required bool dark,
}) async {
  Future<void> keep(_Frame frame, String focus) async {
    if (Platform.environment['PLEYA_SHOT_DIR'] case final dir?) {
      await tester.runAsync(
        () => File('$dir/focus-$group-$theme-ring-on-$focus-1920x1080.png').writeAsBytes(frame.png),
      );
    }
  }

  // Real time for bundled images (the logo) to decode before the first frame is kept.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await _focus(tester, secondary);
  final focused = await _Frame.of(tester);
  await keep(focused, 'secondary');
  final inRing = focused.label(tester.getRect(_label(secondary)));
  final ring = focused.ring(tester.getRect(_button(secondary)));

  await _focus(tester, primary);
  final other = await _Frame.of(tester);
  await keep(other, 'primary');
  final resting = other.label(tester.getRect(_label(secondary)));
  final primaryRing = other.ring(tester.getRect(_button(primary)));

  final focus = _ratio(inRing.ink, inRing.background);
  final rest = _ratio(resting.ink, resting.background);
  debugPrint(
    'evidence $group $theme "$secondary": '
    'rest ${rest.toStringAsFixed(2)}:1 (ink ${_hex(resting.ink)} on ${_hex(resting.background)}), '
    'focus ${focus.toStringAsFixed(2)}:1 (ink ${_hex(inRing.ink)} on ${_hex(inRing.background)}), '
    'focus against rest ink ${_ratio(inRing.ink, resting.ink).toStringAsFixed(2)}:1, '
    'ring ${_hex(ring.ring)} against ${_hex(ring.outside)} ${_ratio(ring.ring, ring.outside).toStringAsFixed(2)}:1, '
    'ring on primary ${_hex(primaryRing.ring)} against ${_hex(primaryRing.outside)} '
    '${_ratio(primaryRing.ring, primaryRing.outside).toStringAsFixed(2)}:1',
  );

  expect(inRing.ink, isNot(resting.ink), reason: 'focused and resting label differ');
  if (dark) expect(rest, greaterThanOrEqualTo(4.5), reason: 'resting "$secondary" on $theme');
}

void main() {
  final darkThemes = [('dark', monoTheme(dark: true)), ('oled', monoTheme(dark: true, oled: true))];

  setUpAll(loadAppFontsForGoldens);

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  Future<void> tv(WidgetTester tester, {bool apple = true}) async {
    if (apple) {
      TvDetectionService.debugSetAppleTVOverride(true);
    } else {
      TvDetectionService.debugSetTVOverride(true);
    }
    addTearDown(() {
      TvDetectionService.debugSetAppleTVOverride(null);
      TvDetectionService.debugSetTVOverride(null);
    });
    await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.nl));
    addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
    tester.view.physicalSize = _physical;
    tester.view.devicePixelRatio = apple ? _appleTvScale : _androidTvScale;
    addTearDown(tester.view.reset);
  }

  for (final (name, theme) in [...darkThemes, ('light', monoTheme(dark: false))]) {
    testWidgets('confirm dialog on $name: Cancel next to the filled confirm', (tester) async {
      await tv(tester);
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
      expect(_hasFocus(tester, t.common.cancel), isTrue, reason: 'the dialog opens on Cancel');

      // The remote walks the two actions.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(_hasFocus(tester, t.common.confirm), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _settle(tester);
      expect(_hasFocus(tester, t.common.cancel), isTrue);

      await _measure(
        tester,
        group: 'dialog',
        theme: name,
        secondary: t.common.cancel,
        primary: t.common.confirm,
        dark: name != 'light',
      );
    });
  }

  for (final (name, theme) in darkThemes) {
    testWidgets('sign-in on $name (Android TV): Use browser under the two filled backends', (tester) async {
      await tv(tester, apple: false);
      Future<PlexAuthService> service() async => PlexAuthService.forTesting(
        http: MediaServerHttpClient(client: MockClient((_) async => http.Response('{}', 200))),
      );
      await tester.pumpWidget(
        _app(theme, AuthScreen(plexPinAuthServiceFactory: service, plexConnectAuthServiceFactory: service)),
      );
      await _settle(tester);

      await _measure(
        tester,
        group: 'signin',
        theme: name,
        secondary: t.auth.useBrowser,
        primary: t.auth.connectToJellyfin,
        dark: true,
      );
    });

    testWidgets('Seerr settings on $name: Disconnect under the filled requests button', (tester) async {
      await tv(tester);
      final fake = FakeSeerr();
      final provider = await seerrProvider(fake);
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        _app(
          theme,
          const SeerrSettingsScreen(),
          providers: [ChangeNotifierProvider<SeerrProvider>.value(value: provider)],
        ),
      );
      await _settle(tester);

      await _measure(
        tester,
        group: 'settings',
        theme: name,
        secondary: t.seerr.disconnect,
        primary: t.seerr.myRequests,
        dark: true,
      );
    });

    testWidgets('profile page on $name: Change PIN and the filled Save', (tester) async {
      await tv(tester);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final profile = Profile.local(
        id: 'local-owner',
        displayName: 'Sanne',
        pinHash: 'synthetic',
        createdAt: DateTime(2026, 1, 1),
      );
      final connections = _NoConnections(db);
      final profileConnections = _NoProfileConnections(db);
      // Outside the fake clock: the preferences read never completes inside it.
      final storage = await tester.runAsync(StorageService.getInstance);
      final plexHome = PlexHomeService(
        connections: connections,
        profileConnections: profileConnections,
        storage: storage!,
        plexHomeUserFetcher: (_) async => const [],
      );
      addTearDown(() async {
        await plexHome.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        _app(
          theme,
          ProfileDetailScreen(profile: profile),
          providers: [
            Provider<ProfileRegistry>.value(value: ProfileRegistry(db)),
            Provider<ProfileConnectionRegistry>.value(value: profileConnections),
            Provider<ConnectionRegistry>.value(value: connections),
            Provider<PlexHomeService>.value(value: plexHome),
          ],
        ),
      );
      await _settle(tester);
      // Save is only a live button once the name differs.
      await tester.enterText(find.byType(EditableText).first, 'Sanne B');
      await _settle(tester);

      await _measure(
        tester,
        group: 'profile',
        theme: name,
        secondary: t.profiles.changePin,
        primary: t.common.save,
        dark: true,
      );
    });
  }
}

class _NoConnections extends ConnectionRegistry {
  _NoConnections(super.db);

  @override
  Future<List<Connection>> list() async => const [];
}

class _NoProfileConnections extends ProfileConnectionRegistry {
  _NoProfileConnections(super.db);

  @override
  Stream<List<ProfileConnection>> watchForProfile(String profileId) => Stream.value(const []);
}
