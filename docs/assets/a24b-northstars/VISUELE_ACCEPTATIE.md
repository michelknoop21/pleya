# A-24b: controleer mockup naast echte Pleya-build

Kijk op **ieder platform** naast elkaar naar dezelfde pagina, thema, tekst, focus en zichtbare/verborgen functies. Vink af met screenshotbewijs. Een stilstaande mockup heeft illustratieve inhoud; verifieer functionaliteit altijd in bron en simulator.

## Instellingen · Apple TV

| Controle | In de gekozen northstar | Vereiste build-check |
| --- | --- | --- |
| Categorieën | Weergave, Afspelen, Taal en ondertitels, Bibliotheken, Home aanpassen, Koppelingen, ieder met icoon; overige bestaande groepen logisch doorlopend | Juiste categorieën en volgorde, geen verloren oude routes |
| Header | `Instellingen` en `Jouw kijkervaring, tot in detail.` | Zelfde teksthiërarchie, niet een kale oude menukop |
| Actieve sectie | `WEERGAVE` boven `Zo ziet jouw Pleya eruit` | Grote titel en gekozen categorie zichtbaar |
| Achtergrond | Subtiele warme wash/gradient; afzonderlijk warm gebroken wit in lichtmodus | Beide thema's daadwerkelijk gerenderd, contrast bruikbaar |
| Rijen | Fijne scheiding en actuele waarde rechts | Dichtheid, labels, waarden, leesafstand en focus |
| Directe schakelaar | Liquid Glass zichtbaar in de rij | Select op de hele rij wisselt, geen extra focusstop of onnodige subpagina |
| Voorbeeldkaart | `LIVE VOORBEELD`, drie posters, `Jouw bibliotheek`, modusregel, `Bekijk voorbeeld` | Kaart, inhoud en actie aanwezig waar de mockup die toont |

## Instellingen · iPhone

| Controle | In de gekozen northstar | Vereiste build-check |
| --- | --- | --- |
| Kop en media | `Instellingen`, `PLEYA · PERSOONLIJK`, `Maak Pleya helemaal van jou.`, filmbeeld | Typografie en artwork. Test fixtures plus lege toestand |
| Structuur | Groepen `VOOR JOU` en `VERBINDINGEN EN PROFIELEN` in startbeeld, volgende groepen scrollbaar | Huidige instellingen verplaatst naar gekozen groepen en verderop bereikbaar |
| Rijen | Compacte lijst, dunne separators, rustige lijniconen zonder grote vierkante icoonbadges | Geen overname van oude grote knoppen/tegelstructuur |
| Weergave | Bovenaan een kaart met echte titel en voorbeeld, hieronder huidige waarden | `Live voorbeeld`, themakeuze, effecten, directe beschikbare switches |
| Gedrag | Zoekfunctie, scrollen, bestaande inklappende/verschijnende header | Test na scrollen omlaag en omhoog, plus terugnavigatie |

## Mijn Pleya · iPhone Editorial

| Controle | Northstar | Vereiste build-check |
| --- | --- | --- |
| Profiel | Compacte profielregel, naam, correcte online-serverstatus | Tik/wissel naar werkelijk profiel |
| Kijklijst | Echte posters direct onder profiel; `Bekijk alles` | Door profiel/provider gevoed, lege toestand apart |
| Content | Rustige kleine rijen voor Bibliotheken, Downloads en Aanvragen indien beschikbaar | Geen oude grof gerasterde knoppen |
| Big P | Herkenbare compacte kaart, met Pleya-illustratie | Bestaande Big P-route en juiste capability |
| Overige | Servers, Activiteit, Samen kijken, Instellingen, Over Pleya, Uitloggen en bestaande profielacties bereikbaar | Alle bestaande bestemmingen in matrix, scrollbaar waar nodig |

## Mijn Pleya · Apple TV Editorial

| Controle | Northstar | Vereiste build-check |
| --- | --- | --- |
| Top | Pleya-navigatie, titel, compacte profielregel, `Profiel wisselen` en status | Eén remote-focus, terug naar laatst gefocuste actie |
| Kijklijst | Brede rail met posters en `Bekijk alles` | Links/rechts-focus, geen overlapping |
| Mijn content | Collecties, Afspeellijsten, Aanvragen waar beschikbaar | Normale focusvolgorde inclusief ontbrekende modules |
| Bronnen | Bibliotheken, Servers, Activiteit en Samen kijken | Dynamische condities behouden |
| Rechterkant | Big P en compacte beheeracties, waaronder Instellingen | Correcte koppelingen en focusherstel |
| Thema | Donkere en lichte variant, leesbare focusring en posters | Vergelijk `05-tvos-licht.png` en de focusbeelden |

## Bewijs per afwijking

Bewaar voor elk van bovenstaande punten:

- Het exacte northstarbestand en de build-screenshot van dezelfde staat.
- **Match / afwijking / functie voorwaardelijk niet beschikbaar**, met concrete motivatie.
- Bij afwijking: zichtbaar verschil, ernst, besluit, taak en status. Voer de kleinste bijstelling uit en maak het screenshot opnieuw.
- Pariteitscontrole per route inclusief huidige locatie, nieuwe locatie, provider en platformvoorwaarde.

**Klaar** betekent dat de schermen daadwerkelijk in Pleya zijn aangepast en vergeleken, alle bestaande functies zijn verantwoord en resterende verschillen zichtbaar zijn vastgelegd. Een stylingpatch op de oude indeling voldoet niet.
