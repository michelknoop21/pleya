---
name: pleya-tvbuild
description: Zet een tvOS Release-build van een gekozen SHA rechtstreeks op de gepairde Apple TV, buiten App Store Connect om. Gebruik bij "/pleya-tvbuild", "zet deze branch op mijn Apple TV", "private tvOS-build", of wanneer een TV-wijziging op echte hardware bewezen moet worden.
---

# /pleya-tvbuild

Een tvOS Release-build op de Apple TV zetten zonder App Store Connect aan te raken. Geen
upload, geen wachtrij, en niets dat bij een andere tester kan belanden.

## Waarom niet via TestFlight

De app heeft één interne groep, "Pleya", met `hasAccessToAllBuilds: true` en
`autoNotifyEnabled` op elke build. Daar zit naast Michel ook Guido van Beek in. Elke upload
landt dus automatisch bij hem, met notificatie. Die schakelaar is in de App Store Connect-API
create-only: een PATCH op `/v1/betaGroups/{id}` geeft `409 ENTITY_ERROR.ATTRIBUTE.NOT_ALLOWED`,
dus uitzetten kan alleen met de hand in de webinterface. Het is ook geen momentopname bij
upload maar een staande eigenschap, dus tijdelijk uitzetten en later terugzetten geeft de
tussenliggende builds alsnog vrij.

Voor een build die alleen op Michels eigen toestel hoort te draaien is deze route daarom de
juiste, en niet een omweg.

Voor de hardware-registerrijen die om runtimebewijs vragen (4K-output, overscan, VoiceOver,
Reduce Motion) is een development-build net zo geldig als een TestFlight-build. Geen van die
rijen toetst de distributieketen zelf.

## Eerst de bron vaststellen

Bouw nooit blind op de branch-tip. Bevestig welke SHA bedoeld is en dat de closurecommits die
de opdrachtgever noemt er werkelijk in zitten, en rapporteer dat voor je begint. Let op dat
`origin` naar Gitea wijst en `github` naar GitHub: een branch die alleen op GitHub bestaat komt
pas binnen na `git fetch github <branch>`, en een `git fetch origin` haalt hem niet op.

## Elke build krijgt een eigen nummer

Hoog het buildnummer op vóór je bouwt, en commit die bump op de branch waar je vandaan bouwt:

```bash
scripts/bump_build_number.sh          # +1, print het nieuwe nummer
git commit -am "chore: build <nummer> voor de Apple TV"
```

Bouw daarna van díe SHA. Zonder eigen nummer is een build op het toestel niet van zijn
voorganger te onderscheiden: "Over Pleya" toont hetzelfde nummer als de build die er al stond,
en een correctieronde vinkt dan bevindingen af tegen een binary die de fix niet draagt. Dat is
op 4 september precies misgegaan, toen build 247 uit `feat/pleyaserver` voor de redesign-build
werd aangezien.

Ligt er al een hoger nummer op een toestel dat niet in git staat, ga er dan overheen met
`--to <nummer>`. Het script weigert een nummer dat gelijk is aan of lager dan het huidige.

De release-lane komt hier niet mee in de knoop. `ensure_build_number` in `fastlane/Fastfile`
hergebruikt het pubspec-nummer zolang dat boven het hoogste TestFlight-nummer ligt, en pakt
anders het eerstvolgende vrije. Een lokaal opgehoogd nummer wordt dus overgenomen of
overgeslagen, nooit dubbel uitgegeven.

## De stappen

Werk in een detached worktree, zodat de hoofdcheckout met eventueel ongecommit werk onaangeroerd
blijft.

```bash
git worktree add --detach /Volumes/SSD/Projects/PlexFlixNetwork/pleya-tvbuild <sha>
cd /Volumes/SSD/Projects/PlexFlixNetwork/pleya-tvbuild
export PATH="/Volumes/SSD/flutter-sdks/3.44.0/flutter/bin:$PATH"

flutter pub get
tvos/scripts/fetch_engine.sh
(cd tvos && pod install)

xcrun devicectl list devices           # zoek de Apple TV en pak zijn identifier

xcodebuild \
  -workspace tvos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination "platform=tvOS,id=<device-id>" \
  -derivedDataPath build/tvbuild \
  -allowProvisioningUpdates \
  build

APP=build/tvbuild/Build/Products/Release-appletvos/Runner.app
xcrun devicectl device install app --device <device-id> "$APP"
xcrun devicectl device process launch --device <device-id> nl.michelknoop.pleya
```

De gepinde SDK moet vooraan in `PATH`. Staat er een nieuwere Flutter op het systeem, dan
schaduwt die de pin uit `.fvmrc`.

`fetch_engine.sh` haalt de engine-fork en herschrijft `Generated.xcconfig`. Sla je hem over, dan
breekt de build op "Unable to find module dependency: 'Flutter'", een melding die nergens naar de
werkelijke oorzaak wijst.

`pod install` is nodig omdat het workspace naar `Pods/Pods.xcodeproj` verwijst en die map niet in
git zit. De waarschuwing over de `profile`-baseconfig hoort erbij en is geen fout.

## Bewijs achteraf

Twee dingen controleren en rapporteren, niet aannemen.

Dat het werkelijk Release is:

```bash
file "$APP/Frameworks/App.framework/App"      # moet een Mach-O dylib geven (AOT)
ls "$APP/Frameworks/App.framework/flutter_assets/" | grep snapshot   # moet leeg zijn
```

Een debug-build heeft daar kernel-snapshots staan. Bouw je per ongeluk in Debug, dan meet je
Flutter-debugprestaties en lijken het hero-carousel en het gridscrollen schokkerig terwijl er
niets mis is.

En dat hij draait:

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" "$APP/Info.plist"
codesign -d --verbose=2 "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier"
xcrun devicectl device info processes --device <device-id> | grep Runner
```

Verwacht: signing met de Apple Development-identity, team XL9KN38ATX, en een profiel met
`ProvisionedDevices`. Een Apple Distribution-identity betekent dat er iets misgegaan is in de
scheme-configuratie.

## Vallen

De eerste minuten lijkt xcodebuild te hangen zonder een enkele compileregel. Hij haalt dan de
MPVKit-XCFrameworks binnen, goed voor ongeveer een gigabyte in `SourcePackages`. Wachten, niet
afbreken.

De Apple TV moet aan staan en op hetzelfde netwerk zitten. `xcrun devicectl list devices` toont
hem als `available (paired)`; staat daar iets anders, dan is dat het probleem en niet de build.

## Wat je niet doet

Niets uploaden, niets pushen, niet naar main mergen. De bump uit de vorige sectie is de enige
commit die deze route maakt.

App Store Connect blijft onaangeroerd, ook de groepsinstellingen. Loopt iemand tegen de
distributiegrens aan en wil hij hem toch omzetten, dan is dat een handmatige actie in de
webinterface door de accounthouder, en geen onderdeel van deze route.

Vink geen registerrijen af op grond van een geslaagde build. Dat is de waarneming van degene die
voor de televisie zit.
