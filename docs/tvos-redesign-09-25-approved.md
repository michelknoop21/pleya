# Approval-manifest: tvOS-mockups 09 tot en met 25

Michel heeft de gecorrigeerde candidate-set op 3 september 2026 expliciet goedgekeurd. Dit
bestand is vanaf dat moment de statusautoriteit voor die zeventien beelden, niet de tekst in de
PNG's zelf en niet `00-overzicht.md`, die beide nog "candidate" zeggen. De beelden zijn niet
opnieuw gerenderd om dat woord weg te halen: opnieuw renderen zou de pixels wijzigen die hier
gehasht staan.

## Status

| Veld | Waarde |
|------|--------|
| Status | APPROVED DESIGN TARGET |
| Goedgekeurd door | Michel Knoop |
| Datum | 3 september 2026 |
| Set | 09 tot en met 25, zeventien beelden op 1920x1080 |
| Herkomst | `~/Downloads/mockups-tvos/`, gebouwd met `_src/build.mjs` |
| In de repo | `docs/assets/tvos-unified/approved-2026-09-03/` |
| Audit | `docs/assets/tvos-unified/approved-2026-09-03/01-code-parity-audit.md` |
| Sluit aan op | northstar 01 tot en met 08, `docs/assets/tvos-unified/northstar/` (DEC-065) |

De code-parity-audit blijft inhoudelijk volledig geldig. Wat er verandert is de poort: de
approval-gate is dicht, de bevindingen zijn werk geworden. De audit staat mee in de repo omdat
hij per mockup de bestaande productiecode, route, primitives, acties en staten benoemt met
regelnummers, en dat is de invoer voor het implementatieregister.

## Wat is goedgekeurd

De goedgekeurde mockup bepaalt compositie, visuele hiërarchie, TV-dichtheid, page framing,
positionering, componentfamilie, kaarttaal, focustaal, typografische richting en de ruimtelijke
verhouding tussen bedieningselementen.

Een screenshot is geen functionele specificatie. Bestaande productfunctionaliteit die niet op
een beeld staat verdwijnt niet: foutstaten, laden, opnieuw proberen, paginering, contextacties,
offline, beheeracties, toegankelijkheid, platformcondities, Back en Menu, bronkeuze, kijkstatus
en de bestaande spelerfuncties horen in een passende secundaire staat binnen dezelfde
goedgekeurde taal. Voorbeeldwaarden in een beeld zijn geen toestemming om data te verzinnen die
de app niet kent. Waar het productcontract vraagt dat de app die data voortaan wel kent, komt
eerst de state, het model en de service, en pas daarna de UI.

De vijftien productbesluiten die onder deze approval horen staan in
`docs/tvos-redesign-implementatiecontract.md`. Bij een conflict wint dat contract van de
compositie, en de compositie wint van een oudere codebeperking.

## Gehashte set

SHA256 over de goedgekeurde pixels. Wie later wil vaststellen welk beeld is goedgekeurd,
vergelijkt tegen deze regels.

| Nr | Bestand | SHA256 |
|----|---------|--------|
| 09 | 09-film-detail.png | `a86d4dd3c1085174644a9c86afc49c04b8dbbeae915b4b48a84dce273884a974` |
| 10 | 10-serie-detail.png | `be39609252e77e652c2bbe1fcb5f00548dba4b49845a66d5131fa920c3a2e0da` |
| 11 | 11-bronkeuze.png | `8ab374f1dae52378e973ff20f3899e69c9052da35a134179ef497f3b665c4c63` |
| 12 | 12-contextmenu.png | `dce0d9ec7bb97f7985c62102b7a0f22fbb73c65ebf661da9f1925f7d45fe776f` |
| 13 | 13-zoeken.png | `f7989e9b63a1f66e2f1cae66b553478033ef033f4f5d4ddb0e11afde369ecd57` |
| 14 | 14-kijklijst.png | `f59966a64919d1b3f94dbe355bdfc916cdcdcab449e0ad5d2aebbd9ce0cbeb8e` |
| 15 | 15-aanvragen.png | `2e29c4909d8d939dcfd24e5723f003580f27acff1fb2cc70a5025c211b1ad55c` |
| 16 | 16-activiteit.png | `2519cd2e5c3c22ae39ad930b5af1db3920c1b1c99cfe3944eac3f9aa8c361c3b` |
| 17 | 17-live-tv.png | `1613ae54d7a4793f176920a6db02c5de7235fd8f2944536eb947e25ceed522f3` |
| 18 | 18-speler.png | `e2c93b7e92d4b33257481e4ec52d7309a0856ec6307d3d1a75a1d6106c1ac485` |
| 19 | 19-speler-infopanel.png | `f1cfd54beaca77af4922651f1827d6876462f381d4bfbff36bee817f4768a52a` |
| 20 | 20-instellingen-uiterlijk.png | `8dc387fd7401b14bd36450f472bdcd0161d1492e58b6d1fb88b5215cd63b59dd` |
| 21 | 21-profiel-kiezen.png | `f63f9c2e7b8b69bf4147045693ad4bed311735da2244557500c7696e9c46ffcb` |
| 22 | 22-inloggen.png | `2216a6c69feaf6ff9732187bd6a4f84245f545320c240f86cfde8c2c0f7346cd` |
| 23 | 23-offline.png | `44b00d8757b0a31e0c771b7ed4dc3ee76cccf52ed382f45a8ee68df0db0443f4` |
| 24 | 24-collectie.png | `6511b925b6cd3ed13fff8f47a842a4889e0e0cac5f3a13b1a7fd20edb2a93b07` |
| 25 | 25-persoon.png | `e9f1c7072fb47f9b357b83ce7d829eea9346be8e3b743b032624de77a40bcd0c` |

Bijbehorende documenten, dezelfde datum:

| Bestand | SHA256 |
|---------|--------|
| 00-overzicht.md | `9a29af90725ac165b5bf106d477f6885d126499097bf5f177f87be458281ba38` |
| 01-code-parity-audit.md | `3908f3204465348273d74d31fa018adb1b1896863a1e6b0af0246736928e32a7` |

De HTML-bron waaruit de beelden geschoten zijn staat buiten de repo in
`~/Downloads/mockups-tvos/_src/`. De gesorteerde inhoud van de `.html`-, `.css`- en
`.mjs`-bestanden daarin hasht op
`198b91a178e4a42db9b2e0ed881cd37568a721ea9657739728925c0501a80156`. Die bron loopt op twee
punten aantoonbaar achter op de code, zie de tokenaudit: `_src/tv.css` presenteert 267x400 en
400x225 nog als bindend terwijl DEC-087 de railband 346, de 16:9-kaart 615 en de buren 231
autoriseert. Bij zo'n conflict wint de code.

## Wanneer nog een keer approval nodig is

Alleen wanneer de goedgekeurde primaire compositie technisch onhaalbaar blijkt, wanneer een
schermtype nodig is dat niet uit deze set af te leiden valt, wanneer een fundamenteel nieuw
productconcept nodig blijkt, of wanneer de enige juiste fix de zichtbare hoofdcompositie
wezenlijk verandert.

Niet voor implementatiedetails, en niet voor secundaire functionele staten die de bestaande
functionaliteit behouden, de goedgekeurde componenttaal gebruiken en de primaire compositie
ongemoeid laten. Laden, fouten, leeg, opnieuw proberen, beheeracties, paginering, de
offline-variant en sheet-staten vallen daar allemaal onder.
