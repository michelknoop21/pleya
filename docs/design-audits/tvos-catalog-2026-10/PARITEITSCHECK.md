# Pariteit met `2026-10-30-set2`

Referenties staan buiten de repo in `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-northstar-refs/2026-10-30-set2/` (`01.png` tot en met `03.png`, 3840 x 2160). `01` toont het raster gesorteerd op titel, met rechts een A-Z-strip. `02` toont het sorteerpaneel met elf rijen. `03` toont het raster gesorteerd op Critic Rating, met een score als tweede regel en een Wissen-chip. Het Verify-bewijs staat in `MANIFEST.md`.

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
| Elf sorteerrijen (Title, Year, Release Date, Critic Rating, Audience Rating, Rating, Content Rating, Duration, Progress, Plays, Date Added) | deels | de unified sortering heeft vier velden: Titel, Toegevoegd, Release, Bekeken. Uitbreiding volgt in een aparte ronde |
| Score met tomaatje als tweede regel (`03.png`) | niet gebouwd | geen scoresortering in unified (hoofdstuk 10.5) |
| Posterbreedte 152 logisch (235 van 1600) | afwijking | 145 x 217,5 logisch (268 x 402 pt): twee rijen op 584 hoog laten niet meer toe |
| Bovenste focusring binnen de band van 8.1 | afwijking | voet van rij twee zakt onder focus 5 px de band in |
| Nederlandse labels | afwijking | de referentie is Engels, de app volgt de taalkeuze |

Beelden die dit onderbouwen: zie `MANIFEST.md`.
