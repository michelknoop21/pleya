# TestFlight releases

Automatische TestFlight-uploads voor iOS, tvOS en macOS naar interne testers
(geen Beta App Review nodig). Draait lokaal op de Mac van Michel.

## Hoe het werkt

- `fastlane/Fastfile` — lanes `ios_beta`, `tvos_beta`, `macos_beta`, `beta` (alle drie),
  plus `external` en `add_testers` voor external testing (zie hieronder).
- `scripts/testflight_release.sh [lane]` — bumpt het build number in `pubspec.yaml`,
  commit+pusht dat, en draait daarna de fastlane lane (default `beta`).
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

## External testers

Internal testers krijgen elke build direct (geen review). Voor testers búiten
het team (tot 10.000) is er external testing — die builds gaan wél door Beta
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

`external` bouwt niets — het distribueert de laatste geüploade build
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
| `upload_to_testflight` breekt af na ~1 minuut, fastlane toont een foutsamenvatting zonder foutregel | Onderbroken upload — niet noodzakelijk een echte fout | Lane opnieuw draaien. Archief en IPA blijven behouden, dus een herhaling is snel |
| Builds staan wel in TestFlight, maar er valt er geen te koppelen aan de App Store-versie | Het versie-record in App Store Connect staat op een ánder versienummer dan de pubspec. Bijt stil: uploaden lukt, indienen niet. macOS en tvOS stonden zo maandenlang op 1.0 tegenover builds van 2.8.0, waardoor die twee platforms nooit zijn ingediend | Per platform het `appStoreVersions`-record op het pubspec-versienummer zetten (App Store Connect of de API). Controle: `GET /v1/apps/<app-id>/appStoreVersions?fields[appStoreVersions]=versionString,platform,appVersionState` moet voor elk platform dezelfde `versionString` geven. App-id is `6787464031` — **niet** 6786811460, dat is het verweesde PlexFlixNetwork-record uit [DEC-001](DECISIONS.md#dec-001) |

| De lane meldt "Successfully uploaded" en de build is `VALID`, maar hij verschijnt bij geen enkele tester | Export compliance ontbreekt. Zonder `ITSAppUsesNonExemptEncryption` in de `Info.plist` zet Apple de build op `internalBuildState: MISSING_EXPORT_COMPLIANCE`, en dan is hij onzichtbaar, ook intern. Alles ervóór in de keten slaagt, dus de lane-output is misleidend groen. macOS miste de sleutel en heeft daardoor vanaf build 196 nooit een tester bereikt | De sleutel staat nu in alle drie de plists. Al geüploade builds trek je los met `PATCH /v1/builds/<id>` en `{"data":{"type":"builds","id":"<id>","attributes":{"usesNonExemptEncryption":false}}}`. Controle: `GET /v1/builds/<id>/buildBetaDetail` moet `IN_BETA_TESTING` geven. `processingState: VALID` zegt hier niets. Zie [DEC-018](DECISIONS.md#dec-018) |
| Een lange lane hangt minutenlang op `xattr -r -d com.apple.FinderInfo` | Flutter draait die recursief over de hele projectmap. Met een volgelopen `build/` (13 GB gemeten) duurt dat op de externe SSD eindeloos | `rm -rf build`, en draai een reaper mee die alleen een `xattr -r`-proces boven de 45 seconden afbreekt; een normale pass duurt seconden. Kill nooit de build zelf tijdens die stap, dat laat residu achter dat de vólgende config-only sloopt |

Draai lanes altijd met de uitvoer **direct naar een bestand** (`fastlane ios_beta > log.txt 2>&1`), niet via een pipe: bij `| tail` lees je de exitcode van `tail` en lijkt een mislukte run geslaagd.

## Let op (macOS)

Voor Mac App Store/TestFlight is App Sandbox verplicht — die staat sinds deze
setup **aan** in `macos/Runner/Release.entitlements`. Test na de eerste macOS
TestFlight-build of videoplayback (mpv) en netwerkverkeer nog werken; de
DMG-distributie (zonder sandbox) blijft onaangetast via de bestaande CI.
