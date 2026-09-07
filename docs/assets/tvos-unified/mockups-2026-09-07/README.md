# Mockup 34 tot en met 36, voorgedragen op 7 september 2026

**Status: PROPOSED. Er mag niets van gebouwd worden voordat Michel per beeld akkoord
geeft.** Dat is de werkwijze die de e-booksset vastlegt en die hier onverkort geldt: een
schermgolden is het ontwerpcontract voor één venster, en `proposed` betekent dat het
contract nog niet gesloten is.

## Waar deze set vandaan komt

Drie meldingen van 7 september, alle drie op een fysieke Apple TV gezien:

1. De filtering van Alle films en Alle series moet ook op de andere lijstvensters komen,
   waaronder de kijklijst en aanvragen.
2. De resterende goldens moeten verder uitgewerkt worden.
3. Op de aanvragen- en zoekvensters zijn de items veel groter en wijken ze af van de
   nieuwe kaarttaal. Dat staat als CAT11 in `docs/tvos-fysieke-correctieronde.md`.

Die drie gaan over dezelfde drie schermen, dus ze zitten in één set.

## Wat er in zit

| Nr | Bestand | Wat het vastlegt |
|----|---------|------------------|
| 34 A | `34-kijklijst-a` | Kijklijst als catalogusraster, rail dicht, actieve keuzes als tag rechtsboven |
| 34 B | `34-kijklijst-b` | De rail open, met de drie regels die de kijklijst werkelijk kan |
| 34 C | `34-kijklijst-c` | Filters actief, plus de melding bij onvolledige serverdekking |
| 34 D | `34-kijklijst-d` | Lege staat mét filter, wat iets anders is dan een lege kijklijst |
| 35 A | `35-aanvragen-a` | Ontdekken via Aanvragen in de kaarttaal van de catalogus |
| 35 B | `35-aanvragen-b` | "Alles tonen" op een Seerr-rij, met de Seerr-eigen railregels |
| 35 C1 | `35-aanvragen-c1` | **Keuze:** Alle aanvragen als raster met statuscapsule |
| 35 C2 | `35-aanvragen-c2` | **Keuze:** Alle aanvragen als lijst, op TV-maat |
| 35 D | `35-aanvragen-d` | De statuskeuze als subweergave van de rail, met aantallen |
| 36 A | `36-zoeken-a` | Zoeken in rust, met recent gezocht |
| 36 B | `36-zoeken-b` | Resultaten, en het antwoord op SEARCH1 |
| 36 C | `36-zoeken-c` | Geen resultaten, met de Aanvragen-uitweg |

**35 C1 en C2 zijn twee kanten van één vraag**, geen twee schermen. Er hoort er precies
één goedgekeurd te worden.

## Wat er bewust niet in zit

**Bibliotheken.** Michel noemde die pagina als voorbeeld, en er is nagekeken of er een
nieuwe mockup voor nodig is. Dat is niet zo. Mockup 27 (`../mockups-2026-09-04/`) dekt
bronbeheer in vijf standen, is goedgekeurd onder DEC-092, en state D tekent het openen in
de catalogus al mét de CAT5-rail erin, dus de set anticipeerde op het besluit dat er na
haar kwam. Wat daar ontbreekt is geen ontwerp maar een bouwronde: LIB7 staat in de
correctieronde als "goedgekeurd, bouw open". Een tweede mockupset erbij tekenen zou het
werk verplaatsen in plaats van het te doen.

## De headroom boven een raster

Michel zag in de eerste ronde dat een gefocuste kaart in de bovenste rij over de paginakop
viel. Dat is geen tekenfout maar precies het contract dat CAT10 in code afdwingt, en het
hoort dus ook in het beeld te staan.

Een gefocuste kaart schaalt 1,05 om zijn onderrand, dus een kaart van 422 groeit 21 pixels
omhoog, en daarbovenop komt de ring: gap 8 plus lijn 4. Samen 33. `tv.css` draagt dat nu als
`--focus-headroom: 36px`, en elke band waarin een kaart de focus kan hebben reserveert het
boven zich. In de code is dit `TvCatalogGrid.focusHeadroom`, dat in `scrollPadding` zit.

Wie een nieuwe pagina met een raster of rail tekent: zet die reservering erbij. Zonder is
het beeld op de eerste blik goed en op de tweede fout, want de overlap ontstaat alleen in de
gefocuste stand.

## Waar de nummers vandaan komen

33 was het spelerpaneel (`../mockups-2026-09-05/`), dus deze set begint bij 34. De
nummers 09 tot en met 25 uit `../approved-2026-09-03/` blijven staan; 34 vervangt wat
mockup 14 over de kijklijst zei, 35 wat 15 over aanvragen zei, en 36 wat 13 over zoeken
zei. Die drie zijn van vóór DEC-093, en dat besluit schreef zelf al op dat mockup 14 erop
achterloopt.

## Renderen

```bash
cd docs/assets/tvos-unified/src
PLEYA_MOCKUP_ART=~/Downloads/mockups-tvos/_src/art node build.mjs 34-kijklijst
```

`pages/*.html` zijn fragmenten. De bron hoort bij het beeld: alleen een PNG is geen
ontwerpcontract, want die is niet opnieuw op te bouwen.
