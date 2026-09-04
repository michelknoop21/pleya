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
| `02a-all-books.png` | Alle boeken, canonieke startstaat | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `02b-all-books-scrolled.png` | Scrollbewijs bij `02a`, laatste rij vrij van de tabbalk | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `02c-all-books-controls.png` | Detail: de pill-rij in rust en actief | approved | detailuitsnede, 1179×850 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `03a-filters-status.png` | Filtersheet, canonieke openstaat op Status | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `03b-filters-genre.png` | Filtersheet, Genre open met twee klaargezette keuzes | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `03c-filters-controls.png` | Detail: kop, groepsrij en actiebalk in beide staten | approved | detailuitsnede, 1179×1860 | DEC-094, DEC-090 | 2026-09-03 | zie onder |
| `04a-books-search.png` | Boeken zoeken, canonieke staat op `dune` met Alles actief | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `04b-books-search-books.png` | Dezelfde zoekopdracht met alleen Boeken actief | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `04c-books-search-rowtypes.png` | Detail: de drie resultaatsoorten onder elkaar | approved | detailuitsnede, 1179×1590 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `05a-book-detail.png` | Boekdetail, canonieke staat op Dune met leesvoortgang | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `05b-book-detail-unread.png` | Hetzelfde scherm voor een boek zonder voortgang en zonder reeks | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `05c-book-detail-actions.png` | Detail: het actieblok in beide staten | approved | detailuitsnede, 1179×1680 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `06a-books-toc.png` | Inhoudsopgave, canonieke staat op Atomic Habits met de boom open op de locator | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `06b-books-toc-collapsed.png` | Dezelfde boom met alle delen dichtgeklapt | approved | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `06c-books-toc-rowtypes.png` | Detail: de rijsoorten van de boom in hun drie posities | approved | detailuitsnede, 1179×1935 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `07a-books-reader.png` | Reader, canonieke staat op Dune hoofdstuk 12 met de chrome zichtbaar | approved (revisie B) | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `07b-books-reader-immersive.png` | Dezelfde pagina met de chrome verborgen | approved (revisie B) | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `07c-books-reader-themes.png` | Detail: dezelfde pagina in licht, sepia en donker | approved (revisie B) | detailuitsnede, 1179×2478 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `08a-reader-settings.png` | Leesinstellingen, canonieke staat over de leespagina | **proposed** | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `08b-reader-large-type.png` | Dezelfde pagina op de grootste lettergrootte, blad dicht | **proposed** | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `08c-reader-settings-controls.png` | Detail: de vijf bedieningen met hun staten | **proposed** | detailuitsnede, 1179×1851 | DEC-094, DEC-090 | 2026-09-04 | zie onder |

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

## Golden 02, Alle boeken (approved)

De grid-bestemming achter `Alle boeken ›` op Boeken-home. Inhoud van paneel 2 van de comp,
uitvoering van de iOS Unified-set, aansluitend op goedgekeurde golden 01b. Drie frames, samen één
scherm: `02a` de startstaat, `02b` dezelfde pagina gescrold, `02c` een detailuitsnede van alleen de
bedieningsrij zodat de actieve en niet-actieve staat naast elkaar te beoordelen zijn.

Golden 02 is op 3 september 2026 goedgekeurd, inclusief de negen keuzes hieronder.

De filtersheet zit hier bewust niet in. Dat is schermgolden 03 met zijn eigen goedkeuring; de
Filters-pill in dit beeld opent hem, maar wat er dan opengaat wordt hier niet beslist. Tot die
goedkeuring er is tekent de implementatie de pills wel en opent ze niets: golden 02 keurt goed hoe
ze eruitzien, niet wat erachter zit.

**De keuzes die de comp niet maakt, en die dus goedgekeurd of afgewezen moeten worden.**

- **Drie kolommen, en dat is gemeten, niet aangenomen.** `03-alle-films.png` uit de Unified-set zet
  op dezelfde iPhone 15 Pro drie kolommen van 114 pt met 10 pt ertussen en 16 pt paginamarge. Boeken
  krijgen exact dezelfde maten, zodat een plank boeken en een plank films uitlijnen. Vier kolommen
  zou 83 pt per cover geven, en op die breedte breekt een titel na ongeveer elf tekens af; twee
  kolommen maakt van een bibliotheek een fotoalbum. Bij 114 pt past `Children of Dune` precies op
  één regel en breekt `Project Hail Mary` netjes over twee.
- **Coververhouding 2:3**, dus 114 × 171, gelijk aan de rails in 01b en aan de filmposters. Echte
  boekcovers variëren tussen 1:1,5 en 1:1,6; één vaste verhouding houdt het raster recht en is een
  keuze, geen meting.
- **Filter en sorteren zijn pills, geen icon-buttons.** Dat is de taal van de Unified-set. De
  sorteerpill draagt zijn huidige waarde (`Titel A–Z`) in plaats van het woord `Sorteren`: een
  bediening die zijn stand toont scheelt een tik om hem te lezen. De comp schrijft `Sorteren`, dit
  wijkt daar bewust van af.
- **De actieve staat is de pill in accentkleur met een telling erin**, en de filtersamenvatting
  rechts op de resultaatregel. Zie `02c`.
- **`128 boeken` staat links op een resultaatregel onder de pills**, waar de Unified-set
  `126 titels geladen` zet. Bij een actief filter komt de samenvatting daar rechts naast. In rust
  blijft die rechterkant leeg.
- **Reeksinformatie staat niet in het raster.** Titel en auteur zijn de twee regels; een derde regel
  voor de reeks maakt de cel hoger en het raster losser, en de reeks is al bereikbaar via de
  Boekenseries-rail en het boekdetail.
- **Geen filmmetadata.** Geen jaar, speelduur, resolutie of waardering. Dat is bewust: dit is een
  boekenplank, geen filmcatalogus.
- **Het bijschriftblok heeft een vaste hoogte** van twee titelregels plus één auteursregel, zodat
  elke rij op dezelfde lijn begint, wat een lange titel ook doet. De speling valt onderaan de cel,
  niet tussen titel en auteur.
- **De header draagt rechts alleen zoeken.** Paneel 2 van de comp zet daar nog een tweede glyph
  waarvan de bestemming nergens is vastgelegd; die is hier weggelaten in plaats van er een betekenis
  bij te verzinnen.

Net als bij 01b geldt: de tabbalk mag de laatste rij tijdelijk overlappen, nooit permanent.
`02b` laat zien hoe ver er onderaan doorgescrold moet kunnen worden.

## Golden 03, Filtersheet (approved)

Wat er opengaat achter de Filters-pill uit golden 02. Inhoud van paneel 3 van de comp, uitvoering van
`04-filters-sheet.png` uit de iOS Unified-set. Drie frames, samen één scherm: `03a` de openstaat met
Status geselecteerd, `03b` dezelfde sheet met Genre open en twee keuzes klaargezet, `03c` een
detailuitsnede van de kop, de groepsrij en de actiebalk, zodat rust en actief naast elkaar te
beoordelen zijn.

Golden 03 is op 3 september 2026 goedgekeurd, inclusief de zes keuzes hieronder.

De maatvoering is nagemeten op `04-filters-sheet.png` en overgenomen, niet opnieuw bedacht: sheet
vanaf 252 pt met 13 pt hoekradius, greep 36 × 5 op 260, linkerkolom 131 breed met een scheidingslijn
van 1 pt, groepsrijen op een steek van 43,5, optierijen op 47,5 met een opgetilde pil van 37 hoog,
actiebalk 97 hoog met de scheidingslijn op 755. De scrim is één zwarte laag van 60 % over het hele
frame, de statusbalk inbegrepen; dat is af te lezen aan de referentie, waar de `9:41` op 102 van 255
uitkomt en de paginaachtergrond op 8 van 20.

**De keuzes die goedgekeurd of afgewezen moeten worden.**

- **Twee panelen, geen lijst met doorklikrijen.** De comp zet `Genre  Alles ›` als rij die ergens
  naartoe duwt, dus een genre kiezen kost een push en een terug per groep. De Unified-set zet de
  groepen links en hun keuzes rechts, en daar kost het nul paginawissels. De set wint hier voor de
  uitvoering, zoals bovenaan afgesproken.
- **Sorteren zit er niet in.** De comp heeft `Sorteren op · Datum toegevoegd` als laatste rij van de
  sheet. Golden 02 heeft sorteren al een eigen pill gegeven die zijn waarde draagt, en die is
  goedgekeurd. Eén instelling op twee plekken is geen keuzevrijheid maar een bron van tegenstrijdige
  staat, dus de sorteerrij vervalt.
- **De sheet is een klad, `Toepassen` is het enige moment waarop er iets gebeurt.** Daarom staat de
  Filters-pill achter de sheet in `03b` nog in rust terwijl er binnen al twee keuzes staan, en daarom
  staat er rechtsboven `2 gekozen` waar de Unified-set `2 actief` schrijft. Het alternatief, meteen
  filteren bij elke tik, maakt `Toepassen` een knop zonder werk en laat de gebruiker door een
  telkens verspringende plank kijken.
- **`Wissen` staat linksonder naast `Toepassen`, niet rechtsboven.** De comp zet hem in de kop. De
  set zet de twee handelingen bij elkaar onderin en gebruikt de rechterbovenhoek voor de telling.
  Onderin winnen ze allebei: wissen en toepassen zijn hetzelfde soort handeling en horen op dezelfde
  regel. Met niets gekozen staat `Wissen` er wel maar inert, op 50 % inkt.
- **Vijf groepen: Status, Genre, Series, Auteur, Taal.** Precies de lijst van de comp. De Unified-set
  heeft daarnaast `Servers` en `Bibliotheken`; die staan hier niet, omdat golden 02 geen bronpill
  heeft en de comp ze niet toont. Moeten boeken per server te begrenzen zijn, dan is dat een zesde
  groep en een besluit, geen omissie om er stilletjes bij te zetten.
- **Status is één keuze, de andere vier zijn meerdere.** De comp zet een vinkje bij precies één
  status. `Alles` is daarbij de neutrale stand en telt niet mee voor de telling, en dat is waarom
  `03a` geen `1` naast Status zet terwijl er wel een vinkje staat.

Twee dingen die uit een eerder besluit volgen en hier alleen worden uitgevoerd. De actieve groep
krijgt een witte randbalk plus een opgetilde rij, niet alleen een getinte achtergrond, want in
`monoTheme` valt zo'n tint samen met het oppervlak eronder ([DEC-053](../../../DECISIONS.md#dec-053)).
En de negen genres staan alfabetisch, in hetzelfde aantal als de set, zodat de laatste rij vrij van
de actiebalk blijft.

**Eis aan de implementatie, niet aan de golden.** De rechterkolom scrollt zelfstandig, de
groepenkolom blijft staan. Een groep met meer keuzes dan er passen mag dus niet de hele sheet laten
scrollen, want dan verdwijnt de groep waar je in zit uit beeld.

## Golden 04, Boeken zoeken (approved)

Boeken, auteurs en boekenseries in Pleya's eigen zoekscherm. Inhoud van paneel 4 van de comp,
uitvoering van `05-zoeken.png` uit de iOS Unified-set. Drie frames, samen één scherm: `04a` de
canonieke staat op de zoekterm `dune` met Alles actief en alle drie de resultaatsoorten in beeld,
`04b` dezelfde zoekopdracht met alleen Boeken actief, `04c` een detailuitsnede van de drie
rijsoorten onder elkaar zodat het verschil ertussen te beoordelen is zonder de rest van het scherm.

Golden 04 is op 4 september 2026 goedgekeurd, inclusief de keuzes hieronder.

De drie frames hebben elk een andere rol, en die rollen horen bij de goedkeuring.
`04a-books-search.png` is de **hoofdstaat**: het scherm zoals het zich in de breedte gedraagt, met
alle drie de secties in beeld. `04b-books-search-books.png` is **gedragsbewijs** voor het filteren
door een categorie te kiezen, geen tweede scherm. `04c-books-search-rowtypes.png` is een
**vormspecificatie** van de drie rijsoorten en geen runtime-staat; een implementatie die hem als
scherm behandelt volgt deze golden niet. Bij de goedkeuring hoort dat de lege ruimte onder één
zichtbare resultaatgroep in `04b` zo hoort: er is maar één groep, en die uitrekken zou liegen over
hoeveel er gevonden is.

**Presentatie en matching zijn twee contracten.** Deze golden legt alleen het eerste vast: hoe een
resultaat eruitziet en hoe de soorten uit elkaar te houden zijn. Welke boeken, auteurs en series bij
een zoekterm horen is een rankingbesluit dat los kan bewegen, en dat moet het ook: zodra PS-14 echte
data levert, of zodra er servermatching bij komt, verandert de vulling zonder dat dit beeld
meebeweegt.

**Dit brengt geen eigen zoek-UI mee.** De kop, het zoekveld en de chiprij zijn die van
`05-zoeken.png`, nagemeten en overgenomen: paginamarge 16, veld op 109 met een hoogte van 36 en zijn
glyph op 32, chips op 161 met een hoogte van 33, eerste sectiekop op 213 en de eerste kaart op 236.
`lib/screens/search_screen.dart` heeft die chiprij al, met `_SearchFilter` en een chip per soort die
alleen verschijnt als er resultaten van die soort zijn. Boeken voegt daar een vierde categorie aan
toe en drie resultaatsoorten eronder, niets meer.

Dit is bibliotheekzoeken. Zoeken **binnen** een boek is paneel 9 van de comp, hoort bij de reader en
heeft niets met dit scherm te maken.

**De keuzes die goedgekeurd of afgewezen moeten worden.**

- **De vierde categorie heet `Boekenseries`, niet `Series`.** De comp schrijft `Series`. Onderin
  staat `Series` al voor televisie, en anders dan bij de filtersheet is die tabbalk hier gewoon in
  beeld. Dezelfde redenering als bij golden 01b, waar de rail om die reden `Boekenseries` werd.
- **Een boekrij is cover, titel, auteur, en verder niets.** De comp zet er een derde regel
  `Sci-Fi · 1965` onder. Golden 02 heeft jaar en genre al uit het raster gehouden omdat dit een
  boekenplank is en geen filmcatalogus; een zoekresultaat is dezelfde plank in een andere vorm.
- **Drie silhouetten, zodat de soort te zien is voordat het label gelezen is.** Een boek is een
  cover van 44 × 66 op 2:3, een auteur is een ronde avatar van 44, en een serie is een cover met de
  bladzijden van twee boeken erachter. Die stapelranden zijn crème en niet grijs: bij acht pixels
  breed is het snedevlak het enige deel van een boek dat nog leest tegen een donkere kaart.
- **Een auteursrij draagt alleen de naam.** Een tweede regel zou hem weer op een boekrij laten
  lijken, en dat is precies wat hier niet mag. Of er een telling bij hoort (`3 boeken`) is een open
  vraag, geen besluit dat deze golden neemt.
- **Frank Herbert staat onder Auteurs terwijl zijn naam de zoekterm niet bevat.** De comp doet dat
  ook. Het betekent dat de auteurssectie matcht op wie de gevonden boeken schreef, niet alleen op
  namen die op de zoekterm lijken. Dat is de nuttige uitkomst en het is een echte keuze, want de
  strikte lezing zou hier een lege auteurssectie geven.
- **De actieve chip is een accentrand met accentinkt, geen gevulde rode capsule.** De comp vult hem
  massief rood. `05-zoeken.png` doet dat niet, en op dit scherm zou zo'n blok het enige massieve
  accentvlak zijn op een plek waar accent verder "speelt nu" of "geselecteerd" betekent.
- **Eén afgeronde kaart per sectie met haarlijnen ertussen**, in plaats van de losse kaart per rij
  die de comp tekent. Minder randen op een scherm dat toch al drie verschillende dingen naast elkaar
  moet laten zien.
- **De avatar is een monogram, geen portret.** De comp zet er een foto neer. Een auteursportret is
  niet iets wat als golden-asset in de repository hoort, en de vaste fixture heeft er geen.

De lege staat zit hier bewust niet in. Een zoekscherm zonder resultaten is een eigen compositie, en
hem in dit frame proppen zou de enige vraag die 04 stelt, namelijk of de drie soorten uit elkaar te
houden zijn, alleen maar vertroebelen.

## Golden 05, Boekdetail (approved)

De pagina achter een cover, waar een boek zichzelf voorstelt en het lezen begint. Inhoud van paneel 5
van de comp, uitvoering van `06-film-detail.png` uit de iOS Unified-set. Drie frames, samen één
scherm: `05a` de canonieke staat op Dune, halverwege gelezen, `05b` dezelfde pagina voor een boek dat
nog niet begonnen is en niet in een reeks staat, `05c` een detailuitsnede van het actieblok in beide
staten zodat het verschil zonder de rest van het scherm te beoordelen is.

Golden 05 is op 4 september 2026 goedgekeurd, inclusief de keuzes hieronder, na één correctieronde
op de eerste voordracht. Die ronde had precies één blocker: de primaire knop droeg de play-driehoek
uit de comp, en dat glyph komt uit video terwijl de actie de reader opent. De geometrie, de teksten
en de rest van de compositie zijn daarbij niet aangeraakt.

De rollen van de drie frames horen bij de goedkeuring, net als bij golden 04. `05a` is de
**hoofdstaat**: een boek met leesvoortgang, het geval waar dit scherm voor bestaat. `05b` is
**gedragsbewijs** dat het schermmodel niet verandert als een boek geen reeks en geen voortgang heeft,
geen tweede scherm en geen variant. `05c` is een **ondersteunende vormspecificatie** van het
actieblok en geen runtime-staat; een implementatie die hem als scherm behandelt volgt deze golden
niet.

**Deze golden houdt op bij de knop.** Wat `Lees verder` opent is de reader, paneel 7 van de comp, met
een eigen golden en een eigen goedkeuring. Zolang die er niet is tekent de implementatie de knoppen
en openen ze niets, precies zoals de Filters-pill tussen golden 02 en golden 03 stond. Zo ook voor
het overflowmenu rechtsboven: het staat er omdat de comp het tekent, wat erin zit wordt hier niet
beslist.

De maatvoering komt van `06-film-detail.png` en is nagemeten, niet opnieuw bedacht. De kop staat op
de band 71 tot 84, de pillen zijn 48 hoog met 10 pt ertussen en 16 pt paginamarge, de secundaire is
`#2F2F2F`, en de beschrijving loopt op 16/21. De cover is 150 breed, dezelfde maat die golden 01b een
Boekenseries-kaart gaf, in de 2:3 die golden 02 voor het raster vastlegde. In het gerenderde frame
staat de cover van 104 tot 329, de titel op 349, de pillen op 503 en 561, de statsrij op 629 en de
beschrijving op 689, met de laatste regel 17,7 pt vrij van de tabbalk.

**De keuzes die de bronnen niet zelfstandig maken, en die dus goedgekeurd of afgewezen moeten
worden.**

- **De kop draagt geen titel.** `06-film-detail.png` zet `Dune: Part Two` naast de terugpijl. Paneel 5
  doet dat niet, en de titel staat 270 pt lager in 30 pt vet; hem twee keer zetten levert geen extra
  informatie op en kost de bovenrand zijn rust. De comp wint hier voor de compositie.
- **Voortgang is twee regels tekst en geen balk.** `48% gelezen` is exacter dan een streep en
  `Hoofdstuk 12` zegt waar je bent; een balk zou daar een derde horizontale lijn bij zetten, vlak
  boven twee pillen die de volle breedte pakken. De comp toont ook geen balk. Dit wijkt bewust af van
  de Verder-lezen-kaart op Boeken-home, die er wel een heeft: daar is de kaart klein en de tekst
  onbetaalbaar, hier is het omgekeerd.
- **De primaire actie draagt een open boek, geen play-driehoek.** De comp tekent een driehoek. Dat is
  het glyph voor het starten van een stream, en op het enige scherm in deze reeks waar helemaal geen
  video zit zou het het laatste overblijfsel ervan zijn. De knop opent de reader, dus hij draagt het
  boek, in beide staten en met hetzelfde silhouet als de Boeken-tab, omdat het hetzelfde ding is. De
  pil, de maten, de teksten en de plaatsing veranderen er niet door.
- **De secundaire actie is een gevulde pil, niet de omlijnde uit de comp.** De set vult hem met
  `#2F2F2F`. Een omlijnde knop over de volle breedte zou het enige omlijnde bedieningselement in de
  hele set zijn.
- **De statsrij houdt jaar, genre en pagina's.** Golden 02 hield die uit het raster omdat een plank
  geen filmcatalogus is. Dat was een besluit over het raster, niet over het product: het detail is
  precies de plek waar de metadata van een boek hoort, en de comp zet ze daar ook neer.
- **`616 Pagina's` is bibliografische editiemetadata en géén leespositie.** Een reflowable EPUB heeft
  geen vast aantal schermpagina's: dat verschuift met lettergrootte, lettertype en marges, en het is
  per toestel anders. De kolom toont dus wat de editie of de provider betrouwbaar meelevert, en wordt
  nooit uit de paginering van de reader afgeleid. Levert de bron niets, dan valt de rij terug op twee
  waarden; er verschijnt geen lege kolom en zeker geen `0 Pagina's`. Het is daarmee de enige stat die
  optioneel is: jaar en genre staan er altijd.
- **De genrekolom is 1,45 keer zo breed als de twee andere.** Een gelijke derde is te smal voor het
  enige woord van de drie: `Sciencefiction` liep dan tegen de haarlijnen aan.
- **De reeksregel is een label en verder niets.** `Dune #1` staat onder de auteur, in dezelfde inkt
  als de rest van de secundaire tekst. Of hij naar de reeks navigeert is een open vraag; deze golden
  tekent hem, hij belooft geen bestemming.
- **Drie regels beschrijving met een inline `meer`, ook als er ruimte over is.** In `05a` is drie
  precies wat er boven de tabbalk past. In `05b`, waar het voortgangsblok wegvalt, blijven het er
  drie en valt de winst als witruimte onderaan. Dat is dezelfde regel als bij `04b`: ruimte opvullen
  omdat ze er is liegt over hoeveel er te zeggen valt.
- **Een ontbrekend blok neemt zijn eigen witruimte mee.** De kolom onder de cover is een reeks
  elementen met elk de ruimte erboven; mist een boek zijn reeks of zijn voortgang, dan schuift wat
  eronder staat exact op met wat er weg is. De 24 pt tussen het identiteitsblok en de eerste knop
  blijft in beide staten gelijk, en dat is te zien in `05c`.
- **De ambience is van de cover afgeleid, niet de cover nog een keer.** Dezelfde regel die golden 01b
  voor de Verder-lezen-kaart stelde. De scrim landt het veld op de paginakleur vóór de statsrij, dus
  de onderste helft van het scherm is gewoon `--bg`.

**Wat deze golden expliciet openlaat**, zodat het later een besluit is en geen omissie:

- **De inhoudsopgave heeft geen zichtbare ingang, en die verzinnen we nu niet.** Paneel 6 van de comp
  is de inhoudsopgave, maar paneel 5 toont nergens hoe je er komt. Er komt hier dus geen extra rij
  bij: eerst moet vaststaan hoe de reader opengaat en hoe zijn chrome werkt, want daar hoort een
  inhoudsopgave in de eerste plaats thuis. Blijkt bij golden 06 dat hij ook vóór het openen van het
  boek bereikbaar moet zijn, dan komen we gecontroleerd op golden 05 terug. Alleen die uitkomst is
  grond om dit scherm te heropenen.
- **`Downloaden` legt alleen het zichtbare CTA-slot vast.** Golden 05 zegt dat er een tweede,
  secundaire actie onder de leesknop staat, hoe die eruitziet en waar hij hangt. Wat `Downloaden`,
  `Downloaden…`, `Gedownload`, `Verwijderen` of een foutstaat betekenen, en wanneer ze elkaar
  vervangen, wordt hier niet beslist en mag er ook niet stilzwijgend uit worden afgelezen. Dat blijft
  PS-16, de downloadfase die ook paneel 10 van de comp bedient. Dat nummer staat nog nergens als
  vastgelegde Phase ID: de goedgekeurde serverroadmap loopt tot PS-13, en `PS-14` wordt in golden 04
  net zo gebruikt. Beide horen bij de e-booksnummering en moeten nog in de roadmap landen.
- **Wat er onder de vouw staat.** De pagina scrollt, want de beschrijving is afgekapt. Of daar de
  volledige beschrijving, de reeks of aanbevelingen op volgen is niet vastgelegd.

**Bewuste verschillen met het beeld die geen goedkeuring nodig hebben.** De covers zijn getekend in
CSS en de reekstelling in de comp (`Dune 6 boeken`) staat hier niet, om dezelfde redenen als bij de
eerdere goldens. De tabbalk staat in beeld omdat de comp hem tekent; net als bij golden 02 en 04
dekt het echte scherm `MainScreen` af zodra het op de profielnavigator gepusht wordt, en die
kanttekening verandert hier niet.

## Golden 06, Inhoudsopgave (approved)

De kaart van een boek: waar je bent, wat er achter je ligt, en waar je heen kunt zonder te bladeren.
Inhoud van paneel 6 van de comp, uitvoering van `14-instellingen.png` en `07-serie-afleveringen.png`
uit de iOS Unified-set. Drie frames, samen één scherm: `06a` de canonieke staat op Atomic Habits met
de boom open op de plek waar gelezen wordt, `06b` dezelfde boom met alle delen dichtgeklapt, `06c` een
detailuitsnede van de rijsoorten in hun drie posities, zodat het verschil tussen vóór, op en na de
locator te beoordelen is zonder de rest van het scherm.

Golden 06 is op 4 september 2026 goedgekeurd, inclusief de keuzes hieronder, na twee
correctierondes op de eerste voordracht. Het beeld dat is goedgekeurd is revisie B.

Voordracht A stond op Dune met genummerde hoofdstukken, een opschrift van 11 pt als enige verwijzing
naar het boek, het percentage op de rij van het hoofdstuk, en een kaart die 37 pt boven de actiebalk
ophield. Daaruit kwamen vier punten die hieronder als keuze staan: het boek als rij bovenin,
hoofdstukken met een naam, een eigen staat per hoofdstuk in plaats van een tweede percentage, en een
lijst die onder de balk doorloopt.

Revisie B corrigeerde daarna alleen de betekenis van die staat, en dat was de laatste blocker.
Voordracht A dimde wat vóór de leespositie lag, zette er een vinkje achter en schreef `· gelezen` in
de tweede regel van een deel. Dat is een bewering die de bron niet kan dragen, en Michel heeft hem om
die reden afgewezen. Een locator zegt waar de lezer nu staat, en dus alleen dat een ingang eerder in
de publicatievolgorde komt; hij zegt niet dat die ingang geopend is. Wie vanaf dit scherm naar
hoofdstuk 12 springt zou elf hoofdstukken gedimd en afgevinkt zien zonder er een bladzijde van gezien
te hebben. De vinkjes en de suffixen zijn daarom weg, de drie posities zijn gebleven, en de compositie
is verder onaangeroerd: fixture, geometrie, boomstructuur, open- en dichtgedrag, afbreking, actiebalk
en `Ga naar pagina` staan er precies zoals ze in A stonden. Het enige zichtbare gevolg is dat
`11. Walk Slowly, but Never Backward` nu volledig past, want het vinkje nam de 27 pt die de titel
tekortkwam.

**Wat de goedkeuring van de staatgrammatica betekent voor de code**, omdat het de blocker was die
twee rondes kostte: de gedimde rij is een uitspraak over positie ten opzichte van de huidige locator
en nooit over voltooiing. Een veld of klasse die dit `isRead` of `completed` noemt geeft de golden
verkeerd weer, ook als het beeld klopt.

De rollen van de drie frames horen bij de goedkeuring, net als bij golden 04 en 05. `06a` is de
**hoofdstaat**: de inhoudsopgave van een boek dat halverwege is, het geval waar dit scherm voor
bestaat. `06b` is **gedragsbewijs** dat de boom dichtgeklapt kan worden zonder dat de leespositie uit
beeld verdwijnt, geen tweede scherm en geen variant. `06c` is een **ondersteunende vormspecificatie**
van de rijsoorten en geen runtime-staat; een implementatie die hem als scherm behandelt volgt deze
golden niet. Bij de goedkeuring hoort dat de lege ruimte onder de kaart in `06b` zo hoort: acht
dichtgeklapte rijen zijn acht rijen, en de kaart uitrekken tot de actiebalk zou liegen over hoeveel
er in staat.

**Deze golden tekent het scherm en niet zijn deur.** Waar de inhoudsopgave opengaat zit in de chrome
van de reader, paneel 7, en die heeft geen goedkeuring. Golden 05 heeft om precies die reden geen
inhoudsopgave-rij gekregen. Zolang de reader er niet is worden de rijen getekend en openen ze niets,
dezelfde plek waar de Filters-pill tussen golden 02 en golden 03 stond.

De maatvoering komt uit de set en is nagemeten, niet opnieuw bedacht. De kop staat op de band 71 tot
84 die elk scherm van de set aanhoudt, met de terugpijl op 16 en de titel op 56. De kaart begint op
104, de band waar golden 05 zijn cover zet, en loopt van 16 tot 377 met een hoekradius van 12,
`#1F1F1F` als grond en `#2E2E2E` als haarlijn. De boekrij is de boekrij van golden 04: 82 hoog, cover
44 × 66. Een deel is de tweeregelige rij van `14-instellingen.png`, gemeten op 60,7 en gezet op 61.
Een losse ingang staat op 47,5, de optierij van `04-filters-sheet.png`. Een hoofdstuk staat op 44,
de kleinste rij die iOS laat aantikken. De actiebalk is de balk die golden 03 heeft goedgekeurd:
scheidingslijn op 755, 97 pt hoog, de pil 40 hoog vanaf 771.

In het gerenderde frame `06a` staat de boekrij van 104 tot 186 en de inleiding van 186 tot 233,5. De
delen beginnen op 233,5, 294,5, 355,5 en 416,5; de vier hoofdstukken van het open deel lopen vanaf
477,5 met een steek van 44, zodat hoofdstuk 12 van 521,5 tot 565,5 staat. Het vierde deel begint op
653,5 en het vijfde op 714,5, en dat wordt door de balk op 755 gesneden; de conclusie staat eronder
van 775,5 tot 823. De pil staat van 227 tot 377 en van 771 tot 811, `55% gelezen` links op 782.
Revisie B raakt geen van die getallen aan: de kaart loopt in beide revisies van 104 tot 823 en elke
rij begint op dezelfde punt.

**De keuzes die de bronnen niet zelfstandig maken, en die dus goedgekeurd of afgewezen moeten
worden.**

- **De kop draagt één sluitglyph, en dat is de terugpijl.** De comp zet er een terugpijl én een kruis
  in dezelfde balk. Twee deuren voor één handeling, tenzij het kruis iets anders betekent dan
  teruggaan, bijvoorbeeld het boek verlaten. Dat zou een besluit over de chrome van de reader zijn en
  daar gaat deze golden niet over. Met één glyph leest het scherm als een gepushte pagina, en dan
  staat de titel links naast de pijl zoals bij elke kop in de set, niet gecentreerd zoals in de comp.
- **Het boek staat als eerste rij in de kaart: cover, titel, auteur.** Paneel 6 noemt nergens van
  welk boek dit de inhoudsopgave is. In de comp valt dat niet op omdat het paneel naast de reader
  hangt; op een toestel is het het enige scherm van de reeks dat je niet kunt plaatsen. De rij is
  het silhouet dat golden 04 voor een boekresultaat goedkeurde, dus er komt geen nieuwe vorm bij.
- **De fixture is Atomic Habits en niet Dune.** Dune, het boek van golden 05, heeft geen benoemde
  hoofdstukken, en een inhoudsopgave met alleen `Hoofdstuk 9` tot `17` bewijst niets over wat een
  echte titel op 393 pt doet. Atomic Habits is het enige boek op de plank waarvan de editie zijn
  hoofdstukken benoemt en in delen groepeert, en het heeft in geen enkele goedgekeurde golden een
  leespositie, dus er een geven spreekt niets tegen. Sapiens benoemt ook, maar staat in golden 01b op
  3 % en hoofdstuk 1, en daarmee valt er niets achter de lezer te tekenen. De delen en de namen zijn
  die van het boek zelf; de lezer staat in hoofdstuk 12 van 20, op 55 %.
- **De boom opent op de plek waar je bent.** Het deel met het huidige hoofdstuk staat open, de andere
  dicht. De comp klapt het eerste deel open en markeert niets, terwijl paneel 5 en 7 allebei op
  hoofdstuk 12 staan.
- **Drie posities ten opzichte van de locator, en geen leesstaat.** Wat vóór de locator in de
  publicatievolgorde ligt staat op 38 % inkt, waar de locator staat is wit met een stip in de
  inspringmarge, en wat erna komt houdt de gewone niet-actieve presentatie op 70 %. Dat is precies de
  compositie die voordracht A had, met een andere betekenis eronder: het dimmen zegt "dit komt eerder
  in het boek" en niet "dit heb je gelezen". Er staat daarom geen vinkje achter een ingang en geen
  `· gelezen` onder een deel. Een completionmodel vraagt een eigen bron van waarheid, per ingang
  bijgehouden, en dat is geen besluit dat in een schermgolden thuishoort. In voordracht A stond het
  percentage bovendien twee keer op één scherm, op de rij en in de voet; het staat nu alleen in de
  voet.
- **`55% gelezen` in de voet is een globaal voortgangslabel en blijft staan.** Dat is de
  `totalProgression` van de reader, één getal over de hele publicatie, en geen bewering dat elk
  eerder hoofdstuk afzonderlijk voltooid is. Daarom mag het naast drie posities staan die zich
  nergens over voltooiing uitspreken. Intern heet het `totalProgression`; de gebruikerscopy blijft
  `55% gelezen`.
- **De markering verhuist naar het deel zodra dat dichtklapt.** Rechts naast de chevron, de plek waar
  `14-instellingen.png` zijn eigen stip zet op een rij die aandacht vraagt. `06b` bestaat om dat te
  kunnen beoordelen.
- **Een deel is twee regels, een losse ingang één, een hoofdstuk één met zijn nummer ervoor.** Een
  deel draagt zijn naam en het bereik `Hoofdstuk 11 tot 14` eronder, zodat je ook bij een dicht deel
  weet wat erin zit. Een hoofdstuk schrijft `12. The Law of Least Effort`, precies zoals de
  afleveringenlijst `3. Who Is Alive?` schrijft. De comp geeft alles één regel op een steek van 72 en
  51, losser dan elke lijst in de set; hier zijn het 61, 47,5 en 44, alle drie uit de set of het
  platform.
- **Een titel die niet past breekt af met een ellips, op elk niveau.** `06a` laat dat vier keer zien:
  het eerste deel, het laatste deel, hoofdstuk 13 en hoofdstuk 14. Een tweede regel voor de titel
  zou de steek per rij laten verspringen en de boom onrustig maken; wie de hele naam wil ziet hem in
  de reader.
- **Twee niveaus, en een derde wordt niet getekend.** De navigatie van een EPUB kan dieper nesten dan
  deel en hoofdstuk. Drie niveaus inspringing op 393 pt maakt van een kantlijn een doolhof, dus wat
  dieper zit klapt op zijn hoofdstuk. Dat is een keuze en geen beperking van het formaat.
- **De bovenlaag mengt losse ingangen en delen.** De inleiding en de conclusie hebben geen kinderen,
  zijn geen groep en dragen geen chevron. Dat is wat de comp met `Voorwoord` tekent en wat een echte
  inhoudsopgave doet.
- **Haarlijnen markeren alleen de grenzen van de bovenlaag.** Tussen de hoofdstukken van een deel
  staat er geen lijn; die worden bij elkaar gehouden door hun steek en hun inspringing. Vier lijnen
  in een open deel zouden de kaart in kaartjes hakken, precies wat golden 04 al afwees.
- **`Ga naar pagina` staat in een vaste actiebalk en niet als laatste rij van de kaart.** De comp zet
  hem binnen de kaart. Een inhoudsopgave is lang, en een sprongknop die met de lijst wegscrollt is
  onbereikbaar op het moment dat je hem nodig hebt. De balk is die van golden 03, tot op de punt, en
  om dezelfde reden. Hij is ook een gevulde pil in plaats van de omlijnde uit de comp, dezelfde
  afweging die golden 05 voor zijn tweede actie maakte.
- **`Ga naar pagina` bestaat alleen als de publicatie een bruikbare paginanavigatie meelevert.** De
  voorwaarde is de aanwezigheid van de `page-list`-navigatie van de EPUB, de lijst die de pagina's van
  de gedrukte editie op posities in de tekst afbeeldt. Twee dingen zijn expliciet géén vervanging.
  Schermpagina's niet, want een reflowable EPUB heeft er geen vast aantal van: dat verschuift met
  lettergrootte, lettertype en marges. En de bibliografische paginatelling ook niet, de `320` of
  `496` uit de statsrij van golden 05: dat is een getal over de editie en geen kaart naar plekken in
  de tekst. Draagt de publicatie geen paginanavigatie, dan blijft de knop weg en houdt de balk alleen
  het voortgangslabel. De frames tekenen de knop omdat de fixture die navigatie declareert.
- **De lijst loopt onder de balk door en niets wordt ingekort om hem passend te maken.** De kaart
  eindigt waar de inhoud eindigt. In `06a` is dat op 823, achter een balk die op 755 begint, en dat is
  te zien aan het deel dat halverwege zijn tweede regel gesneden wordt. Wat onder de balk zit is
  bereikbaar door te scrollen; de balk zelf beweegt niet mee.

**Wat deze golden expliciet openlaat**, zodat het later een besluit is en geen omissie:

- **Waar de inhoudsopgave opengaat.** Dat zit in de chrome van de reader en die is niet ontworpen.
  Het gevolg van paneel 6 vóór paneel 7 nemen is dat de presentatiegrammatica hier gekozen wordt
  zonder de ingang te kennen: dit is een gepushte pagina. Maakt de golden van de reader er een sheet
  van, dan komt deze kop terug voor één correctie. Dat is de prijs van deze volgorde en die is nu
  bekend, niet straks.
- **Wat er gebeurt als je een rij aantikt.** Een hoofdstuk kiezen springt de reader in, en die
  bestaat niet. De rijen worden getekend en openen niets.
- **Of er ooit een echte leesstaat per ingang komt.** Deze golden spreekt zich er niet over uit, en
  zolang de enige bron een locator is kan dat ook niet. Wil de app tonen wat werkelijk gelezen is,
  dan is dat een eigen model met een eigen bron, en dan is ook de vraag open wat zo'n staat naast de
  drie posities hier zou moeten tekenen. Wat hier vastligt is dat het dimmen die vraag niet
  stilzwijgend beantwoordt.
- **Wat `Ga naar pagina` opent.** Een veld, een schuif of een eigen sheet: de comp tekent het niet en
  deze golden beslist het niet. Wel dat de knop in de balk staat en wanneer hij er is.
- **Bladwijzers en aantekeningen.** Paneel 7 zet een bladwijzerglyph in de chrome van de reader.
  Of de inhoudsopgave daarnaast een tweede lijst krijgt met bladwijzers en markeringen staat hier
  niet: de comp toont één boom en geen tabs.
- **Hoe een boek zonder delen eruitziet.** Een boek met een platte hoofdstuklijst heeft geen groepen,
  en dan is de bovenlaag de hoofdstuklaag. Uit de regels volgt dat de boom het niveau dat hij niet
  heeft laat vallen, maar geen van de drie frames bewijst het.
- **De vierde kaart in Verder lezen.** Atomic Habits krijgt in de app-fixture een leespositie, en
  daarmee een kaart op Boeken-home. Golden 01b legt de eerste drie kaarten van die rij vast en zegt
  niets over een vierde; waar hij in de rij landt volgt uit de sortering van de rij, niet uit deze
  golden.

**Bewuste verschillen met het beeld die geen goedkeuring nodig hebben.** De comp schrijft in de kop
`Inhoudsoggave`; dat is stil gecorrigeerd. De inhoud van het boek is Engels en de bediening
Nederlands, dus onder `The 3rd Law: Make It Easy` staat `Hoofdstuk 11 tot 14`, en dat is wat de app
bij een Engelse editie ook laat zien. De kleuren van de kaart, de haarlijn en het accent komen uit
`mono_theme.dart` en niet uit de grijstinten van de comp. De tijd in de statusbalk is 9:41 zoals in
de hele set, waar paneel 6 een renderrestje `91:43` laat zien. En anders dan bij golden 02, 04 en 05
staat er geen tabbalk in het beeld die in de app zou ontbreken: paneel 6 tekent er zelf geen, want de
reader dekt hem af.

## Golden 07, Reader (approved, revisie B)

Het leesoppervlak zelf: de pagina waar een boek gelezen wordt, en de chrome die eroverheen komt en
weer weggaat. Inhoud van paneel 7 van de comp, uitvoering op de chrome-grammatica van
`20-speler.png` uit de iOS Unified-set. Drie frames, samen één scherm: `07a` de hoofdstaat met de
chrome zichtbaar, `07b` dezelfde pagina met de chrome verborgen, `07c` een detailuitsnede van
dezelfde regels in licht, sepia en donker.

**Michel heeft revisie B op 4 september 2026 in de chat goedgekeurd**, na visuele beoordeling van de
drie frames op volle resolutie. Voordracht A was inhoudelijk goedgekeurd met drie van de vier keuzes
aangenomen en één verplichte revisie, de leesletter; die zit hierin. Dit is vanaf nu het contract
waar de reader tegen gebouwd wordt.

**Vier implementatieregels die bij de goedkeuring horen** en die het beeld zelf niet laat zien:

- **De reader moet exact ditzelfde fontbestand én dezelfde assen gebruiken.** Alleen
  `fontFamily: Literata` zetten is niet genoeg; zonder `wght` 400 en `opsz` 18 tekent de app een
  andere snit dan de golden.
- **De canonieke staat is een regressiecheck.** Bij de standaard leesstijl moet werkelijk gelden:
  familie Literata, `wght` 400, `opsz` 18, tekengrootte 18 pt, regelband 28 pt. Niet omdat elke
  toekomstige instelling zo moet blijven, maar omdat de standaard anders niet meer op de goedgekeurde
  golden ligt. Kiest een lezer later 22 pt, dan hoort `opsz` mee te bewegen en niet op 18 te blijven
  hangen; of dat automatisch aan de tekstgrootte gekoppeld wordt of expliciet gestuurd, beslist
  golden 08.
- **Markeringsgeometrie volgt de werkelijke tekst- en regelvakken van de readerlaag.** De 27 punt uit
  de maatvoering hierboven is een meting, geen constante om over te schrijven. Wordt hij nagetekend,
  dan loopt de markering scheef zodra tekengrootte, regelafstand of letter verandert.
- **De chrome mag de documentlayout niet beïnvloeden.** Tonen en verbergen levert nul verschuiving
  op; `07b` is daar het bewijs van en de bouw moet datzelfde bewijs leveren.

**Over de markering met Literata.** De twee merkvlakken raken elkaar nu bijna. Beoordeeld en
goedgekeurd: als markering leest dat als één doorlopende passage over twee regels, en niet als twee
losse blokken. De 7 punt opening van Georgia wordt niet kunstmatig teruggebouwd.

**Wat revisie B verandert, en verder niets.**

- **De leesletter is Literata en niet langer de systeem-Georgia van macOS.** Een productbesluit van
  Michel, geen renderdetail: zie de keuze hieronder. De drie frames zijn daarom opnieuw gerenderd en
  opnieuw gemeten, zonder de oude regelovergangen te forceren.
- **De bladwijzer in de chrome is hol getekend in plaats van gevuld.** Een gevuld symbool is zelf een
  staat en zou beweren dat de locator onder deze pagina bewaard is. Dat beslist deze golden niet.
- **Het voetcontract is strenger opgeschreven.** Het percentage en het paginalabel volgen niet meer
  uit dezelfde bron, en `van N` mag nu alleen nog uit een betrouwbaar eindlabel van de `page-list`
  komen.

De rollen van de drie frames horen bij de voordracht, net als bij 04, 05 en 06. `07a` is de
**hoofdstaat**: de pagina zoals je hem ziet op het moment dat je de chrome oproept. `07b` is
**gedragsbewijs** dat de chrome verdwijnt zonder dat er één regel verspringt, geen tweede scherm en
geen variant. `07c` is een **ondersteunende vormspecificatie** van de drie leesthema's en geen
runtime-staat; de reader toont er één tegelijk.

De maatvoering is gemeten op de frames van revisie B, niet bedacht. De chrome staat op de band 62
tot 94 die elk scherm van de set aanhoudt, met de glyfrij op 69,7 tot 86,7 en een paginamarge van
24. De kopregel `DUNE · HOOFDSTUK 12` staat op 128,0 tot 137,3. De tekstkolom begint op 188 en heeft
een marge van 32, breder dan die van de chrome, met 18 pt Literata op een regelband van 28 en 24 pt
tussen de alinea's. De regelbanden liggen daarmee op 188, 216, 244 en zo verder. In `07a` staat de
inkt van de vijf regels van de eerste alinea op 195,0 / 222,7 / 250,7 / 278,7 / 307,0, van de drie
regels van de tweede op 358,7 / 386,7 / 415,0, van de twee van de derde op 466,7 / 499,3. De vierde
alinea is gemarkeerd, en dan meet je het merkvlak en niet de inkt: dat loopt van 540 tot 567 en van
568 tot 595. De breedste regel eindigt op 356,7 in een kolom die tot 361 loopt; de markering bloedt
aan de linkerkant tot 25 door, 7 punt buiten de kolom, zoals een marker over zijn woorden heen
schiet. De schuif ligt op 753,7 tot 772,3 met een greep van 16, het label eronder op 790,0 tot
803,0, en de home-indicator op 839,0 tot 844,0. De sepia-grond meet `#F0E5D7` en de markering
`#FDDF9E`, allebei overgenomen uit paneel 7.

**Wat de wissel van Georgia naar Literata met de bladspiegel deed**, gemeten op `07a` van beide
revisies. Het aantal regels per alinea is gelijk gebleven: vijf, drie, twee, twee. De alinea's twee
tot en met vier breken zelfs op dezelfde woorden. De eerste alinea niet: Literata is breder, dus
`sand.` en `desert` schuiven naar het regeleinde waar Georgia `Paul` en `his` had staan. De inkt
zakt overal 0,3 tot 0,7 punt, want Literata hangt anders in zijn regelband. Het zichtbaarste
verschil zit in de markering: het merkvlak is 27 punt hoog in plaats van 21, dus de twee gemarkeerde
regels raken elkaar nu op 567 en 568 in plaats van 7 punt uit elkaar te staan. Dat is een gevolg van
de metriek van de letter en geen aparte ontwerpkeuze, maar het is wel te zien en het staat hier
daarom.

**De vier keuzes van voordracht A, alle vier genomen.**

- **De leesletter: Literata is de product-serif van de Pleya-reader.**
  Systeem-Georgia is afgewezen. De reden is niet alleen reproduceerbaarheid: de reader wordt een
  eigen productoppervlak, en dan moeten golden en app dezelfde glyphmetriek hebben, moeten iPhone en
  iPad dezelfde snit gebruiken, moet een nieuwe machine dezelfde golden kunnen reconstrueren, en mag
  een OS-update de bladspiegel van een pagina niet stil veranderen. `assets/fonts/Literata-Variable.ttf`
  is daarom onderdeel van het product geworden, byte-identiek aan `google/fonts`, met versie,
  bovenstroomse commit, sha256 en de licentiecontrole in `assets/fonts/README.md`. Het is SIL Open
  Font License 1.1 zonder Reserved Font Name, wat bundelen in een App Store-app toestaat zolang de
  licentietekst meegaat; die staat als `assets/fonts/OFL-Literata.txt` naast het bestand. De
  goldenbron laadt precies dat bestand met een relatief pad, net als Inter, dus er komt geen webfont
  en geen systeemfallback meer aan te pas. **Eén detail moet meeverhuizen naar de app en is nu al
  bekend:** het is een variabele letter met een `opsz`-as, Chromium vult die as zelf met de
  tekengrootte en Flutter doet dat niet. De bron pint hem daarom expliciet op `'opsz' 18, 'wght' 400`
  en de reader moet dezelfde waarden zetten, anders tekent de app een andere snit dan de golden.
  Of `opsz` een door de lezer gekozen tekengrootte volgt hoort bij golden 08.
- **`Pagina 248 van 616`, goedgekeurd met een strenger contract.** Golden 05 heeft vastgelegd dat een
  paginatelling bibliografische editiemetadata is en nooit uit de paginering van de reader komt.
  Golden 06 hing `Ga naar pagina` aan de `page-list`-navigatie van de EPUB en sloot schermpagina's en
  de bibliografische telling daarbij expliciet uit. De voet van de reader houdt zich aan allebei, en
  wel zo:
  - het percentage komt altijd uit `totalProgression` en staat er dus altijd;
  - een paginalabel verschijnt alleen wanneer de publicatie echte `page-list`-navigatie meelevert
    **en** de locator daarop te mappen is; getoond wordt dan het label van die ingang, niet een
    getelde positie;
  - `van N` verschijnt alleen wanneer diezelfde `page-list` een betrouwbaar numeriek eind- of
    totaallabel oplevert. Een page-list mag labels dragen die niet netjes van 1 tot 616 lopen; dan
    staat het huidige label er wel en `van N` niet;
  - `N` wordt nooit berekend uit het aantal ingangen in de `page-list`;
  - de bibliografische `Pagina's` uit golden 05 wordt hier nooit voor hergebruikt. Dat `616` in dit
    frame gelijk is aan de statsrij van golden 05 is een eigenschap van deze editie en geen
    afleiding.

  Er zijn dus drie vormen en `van N` is geen alles-of-nietsvoorwaarde voor het paginalabel:

  | staat | voet |
  | --- | --- |
  | page-list met een betrouwbaar eindlabel | `48% · Pagina 248 van 616` |
  | page-list waarvan alleen het huidige label betrouwbaar is | `48% · Pagina 248` |
  | geen bruikbare page-list | `48%` |

  Het frame toont de rijke staat; de twee andere staan beschreven en zijn niet getekend.
- **Eén zoekglyf, goedgekeurd.** Paneel 7 zet er twee naast elkaar die er hetzelfde uitzien. Eén
  ervan is een vergissing of een tweede functie zonder naam, en deze golden verzint er geen betekenis
  bij: er staat er één, en die opent `Zoeken in boek` uit paneel 9. Dezelfde behandeling die golden
  02 aan de tweede glyf in paneel 2 gaf. Weet Michel wat de tweede moest doen, dan komt hij terug.
- **De inhoudsopgaveglyf duwt golden 06 als pagina, goedgekeurd.** De tweede glyf linksboven is de
  inhoudsopgave. Golden 06 koos zijn presentatie als gepushte pagina zonder de deur te kennen en
  schreef op dat de kop terug zou komen voor een correctie als 07 er een sheet van maakte. Dat
  gebeurt niet: de glyf pusht dezelfde pagina die golden 06 tekent, met de terugpijl die er al op
  staat. **Golden 06 heeft daarmee geen correctieronde nodig.**

**De bladwijzer, gesloten in revisie B.** De glyf is hol. Hol betekent dat de huidige locator geen
bladwijzer heeft; gevuld wordt later de staat waarin hij er wel een heeft. Meer legt deze golden niet
vast. Hoe een bladwijzer bewaard wordt, hoeveel er kunnen zijn, waar je ze terugziet en of ze naast
de inhoudsopgave een eigen lijst krijgen is werk voor later, precies zoals golden 06 het openliet.

**Wat deze golden expliciet openlaat**, zodat het later een besluit is en geen omissie:

- **Hoe de chrome opgeroepen en weggehaald wordt.** `07b` laat zien wat verborgen betekent, niet wat
  het oproept. Een tik in het midden van de pagina is de conventie, maar dan is de vraag wat een tik
  aan de rand doet, en bladeren is paneel 8 (`Scrollmodus`, `Verticale scroll`) en niet deze golden.
- **Wat de markering is en hoe je er een maakt.** Paneel 7 tekent een gemarkeerde zin en deze golden
  tekent hem mee. Hoe een lezer er een maakt en waar ze terug te vinden zijn staat hier niet.
- **Welk thema de reader standaard opent.** Paneel 7 tekent sepia en paneel 12 zet `Leesthema` op
  `Donker`. Die twee spreken elkaar tegen. `07a` en `07b` staan in sepia omdat paneel 7 het onderwerp
  van deze golden is. **Sepia in 07 bewijst geen standaardinstelling**, alleen de sepia-leesstaat;
  welke van de drie standaard geselecteerd staat hoort bij golden 08.
- **Wat de schuif doet terwijl je hem sleept.** Er is geen voorbeeldweergave, geen hoofdstuknaam die
  meeloopt en geen terugsprongknop getekend. Of de reader die nodig heeft is een eigen vraag.
- **De liggende stand en de iPad.** Beide frames zijn staand op 393 pt. Een tekstkolom van 329 pt
  breed is op een iPad een verkeerde maat, en de vijf iPad-goldens die nog komen zijn de plek waar
  dat beslist wordt.
- **De cursieve snit van Literata.** Deze golden tekent geen cursief, dus staat het bestand nog niet
  in de repository. Een EPUB met `<em>` heeft hem nodig; herkomst, licentie en hash liggen al klaar
  in `assets/fonts/README.md`, dus toevoegen is dan mechanisch en geen tweede licentieronde.

**Bewuste verschillen met het beeld die geen goedkeuring nodig hebben.** De comp schrijft de
kopregel als `DUNE - HOOFDSTUK 12` en de voet als `48% - Pagina 248 van 616` met een koppelteken;
hier staat de punt die golden 01b voor `48% · Hoofdstuk 12` heeft goedgekeurd. De passage is voor
deze repository geschreven en niet uit het boek geciteerd, en hij staat in het Engels omdat de vaste
set Dune als Engelse editie voert; de Nederlandse vulling van de comp zou een vertaling op het scherm
zetten die de plank niet heeft. De kopregel blijft wél Nederlands, want die wordt door de app
gemaakt uit `chapterLabel`, precies zoals golden 06 `Hoofdstuk 11 tot 14` onder een Engelse titel
zet. Paneel 12 noemt `Georgia` als lettertype en de reader draagt nu Literata; dat is de keuze
hierboven en golden 08 erft hem. De chrome staat direct op de pagina zonder de scrim die
`20-speler.png` onder zijn bediening legt: die scrim tilt witte glyfs van een bewegende foto, en een
pagina tekst is geen van beide. De statusbalk staat in `07b` gewoon aan, want iOS houdt hem daar en
een leeg gat rond de inkeping is geen leeswinst. En de kopregel verdwijnt niet met de chrome mee:
dat is de kopregel van de pagina, zoals een gedrukt boek er bovenaan een draagt, en geen bediening.

## Golden 08, Leesinstellingen (proposed)

Waar je de pagina zet: tekengrootte, regelafstand, marges, thema en scrollmodus. Inhoud van paneel 8
van de comp, uitvoering op de bladgrammatica van golden 03. Drie frames, samen één scherm: `08a` het
blad open over de leespagina, `08b` diezelfde pagina op de grootste stop met het blad dicht, `08c`
een detailuitsnede van de vijf bedieningen met hun staten.

**Dit is een voordracht en geen contract.** Er mag niets tegen gebouwd worden voordat Michel de
keuzes hieronder heeft goedgekeurd of afgewezen. Eén ervan raakt bovendien een goedgekeurde golden:
dit blad heeft geen deur, en de enige plek waar er een past is de chrome van golden 07.

`08a` is de **hoofdstaat**: het blad zoals het opengaat, met de instellingen die op de pagina
eronder staan. `08b` is **gedragsbewijs**, en het enige frame in de set dat laat zien wat een
instelling met de pagina doet. `08c` is een **ondersteunende vormspecificatie** van de bedieningen
en geen runtime-staat; geen scherm toont een bediening twee keer.

De maatvoering is gemeten op de gerenderde frames. Het blad begint op 340, met de hoek van 13 en de
greep van 36 × 5 die golden 03 vastlegde, en de kop `Leesinstellingen` in 18 pt bold op 368,7 tot
387,0. Elke groep is een label van 16 met zijn bediening 24 daaronder: `Lettergrootte` op 405,3 met
de schuif op 434 tot 453, `Regelafstand` op 485,0 met de rij op 506 tot 542, `Marges` op 569,3 met
de rij op 590 tot 626, `Thema` op 653,3 met de schijven op 670 tot 722 en hun onderschriften op
727,7 tot 739,7. De haarlijn ligt op 754 en de scrollrij van 772 tot 808,7. De bedieningsrijen zijn
36 hoog met 8 ertussen, de themaschijven 44 met 26 ertussen, en de schakelaar is de iOS-maat van
51 × 31.

**De keuzes die deze golden moet nemen.**

- **Het blad heeft geen deur, en de enige plek waar er een past zit in een goedgekeurde golden.** De
  chrome van golden 07 heeft vier glyfs en geen daarvan opent instellingen. Paneel 7 tekent er vijf,
  waarvan twee identieke vergrootglazen; golden 07 heeft de tweede weggelaten omdat hij geen
  betekenis had, met de aantekening dat hij terugkomt als die betekenis er blijkt te zijn. Dit is de
  betekenis: **`Aa` in het vijfde slot**, links van het vergrootglas. Beide frames tekenen die
  chrome. Dat is een aanvulling op een goedgekeurde golden en vraagt dus apart goedkeuring; de
  bandhoogte, de marge en de vier bestaande glyfs veranderen niet.
- **Er staat geen `Lettertype`-rij in, en paneel 8 tekent er wel een.** De comp zet `Georgia` in een
  keuzerij. Pleya bundelt sinds golden 07 één leesletter, Literata, en een keuzelijst met één
  ingang is een bediening die je niet kunt bedienen. Dezelfde behandeling die golden 07 de tweede
  vergrootglas gaf en golden 02 de tweede glyf in paneel 2: niet tekenen tot hij iets doet. De rij
  komt terug op de dag dat er een tweede snit in `assets/fonts` staat. Het alternatief is de rij wel
  tekenen met `Literata` erin als vaste waarde, en dat is verdedigbaar als je hem als informatie
  leest in plaats van als keuze.
- **De stopwaarden.** Zes tekengroottes (15, 16,5, 18, 20, 22 en 24 pt), drie regelbanden (1,33,
  1,56 en 1,78 keer de tekengrootte) en vier marges (20, 26, 32 en 40). In alle drie is de
  goedgekeurde staat van golden 07 een stop: 18 pt is de derde, 28 op 18 is de middelste band, en 32
  is de derde marge. Zes stops en geen vrije schuif, omdat een leesmaat een keuze uit een reeks is
  waar een typograaf voor kan instaan en niet een getal waar je tussen kunt landen.
- **De optische as reist mee met de maat.** Kies je 24 pt, dan gaat `opsz` mee naar 24; `08b` is in
  die snit gezet. Dat is wat optische maatvoering betekent, en het alternatief, `opsz` vastzetten op
  18, laat een pagina op 24 pt in een snit staan die voor kleiner werk getekend is. Sturen blijft
  mogelijk (`ReaderTypography.styleFor` heeft er een aparte parameter voor), maar dit voorstel
  gebruikt hem niet.
- **Sepia staat aan in `08a`, en dat is de gekozen waarde en niet de standaard.** Paneel 12 zet
  `Leesthema` op `Donker` als profielinstelling, en dat is golden 12. Het blad hoort te tonen wat er
  op de pagina eronder staat, en die staat in sepia omdat golden 07 daar in gezet is. Wat een vers
  profiel krijgt is dus een andere vraag dan wat dit blad tekent.
- **Het blad heeft geen scrim en dekt de pagina niet af.** Golden 03 legt een zwarte laag van 60 %
  over het hele frame; dat werkt voor een filtersheet, waar de lijst eronder niet meebeweegt. Hier
  zet je de tekst die je aan het lezen bent, dus die tekst moet zichtbaar blijven: het blad begint
  op 340 en er ligt niets overheen. Boven het blad staan de kopregel en de eerste alinea, precies
  het stuk waar je naar kijkt terwijl je schuift.

**Wat deze golden openlaat**, zodat het later een besluit is en geen omissie:

- **Wat de scrollmodus aanzet.** De rij is getekend en de schakelaar staat uit. Verticaal scrollen
  in plaats van bladeren is een tweede leesmodus met een eigen bladspiegel, een eigen voet en een
  eigen antwoord op wat een pagina dan nog is. Dat is geen schakelaar maar een scherm, en het heeft
  er geen.
- **Of het blad meteen toepast of pas bij sluiten.** `08a` en `08b` zijn twee frames en geen
  animatie. Het voorstel dat eronder ligt is direct toepassen, want dat is de hele reden dat de
  pagina zichtbaar blijft, maar bewezen wordt het hier niet.
- **Wat er gebeurt met de leespositie als de tekst herpagineert.** Op 24 pt passen er twee alinea's
  op de pagina in plaats van vier. De voet blijft `48% · Pagina 248 van 616` staan, en dat klopt:
  allebei die getallen gaan over waar de lezer in de publicatie staat en niet over hoeveel er op
  het scherm past. Hoe de reader die positie vasthoudt terwijl hij opnieuw zet, is de
  reader-engine, en die is PS-15.
- **Terugzetten op de standaard.** Er is geen `Herstel`-knop getekend en of die er hoort is niet
  beslist.
- **De liggende stand en de iPad**, om dezelfde reden als bij golden 07.

**Bewuste verschillen met het beeld die geen goedkeuring nodig hebben.** De comp noemt het blad
`Instellingen`, hetzelfde woord dat paneel 12 voor de profielinstellingen van Boeken gebruikt; hier
staat `Leesinstellingen`, zodat de twee schermen in de app niet dezelfde kop dragen. De comp tekent
het blad als een losse kaart over het hele scherm en niet als een blad over de pagina; de reden voor
dat verschil staat hierboven. De schakelaar is groen, de iOS-kleur, en niet het accent: het accent
is in dit blad al de gekozen-markering van de schuif en van het thema, en dezelfde kleur voor
"gekozen" en voor "aan" zou de twee laten samenvallen.

Eén ding dat het beeld zelf laat zien en dat beoordeling vraagt: **de vier marge-iconen liggen dicht
bij elkaar.** Op 26 punt breed is het verschil tussen de eerste en de tweede stop twee punt
tekening. De reeks leest van smal naar breed en de gekozen stop is duidelijk, maar of vier stops
hier vier verschillende iconen waard zijn is een oordeel over het beeld en geen meting.

## Wat er tegen golden 07 gebouwd is

`lib/screens/books/book_reader_screen.dart`, met `widgets/book_reader_chrome.dart` eronder voor de
glyfs, de kopregel, de alinea met zijn markering en de voet. Daaronder liggen drie modules die geen
widget zijn: `lib/books/reader_typography.dart` (de snit), `book_reader_theme.dart` (de drie
leesthema's uit `07c`) en `book_reader_layout.dart` (de banden). Het scherm heeft nu wél een deur:
`Lees verder` op
het boekdetail opent hem, en de inhoudsopgaveglyf in de chrome pusht golden 06.

**De leesletter is een module en geen `TextStyle` in een widget.** `ReaderTypography` is de enige
plek waar de reader zijn snit vandaan haalt, en dat is nodig omdat drie dingen samen moeten kloppen
en elk ervan stil misgaat. Literata is variabel: Chromium vult de `opsz`-as zelf met de
tekengrootte, Flutter blijft op de fontstandaard 12, dus de as wordt expliciet gezet. En een `Text`
mengt de omringende `DefaultTextStyle` in de zijne, waardoor de reader Materials
`letterSpacing: 0.3` erfde. **Dat kostte de eerste regel 11,7 punt breedte** bij precies dezelfde
woorden en dezelfde regelovergangen, en geen enkele widgettest zag het: het valt alleen op naast de
golden. De leesstijl erft daarom niets meer (`inherit: false`) en zet zijn eigen `letterSpacing`,
`wordSpacing` en `leadingDistribution`. Die laatste staat op `even`, de halve leading die CSS
gebruikt; Flutters standaard verdeelt evenredig en zet de basislijn een fractie lager.

**De markering leest zijn geometrie uit de tekst.** `computeLineMetrics()` van dezelfde
`TextPainter` die de alinea zet, met de bovenkant als basislijn min stijgvlak en de hoogte als de
regelband. De 27 punt uit de maatvoering staat nergens in de code. Eén subtiliteit die vier punt
kostte: `getBoxesForSelection` loopt tot het einde van de regel inclusief de spatie die de
regelovergang opat, dus die is vervangen door `LineMetrics.width`, de gezette breedte van de regel
zelf. En de overschieting van 7 punt hoort bij de passage en niet bij elke regel: een marker wordt
vóór het eerste woord neergezet en ná het laatste opgetild, precies zoals de browser een inline
`box-shadow` over regelfragmenten snijdt. Op elke regel getekend zou hij bij iedere regelovergang
een keep in de linkermarge zetten.

Bewijs: `pleya_verify/scenarios/books.reader.layout.yaml` groen op de vastgezette iPhone 15
Pro-simulator, met beide staten in één bundel, plus tien widgettests in
`test/screens/book_reader_screen_test.dart` en vijftien eenheidstests in
`test/books/book_reader_test.dart`. De hele suite staat op 5019 groen.

De vier gemeten automation-nodes liggen exact op de golden: de chrome op (0, 62) met 393 × 32, de
tekstkolom op (32, 188) met 329 × 564, de voet op (0, 752) met 393 × 52 en de inhoudsopgaveglyf op
(74, 65) met 26 × 26. **En het bewijs waar `07b` voor bestaat staat er twee keer in dezelfde
bundel:** na het verbergen van de chrome meet de kolom `GeoRect(32.0, 188.0, 329.0x564.0)`, tot op de
punt hetzelfde rechthoekje als ervoor. In de widgettests wordt dat op de rect gecontroleerd en niet
op de widgetboom, want een boom die er hetzelfde uitziet kan nog steeds anders meten.

Een rijprofiel over `07a` en het simulatorbeeld: de statusbalk, de glyfrij, de kopregel, de schuif,
het label en de home-indicator liggen binnen 0,33 punt. De twaalf tekstregels liggen horizontaal op
**nul punt** verschil, links en rechts, regel voor regel. De markering begint in allebei op 25,0 en
eindigt op 357,0 tegen 356,67 en op 235,0 tegen 234,67.

Bewuste verschillen met het beeld:

- **De inkt staat 1,00 punt lager in de app**, op elke regel even veel. Het regelvak niet: de
  markering begint in allebei precies op 540, de regelmaat van 28 klopt, en de regelbreedtes liggen
  op nul. Het verschil zit in waar de basislijn binnen een identiek regelvak landt, tussen de
  tekstzetter van Flutter en die van de browser. Een punt op een pagina van 852, uniform, en niets
  in de layout verschuift mee.
- **Het merkvlak is 28 punt hoog en niet 27, dus de twee gemarkeerde regels raken elkaar.** Dat is
  de goedgekeurde uitkomst van de regel dat de markering de echte regelvakken volgt: 27 is de
  som van stijg- en daalvlak van de letter, 28 is de regelband die de reader zet.
- **De schuifschaduw is 1,33 punt hoger zichtbaar** dan in de browser, bij een gelijke onderkant.
- **De grond is `#F0E5D7` en niet de OLED-variant.** De reader zet zijn eigen papier neer en leest
  `monoTheme` niet, anders dan de andere boekenschermen; dat is de hele reden dat `BookReaderTheme`
  bestaat.

Wat bewust niet gebouwd is, en waar dus geen code voor bestaat:

- **Paginering.** De fixture levert een pagina en geen boek. Tekst in pagina's snijden is de
  reader-engine, die bij PS-15 hoort. De kolom is daarom een vak waar de pagina in moet passen, met
  een widgettest die dat controleert, en geen venster op een langere tekst.
- **Bladeren, en wat een tik aan de rand doet.** Een tik op de pagina haalt de chrome weg en zet hem
  terug, de conventie die de golden noemt. Verder doet een tik niets, en de randen doen niets.
- **De schuif slepen, `Zoeken in boek`, en de bladwijzer.** Alle drie getekend en inert, elk om zijn
  eigen reden uit de golden.
- **Van thema wisselen.** `BookReaderTheme` heeft de drie van `07c` en een test die hun kleuren
  vastlegt, maar er is geen bediening: welk thema standaard staat en hoe je wisselt is golden 08.
- **De cursieve snit van Literata**, want deze pagina tekent er geen.

Drie dingen die uit de bouw komen en niet uit de golden, en die goedkeuring vragen:

- **De glyfs in de chrome zijn 26 punt en dat is minder dan de 44 die iOS als minimum aanhoudt.** Dat
  is geen implementatiekeuze die stilletjes te repareren valt: de chromeband van de golden is 32 punt
  hoog, dus een raakvlak van 44 past er niet in zonder de band te veranderen. De rijen van golden 06
  worden wel op 44 getoetst; deze glyfs bewust niet, en de scenario-regel zegt dat er ook bij.
- **De inhoudsopgaveglyf is inert op Dune.** Hij pusht golden 06 voor een publicatie die navigatie
  declareert, en in de vaste set is dat alleen Atomic Habits; Dune levert een `page-list` maar geen
  boom. De glyf wordt wel getekend, want de golden tekent hem. Of Dune een boom in de fixture krijgt
  is een keuze over de fixture, en een boek zonder delen is een staat die golden 06 expliciet
  openlaat, dus die is hier niet genomen.
- **De tik op de pagina.** De golden noemt hem de conventie en beslist hem niet. Zonder hem is `07b`
  onbereikbaar en heeft de reader geen manier om zijn chrome kwijt te raken, dus hij zit erin, alleen
  hij, en de randen blijven onaangeroerd.

## Wat er tegen golden 06 gebouwd is

`lib/screens/books/books_toc_screen.dart`, met `widgets/book_toc_rows.dart` eronder voor de vier
rijsoorten. Het scherm heeft geen deur, en dat is de golden zelf: waar een inhoudsopgave opengaat
zit in de chrome van de reader, en golden 05 heeft er om precies die reden geen rij voor gekregen.
Er is dus niets dat een lezer kan aanraken dat deze route opent. Boeken-home registreert er onder
`kPleyaVerify` een route-opener voor, zodat het scherm op een toestel te fotograferen is; in een
gewone build verdwijnt die met de rest van het automation-oppervlak.

**De semantische regel staat in de code en niet alleen in het beeld.** `BookTocPosition` heeft drie
waarden, `behind`, `atLocator` en `ahead`, en de klassendocumentatie zegt waarom: een locator zegt
waar de lezer nu staat en dus alleen dat een ingang eerder in de publicatievolgorde komt. Het woord
`read` en het woord `completed` komen in `lib/books/book_toc.dart`, `book_toc_view.dart` en het
scherm niet voor. De enige leesuitspraak is `totalProgression` in de voet, en een widgettest
controleert dat er nergens een vinkje staat en dat `55% gelezen` precies één keer op het scherm
voorkomt.

**De layoutregel is een eigen module, met een andere vorm dan bij golden 05.** Het boekdetail is
een vaste reeks blokken; deze lijst is variabel. `lib/books/book_toc_layout.dart` is daarom een
tabel per rijsoort (boekrij 82, losse ingang 47,5, deel 61, hoofdstuk 44, inspringing 28), en
`positions()` loopt over de rijen die de boom op dat moment tekent. Het scherm bouwt de kaart uit
diezelfde tabel, dus voorspelling en implementatie kunnen niet uit elkaar lopen. Wat een rij *is*
staat een laag lager: `book_toc.dart` heeft de boom en de positiebepaling, `book_toc_view.dart`
leidt daar de getekende rijen uit af. Dezelfde scheiding als bij golden 04 en 05, en om dezelfde
reden: die metadata beweegt zodra PS-14 echte navigatie levert, en dan verschuift die laag en geen
widget.

Bewijs: `pleya_verify/scenarios/books.toc.layout.yaml` groen op de vastgezette iPhone 15
Pro-simulator, met beide staten in één bundel, plus vijftien widgettests in
`test/screens/books_toc_screen_test.dart` en twintig eenheidstests in `test/books/book_toc_test.dart`.
De hele suite staat op 4994 groen.

De vergelijking is de scherpste tot nu toe. De vier gemeten automation-nodes liggen exact op de
golden: de boekrij op 104 met 361 × 82, het open deel op 416,5 met 61 hoog, hoofdstuk 12 op 521,5
met 44 hoog, en de pil van 771 tot 811. Een rijprofiel over `06a` en het simulatorbeeld legt elk
tekstblok in de kaart op nul punt verschil: boekrij 112,0, inleiding 203,0 tegen 203,3, de vier
delen op 248,3 / 309,3 / 370,3 / 431,3 met het bereik van het vierde op 452,7, de vier hoofdstukken
op 493,3 / 536,7 / 581,0 / 625,0, het vijfde en zesde deel op 668,0 en 729,0, en de voet op 785,0
tegen 785,3. Alleen de kop ligt 0,7 hoger. Horizontaal net zo: een deeltitel begint in allebei op
32,67, de stip bij hoofdstuk 12 staat in allebei op x 44,0 tot 49,7, en de inspringing van een
hoofdstuk meet 28,3 tegen 28,0. Voor `06b` geldt hetzelfde: na het dichtklappen staat het vierde
deel op 477,5, precies waar de tabel het voorspelt, en elk tekstblok ligt binnen 0,3 punt.

Wat die vergelijking opleverde, en wat geen enkele test zag:

- **Met de boom dichtgeklapt hing de actiebalk midden op het scherm.** De balk staat als
  `Positioned(bottom: 0)` in een `Stack`, en een `Stack` schaalt naar zijn grootste kind. Een
  `SingleChildScrollView` onder losse constraints meet zich op zijn inhoud, dus bij acht
  dichtgeklapte rijen was de stack 768 hoog in plaats van 852 en landde de balk op 671. In `06a`
  viel het niet op, want daar is de inhoud hoger dan het scherm: de fout bestond alleen in de staat
  waar de kaart de pagina niet vult. Dat is precies de lege ruimte onder de kaart die bij de
  goedkeuring van `06b` hoort. Opgelost met `StackFit.expand`; de test die het nu bewaakt zakt zonder
  die regel met de pil 84 punt omhoog.

Bewuste verschillen met het beeld:

- **De pagina is zwart en niet `#141414`.** De verify-simulator draait de OLED-variant van
  `monoTheme`. De kaart zelf meet in allebei exact `#1F1F1F`, dus het verschil zit in de grond
  eromheen en niet in de kaart.
- **De cover is getekend door `BookCover` en niet door de CSS van de bron.** Zichtbaar gevolg: de
  app zet er ook `JAMES CLEAR` op, de golden niet.
- **`Ga naar pagina` is 3,3 punt breder**, 223,7 tot 377,0 tegen 227 tot 377. De rechterrand, de
  hoogte en de verticale plaatsing zijn gelijk; het verschil is de breedte van dezelfde tekst in
  Inter zoals de app hem laadt tegenover de browserrender.
- **Een titel breekt soms één glyph eerder af.** `Advanced Tactics: How to Go fro…` tegen
  `… from…`, uit dezelfde metriek.
- **De actiebalk gebruikt 7 punt onder de pil en niet de 8 van de filtersheet.** Alles erboven is
  golden 03's balk ongewijzigd; met 8 ligt de hele band één punt hoog, op 754 en 770 in plaats van
  golden 06's eigen 755 en 771. Dat punt komt van de ruimte onder de pil, waar niets getekend wordt.

Wat bewust niet gebouwd is, en waar dus geen code voor bestaat:

- **De reader.** Elke rij wordt getekend en opent niets, precies waar de Filters-pill tussen golden
  02 en 03 stond. Een widgettest tikt een hoofdstuk, de boekrij en `Ga naar pagina` aan en
  controleert dat er niets opengaat en dat geen rij verschuift.
- **Wat `Ga naar pagina` opent.** Er is geen invoerveld, geen schuif en geen sheet: wat die knop
  opent is een open punt van de golden. Wel de voorwaarde eronder, `BookToc.hasPageList`, met de
  regel dat schermpagina's en de bibliografische paginatelling er geen vervanging voor zijn. Een
  eenheidstest en een widgettest laten zien dat een publicatie zonder die navigatie het label houdt
  en de knop verliest.
- **Een ingang vanaf het boekdetail.** Golden 05 heeft daar geen rij en de widgettest die dat bewaakt
  staat er nog. Golden 06 heeft de presentatie als gepushte pagina gekozen zonder de deur te kennen,
  en die deur blijft dus open tot golden 07.
- **Een derde niveau.** Wat dieper nest dan deel en hoofdstuk klapt op zijn hoofdstuk, zoals de
  golden zegt. Het model verbiedt een diepere boom niet, maar er is geen fixture die er een heeft.
- **Een boek zonder delen.** De golden laat expliciet open hoe dat eruitziet en geen frame bewijst
  het, dus er is ook geen fixture voor. Atomic Habits is de enige publicatie in de vaste set die
  navigatie declareert; de rest antwoordt `null`, en dat is iets anders dan een lege boom.

Eén ding dat niet uit de golden volgt maar wel uit het scherm, en dat goedkeuring vraagt:

- **De leespositie van Atomic Habits staat bij de reader en niet op de plank.** Golden 06 noemt als
  open punt dat Atomic Habits in de app-fixture een leespositie krijgt en daarmee "een vierde kaart"
  in Verder lezen. Dat klopt niet: die rij sorteert op voortgang, en 55 % gaat vóór Dune op 48 %.
  Het zou dus geen vierde kaart worden maar een nieuwe eerste, op precies de rij waarvan golden 01b
  de eerste drie kaarten vastlegt. `Book.progress` van Atomic Habits blijft daarom leeg en de
  locator zit in `BookToc`, waar hij inhoudelijk ook hoort: een publicatiebrede `totalProgression`
  met een positie erin is reader-state. Boeken-home blijft daarmee exact zoals hij is goedgekeurd.
  Een eenheidstest legt dat vast, met de reden erbij.

## Wat er tegen golden 05 gebouwd is

`lib/screens/books/book_detail_screen.dart`, met `widgets/book_detail_ambience.dart`,
`widgets/book_detail_actions.dart` en `widgets/book_description.dart` eronder. Het scherm is
bereikbaar vanaf de Verder-lezen-kaart en de Recent-toegevoegd-rij op Boeken-home, vanaf een cel in
Alle boeken, en vanaf een boekrij in Boeken zoeken. Auteurs- en seriesrijen gaan er niet heen, want
waar die naartoe leiden staat in geen enkele goedgekeurde golden.

**De layoutregel is een eigen module en geen reeks getallen in een widget.**
`lib/books/book_detail_layout.dart` is de tabel uit de bron van de golden: per blok de ruimte erboven
en zijn eigen hoogte. `positions()` rekent daar de voorspelling uit, en het scherm bouwt zijn kolom
uit diezelfde tabel, dus voorspelling en implementatie kunnen niet uit elkaar lopen. Een blok dat een
boek niet heeft, verdwijnt met zijn eigen witruimte; niets ertussen rekt op om het gat te vullen.
`lib/books/book_detail_view.dart` staat daarnaast en leidt af wát een blok zegt: de reeksregel, de
twee voortgangsregels en de statskolommen. Dat is dezelfde scheiding die golden 04 met
`BookSearchRanking` maakte, en om dezelfde reden: de metadata onder dit scherm gaat bewegen zodra
PS-14 echte data levert, en dan verschuift die laag en geen widget.

Bewijs: `pleya_verify/scenarios/books.detail.layout.yaml` groen op de vastgezette iPhone 15
Pro-simulator, plus achttien widgettests in `test/screens/book_detail_screen_test.dart` en vijftien
eenheidstests in `test/books/book_detail_layout_test.dart`. De hele suite staat op 4960 groen.

De vergelijking met `05a` is de scherpste van de vijf tot nu toe. De vier gemeten automation-nodes
liggen exact op de golden: cover op 104 met 150 × 225, de primaire pil op 503, de secundaire op 561
en de statsrij op 629, allemaal 361 breed vanaf 16. Een rijprofiel over beide frames legt ook elk
tekstblok op nul punt verschil: titel 356,0, auteur 393,7, reeks 417,0, percentage 445,0, hoofdstuk
465,0, het label in de primaire pil 520,7, dat in de secundaire 579,0, de statswaarden 633,7, de
statslabels 656,0, en de drie beschrijvingsregels op 693,0 / 714,0 / 735,0. De kolomgrenzen van de
statsrij vallen in allebei op 121 en 272, dus de genrekolom is werkelijk 1,45 keer zo breed.

Wat de vergelijking opleverde, en wat geen enkele test zag:

- **Het scherm sprak half Nederlands en half Engels.** `Verder lezen` en `Download` kwamen uit
  bestaande vertaalde sleutels, terwijl `48% read`, `Year` en `Pages` op het Engelse basisniveau
  terugvielen. Dat is het gevolg van alleen `en.i18n.json` bijwerken op een scherm dat naast
  hergebruikte sleutels ook nieuwe heeft. Alle acht de nieuwe sleutels staan nu ook in
  `nl.i18n.json`.
- **De knop leende de kop van een rij.** `books.continueReading` is `Verder lezen`, de rijkop die
  golden 01b goedkeurde; golden 05 zet op de knop `Lees verder`. Een kop noemt een rij en een knop
  noemt een handeling, dus de knop heeft nu zijn eigen `books.readContinue`. Hetzelfde voor de
  tweede pil: de app-brede `downloads.downloadNow` is in het Nederlands `Download`, de golden zegt
  `Downloaden`, en die string aanpassen zou elk ander scherm dat hem gebruikt herformuleren. Boeken
  heeft er daarom een eigen `books.download` naast.

Bewuste verschillen met het beeld:

- **Er is geen tabbalk.** Hetzelfde als bij golden 02 en 04: het scherm wordt op de profielnavigator
  gepusht en dekt `MainScreen` volledig af. Nagemeten op de bewijsbundel, waar de balk van de golden
  op 776 het enige blok is dat in de app ontbreekt.
- **De ambience is afgeleid, niet overgenomen.** De golden zet voor Dune en Project Hail Mary met de
  hand gekozen kleuren neer; de app leidt ze af uit `BookArtwork`, zoals golden 01b voor de
  Verder-lezen-kaart voorschrijft. Voor Dune komt dat dicht bij het beeld uit. Voor een boek met een
  bijna zwarte grond en een felle accentkleur, zoals Project Hail Mary, wordt het veld donkerder dan
  de golden het tekent, want die haalt daar zijn ground uit het accent.
- **De scrim landt op de themakleur, niet op `#141414`.** De verify-simulator draait de
  OLED-variant van `monoTheme` met een zwarte pagina. Een scrim die op `#141414` eindigt zou daar een
  zichtbare band achterlaten precies waar hij op de pagina hoort te landen, dus hij leest
  `scaffoldBackgroundColor`. In het niet-OLED-thema is dat exact de kleur van de golden. Zichtbaar
  effect: de tweede pil tekent in de app een rand die in de golden wegvalt tegen de achtergrond,
  dezelfde geometrie bij meer contrast.
- **De cover is getekend en de beschrijving komt uit de vaste set**, om dezelfde redenen als bij de
  eerdere goldens.
- **De koptaphoogte is 32 punt.** Dat is de band die de golden tekent. Breder maken zonder het glyph
  te verplaatsen kan alleen door het blok hoger te maken, en dat verschuift de cover en daarmee de
  hele kolom eronder.

Wat bewust niet gebouwd is, en waar dus geen code voor bestaat:

- **De reader.** Beide pillen worden getekend en openen niets, precies waar de Filters-pill tussen
  golden 02 en 03 stond. Een widgettest tikt ze allebei aan en controleert dat er niets opengaat.
- **De downloadstaten.** `Downloaden` is alleen het zichtbare CTA-slot. Wat `Downloaden…`,
  `Gedownload`, `Verwijderen` of een foutstaat betekenen blijft PS-16.
- **Het overflowmenu.** Getekend omdat de comp het tekent, zonder handler.
- **`meer` is tekst, geen knop.** Wat er onder de vouw staat is een van de dingen die golden 05
  openlaat, en in de pagina uitklappen zou dat beantwoorden.
- **Geen inhoudsopgave-rij.** Die blijft open tot golden 06. Een widgettest bewaakt dat er tussen de
  blokken die golden 05 noemt niets is bijgekomen.

Twee dingen die niet uit de golden volgen maar wel uit het scherm:

- **`Pagina's` is optioneel en `Brave New World` heeft er geen.** De vaste set draagt bewust één
  editie zonder paginatelling, zodat de terugval op twee kolommen echt is en niet theoretisch. Er
  verschijnt nooit `0 Pagina's`: een nul is een bron die niets te zeggen heeft.
- **De reeksregel heeft de reekstitel nodig, niet alleen het `seriesId`.** Kan het profiel de reeks
  niet benoemen, dan blijft de regel weg in plaats van dat er een label verzonnen wordt.

Wat het scenario niet bewijst: de onbegonnen staat van `05b`. Een route-opener is een `VoidCallback`
per scherm-id, dus er is er precies één, en die landt op Dune omdat dat het boek is waar `05a` mee
getekend is. `05b` staat in de widgettests, tegen dezelfde layoutregel waar het scherm zelf op
gebouwd is.

## Wat er tegen golden 04 gebouwd is

`lib/screens/books/books_search_screen.dart` met `lib/screens/books/widgets/book_search_row.dart`
voor de drie rijsoorten, bereikbaar via het zoekglyph op Boeken-home en op Alle boeken. Dat glyph
opent nu Boeken zoeken in plaats van de bibliotheekbrede zoekpagina, want golden 04 begrenst hem tot
boeken: er staat geen Films-chip in de rij en de tabbalk eronder heeft Boeken actief.

**Presentatie en matching staan los.** `lib/books/book_search.dart` bevat het matchingcontract als
een eigen `BookSearchRanking`, geïnjecteerd in het scherm. Wat een resultaat matcht is daarmee te
vervangen zonder een widget aan te raken, en dat is nodig: ranking beweegt mee met echte metadata
(PS-14) en nog een keer als matching ooit naar de server gaat. `LocalBookSearchRanking` is eerlijk
over wat hij is, een substringzoeker over een plank die in het geheugen past.

Bewijs: `pleya_verify/scenarios/books.search.layout.yaml` groen op de vastgezette iPhone 15
Pro-simulator, plus tien widgettests in `test/screens/books_search_screen_test.dart` en dertien
eenheidstests in `test/books/book_search_test.dart`.

De vergelijking met `04a` legt het scherm binnen ongeveer twee punt op de golden: veld op 127,0
tegen 127,7, chiprij op 177,2 tegen 177,7, eerste sectiekop op 220,8 tegen 219,8, en de kop op 80,2
tegen 77,8.

Wat die vergelijking opleverde, en wat geen enkele test zag:

- **Het toetsenbord dekte twee van de drie secties af.** Het scherm nam de focus meteen, wat klopt
  voor iemand die komt typen, maar niet voor een veld dat al gevuld is. Nu neemt het de focus alleen
  bij een leeg veld. Dat is ook waarom het simulatorbeeld eerst alleen de Boeken-sectie liet zien.
- **`Dune` stond derde bij het zoeken op `dune`.** De ranking sorteerde alleen alfabetisch, dus
  `Children of Dune` won. Er is nu een band vóór het alfabet: eerst de titel die de zoekterm ís, dan
  de titels die ermee beginnen, dan de rest. De volgorde in de app is daarmee die van de golden.
- **Het zoekveld had een tweede, lichter oppervlak in zich.** Een donker `InputDecorationTheme` vult
  een veld standaard; `filled: false` haalt die laag weg.
- **De serie-cover tekende zijn titel over de stapelranden heen.** Op 44 punt vechten die om
  dezelfde pixels. De voorkant van een seriebeeld draagt geen letters meer.

Twee dingen die de gate ving en de golden niet:

- Een kaal `TextField` is hier niet toegestaan: `test/no_bare_text_field_test.dart` eist
  `FocusableTextField`, want dat is wat een veld met een tv-afstandsbediening laat werken.
- De runner weigerde eerst te compileren op symbolen die gewoon bestonden. Dat was een verouderde
  `pleya_verify/runner/.dart_tool`; opnieuw `dart pub get` loste het op.

Bewuste verschillen met het beeld:

- **Er is geen tabbalk, en dat geldt ook voor Alle boeken.** Golden 02 en golden 04 tekenen er
  allebei een, maar beide schermen worden op de profielnavigator gepusht en dekken `MainScreen`
  daarmee volledig af, tabbalk inbegrepen. Nagemeten op de bewijsbundels van allebei de scenario's.
  Het is geen fout in dit scherm maar een eigenschap van de navigatieschil, en het raakt een al
  goedgekeurd en gebouwd venster. Het hoort in een eigen ronde, niet in deze.
- **Het scenario typt de zoekterm niet, maar krijgt hem mee.** De iOS-driver heeft geen
  tekstinvoer (`typeText: no /v1/input/text endpoint exists yet`), dus zonder zaaien is er geen
  canonieke staat om op hardware te fotograferen. Bewezen is daarmee dat de drie secties op een
  echt toestel uitkomen waar de golden ze zet; niet bewezen is dat typen ze oplevert, en dat doen de
  widgettests wel. Zodra de driver tekstinvoer krijgt hoort dit scenario zelf te typen.
- **De covers zijn getekend en de auteursavatar is een monogram**, om dezelfde reden als bij de
  eerdere goldens.

## Wat er tegen golden 03 gebouwd is

`lib/screens/books/widgets/book_filter_sheet.dart` met `lib/books/book_filter.dart` eronder, geopend
door de Filters-pill op Alle boeken. De maten in `BookFilterSheetMetrics` zijn de gemeten maten van
de golden, en de sheet houdt de verhouding 600 op 852 aan in plaats van een vaste hoogte, zodat hij
op een korter toestel niet over de rand loopt.

De sheet gaat open op de dichtstbijzijnde navigator, niet op de root. De browse-UI hangt onder
`ProfileNavigationScope`, en een route daarboven verliest die scope; dat is de overlay-val uit
CLAUDE.md.

Bewijs: `pleya_verify/scenarios/books.filters.layout.yaml`, groen op de vastgezette iPhone 15
Pro-simulator, plus twaalf widgettests in `test/screens/book_filter_sheet_test.dart` en zestien
eenheidstests in `test/books/book_filter_test.dart`.

De vergelijking van het simulatorbeeld met `03a` legt de sheet op de golden binnen ongeveer één
punt: bovenrand van de sheet 252 tegen 252, kop op 289,2 tegen 289,2, de vijf groepsrijen op 334,7 /
378,0 / 421,5 / 465,2 / 508,8 tegen 334,5 / 378,3 / 421,2 / 465,3 / 508,3, de vier keuzes op 337,0 /
386,2 / 432,0 / 479,7 tegen 336,3 / 385,8 / 431,3 / 479,3, en de Toepassen-pill exact op 243,3 tot
372,3. De scheidingslijn staat één punt verder naar rechts dan in de golden.

Wat de vergelijking opleverde:

- **Een groepslabel stond bovenin zijn rij in plaats van in het midden.** Een `Stack` geeft zijn
  niet-gepositioneerde kinderen losse constraints, dus de rij van 43,5 hoog kreeg een label van één
  regel tekst tegen de bovenrand. Geen enkele test klaagde erover en op een screenshot zonder golden
  ernaast valt het niet op; het scheelde 11 punt. Opgelost met `StackFit.expand`.
- **De pill-rij op Alle boeken paste niet meer toen de badge erbij kwam.** Zichtbaar gemaakt door de
  testfont, waarin elk teken een vierkant em is, maar het probleem is echt: een langer sorteerlabel
  of een grotere tekstschaal loopt op een echt toestel net zo goed over. De rij scrollt nu
  horizontaal in plaats van zijn waarde af te knippen. Met Inter en deze twee pills scrollt hij
  niet.

Bewuste verschillen met het beeld:

- **De statusbalk is niet gedimd, en dat kan ook niet.** In de golden ligt de scrim over het hele
  frame, statusbalk inbegrepen; op iOS tekent het systeem die balk boven alles wat de app tekent. De
  pagina eronder is wel precies goed gedimd: 102 van 255 op de paginatitel in allebei.
- **De golden tekent onderaan geen home-indicator, het toestel wel.** De Toepassen-pill blijft er
  vrij van; het scenario controleert dat met `insideViewport`.
- **Negen genres in de golden, zeven in de app.** De golden toont een plank van 128 boeken, de
  fixture heeft er twaalf, en de rechterkolom komt uit de boeken zelf. Biografie en Thriller staan
  daarom niet in de lijst. Hetzelfde soort verschil als `128 boeken` tegenover `12 boeken` bij
  golden 02.
- **De verify-simulator draait de OLED-variant van `monoTheme`**, met een zwarte pagina in plaats
  van `#141414`. De sheet zelf klopt, want de books-schermen zetten sinds golden 01b de kleuren van
  de golden hard neer in plaats van themetokens te lezen. Dat is een bestaande keuze van 01b en 02,
  geen nieuwe.

## Wat er tegen golden 02 gebouwd is

`lib/screens/books/all_books_screen.dart`, bereikbaar via `Alle boeken ›` op Boeken-home. De
grid-maten zijn de gemeten maten: drie kolommen, 10 pt ertussen, 16 pt marge, covers 2:3. De pills
worden getekend en openen niets, want wat achter Filters zit is golden 03 en heeft geen goedkeuring.
De sorteerpill liegt niet: het raster is echt titel A–Z.

Bewijs: `pleya_verify/scenarios/books.all.layout.yaml`, groen op een iPhone 15 Pro-simulator.

Wat de vergelijking met de golden opleverde:

- De covertitels waren te groot en braken middenin een woord (`CHILDRE / N OF / DUNE`). De maat
  hing aan het motief, niet aan de lengte van de titel, dus `1984` en `Brave New World` kregen
  dezelfde 26 pt. Nu bepaalt de lengte de maat.
- De automation-node zat om een sliver en had daardoor geen bounds; een geometrie-assertie had niets
  te meten. De node zit nu per cel, zoals `library.grid.item` al deed.

Twee bewuste verschillen met het beeld:

- **De volgorde.** De golden toont een plank in comp-volgorde, de app sorteert titel A–Z zoals de
  pill zegt. Het beeld is een mockup, het label is het contract.
- **Het aantal.** De golden zegt `128 boeken`, de app telt de twaalf die de vaste set heeft.

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

Golden 03 gaat hetzelfde, met één verschil: `03c` is een detailuitsnede, dus de hoogte gaat als
vierde argument mee.

```
cd docs/assets/ebooks/northstar/src/03-filters
export NODE_PATH=/opt/homebrew/lib/node_modules:/opt/homebrew/lib/node_modules/@playwright/test/node_modules
node render.js filters.html ../../03a-filters-status.png status
node render.js filters.html ../../03b-filters-genre.png genre
node render.js filters.html ../../03c-filters-controls.png controls 620
```

Op 3 september 2026 leverden twee opeenvolgende runs identieke bestanden op (md5 `c8b57185…`,
`3c6bacaa…` en `39e74866…`).

Golden 04 gaat net zo, met `530` als hoogte voor het detailframe.

```
cd docs/assets/ebooks/northstar/src/04-books-search
export NODE_PATH=/opt/homebrew/lib/node_modules:/opt/homebrew/lib/node_modules/@playwright/test/node_modules
node render.js search.html ../../04a-books-search.png all
node render.js search.html ../../04b-books-search-books.png books
node render.js search.html ../../04c-books-search-rowtypes.png rowtypes 530
```

Op 4 september 2026 leverden twee opeenvolgende runs identieke bestanden op (md5 `3ade063c…`,
`db01b97b…` en `ea2e2487…`).

Golden 05 gaat net zo, met `560` als hoogte voor het detailframe.

```
cd docs/assets/ebooks/northstar/src/05-books-detail
export NODE_PATH=/opt/homebrew/lib/node_modules:/opt/homebrew/lib/node_modules/@playwright/test/node_modules
node render.js detail.html ../../05a-book-detail.png reading
node render.js detail.html ../../05b-book-detail-unread.png unread
node render.js detail.html ../../05c-book-detail-actions.png actions 560
```

Op 4 september 2026 leverden twee opeenvolgende runs identieke bestanden op (md5 `e113ae65…`,
`48cd7f26…` en `53199612…`).

Golden 06 gaat net zo, met `645` als hoogte voor het detailframe. Die hoogte is niet geraden: de
pagina rekent hem zelf uit met `window.specHeight()`, zodat het frame precies om zijn eigen inhoud
sluit.

```
cd docs/assets/ebooks/northstar/src/06-books-toc
export NODE_PATH=/opt/homebrew/lib/node_modules:/opt/homebrew/lib/node_modules/@playwright/test/node_modules
node render.js toc.html ../../06a-books-toc.png reading
node render.js toc.html ../../06b-books-toc-collapsed.png collapsed
node render.js toc.html ../../06c-books-toc-rowtypes.png rowtypes 645
```

Op 4 september 2026 leverden twee opeenvolgende runs identieke bestanden op (md5 `3c9152e8…`,
`6dbfe719…` en `68c46397…`). Dat zijn de goedgekeurde frames; de md5's van voordracht A en van de
eerste render van revisie B staan hier bewust niet, want alleen de goedgekeurde staat is contract.

Golden 07 gaat net zo, met `826` als hoogte voor het themaframe; ook die hoogte komt uit
`window.specHeight()` en is niet geraden.

```
cd docs/assets/ebooks/northstar/src/07-books-reader
export NODE_PATH=/opt/homebrew/lib/node_modules:/opt/homebrew/lib/node_modules/@playwright/test/node_modules
node render.js reader.html ../../07a-books-reader.png reading
node render.js reader.html ../../07b-books-reader-immersive.png immersive
node render.js reader.html ../../07c-books-reader-themes.png themes 826
```

Op 4 september 2026 leverden twee opeenvolgende runs van revisie B identieke bestanden op (md5
`ae365ae9…`, `3784195f…` en `8a9e7a24…`).

Golden 08 gaat net zo, met `617` als hoogte voor het bedieningsframe.

```
cd docs/assets/ebooks/northstar/src/08-reader-settings
export NODE_PATH=/opt/homebrew/lib/node_modules:/opt/homebrew/lib/node_modules/@playwright/test/node_modules
node render.js settings.html ../../08a-reader-settings.png settings
node render.js settings.html ../../08b-reader-large-type.png large
node render.js settings.html ../../08c-reader-settings-controls.png controls 617
```

Twee opeenvolgende runs leverden identieke bestanden op (md5 `9d2cd994…`, `3201b7be…` en
`4d740908…`). Dit is de eerste golden van de set waarvan de tekstkolom
een letter uit de repository laadt in plaats van er een van het besturingssysteem te lenen, dus de
render is nu ook buiten macOS reproduceerbaar. De md5's van voordracht A staan hier niet meer; die
frames leunden op de systeem-Georgia en zijn daarmee toch niet na te maken.

**Elke golden van deze set reproduceert nu vanuit elke clone.** Golden 07 was de uitzondering zolang
zijn tekstkolom `Georgia` aan het besturingssysteem vroeg; revisie B laadt Literata uit
`assets/fonts` met een relatief pad, net als Inter, en pint daarbij `'opsz' 18, 'wght' 400`, want een
variabele letter waarvan de assen niet vastliggen is zelf een bron van drift.

`render.js` opent Chromium op 393×852 met `deviceScaleFactor: 3` en wacht op `document.fonts.ready`.
Op 3 september 2026 leverde deze route vanuit de repo-bron byte-identieke PNG's op (md5
`7a7211c4…` voor 00a, `f9c034d0…` voor 00b); een afwijking na een Chromium- of fontwissel is een
signaal om de golden opnieuw te laten beoordelen, niet om de PNG stil te overschrijven.
De maten van de tabbalk (baltop 768 pt, icoonmidden 788 pt, label 11 pt op 806 pt, home-indicator
op 839 pt) zijn gemeten op `01-series-landing.png` uit de iOS Unified-set.
