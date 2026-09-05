# De Siri Remote van UIPress tot FocusableWrapper

Op 5 september 2026 kostte één dubbele pijlstap acht toestelbuilds (252 t/m 259), vier
app-logs en een crash. De oorzaak stond de hele tijd in de engine-fork, in twintig regels
Objective-C. Dit document bestaat zodat de volgende remote-melding bij die regels begint en
niet bij een build.

## Eerst de bron, dan pas een build

De gepinde engine (`tvos/engine.version`, gehaald door `tvos/scripts/fetch_engine.sh`) komt uit
`github.com/edde746/flutter-tvos`. Dat is geen engine-fork maar een **patchreeks** op upstream
Flutter: er staat geen `FlutterViewController.mm` in, alleen 48 diffs die er samen één van
maken. Reconstrueer hem:

```bash
scripts/tvos_engine_source.sh
# → build/tvos-engine-source/src/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController.mm
```

Het script haalt het upstream-bestand op bij de commit uit `sdk.lock` van de gepinde tag, past
elke patch toe die het bestand raakt, en laat een git-repo achter met één commit per patch. Het
draait in minder dan een minuut en is byte-gelijk gecontroleerd tegen een handmatige
reconstructie. Alles wat over de remote gaat zit in patch 0032 t/m 0048.

## Het pad

Een druk op de ring loopt langs deze stations. Wie een melding onderzoekt, wijst aan bij welk
station het misgaat vóór hij iets wijzigt.

| # | Station | Waar | Wat het bijhoudt |
|---|---------|------|------------------|
| 1 | UIKit levert een `UIPress` met fase `.began`, later `.ended` | tvOS | het `UIPress`-object is per druk hetzelfde |
| 2 | `flutterTvos_sendEvent:` op `UIApplication` én `UIWindow` | engine, swizzle | niets; bij een geclaimde druk wordt de originele `sendEvent:` overgeslagen en ziet UIKit de druk nooit |
| 3 | `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)` | `tvos/Runner/AppDelegate.swift` | de enige app-hook; `false` zonder `super` tijdens een native tekstsessie (DEC-019) |
| 4 | `tvosHandlePressFromUIEvent:` | engine | `.began` → keydown, `.ended` of `.cancelled` → keyup met `tapIfMissingKeyDown:YES` |
| 5 | `sendSynthesizedKeyEventOfType:` | engine | `synthesizedPressedKeys`: een down voor een toets die er al in zit wordt genegeerd, een up voor een toets die er niet in zit ook |
| 6 | herhaaltimer | engine | pijltjes: na 0,4 s een repeat, daarna elke 80 ms, tot de up de toets uit de set haalt |
| 7 | `sendKeyEvent:` met `synthesized = true`, `deviceType = directionalPad` | engine → `flutter/keydata` | het pakket gaat zonder `flutter/keyevent`-tegenhanger en wordt daarom meteen afgeleverd |
| 8 | `HardwareKeyboard.handleKeyEvent` | SDK | `physicalKeysPressed`, bijgewerkt vóór de handlers draaien |
| 9 | `FocusManager` early key handlers | `AppleTvRemoteTouchService` | de enige plek in Dart die een druk kan stoppen; een `HardwareKeyboard.addHandler` die `true` geeft stopt niets |
| 10 | focus-tree | `FocusableWrapper` | `onNavigateLeft` en verwanten, op `KeyDownEvent` |

Station 3 krijgt de druk twee keer (beide swizzles), leest daarom alleen een vlag en logt. Wat
de app op dat niveau met een fase doet, is beperkt tot drie antwoorden, en twee daarvan zijn op
het toestel bewezen fout (zie de tabel hieronder).

## De drie zijdeuren in de engine

Het pad hierboven is symmetrisch. Wat asymmetrie veroorzaakt zit in drie extra regels.

1. **`setMenuPressPassthroughEnabled:YES` roept `releaseAllSynthesizedPresses`.** Elke toets
   die de engine op dat moment vasthoudt krijgt een synthetische keyup. De app zet die vlag via
   `flutter/tvos_system_navigation` (`TvosSystemNavigationService`). Gebeurt dat terwijl een pijl
   ingedrukt is, dan volgt op `.ended` zijdeur 2.
2. **`.ended` met `tapIfMissingKeyDown:YES`.** Staat de toets niet meer in de set, dan stuurt de
   engine een vers down/up-paar. Bedoeld voor een druk waarvan de began verloren ging; in
   combinatie met zijdeur 1 is het een tweede stap.
3. **De herhaaltimer loopt zolang de toets in de set staat.** Bereikt een `.ended` de engine
   niet, dan blijft de richting herhalen tot de app opnieuw start.

`TvosSystemNavigationService` parkeert sinds `7786a952` een enable tot `physicalKeysPressed`
leeg is. Een disable laat in de engine niets los en gaat direct.

## Symptoom naar station

| Symptoom op het toestel | Waar te kijken | Gezien in |
|-------------------------|----------------|-----------|
| Één druk, twee stappen, alleen op de druk die op een bepaalde plek landt | zijdeur 1: welke toestandsverandering stuurt een enable tijdens de druk | build 251-255, log `wa6v9` |
| Een richting blijft herhalen, app onbedienbaar, geen crash | zijdeur 3: welke `.ended` bereikt de engine niet | build 257 |
| Crash op elke pijl, `_UIFocusMovementPressGestureRecognizer _verifyTrackingPresses:` | station 2: een `.ended` aan UIKit gegeven na een `.began` die de engine claimde | build 256 |
| Navigeren werkt, klikken op het systeemtoetsenbord niet | station 3: de sessietak (DEC-019) | 2026-08 |
| Echte snelle drukken verdwijnen | station 9: een timing-heuristiek in Dart | build 254, log `ld1t1` |

## Meetprotocol

Wat een log moet bevatten voordat er een build wordt gemaakt:

- per druk de **fase en het `UIPress`-adres** vanuit station 3 (`pressLog` in `AppDelegate`);
- per keydown en keyup in Dart de **logische toets en het tijdstip** (`native keydown` in
  `AppleTvRemoteTouchService`);
- de **kanaalberichten** die de app in datzelfde venster verstuurt. Een keyup binnen enkele
  milliseconden na een keydown, terwijl de ring nog vast zit, is nooit UIKit; dan heeft de app
  iets tegen de engine gezegd.

Log `wa6v9` had de eerste twee. Het derde ontbrak, en daarmee is drie uur in fasen gezocht die
in orde waren.

## Waar een fix hoort

- Zegt de app iets tegen de engine op een moment dat de engine daar staat op wijzigt (vlag,
  sessie, kanaal), dan hoort de fix in de app, bij de afzender van dat bericht.
- Is het contract van de engine zelf fout (een fase die het verkeerde synthetiseert), dan hoort
  de fix in de patchreeks. Dat betekent een engine bouwen zoals de README van de fork
  beschrijft (10 GB upstream, twintig minuten fetch, daarna de build), de tarball zelf hosten,
  `tvos/engine.version` bumpen en na de bump `engine press hook available=` in de
  AppDelegate-log controleren. Niet uit te stellen als het nodig is, maar ook niet de eerste
  gok.
- Nooit: fasen inslikken of doorgeven in `AppDelegate`, of tijd meten in Dart. Beide zijn op
  het toestel gemeten en beide zijn slechter dan het defect.
