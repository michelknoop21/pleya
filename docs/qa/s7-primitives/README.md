# S7 primitieven: screenshots

Opnamen van de dev-galerij `/dev/primitives` in `pleya_web`, gemaakt op 10 oktober 2026 met
`scripts/primitives-shots.ts` tegen `vite dev` (dark-thema, de standaard van de web-app sinds
taak 9a, tenzij de naam iets anders zegt). Sinds taak 9a tonen ze designsysteem v2; leg ze naast
`v2-specimen/v2@1600.png` en `v2@393.png` voor de uitvoering en naast de northstar voor de structuur. De
route bestaat alleen in ontwikkeling; in de productiebundel gooit de load een 404.

Opnieuw maken:

```bash
cd pleya_web
bun run dev
PLEYA_DEV_URL=http://localhost:5173 bun run scripts/primitives-shots.ts
```

De galerij draait zonder app-schil (geen topnavigatie of tabbalk), dus vergelijk de componenten
met de mockup, niet de omlijsting. Sinds taak 9b heeft hij een eigen index: links vanaf 900, als
strook chips bovenaan daaronder. Elke sectie heeft een kop van 11 px in kapitalen met een
haarlijn, en bovenaan staat het Overzicht: specimen v2 nagebouwd met de echte componenten. De
sectie-ids staan in `pleya_web/src/routes/dev/primitives/sections.ts`; het script leest ze daar.

## Waar je elke opname naast legt

| Opname | Northstar | Wat je vergelijkt |
| --- | --- | --- |
| `galerij@{393,1024,1600}` | geen één-op-één | de hele pagina met index (links, of als chipstrook op 393), voor regressie tussen rondes |
| `overzicht@{393,1024,1600}` | specimen `v2@1600`, `v2@393`; 20, 21, 24 | het specimen met echte componenten: kop met statusstip, melding, vier even hoge tegels (sparkline op Titels), opslagmeter, bibliotheektabel met tags, statuscel en voortgang (gestapeld op 393), formulierpaneel, gevarenzone en een laadkaart. De zijbalk van het specimen hoort bij de app-schil en ontbreekt |
| `overzicht-{oled,light}@{393,1600}` | als hierboven | hetzelfde in OLED en light: segmentkleuren, tags en statusstippen op het witte paneel |
| `opslagmeter@{393,1024,1600}` | specimen "Opslag per bibliotheek"; 20, 24 | StorageMeter normaal (vijf segmenten, vrij gedempt), bijna vol (Kids rood, 0,3 TB vrij) en leeg of onbekend (gedempt spoor met uitleg in plaats van legenda) |
| `opslagmeter-{oled,light}@{393,1600}` | als hierboven | dezelfde drie staten in OLED en light |
| `velden@{393,1024,1600}` | 22, 40, 41, 42 | velden in een paneel: invoer dieper dan het paneel (`--inset-bg`), pad in mono met focus (1 px inktrand, geen ring), fout, uitgeschakeld; select; toggle (uit met gedimde knop); keuzelijst en tegels |
| `panelen@{393,1024,1600}` | 20, 21, 22, 24, 35 | paneel met titel en actie, flush met een lijst tot de rand, `tone="warn"` (35), `tone="danger"` (22); stattegels uit 20 met sparkline en eenheid in grijs, per rij even hoog |
| `velden-foutfocus@{393,1024,1600}` | 22, 40 | foutveld met focus: rode rand van 2 px (rand plus schaduw van 1 px); de northstar tekent deze staat niet |
| `pillen@{393,1024,1600}` | 21, 25, 26, 34 | vijf tonen, met en zonder stip, statusvorm (`variant="dot"`), klein als tag |
| `meldingen@{393,1024,1600}` | 21, 24, 31, 35 | waarschuwing, fout met actie, info zonder titel, info met twee acties |
| `chips@*`, `chips-focus@*` | 02, 05, 16 | outline enkel en meervoudig, quiet; focusring op de eerste chip |
| `focus-knop@{393,1024,1600}`, `focus-knop-light@{393,1600}` | DESIGN.md `--ring` | de globale focusring op een gewone knop in een paneel: 3 px in `--ink` op een gap van 3 px. Gemeten met `getComputedStyle`: `3px solid rgb(255, 255, 255)` in dark, `3px solid rgb(17, 17, 17)` in light, offset `3px` |
| `tabel@{393,1024,1600}` | 21, 25, 26, 35 | scrollende tabel met mono-padkolom en statuscel als stip plus tekst, gestapelde tabel (kale regels, alleen "Titels" met `showLabel`), lege tabel |
| `stappen@{393,1024,1600}` | 40 t/m 44 | stap 1, stap 3, laatste stap, alles af |
| `dialoog-plain@{393,1600}` | 23 | dialoog zonder overtypzin; op 393 als sheet onderaan |
| `dialoog-phrase@{393,1600}` | 23 | dialoog met overtypzin, opsomming en prullenbakicoon |
| `dialoog-phrase-gescrold@393` | 23 | dezelfde sheet na 600 px wielscroll erachter; de pagina staat stil |
| `{velden,velden-foutfocus,panelen,meldingen,pillen,chips,tabel}-{oled,light}@{393,1600}`, `stappen-light@{393,1600}` | als de dark-opname | dezelfde sectie in OLED en light: scheiding van paneel en pagina, haarlijn, inset, en leesbaarheid van fout-, waarschuwings- en oktekst |
| `dialoog-phrase-{oled,light}@{393,1600}` | 23 | dialoog met overtypzin in OLED en light |
| `skelet@{393,1024,1600}` | 15, 16 | losse vormen, artworkvlak zonder beeld, de vier SkeletonPage-varianten |
| `kaarten@{393,1024,1600}` | 16; `v3-specimen/kaarten@*` | MediaCard in elf staten, volgorde van specimen v3. Hover en toetsenbordfocus zijn echt: het script zet de muis op de tweede kaart en de focus op de derde. De onderregel toont alleen het jaar, want `Item` draagt nog geen genre (PS-7N); de galerij heeft links een index, dus op 1600 passen er zes kaarten per rij en geen zeven |
| `rail@{393,1024,1600}` | 01; `v3-specimen/rail@*` | HubRail in drie rijen zoals het specimen: Continue watching met voortgang, Next up met vijf afleveringen in de brede vorm en zonder "View all", en Recently added met twaalf titels. Het script zet de muis op de kop van de derde rij, dus daar staan de pijlen (vanaf 900). De uitsnede is aan beide kanten `--inset` breder dan de sectie, want de rail loopt tot de rand van de galerijkolom; op 1600 is dat niet de rand van het venster |
| `skelet-oled@1024`, `skelet-light@1024` | 15, 16 | skeletvulling naast artworkplaatshouder, en een skelet in een paneel, in OLED en light |
| `skeleton-home@{393,768,1024,1280,1600}` | 15 | hero plus twee rails |
| `skeleton-grid@{393,768,1024,1280,1600}` | 15, 05 | raster zoals op een bibliotheekpagina |
| `skeleton-detail@{393,768,1024,1280,1600}` | 15, 08 | poster plus regels zoals de itempagina |

## Opgelost in ronde 1 van de visuele poort

- Focus op Field en Select is een rand van 1 px in `--ink`, zonder ring, ook na een muisklik
  (23, 40, 42). Knoppen, chips, keuzes en schakelaars houden de ring. Daarbij bleek de foutrand
  op een tekstveld nooit zichtbaar: de vakstijl won op specificiteit. Beide hersteld. Een foutveld
  met focus wordt 2 px rood (ronde 2), zodat ook dat veld een zichtbaar focusverschil heeft.
- Panel kreeg `tone="danger" | "warn"`: rode titel in `--danger-ink` (#FF6A63, 22) en de
  amberkleurige tweeling met rand en titel in `--amber` (35). `danger` werkt nog.
- Gestapelde DataTable toont de kolomnamen alleen voor een schermlezer; zichtbaar per kolom met
  `showLabel`.
- ConfirmDialog zet het scrollen van de pagina stil zolang hij open is. Gemeten: een wielscroll van
  600 px laat `scrollY` op 5153 (393) en 3049 (1600) staan. Na sluiten scrolt de pagina weer.

## Bekende afwijkingen

- Chips: op 393 loopt de rij rechts buiten beeld en scrolt hij horizontaal. Sinds 9a begint de
  eerste chip op de sectierand; de 4 px voor de focusring vangt een negatieve marge op.

- Skelet-hero (`skeleton-home@*`): loopt van rand tot rand zonder ronde hoeken. Mockup 15 tekent de
  hero binnen de pagina-inzet met afgeronde hoeken en een iets lichtere vulling.
- Opsomming in de dialoog toont geen opsommingstekens; de reset in `base.css` haalt ze weg.
- Scrollvergrendeling is alleen met het muiswiel gemeten. Vegen op een touchscherm en het
  vasthouden van de scrollbalkgoot op desktop zijn niet bewezen: headless Chromium tekent
  overlay-scrollbalken, dus de breedte van de pagina verandert daar hoe dan ook niet.
- Inter heeft in de bundel alleen 400, 500 en 700. De gewichten 600, 750 en 800 uit het specimen
  vallen terug op 700, dus titels en tegelwaarden zijn iets lichter dan in `v2@1600.png`.

## Opgelost in taak 9a (designsysteem v2)

- Flush paneel: kop en inhoud staan allebei op 20 px inzet, en titel en actie blijven ook op 393
  naast elkaar (`tabel@393`).
- Skelet en artworkvlak delen `--skeleton`; gemeten in OLED en light identiek
  (`rgba(255,255,255,.07)` en `rgba(17,17,17,.07)`).
- Statuscel (`variant="dot"`): `run` is een amber stip die pulseert, zoals "bezig" in 21 en het
  specimen; de capsule `run` blijft inkt (25).
- Light kreeg eigen tekstkleuren voor de tonen (`--danger-ink` #a81d18, `--warn-ink` #7a4f00,
  `--ok-ink` #0c6b3c): de merkkleuren haalden op wit 1,8 tot 2,8:1. Berekend (WCAG 2.x) op wit,
  pagina #f7f7f8 en inset #f1f1f3, de laagste waarde per geval: err-pill 5,15, warn-pill 5,87,
  ok-pill 5,40, gekozen outline-chip 4,87, ok-tekst op een tint van zichzelf 4,77. Het aan-spoor
  van Toggle en de sparkline gebruiken in light ook het donkere groen (witte knop 6,6:1). De
  statusstip `run` pulseert tot 0,6 in plaats van 0,35, anders verdween hij op wit. Dark en OLED
  zijn ongewijzigd. Hertest in light met `PLEYA_SHOTS_THEME=light`.

## Taak 9b: opslagmeter en galerij als pagina

- `StorageMeter` (`pleya_web/src/lib/components/StorageMeter.svelte`): breedtes via
  `style:flex-grow` in procenten van het totaal, een segment van 0 alleen in de legenda, een
  piepklein segment minstens 1 procent (plus 4 px als vangnet in CSS), en een `total` groter dan
  de som tekent de rest als gedempt vrij vlak. De legenda is een lijst met `aria-label`; de balk
  staat `aria-hidden`, want hij herhaalt alleen wat de legenda zegt.
- Twee grafiektokens in `tokens.css`: `--blue` (#7aa7ff in dark en OLED, #3d72e0 in light, 4,49:1
  op wit) en `--amber-graphic` (amber in dark en OLED, #c27c00 in light, 3,40:1 op wit). Amber
  haalde als balksegment op het witte paneel maar 1,8:1; `--warn-ink` is als vlak bruin en leest
  niet meer als amber. De legendatekst gebruikt `--ink-2` en `--ink-3`.
- Stattegels in één rij strekken nu tot dezelfde hoogte (`gs__grid--stretch` in de galerij,
  `align-items: stretch` in het Overzicht).
- De index markeert de huidige sectie met een scrollmeting (kop boven een kwart van het venster).
  Een IntersectionObserver gaf na een ankersprong de vorige sectie aan.
- Opnamen van secties zijn elementopnamen: de buitenste ring en schaduw van een paneel vallen op
  de rand van het beeld deels weg. Dat is de uitsnede, niet het paneel.

## Eindreview van de branch (2026-10-10)

- `--ink-3` staat in light op `#6b6b70`. Gemeten met WCAG 2.x: 5,30 op wit, 4,95 op de pagina
  `#f7f7f8`, 5,08 op paneel-2 `#fafafa` en 4,70 op de inset `#f1f1f3`. Daarvoor was het `#111`
  op 50 procent, 3,54 / 3,49 / 3,45. In dark en OLED blijft het wit op 50 procent, 5,05 tot 5,34
  op paneel, paneel-2 en inset. Het stapellabel van de tabel (`showLabel`) stond op `--ink-4`
  (2,5 tot 2,7:1) en staat nu op `--ink-3`.
- De globale focusring volgt DESIGN.md: 3 px in `--ink` op een gap van 3 px (`focus-knop@*`).
  Tekstvakken houden alleen de rand van 1 px (`velden@*`, het padveld met focus).
- Opnieuw gemaakt, met `PLEYA_SHOTS_SECTIONS=velden,tabel,stappen,panelen,chips` en
  `PLEYA_SHOTS_THEME=dark` en daarna `light`: `{velden,velden-foutfocus,panelen,chips,chips-focus,tabel,stappen,focus-knop}@{393,1024,1600}`
  en `{velden,panelen,chips,tabel,stappen,focus-knop}-light@{393,1600}`. In dark kwamen velden,
  panelen, chips, chips-focus, stappen en velden-foutfocus byte-gelijk terug; alleen `tabel@*`
  veranderde (het stapellabel). De overige opnamen, ook `velden-foutfocus-light` en alles in OLED,
  zijn van de vorige ronde.
