# S7 primitieven: screenshots

Opnamen van de dev-galerij `/dev/primitives` in `pleya_web`, gemaakt op 10 oktober 2026 met
`scripts/primitives-shots.ts` tegen `vite dev` (OLED-thema tenzij de naam iets anders zegt). De
route bestaat alleen in ontwikkeling; in de productiebundel gooit de load een 404.

Opnieuw maken:

```bash
cd pleya_web
bun run dev
PLEYA_DEV_URL=http://localhost:5173 bun run scripts/primitives-shots.ts
```

De galerij draait zonder app-schil (geen topnavigatie of tabbalk), dus vergelijk de componenten
met de mockup, niet de omlijsting.

## Waar je elke opname naast legt

| Opname | Northstar | Wat je vergelijkt |
| --- | --- | --- |
| `galerij@{393,1024,1600}` | geen één-op-één | het geheel, voor regressie tussen rondes |
| `velden@{393,1024,1600}` | 22, 40, 41, 42 | veld met hint en focusring, fout, uitgeschakeld; select; toggle; keuzelijst en tegels |
| `panelen@{393,1024,1600}` | 20, 21, 24, 35 | paneel met titel en actie, flush, gevarenrand; stattegels uit 20 |
| `pillen@{393,1024,1600}` | 21, 25, 26, 34 | vijf tonen, met en zonder stip, klein |
| `meldingen@{393,1024,1600}` | 21, 24, 31, 35 | waarschuwing, fout met actie, info zonder titel, info met twee acties |
| `chips@*`, `chips-focus@*` | 02, 05, 16 | outline enkel en meervoudig, quiet; focusring op de eerste chip |
| `tabel@{393,1024,1600}` | 21, 25, 26 | scrollende tabel, gestapelde tabel, lege tabel |
| `stappen@{393,1024,1600}` | 40 t/m 44 | stap 1, stap 3, laatste stap, alles af |
| `dialoog-plain@{393,1600}` | 23 | dialoog zonder overtypzin; op 393 als sheet onderaan |
| `dialoog-phrase@{393,1600}` | 23 | dialoog met overtypzin, opsomming en prullenbakicoon |
| `dialoog-phrase-gescrold@393` | 23 | dezelfde sheet na 600 px wielscroll erachter |
| `skelet@{393,1024,1600}` | 15, 16 | losse vormen, artworkvlak zonder beeld, de vier SkeletonPage-varianten |
| `skelet-oled@1024`, `skelet-light@1024` | 15, 16 | skeletvulling naast artworkplaatshouder in twee thema's |
| `skeleton-home@{393,768,1024,1280,1600}` | 15 | hero plus twee rails |
| `skeleton-grid@{393,768,1024,1280,1600}` | 15, 05 | raster zoals op een bibliotheekpagina |
| `skeleton-detail@{393,768,1024,1280,1600}` | 15, 08 | poster plus regels zoals de itempagina |

## Bekende afwijkingen

- Gestapelde tabel op 393 (`tabel@393`): elke cel na de eerste toont zijn kolomnaam ("Soort",
  "Pad"). Mockup 21@393 heeft geen gestapelde variant; daar scrolt de tabel horizontaal zonder
  labels in de rijen. De labels zijn een keuze uit taak 4 voor schermlezers, niet hersteld.
- Pagina achter de dialoog scrolt mee. Gemeten: een wielscroll van 600 px buiten de kaart zet
  `scrollY` van 4922 naar 5522 op 393 en van 3049 naar 3649 op 1600, voor beide dialogen.
  `dialoog-phrase-gescrold@393` laat zien dat de sheet op zijn plek blijft en de inhoud erachter
  doorschuift. ConfirmDialog zet geen scrollvergrendeling op `body`.
- Kop van een flush paneel op 393 (`tabel@393`, eerste tabel): titel en actieknop staan onder
  elkaar in plaats van naast elkaar. In `panelen@1600` houdt de flush kop 20 px inzet terwijl de
  inhoud op 8 px begint; dat is zo bedoeld voor tabellen, maar oogt bij lopende tekst scheef.
- Chips: de eerste chip begint 4 px rechts van de sectierand, de ruimte die de knop houdt zodat
  de focusring niet wordt afgeknipt. De focusring zelf is volledig zichtbaar (`chips-focus@393`).
  Op 393 loopt de rij rechts buiten beeld en scrolt hij horizontaal.
- Skeletvulling tegen artworkplaatshouder: het skelet gebruikt `--fill` (inkt op 8 procent), het
  artworkvlak `--skeleton` (7 procent). Berekend in OLED `rgb(255 255 255 / .08)` tegen
  `rgba(255,255,255,.07)`, in light `rgb(17 17 17 / .08)` tegen `rgba(17,17,17,.07)`. Met het oog
  niet te onderscheiden (`skelet-oled@1024`, `skelet-light@1024`), wel twee tokens voor hetzelfde.
- Skelet-hero (`skeleton-home@*`): loopt van rand tot rand zonder ronde hoeken. Mockup 15 tekent de
  hero binnen de pagina-inzet met afgeronde hoeken en een iets lichtere vulling.
- Opsomming in de dialoog toont geen opsommingstekens; de reset in `base.css` haalt ze weg.
