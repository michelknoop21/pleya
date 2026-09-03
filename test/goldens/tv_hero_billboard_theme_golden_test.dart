/// H20: the hero billboard's reading scrim and text ink stay legible on the
/// light theme, not just the dark one it was tuned against.
///
/// `MonoTokens.artworkScrimAlpha`/`onArtworkInk` exist precisely for a layer
/// like this one — text and a wash sitting directly on artwork, which never
/// flips with the theme the way a plain surface does (`mono_tokens.dart`'s own
/// doc on [MonoTokens.isLight]). Before this fix `tv_hero_billboard_card.dart`
/// read `TvHomeLayout.heroScrimAlpha`/`inkSecondary`/`inkTertiary` straight,
/// the same single strength on both themes — correct for dark, where the veil
/// is `tk.bg` almost-black over already-dark artwork, but wrong for light,
/// where the same veil is `tk.bg` near-white and *brightens* the artwork
/// under the text instead of dimming it.
///
/// Painted with a bright placeholder in place of real artwork on purpose: a
/// dark test backdrop would still read as "legible" even with the old,
/// theme-blind alpha, and would hide exactly the regression this file exists
/// to catch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_card.dart';

import '../test_helpers/golden.dart';

UnifiedMediaGroup _group() {
  final item = MediaItem(
    id: 'dune',
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Dune',
    year: 2021,
    summary: 'A noble family becomes embroiled in a war for control over the galaxy\'s most valuable asset.',
    genres: const ['Science Fiction'],
    durationMs: 155 * 60 * 1000,
    serverId: 'nas',
    serverName: 'nas',
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'dune-group',
    identity: canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque(),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: selectRepresentativeWatchState({source.sourceKey: item}),
  );
}

Widget _scene({required bool dark, bool oled = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: monoTheme(dark: dark, oled: oled),
  home: Scaffold(
    body: Center(
      child: TvHeroBillboardCard(
        group: _group(),
        size: const Size(760, 308),
        // A bright, saturated stand-in for the artwork layer — a vivid poster
        // is the case that actually stresses `artworkScrimAlpha`/
        // `onArtworkInk`, since a dark or already-muted backdrop would read
        // as "legible" even under the old, theme-blind alpha this test
        // exists to catch a regression of.
        artwork: const ColoredBox(color: Color(0xFFF2C744)),
        actions: const SizedBox(height: 40),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadAppFontsForGoldens);

  testWidgets('the reading scrim and ink wash harder on a light surface than on dark', (tester) async {
    setGoldenSurfaceSize(tester, size: const Size(820, 360));

    await tester.pumpWidget(_scene(dark: false));
    await tester.pumpAndSettle();

    final tk = Theme.of(tester.element(find.byType(Scaffold))).extension<MonoTokens>()!;
    expect(tk.isLight, isTrue);
    // The mechanism this fix relies on: light must ask for materially more
    // wash/ink than dark, not share one flat constant with it.
    expect(tk.artworkScrimAlpha(dark: 0.86, light: 0.94), greaterThan(0.86));
    expect(tk.onArtworkInk(dark: 0.78, light: 0.92).a, closeTo(0.92, 0.01));

    await expectMatchesGolden(find.byType(Scaffold), 'tv_hero_billboard_light_theme');
  });

  testWidgets('the same scene on the dark palette keeps its existing, unboosted strength', (tester) async {
    setGoldenSurfaceSize(tester, size: const Size(820, 360));

    await tester.pumpWidget(_scene(dark: true));
    await tester.pumpAndSettle();

    final tk = Theme.of(tester.element(find.byType(Scaffold))).extension<MonoTokens>()!;
    expect(tk.isLight, isFalse);
    expect(tk.artworkScrimAlpha(dark: 0.86, light: 0.94), 0.86);
    expect(tk.onArtworkInk(dark: 0.78, light: 0.92).a, closeTo(0.78, 0.01));

    await expectMatchesGolden(find.byType(Scaffold), 'tv_hero_billboard_dark_theme');
  });

  testWidgets('J11: OLED only changes bg to pure black — surface, text and ink stay identical to dark', (tester) async {
    // mono_theme.dart's own token table: OLED steps every dark background
    // tier one notch darker (bg #141414→#000000, surface #1F1F1F→#141414),
    // but surfaceElevated, outline, text and textMuted are byte-identical to
    // dark. Nothing that reads only those four (which is most TV chrome —
    // borders, ink, the elevated tier a panel already sits on) needs
    // OLED-specific handling; only a layer painting the raw page background
    // or a plain surface actually changes, and the token system already
    // carries that automatically.
    final dark = monoTheme(dark: true).extension<MonoTokens>()!;
    final oled = monoTheme(dark: true, oled: true).extension<MonoTokens>()!;

    expect(oled.bg, const Color(0xFF000000));
    expect(oled.bg, isNot(dark.bg));
    expect(oled.surface, isNot(dark.surface));
    expect(oled.surfaceElevated, dark.surfaceElevated);
    expect(oled.outline, dark.outline);
    expect(oled.text, dark.text);
    expect(oled.textMuted, dark.textMuted);
    expect(oled.isLight, isFalse, reason: 'OLED is a dark-theme variant for the light-theme H20 gate too');

    setGoldenSurfaceSize(tester, size: const Size(820, 360));
    await tester.pumpWidget(_scene(dark: true, oled: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await expectMatchesGolden(find.byType(Scaffold), 'tv_hero_billboard_oled_theme');
  });
}
