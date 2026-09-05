---
name: tvos-remote-input
description: Onderzoekt een Siri Remote-melding op de Apple TV (dubbele stap, hangende richting, crash op een pijl, stil toetsenbord) langs het vaste pad van UIPress tot FocusableWrapper. Gebruik bij "/tvos-remote-input", "de remote doet X dubbel", "één druk is twee stappen", "de remote blijft hangen", of elke melding over pijltjes, Select of Menu op tvOS. Begint bij de engine-bron en een logtrace, niet bij een build.
---

# /tvos-remote-input

Op 5 september 2026 kostte één dubbele pijlstap acht toestelbuilds, omdat de engine-fork
nooit gelezen was en de logs het derde signaal misten. Deze skill is de volgorde die dat
voorkomt. Een build op het toestel is stap 5, niet stap 1.

## 1. Lees het pad, wijs het station aan

```bash
scripts/tvos_engine_source.sh     # reconstrueert FlutterViewController.mm uit de patchreeks, < 1 min
```

`docs/tvos-remote-press-pipeline.md` heeft de tien stations, de drie zijdeuren in de engine
(`releaseAllSynthesizedPresses` bij een passthrough-enable, `tapIfMissingKeyDown:YES` op
`.ended`, de herhaaltimer zolang een toets in `synthesizedPressedKeys` staat) en een
symptoomtabel. Zoek de melding daarin op en benoem het station vóór je verder gaat.

Lees in de gereconstrueerde bron minstens: `tvosHandlePressFromUIEvent:`,
`synthesizeRemotePressType:`, `sendSynthesizedKeyEventOfType:`, `releaseAllSynthesizedPresses`
en `setMenuPressPassthroughEnabled:`. Bij een engine-bump (`tvos/engine.version`) opnieuw lezen:
de patchnummers verschuiven.

## 2. Trace het log

```bash
scripts/tvos_press_trace.sh <log-id>          # curl https://ice.pleya.app/logs/<id>
scripts/tvos_press_trace.sh pad/naar/log.txt
```

Drie vlaggen, exit 2 zodra er één is:

| Vlag | Betekent | Zijdeur |
|------|----------|---------|
| `EARLY-KEYUP` | keyup binnen 40 ms na de keydown terwijl de druk nog vastzit | 1: de engine liet de toets los |
| `RE-TAP` | verse keydown binnen 400 ms na een early keyup | 2: `.ended` tikte opnieuw, dat is stap twee |
| `ENABLE-HELD` | `menuPassthroughEnabled=true` verstuurd terwijl een toets ingedrukt is | 1: het bericht dat de release uitlokt |

Een keyup twee tot drie milliseconden na een keydown is nooit UIKit. Dan heeft de app iets tegen
de engine gezegd; zoek het kanaalbericht in datzelfde venster. `TvosSystemNavigationService` logt
zijn berichten op debug-niveau, dus staat het er niet, dan is het een ander kanaal.

Het log moet debug-regels bevatten (`AppleTvRemoteTouchService: native keydown`). Michel zet de
debug-pref aan vóór de reproductie; zie het geheugen `pleya-log-relay-ophalen`.

## 3. Reproduceer in de simulator wat de simulator kán raken

Een idb-druk bereikt station 3 niet (gemeten: nul hook-hits in tien drukken, hook wel
beschikbaar). De synthesizer, de pressed-set, de herhaaltimer en de release bij een
passthrough-enable zijn in de simulator dus niet te raken. Wat daar leeft is `HARDWARE ONLY`;
schrijf dat zo op en probeer het niet met een langere `holdMs` alsnog.

Wat wél kan: alles wat de app zelf doet rond een druk. `press: {key: left, holdMs: 250}` is een
echte vastgehouden druk en `HardwareKeyboard` ziet keydown en keyup apart. Publiceer de
app-kant als automation-state (zoals `tvos.menu_passthrough` met `parkedFlushes` en
`enablesSentWhileKeysHeld`) en assert daarop met `state:`. Houd `holdMs` onder de 400 ms.

`pleya_verify/scenarios/tvos.nav.held-press-lands-once.yaml` is het voorbeeld.

```bash
cd pleya_verify/runner
dart run bin/verify.dart run ../scenarios/tvos.nav.held-press-lands-once.yaml --json
```

## 4. Fix bij de afzender, met een negatieve controle

- Zegt de app iets tegen de engine op een moment dat de engine daar staat op wijzigt, dan hoort
  de fix bij de afzender van dat bericht (`TvosSystemNavigationService` parkeert een enable tot
  de toetsen los zijn; DEC-099).
- Nooit fasen inslikken of doorgeven in `tvos/Runner/AppDelegate.swift`: inslikken laat de
  herhaaltimer eeuwig lopen (build 257), doorgeven crasht UIKit op `_verifyTrackingPresses:`
  (build 256). Nooit tijd meten in Dart (build 254 at 65 echte drukken).
- Is het contract van de engine zelf fout, dan is het een patch in de reeks plus een eigen
  engine-build; het pad staat in de pijplijn-doc onder "Waar een fix hoort".

Het scenario uit stap 3 moet rood zijn zonder de fix en groen met. Draai beide en zet beide
uitkomsten in de correctieronde.

## 5. Dan pas het toestel

`/pleya-tvbuild` met een eigen buildnummer. Verwijder `Runner.app` uit
`build/tvbuild/Build/Products/Release-appletvos/` vóór een rebuild, anders blijft
`CFBundleVersion` oud en weigert de installatie op de TopShelf-signature. Vraag Michel om een
log met de debug-pref aan, en draai stap 2 erop voordat je iets concludeert.

## Wat er staat en wat niet

- `scripts/tvos_engine_source.sh`, `scripts/tvos_press_trace.sh`, de pijplijn-doc en het
  held-press-scenario zijn van 5 september 2026 (DEC-099).
- De trace kent alleen de drie vormen hierboven. Een nieuwe vorm hoort erbij in het script én
  in de symptoomtabel, met het log-id waarin hij voor het eerst gezien is.
