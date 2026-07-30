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

## Let op (macOS)

Voor Mac App Store/TestFlight is App Sandbox verplicht — die staat sinds deze
setup **aan** in `macos/Runner/Release.entitlements`. Test na de eerste macOS
TestFlight-build of videoplayback (mpv) en netwerkverkeer nog werken; de
DMG-distributie (zonder sandbox) blijft onaangetast via de bestaande CI.
