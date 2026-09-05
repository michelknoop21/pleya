# Focus-walk oracle — de regels, en waarom ze zo staan

`cases.json` naast dit bestand is de vectorenset; `runner/test/focus_walk_test.dart` draait hem.
De implementatie staat in `runner/lib/src/focus_walk.dart`. Wie een regel wil veranderen,
verandert hem hier én in een vector, nooit alleen in code.

## Wat een walk beoordeelt

Eén hop is: een bronknoop S, een druk in richting d, en een landing T. Het oordeel valt in het
frame **vóór** de druk. Dat is geen detail. Rails scrollen zodra de focus erin komt
(`tv_discovery_rail.dart`), dus dezelfde tegel staat na de druk ergens anders; een oordeel achteraf
zou kandidaten vergelijken met posities die de druk zelf heeft verplaatst.

Knopen worden aan elkaar geknoopt op `node`, het procesnummer dat `AutomationRegistry` per
`FocusNode` uitdeelt. Rects overleven de druk niet en labels zijn `'FocusableWrapper'` voor het
grootste deel van de app.

## De vier uitkomsten

| kind | betekenis |
| --- | --- |
| `ok` | de landing ligt vooruit en er lag niets tussen |
| `skipped` | er lag iets tussen dat gekozen had kunnen worden |
| `notForward` | de landing ligt niet in de gedrukte richting (terug, of een wrap) |
| `inconclusive` | de landing bestaat niet in het frame waarin geoordeeld wordt |

`inconclusive` is een aantekening, geen fout: een enkele hop mag hem hebben. Een walk waarvan
*elke* hop hem heeft bewijst niets en is rood. Dat onderscheid ligt bij de engine, niet bij het
orakel.

## Wanneer een kandidaat is overgeslagen

Kandidaat C telt mee bij een hop van S naar T in richting d als dit allemaal geldt:

1. **C ligt vooruit.** Het midden van C ligt voorbij de verre rand van S. Precies op die rand is
   niet voorbij (`down.centre-on-source-edge`).
2. **C ligt ertussen.** De verre rand van C ligt vóór de nabije rand van T, met 8 px speling
   (`kOverhangTolerance`). Zonder die speling wipt een kandidaat waarvan de rand op een
   afrondingsfout na samenvalt met die van T per frame tussen "ertussen" en "ernaast".
3. **C ligt in de band van S.** Minstens de helft van de loodrechte uitmeting wordt gedeeld met
   S, gemeten over de kleinste van de twee. De band komt van de **bron**, niet van de landing:
   Flutters richtingsbeleid scoort kandidaten tegen het vak dat de focus verlaat, en een band om
   de landing zou elke buur van de landing tot alternatief promoveren.
4. **C is zichtbaar.** Het midden van C ligt binnen de viewport. De rij onder de vouw is geen
   keuze die een kijker kan maken (`down.offscreen-candidate`).
5. **C is een echte derde.** Niet S, niet T, met oppervlak, en hij bevat S noch T. Die laatste
   houdt voorouder-scopes buiten de deur: hun rect omvat de hele rij, dus zonder deze regel is
   elke hop rood.

Kandidaten die geen focus kunnen krijgen (`canRequestFocus: false`) vallen al af bij
`walkCandidatesFrom`. Ze waren nooit een keuze, dus ze "overslaan" bestaat niet.

## Waarom dit geen kopie van `DirectionalFocusTraversalPolicy` is

Een kopie zou elke bewuste afwijking van deze app als fout melden — DOWN vanaf de hero landt op de
tegel die de rij onthoudt, RECHTS op de taalpagina landt op serierij 0 — en meedrijven met de SDK.
Wat hier van het beleid over is, is alleen het deel dat garandeert dat het orakel niets meldt wat
het beleid nooit had kunnen kiezen: de geschiktheidstest en de band van de bron.

Bedoelde afwijkingen horen in het scenario, niet in ruimere marges:

- `expect: [...]` benoemt waar elke hop landt. Een gematchte hop is vrijgesteld van de
  voorwaartsheidscheck, **niet** van de overslagcheck (`right.expected-hop-still-checked`).
- `allow: [...]` benoemt welke kandidaat gepasseerd mag worden, per id.

Een grens verruimen om een melding weg te krijgen is de ene verandering die hier niet hoort: dan
weet niemand meer welke sprongen het orakel nog ziet.

## Wat een walk niet vangt

De dubbele stap uit de aanraaklaag (NAV1) niet. `idb` stuurt één druk en geen aanraakstroom, en de
tweede native druk die een Siri Remote produceert komt daar dus niet uit. Die hoort bij de
replay-tests van `AppleTvRemoteTouchService`. Een groene walk over de navbalk zegt iets over de
layout, niet over de invoerlaag.
