# Alle films en Alle series op Apple TV: inventaris van functies

Stand van commit `61dac7291` op `feat/tvos-catalog-fullbleed`. Route: `_openTvCompleteCatalog`, scherm `TvUnifiedCatalogScreen(fullBleed: true)` (`lib/screens/main_screen.dart:2565`). Elke rij zegt of de functie de herbouw heeft overleefd. Kijklijst, Aanvragen, de offline-root, `tv_libraries_screen` en `tv_content_feed` gebruiken hetzelfde scherm zonder `fullBleed` en zijn niet geraakt.

| Functie | Voor de herbouw | Nu op de fullBleed-route |
|---|---|---|
| Raster | 5 of 6 kolommen, anderhalve rij zichtbaar, kaart krimpt als de rail opent | 6 kolommen, 2 hele rijen op 1038 x 584, geen krimp bij paneel |
| Kaart openen | Select opent detail of bronkiezer | ongewijzigd (`_activate`) |
| Contextmenu | lang drukken: afspelen, vanaf begin, meer info, bron wisselen | ongewijzigd (`_openContextMenu`) |
| Paginakop met titel en tags | boven het raster | weg |
| Topnavigatie | scroll-away | `collapsible`: weg zolang de focus in de pagina staat, UP vanaf rij 0 doet niets |
| Rail met Bronnen, Filters, Sorteren | links van het raster | één paneel over een gedimde pagina, LEFT vanaf kolom 0 |
| Sorteerkiezer | gecentreerde modal, zeven rijen | pagina in het paneel, één rij per sorteerveld dat alle bronnen kunnen, met richtingpijl in accentkleur |
| Filterkiezers | gecentreerde modal | pagina in het paneel: snelle keuzes (direct toegepast), scheidingslijn, categorieën (achter Apply) |
| Spring naar | bestond niet | rij in het paneel bij sorteren op titel, `#` en A-Z |
| Tweede regel onder de titel | jaar | volgt de sortering; score met bronicoon, jaar, datum, duur, positie, afgespeeld, leeftijd of resolutie; leeg zonder waarde |
| Ongekeken-aantal | niet op de TV-kaart | rechtsboven op de kaart |
| Gestippeld sorteerlabel | altijd zichtbaar | alleen bij een andere sortering dan de standaard of naast filtertags |
| Wissen | in de rail | rij in het paneel zolang een filter actief is |
| Dichtheid | voorkeur 1 tot 5 | blijft: 3 tot en met 5 geven 6 x 2 op volle maat |
| Doorladen | op de achtergrond tot de bibliotheek compleet is | ongewijzigd, nu ook door Spring naar gebruikt tot de grens van 3000 |
| Lege, gefilterd-lege en foutstaat | eigen actie (Verversen of Wissen) | ongewijzigd, LEFT opent het paneel |
| Menu | sluit rail, dan route | sluit pagina, dan paneel, dan route |
| Bronbeschikbaarheid, offline, bronkiezer | via `_activate` | ongewijzigd |

Wat bewust niet meekomt uit het beeld staat in `PARITEITSCHECK.md`.
