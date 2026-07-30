# Prompt voor nieuwe sessie: telefoon-hero te hoog + hero-art valt buiten beeld

Kopieer alles onder de streep als eerste bericht in een verse sessie.

---

Werk in `/Users/michelknoop/.supacode/repos/plezy-main/test` (Flutter-app Pleya, branch `test`).
Los onderstaande twee hero-problemen op, verifieer ze **visueel met screenshots** (niet alleen
analyze/test), commit, push naar beide remotes en zet een TestFlight-build klaar.
Werk zelfstandig door; stel alleen een vraag als je echt vastloopt.

## Waar we staan

Build **197** staat op TestFlight (iOS + tvOS + macOS, alle drie geüpload, exit code 0).
Relevante commits op `test`:

- `205701c` — fix: hero-hoogte op breed venster, focus-overlap in rijen en tv home-layout
- `4a0299b` — chore: bump build number to 197 for TestFlight

Wat er in `205701c` zat (dit is de directe aanleiding voor de nieuwe klachten):

1. Telefoon-hero haalt de backdrop alsnog op via `_enrichSpotlightArt` + nieuw
   `_ensureHeroArt(index)` (zichtbare pagina + directe buren, max 3 `fetchItem`-calls).
2. `_hasBillboardArt` is nu `item.billboardArt()?.isBackdrop == true` — telde eerder
   `backgroundSquarePath` mee en sloeg daardoor juist de fout renderende items over.
3. **Hero-hoogte opgeschroefd van `0.52` naar `0.62` vh** en op brede vensters afgestemd op
   het volledige 16:9-kader. Dit is wat nu te ver doorgeslagen is.
4. Focus-overlap in carrousels (tussenruimte afgeleid van de werkelijke schaalgroei).
5. Focus-ring volgt ronde knoppen (`BoxShape.circle`).
6. tvOS Home Layout: omhoog/omlaag-knoppen (slepen kan niet met een remote).
7. Home layout synct via iCloud (keys als user-scoped geregistreerd + schrijf-hook vuurt).

## Probleem 1 — hero is op telefoon nu te hoog

Op een iPhone (TestFlight 197, zie screenshots van de gebruiker) valt de **tekst onder de
posters van de rij "Verder kijken" buiten beeld** — de titels worden afgesneden door de
onderste tabbalk. De rij zelf is nog net zichtbaar, de labels eronder niet.

De code, `lib/screens/discover_screen.dart:1831-1833`:

```dart
final heroHeight = useSideNav
    ? (h * 0.75).clamp(480.0, 900.0) // desktop / tablet
    : math.max((h * 0.62).clamp(360.0, 620.0), math.min(w * 9 / 16, h * 0.8)) + statusBarHeight;
```

Reken het na op een iPhone 16 Pro (w=402, h=874): `w * 9/16 = 226`, dus de `math.max` valt
altijd op de telefoon terug op `0.62 * 874 = 542` + statusbar. De 16:9-tak raakt een telefoon
dus nooit — die is er puur voor brede vensters (macOS/iPad-landscape) en moet blijven werken.

Wat er moet gebeuren: **verlaag de telefoonfactor** zodat kop + poster + label van de rij
eronder volledig in beeld staan. Meet dat, gok niet: de rijhoogte komt uit
`lib/widgets/hub_section.dart` (`containerHeight` = `posterHeight + (isTv ? 48 : 33)`, plus de
focus-slack die in `205701c` is aangepast). Trek van de schermhoogte ook de statusbar én de
bottom-tabbalk af. Ergens rond `0.52`-`0.55` is waarschijnlijk goed, maar lever de berekening.

Let op: raak de `useSideNav`-tak (`0.75`) en de 16:9-tak voor brede vensters niet aan — die
zijn in 197 juist gerepareerd (macOS-hero was te kort).

## Probleem 2 — hero-artwork valt buiten beeld

Op dezelfde screenshots is te zien dat de backdrop zwaar bijgesneden is: bij "The Gentleman
Thief" staat het hoofd half buiten het kader, bij "Avatar Aang" valt het gezicht rechts weg.

Oorzaak: het hero-vak is op een telefoon veel smaller dan hoog (402×542 → aspect ~0.74),
terwijl de art 16:9 (~1.78) is. Met `BoxFit.cover` moet het beeld op hoogte schalen, waardoor
de breedte naar ~964pt gaat en er ruim 500pt aan beeld links/rechts wegvalt. Hoe hoger de
hero, hoe erger de horizontale crop — probleem 1 en 2 hebben dus dezelfde wortel.

Relevante plekken in `lib/screens/discover_screen.dart`:
- `:2039` `final artHeight = (screenWidth * 9 / 16).clamp(heroHeight, double.infinity)`
- `:2067` `fit: BoxFit.cover`
- `:2072` `alignment: Alignment.topCenter`
- de `maxWidth`/`maxHeight` die naar `MediaImageHelper.getOptimizedImageUrl` gaan (Plex snijdt
  server-side vanuit het **midden** bij `minSize=1`, zie de comment ter plaatse — een
  vak-vormige request bakt die centrale crop er al in vóór Flutter kan top-aligneren).

Denk hierbij aan de bestaande logica in `MediaItem.billboardArt()`
(`lib/media/media_item.dart:664`) en `heroArtCandidates({containerAspectRatio})`
(`:654`): die kiest bij een smal vak (`containerAspectRatio < 1.39`) al bewust
`backgroundSquarePath` boven `artPath`. Onderzoek of de telefoon-hero die vierkante variant
zou moeten gebruiken in plaats van de 16:9-backdrop — dat is precies waar dat pad voor bedoeld
is. Verifieer eerst of Plex/Jellyfin die square art überhaupt leveren voor deze items.

Los dit op zonder de winst van 197 terug te draaien: op telefoon moet er nog steeds een échte
backdrop staan (geen uitvergrote, geblurde poster) — dat was de fix in `2a5a03d` + `205701c`.

## Verificatie (bewijs tonen, niet claimen)

Dit is de belangrijkste opdracht: **in de vorige sessie is er géén visuele verificatie gedaan**
omdat de simulator-launch faalde (`Error launching application on iPhone 17 Pro`, terwijl de
Xcode-build zelf wél slaagde in 7,6s). Daardoor zijn deze twee regressies pas in TestFlight
ontdekt. Doe het deze keer wél:

1. Zoek de simulator-launch-fout uit. Beschikbare toestellen zijn o.a. **iPhone 17 Pro**
   (`42A75485-A48E-4645-9FC5-E10CD8E9BEE4`) en **iPhone 16e**; een iPhone 16 Pro of SE bestaat
   niet op deze machine. De volledige `flutter run`-log staat vol simulator-systeemruis —
   filter op de echte fout.
2. Maak screenshots op een grote én een kleine iPhone en toon ze: hero in beeld, en de rij
   "Verder kijken" met kop, posters **en titels** volledig zichtbaar zonder te scrollen.
3. Toon een screenshot waarop de hero-art niet meer door het gezicht heen snijdt.
4. `flutter analyze` — warnings zijn een CI-failure.
5. `flutter test`. **Let op:** `test/screens/video_player/player_prompt_overlays_test.dart`
   faalt al vóór deze wijzigingen (3 pending-timer asserts). Dat is pre-existing en
   geverifieerd op een schone tree — niet jouw werk. Verwacht 2742 geslaagd, 3 gefaald.
6. `scripts/codegen.sh` alleen als je een model of `strings.i18n.json` aanraakt.

## Afronden

- Commit in het Nederlands, in de stijl van `git log --oneline -10`. Geen AI-/modelvermelding,
  geen `Co-Authored-By`- of `Claude-Session`-trailer.
- Push naar **beide** remotes: `github` (github.com/michelknoop21/pleya) én `origin`
  (gitea:michelk/Plexflixnetwork). Check met `git log --oneline github/test -1` en
  `git log --oneline origin/test -1` dat ze gelijk lopen.
- Daarna `scripts/testflight_release.sh beta` in de achtergrond (iOS + tvOS + macOS;
  `ensure_build_number` geeft ze automatisch hetzelfde nummer, 197 → 198). Fastlane commit en
  pusht de pubspec-bump zelf naar gitea; push die commit daarna ook naar `github`. Rapporteer
  aan het eind lane, buildnummer en exit-code.

## Laat met rust (stond al open vóór dit werk)

- `android/app/src/main/kotlin/nl/michelknoop/pleya/watchnext/WatchNextPlugin.kt`
- `android/app/src/main/kotlin/nl/michelknoop/pleya/watchnext/WatchNextProvider.kt`
- `tvos/TopShelfExtension/TopShelfProvider.swift`
- `docs/sessions/`
- **`fastlane/Fastfile`** — bevat ongecommitte wijzigingen die niet uit de vorige sessie komen:
  een `upload_external`-lane + `EXTERNAL_GROUP` voor externe TestFlight-distributie. Niet
  committen zonder het te vragen.

## Nog open device-tests (mag je meenemen in dezelfde build)

- tvOS schone start: hero moet direct de nieuwste film tonen, nooit Continue Watching.
- Verse install op telefoon: thema is OLED (zwart) inclusief splash.
- tvOS → Instellingen → Home Layout: de nieuwe omhoog/omlaag-knoppen bedienbaar met de remote.
- Carrousel-focus: gefocust item wordt niet meer overlapt door de volgende kaart.
- Ronde knoppen: focus-ring volgt de cirkel (o.a. video-controls, tv-gids tijdnavigatie).
- Home layout sync via iCloud tussen twee Apple-devices.
