# E-books northstar en schermgoldens

Deze map bevat drie soorten beeld, en ze hebben elk een andere status.

1. **Design North Star**: `ebooks-northstar-comp.png`, de samengestelde e-books-mockup
   (twaalf iPhone-panelen, 1528×1029) die Michel op 3 september 2026 als bindende inhoudelijke bron
   heeft aangeleverd. Hij bepaalt de e-book-specifieke compositie: Boeken-home, alle boeken, filters,
   zoeken, boekdetail, inhoudsopgave, reader in drie thema's, readerinstellingen, zoeken in boek,
   downloads, aanbevelingen en boekeninstellingen.
2. **Schermgolden (mockup)**: één afzonderlijke high-fidelity mockup per venster, op de echte
   iPhone 15 Pro-viewport (393×852 pt, 1179×2556 px). Een schermgolden is het ontwerpcontract voor
   de implementatie van precies dat venster. Hij wordt pas `approved` na een expliciet akkoord van
   Michel in de chat; `proposed` betekent dat er nog niet gebouwd mag worden.
3. **Executable golden**: een screenshot uit de draaiende app onder een Pleya Verify-fixture. Die
   komt niet hier maar in de evidencebundel van het bijbehorende scenario, en bewaakt regressies
   nadat het venster tegen de schermgolden is gebouwd.

Hoe de schermgoldens als Pleya-product worden uitgevoerd (shell, tabbalk, header, kaarten, chips,
typografie, tokens) volgt de iOS Unified 2026-set op `feat/netflix-mobile`
(`docs/assets/ios-unified/northstar/`, DEC-090 op die branch, commit `011ffdb`). Waar de e-books-comp
en die set elkaar raken, wint de set voor de uitvoering en de comp voor de e-book-inhoud.

## Manifest

| Bestand | Scherm | Status | Viewport | DEC | Datum | Afwijking |
| --- | --- | --- | --- | --- | --- | --- |
| `ebooks-northstar-comp.png` | Design North Star, twaalf panelen | bron, niet ter goedkeuring | comp, 1528×1029 | DEC-094 | 2026-09-03 | n.v.t. |
| `00-mobile-nav-books.png` | Mobiele vijfslots-navigatie met Boeken als vierde bestemming; links Home (Boeken inactief), rechts Boeken actief | approved | 2 × iPhone 15 Pro naast elkaar | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `00a-mobile-nav-home-books-inactive.png` | Home, Boeken in slot 4 inactief | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `00b-mobile-nav-books-active.png` | Boeken-tab actief | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `01-books-home.png` | Boeken-home, eerste ronde | vervangen door 01b | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `01b-books-home.png` | Boeken-home, canonieke startstaat | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `01b-books-home-series.png` | Scrollbewijs bij `01b-books-home.png`, geen apart scherm | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `01b-books-home-comp.png` | Beide 01b-frames naast elkaar | approved | 2 × iPhone 15 Pro | DEC-094, DEC-090 | 2026-09-03 | n.v.t. |

Golden 00 is op 3 september 2026 door Michel in de chat goedgekeurd, na visuele beoordeling van
00a en 00b op volle resolutie. Een approved golden staat hier altijd samen met zijn bron onder
`src/<golden>/`; alleen een PNG is geen ontwerpcontract, omdat hij dan niet opnieuw op te bouwen is.

Wat golden 00 wel en niet vastlegt. Ter goedkeuring staan de tabbalk (vijf slots, volgorde, iconen,
labels, actieve en inactieve staat, geometrie) en de header (wordmark, zoekicoon, avatar). De
Home-inhoud in 00a volgt de goedgekeurde `home-comp` uit DEC-090 en is hier alleen context; de twee
open details uit dat besluit (secundaire hero-CTA en de vijf dots) worden door deze golden niet
beslist. De Boeken-inhoud in 00b volgt paneel 1 van de comp maar is evenmin ter goedkeuring: dat is
schermgolden 01 (Boeken-home), die apart volgt.

Bewuste afwijkingen in golden 00:

- Actieve tab is rood icoon plus rood label, zonder het rood-amberen puntje en zonder de rode
  indicatorstreep die `navigation_tabs.dart` en `main_screen.dart` op `main` tekenen. Dat is de
  keuze van de iOS Unified-set (`01-series-landing`, `10-live-tv`) en van de e-books-comp; beide
  bronnen zijn het hierover eens.
- Het Boeken-icoon is een gevuld open boek, zoals in alle panelen van de comp. De overige vier
  iconen volgen de iOS Unified-set (gevuld huis, tv met antenne, klapbord, profielavatar), niet de
  dunne iconen van de comp.
- 00b toont naast de paginatitel `Alle boeken ›`, zoals `01-series-landing` naast `Series` doet
  (DEC-068). Paneel 1 van de comp heeft die link niet. Dit valt onder schermgolden 01 en is hier
  alleen zichtbaar omdat de balk ergens onder moet staan.
- Artwork is eigen CSS-werk met de titels uit de vaste fixture (Dune 48 % en hoofdstuk 12, Project
  Hail Mary, Sapiens, 1984, De Alchemist, Atomic Habits; voor film en serie de Blender open movies
  die ook op de demoserver staan). Commerciële covers en posters horen niet als golden asset in de
  repository; verhouding, kleurdynamiek en informatiedichtheid zijn wel aangehouden.

## Golden 01b, Boeken-home (approved)

Inhoud komt van paneel 1 van de comp, uitvoering van de iOS Unified-set. De maatvoering is
nagemeten op `01-series-landing.png`: paginatitel 28 px, rijkop 19 px, covers 110×165 met 12 pt
tussenruimte en 16 pt paginamarge. Dezelfde schaal als golden 00, want die was al op dezelfde
referentie gekalibreerd.

Golden 01b is op 3 september 2026 goedgekeurd. De twee frames zijn samen één contract voor één
scherm: `01b-books-home.png` is de canonieke startstaat van Boeken-home, `01b-books-home-series.png`
is scrollbewijs bij diezelfde pagina. Ze zijn geen twee schermen en geen twee varianten, en een
implementatie die het tweede frame als eigen bestemming behandelt volgt deze golden niet.

Bij de goedkeuring hoort dat titels als `Project Hail M…` op deze breedte mogen afbreken.

Eerder, in dezelfde ronde, keurde Michel vier keuzes goed: de link `Alle boeken ›` naast de
paginatitel, de liggende Verder-lezen-kaart met de cover rechts, `48% · Hoofdstuk 12` in plaats
van alleen een percentage, en een vaste tabbalk over scrollende inhoud. Dichtheid, covermaat,
header en compositie liggen daarmee vast en veranderen niet meer.

Wat 01b anders doet dan de eerste ronde, op zijn verzoek:

- **De achtergrond van een Verder-lezen-kaart is cover-derived ambience, geen tweede afdruk van
  de cover.** Ronde 1 zette dezelfde cover onscherp over de volle breedte; je kon hem herkennen,
  en bij een lichte, drukke of puur typografische cover valt die truc uit elkaar. De kaart neemt
  nu alleen kleur en licht van de cover over, in een veld dat geen enkele vorm ervan draagt. De
  scherpe inzet rechts blijft de enige plek waar de cover zelf staat.
- **De rail heet `Boekenseries`, niet `Series`.** In dezelfde viewport staat `Series` onderin al
  voor televisieseries. Eén label met twee betekenissen op één scherm is een fout, geen nuance.
- **Er is een tweede frame, `01b-books-home-series.png`.** Onder een cover van 150 pt past de
  metadata in rust niet boven de tabbalk, dus `Dune · 6 boeken` was in het eerste frame niet te
  beoordelen. Dat frame is dezelfde pagina, gescrold. Het is geen apart scherm.

**Eis aan de implementatie, niet aan de golden.** De tabbalk mag inhoud tijdelijk overlappen,
nooit permanent onbereikbaar maken. De Boeken-home krijgt dus onderaan genoeg scrollruimte om de
laatste rij inclusief metadata volledig boven de balk te brengen. Het tweede frame laat zien hoe
dat eruitziet.

## Wat er tegen golden 01b gebouwd is

`lib/screens/books/books_home_screen.dart` met `lib/books/` eronder. De rijen komen uit
`BooksHomeProvider`, de covers worden getekend door `BookCover` omdat er nog geen coverafbeeldingen
zijn, en de Verder-lezen-kaart tekent cover-derived ambience zoals de golden voorschrijft.

Bewijs: `pleya_verify/scenarios/books.home.layout.yaml` draait op een echte iPhone 15 Pro-simulator,
dezelfde viewport als de golden, en is groen. Het vergelijken van dat screenshot met deze golden
haalde twee fouten boven die geen enkele test zag: de voortgangsbalk lag 113 × 0 op het scherm
(een `Row` centreert, een `ColoredBox` heeft geen eigen hoogte) en de hele pagina stond 13 tot 25
punt te laag. Beide zijn gecorrigeerd; de uitlijning zit nu binnen 1 tot 7 punt.

Bewuste afwijkingen die blijven staan:

- De covers zijn getekend, niet geladen. Zolang boeken geen coverafbeelding dragen wijkt het detail
  af van de golden: de series-orbs zijn groter en missen de sterren, en een titel breekt soms over
  een ander aantal regels. Vorm, kleur en positie kloppen.
- De avatar is de bestaande ronde `ProfileAvatar`, de golden tekent een afgerond vierkant.
- Het wordmark is in de app iets breder dan in de golden.

## Wat er tegen golden 00 gebouwd is

De navigatie-skeleton implementeert de balk uit deze golden: vijf vaste posities, actieve tab als
rood icoon plus rood label, geen indicatorstreep en geen punt. Die presentatie zit in
`TabBarPresentation.unified2026` en geldt alleen op de iPhone; de iPad houdt `classic`, zodat een
scherm waarvoor geen golden bestaat er niet stilzwijgend anders uit gaat zien.

De vierde slot komt uit `PrimaryMobileDestinationPolicy`. Boeken wint, daarna Live TV, Kijklijst en
Downloads. Zolang de boekenbron nog geen antwoord heeft, blijft de slot leeg in plaats van naar Live
TV te vallen en terug te springen. Boeken zelf is nog een placeholder: het scherm eronder is
schermgolden 01 en wordt pas gebouwd na goedkeuring daarvan.

`pleya_verify/scenarios/mobile.nav.primary.yaml` meet de balk op een echte iPhone-simulatorbuild.
Van de vijf permutaties uit DEC-094 punt 5 is nu alleen de Downloads-bodem te bewijzen; welke drie
niet, en waarom, staat in het scenario zelf.

## Opnieuw renderen

De bron van iedere approved golden staat in `src/<golden>/`. Dat wijkt af van DEC-065 en DEC-090,
waar de HTML-bronnen buiten de repository bleven; voor e-books is de bron onderdeel van het contract.
Voor golden 00 is dat `src/00-mobile-nav-books/` met `nav.html`, `render.js` en `compose.py`. De
pagina laadt Inter en het wordmark met relatieve paden uit `assets/` van de repository, dus de render
werkt vanuit elke clone.

```
cd docs/assets/ebooks/northstar/src/00-mobile-nav-books
export NODE_PATH=/opt/homebrew/lib/node_modules:/opt/homebrew/lib/node_modules/@playwright/test/node_modules
node render.js nav.html ../../00a-mobile-nav-home-books-inactive.png home
node render.js nav.html ../../00b-mobile-nav-books-active.png books
python3 compose.py ../../00a-mobile-nav-home-books-inactive.png ../../00b-mobile-nav-books-active.png ../../00-mobile-nav-books.png
```

`render.js` opent Chromium op 393×852 met `deviceScaleFactor: 3` en wacht op `document.fonts.ready`.
Op 3 september 2026 leverde deze route vanuit de repo-bron byte-identieke PNG's op (md5
`7a7211c4…` voor 00a, `f9c034d0…` voor 00b); een afwijking na een Chromium- of fontwissel is een
signaal om de golden opnieuw te laten beoordelen, niet om de PNG stil te overschrijven.
De maten van de tabbalk (baltop 768 pt, icoonmidden 788 pt, label 11 pt op 806 pt, home-indicator
op 839 pt) zijn gemeten op `01-series-landing.png` uit de iOS Unified-set.
