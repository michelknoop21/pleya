# STATUS — Pleya

_Laatst bijgewerkt: 2026-08-05 (branch `main`, gepusht)_

## Waar was ik

Zoeken werkt nu op elk apparaat, inclusief inspreken met de Siri Remote. tvOS geeft apps geen microfoontoegang, dus dictatie loopt via het systeem-toetsenbord: het zoekveld op Apple TV was een kale `InputDecorator` zonder focus en dus niet eens selecteerbaar, en is nu een `FocusableButton` die op select de native alert opent — voorgevuld, met partials die live in de bestaande debounce lopen. Daaronder zaten twee globale focusbugs die het "kan soms niets selecteren"-gedrag verklaren: de context-menu-toets armde de `SelectKeyUpSuppressor` ook zonder handler (die at dan de volgende select-druk op), en een select-key-up die op een andere node landde werd geslikt in plaats van doorgegeven. Verder: recente-zoekopdrachten waren op Apple TV niet activeerbaar, "Wis geschiedenis" gooide een `TypeError` en deed op géén platform iets, en sheets op hostloze schermen openden zonder focus. Commit `3b193f8`; CI-gate volledig groen, 2792 tests groen; build **202** staat op TestFlight voor iOS, tvOS en macOS.

Daarvóór:

TestFlight external testing voorbereid. `fastlane/Fastfile` heeft twee nieuwe lanes: `external` (distribueert de laatste geüploade build naar de external groep via `distribute_only`, per platform aanroepbaar met `platform:ios|appletvos|osx`; triggert Beta App Review bij de eerste build van een versie) en `add_testers emails:a@x.nl,b@y.nl` (voegt testers toe via Spaceship `post_bulk_beta_tester_assignments` — `pilot` als lane-actie kent geen tester-commando's). Groepsnaam via `EXTERNAL_GROUP` env-var (default "External Testers"); **de groep moet nog handmatig aangemaakt worden** in App Store Connect → TestFlight → External Testing. Inmiddels gecommit en op `main`.

Daarvóór:

Home-billboard op de telefoon. Drie waargenomen problemen (dubbele titel, aangesneden titelkunst, te dunne app-bar) bleken één oorzaak te hebben: de telefoon-hero vroeg expliciet `posterThumb()` op, dus de ingebakken titelkunst van de poster botste met de titel die de app er zelf overheen zet. De ontbrekende primitieve was het onderscheid tussen artwork dat een vak *vult* (frosted backdrop, tv-spotlight — daar wordt niets overheen getekend) en artwork dat de titeltypografie van de app moet *dragen*. Voor het tweede is de vorm van het vak irrelevant: de 16:9-backdrop wint altijd. `billboardArt()` geeft dat terug als `BillboardArt{path, isBackdrop}`; `heroArtCandidates` is ongewijzigd, dus de vullende call-sites gedragen zich als voorheen. Zonder backdrop valt het billboard terug op vierkante of posterart maar rendert die onscherp — nooit een leeg vlak, nooit een dubbele titel. Telefoon-hero van ~75vh naar ~52vh (bij 75vh is het vak 0,56 en snijdt `cover` twee derde van het 16:9-frame weg). Commit `2a5a03d`, iOS-build draait.

**Visueel ongeverifieerd.** De 52vh en de blur-sigma zijn gerekend, niet gezien. Op de telefoon nalopen: één titel op de hero, hoogte nog "hero" genoeg, een item zónder backdrop toont een onscherpe wash met alleen de app-titel, en witte app-bar-iconen over fel artwork met de zwaardere veil (0,88/0,68/0,42 in donker).

Daarvóór: ondertitel-labels op tvOS.

Ondertitel-labels op tvOS. Build 193 bevat de fix die mpv-ondertitelsporen positioneel koppelt aan de serverstreams (`lib/utils/player_subtitle_labeling.dart`), zodat een spoor zonder containertag alsnog een taal krijgt. Op de Apple TV blijft het paneel toch "Uit / French (Forced) / French / Track 3" tonen: precies wat de containertags in hun eentje al opleveren, dus de koppeling draait niet. De helper faalt op drie punten zwijgend (geen serverdata, afwijkende aantallen, tegensprekende talen), wat statisch niet te onderscheiden is. Daarom is er nu diagnostiek: `SubtitleAlignmentOutcome` + `diagnoseSubtitleAlignment()` maken de uitvalsreden benoembaar, en `logSubtitleLabelingDiagnostics()` logt hem eenmalig per wijziging op infoniveau vanuit beide trackmenu's (tv-paneel en sheet). Commit `4d4839c`, tvOS build **194** staat op TestFlight.

## Volgende stap

Build **202** op de Apple TV installeren en de zoekflow met de remote nalopen — dictatie en iPhone-continuity zijn niet simuleerbaar, dus dit is de enige manier om het af te tekenen:

1. Zoekveld focussen → select → systeem-toetsenbord verschijnt met de huidige query erin
2. Mic-knop op de Siri Remote indrukken → gesproken tekst verschijnt in het veld
3. Menu → toetsenbord sluit, resultaten staan er, en play/pause + D-pad werken daarna nog
4. Long-press op een resultaat (context-menu) en dáárna een gewone select → die moet nu werken (suppressor-fix)
5. Back met een open sheet → sheet sluit zonder dat de focus naar de sidebar springt

Op Android TV: mic-knop, en "zoek X in Pleya" via de Assistent vanuit een **volledig afgesloten** app (cold-start-fix).

Daarna openstaand, uit een eerdere sessie:

Ondertitelpaneel op de Apple TV toonde nog "Track 3". In Instellingen > Logs zoeken op `subtitle-labeling`; die ene regel noemt de uitkomst plus de aantallen en per-spoor metadata aan beide kanten. Daarna de bijbehorende fix:

| `outcome=` | Oorzaak | Fix |
|---|---|---|
| `noServerData` | `_currentMediaInfo` leeg | uitzoeken via welk pad (Plex zonder `partKey` in `plex_playback_mapper.dart:101`, offline-cache, Live TV) en `MediaSourceInfo` alsnog vullen |
| `countMismatch` | Plex zet `external` nooit, dus `isExternal` valt terug op "heeft een `key`" en embedded sporen mét key vallen weg | `external` expliciet bepalen in `PlexFileInfoStreamReader` zodat beide kanten dezelfde definitie gebruiken |
| `contradiction` | één afwijkend paar verwerpt de hele alignment | guard verzachten naar per-spoor |
| `aligned` | serverspoor heeft zelf geen taal | geen bug |

## Blockers

- [ ] **ice.pleya.app**: productie-relay nog niet gevalideerd tegen de Pleya Share-frame-eisen (client is stub-getest).
- [ ] **Wi-Fi Aware iOS**: alleen compile-bewezen (Xcode 26.3/SDK 26.2); echte verbinding vereist iPhone 12+ op iOS 26.
- [x] ~~3 pre-existing testfailures in `player_prompt_overlays_test.dart`~~ — opgelost 2026-08-05. Ze faalden op de pending-timer-invariant, niet op gedrag: `PlayerChromeController` armt de auto-hide-timer bewust opnieuw als een hold wordt vrijgegeven. De tests annuleren die timer nu na teardown.

## Toolchain-valkuil

Na een Xcode-update faalt **élke** build (ook fastlane) tot Xcode één keer handmatig is gestart — de systeemcomponenten in `/Library/Developer/PrivateFrameworks/` blijven anders achter bij Xcode.app. `xcodebuild -runFirstLaunch` lost het niet op. Check: `pkgutil --pkg-info com.apple.pkg.XcodeSystemResources` moet dezelfde versie tonen als `xcodebuild -version`. Zie [DEC-010](docs/DECISIONS.md#dec-010).

## Openstaand plan

Near-realtime sync van kijkvoortgang tussen apparaten: WebSocket-push van Plex/Jellyfin naar de bestaande `WatchStateNotifier` plus directe voortgangsrapportage bij seek. Richting goedgekeurd, nog niet gestart. Plan: `~/.claude/plans/is-er-een-manier-snoopy-snowglobe.md`.

## Quick start

```bash
cd /Volumes/SSD/Projects/PlexFlixNetwork/plezy-main
flutter test test/focus/ test/screens/search_screen_test.dart  # TV-focus en zoeken
scripts/ci_checks.sh                                           # volledige CI-gate
scripts/testflight_release.sh tvos_beta                        # TestFlight-upload (~10 min)
```

## Recente sessies

### 2026-08-05
- Zoeken op elk apparaat: Siri Remote-dictatie via het systeem-toetsenbord op Apple TV, plus zeven focus/selectie/popup-fixes waaronder twee globale (`SelectKeyUpSuppressor`, verweesde key-ups). Commit `3b193f8`, build 202 op iOS/tvOS/macOS.
- Repo gesynchroniseerd: `main` 64 commits bijgewerkt naar `origin/main` en de lokale `test`-branch gemerged.
- Xcode-toolchain hersteld (componenten stonden op 26.3 tegen Xcode 26.6) — zie [DEC-010](docs/DECISIONS.md#dec-010).

### 2026-08-03
- Voice search (Android `RecognizerIntent`), inline TV-zoektoetsenbord in plaats van pop-up, guard-test tegen kale `TextField`s.
- App Review 2.1(a): geen dead-end meer bij inloggen, Plex en Jellyfin gelijkwaardig.

### 2026-07-30
- Fastlane external-testing lanes: `external` (distribute_only naar external groep) en `add_testers` (Spaceship). Groep "External Testers" nog aanmaken in App Store Connect.
- Parallel: tvOS hero-eerste-load-fix, OLED-default, "Recent uitgebracht"-rij, hero-hoogte breed venster (commits `f93c125`, `205701c`, builds 196/197).

### 2026-07-28/29
- Ondertitel-labels: positionele koppeling met serverstreams (build 193), daarna diagnostiek toegevoegd omdat de koppeling op tvOS niet aansloeg (build 194).
- tvOS-hero: details-knop bereikbaar, ondertitels blijven in beeld bij zoom; beeldverhouding/zoom werkt nu echt op iOS/tvOS.
- Home: rij "Recently Added Shows" op serie-niveau, billboard haalt ontbrekend artwork/logo alsnog op en blijft leesbaar tijdens bladeren.
- TestFlight 188 t/m 194.

### 2026-07-25
- Downloads hervatten na systeempauze, netwerkverlies en retry; home-indeling werkt direct in plaats van pas na herstart. TestFlight 187.

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor keuzes, [docs/CHANGELOG.md](docs/CHANGELOG.md) voor details en [docs/PLEYA_SHARE.md](docs/PLEYA_SHARE.md) voor de share-architectuur.
