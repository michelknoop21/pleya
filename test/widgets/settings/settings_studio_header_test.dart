/// A-24 (Apple TV+ Studio on iOS): the large header of the settings pages.
///
/// It draws its artwork from what [DiscoverProvider] already holds and falls
/// back to the brand panel without one, fits a long title at 320 pt, and
/// leaves the pinned bar without a title until it has scrolled under it. On
/// TV a settings page keeps the plain bar.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/theme/mono_theme.dart';
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

final _iPhone = TargetPlatformVariant.only(TargetPlatform.iOS);

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    OptimizedMediaImage.debugImageBuilder = (context, path) => SizedBox.expand(key: ValueKey('art:$path'));
  });
  tearDown(() {
    OptimizedMediaImage.debugImageBuilder = null;
  });

  /// An iPhone-sized view at 3x, so `PlatformDetector.isPhone` reads it as a
  /// phone; [width] and [height] are in points. [dpr] 2 with an iPad size
  /// reads as a tablet.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    DiscoverProvider? discover,
    double width = 375,
    double height = 700,
    double dpr = 3,
  }) async {
    tester.view.physicalSize = Size(width * dpr, height * dpr);
    tester.view.devicePixelRatio = dpr;
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

    testWidgets('a backdrop whose server has no client yet shows the brand panel, not a broken image', (tester) async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      final servers = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(servers.dispose);
      await pump(
        tester,
        ChangeNotifierProvider<MultiServerProvider>.value(
          value: servers,
          child: Scaffold(body: SettingsStudioHeader(title: 'Instellingen')),
        ),
        discover: _Discover(onDeckItems: [_film('met', art: '/library/metadata/7/art/1')]),
      );

      expect(find.byKey(const ValueKey('art:/library/metadata/7/art/1')), findsNothing);
      expect(find.byType(OptimizedMediaImage), findsNothing);
      expect(find.byType(PleyaLogo), findsOneWidget);
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

  group('settings page on an iPhone', () {
    testWidgets('opens on the Studio header, no bar above it and one title at rest', (tester) async {
      await pump(tester, page());

      expect(find.byType(SettingsStudioHeader), findsOneWidget);
      expect(find.byType(AppBar), findsNothing, reason: 'A-24b: the series has no bar above the header');
      expect(find.text('Weergave'), findsOneWidget, reason: 'one title at rest: the large one');
    }, variant: _iPhone);

    testWidgets('the compact bar takes the title once the header has scrolled under the status bar', (tester) async {
      await pump(tester, page(rows: 20));
      expect(find.byType(SettingsStudioBackButton), findsNothing, reason: 'a root page has nothing to go back to');

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      final inBar = find.descendant(of: find.byType(SettingsStudioCompactBar), matching: find.text('Weergave'));
      expect(inBar, findsOneWidget);
      expect(tester.getRect(inBar).top, lessThan(kSettingsStudioBarHeight + 1));

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(SettingsStudioCompactBar), matching: find.text('Weergave')), findsNothing);
    }, variant: _iPhone);

    testWidgets('a pushed page draws the back chevron on the line of its title, and it goes back', (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page())),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final back = find.byType(SettingsStudioBackButton);
      expect(back, findsOneWidget);
      final title = tester.getRect(find.text('Weergave'));
      final chevron = tester.getRect(back);
      expect(chevron.right, lessThanOrEqualTo(title.left), reason: 'the chevron precedes the title');
      expect((chevron.center.dy - title.center.dy).abs(), lessThan(4), reason: 'on the same line');
      expect(chevron.width, greaterThanOrEqualTo(44));
      expect(tester.getSemantics(back), matchesSemantics(isButton: true, hasTapAction: true, label: 'Back'));

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(SettingsStudioHeader), findsNothing);
    }, variant: _iPhone);

    testWidgets('only the page on top answers to settings.back', (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page())),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => page(title: 'Downloads'))));
      await tester.pumpAndSettle();

      final backIds = find.byWidgetPredicate(
        (w) => w is AutomationNode && w.id == AutomationIds.settingsBack,
        skipOffstage: false,
      );
      expect(backIds, findsOneWidget, reason: 'the page underneath keeps its chevron but not the id');
      expect(find.descendant(of: backIds, matching: find.byType(SettingsStudioBackButton)), findsOneWidget);
      expect(
        find.ancestor(of: backIds, matching: find.byType(SettingsStudioHeader)).evaluate().single.widget,
        isA<SettingsStudioHeader>().having((h) => h.title, 'title', 'Downloads'),
      );
    }, variant: _iPhone);

    testWidgets('the main page carries its section and tagline under the title', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: SettingsStudioHeader(
            title: 'Instellingen',
            section: 'Persoonlijk',
            tagline: 'Maak Pleya helemaal van jou.',
          ),
        ),
      );
      final eyebrow = tester.getRect(find.text('PLEYA · PERSOONLIJK'));
      final tagline = tester.getRect(find.text('Maak Pleya helemaal van jou.'));
      expect(eyebrow.top, greaterThan(tester.getRect(find.text('Instellingen')).bottom));
      expect(tagline.top, greaterThan(eyebrow.bottom));
    }, variant: _iPhone);

    testWidgets('the status bar ink follows the theme, light glyphs on dark and dark on light', (tester) async {
      await pump(tester, page());
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(region.value, SystemUiOverlayStyle.light);
    }, variant: _iPhone);

    // The test face is wide (every glyph one em), so these titles are short
    // stand-ins for the device's "Weergave" and "Bibliotheek & Home".
    testWidgets('a short title sits at the series size on one line', (tester) async {
      await pump(tester, page(title: 'Taal'));
      final title = find.text('Taal');
      expect(tester.widget<Text>(title).style!.fontSize, 28, reason: 'the series title, about 27 pt on 380 pt');
      expect(tester.getSize(title).height, lessThan(kSettingsStudioTitleSize * 1.6), reason: 'one line');
    }, variant: _iPhone);

    for (final width in [375.0, 320.0]) {
      testWidgets('the title never runs over the artwork (${width.toInt()} pt)', (tester) async {
        await pump(tester, page(title: 'Taal en tv'), width: width);
        final artLeft = width - math.min(width * kSettingsStudioArtFraction, kSettingsStudioMaxArtWidth);
        final title = tester.getRect(find.text('Taal en tv'));
        expect(title.right, lessThanOrEqualTo(artLeft - kSettingsStudioArtGap + 0.5));
        expect(tester.renderObject<RenderParagraph>(find.text('Taal en tv')).didExceedMaxLines, isFalse);
        final eyebrow = tester.getRect(find.text('PLEYA · ${t.settings.title.toUpperCase()}'));
        expect(eyebrow.right, lessThanOrEqualTo(artLeft));
      }, variant: _iPhone);
    }

    testWidgets('a long title fits a 320 pt phone without overflow or a clipped word', (tester) async {
      await pump(tester, page(title: 'Taal en tv'), width: 320);

      expect(tester.takeException(), isNull);
      final title = tester.renderObject<RenderParagraph>(find.text('Taal en tv'));
      expect(title.didExceedMaxLines, isFalse);
      final rect = tester.getRect(find.text('Taal en tv'));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      final eyebrow = tester.getRect(find.text('PLEYA · ${t.settings.title.toUpperCase()}'));
      expect(eyebrow.top, greaterThanOrEqualTo(rect.bottom), reason: 'the eyebrow sits under the title');
    }, variant: _iPhone);
  });

  group('settings page off the iPhone keeps the plain bar', () {
    testWidgets('on an iPad', (tester) async {
      await pump(tester, page(), width: 1024, height: 1366, dpr: 2);
      expect(find.byType(SettingsStudioHeader), findsNothing);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Weergave')), findsOneWidget);
    }, variant: _iPhone);

    testWidgets('on Android and desktop platforms', (tester) async {
      await pump(tester, page());
      expect(find.byType(SettingsStudioHeader), findsNothing);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Weergave')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('on macOS', (tester) async {
      await pump(tester, page());
      expect(find.byType(SettingsStudioHeader), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  group('on TV', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    testWidgets('a settings page keeps the plain bar', (tester) async {
      await pump(tester, page());
      expect(find.byType(SettingsStudioHeader), findsNothing);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Weergave')), findsOneWidget);
    }, variant: _iPhone);
  });
}
