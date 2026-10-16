# Mockupset 45: Kinderen in huis (Big P)

Status: VOORSTEL, wacht op akkoord van Michel. Geen app-code. Roadmap: BP-11c (editor bij BP-11b, PR 365).
Plan: "Fase BP-11c" in het Big P-masterplan. Gebouwd pas na akkoord, daarna Pleya Verify met screenshots.

Michel voert zijn kinderen één keer in (naam plus geboortemaand, bijvoorbeeld "Sam, mei 2023"). Big P filtert daarmee voorstellen voor "mijn kinderen" op elk profiel. Alle gegevens blijven op dit toestel (`household_kids`, deviceLocal). De namen gaan nooit naar het AI-model; het model krijgt alleen "jongste bedoelde kind: 3 jaar". De leeftijd rekent de code streng uit hele maanden uit (BP-11b). Onder de twee jaar staat er "3 maanden" in plaats van jaren.

Kleuren komen uit `lib/theme/mono_theme.dart` (donker en licht), de bouwstenen uit set 43 en 44, de kaart uit 39 G en de bestaande leeftijdenkaart (`big_p_kids_ages_card.dart`), de tv-taal uit set 43 M. Alle PNG's zijn 2x. Opnieuw renderen: `python3 gen45.py`.

## De beelden

iPhone 402x874, donker en licht (`<beeld>-dark.png`, `<beeld>-light.png`). iPad 1180x820, donker en licht. tvOS 1920x1080, alleen donker.

| Beeld | Scherm |
| --- | --- |
| 45 A `45-a-ingang` | Instellingen > Big P: de rij "Kinderen in huis" vervangt "Leeftijden kinderen (dit profiel)" op een volwassen profiel |
| 45 B `45-b-lijst` | de lijst met kinderen en hun berekende leeftijd, "Kind toevoegen", uitleg over privacy |
| 45 C `45-c-leeg` | lege staat |
| 45 D `45-d-toevoegen` | sheet Kind toevoegen: naam, maand en jaar als wielkiezer, voorbeeld "Wordt nu 3 jaar" |
| 45 E `45-e-bewerken` | sheet Kind bewerken, met Verwijderen |
| 45 F `45-f-wissen` | bevestiging bij Verwijderen |
| 45 G `45-g-kaart` | de kaart in het Big P-gesprek als er nog geen kinderen zijn: "Voor welke kinderen?" |
| 45 H `45-h-kinderprofiel` | Instellingen > Big P op een kinderprofiel |
| 45 I `45-i-ipad` | iPad: lijst links, bewerkpaneel rechts |
| 45 J `45-j-tv-lijst` | tvOS: de lijst met focus op een kind |
| 45 K `45-k-tv-naam` | tvOS: Kind toevoegen, focus op Naam |
| 45 L `45-l-tv-maand` | tvOS: focus op Maand, omhoog en omlaag kiest |

## Wat elk scherm doet

**Lijst (A, B, C).** Kinderen staan oudste eerst, met de leeftijd rechts. Een tik opent het bewerkpaneel. De uitlegregel onder de lijst zegt wat er gebeurt: alleen op dit toestel, namen nooit naar het model. In de lege staat staat dezelfde regel, plus een knop. Dubbele namen mogen. Maximaal 8 kinderen.

**Toevoegen en bewerken (D, E, F).** Eén sheet voor beide. De wielkiezer toont maand en jaar; tikken op Naam opent het toetsenbord en klapt de kiezer in tot een regel "mei 2023" die weer uitklapt bij een tik. Het voorbeeld onder de kiezer geeft meteen de leeftijd. Bewaar blijft grijs tot er een naam en een maand zijn. Een toekomstige maand kan niet gekozen worden. Een kind van 18 of ouder blijft bewaard, maar krijgt de regel "Telt niet meer mee" in plaats van een leeftijd. Verwijderen vraagt altijd bevestiging. Bij het laatste kind staat er een extra zin: Big P vraagt ze daarna opnieuw als je naar je kinderen vraagt.

**Kaart in het gesprek (G).** Verschijnt op een volwassen profiel zodra de vraag over "mijn kinderen" gaat en er geen kinderen zijn. Zelfde opmaak als de bestaande leeftijdenkaart (Pleya vraagt, geen bericht van Big P), met naam, maand en jaar in plaats van een leeftijdschip. "Nog een kind toevoegen" voegt een regel toe, het eerste kind staat dan als chip erboven. "Bewaar en zoek verder" bewaart en stelt de vraag opnieuw (zelfde patroon als `saveKidsAgesAndRetry`). Menu of wegtikken laat het antwoord staan en sluit de kaart. Op tvOS is het dezelfde kaart als paneel, met de invoer van K en L.

**Kinderprofiel (H).** "Kinderen in huis" is verborgen, niet vergrendeld: de namen en geboortemaanden van het huishouden zijn voor een ouder. "Leeftijden kinderen (dit profiel)" blijft bestaan en blijft de poort van dit profiel bepalen.

**tvOS (J, K, L).** Focusvolgorde in de lijst: kinderen van boven naar beneden, dan Kind toevoegen. OK op een kind opent hetzelfde paneel als bewerken, met Verwijderen onderaan en dezelfde bevestiging. In het paneel: Naam, Maand, Jaar, Annuleren, Bewaar. OK op Naam opent het systeemtoetsenbord (dicteren via de microfoonknop). Op Maand en Jaar kiest omhoog en omlaag direct de waarde, links en rechts wisselt tussen Maand en Jaar, OK springt naar Bewaar. Menu sluit het paneel zonder te bewaren.

## Besluiten

- Rij bij Big P, niet bij Kinderprofiel: het is huishoudinformatie voor een volwassen profiel, het kinderprofiel is een apart begrip.
- Verborgen op kinderprofielen: een kind hoort de namen van zijn broers en zussen niet te kunnen bewerken of lezen.
- Maand en jaar als twee velden, geen datum: het model en de poort hebben alleen de maand nodig, een dag vraagt om gegevens die niemand nodig heeft.
- Leeftijd berekend en getoond naast het kind: zo ziet Michel meteen wat Big P gebruikt.
- Geen sync, geen export (zoals in BP-11b): dezelfde regel als de overige deviceLocal-voorkeuren, sync komt later met BP-08b.
- De leeftijden van het kinderprofiel blijven per profiel: een kinderprofiel werkt zo ook op een toestel waar geen ouder kinderen invoerde.

## Open vragen voor Michel

1. Moet een kinderprofiel zonder eigen leeftijden terugvallen op het jongste kind uit het huishouden, of blijft het ongefilterd tot een ouder "Leeftijden kinderen (dit profiel)" invult?
2. Is 8 kinderen het goede maximum?
3. Wil je op iPhone een tik op de rij voor bewerken (zoals getekend), of een veegactie voor Verwijderen erbij?
4. Moet het geheugenoverzicht (set 43) de namen van de kinderen noemen, of blijft het bij "Je hebt twee kinderen. Hun leeftijden staan bij Kinderen in huis."?
5. Een kind van 18 of ouder: bewaren met een grijze regel (getekend) of bij het bewaren weigeren?
