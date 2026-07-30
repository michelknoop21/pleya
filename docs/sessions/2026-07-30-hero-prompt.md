# Prompt voor nieuwe sessie: telefoon-hero fixen + builds

Kopieer alles hieronder als eerste bericht in een verse sessie.

---

Werk in `/Users/michelknoop/.supacode/repos/plezy-main/test` (Flutter-app Pleya, branch `test`).
Pak onderstaande twee fixes in één keer op, verifieer ze, commit, push en zet daarna een
TestFlight-build klaar. Werk zelfstandig door; stel alleen een vraag als je echt vastloopt.

## Achtergrond
Op iOS (build 196) klopt de home-hero (billboard) niet:

1. **De hero toont een uitvergrote poster in plaats van een landscape-backdrop.**
   `/library/recentlyAdded` (`lib/services/plex_client.dart:1332-1341`) levert wel `thumb`
   maar vaak géén `art` en nooit de `Image`-tags (clearLogo). `MediaItem.billboardArt()`
   (`lib/media/media_item.dart:663`) valt dan terug op `thumbPath` met `isBackdrop: false`,
   en `_buildHeroItem` rendert die poster `BoxFit.cover` + `Alignment.topCenter` met blur 28
   (`lib/screens/discover_screen.dart:2028-2045`). Zichtbaar gevolg: een bijgesneden gezicht
   met uitgesmeerde rand (voorbeeld: de film "Disclosure Day").
   De tv-kant heeft dit al opgelost via `_enrichSpotlightArt` (`discover_screen.dart:639-664`),
   dat met `fetchItem` het volledige item ophaalt en art + clearLogo erin mergt — maar dat pad
   draait alleen voor de tv-spotlight (`_setSpotlightDebounced`, enkel aangeroepen vanaf
   `onFocusedItemChanged` op regel ~1637). De telefoon-PageView (~1812-1823) gebruikt de rauwe
   `_latestMovies`-items en repareert dus nooit.

2. **De hero is te kort.** `discover_screen.dart:1798-1806` gebruikt op telefoon
   `(h * 0.52).clamp(320.0, 520.0) + statusBarHeight` — ~516 van 874pt op een iPhone 16 Pro.
   Niets stemt de hero af op de verder-kijken-rij (de tv-tak doet dat wél, ~1520-1539).

Regelnummers zijn van vóór jouw wijzigingen; verifieer ze.

## Fix 1 — backdrop ophalen op telefoon
Alles in `lib/screens/discover_screen.dart`; geen nieuwe service-laag. `fetchItem`
(`plex_client.dart:3316`, ook in `local_folder_client.dart:263`) en `_spotlightArtCache`
bestaan al.

- Maak `_enrichSpotlightArt` generiek: nu swapt hij alleen `_spotlightItem` als het item nog
  de tv-spotlight is. Voeg toe dat hij, als het verrijkte item in `_latestMovies` zit, een
  `setState(() {})` doet zodat de telefoon-PageView opnieuw bouwt. De `_spotlightArtCache`
  (in-flight/mislukt = `null`-marker) blijft de rem op fetch-storms.
- Nieuwe `void _ensureHeroArt(int index)` die het item op `index` plus de directe buren
  (`index-1`, `index+1`) door `_enrichSpotlightArt` haalt. Aanroepen vanaf (a) de bestaande
  `onPageChanged` van de hero-PageView en (b) éénmalig post-frame zodra `_latestMovies` voor
  het eerst gevuld is — haak aan op het bestaande provider-luisterblok rond regel 518-560 dat
  al `isNewLoad` detecteert. **Nooit vanuit `build()` aanroepen.**
- Laat de PageView-builder het verrijkte item doorgeven: `_spotlightArtCache[item.globalKey] ?? item`,
  precies zoals `_setSpotlightDebounced` (~614-625) dat al doet.
- Zet de guard scherper: `_hasBillboardArt` (~634) telt `backgroundSquarePath` mee, terwijl
  `billboardArt()` dat pad juist als *niet*-backdrop behandelt. Vervang de check door
  `item.billboardArt()?.isBackdrop == true`, anders slaat de verrijking precies de items over
  die nu fout renderen.

Niet doen: het backdrop-veld in `data_aggregation_service`/`plex_client` mee laten komen —
`/library/recentlyAdded` levert die tags niet en dat zou 100 extra metadata-calls per load
kosten in plaats van 1-3 voor alleen de zichtbare hero.

## Fix 2 — hero verticaal groter
- `discover_screen.dart:1798-1806`, telefoon-tak: `(h * 0.52).clamp(320.0, 520.0)` →
  `(h * 0.62).clamp(360.0, 620.0)`, `+ statusBarHeight` blijft. iPhone 16 Pro: 516 → 604pt,
  ~270pt over voor de rij (kop ~40 + poster 156 + label 33 ≈ 230pt, zie
  `lib/widgets/hub_section.dart:509-521`). De desktop/tablet-tak (`useSideNav`, factor 0.75)
  blijft ongemoeid.
- `artHeight` (~2004) is `(screenWidth * 9/16).clamp(heroHeight, ∞)` en schaalt vanzelf mee.

## Verificatie (bewijs tonen, niet claimen)
1. `scripts/codegen.sh` alleen als je een model of i18n aanraakt (waarschijnlijk niet nodig).
2. `flutter analyze` — warnings zijn een CI-failure.
3. `flutter test`. Let op: `test/screens/video_player/player_prompt_overlays_test.dart` faalt
   al vóór deze wijzigingen (3 pending-timer asserts) — pre-existing, niet jouw werk.
4. iOS-simulator: home openen op een schone start. De hero moet een scherpe landscape-backdrop
   tonen, geen uitvergroot gezicht. Swipe door de hero-pagina's: ook scherp, zonder laadflits.
   Maak screenshots op een iPhone 16 Pro én een iPhone SE en laat ze zien: hero groter, rij
   "Verder kijken" met kop, posters en titels volledig in beeld zonder scrollen.
5. Controleer dat er maximaal een paar `fetchItem`-calls lopen (huidige pagina + buren), niet
   één per item uit de rij van 100.

## Afronden
- Commit in het Nederlands, in de stijl van de bestaande log (`git log --oneline -10`).
  Geen AI-/modelvermelding, geen `Co-Authored-By`- of `Claude-Session`-trailer.
- Laat deze bestanden met rust, ze stonden al open vóór dit werk:
  `android/.../watchnext/WatchNextPlugin.kt`, `WatchNextProvider.kt`,
  `tvos/TopShelfExtension/TopShelfProvider.swift`, `docs/sessions/`.
- Push naar `github/test` (remote `github` = github.com/michelknoop21/pleya) én naar
  `origin`/gitea, zodat beide gelijk lopen — check eerst met `git remote -v` en
  `git log --oneline origin/test -1`.
- Daarna: `scripts/testflight_release.sh beta`. Die lane doet iOS + tvOS + macOS en
  `ensure_build_number` in `fastlane/Fastfile` geeft ze automatisch hetzelfde buildnummer
  (nu 196, wordt 197). Fastlane commit en pusht de pubspec-bump zelf naar gitea; push die
  commit daarna ook naar `github`. Draai de build in de achtergrond en rapporteer aan het
  eind lane, buildnummer en exit-code.

## Nog open van de vorige sessie (device-tests, mag je meenemen in dezelfde build)
- tvOS schone start: hero moet direct de nieuwste film tonen, nooit Continue Watching.
- Verse install op telefoon: thema is OLED (zwart) inclusief splash.
