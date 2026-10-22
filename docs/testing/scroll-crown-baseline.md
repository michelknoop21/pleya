# Scrollkroon: herhaalbare nulmeting

Roadmap: A-06. Unified impact: uitsluitend tests voor de twee bestaande
iPhone-kronen. Geen wijziging in productiecode, gevoeligheid of versnellingscurve.

## Proef

`test/widgets/scroll_crown/scroll_crown_measurement_test.dart` gebruikt een
lazy lijst met 100, 1.000 of 10.000 aanklikbare titels, genummerd vanaf
`Titel 00000`. Beide echte kroonwidgets bedienen dezelfde lijst en controller.
Het alfabet geeft tijdens het slepen alleen de positie aan. Een sprong naar
een letter tijdens deze proef is een fout.

Elke proef begint bovenaan, op een viewport van 400 × 720 logische pixels,
met rijen van 100 pixels en een aangrijppunt op (378, 360). De vinger beweegt
80 keer 2 pixels omlaag, vervolgens vier keer 1 pixel omhoog. Dezelfde
ruimtelijke samples worden afgespeeld met 5, 20 en 80 ms tussen de eerste
80 bewegingen. De correcties duren steeds 80 ms per pixel. Dit zijn
teststimuli, geen gekozen gevoeligheidswaarden. Pointertijd, frametijd en
haptiekklok lopen samen. Daarna kiest de test de werkelijk zichtbare
`Titel 00050`, `Titel 00500` of `Titel 05000`, zonder programmatisch naar
de titel te scrollen. Er zijn 18 replays: drie groottes, twee toepassingen,
drie snelheden.

Per replay verschijnt één `CROWN_BASELINE`-JSON-regel in het testlog:
schema, viewport, rijhoogte, aantal titels, toepassing, timing, doel en gekozen
titel, plus per sample tijd in microseconden, vingerpositie, fase,
scrollpositie, actuele maximumpositie, bovenste titel en cumulatief aantal
tikaanroepen. De afzonderlijke tikken bevatten tijd en soort (tand/letter).
De regel wordt vóór de resultaatasserties geschreven, ook bij een mislukte
keuzetaak. Haptiek betekent hier een widgetcallback, geen gemeten trilling.

De nulmeting vergelijkt alle posities tussen toepassingen en snelheden.
Dit legt de huidige tijdonafhankelijke werking vast, niet de gewenste
eindafstelling. Een latere curvewijziging vereist een bewuste herziening van
deze nulmeting. Bewaar log en commit-SHA per kandidaat en vergelijk steeds
dezelfde samples. Pas geen andere rijhoogte, viewport of samplefrequentie
toe zonder dat als afzonderlijke proef te benoemen.

## Draaien en bewijs bewaren

Gebruik Flutter uit `.fvmrc` en de bestaande repositorysetup:

```sh
flutter test --reporter expanded test/widgets/scroll_crown test/screens/libraries/alpha_scroll_handle_test.dart > /tmp/crown-baseline.log 2>&1
scripts/ci_checks.sh
```

De gerichte Actions-workflow `Scroll crown baseline` draait dezelfde tests
en bewaart `tests.log`, `baseline.jsonl`, commit/runtime en formatter- en gatelogs
in artifact `crown-baseline`.
De gewone CI blijft daarnaast actief. De bestaande eindpunt-, bijlaad- en
alfabettests blijven behouden. Hun bewijs moet bij elke afstelling opnieuw
groen zijn. De meetjob controleert de gecommitteerde formattering en draait
`scripts/ci_checks.sh`; hij repareert geen bronbestanden tijdens de meting.

## Bewijsgrenzen

- Flutter: replays, echte widgetcallbacks, kiestaken, bestaande eindpunt- en
  bijlaadtests en de codegate moeten daadwerkelijk worden uitgevoerd.
  Een bronreview alleen is geen geslaagde nulmeting.
- Simulator: `ios.scroll-crown.ends` opnieuw uitvoeren als de scrollwerking
  later verandert. De 18 widgetreplays bewijzen geen native iOS-rendering,
  echte bibliotheekintegratie of invoervertraging.
- Fysieke iPhone: dezelfde kiestaken bij beide kronen met echte vingerinvoer,
  minimaal langzaam, snel en snel gevolgd door kleine correcties. Leg model,
  viewport, aantal titels, build-SHA, beweging/tijd, eindpositie, gekozen titel,
  herstelbewegingen en ervaren haptiek vast. Controleer beide uiteinden en
  bijladen terwijl de onderrand vastgehouden wordt. Vingerbedekking,
  trillingsgevoel en menselijke kiestijd blijven onbewezen zonder deze run.

Deze patch voegt geen invoerrecorder voor een fysieke telefoon toe en claimt
geen menselijke meetresultaten. De vaste widgetstimuli zijn de eerste
vergelijkbare nulmeting voordat een gevoeligheid wordt gekozen.
