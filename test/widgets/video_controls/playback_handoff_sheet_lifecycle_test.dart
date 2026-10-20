import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/video_controls/sheets/playback_handoff_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/watch_together_fakes.dart';

/// Never finishes initialising: the sheet stays in its search, the way it does
/// on a device that has no Plex identity yet or a slow network.
class _PendingProfile extends ChangeNotifier implements ActiveProfileProvider {
  @override
  Future<void> initialize() => Completer<void>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConnections extends Fake implements ConnectionRegistry {}

class _FakeProfileConnections extends Fake implements ProfileConnectionRegistry {}

class _FakePlexHome extends Fake implements PlexHomeService {}

void main() {
  // Closing the handoff sheet while it still searched used to throw from its
  // dispose, which left the sheet's subtree half unmounted. The next sheet then
  // reused the host's GlobalKey'd Material and hit
  // `'element._lifecycleState == _ElementLifecycle.inactive': is not true`.
  testWidgets('a sheet opened after the handoff sheet was dismissed builds without errors', (tester) async {
    final player = FakeSyncPlayer(playing: true, duration: const Duration(minutes: 90));
    addTearDown(player.dispose);
    final remote = CompanionRemoteProvider();
    addTearDown(remote.dispose);
    final profile = _PendingProfile();
    addTearDown(profile.dispose);

    late BuildContext hostContext;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CompanionRemoteProvider>.value(value: remote),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: profile),
          Provider<ConnectionRegistry>.value(value: _FakeConnections()),
          Provider<ProfileConnectionRegistry>.value(value: _FakeProfileConnections()),
          Provider<PlexHomeService>.value(value: _FakePlexHome()),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: OverlaySheetHost(
            child: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );

    final sheets = OverlaySheetController.of(hostContext);
    unawaited(
      sheets.show<void>(
        builder: (_) => PlaybackHandoffSheet(player: player, serverId: 'srv', itemId: '1', title: 'Film'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PlaybackHandoffSheet), findsOneWidget);

    // Dismiss while the search is still running, as a tap on the barrier does.
    sheets.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PlaybackHandoffSheet), findsNothing);
    final onClose = tester.takeException();

    unawaited(sheets.show<void>(builder: (_) => const Text('Instellingen')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final onReopen = tester.takeException();

    expect(onClose, isNull, reason: 'closing the handoff sheet threw');
    expect(onReopen, isNull, reason: 'the next sheet threw while building');
    expect(find.text('Instellingen'), findsOneWidget);
  });
}
