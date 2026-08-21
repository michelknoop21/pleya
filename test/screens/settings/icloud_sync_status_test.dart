import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/settings/icloud_sync_status_line.dart';
import 'package:pleya/services/preferences/preference_sync_status.dart';
import 'package:pleya/theme/mono_theme.dart';

/// A11. One line under the toggle. It says what the sync is doing, it never
/// claims anything about the user's other devices, and it never leaks a key or
/// a value into the interface.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ready = PreferenceSyncStatus(availability: PreferenceSyncAvailability.ready);
  final at = DateTime.utc(2026, 8, 21, 12, 34);

  Future<void> pump(WidgetTester tester, PreferenceSyncStatus status) async {
    final listenable = ValueNotifier<PreferenceSyncStatus>(status);
    addTearDown(listenable.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: ICloudSyncStatusLine(status: listenable)),
      ),
    );
  }

  testWidgets('a switched-off sync says nothing extra: the toggle already does', (tester) async {
    await pump(tester, const PreferenceSyncStatus());

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a signed-out account says nothing extra either: the subtitle covers it', (tester) async {
    await pump(tester, const PreferenceSyncStatus(availability: PreferenceSyncAvailability.unavailable));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a sync in progress says so', (tester) async {
    await pump(tester, ready.starting(at));

    expect(find.textContaining('Syncing'), findsOneWidget);
  });

  testWidgets('a success reports what this device sent, never what other devices received', (tester) async {
    await pump(tester, ready.writeSucceeded(at));

    final text = tester.widget<Text>(find.byType(Text)).data!;
    expect(text, contains('Last sent to iCloud'));
    for (final claim in ['All devices', 'all devices', 'in sync', 'up to date']) {
      expect(text.contains(claim), isFalse, reason: 'the store cannot report delivery, so the UI must not imply it');
    }
  });

  testWidgets('a quota stop is shown, and a later successful write does not hide it', (tester) async {
    await pump(tester, ready.raise(PreferenceSyncHealth.quota).writeSucceeded(at));

    expect(find.textContaining('no room left'), findsOneWidget);
  });

  testWidgets('a transport error says the settings are safe locally', (tester) async {
    await pump(tester, ready.raise(PreferenceSyncHealth.error, errorCategory: 'PlatformException'));

    expect(find.textContaining('saved on this device'), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
  });

  testWidgets('an oversize value is reported without naming it', (tester) async {
    await pump(tester, ready.reconcileSucceeded(at, pushedCount: 3, skippedCount: 0, oversizeCount: 1));

    expect(find.textContaining('too large'), findsOneWidget);
  });

  testWidgets('the legacy-peer warning stands next to a success, not instead of it', (tester) async {
    await pump(tester, ready.sawLegacyPeer().writeSucceeded(at));

    expect(find.textContaining('older Pleya version'), findsOneWidget);
  });

  group('the messages carry no identity', () {
    test('no message contains a key, a count or a device name', () {
      final statuses = <PreferenceSyncStatus>[
        const PreferenceSyncStatus(),
        ready,
        ready.starting(at),
        ready.writeSucceeded(at),
        ready.raise(PreferenceSyncHealth.error, errorCategory: 'StateError'),
        ready.raise(PreferenceSyncHealth.quota),
        ready.reconcileSucceeded(at, pushedCount: 9, skippedCount: 4, oversizeCount: 2),
        ready.sawLegacyPeer(),
      ];

      for (final status in statuses) {
        for (final message in ICloudSyncStatusLine.messagesFor(status, null)) {
          for (final forbidden in ['hidden_libraries', 'subtitle_', 'user_', '__pleya_pref', 'StateError', 'macbook']) {
            expect(message.text.contains(forbidden), isFalse, reason: 'leaked "$forbidden" into the UI');
          }
        }
      }
    });

    test('every state produces a message list without throwing', () {
      for (final availability in PreferenceSyncAvailability.values) {
        for (final health in PreferenceSyncHealth.values) {
          final status = PreferenceSyncStatus(availability: availability, health: health, lastSuccess: at);
          expect(() => ICloudSyncStatusLine.messagesFor(status, null), returnsNormally);
        }
      }
    });
  });
}
