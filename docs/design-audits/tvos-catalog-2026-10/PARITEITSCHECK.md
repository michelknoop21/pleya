# Pariteit met `2026-10-30-set2`

Referenties staan buiten de repo in `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-northstar-refs/2026-10-30-set2/` (`01.png` tot en met `04.png`, 3840 x 2160). `01` toont het raster gesorteerd op titel, met rechts een A-Z-strip. `02` toont het sorteerpaneel met elf rijen. `03` toont het raster gesorteerd op Critic Rating, met een score als tweede regel en een Wissen-chip. `04` toont het raster op Year, gelijke jaren op titel. Het Verify-bewijs staat in `MANIFEST.md`.

| Punt in het beeld | Resultaat | Toelichting |
|---|---|---|
| Zes kolommen, twee rijen met posterhoogte uit het beeld | gehaald | Verify `tvos.catalog.full-bleed.grid`, beeld `00-rest.png` |
| Kop met tabbladen, klok en filterchips (`Alles`, `Movies`, `door Title`, `485 items`, Wissen) boven het raster | niet gebouwd | de opdracht is een raster zonder balken; bron, filter en sortering zitten in het paneel |
| Verticale A-Z-strip rechts naast het raster | afwijking | Spring naar is een rij in het paneel (besluit Michel), geen permanente strip |
| Vinkje rechtsboven op gekeken kaarten | deels | vinkje en ongekeken-aantal delen die hoek |
| Paneel over een gedimde pagina, gefocuste rij wit | gehaald | beeld `00-panel-open.png`, `01-sort-page.png` |
| Richtingpijl rechts op de actieve sorteerrij | gehaald | pijl omlaag voor oplopend, omhoog voor aflopend |
| Paneel aan de rechterkant | afwijking | het paneel schuift van links, omdat de topnavigatie en LEFT vanaf kolom 0 de ingang zijn |
| Zijbalk met pictogrammen links | afwijking | de inklapbare topnavigatie blijft (besluit Michel) |
| Elf sorteerrijen (Title, Year, Release Date, Critic Rating, Audience Rating, Rating, Content Rating, Duration, Progress, Plays, Date Added) | gehaald, per bron | dertien rijen in de volgorde van `library_menu_definition.dart`, met Bekeken en Resolutie erachter. Een rij verschijnt alleen als elke bron hem kan uitvoeren: op Jellyfin tien, op Pleya Server vijf |
| Score met tomaatje als tweede regel (`03.png`) | gehaald | bron-icoon via `MediaRatingBadge`, tomaat plus percentage. Beeld `01-critics-down.png` |
| Gelijke waarden op titel (`04.png`) | gehaald | gelijke jaren en scores lezen op titel, in beide richtingen |
| Titels zonder waarde | gehaald | altijd achteraan, lege tweede regel met gelijke hoogte. Beeld `03-critics-up.png` |
| Posterbreedte 152 logisch (235 van 1600) | afwijking | 145 x 217,5 logisch (268 x 402 pt): twee rijen op 584 hoog laten niet meer toe |
| Bovenste focusring binnen de band van 8.1 | afwijking | voet van rij twee zakt onder focus 5 px de band in |
| Dolby Vision, HDR10+, Atmos en de overige filters van de server in Filteren op | gehaald in code, nog niet tegen een echte server bewezen | zichtbaar zodra de server het filter noemt in `/library/sections/{id}/filters`. Elk boolean-filter komt in de snelle lijst: bekende sleutels (ook `dolbyVision`, `hdr10Plus`, `dovi`) op hun plek met Pleya-label, een onbekend boolean onderaan met het label van de server. Niet-booleans komen als categorie na de scheidingslijn, in serverlabel. Het verzoek gebruikt de `filter`-waarde van de server. Fixture-tests bewijzen de classificatie en het verzoek; een live Plex-server is niet bevraagd. Alleen Plex noemt deze lijst: in een unified catalogus met een andere backend verdwijnen ze, Jellyfin, Emby en Pleya Server blijven zoals de capabilities zeggen |
| Nederlandse labels | afwijking | de referentie is Engels, de app volgt de taalkeuze |

Beelden die dit onderbouwen: zie `MANIFEST.md`.
