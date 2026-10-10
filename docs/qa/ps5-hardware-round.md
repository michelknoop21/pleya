# PS-5 acceptatiecriterium 4: hardwareronde

Criterium 4 van PS-5 vraagt een regressieronde op echte hardware voor tvOS en minimaal één
desktopplatform. Dit document is het bewijsdossier. Alles start als **open**; een rij wordt pas
PASS met datum, build, toestel en een verwijzing naar het bewijs.

Aangemaakt: 2026-09-04, op `5eebb83` (feat/pleyaserver).

## Stand op `main`, 10 oktober 2026

Dit dossier is op 10 oktober 2026 van `feat/pleyaserver` naar `main` overgenomen. Er is sinds
4 september geen test bijgekomen: de ronde is niet gedraaid en elke rij hieronder die open stond,
staat nog open. Zeven dingen zijn sindsdien veranderd of vastgesteld. De eerste is in de tekst
hieronder verwerkt; bij de andere staat waar dat nodig is een verwijzing naar dit blok. Waar de
tekst van 4 september en dit blok verschillen, gaat dit blok voor.

- Het besluit heet op `main` DEC-118. Op `feat/pleyaserver` droeg het nummer DEC-064, dat op `main`
  een ander besluit is; de hernummeringstabel onderaan `docs/DECISIONS.md` voert het als oud
  server-DEC 097. De regelnummers bij delta B en bij de `_legacy`-constanten volgen de bestanden op
  `main`.
- PS-5 staat inmiddels op `main`: `dc06bf3` (TrueHD) en `f0b5bc7` (resolutiecap) zijn voorouders van
  `main`. De zin onder poort 0 dat `origin/main` PS-5 niet bevat en de telling 185/46 bij
  startvoorwaarde 2 beschrijven 4 september. Een build uit `main` komt nu uit een boom die beide
  draagt. Poort 0 blijft per build nodig: tel de markers en vervang `5eebb83` in de laatste regel
  van het script door de commit waarvan je bouwt.
- Het macOS-artefact van build 246 is op 10 oktober niet teruggevonden in de werkboom van
  `feat/pleyaserver` (`build/macos` ontbreekt). De PASS van stap 1 rust op de opstartregel die
  hieronder is overgenomen, niet op een bewaard artefact.
- De blokkade "geen Jellyfin-account" is op 4 september gemeten en daarna niet opnieuw gemeten.
- De ronde is achterstallig sinds 25 september 2026. DEC-118 noemt drie uiterste momenten, wat zich
  het eerst voordoet: de eerstvolgende publieke release met PS-5- of PS-9-gedrag, een
  TestFlight-indiening naar App Review, of een merge van `feat/pleyaserver` naar `main`. De
  PS-5-code kwam op 25 september 2026 op `main` via PR #94 (`638e7524`, branch
  `integration/pleya-server-completion`), zonder dat de ronde was gedraaid. Dat derde moment is
  gepasseerd.
- De andere twee momenten zijn op 10 oktober 2026 nagelezen in App Store Connect, over de builds die
  sinds 20 augustus zijn geüpload. Het tweede moment is daarbij gelezen als een indiening van een
  build met PS-5- of PS-9-gedrag (besluit van 10 oktober: het gaat om relevante indieningen); DEC-118
  zelf schrijft die beperking niet uit. Wat er is ingediend:
  - iOS-build 296 en tvOS-build 298, naar App Review op 24 september 2026, nu in de App Store.
  - tvOS-build 259, langs Beta App Review; geüpload op 5 september 2026, App Store Connect geeft
    voor deze indiening geen datum terug.

  Volgens de markers in `docs/RELEASES.md` horen daar `5b937630` (296) en `53e2704a` (298) bij; 259
  is `740c78b6`. Die marker is het anker van de releasenotes en geen herkomstregistratie van de
  binary. Het sterkere argument: alle drie staan op `main` vóór `638e7524`, en `dc06bf3`, `f0b5bc7`
  en `5eebb83` zijn van geen van de drie een voorouder. Build 242 (23 augustus, van
  `feat/pleyaserver`) draagt PS-5 wel; die is alleen naar interne testers gegaan en heeft in App
  Store Connect geen review-indiening. Er is dus geen PS-5- of PS-9-gedrag publiek uitgebracht of
  ter review aangeboden, en sinds 25 september is er niets ingediend. Build 315 (geüpload op
  1 oktober voor iOS, tvOS en macOS) is niet ingediend; hij hangt aan het macOS-versierecord 2.8.0,
  dat op "voorbereiden voor indiening" staat. Van welke commit 315 komt is hier niet vastgesteld;
  komt hij van `main` na 25 september, dan draagt hij PS-5.
- De releasevoorwaarden (besluit van 10 oktober 2026). DEC-118 blijft ongewijzigd staan, dus de
  momenten die niet gepasseerd zijn gelden nog: geen publieke release van de client met PS-5- of
  PS-9-gedrag en geen indiening naar App Review van een build met dat gedrag, zonder geslaagde
  hardwareacceptatie. Een gedraaide ronde met een FAIL haalt die grens niet. Bovenop DEC-118 moet
  PS-5 volledig gevalideerd zijn vóór de eerste publieke release van Pleya Server. Een release van
  onderdelen die aantoonbaar onafhankelijk zijn van PS-5 valt er niet onder. De status hoort in
  `docs/PLEYA-SERVER-MASTERLIST.md`; zegt die nog "uitgesteld", dan loopt de masterlijst achter op
  dit blok.

## Status op 4 september: uitgesteld, met een startvoorwaarde

Besloten op 4 september 2026. PS-5 blijft **code complete**; acceptatiecriterium 4 is **expliciet
niet gehaald** en de ronde is uitgesteld. Dat is een vastgelegde stand, geen open eindje dat
stilzwijgend meelift naar een release.

De poort uit
[DEC-118](../DECISIONS.md#dec-118-het-openstaande-hardwarecriterium-van-ps-5-blokkeert-ps-9-niet)
blijft staan: de hardwaretest moet uiterlijk vóór de eerstvolgende publieke release die PS-5- of
PS-9-gedrag bevat alsnog gedraaid zijn. Dat geldt nog, en sinds 10 oktober moet de ronde ook
geslaagd zijn. De merge naar `main` uit
dat besluit is sindsdien gepasseerd, zie *Stand op `main`*; de ronde is daarmee achterstallig. Dat PS-9
op 4 september gesloten is, bewijst niets over dit criterium.

Drie voorwaarden gelden vóór de ronde mag starten:

1. Er is een bereikbare Jellyfin-server met TrueHD-materiaal, en er is op beide platforms op
   ingelogd. Zonder dat toetst de ronde niets, zie de blokkade hieronder.
2. De builds komen uit een boom die zowel PS-5 als `main` draagt, niet uit `feat/pleyaserver`.
   Die branch liep op 4 september 185 commits achter op `origin/main` (`git rev-list --left-right
   --count origin/main...HEAD` gaf 185/46), dus een build hieruit levert bevindingen op die niets
   met PS-5 te maken hebben.
3. Poort 0 hieronder is gehaald voor precies de builds die getest worden.

Zodra die drie staan, is dit document het startpunt en verandert er verder niets aan het protocol.

**Het tvOS-artefact van build 247 is op 4 september verwijderd.** Het staat in de markertabel
hieronder als historisch bewijs, maar `build/tvbuild/` bestaat niet meer. Reden: die build is op de
gedeelde Apple TV geïnstalleerd en verdrong daar het werk van een andere sessie, zonder dat de
verdrongen build terug te zetten was. Hij is opnieuw te bouwen en zijn bewijswaarde staat hier al
vastgelegd. Het macOS-artefact van 246 was op 4 september bewaard: geen gedeeld toestel, en het was
het enige artefact achter de enige PASS. Op 10 oktober is het niet teruggevonden, zie *Stand op
`main`*; de PASS van stap 1 is daarmee historisch en geen actueel hardwarebewijs.

## Poort 0: draagt de build de wijziging?

Deze stap gaat vóór elke test. Op 4 september bevatte `origin/main` PS-5 niet, dus een build uit
main leverde overal "geen regressie" op zonder iets te bewijzen. Sinds 25 september draagt `main`
PS-5 wel (zie *Stand op `main`*); een oudere build kan nog steeds zonder zijn. Tel eerst de markers
in de binary.

```bash
BIN=<app>/Contents/Frameworks/App.framework/App     # macOS
BIN=<app>/Frameworks/App.framework/App              # tvOS
for m in 'override of ' 'connection(local=' 'bitstream=' 'DirectPlayProfiles'; do
  printf "%-24s %s\n" "$m" "$(strings -a "$BIN" | grep -cF "$m")"
done
strings -a "$BIN" | grep -cE '^5eebb83$'
```

`DirectPlayProfiles` is de controlemarker en staat er in elke build. De andere drie staan alleen in
een PS-5-build. Een build waarin de eerste drie op nul staan en de vierde niet, is de nulmeting.

| Build | Platform | override of | connection(local= | bitstream= | DirectPlayProfiles | sha | Oordeel |
|---|---|---|---|---|---|---|---|
| 2.8.0+245 (`/Applications/Pleya.app`) | macOS, iOS-on-Mac | 0 | 0 | 0 | 2 | n.v.t. | pre-PS-5, ongeschikt |
| 2.8.0+246 (`build/macos/…/Pleya.app`) | macOS native | 2 | 2 | 2 | 2 | 5eebb83 | geschikt |
| 2.8.0+247 (`build/tvbuild/…/Runner.app`) | tvOS | 1 | 1 | 1 | 1 | 5eebb83 | geschikt |

De absolute aantallen verschillen per platform door stringdeduplicatie. Wat telt is de verhouding
tot de controlemarker: gelijk betekent aanwezig, nul betekent afwezig.

## De drie delta's die PS-5 op de lijn zet

| | Wijziging | Waar | Actief wanneer |
|---|---|---|---|
| A | `truehd` erbij in de Jellyfin `DirectPlayProfiles.AudioCodec` | `lib/media/device_capability_baseline.dart` (`kInferredAudioCodecs`) | elk mpv-platform; Android/ExoPlayer houdt de oude lijst |
| B | `Width`/`Height` `LessThanEqual` in `CodecProfiles` | `lib/services/jellyfin_client/jellyfin_device_profile.dart:86-87` | alleen als `display_max_resolution` niet op `auto` staat |
| C | Plex: geen delta | `lib/services/plex_client/plex_client_profile.dart` | nooit; de override reproduceert `preset.videoBitrateKbps` |

Delta A is het echte risico, en de twee platforms testen verschillende helften ervan. Op macOS gaat
TrueHD als bitstream naar de receiver. Op tvOS staat `truehd` niet in `appleBitstreamCodecs`, dus
mpv moet hem decoderen naar multichannel-PCM.

Omdat C nul is, is elk waargenomen verschil op Plex een echte bevinding en geen verwachte wijziging.

## Blokkade: er is geen Jellyfin-account

Delta A en B werken alleen tegen Jellyfin. Op 4 september 2026 is op geen van beide platforms een
Jellyfin-server geconfigureerd.

| Installatie | Jellyfin-treffers in prefs | Plex-treffers |
|---|---|---|
| macOS, container van build 245 | 0 | 61 |
| Apple TV, container na install van 247 | 0 | 38 |

De ronde kan dus niet starten met een bestaande login. Er moet eerst een Jellyfin-server met
TrueHD-materiaal beschikbaar zijn en in beide builds worden ingelogd. Zonder dat blijven T1 tot en
met T4 op Jellyfin onuitvoerbaar en dekt de ronde alleen de Plex-controle, die per definitie
delta-nul is.

## Stap 1: opstartregel

| Platform | Build | Status | Bewijs |
|---|---|---|---|
| macOS | 246 | **PASS** (4 sep 2026); historisch, opnieuw te doen op de rondebuild | zie hieronder |
| tvOS | 247 | open | Dart-log niet vanaf de CLI leesbaar, zie *Wat niet meetbaar bleek* |

De macOS-regel:

```
Pleya v2.8.0+246 (5eebb83) [effects: full]
[device: decoder(mpv: video=hevc,h264,h265,vp8,vp9,av1,mpeg4,mpeg2video(inferred),
         audio=aac,mp3,mp2,ac3,eac3,flac,opus,vorbis,dts,truehd(inferred),
         containers=mp4,mkv,m4v,webm,mov,ts(inferred))
 display(?(unknown)x?(unknown), hz=?(unknown), hdr=?(unknown))
 audio(channels=?(unknown), bitstream=ac3,eac3,dts,dtshd,truehd(inferred))
 connection(local=?(unknown), maxKbps=?(unknown))]
```

Daarmee is bevestigd dat het profiel `truehd` declareert (delta A staat aan; of TrueHD afspeelt
toetst T1, en die staat open) en is delta B aantoonbaar uit, want `display` is unknown. Er staat
geen `override of` bij bitstream, dus de audioprioriteit staat al op originele Dolby.

Op tvOS bevestigt de prefs-uitlezing dezelfde uitgangspositie: `audio_priority = originalDolby`,
`audio_output_mode = pcm`, `enable_hdr = false`, en `display_max_resolution` ontbreekt, wat `auto`
betekent. De native log bij het opstarten toont `engine press hook available=true` en
`[AudioSession] configure(multichannel: true)` met `AVAudioSessionCategoryPlayback` en
`AVAudioSessionModeMoviePlayback`. Dat laatste is de opt-in die het PCM-pad van delta A op tvOS
mogelijk maakt.

## T1 tot en met T4

Draai elke rij op Jellyfin en op Plex, en start de app uit de builddirectory, niet uit
`/Applications`.

| # | Materiaal | Verwacht | macOS | tvOS |
|---|---|---|---|---|
| T1 | mkv met TrueHD-spoor | beeld en geluid, alle kanalen, Jellyfin meldt Direct Play | open | open |
| T2 | DTS-HD MA (controle) | gelijk aan vóór PS-5 | open | open |
| T3 | 4K HEVC met EAC3 | gelijk aan vóór PS-5 | open | open |
| T4 | H.264/AAC in mp4 | gelijk aan vóór PS-5 | open | open |

T1 is de belangrijkste FAIL-conditie. Stilte, alleen stereo, zwart beeld of een afbrekende speler
is FAIL. Op macOS hoort de receiver bij T1 TrueHD of Dolby TrueHD/Atmos te tonen.

Op Plex geldt voor alle vier de rijen en beide platforms: nul verschil met vóór PS-5. Elk verschil
is FAIL.

## Stap 5: de resolutiecap

Alleen zinvol als delta B aanstaat.

| # | Handeling | Verwacht | Status |
|---|---|---|---|
| R1 | `display_max_resolution` op 1080p, T3 starten | de server levert 1080p | open |
| R2 | terug op `auto`, T3 opnieuw | weer 4K Direct Play | open |

## Wat niet meetbaar bleek

De Dart-opstartregel van de Apple TV is niet vanaf de commandline te halen. Drie routes zijn
geprobeerd en alle drie vallen af:

- `xcrun devicectl device process launch --console` levert alleen native `NSLog`, geen os_log. De
  Dart-logger schrijft via os_log.
- `log stream` kent op deze macOS geen `--device-udid` meer, en `devicectl device` heeft geen
  console-subcommando.
- `xcrun devicectl device sysdiagnose` faalt met `CoreDeviceCLISupport.DiagnoseError error 0`.

Wat wel werkt is de logupload in de app zelf, via Instellingen, Logboek, uploaden, gevolgd door
`curl https://ice.pleya.app/logs/<code>`. Debug-logging staat op het toestel al aan. Die stap
vereist de afstandsbediening.

## Bij een FAIL

[DEC-118](../DECISIONS.md#dec-118-het-openstaande-hardwarecriterium-van-ps-5-blokkeert-ps-9-niet) maakt een gefaalde ronde een regressie, en de reparatie gaat voor nieuw
fasewerk.

- FAIL op TrueHD: `git revert dc06bf3`, bewust als losse terugdraaibare commit gebouwd.
- FAIL op de resolutiecap: `git revert f0b5bc7`.
- FAIL op T2, T3, T4 of op Plex: niet reverten. Vergelijk eerst het verzonden profiel uit het
  logboek met de `_legacy`-constanten in `jellyfin_device_profile.dart:123-127` en
  `plex_client_profile.dart:96-98`. Wat daar niet aan gelijk is, is de bug.

## Bewijs bewaren

Logcodes per platform via de logupload. Schermafbeeldingen van het Jellyfin-dashboard met Play
method en de reden erbij, en van Plex Activity. Een foto van het AVR-display bij macOS T1.

## Aantekening bij het bouwen van 247

`tvos/scripts/xcode_appletv.sh sync_version` leest het buildnummer hard uit `pubspec.yaml` en
schrijft het met PlistBuddy in de al ondertekende bundles, ná Xcode's eigen Info.plist-stap. Een
commandline-`FLUTTER_BUILD_NUMBER` en een gepatchte `Generated.xcconfig` worden daardoor allebei
overschreven. Normaal valt dat niet op omdat dezelfde waarde wordt teruggeschreven en het zegel
geldig blijft.

Wie het nummer buiten pubspec om wil zetten, moet het ná de build zetten en opnieuw ondertekenen,
eerst `TopShelfExtension.appex` en dan `Runner.app`, met de entitlements uit de bestaande
signature. Doe je alleen het eerste, dan weigert het toestel de install met
`ApplicationVerificationFailed (0xe8008001)` op de extensie, en zegt `codesign --verify --deep
--strict` lokaal `invalid Info.plist (plist or signature have been modified)`.
