// Visual evidence: Big P on iPhone (39 A to H) at 402x874 and on iPad (39 I)
// at 1180x820, with the app's fonts, over the 39 A mockup as Home. The header is the real one; the iOS
// keyboard is the mockup's, cut from 39 B. Skipped unless BIGP_SHOT_DIR is set:
//   BIGP_SHOT_DIR=/tmp/bigp flutter test test/screens/big_p/big_p_mobile_shots_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/big_p/big_p_detail_peek.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/screens/my_pleya_screen.dart';
import 'package:pleya/screens/search_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_keychain.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/big_p_rig.dart';
import 'package:pleya/widgets/mobile/mobile_page_header.dart';
import 'package:pleya/widgets/pleya_wordmark.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';
import '../../widgets/big_p/fake_assistant_controller.dart';
import 'big_p_mobile_fixtures.dart';

final _dir = Platform.environment['BIGP_SHOT_DIR'];
const _mockups = 'docs/assets/ios-unified/big-p-39';

Future<ui.Image> _image(String path) async {
  final bytes = File(path).readAsBytesSync();
  return (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
}

void main() {
  late ui.Image home;
  late ui.Image keys;
  late ui.Image detail;

  setUpAll(() async {
    if (_dir == null) return;
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
    home = await _image('$_mockups/39-a-gezichtsknop.png');
    keys = await _image('$_mockups/39-b-opgeroepen.png');
    detail = await _image('docs/assets/ios-unified/detail-2026/D-01-film.png');
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    FakeAssistantController c, {
    _Phone phone = _iPhone17Pro,
    bool keyboard = false,
    Future<void> Function(BigPMobileSession session)? before,
    void Function(FakeAssistantController c)? answer,
  }) async {
    tester.view.physicalSize = phone.size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final session = BigPMobileSession(c);
    addTearDown(session.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TranslationProvider(
          child: ChangeNotifierProvider<BigPMobileSession>.value(
            value: session,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    viewPadding: phone.safe,
                    padding: keyboard ? phone.safe.copyWith(bottom: 0) : phone.safe,
                    viewInsets: EdgeInsets.only(bottom: keyboard ? phone.keyboard : 0),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // No iPad Home without its balloon: black under the dim.
                      if (phone.size.width < 700)
                        RawImage(image: home, fit: BoxFit.cover, alignment: Alignment.topCenter),
                      if (phone.size.width >= 700) const ColoredBox(color: Colors.black),
                      // The real header over the mockup's.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: phone.safe.top,
                        height: 64,
                        child: ColoredBox(
                          color: Colors.black,
                          child: OverflowBox(
                            alignment: Alignment.bottomCenter,
                            maxHeight: 200,
                            child: Material(
                              type: MaterialType.transparency,
                              child: MobilePageHeader(onSearchTap: () {}, activeProfile: null),
                            ),
                          ),
                        ),
                      ),
                      const BigPMobileHost(),
                      if (keyboard)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: phone.keyboard,
                          child: ClipRect(
                            child: RawImage(image: keys, fit: BoxFit.fitWidth, alignment: Alignment.bottomCenter),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await precacheBigP(tester, boundary);
    await tester.pump(const Duration(milliseconds: 100));
    await before?.call(session);
    if (answer != null) {
      answer(c);
      c.emit();
    }
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await save(tester, boundary, name);
  }

  /// Task 9: a whole screen with Big P ready, on the 402 iPhone or [phone].
  Future<void> shootScreen(
    WidgetTester tester,
    String name,
    Widget home, {
    _Phone phone = _iPhone17Pro,
    List<SingleChildWidget> more = const [],
    Future<void> Function()? after,
  }) async {
    tester.view.physicalSize = phone.size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = shotController();
    final session = BigPMobileSession(c);
    addTearDown(session.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<AssistantController>.value(value: c),
              ChangeNotifierProvider<BigPMobileSession>.value(value: session),
              ...more,
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              // Inter for every style: the ones without a family fall back to the
              // test font's boxes here, the system font on a device.
              theme: () {
                final theme = monoTheme(dark: true);
                return theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Inter'));
              }(),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true, viewPadding: phone.safe, padding: phone.safe),
                  child: home,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await precacheBigP(tester, boundary);
    await tester.pumpAndSettle();
    await after?.call();
    await save(tester, boundary, name);
  }

  testWidgets('t9 My Pleya tile', skip: _dir == null, (tester) async {
    await _services(tester);
    await shootScreen(tester, 't9-mijn-pleya', MyPleyaScreen(onOpenTab: (_) {}));
  });

  /// Zoeken after [query] over two Dune films.
  Future<void> shootSearch(WidgetTester tester, String name, String query, {_Phone phone = _iPhone17Pro}) async {
    await _services(tester);
    final manager = MultiServerManager()
      ..debugRegisterClientForTesting(
        FakeSearchServer([
          for (final (id, title, year) in [('d1', 'Dune', 2021), ('d2', 'Dune: Part Two', 2024)])
            if (title.toLowerCase().contains(query))
              MediaItem(
                id: id,
                backend: MediaBackend.plex,
                kind: MediaKind.movie,
                title: title,
                year: year,
                serverId: 'nas',
                serverName: 'NAS',
              ),
        ]),
      );
    final servers = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(servers.dispose);
    final hidden = HiddenLibrariesProvider();
    addTearDown(hidden.dispose);
    final key = GlobalKey<State<SearchScreen>>();
    await shootScreen(
      tester,
      name,
      SearchScreen(key: key),
      phone: phone,
      more: [
        ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
        ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
      ],
      after: () async {
        (key.currentState! as SearchInputFocusable).setSearchQuery(query);
        (key.currentState! as Refreshable).refresh();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('t9 search row', skip: _dir == null, (tester) async => shootSearch(tester, 't9-zoeken', 'dune'));

  testWidgets(
    't9 search row, no results',
    skip: _dir == null,
    (tester) async => shootSearch(tester, 't9-zoeken-geen-resultaten', 'blade runner'),
  );

  testWidgets(
    't9 search row, iPad',
    skip: _dir == null,
    (tester) async => shootSearch(tester, 't9-zoeken-ipad', 'dune', phone: _iPad),
  );

  testWidgets('39-a face button', skip: _dir == null, (tester) async {
    final c = shotController();
    await shoot(tester, '39-a-gezichtsknop', c);
  });

  // Two seeds: the examples and the follow-ups differ per summon and answer.
  for (final seed in [1, 2]) {
    testWidgets('39-b summoned, seed $seed', skip: _dir == null, (tester) async {
      await shoot(tester, '39-b-opgeroepen-seed$seed', shotController(seed: seed), before: (s) async => s.summon());
    });
  }

  testWidgets('39-c no model', skip: _dir == null, (tester) async {
    final c = shotController()..availability = AssistantAvailability.needsSetup;
    PleyaKeychain.debugForceSupported = true;
    addTearDown(() => PleyaKeychain.debugForceSupported = false);
    await shoot(tester, '39-c-geen-model', c, before: (s) async => s.summon());
  });

  testWidgets('39-d dictating', skip: _dir == null, (tester) async {
    final c = shotController();
    await shoot(
      tester,
      '39-d-dicteren',
      c,
      keyboard: true,
      before: (s) async {
        s.summon();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), 'welke animatiefilms heb ik nog niet ge');
      },
    );
  });

  testWidgets('working', skip: _dir == null, (tester) async {
    final c = shotController();
    await shoot(
      tester,
      'working',
      c,
      before: (s) async {
        s.summon();
        c
          ..prompt = 'Welke animatiefilms heb ik nog niet gezien?'
          ..state = AssistantSurfaceState.working
          ..steps = const [
            AssistantStep(index: 0, tool: 'search_catalog', serverName: 'Zolder', phase: AssistantStepPhase.done),
            AssistantStep(index: 1, tool: 'find_title', serverName: 'Zolder', phase: AssistantStepPhase.started),
          ]
          ..emit();
      },
    );
  });

  for (final seed in [1, 2]) {
    testWidgets('39-e answer with titles, seed $seed', skip: _dir == null, (tester) async {
      final c = shotController(seed: seed);
      await shoot(tester, '39-e-antwoord-titels-seed$seed', c, before: (s) async => s.summon(), answer: answerTitles);
    });
  }

  // Build 323 device feedback: a long answer, two cards, three follow-ups.
  for (final phone in [_iPhone17Pro, _phones[1]]) {
    testWidgets('long answer ${phone.name}', skip: _dir == null, (tester) async {
      final c = shotController();
      await shoot(
        tester,
        'long-${phone.name}',
        c,
        phone: phone,
        before: (s) async => s.summon(),
        answer: answerLongTitles,
      );
    });
  }

  testWidgets('39-f watch stats', skip: _dir == null, (tester) async {
    final c = shotController();
    await shoot(tester, '39-f-kijkcijfers', c, before: (s) async => s.summon(), answer: answerWatchStats);
  });

  testWidgets('39-g confirm', skip: _dir == null, (tester) async {
    final c = shotController();
    await shoot(
      tester,
      '39-g-bevestigen',
      c,
      before: (s) async => s.summon(),
      answer: (c) => c
        ..prompt = 'Maak Sam aan en geef hem alleen Kids.'
        ..state = AssistantSurfaceState.working
        ..pending = createSam(),
    );
  });

  testWidgets('39-h back to Big P', skip: _dir == null, (tester) async {
    final c = shotController();
    await shoot(
      tester,
      '39-h-terug-naar-big-p',
      c,
      before: (s) async {
        answerLibraryTitles(c);
        c.emit();
        // The host's _openTitle, over the D-01 mockup as the detail page.
        s.openedTitle(nasTarget('s', 'Sintel', 2010).item.globalKey);
        unawaited(
          Navigator.of(tester.element(find.byType(BigPMobileHost))).push(
            MaterialPageRoute<void>(
              builder: (_) => Stack(
                fit: StackFit.expand,
                children: [
                  ClipRect(
                    child: RawImage(image: detail, fit: BoxFit.fitWidth, alignment: Alignment.topCenter),
                  ),
                  const BigPDetailPeek(),
                ],
              ),
            ),
          ),
        );
      },
    );
  });

  // T8: title facts on the cards and the ages card, on a Dutch device.
  for (final phone in [_iPhone17Pro, _phones[1], _iPad]) {
    for (final (tag, answer) in [('feiten', answerFactsTitles), ('leeftijden', answerKidsAges)]) {
      testWidgets('t8 $tag ${phone.name}', skip: _dir == null, (tester) async {
        tester.platformDispatcher.localeTestValue = const Locale('nl', 'NL');
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        final c = shotController();
        await shoot(tester, 't8-$tag-${phone.name}', c, phone: phone, before: (s) async => s.summon(), answer: answer);
      });
    }
  }

  testWidgets('t8 leeftijden gekozen 402', skip: _dir == null, (tester) async {
    final c = shotController();
    await shoot(
      tester,
      't8-leeftijden-gekozen-402',
      c,
      before: (s) async {
        s.summon();
        answerKidsAges(c);
        c.emit();
        await tester.pump(const Duration(milliseconds: 100));
        for (final age in ['4', '9']) {
          await tester.tap(find.text(age));
          await tester.pump();
        }
      },
    );
  });

  testWidgets('39-i iPad', skip: _dir == null, (tester) async {
    final c = shotController();
    await shoot(tester, '39-i-ipad', c, phone: _iPad, before: (s) async => s.summon(), answer: answerTitles);
  });

  for (final phone in _phones) {
    for (final keyboard in [false, true]) {
      final tag = '${phone.name}${keyboard ? '-kb' : ''}';
      testWidgets('sweep greet $tag', skip: _dir == null, (tester) async {
        final c = shotController();
        await shoot(tester, 'sweep-$tag-greet', c, phone: phone, keyboard: keyboard, before: (s) async => s.summon());
      });
      testWidgets('sweep setup $tag', skip: _dir == null, (tester) async {
        final c = shotController()..availability = AssistantAvailability.needsSetup;
        PleyaKeychain.debugForceSupported = true;
        addTearDown(() => PleyaKeychain.debugForceSupported = false);
        await shoot(tester, 'sweep-$tag-setup', c, phone: phone, keyboard: keyboard, before: (s) async => s.summon());
      });
    }
  }
}

typedef _Phone = ({String name, Size size, EdgeInsets safe, double keyboard});

/// The 402 one (iPhone 17 Pro) is what the 39 mockups are drawn at.
const _Phone _iPhone17Pro = (
  name: '402',
  size: Size(402, 874),
  safe: EdgeInsets.only(top: 54, bottom: 34),
  keyboard: 300,
);

/// 39 I: an 11-inch iPad in landscape.
const _Phone _iPad = (name: 'ipad', size: Size(1180, 820), safe: EdgeInsets.only(top: 24, bottom: 20), keyboard: 0);
const List<_Phone> _phones = [
  _iPhone17Pro,
  (name: 'se', size: Size(375, 667), safe: EdgeInsets.only(top: 20), keyboard: 260),
  (name: '440', size: Size(440, 956), safe: EdgeInsets.only(top: 62, bottom: 34), keyboard: 346),
];

Future<void> precacheBigP(WidgetTester tester, GlobalKey boundary) => tester.runAsync(() async {
  final ctx = tester.element(find.byKey(boundary));
  for (final a in [
    for (final p in kBigPPoses) bigPPoseAsset(p),
    for (final m in kBigPMouths) bigPAsset('mouth-$m'),
    bigPAsset('brow-l'),
    bigPAsset('brow-r'),
    bigPAsset('aim-arm'),
    bigPAsset('wave-arm'),
    bigPAsset('still-zwaaien'),
    PleyaWordmark.markAsset,
  ]) {
    await precacheImage(AssetImage(a), ctx);
  }
});

Future<void> save(WidgetTester tester, GlobalKey boundary, String name) async {
  await tester.runAsync(() async {
    final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await ro.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
}

/// Off the fake clock: shared preferences never complete inside testWidgets.
Future<void> _services(WidgetTester tester) => tester.runAsync(() async {
  resetSharedPreferencesForTest();
  SettingsService.resetForTesting();
  await StorageService.getInstance();
  await SettingsService.getInstance();
});
