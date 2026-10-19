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

Bronnen: de iPhone-pagina's staan in `src-ios/` en bouwen met `build.mjs` van de iOS-northstarbron
(die staat buiten de repo, net als de art), aangevuld met drie iconen (`handoff`, `tv`, `phone`) die in
de pagina's als `{{icon:...}}` staan. De Apple TV-pagina's staan in
`docs/assets/tvos-unified/src/pages/45-t*.html`:

    PLEYA_MOCKUP_ART=<art-map> PLEYA_MOCKUP_DEST=<uit> node docs/assets/tvos-unified/src/build.mjs 45-t

De art (filmbeelden) staat niet in git; de PNG's hier zijn de bron van waarheid.
