# Mockupset 39: Big P op iPhone, iPad en als tvOS-variant

Status: APPROVED (4 oktober 2026). De iOS-beelden A t/m I worden gebouwd, 39 J ook in deze ronde.

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

## Besluit over 39 H

Gekozen: Big P kijkt rechtsonder over de rand van het detailscherm mee, met "Nog 2 titels", zolang je door de titels uit zijn antwoord bladert. Terug naar Home zet hem weer in de gezichtsknop. Het detailscherm heeft geen header met die knop, dus terugschuiven naar de knop viel af. De peek hoort in de detailroute zelf, niet in een overlay boven de routes.

## Besluit over 39 J

De Clippy-vorm komt nu ook op tvOS, in deze ronde: de ballon en Big P rechts, in plaats van het zwevende paneel.

## Wat de bouw nodig heeft

De armposes staan al in de app. `assets/branding/bigp/` heeft `pose-zwaaien.png`, `pose-vinger_presenteren.png` en `pose-duim_presenteren.png` als gelaagde assets, en `BigPAvatar` kiest de pose per stemming. De hangende armen van `body.png` met de bezorgde wenkbrauwen zijn de bezorgde vorm. Er komt alleen `still-zwaaien.png` bij, een platte afbeelding voor de peek op het detailscherm, zodat daar geen ticker draait. `pose-wijzen_links.png` blijft ongebruikt: de avatar valt al terug op `vinger_presenteren`.

## Opnieuw renderen

`python3 gen39.py` schrijft de HTML. De PNG's zijn op 2x gerenderd met Playwright (Chromium, `deviceScaleFactor: 2`). iPhone is 402x874 pt, iPad 1180x820 pt, tvOS 1920x1080.
