import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_avatar.dart';
import 'package:pleya/widgets/app_icon.dart';

/// Profiles, Settings and Sign out used to hang off the avatar in the Home
/// header on every platform, while mobile grew a My Pleya tab that does the
/// same job. These lock in that the two never overlap and never both vanish.
class _FakeActiveProfile extends ChangeNotifier implements ActiveProfileProvider {
  _FakeActiveProfile(this._active);

  Profile? _active;

  @override
  Profile? get active => _active;

  set activeProfile(Profile? value) {
    _active = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile({required String id, required String name}) =>
    Profile.local(id: id, displayName: name, createdAt: DateTime.utc(2026, 8, 17));

void main() {
  group('the account actions live in exactly one place per platform', () {
    test('mobile has My Pleya and no header menu; desktop and TV have the menu and no tab', () {
      for (final isMobile in [true, false]) {
        final tabs = NavigationTab.getVisibleTabs(
          isOffline: false,
          hasLiveTv: true,
          hasSeerr: true,
          hasWatchlist: true,
          isMobile: isMobile,
        );
        final hasMyPleya = tabs.any((tab) => tab.id == NavigationTabId.myPleya);

        expect(hasMyPleya, isMobile, reason: 'My Pleya is the mobile-only personal destination');
        expect(
          showsHeaderAccountMenu(isMobile: isMobile),
          !hasMyPleya,
          reason: 'either the header carries the account menu or My Pleya does, never both and never neither',
        );
      }
    });

    // tvOS and macOS both resolve isMobile to false, tvOS through
    // PlatformDetector.isTV() and macOS through its TargetPlatform, so this is
    // the guard that the mobile consolidation did not reach them.
    test('desktop and TV keep the header menu they always had', () {
      expect(showsHeaderAccountMenu(isMobile: false), isTrue);
    });

    test('mobile keeps My Pleya offline, so signing out never becomes unreachable', () {
      final tabs = NavigationTab.getVisibleTabs(
        isOffline: true,
        hasLiveTv: false,
        hasSeerr: false,
        hasWatchlist: false,
        isMobile: true,
      );
      expect(tabs.map((tab) => tab.id), contains(NavigationTabId.myPleya));
      expect(showsHeaderAccountMenu(isMobile: true), isFalse);
    });
  });

  group('the My Pleya slot shows who is signed in', () {
    NavigationTab myPleyaTab() => NavigationTab.getVisibleTabs(
      isOffline: false,
      hasLiveTv: false,
      hasSeerr: false,
      hasWatchlist: false,
      isMobile: true,
    ).firstWhere((tab) => tab.id == NavigationTabId.myPleya);

    Future<void> pumpDestination(WidgetTester tester, _FakeActiveProfile provider) async {
      final destination = myPleyaTab().toDestination();
      await tester.pumpWidget(
        ChangeNotifierProvider<ActiveProfileProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(body: Center(child: destination.selectedIcon ?? destination.icon)),
          ),
        ),
      );
      await tester.pump();
    }

    test('the slot keeps a separate selected state, so an avatar is still a tab', () {
      final destination = myPleyaTab().toDestination();

      expect(destination.selectedIcon, isNotNull);
      expect(destination.icon, isA<MyPleyaTabIcon>());
      expect((destination.icon as MyPleyaTabIcon).selected, isFalse);
      expect((destination.selectedIcon! as MyPleyaTabIcon).selected, isTrue);
      expect(destination.label, isNotEmpty);
    });

    testWidgets('the real avatar replaces the generic glyph', (tester) async {
      final provider = _FakeActiveProfile(_profile(id: 'a', name: 'Gideuh'));
      addTearDown(provider.dispose);
      await pumpDestination(tester, provider);

      expect(find.byType(ProfileAvatar), findsOneWidget);
      expect(tester.widget<ProfileAvatar>(find.byType(ProfileAvatar)).profile?.displayName, 'Gideuh');
      // The label on the destination already announces the tab; the avatar
      // must not announce a second time.
      expect(find.ancestor(of: find.byType(ProfileAvatar), matching: find.byType(ExcludeSemantics)), findsOneWidget);
    });

    testWidgets('without a resolved profile the tab falls back to its own glyph', (tester) async {
      final provider = _FakeActiveProfile(null);
      addTearDown(provider.dispose);
      await pumpDestination(tester, provider);

      expect(find.byType(ProfileAvatar), findsNothing);
      expect(find.byType(NavGlyph), findsOneWidget);
    });

    testWidgets('switching profile repaints the slot without a restart', (tester) async {
      final provider = _FakeActiveProfile(_profile(id: 'a', name: 'Gideuh'));
      addTearDown(provider.dispose);
      await pumpDestination(tester, provider);
      expect(tester.widget<ProfileAvatar>(find.byType(ProfileAvatar)).profile?.displayName, 'Gideuh');

      provider.activeProfile = _profile(id: 'b', name: 'Michel');
      await tester.pump();

      expect(tester.widget<ProfileAvatar>(find.byType(ProfileAvatar)).profile?.displayName, 'Michel');
    });

    testWidgets('signing out empties the slot instead of leaving the old face behind', (tester) async {
      final provider = _FakeActiveProfile(_profile(id: 'a', name: 'Gideuh'));
      addTearDown(provider.dispose);
      await pumpDestination(tester, provider);

      provider.activeProfile = null;
      await tester.pump();

      expect(find.byType(ProfileAvatar), findsNothing);
      expect(find.byType(NavGlyph), findsOneWidget);
    });
  });
}
