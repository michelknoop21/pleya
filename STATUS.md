# STATUS — Pleya

_Laatst bijgewerkt: 2026-07-30 (branch `test`)_

## Waar was ik

TestFlight external testing voorbereid. `fastlane/Fastfile` heeft twee nieuwe lanes: `external` (distribueert de laatste geüploade build naar de external groep via `distribute_only`, per platform aanroepbaar met `platform:ios|appletvos|osx`; triggert Beta App Review bij de eerste build van een versie) en `add_testers emails:a@x.nl,b@y.nl` (voegt testers toe via Spaceship `post_bulk_beta_tester_assignments` — `pilot` als lane-actie kent geen tester-commando's). Groepsnaam via `EXTERNAL_GROUP` env-var (default "External Testers"); **de groep moet nog handmatig aangemaakt worden** in App Store Connect → TestFlight → External Testing. Ongecommit; syntax en lane-registratie geverifieerd. Daarnaast staan er ongecommitte wijzigingen in `WatchNextPlugin.kt`/`WatchNextProvider.kt`/`TopShelfProvider.swift` uit de parallelle sessie (zie `docs/sessions/2026-07-30.md`).

Daarvóór:

Home-billboard op de telefoon. Drie waargenomen problemen (dubbele titel, aangesneden titelkunst, te dunne app-bar) bleken één oorzaak te hebben: de telefoon-hero vroeg expliciet `posterThumb()` op, dus de ingebakken titelkunst van de poster botste met de titel die de app er zelf overheen zet. De ontbrekende primitieve was het onderscheid tussen artwork dat een vak *vult* (frosted backdrop, tv-spotlight — daar wordt niets overheen getekend) en artwork dat de titeltypografie van de app moet *dragen*. Voor het tweede is de vorm van het vak irrelevant: de 16:9-backdrop wint altijd. `billboardArt()` geeft dat terug als `BillboardArt{path, isBackdrop}`; `heroArtCandidates` is ongewijzigd, dus de vullende call-sites gedragen zich als voorheen. Zonder backdrop valt het billboard terug op vierkante of posterart maar rendert die onscherp — nooit een leeg vlak, nooit een dubbele titel. Telefoon-hero van ~75vh naar ~52vh (bij 75vh is het vak 0,56 en snijdt `cover` twee derde van het 16:9-frame weg). Commit `2a5a03d`, iOS-build draait.

**Visueel ongeverifieerd.** De 52vh en de blur-sigma zijn gerekend, niet gezien. Op de telefoon nalopen: één titel op de hero, hoogte nog "hero" genoeg, een item zónder backdrop toont een onscherpe wash met alleen de app-titel, en witte app-bar-iconen over fel artwork met de zwaardere veil (0,88/0,68/0,42 in donker).

Daarvóór: ondertitel-labels op tvOS.

Ondertitel-labels op tvOS. Build 193 bevat de fix die mpv-ondertitelsporen positioneel koppelt aan de serverstreams (`lib/utils/player_subtitle_labeling.dart`), zodat een spoor zonder containertag alsnog een taal krijgt. Op de Apple TV blijft het paneel toch "Uit / French (Forced) / French / Track 3" tonen: precies wat de containertags in hun eentje al opleveren, dus de koppeling draait niet. De helper faalt op drie punten zwijgend (geen serverdata, afwijkende aantallen, tegensprekende talen), wat statisch niet te onderscheiden is. Daarom is er nu diagnostiek: `SubtitleAlignmentOutcome` + `diagnoseSubtitleAlignment()` maken de uitvalsreden benoembaar, en `logSubtitleLabelingDiagnostics()` logt hem eenmalig per wijziging op infoniveau vanuit beide trackmenu's (tv-paneel en sheet). Commit `4d4839c`, tvOS build **194** staat op TestFlight.

## Volgende stap

Build 194 op de Apple TV installeren, een item met meerdere ondertitelsporen afspelen, het ondertitelpaneel openen en in Instellingen > Logs zoeken op `subtitle-labeling`. Die ene regel noemt de uitkomst plus de aantallen en per-spoor metadata aan beide kanten. Daarna de bijbehorende fix:

| `outcome=` | Oorzaak | Fix |
|---|---|---|
| `noServerData` | `_currentMediaInfo` leeg | uitzoeken via welk pad (Plex zonder `partKey` in `plex_playback_mapper.dart:101`, offline-cache, Live TV) en `MediaSourceInfo` alsnog vullen |
| `countMismatch` | Plex zet `external` nooit, dus `isExternal` valt terug op "heeft een `key`" en embedded sporen mét key vallen weg | `external` expliciet bepalen in `PlexFileInfoStreamReader` zodat beide kanten dezelfde definitie gebruiken |
| `contradiction` | één afwijkend paar verwerpt de hele alignment | guard verzachten naar per-spoor |
| `aligned` | serverspoor heeft zelf geen taal | geen bug |

## Blockers

- [ ] **ice.pleya.app**: productie-relay nog niet gevalideerd tegen de Pleya Share-frame-eisen (client is stub-getest).
- [ ] **Wi-Fi Aware iOS**: alleen compile-bewezen (Xcode 26.3/SDK 26.2); echte verbinding vereist iPhone 12+ op iOS 26.
- [ ] **3 pre-existing testfailures** in `test/screens/video_player/player_prompt_overlays_test.dart` (falen ook op HEAD, niet door recent werk veroorzaakt).

## Openstaand plan

Near-realtime sync van kijkvoortgang tussen apparaten: WebSocket-push van Plex/Jellyfin naar de bestaande `WatchStateNotifier` plus directe voortgangsrapportage bij seek. Richting goedgekeurd, nog niet gestart. Plan: `~/.claude/plans/is-er-een-manier-snoopy-snowglobe.md`.

## Quick start

```bash
cd /Users/michelknoop/.supacode/repos/plezy-main/test
flutter test test/utils/player_subtitle_labeling_test.dart   # ondertitel-koppeling
flutter analyze                                              # warnings = CI-failure
scripts/testflight_release.sh tvos_beta                      # TestFlight-upload (~10 min)
```

## Recente sessies

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

### 2026-07-23
- Hero-resume-bug: direct-play herfetcht items zonder viewOffset; iCloud-voortgang merge (max/OR) + share-keys op denylist.
- Wi-Fi Aware release-compile-fix (Kotlin-lambda), TestFlight 185, APK ververst op geheime link.

### 2026-07-22
- Pleya Share compleet: pairAny (QR/hotspot), relay-tunnel, iOS keepalive, sessietoken-persistentie, multi-client + scan-cache, link-local/USB-kabel, offline bind + auto-resume, Plex-brug voor share-items, Wi-Fi Aware-transport, energie-optimalisaties, GUI-uitleg, website, geheime APK-download-link op de NAS.
- TestFlight 182 t/m 185.

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor keuzes, [docs/CHANGELOG.md](docs/CHANGELOG.md) voor details en [docs/PLEYA_SHARE.md](docs/PLEYA_SHARE.md) voor de share-architectuur.
