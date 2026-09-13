/// MOC-21: `ProfileAvatar` grew a `roundedSquare` shape for the TV selection
/// gate (mockup 21) alongside the circle every other surface already draws.
/// The audit that flagged mockup 21 also flagged a real bug —
/// `profile_switch_screen.dart`'s old `ClipRRect(4)` clipped the corner of the
/// slot/lock badge — so this file guards that the badge stays fully visible
/// (not clipped by either shape's own clip) rather than just checking shape
/// selection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_avatar.dart';
import 'package:pleya/theme/mono_theme.dart';

Profile _profile({bool pinProtected = false}) => Profile.local(
  id: 'p1',
  displayName: 'Eray',
  createdAt: DateTime(2026, 1, 1),
  pinHash: pinProtected ? 'hash' : null,
);

Widget _harness(Widget child) => MaterialApp(
  theme: monoTheme(dark: true),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('circle is the default shape, unchanged for every existing caller', (tester) async {
    await tester.pumpWidget(_harness(ProfileAvatar(profile: _profile(), size: 100)));

    expect(find.byType(ClipOval), findsOneWidget);
    expect(find.byType(ClipRRect), findsNothing);
  });

  testWidgets('roundedSquare clips to a rounded rect instead of a circle', (tester) async {
    await tester.pumpWidget(
      _harness(
        ProfileAvatar(profile: _profile(), size: 260, shape: ProfileAvatarShape.roundedSquare, borderRadius: 24),
      ),
    );

    expect(find.byType(ClipOval), findsNothing);
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(24));
  });

  testWidgets('roundedSquare defaults its radius to a tenth of size when none is given', (tester) async {
    await tester.pumpWidget(
      _harness(ProfileAvatar(profile: _profile(), size: 260, shape: ProfileAvatarShape.roundedSquare)),
    );

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(26));
  });

  testWidgets('the lock badge for a PIN-protected profile is not clipped by either shape', (tester) async {
    for (final shape in ProfileAvatarShape.values) {
      await tester.pumpWidget(_harness(ProfileAvatar(profile: _profile(pinProtected: true), size: 100, shape: shape)));

      // The badge sits in a `Positioned` sibling of the clip, inside a
      // `Stack(clipBehavior: Clip.none)` — this is the negative control for
      // the audit's finding: an outer clip wrapped *around* this whole stack
      // (as `_GateTile` used to do) would cut this widget's bounds down
      // before it ever painted, which `findsOneWidget` catches either way.
      expect(find.byIcon(Symbols.lock_rounded), findsOneWidget, reason: 'shape=$shape');
      final stackFinder = find.descendant(of: find.byType(ProfileAvatar), matching: find.byType(Stack));
      final stack = tester.widget<Stack>(stackFinder);
      expect(stack.clipBehavior, Clip.none, reason: 'shape=$shape');
    }
  });

  testWidgets('no badge for a profile without a PIN', (tester) async {
    await tester.pumpWidget(_harness(ProfileAvatar(profile: _profile(), size: 100)));

    expect(find.byIcon(Symbols.lock_rounded), findsNothing);
  });
}
