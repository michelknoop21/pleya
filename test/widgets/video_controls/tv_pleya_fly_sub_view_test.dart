import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/services/companion_remote/lan_discovery_service.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/services/companion_remote/playback_handoff_sender.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_panel_types.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_panel_widgets.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_pleya_fly_sub_view.dart';
import 'package:pleya/widgets/video_controls/tv_info_panel/tv_video_tab.dart';

import '../../test_helpers/fake_handoff_transport.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/watch_together_fakes.dart';

// A-23d: the picker of iPhones and iPads in the TV player panel.
void main() {
  late FakeHandoffTransport transport;
  late PlaybackHandoffSender sender;
  late FocusNode first;
  late List<DiscoveredHost> selected;

  setUp(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    TvDetectionService.debugSetAppleTVOverride(true);
    transport = FakeHandoffTransport();
    sender = PlaybackHandoffSender(transport: transport, currentStop: () => null);
    first = FocusNode(debugLabel: 'first');
    selected = [];
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    first.dispose();
  });

  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: TvPleyaFlySubView(
            sender: sender,
            title: 'Big Buck Bunny',
            from: const Duration(minutes: 3, seconds: 46),
            firstFocusNode: first,
            onSelectHost: selected.add,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Unmounts the view and the sender, so no search timer outlives the test.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    sender.dispose();
  }

  TvPanelRow row(WidgetTester tester, String title) =>
      tester.widget<TvPanelRow>(find.widgetWithText(TvPanelRow, title));

  testWidgets('searching: one focusable row says so, with the title on the right', (tester) async {
    await pumpView(tester);
    expect(find.text('Looking for iPhone and iPad…'), findsOneWidget);
    expect(find.text('Big Buck Bunny'), findsOneWidget);
    expect(find.text('Continue from 3:46'), findsOneWidget);
    first.requestFocus();
    await tester.pump();
    expect(row(tester, 'Looking for iPhone and iPad…').focusNode, same(first));
    expect(first.hasPrimaryFocus, isTrue);
    await finish(tester);
  });

  testWidgets('nothing found: the copy says Pleya must be open, Search again searches', (tester) async {
    transport.discoverable = false;
    await pumpView(tester);
    await tester.pump();
    expect(find.text('No iPhone or iPad found'), findsOneWidget);
    expect(find.text(t.playbackHandoff.noPhone), findsOneWidget);
    expect(t.playbackHandoff.noPhone, contains('cannot open Pleya on your iPhone'));

    first.requestFocus();
    await tester.pump();
    expect(row(tester, 'Search again').focusNode, same(first));
    expect(transport.discoverCalls, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(transport.discoverCalls, 2);
    await finish(tester);
  });

  testWidgets('one row per iPhone or iPad, the first takes the landing focus', (tester) async {
    await pumpView(tester);
    transport.beacons.add([
      fakeHost('iPhone van Michel'),
      fakeHost('Apple TV slaapkamer', platform: 'tvOS'),
      fakeHost('iPad', clientId: 'ipad'),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('iPhone van Michel'), findsOneWidget);
    expect(find.text('iPad'), findsOneWidget);
    expect(find.text('Apple TV slaapkamer'), findsNothing);
    expect(find.text('Pleya open'), findsNWidgets(2));

    first.requestFocus();
    await tester.pump();
    expect(row(tester, 'iPhone van Michel').focusNode, same(first));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected.map((h) => h.name), ['iPhone van Michel']);
    await finish(tester);
  });

  testWidgets('while one phone starts, the others are dimmed and take no Select', (tester) async {
    final answer = Completer<PlaybackHandoffOutcome>();
    transport.answer = (_) => answer.future;
    await pumpView(tester);
    final phone = fakeHost('iPhone van Michel');
    transport.beacons.add([phone, fakeHost('iPad', clientId: 'ipad')]);
    await tester.pump();
    await tester.pump();

    unawaited(sender.handOff(phone, serverId: 'srv', itemId: '42', positionMs: 0, title: 'Big Buck Bunny'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Starting on iPhone van Michel…'), findsOneWidget);
    final busy = row(tester, 'iPhone van Michel');
    final other = row(tester, 'iPad');
    expect(busy.onSelect, isNull);
    expect(other.dimmed, isTrue);
    expect(other.onSelect, isNull);

    // Select on the dimmed row does nothing.
    final otherFocus = find.descendant(of: find.widgetWithText(TvPanelRow, 'iPad'), matching: find.byType(Focus)).first;
    tester.widget<Focus>(otherFocus).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected, isEmpty);

    answer.complete(PlaybackHandoffOutcome.wrongProfile);
    await tester.pump();
    await tester.pump();
    expect(find.text('Uses another profile. Pick your profile on iPhone van Michel and try again.'), findsOneWidget);
    expect(row(tester, 'iPad').dimmed, isFalse);
    await finish(tester);
  });

  testWidgets('a fly keeps its busy row when the beacons change, and offers no Search again', (tester) async {
    final answer = Completer<PlaybackHandoffOutcome>();
    transport.answer = (_) => answer.future;
    await pumpView(tester);
    final phone = fakeHost('iPhone van Michel');
    transport.beacons.add([phone]);
    await tester.pump();
    await tester.pump();
    unawaited(sender.handOff(phone, serverId: 'srv', itemId: '42', positionMs: 0, title: 'Big Buck Bunny'));
    await tester.pump();

    // A new beacon object for the same phone.
    transport.beacons.add([fakeHost('iPhone van Michel')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Starting on iPhone van Michel…'), findsOneWidget);

    // Its beacon goes stale.
    transport.beacons.add([]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Starting on iPhone van Michel…'), findsOneWidget);
    expect(find.text('Search again'), findsNothing);

    answer.complete(PlaybackHandoffOutcome.failed);
    await tester.pump();
    await tester.pump();
    await finish(tester);
  });

  test('the failure notice says why the phone refused', () {
    expect(
      pleyaFlyFailureBody('iPad', PlaybackHandoffRefusal.wrongProfile),
      t.playbackHandoff.wrongProfileOn(name: 'iPad'),
    );
    expect(
      pleyaFlyFailureBody('iPad', PlaybackHandoffRefusal.pinNotEntered),
      t.playbackHandoff.pinNotEnteredOn(name: 'iPad'),
    );
    expect(pleyaFlyFailureBody('iPad', null), t.playbackHandoff.failedBody);
  });

  testWidgets('a phone that drops out does not hand the focus to another phone', (tester) async {
    await pumpView(tester);
    transport.beacons.add([fakeHost('iPhone van Michel'), fakeHost('iPad', clientId: 'ipad')]);
    await tester.pump();
    await tester.pump();

    // The user moves to the iPad, then the iPhone's beacon goes stale.
    final ipadFocus = find.descendant(of: find.widgetWithText(TvPanelRow, 'iPad'), matching: find.byType(Focus)).first;
    tester.widget<Focus>(ipadFocus).focusNode!.requestFocus();
    await tester.pump();
    transport.beacons.add([fakeHost('iPad', clientId: 'ipad')]);
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected.map((h) => h.name), ['iPad'], reason: 'Select reaches the phone the user is on');
    await finish(tester);
  });

  testWidgets('when the focused first phone drops out, the focus goes to the next one', (tester) async {
    await pumpView(tester);
    transport.beacons.add([fakeHost('iPhone van Michel'), fakeHost('iPad', clientId: 'ipad')]);
    await tester.pump();
    await tester.pump();
    first.requestFocus();
    await tester.pump();

    transport.beacons.add([fakeHost('iPad', clientId: 'ipad')]);
    await tester.pump();
    await tester.pump();
    expect(first.hasPrimaryFocus, isTrue, reason: 'the focus vanished with the phone');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected.map((h) => h.name), ['iPad']);
    await finish(tester);
  });

  testWidgets('the landing focus stays on its row when the first phone appears', (tester) async {
    await pumpView(tester);
    first.requestFocus();
    await tester.pump();
    expect(find.text('Looking for iPhone and iPad…'), findsOneWidget);

    transport.beacons.add([fakeHost('iPhone van Michel')]);
    await tester.pump();
    await tester.pump();
    expect(first.hasPrimaryFocus, isTrue, reason: 'the searching row became the phone row, focus and all');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected.map((h) => h.name), ['iPhone van Michel']);
    await finish(tester);
  });

  testWidgets('a reopened panel gets the sender whose fly still runs', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox.shrink();
        },
      ),
    );
    final answer = Completer<PlaybackHandoffOutcome>();
    transport.answer = (_) => answer.future;
    final firstPanel = tvPleyaFlySender(context, onViewFailed: () {}, create: () => sender);
    final running = firstPanel.handOff(
      fakeHost('iPhone van Michel'),
      serverId: 'srv',
      itemId: '42',
      positionMs: 0,
      title: 'Big Buck Bunny',
    );
    await tester.pump();
    firstPanel.release();

    final other = PlaybackHandoffSender(transport: FakeHandoffTransport(), currentStop: () => null);
    addTearDown(other.dispose);
    final secondPanel = tvPleyaFlySender(context, onViewFailed: () {}, create: () => other);
    expect(identical(secondPanel, firstPanel), isTrue);
    expect(secondPanel.busy, isTrue);

    answer.complete(PlaybackHandoffOutcome.failed);
    await running;
    secondPanel.release();
  });

  group('the Video tab', () {
    Future<List<TvInfoPanelSubView>> pumpTab(WidgetTester tester, {required bool canHandoff}) async {
      final opened = <TvInfoPanelSubView>[];
      final player = FakeSyncPlayer(playing: true, duration: const Duration(minutes: 10));
      addTearDown(player.dispose);
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TvVideoTab(
              player: player,
              boxFitMode: 0,
              onCycleBoxFit: null,
              chapters: const [],
              canControl: true,
              isLive: false,
              ambientSupported: false,
              ambientEnabled: false,
              ambientIntensity: 'off',
              // ignore: no-empty-block - ambient is not exercised here
              onSetAmbientIntensity: (_) {},
              canHandoff: canHandoff,
              firstFocusNode: first,
              // ignore: no-empty-block - the pill is not part of this test
              onNavigateUp: () {},
              onOpenSubView: opened.add,
            ),
          ),
        ),
      );
      await tester.pump();
      return opened;
    }

    testWidgets('a Pleya Fly row beside the sleep timer opens the picker', (tester) async {
      final opened = await pumpTab(tester, canHandoff: true);
      final fly = find.widgetWithText(TvPanelRow, 'Pleya Fly');
      expect(fly, findsOneWidget);
      expect(find.descendant(of: fly, matching: find.byType(TvPleyaFlyGlyph)), findsOneWidget);
      expect(
        tester.getTopLeft(fly).dy,
        greaterThan(tester.getTopLeft(find.widgetWithText(TvPanelRow, 'Sleep Timer')).dy),
      );
      tester.widget<TvPanelRow>(fly).onSelect!();
      expect(opened, [TvInfoPanelSubView.pleyaFly]);
    });

    testWidgets('no row when the playback cannot fly (live, offline, a local file)', (tester) async {
      await pumpTab(tester, canHandoff: false);
      expect(find.widgetWithText(TvPanelRow, 'Pleya Fly'), findsNothing);
    });
  });
}
