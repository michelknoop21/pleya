# Pleya tvOS — bibliotheekbreedte, ontwerpvoorstel

Roadmap: A-06/A-06b. Register: A06B-WIDTH1. Dit is de interactieve HTML-ontwerpreferentie,
goedgekeurd door Michel op 22 oktober 2026, inclusief de ruimere art/titelafstand.
De appimplementatie en haar eigen bewijsstatus staan onder A06B-WIDTH1-BUILD in het register.
De mockup zelf is geen bewijs voor native tvOS of hardwareacceptatie.

Gebaseerd op Michels IMG_0091/0092/0093 en zijn keuze voor zes grote posters met
een aangesneden volgende rij. Aanvullende referentie: [Netflix TV redesign](https://www.netflix.com/tudum/articles/netflix-new-tv-layout).
De mockup behoudt Pleya's typografie en merkassets uit de bestaande TV-mockupset.

## Bekijken

Start vanuit de repositoryroot:

```sh
python3 -m http.server 8794 --bind 127.0.0.1 --directory docs/assets
```

Open <http://127.0.0.1:8794/tvos-library-width-2026-10-22/>. Stop de server na gebruik.
Nooit via `file://`: de catalogus wordt via HTTP geladen.

- Pijltjes: door de kaarten; omhoog vanaf rij 1 naar de navigatie.
- Esc: terug naar de navigatie; omlaag opent de eerste rij in dezelfde kolom.
- F: Films/Series. H: uitleg tonen/verbergen.
- `?clean=1`: beeld zonder bedieningsuitleg.
- `?clean=1&state=browse&kind=films`: Films in bladerstand.

Zes kolommen, 86 px zijmarge, 28 px goot en 268 × 402 px posters op 1920 × 1080.
De afstand van poster tot titel is 32 px; na vergroting en focusring blijft circa
12,5 px vrije ruimte over. Titels staan maximaal op twee regels, daarna ellipsis; volledige titel in de
accessible naam en als tooltip. Bekeken-/voortgangsbadges zijn illustratief.
De sorteervolgorde en overige navigatieroutes zijn niet geïmplementeerd; klikken
meldt dat expliciet. De collectie is representatieve fixturedata, geen live bibliotheek.

## Controle

Met de server actief, Python Playwright en Chrome geïnstalleerd:

```sh
python3 docs/assets/tvos-library-width-2026-10-22/check.py
```

De controle test 1920 × 1080 en 1038 × 584, randfocus, actieve kaart/metadata,
rij- en navigatieovergangen, lange titels, Films/Series en fouten in JavaScript.
Screenshots en `checks.json` staan buiten source in `/tmp/pleya-library-width-evidence/`.
Dit bewijst browsergedrag, niet tvOS-rendering, Siri Remote of leesbaarheid op afstand.

## Beeldbronnen en Unified impact

Posters zijn lokaal opgeslagen voor een stabiele mockup, verkleind tot maximaal
500 × 750. `catalog.json` vermeldt per poster de publieke TMDB- of TVmaze-bron.
Gebruik deze beelden uitsluitend voor dit ontwerpvoorstel; ze zijn geen appassets.
Unified impact: uitsluitend presentatie; bronselectie, rechten en deduplicatie blijven intact.
