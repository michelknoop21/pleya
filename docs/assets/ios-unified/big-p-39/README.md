# Mockupset 39: Big P op iPhone, iPad en als tvOS-variant

Status: PROPOSED, wacht op Michels akkoord. Er is nog geen code voor gebouwd.

De stijl komt uit twee bronnen. De eerste is de iOS-app zoals main (91e02ba2) hem op 3 oktober 2026 tekende: de Verify-screenshots van Home, Mijn Pleya, Zoeken en Instellingen. Daaruit komen de OLED-zwarte achtergrond, de header met lockup, zoek-icoon en avatar, en de ondoorzichtige tabbalk. De tweede bron is de Big P-componentfamilie van tvOS 319: het paneel, de chip "Je vroeg", de titelkaart met statuspil en rangbadge, de kijkcijferkaart en de grijze en witte pillen. De oude northstar-comps en set 38 zijn bewust niet als bron gebruikt. Op de achtergrond staan Blender-posters, omdat de fixture alleen effen vlakken levert.

## De beelden

| Beeld | Wat het vastlegt |
| --- | --- |
| 39 A | De gezichtsknop in de header, tussen zoeken en de avatar. Alleen zichtbaar als Big P beschikbaar is. |
| 39 B | Opgeroepen: Big P zwaait, het toetsenbord staat open en er zijn drie voorbeeldvragen. De knop in de header is een lege ring, want Big P is eruit gesprongen. |
| 39 C | Eerste keer zonder model: één witte knop naar de instelling, en de vermelding dat die instelling via de iCloud-sleutelhanger meegaat. |
| 39 D | Dicteren met de microfoon van het iOS-toetsenbord. Pleya heeft geen eigen spraakherkenning. |
| 39 E | Antwoord met titelkaarten. Elke film is een kaart met poster: openen als hij in de bibliotheek staat, aanvragen als hij ontbreekt. De drie vervolgvragen staan naast Big P. |
| 39 F | Kijkcijfers: de ballon groeit naar een groot paneel met de kijkcijferkaart en gerangschikte titels. |
| 39 G | Bevestigingskaart voor een gevoelige actie. Er is geen invoerbalk en wegvegen kan pas na de keuze. |
| 39 H | Na een tik op een titel: Big P kijkt rechtsonder over de rand van het detailscherm mee, met "Nog 2 titels". |
| 39 I | iPad liggend: dezelfde ballon, breder, met kaarten in twee kolommen. |
| 39 J | tvOS-variant: de Clippy-vorm als alternatief voor het huidige zwevende paneel. De kaart met focus heeft de witte rand. |

## Open punt in 39 H

Afgesproken was dat Big P na een tik op een kaart terugschuift naar zijn gezichtsknop. Het detailscherm heeft geen header met die knop, dus 39 H stelt iets anders voor: Big P blijft klein aan de rand staan zolang je door de titels uit zijn antwoord bladert. Terug naar Home zet hem weer in de knop. Dit vraagt een expliciete keuze.

## Wat de bouw nodig heeft

De app bevat nu alleen de gelaagde motion-assets (`assets/branding/bigp/`). De zwaai-, presenteer-, duim- en bezorgde poses met armen staan alleen in `docs/assets/tvos-unified/src/assets/bigp/`. Die moeten mee de app in. `pose-wijzen_links.png` is smaller getekend dan de rest en oogt op een telefoon geknepen. Michel keurde hem daarom af op 3 oktober.

## Opnieuw renderen

`python3 gen39.py` schrijft de HTML. De PNG's zijn op 2x gerenderd met Playwright (Chromium, `deviceScaleFactor: 2`). iPhone is 402x874 pt, iPad 1180x820 pt, tvOS 1920x1080.
