# Big P, motion-prototype bij mockup 38

Een klikbaar, zelfspelend prototype van de Big P-schermen op Apple TV. Het beeld is 1920 x 1080 en schaalt mee met het browservenster. Status: voorstel, geen bouwopdracht. Dit is de tweede ronde (2 oktober 2026): Big P beweegt veel meer, praat zijn antwoorden uit, en het gesprek staat in een smal glaspaneel in plaats van over de volle breedte.

## Openen

Dubbelklik `index.html` (Chrome of Safari, rechtstreeks van schijf). Er is geen server nodig en er wordt niets van internet geladen; Inter staat in `assets/`.

Onder het tv-beeld staat de bediening: Pauze/Afspelen, Volgende stap, een knop per scene, "Lang drukken Play/Pause" (roept Big P op in scene 0 en 0c) en "Minder beweging". Die laatste doet hetzelfde als de systeeminstelling voor minder beweging. Big P blijft bewegen als het script gepauzeerd is.

`index.html?scene=4` begint bij een scene. `index.html?still=4` stopt op het sleutelmoment van die scene, laat Big P 0,9 s bijkomen en bevriest hem buiten een knipper; zo zijn de stills gemaakt.

## Scenes

| Nr | Naam | Wat je ziet |
|----|------|-------------|
| 0 | Oproepen | Films-catalogus op Zolder. Na lang drukken op Play/Pause springt Big P rechtsonder in beeld, het toetsenbord schuift omhoog. Gedicteerd: "Scan deze bibliotheek opnieuw." Twee stappen, juichen, hij zegt het antwoord met een duim omhoog en springt weer weg. |
| 0c | Oproepen, bevestiging | Zelfde ingang, nu een gevoelige actie. De Pleya-kaart staat midden in beeld; Big P kijkt ernaar en knikt als je bevestigt. |
| 1 | Rust | Mijn Pleya ▸ Big P. Big P springt binnen, zwaait en zegt "Hoi Michel, wat moet er gebeuren?". Daarna rust: zweven, knipperen, af en toe kijken naar de voorbeeldvragen. |
| 2 | Luisteren | Toetsenbord met dicteren. Big P staat kleiner boven het toetsenbord, met ronde mond, wenkbrauwen omhoog, hoofd scheef dat van kant wisselt, en een knikje per binnenkomend woord. |
| 3 | Werken | Stappenlijst die per server afvinkt. Big P wijst met zijn arm de nieuwste stap aan, de arm volgt de lijst omlaag; elke afgeronde stap krijgt even de vinger omhoog. |
| 4 | Resultaat | Juichen met een sprong, dan zegt hij het antwoord woord voor woord met een duim omhoog en komt tot rust. |
| 5 | Gebruiker aanmaken | Dicteren, drie controlestappen, bevestigingskaart. Big P stapt opzij, kijkt naar de kaart en knikt bij Aanmaken, daarna het resultaat. |
| 6 | Fout | Zolder offline. Big P schudt het hoofd, zakt door, kijkt bezorgd en zegt de foutmelding rustig, zonder nadruk. |
| 7 | Aanvragen op beschrijving | "Die film waarin een astronaut alleen achterblijft op Mars en aardappels kweekt." Stappen: titels bedenken, Seerr doorzoeken. Vier keuzekaarten in het paneel (poster als kleurvlak, titel, jaar, één regel beschrijving, status). Big P wijst de kaart met focus aan; kiezen opent de Pleya-kaart "The Martian (2015) aanvragen" met focus op Annuleren, daarna het resultaat. |

De stills staan in `docs/assets/tvos-unified/mockups-2026-10-02-big-p/motion/`: `38-motion-0.png` (opgeroepen, luistert), `38-motion-0b.png` (opgeroepen, resultaat met duim), `38-motion-1.png` tot en met `38-motion-6.png`, en `38-motion-7.png` (keuzekaarten, Big P wijst The Martian aan).

## Paneel

Het gesprek staat in een zwevend glaspaneel van 800 px breed rechts van Big P, onderaan verankerd: het nieuwste staat onderaan en het paneel groeit naar boven. Antwoordtekst op 34 en 25 px komt uit op 45 tot 55 tekens per regel. De vraag van de gebruiker staat als compacte geciteerde regel rechts boven het antwoord. Stappen, resultaatkaarten, keuzekaarten en voorbeeldvragen blijven binnen de paneelbreedte en lopen door naar een tweede regel.

Het Pleya-scherm blijft eronder zichtbaar, vervaagd (blur 14) en gedimd, zodat Big P als laag over Pleya ligt en niet als losse pagina met veel lege ruimte. Het glas is het tvOS-nepglas van LG-04 tot en met LG-06 (`docs/assets/liquid-glass/src/tv-glass.css`: blur 30, verzadiging 1,2, demping 0,80, witte tint 12 procent, lichtrand), hier in `index.html` ingevoegd. Kaarten op het glas houden een donkere ondergrond van 45 tot 72 procent, zodat tekst niet van de achtergrond afhangt (contrastregel uit `docs/liquid-glass-mockups-2026-09.md`). De focusring blijft de witte ring met ring-gap.

Bevestigingskaarten zijn van Pleya, niet van het gesprek: ze blijven ondoorzichtige kaarten midden in beeld, nu 880 px breed. Opgeroepen staat een paneel van 570 px links naast de Big P in de hoek, in hetzelfde glas.

Gebruikt als referentie:
- `docs/liquid-glass-mockups-2026-09.md` en de pagina's `LG-04-home`, `LG-05-spelerpaneel`, `LG-06-zoeken` in `docs/assets/tvos-unified/src/pages/`.
- Gemini op Google TV toont antwoorden in een paneel over wat je aan het doen bent in plaats van een volledig scherm: [9to5Google, hands-on, januari 2025](https://9to5google.com/2025/01/09/google-tv-gemini-hands-on/); [9to5Google, maart 2026](https://9to5google.com/2026/03/24/gemini-google-tv-visuals/) over beeld en tekst in de antwoorden.
- Liquid Glass sinds tvOS 26, variant regular als standaard voor de meeste UI: [Wikipedia, Liquid Glass](https://en.wikipedia.org/wiki/Liquid_Glass) en [conor.fyi, Liquid Glass reference](https://www.conor.fyi/writing/liquid-glass-reference). De HIG-pagina Materials kon niet worden opgehaald (rendert alleen met JavaScript).

## Hoe Big P beweegt

Alles zit in `bigp.js`: één `<svg>` per Big P met één rig-groep. Beweging is een transform op die groep, op de arm, de wenkbrauwen of de oogleden, plus wisselen welke laag zichtbaar is. Dat past op een Flutter-widget met een paar `AnimationController`s en `Transform`.

Het gedrag komt uit de Remotion-template van de big-p-skill (`~/.claude/skills/big-p/template/src/BigP.tsx`, `poses.ts`, `mouth.ts`, `talk.ts`):

- Doorlopend: zweven tot 22 render-px boven de vloer in 3,1 s (schaduw krimpt mee), wiegen rond de voeten tot 1,6 graad in 6,3 s, ademen (hoogte 1,4 procent op en neer), elke 2 tot 4,5 s een nieuwe hoofdkanteling tot 2,6 graad. Knipperen duurt 150 ms, om de 1,8 tot 4,5 s, een op de vijf keer dubbel.
- Overgangen lopen via een licht onderdempte veer (stijfheid 150, demping 0,72): een fractie doorschieten, dan stil, geen getril.
- Sprong: inveren, strekken bij het afzetten, parabool, platdrukken bij de landing, met volumebehoud in de breedte. Bij oproepen, bij het begin van elke scene en bij succes. Weggaan is een sprongetje met de neus naar de uitgang.
- Houdingen wisselen zonder overvloeien (SKILL.md: overvloeien geeft spookarmen): het beeld springt halverwege een wissel van 270 ms terwijl het lichaam inveert. Elke houding zakt naar zijn eigen voethoogte uit `bigp-layers.json`.
- Praten: per woord lettergrepen uit de klinkergroepen. Per lettergreep `small`, dan de klinkervorm (`o` voor o/oe/u, `e` voor i/ie/ee/e/ij, anders `mid`, `big` op de eerste lettergreep van een benadrukt woord), dan half dicht. De mond opent hooguit één stand tegelijk en is dicht tussen zinnen. Op benadrukte woorden (lang, naam, cijfer) knikt het lijf en gaan de wenkbrauwen omhoog. Zolang de mond open is zakt het lijf iets door.

| Stand | Houding en gezicht | Beweging |
|------|------|------|
| rust | armen omlaag, mond dicht | alles hierboven; om de 6 tot 11 s 1,7 s kijken naar de voorbeeldvragen (kantelen en iets zakken); om de 15 tot 25 s zwaaien |
| luisteren | ronde mond, wenkbrauwen omhoog | zakt iets in, hoofd 4 graden scheef en wisselt elke 2,5 tot 4 s van kant, knikje per woord, duidelijke knik aan het eind van een zinsdeel, minder knipperen |
| werken | wijsarm (`body-wijzen` met `aim-arm`), denkende wenkbrauwen die om de 1,4 s van kant wisselen | arm richt via een veer op de nieuwste stap (-12 tot 60 graden), hoofd draait mee bij elke nieuwe stap, 850 ms vinger omhoog (`vinger_presenteren`) als een stap klaar is |
| succes | juichen met sprong, daarna duim (`duim_presenteren`) en praten | na het antwoord terug naar rust |
| fout | bezorgde wenkbrauwen, ronde mond | hoofdschudden (2,5 keer heen en weer in 1,3 s, uitdovend), zakt 18 px, zweeft minder; praat rustig, zonder nadruk |
| bevestiging | wenkbrauwen iets omhoog | stapt opzij en kantelt naar de kaart, zweeft weinig, knikt bij bevestigen |
| opgeroepen | dezelfde figuur, kleiner, inhoud links | kijkrichting gespiegeld; werken met `wijzen_links` (driekwartaanzicht) omdat de wijsarm alleen naar rechts kan |

Minder beweging (vinkje of systeeminstelling): geen zweven, wiegen, ademen, knipperen, sprongen of knikken, en de arm zwaait niet. Houding, wenkbrauwen en mond wisselen direct; tijdens praten staat de mond op `small`.

### Lagen en houdingen

Uit `~/.claude/skills/big-p/avatar/lagen/`, op de helft verkleind in `assets/` en geplaatst op de volle maten uit `bigp-layers.json`:

- `body.png` (rust), `body-wijzen.png` (rust zonder rechterarm) met `aim-arm.png` erachter, gedraaid rond het scharnier `aim`.
- `pose-zwaaien.png` met `wave-arm.png`, 12 graden heen en weer rond het scharnier `wave`.
- `pose-juichen.png`, `pose-duim_presenteren.png`, `pose-vinger_presenteren.png`, `pose-wijzen_links.png`.
- Monden `rest`, `small`, `mid`, `big`, `o`, `e`, `laugh`; `brow-l.png`, `brow-r.png`. De oogleden zijn getekend.

## Wat echt is en wat nagebootst

Echt: de lagen en houdingen hierboven, de beweging en het lettergreepritme. Nagebootst: alle serverdata, taken, percentages, tijden, de Seerr-kandidaten en de stappen van Big P. Het toetsenbord is een benadering van het tvOS-toetsenbord, zoals in 38 E. Posters zijn kleurvlakken met de titel.

## Grenzen

- Er is geen pupillaag. Kijken is een kanteling van de hele figuur; bij de bevestigingskaart schuift Big P bovendien 200 px opzij.
- Alle mondsprites zijn uit lachende mockups gesneden. De bezorgde Big P krijgt daarom de ronde mond; een echte bezorgde mond bestaat niet.
- `wijzen_links` heeft een eigen gezicht: zolang de opgeroepen Big P werkt, knippert hij niet en bewegen wenkbrauwen en mond niet.
- Praten volgt de tekst, niet een stem. Het is ritme, geen lipsync.
- Gecontroleerd in Chromium (Playwright): alle negen scenes achter elkaar en vijf scenes met minder beweging, zonder console-fouten. Safari en een echte Apple TV zijn niet getest.
