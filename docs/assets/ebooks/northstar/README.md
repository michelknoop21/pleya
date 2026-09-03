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
| `ebooks-northstar-comp.png` | Design North Star, twaalf panelen | bron, niet ter goedkeuring | comp, 1528×1029 | DEC-069 | 2026-09-03 | n.v.t. |
| `00-mobile-nav-books.png` | Mobiele vijfslots-navigatie met Boeken als vierde bestemming; links Home (Boeken inactief), rechts Boeken actief | approved | 2 × iPhone 15 Pro naast elkaar | DEC-069, DEC-090 | 2026-09-03 | zie onder |
| `00a-mobile-nav-home-books-inactive.png` | Home, Boeken in slot 4 inactief | approved | iPhone 15 Pro, 1179×2556 | DEC-069, DEC-090 | 2026-09-03 | zie onder |
| `00b-mobile-nav-books-active.png` | Boeken-tab actief | approved | iPhone 15 Pro, 1179×2556 | DEC-069, DEC-090 | 2026-09-03 | zie onder |
| `01-books-home.png` | Boeken-home: Verder lezen, Recent toegevoegd, Series | proposed | iPhone 15 Pro, 1179×2556 | DEC-069, DEC-090 | 2026-09-03 | zie onder |

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

## Golden 01, Boeken-home (proposed)

Inhoud komt van paneel 1 van de comp, uitvoering van de iOS Unified-set. De maatvoering is
nagemeten op `01-series-landing.png`: paginatitel 28 px, rijkop 19 px, covers 110×165 met 12 pt
tussenruimte en 16 pt paginamarge. Dezelfde schaal als golden 00, want die was al op dezelfde
referentie gekalibreerd.

Vier punten waarop deze golden een keuze maakt die de comp niet maakt, en die dus expliciet
goedgekeurd of afgewezen moeten worden:

- **`Alle boeken ›` naast de paginatitel.** De comp heeft die link niet, de Unified-set wel
  (`Alle series ›`, DEC-068). Zonder de link is er geen route naar de volledige bibliotheek, dus
  hij staat erin.
- **De Verder-lezen-kaart.** Een boek heeft geen liggende artwork, alleen een cover. De kaart
  gebruikt de cover twee keer: onscherp als vulling over de volle breedte, scherp als inzet
  rechts. De comp toont daar een liggende scène die voor een echt boek niet bestaat. Dit is de
  enige echte uitvinding in deze golden.
- **Hoofdstuknummer naast het percentage.** De comp toont op de home alleen `48% gelezen`; het
  hoofdstuk staat er in het boekdetailpaneel wel bij. Hier staat `48% · Hoofdstuk 12`, omdat dat
  is waar je verder leest.
- **De Series-rij loopt onder de tabbalk door.** Dat is zo in de comp en het is wat vertelt dat de
  pagina doorscrolt. De motieven op die covers zitten daarom in de bovenste helft.

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
Van de vijf permutaties uit DEC-069 punt 5 is nu alleen de Downloads-bodem te bewijzen; welke drie
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
