# PS-5 acceptatiecriterium 4: hardwareronde

Criterium 4 van PS-5 vraagt een regressieronde op echte hardware voor tvOS en minimaal één
desktopplatform. Dit document is het bewijsdossier. Alles start als **open**; een rij wordt pas
PASS met datum, build, toestel en een verwijzing naar het bewijs.

Aangemaakt: 2026-09-04, op `5eebb83` (feat/pleyaserver).

## Status: uitgesteld, met een startvoorwaarde

Besloten op 4 september 2026. PS-5 blijft **code complete**; acceptatiecriterium 4 is **expliciet
niet gehaald** en de ronde is uitgesteld. Dat is een vastgelegde stand, geen open eindje dat
stilzwijgend meelift naar een release.

De poort uit [DEC-064](../DECISIONS.md) blijft onverkort staan: de hardwaretest moet uiterlijk vóór
de eerstvolgende publieke release die PS-5- of PS-9-gedrag bevat alsnog gedraaid zijn. Dat PS-9 op
4 september gesloten is, bewijst niets over dit criterium.

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
vastgelegd. Het macOS-artefact van 246 is bewaard: geen gedeeld toestel, en het is het enige
artefact achter de enige PASS die er op dit moment is.

## Poort 0: draagt de build de wijziging?

Deze stap gaat vóór elke test. `origin/main` bevat PS-5 niet, dus een build uit main levert overal
"geen regressie" op zonder iets te bewijzen. Tel eerst de markers in de binary.

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
| B | `Width`/`Height` `LessThanEqual` in `CodecProfiles` | `lib/services/jellyfin_client/jellyfin_device_profile.dart:82-83` | alleen als `display_max_resolution` niet op `auto` staat |
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
| macOS | 246 | **PASS** (4 sep 2026) | zie hieronder |
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

Daarmee is delta A live bevestigd en delta B aantoonbaar uit, want `display` is unknown. Er staat
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

[DEC-064](../DECISIONS.md) maakt een gefaalde ronde een regressie, en de reparatie gaat voor nieuw
fasewerk.

- FAIL op TrueHD: `git revert dc06bf3`, bewust als losse terugdraaibare commit gebouwd.
- FAIL op de resolutiecap: `git revert f0b5bc7`.
- FAIL op T2, T3, T4 of op Plex: niet reverten. Vergelijk eerst het verzonden profiel uit het
  logboek met de `_legacy`-constanten in `jellyfin_device_profile.dart:119-123` en
  `plex_client_profile.dart:88-90`. Wat daar niet aan gelijk is, is de bug.

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
