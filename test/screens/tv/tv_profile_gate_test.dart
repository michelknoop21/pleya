/// MOC-21 (mockup 21, "beeld"): the tvOS composition of the profile
/// selection gate. `TvDetectionService.debugSetAppleTVOverride` is not
/// needed here — this widget is reached only once `ProfileSwitchScreen`
/// already decided to render it, so these tests build it directly and leave
/// that branch to `profile_switch_screen_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_avatar.dart';
import 'package:pleya/screens/tv/tv_profile_gate.dart';
import 'package:pleya/theme/mono_theme.dart';

Profile _profile(String id, String name, {bool pinProtected = false}) =>
    Profile.local(id: id, displayName: name, createdAt: DateTime(2026, 1, 1), pinHash: pinProtected ? 'hash' : null);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpGate(
    WidgetTester tester, {
    required List<Profile> profiles,
    bool switching = false,
    ValueChanged<Profile>? onSelect,
    VoidCallback? onManageProfiles,
  }) async {
    // 1920x1080 at devicePixelRatio 1 is exactly TvLayoutConstants'
    // reference size, so every measurement below is scale-1.0, unscaled.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final nodes = <String, FocusNode>{};
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: TvProfileGate(
          profiles: profiles,
          switching: switching,
          focusNodeFor: (p) => nodes.putIfAbsent(p.id, () => FocusNode(debugLabel: 'gate:${p.id}')),
          onSelect: onSelect ?? (_) {},
          onManageProfiles: onManageProfiles ?? () {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the fixed 260 tile at scale 1.0', (tester) async {
    await pumpGate(tester, profiles: [_profile('p1', 'Michel')]);

    final avatarSize = tester.getSize(find.byType(ProfileAvatar));
    expect(avatarSize, const Size(260, 260));
  });

  testWidgets('the first tile autofocuses', (tester) async {
    await pumpGate(tester, profiles: [_profile('p1', 'Michel'), _profile('p2', 'Eray')]);

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'gate:p1');
  });

  testWidgets('SELECT activates the focused tile with its own profile', (tester) async {
    Profile? selected;
    final eray = _profile('p2', 'Eray');
    await pumpGate(tester, profiles: [_profile('p1', 'Michel'), eray], onSelect: (p) => selected = p);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'gate:p2');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(selected, eray);
  });

  testWidgets('switching disables tile activation', (tester) async {
    Profile? selected;
    await pumpGate(tester, profiles: [_profile('p1', 'Michel')], switching: true, onSelect: (p) => selected = p);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(selected, isNull);
  });

  testWidgets('a PIN-protected profile shows the lock badge, an unprotected one does not', (tester) async {
    await pumpGate(tester, profiles: [_profile('p1', 'Michel'), _profile('p2', 'Eray', pinProtected: true)]);

    expect(find.byIcon(Symbols.lock_rounded), findsOneWidget);
  });

  testWidgets('Profielen beheren is present and reachable', (tester) async {
    var opened = false;
    await pumpGate(tester, profiles: [_profile('p1', 'Michel')], onManageProfiles: () => opened = true);

    expect(find.text(t.screens.manageProfiles), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(opened, isTrue);
  });
}
