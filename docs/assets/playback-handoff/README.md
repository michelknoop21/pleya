# Playback Handoff, northstar

Roadmap: A-23. Status: ontwerp goedgekeurd door Michel Knoop op 19 oktober 2026. Geen
hardwarebewijs; dat valt onder A-22.

Deze set vervangt het eerste voorstel (twee losse borden van 18 oktober), dat niet aansloot op de
bestaande northstars. De beelden zijn getekend met dezelfde bronnen als de rest van de set: de
iPhone-staten met de iOS-northstarbron (`20-speler`, `08-bronkeuze-sheet`, `06-film-detail`, 393x852
op 3x, de speler liggend 852x393), de Apple TV-staten met `docs/assets/tvos-unified/src`
(`18-speler` en de startmelding uit mockup 41, 1920x1080).

| Beeld | Scherm | Staat |
|---|---|---|
| `45-a-speler-knop.png` | iPhone-speler | knop naast Cast en AirPlay: een scherm met een afspeeldriehoek |
| `45-b-kiezen.png` | kiezer | "Deze iPhone" met vinkje, Apple TV's met een groene stip "Pleya open" |
| `45-c-bezig.png` | kiezer | spinner op de gekozen Apple TV, de iPhone speelt door |
| `45-d-ander-profiel.png` | kiezer | de Apple TV gebruikt een ander profiel, melding op die regel |
| `45-e-mislukt.png` | iPhone-speler | melding, de iPhone speelt door |
| `45-f-geen-apple-tv.png` | kiezer | geen Apple TV gevonden, uitleg en "Opnieuw zoeken" |
| `45-g-gelukt.png` | detailpagina | de speler is dicht, melding "Speelt nu op Woonkamer" |
| `45-t1-overdracht-speler.png` | Apple TV-speler | melding "Overgedragen vanaf iPhone van ..." |
| `45-t2-overdracht-ander-scherm.png` | Apple TV, ander scherm | dezelfde melding terwijl de film start |

Afwijking van `45-b` (Michel Knoop, 20 oktober 2026): de kiezer in de iPhone-speler was "gigantisch
voor twee kleine opties", en 45-b tekent hem zelf ook te breed. In de speler is hij liggend 440 breed,
zo hoog als zijn regels, en met Liquid Glass aan een doorschijnende plaat waar de film doorheen
blijft lopen. Dat geldt voor alle sheets in de speler, niet alleen voor de kiezer. De regels, teksten
en staten van 45-b tot en met 45-f blijven zoals getekend.

Bronnen: de iPhone-pagina's staan in `src-ios/` en bouwen met `build.mjs` van de iOS-northstarbron
(die staat buiten de repo, net als de art), aangevuld met drie iconen (`handoff`, `tv`, `phone`) die in
de pagina's als `{{icon:...}}` staan. De Apple TV-pagina's staan in
`docs/assets/tvos-unified/src/pages/45-t*.html`:

    PLEYA_MOCKUP_ART=<art-map> PLEYA_MOCKUP_DEST=<uit> node docs/assets/tvos-unified/src/build.mjs 45-t

De art (filmbeelden) staat niet in git; de PNG's hier zijn de bron van waarheid.

Naam en icoon: de functie heet voor gebruikers Pleya Fly (Michel Knoop, 20 oktober 2026). Het icoon
(een Pleya-P met vleugelveren en afspeeldriehoekje) komt uit `docs/assets/pleya-fly/` en vervangt het
schermicoon uit 45-a; de beelden hier blijven het ontwerp van lay-out en gedrag.

## Meenemen (A-23e), voorstel van 8 november 2026

Status: voorstel, wacht op akkoord van Michel Knoop. Niet bouwen voordat de beelden goedgekeurd zijn.
Besluit: DEC-XXX (Pleya Fly Meenemen) in `docs/DECISIONS.md`.

Meenemen laat de Apple TV doorspelen en zet dezelfde titel synchroon op een iPhone of iPad, via
Samen kijken. De beelden volgen dezelfde bronnen als 45-a tot en met 45-t2.

| Beeld | Scherm | Formaat | Staat |
|---|---|---|---|
| `45-h-meenemen-home.png` | iPhone Home | 1179x2556 (393x852 op 3x) | kaart onder de Home-chips zolang een Apple TV in de Home iets speelt: "Speelt op Woonkamer", titel, positie en de knop Meenemen met het Pleya Fly-icoon. Eén tik en de speler opent |
| `45-i-meenemen-speler.png` | iPhone-speler | 2556x1179 (852x393 op 3x) | speelt synchroon zonder geluid; knop "Geluid aan" linksonder, onder de titel een groene stip met "Synchroon met Woonkamer" |
| `45-t3-fly-kiezer-meenemen.png` | Apple TV, spelerpaneel ▸ Pleya Fly | 1920x1080 | per toestel twee rijen, Verplaatsen (de bestaande fly van A-23d) en Meenemen; focus staat hier op Meenemen |
| `45-t4-telefoon-kijkt-mee.png` | Apple TV-speler zonder bediening | 1920x1080 | melding als een telefoon aansluit, in de vorm van 45-t1 |
| `45-t5-speler-kijkt-mee.png` | Apple TV-speler met bediening | 1920x1080 | zolang een telefoon meekijkt staat dat als label in de inforegel |

Keuzes in de beelden die het besluit niet al vastlegt:

- De Meenemen-kaart staat op Home en nergens anders. Ze verdwijnt zodra de Apple TV stopt.
- In de meekijkende iPhone-speler ontbreken Cast en de snelheidsknop: een snelheid zou in modus
  `anyone` ook de Apple TV versnellen. De fly-knop blijft, Vergrendelen, Audio en ondertitels en
  Slaaptimer ook.
- In de tvOS-kiezer blijft Verplaatsen de eerste rij, zodat de landingsfocus van A-23d niet verschuift.
  45-t3 toont de focus één stap omlaag.
- Er is geen beeld voor de staat zonder ondersteuning (lokale map, Pleya Share, live tv). Die staat
  hergebruikt de kaart uit 45-h zonder knop, met de reden als tweede regel, en op de Apple TV een
  gedimde Meenemen-rij met dezelfde reden. Michel beslist of dat zonder eigen beeld volstaat.

Bouwen: de iPhone-pagina's `src-ios/45-h-*.html` en `src-ios/45-i-*.html` gebruiken alleen
icoontokens die in `build.mjs` van de iOS-northstarbron staan; het Pleya Fly-icoon en de
luidspreker met kruis staan inline in de pagina. Die `build.mjs` schrijft naar
`~/Downloads/mockups`; voor deze set is een kopie gebruikt met `PLEYA_MOCKUP_DEST` als uitvoermap,
plus `pleya_wordmark.png` uit `assets/branding/` in de assets-map van de kopie. De Apple TV-pagina's:

    PLEYA_MOCKUP_ART=<art-map> PLEYA_MOCKUP_DEST=<uit> node docs/assets/tvos-unified/src/build.mjs 45-t3 45-t4 45-t5
