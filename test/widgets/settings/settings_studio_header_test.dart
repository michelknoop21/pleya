/// A-24 (Apple TV+ Studio on iOS): the large header of the settings pages.
///
/// It draws its artwork from what [DiscoverProvider] already holds and falls
/// back to the brand panel without one, fits a long title at 320 pt, and
/// leaves the pinned bar without a title until it has scrolled under it. On
/// TV a settings page keeps the plain bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/optimized_media_image.dart';
import 'package:pleya/widgets/pleya_logo.dart';
import 'package:pleya/widgets/setting_tile.dart';
import 'package:pleya/widgets/settings/settings_studio_header.dart';
import 'package:pleya/widgets/settings_page.dart';
import 'package:pleya/widgets/settings_section.dart';
import 'package:provider/provider.dart';

class _Discover extends ChangeNotifier implements DiscoverProvider {
  _Discover({this.onDeckItems = const [], this.latest = const []});

  final List<MediaItem> onDeckItems;
  final List<MediaItem> latest;

  @override
  List<MediaItem> get onDeck => onDeckItems;

  @override
  List<MediaItem> get latestMovies => latest;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _film(String id, {String? art}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: id, serverId: 'nas', artPath: art);

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    OptimizedMediaImage.debugImageBuilder = (context, path) => SizedBox.expand(key: ValueKey('art:$path'));
  });
  tearDown(() {
    OptimizedMediaImage.debugImageBuilder = null;
  });

  Future<void> pump(WidgetTester tester, Widget child, {DiscoverProvider? discover, double width = 375}) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = TranslationProvider(
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: monoTheme(dark: true), home: child),
    );
    await tester.pumpWidget(
      discover == null ? app : ChangeNotifierProvider<DiscoverProvider>.value(value: discover, child: app),
    );
    await tester.pump();
  }

  Widget page({String title = 'Weergave', int rows = 3}) => SettingsPage(
    title: Text(title),
    children: [
      const SettingsSectionHeader('Scherm'),
      for (var i = 0; i < rows; i++)
        SettingNavigationTile(icon: Symbols.palette_rounded, title: 'Rij $i', onTap: () {}),
    ],
  );

  group('artwork', () {
    testWidgets('the first loaded item with a backdrop fills the panel', (tester) async {
      final discover = _Discover(
        onDeckItems: [
          _film('zonder'),
          _film('met', art: '/library/metadata/7/art/1'),
        ],
        latest: [_film('later', art: '/library/metadata/9/art/1')],
      );
      await pump(
        tester,
        Scaffold(body: SettingsStudioHeader(title: 'Instellingen')),
        discover: discover,
      );

      expect(find.byKey(const ValueKey('art:/library/metadata/7/art/1')), findsOneWidget);
      expect(find.byKey(const ValueKey('art:/library/metadata/9/art/1')), findsNothing);
    });

    testWidgets('without a provider the brand panel stands in', (tester) async {
      await pump(tester, Scaffold(body: SettingsStudioHeader(title: 'Instellingen')));

      expect(find.byType(OptimizedMediaImage), findsNothing);
      expect(find.byType(PleyaLogo), findsOneWidget);
      expect(find.text('PLEYA · ${t.settings.title.toUpperCase()}'), findsOneWidget);
    });

    testWidgets('a provider with no backdrop anywhere also gets the brand panel', (tester) async {
      await pump(
        tester,
        Scaffold(body: SettingsStudioHeader(title: 'Instellingen')),
        discover: _Discover(onDeckItems: [_film('a')], latest: [_film('b')]),
      );
      expect(find.byType(OptimizedMediaImage), findsNothing);
      expect(find.byType(PleyaLogo), findsOneWidget);
    });
  });

  group('settings page off TV', () {
    testWidgets('opens on the Studio header with the bar title left out', (tester) async {
      await pump(tester, page());

      expect(find.byType(SettingsStudioHeader), findsOneWidget);
      expect(find.text('Weergave'), findsOneWidget, reason: 'one title at rest: the large one');
      final big = tester.getRect(find.text('Weergave'));
      expect(big.top, greaterThanOrEqualTo(kToolbarHeight), reason: 'below the pinned bar, not in it');
    });

    testWidgets('the bar shows its title once the header has scrolled under it', (tester) async {
      await pump(tester, page(rows: 20));
      final tk = tokens(tester.element(find.byType(SettingsStudioHeader)));
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
        settingsStudioWashTop(tk),
        reason: 'the bar carries the header wash while the header is in view',
      );

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor, isNot(settingsStudioWashTop(tk)));

      final inBar = find.descendant(of: find.byType(AppBar), matching: find.text('Weergave'));
      expect(inBar, findsOneWidget);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Weergave')), findsNothing);
    });

    testWidgets('a long title fits a 320 pt phone without overflow or a clipped word', (tester) async {
      await pump(tester, page(title: 'Taal en ondertitels'), width: 320);

      expect(tester.takeException(), isNull);
      final title = tester.renderObject<RenderParagraph>(find.text('Taal en ondertitels'));
      expect(title.didExceedMaxLines, isFalse);
      final rect = tester.getRect(find.text('Taal en ondertitels'));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      final eyebrow = tester.getRect(find.text('PLEYA · ${t.settings.title.toUpperCase()}'));
      expect(eyebrow.top, greaterThanOrEqualTo(rect.bottom), reason: 'the eyebrow sits under the title');
    });
  });

  group('on TV', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    testWidgets('a settings page keeps the plain bar', (tester) async {
      await pump(tester, page());
      expect(find.byType(SettingsStudioHeader), findsNothing);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Weergave')), findsOneWidget);
    });
  });
}
