import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/navigation/primary_mobile_destination_policy.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_avatar.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/utils/platform_detector.dart';
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

  /// Zoeken is the other destination DEC-094 §1 took out of the bar, and the
  /// only one that does not land in My Pleya: it becomes an icon in the
  /// Home/Series/Films/Boeken header. So the header gate and the bar
  /// composition have to be complements, and they have to answer the same
  /// question — which is exactly what went wrong when the glyph asked
  /// `isPhone` while the bar was composed on `isMobile`.
  group('Zoeken lives in exactly one place per shell', () {
    List<NavigationTabId> barIds({required bool isMobile}) => mainScreenBottomNavigationTabs(
      visibleTabs: NavigationTab.getVisibleTabs(
        isOffline: false,
        hasLiveTv: true,
        hasSeerr: true,
        hasWatchlist: true,
        isMobile: isMobile,
      ),
      isMobile: isMobile,
      capabilities: const MobileDestinationCapabilities(hasLiveTv: true, hasWatchlist: true),
    ).map((tab) => tab.id).toList();

    test('the bar carries Zoeken exactly when the header does not', () {
      for (final isMobile in [true, false]) {
        expect(
          barIds(isMobile: isMobile).contains(NavigationTabId.search),
          !showsHeaderSearchAction(isMobile: isMobile),
          reason: 'either the bar or the header carries Zoeken, never both and never neither',
        );
      }
    });

    // The complement above is a statement about the predicate; this is the
    // statement about the header that has to honour it. Read off the source
    // rather than from a mounted screen, because the gate sits inside
    // `DiscoverScreen`'s app-bar builder and reaching it means standing up the
    // whole nine-provider stack to look at one `if`. Same shape as
    // `test/no_bare_text_field_test.dart`.
    test('the header asks the predicate rather than a platform question of its own', () {
      final source = File('lib/screens/discover_screen.dart').readAsStringSync();

      expect(
        source,
        contains('showsHeaderSearchAction(isMobile: PlatformDetector.isMobile(context))'),
        reason:
            'the Zoeken glyph must be gated on the same input the bar is composed from. '
            'Gating it on isPhone leaves an iPad with no entry point to Zoeken at all.',
      );
    });

    testWidgets('an iPad is one of the shells the header has to cover', (tester) async {
      // The reason the gate is `isMobile` and not `isPhone`. A tablet-sized
      // iOS view answers true to the first and false to the second, so a
      // header gated on `isPhone` drew nothing while the bar the policy
      // composed for that same view had already dropped the Zoeken slot.
      TvDetectionService.debugSetAppleTVOverride(false);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      late BuildContext ipad;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: MediaQuery(
            // iPad Pro 11": 13.6 diagonal inches by `isTablet`'s own maths.
            data: const MediaQueryData(size: Size(1024, 1366), devicePixelRatio: 2),
            child: Builder(
              builder: (context) {
                ipad = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(PlatformDetector.isMobile(ipad), isTrue, reason: 'no side rail, so the policy composes the bar');
      expect(PlatformDetector.isPhone(ipad), isFalse, reason: 'the old gate, and why it was the wrong question');
      expect(barIds(isMobile: PlatformDetector.isMobile(ipad)), isNot(contains(NavigationTabId.search)));
      expect(
        showsHeaderSearchAction(isMobile: PlatformDetector.isMobile(ipad)),
        isTrue,
        reason: 'Zoeken is not behind My Pleya, so the header is its only entry point here',
      );
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
