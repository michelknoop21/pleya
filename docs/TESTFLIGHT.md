# TestFlight releases

Automatische TestFlight-uploads voor iOS, tvOS en macOS naar interne testers
(geen Beta App Review nodig). Draait lokaal op de Mac van Michel.

## Hoe het werkt

- `fastlane/Fastfile`: lanes `ios_beta`, `tvos_beta`, `macos_beta`, `beta` (alle drie),
  plus `attach_builds`, `external` en `add_testers` (zie hieronder).
- `scripts/testflight_release.sh [--clean] [lane]` bumpt het build number in `pubspec.yaml`,
  commit+pusht dat, en draait daarna de fastlane lane (default `beta`).
- Het script zet `scripts/xattr-fast/` vooraan in `PATH`. Zonder die shim besteedt
  `flutter build ios` ruim een uur aan twee recursieve `xattr`-passes over de hele repo
  voordat `xcodebuild` begint; zie [DEC-029](DECISIONS.md#dec-029). Na afloop rapporteert
  het script hoe vaak de shim is aangeroepen. Staat die teller na een iOS-build op nul,
  dan roept Flutter iets anders aan dan verwacht en is de traagheid terug. Uitzetten kan
  met `PLEYA_XATTR_FAST=0`, het aantal workers met `PLEYA_XATTR_JOBS`.
- `--clean` draait `flutter clean` vooraf. Dat is een herstelmiddel voor een build die
  zich raar gedraagt, geen snelheidstruc: het kost een volledige hercompilatie.
- launchd draait dit **maandelijks** (1e van de maand, 14:00) via
  `~/Library/LaunchAgents/nl.michelknoop.pleya.testflight.plist`,
  zodat builds nooit de 90-dagen TestFlight-limiet halen.
- Log: `~/Library/Logs/pleya-testflight.log`

## Credentials

`.env` in de project root (gitignored, zie `.env.example`):
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` (base64 van de App Store
Connect API `.p8`, rol App Manager).

## Handmatig draaien

```bash
scripts/testflight_release.sh            # alles: bump + iOS + tvOS + macOS
scripts/testflight_release.sh ios_beta   # alleen iOS
fastlane ios_beta                        # zonder build-number bump
```

## Verplicht vóór een iOS-upload: QR-scannen op echte hardware

`mobile_scanner` ging op 17 augustus 2026 van 5.2.3 naar 7.4.0, en daarmee
wisselde de decoder op iOS van Google ML Kit naar Apple's Vision-framework
(zie [DEC-024](DECISIONS.md#dec-024)). Dat de simulator weer bouwt is bewijs
dat de iOS-build gezond is, niet dat scannen werkt: een simulator heeft geen
camera, dus die kant is daar principieel niet te testen.

Loop dit één keer af op een fysiek toestel vóór de eerstvolgende upload. Het is
een smoketest, geen regressiesuite; hij duurt een paar minuten.

- [ ] Pleya Share openen en de scanner starten.
- [ ] De camera-permissievraag verschijnt en toestaan werkt.
- [ ] Een geldige Pleya-pair-QR scannen; de pairing gaat door.
- [ ] `barcode.rawValue` levert de verwachte `pleya://`-URI (log meelezen via
      de debug-pref, of het gedrag afleiden uit een geslaagde pairing).
- [ ] Een onleesbare of niet-Pleya QR aanbieden: de scanner blijft doorzoeken
      in plaats van te stoppen of te crashen.
- [ ] Scanner sluiten en opnieuw openen; de camera komt terug.
- [ ] Eén ronde bij matig licht.

Faalt hier iets, dan is dat een blokkade voor de upload en niet iets voor de
volgende ronde: QR-pairing is de enige manier om een host te koppelen.

### Overgeslagen rondes

Build 226 van 18 augustus 2026 (2.8.0, iOS/tvOS/macOS) is geupload zonder dat
deze lijst is afgelopen. Dat was een bewuste keuze, geen vergissing: de
scanner is op die build niet op een toestel gezien. De vakjes hierboven staan
daarom nog open en gelden onverkort voor de volgende upload.

## Build koppelen aan het App Store-versierecord

Een upload naar TestFlight zet de build nog niet in de versie die je indient.
Zonder die koppeling reviewt Apple gewoon de build die er al hing: bij de
2.1(a)-hertest van augustus 2026 stonden iOS en tvOS nog op de afgewezen build
156 terwijl 220 al een week klaarstond, en macOS had helemaal geen build.

De upload-lanes koppelen daarom zelf. `ios_beta`, `tvos_beta` en `macos_beta`
wachten na de upload op processing en selecteren de build in de bewerkbare
versie van dat platform. In `beta` gebeurt dat pas ná alle drie de uploads, zodat
platform twee niet staat te wachten op Apple's processing van platform één.

Koppelen is nooit fataal: mislukt het, dan staat de build gewoon op TestFlight en
haal je het achteraf in.

```bash
fastlane attach_builds                          # laatste build per platform
fastlane attach_builds platform:ios             # ios | appletvos | osx
fastlane attach_builds platform:osx build:220   # specifieke build
ASC_ATTACH_TIMEOUT=3600 fastlane beta           # langer wachten op processing (default 1800s)
```

Staat de versie in review of live, dan is er niets te bewerken en slaat de lane
dat platform over met een melding. Een versierecord op een ánder versienummer dan
de pubspec blokkeert het koppelen ook; zie de troubleshooting-tabel hieronder.

## Indienen voor review

TestFlight en App Review zijn twee aparte poorten. Een build die intern getest
wordt is nog niet ingediend; daarvoor moet het versierecord van dat platform
compleet zijn, en "Add for Review" weigert zonder te zeggen wélk veld ontbreekt
dan het eerste dat het tegenkomt. Loop daarom de checklist af vóór je klikt.

Per platform moet het versierecord hebben:

| Veld | Via de API te zetten | Opmerking |
|---|---|---|
| Build gekoppeld | ja, `fastlane attach_builds` | zie de sectie hierboven |
| Export compliance | ja, `PATCH /v1/builds/<id>` | anders is de build ook intern onzichtbaar |
| Beschrijving, keywords, support-URL | ja, `appStoreVersionLocalizations` | |
| Reviewnotities, demo-account, contactpersoon | ja, `appStoreReviewDetail` | demo-account is `applereview` op `demo.pleya.app` |
| Copyright | ja, `appStoreVersions.copyright` | jaartal **plus** rechthebbende, dus `2026 Michel Knoop`; alleen een naam wordt geweigerd |
| Screenshots | ja, maar omslachtig | minimaal één per platform, en tvOS en macOS erven die van iOS **niet** |

Copyright zetten of controleren:

```bash
# lezen
GET  /v1/appStoreVersions/<version-id>
# zetten
PATCH /v1/appStoreVersions/<version-id>
{"data":{"type":"appStoreVersions","id":"<version-id>",
         "attributes":{"copyright":"2026 Michel Knoop"}}}
```

De version-id's van 2.8.0: iOS `c5f974ea-55e7-46fb-8258-5f534cf03a35`, tvOS
`f885b8de-2677-4034-ae7f-07ee7c1a9e45`, macOS
`b185cff8-3c5e-4913-9cdb-cbb85df97b47`. Een nieuwe versie krijgt nieuwe id's;
haal ze op met `GET /v1/apps/6787464031/appStoreVersions`.

### Twee dingen die de API niet toont

De API-sleutel met rol App Manager leest deze twee niet: `appDataUsages` en
`appDataUsagePublishState` bestaan niet als relatie op `/v1/apps/<id>` (HTTP 404,
geen 403). Ze zijn account- of app-breed, dus één keer controleren in de
webinterface volstaat voor alle drie de platforms.

- **App Privacy**, het vragenformulier over dataverzameling. Moet op "Published"
  staan; zonder ingevuld formulier blokkeert Apple een eerste inzending.
- **EU DSA trader status**, onder Business. Sinds 17 februari 2025 wordt een
  inzending voor EU-distributie geweigerd zonder gecontroleerde traderstatus, en
  een app die niet voldoet verdwijnt uit alle 27 EU-territoria.

Beide stonden vermoedelijk al goed, want de iOS-inzending van 6 juli 2026 kwam
door de indienstap heen. Dat is een afleiding, geen meting: controleer ze zelf.

### Volgorde bij een hertest na afwijzing

Staat er nog een afgewezen submission open, zoals iOS na 6 juli 2026
(`UNRESOLVED_ISSUES`), dien dan niet opnieuw in vóór het antwoord in Resolution
Center staat. De tekst daarvoor ligt klaar in
[`app-review-reply-2026-08.md`](app-review-reply-2026-08.md). Platforms zonder
open submission (tvOS, macOS) kun je los indienen.

## External testers

Internal testers krijgen elke build direct (geen review). Voor testers búiten
het team (tot 10.000) is er external testing, en die builds gaan wél door Beta
App Review bij de eerste build van een versie.

**Eenmalig:** maak de groep aan in App Store Connect → TestFlight →
External Testing. Naam moet matchen met `EXTERNAL_GROUP` (default
"External Testers").

```bash
fastlane add_testers emails:a@x.nl,b@y.nl   # testers aan de groep koppelen
fastlane external                            # laatste build → external groep (alle platforms)
fastlane external platform:ios               # of: appletvos / osx
TESTFLIGHT_CHANGELOG="..." fastlane external # eigen "What to Test"-tekst
```

`external` bouwt niets: het distribueert de laatste geüploade build
(`distribute_only`) en wacht op processing. `add_testers` gebruikt Spaceship
(`post_bulk_beta_tester_assignments`); `pilot` als lane-actie kent geen
tester-commando's.

## Signing

Automatic signing met cloud-managed certificaten: de lanes geven
`-allowProvisioningUpdates` + de API-key aan xcodebuild.

**macOS extra stap (eenmalig, ook nodig voor de headless launchd-job):** de
`macos_beta` lane hertekent de CocoaPods resource-bundles met *Apple
Distribution* (anders ITMS-90284). `codesign` moet dan zonder pop-up bij de
private key kunnen. Zet daarom eenmalig de keychain partition-list:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k <mac-inlogwachtwoord> ~/Library/Keychains/login.keychain-db
```

Zonder deze stap faalt codesign met `errSecInternalComponent`.

## Vereisten in App Store Connect

- App-record voor `nl.michelknoop.pleya` met de platforms iOS, tvOS
  en macOS toegevoegd.
- Interne testers: App Store Connect → Users and Access (max 100), daarna in
  TestFlight aan de interne groep toevoegen. Nieuwe builds worden bij testers
  automatisch geïnstalleerd (TestFlight "Automatic Updates").

## Troubleshooting

| Symptoom | Oorzaak | Fix |
|---|---|---|
| **Élke** lane faalt binnen seconden op `DVTPlugInLoading: Failed to load code for plug-in com.apple.dt.IDESimulatorFoundation` | Xcode is bijgewerkt maar nooit handmatig gestart; de systeemcomponenten in `/Library/Developer/PrivateFrameworks/` lopen achter op Xcode.app | Start Xcode één keer uit Programma's en laat hem de componenten installeren. `xcodebuild -runFirstLaunch` werkt níet. Check: `pkgutil --pkg-info com.apple.pkg.XcodeSystemResources` moet dezelfde versie tonen als `xcodebuild -version`. Zie [DEC-010](DECISIONS.md#dec-010) |
| `upload_to_testflight` breekt af na ~1 minuut, fastlane toont een foutsamenvatting zonder foutregel | Onderbroken upload, niet noodzakelijk een echte fout | Lane opnieuw draaien. Archief en IPA blijven behouden, dus een herhaling is snel |
| Builds staan wel in TestFlight, maar er valt er geen te koppelen aan de App Store-versie | Het versie-record in App Store Connect staat op een ánder versienummer dan de pubspec. Bijt stil: uploaden lukt, indienen niet. macOS en tvOS stonden zo maandenlang op 1.0 tegenover builds van 2.8.0, waardoor die twee platforms nooit zijn ingediend | Per platform het `appStoreVersions`-record op het pubspec-versienummer zetten (App Store Connect of de API). Controle: `GET /v1/apps/<app-id>/appStoreVersions?fields[appStoreVersions]=versionString,platform,appVersionState` moet voor elk platform dezelfde `versionString` geven. App-id is `6787464031`, **niet** 6786811460, dat is het verweesde PlexFlixNetwork-record uit [DEC-001](DECISIONS.md#dec-001) |

| De lane meldt "Successfully uploaded" en de build is `VALID`, maar hij verschijnt bij geen enkele tester | Export compliance ontbreekt. Zonder `ITSAppUsesNonExemptEncryption` in de `Info.plist` zet Apple de build op `internalBuildState: MISSING_EXPORT_COMPLIANCE`, en dan is hij onzichtbaar, ook intern. Alles ervóór in de keten slaagt, dus de lane-output is misleidend groen. macOS miste de sleutel en heeft daardoor vanaf build 196 nooit een tester bereikt | De sleutel staat nu in alle drie de plists. Al geüploade builds trek je los met `PATCH /v1/builds/<id>` en `{"data":{"type":"builds","id":"<id>","attributes":{"usesNonExemptEncryption":false}}}`. Controle: `GET /v1/builds/<id>/buildBetaDetail` moet `IN_BETA_TESTING` geven. `processingState: VALID` zegt hier niets. Zie [DEC-018](DECISIONS.md#dec-018) |
| Een lange lane hangt minutenlang op `xattr -r -d com.apple.FinderInfo` | Flutter draait die recursief over de hele projectmap. Met een volgelopen `build/` (13 GB gemeten) duurt dat op de externe SSD eindeloos | `rm -rf build`, en draai een reaper mee die alleen een `xattr -r`-proces boven de 45 seconden afbreekt; een normale pass duurt seconden. Kill nooit de build zelf tijdens die stap, dat laat residu achter dat de vólgende config-only sloopt |

Draai lanes altijd met de uitvoer **direct naar een bestand** (`fastlane ios_beta > log.txt 2>&1`), niet via een pipe: bij `| tail` lees je de exitcode van `tail` en lijkt een mislukte run geslaagd.

## Let op (macOS)

Voor Mac App Store/TestFlight is App Sandbox verplicht, en die staat sinds deze
setup **aan** in `macos/Runner/Release.entitlements`. Test na de eerste macOS
TestFlight-build of videoplayback (mpv) en netwerkverkeer nog werken; de
DMG-distributie (zonder sandbox) blijft onaangetast via de bestaande CI.
