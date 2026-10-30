# Rapport: Alle films en Alle series vol in beeld

De catalogus op Apple TV toont zes kolommen bij twee hele rijen, zonder kop en zonder zichtbare balk. Bron, filters, sortering en Spring naar zitten in één paneel dat van links over het raster schuift. Het besluit staat in DEC-XXX, de roadmapregel is A-06c.

## Waar het beeld afwijkt en waarom

1. Het paneel komt van links in plaats van rechts. De topnavigatie blijft bestaan en LEFT vanaf kolom 0 is de enige ingang.
2. Geen zijbalk. Michel koos de inklapbare topnavigatie.
3. Het aantal sorteerrijen volgt de bronnen: dertien op Plex-films, tien op Jellyfin, vijf op Pleya Server. Dolby Vision, HDR10+ en Atmos verschijnen voorlopig nergens: geen enkele backend documenteert een filter ervoor.
4. De poster is 145 x 217,5 logisch, onder de 152 uit het plan. Twee rijen op 584 hoog laten niet meer toe.
5. De voet van rij twee zakt onder focus 5 px in de band van hoofdstuk 8.1.
6. Geen tabbladen, klok en filterchips boven het raster, en geen permanente A-Z-strip rechts: de beelden tonen die, de opdracht vraagt een raster zonder balken en Spring naar zit in het paneel.

## Gedrag dat Michel moet weten

Kiezen sluit het paneel en zet de ring op kaart 0, ook bij een snelle filter. Categorieën blijven achter Toepassen. Omkeren blijft bereikbaar: LEFT, Sorteren, Select, en dezelfde rij nogmaals kiezen. Menu gaat een pagina terug en sluit op het overzicht.

## Bewijs

Simulator: PASS voor `panel`, `grid` en `jump`, paden in `MANIFEST.md`. Widgettests en `scripts/ci_checks.sh` groen. Dit is geen hardwarebewijs.

## Apple TV-checklist voor Michel

1. Open Alle films. Controleer zes kolommen en twee hele rijen, geen balk bovenin.
2. Blader rechts door een hele rij, daarna omlaag door alle rijen tot het einde van de lijst, en omhoog terug naar rij 1. Op rij 1 doet UP niets.
3. Wissel van rij en druk daarna LEFT en RIGHT: de ring blijft in de nieuwe rij.
4. Blader links tot kolom 0 en druk LEFT: het paneel opent op Bronnen, de wand verschuift niet.
5. Ga omhoog en omlaag door het paneel, in alle vier de pagina's (Bronnen, Filters, Sorteren, Spring naar). Aan de uiteinden gebeurt niets.
6. Kies Sorteren, Titel: de lijst draait naar Z-A en de ring staat op kaart 0. Open het paneel opnieuw en kies Titel nogmaals: terug naar A-Z.
7. Kies elke sorteerrij die er staat: de tweede regel volgt, en titels zonder waarde staan onderaan in beide richtingen. Controleer op een Plex-server of de rijen Jaar, Duur, Voortgang en Resolutie verschijnen en echt sorteren, en of Filteren HDR, Niet gekoppeld en Dubbel toont.
8. Spring naar bij Titel A-Z en bij Z-A: de ring landt op de gekozen letter, ook diep in een grote bibliotheek.
9. Menu op een sorteerpagina gaat naar het overzicht, Menu op het overzicht sluit het paneel, Menu op het raster verlaat de route.
10. Controleer Alle series, een filter met Wissen, en een bibliotheek van meer dan 500 titels op soepelheid.
11. Beperk de bronnen tot Pleya Server terwijl op Critici gesorteerd is: de lijst valt op Titel A-Z. Haal de beperking weg: Critici komt terug.
