# Mockup 34 tot en met 36, goedgekeurd

| Veld | Waarde |
|------|--------|
| Status | APPROVED DESIGN TARGET |
| Goedgekeurd door | Michel Knoop |
| Datum | 7 september 2026 |
| Set | 34 kijklijst, 35 aanvragen, 36 zoeken: twaalf beelden op 1920x1080 |
| In de repo | `docs/assets/tvos-unified/mockups-2026-09-07/` |
| Bron | `docs/assets/tvos-unified/src/pages/3[456]-*.html` |
| Besluit | [DEC-108](DECISIONS.md#dec-108) |
| Komt uit | CAT11 in `tvos-fysieke-correctieronde.md` |

## De tekst in het beeld is niet de status

De notitie rechtsboven in elke PNG zegt nog "PROPOSED". Dat is dezelfde situatie als bij 09
tot en met 25, waar de beelden "CANDIDATE" dragen: **dit manifest is de statusautoriteit,
niet de tekst in het beeld.** De beelden zijn bewust niet opnieuw geschoten om die ene regel
te wijzigen, want dan veranderen de pixels en daarmee de hashes hieronder, terwijl er aan het
ontwerp niets verandert.

## Wat de goedkeuring dekt

Hetzelfde als bij 09 tot en met 25: compositie, hiërarchie, dichtheid, framing,
componentfamilie, en de focus- en kaarttaal. Een schermafbeelding is geen functionele
specificatie. Waar het beeld en een eerder besluit elkaar tegenspreken wint het besluit,
en dat wordt hier per geval genoemd.

## De keuze die erin zat

35 C1 en C2 waren twee kanten van één vraag: Alle aanvragen als raster met een
statuscapsule, of als lijst op TV-maat. **C1 is gekozen**, op drie gronden:

1. Bij de 389 aanvragen die op het toestel staan toont C1 er twaalf per scherm en C2 vijf.
2. De melding waar dit uit voortkomt was dat dit scherm afwijkt van de rest; C2 lost het
   formaat op maar houdt een tweede kaarttaal in stand, C1 haalt de afwijking weg.
3. Het argument vóór C2 was dat een rij zijn eigen goedkeur- en afwijsknoppen kan dragen.
   Op TV telt dat niet: acties lopen daar via het unified contextmenu (PB-5, mockup 12),
   dus een rij met knoppen zou juist de uitzondering zijn.

Wat C1 kost is de datum ("3 dagen geleden"), die naast de aanvrager niet op een kaart van
281 past. Die is bewust opgegeven.

**C2 blijft in de map staan** als vastlegging van wat er is afgewogen, net zoals mockup 26
blijft staan voor het afgewezen bibliotheekcontract. Er wordt niet tegen gebouwd.

## Drie besluiten die in de beelden zaten

Ze zijn met de set goedgekeurd en staan hier apart, want ze zijn makkelijk over het hoofd
te zien.

1. **De kijklijst krijgt geen Bronnen-regel** (34 B). Een kijklijstitem is één identiteit
   over alle servers heen (hoofdstuk 20), dus daar valt niets te kiezen. De rail draagt
   Soort, Beschikbaarheid en Sortering: de bestaande chips in railvorm.
2. **Aanvragen houden hun eigen filtermodel** (35 B). Soort, Genre uit de TMDB-lijst, en
   Status. Geen Bronnen, want een aanvraag heeft nog geen bron. Dit is de uitwerking van
   het besluit om alleen visueel gelijk te trekken.
3. **36 B sluit SEARCH1.** De sectiekop heet "Films 4" en is een kop, geen railtitel: hij
   beweegt niet mee met de focus. Die bevinding stond op DEFERRED.

## De headroom

Op de eerste voordracht viel een gefocuste kaart in de bovenste rij over de paginakop.
Dat is geen tekenfout maar hetzelfde contract dat CAT10 in code afdwingt: een kaart
schaalt 1,05 om zijn onderrand, dus 422 groeit 21 pixels omhoog, plus een ring van 8 gap
en 4 lijn. `tv.css` draagt dat sinds deze ronde als `--focus-headroom: 36px`, en elke band
waarin een kaart de focus kan hebben reserveert het. In code heet die grootheid
`TvCatalogGrid.focusHeadroom` en zit hij in `scrollPadding`.

## De beelden

| Nr | Bestand | SHA256 |
|----|---------|--------|
| 34 A | 34-kijklijst-a.png | `302ad404279f5c43fc1569f75a9e79d6a1626388742031a2b3b1aec7e89e0c18` |
| 34 B | 34-kijklijst-b.png | `f6881045fe67ad0fdc9b5620169570080793c98461c4ea8a8935dca70e4988e9` |
| 34 C | 34-kijklijst-c.png | `94375f042b19b2a584abf927644ab6d75bce1ea5dca5dd7b43b57754f61e3e40` |
| 34 D | 34-kijklijst-d.png | `0fda85dde19e91d1261f159dccc6ef4b13608b5f26285bdac2cf36392d66c6f3` |
| 35 A | 35-aanvragen-a.png | `72bcd2f4d3942a2099754b5899efaab4ad8c2533a701bcb98a3a85235d894386` |
| 35 B | 35-aanvragen-b.png | `ad357c5b4527294ef8001815a6ec3c0075045bd7283435ae44bd768c35001957` |
| 35 C1 | 35-aanvragen-c1.png | `121b8e17f59fb963130ac5cdf2aa894833315f843e69f849255ec07bbad8acba` |
| 35 D | 35-aanvragen-d.png | `52c3c02062086b4ba9fc949a1676b49171e1158bdeba12be97616cc78a2de904` |
| 36 A | 36-zoeken-a.png | `ab5112b956d7d845edffeb78ef57fb46cba3864adb73dede578e03ac182045f1` |
| 36 B | 36-zoeken-b.png | `b0727739a1b3d26387de030e9b642ea8411b37e86cfe4a5453b0b26423427f33` |
| 36 C | 36-zoeken-c.png | `659821c85106f3ed6e93d98d21c40ea3c18a0d1991dd3486c62485b0f0e7ee52` |

Niet goedgekeurd, bewaard als afweging:

| Nr | Bestand | SHA256 |
|----|---------|--------|
| 35 C2 | 35-aanvragen-c2.png | `46e7f48a51d0866e926b49c687513097ea516c4a14b8836085be9b8a9c9f4ff4` |

## Wanneer er opnieuw akkoord nodig is

Dezelfde vier gevallen als bij 09 tot en met 25: een andere compositie dan het beeld
tekent, een componentfamilie die niet in de set voorkomt, een dichtheid die van de
getekende afwijkt, en een gedragswijziging die het beeld niet kan tonen maar die een
eerder productbesluit raakt.
