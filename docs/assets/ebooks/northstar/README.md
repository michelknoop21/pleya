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
| `05a-book-detail.png` | Boekdetail, canonieke staat op Dune met leesvoortgang | proposed | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `05b-book-detail-unread.png` | Hetzelfde scherm voor een boek zonder voortgang en zonder reeks | proposed | iPhone 15 Pro, 1179×2556 | DEC-094, DEC-090 | 2026-09-04 | zie onder |
| `05c-book-detail-actions.png` | Detail: het actieblok in beide staten | proposed | detailuitsnede, 1179×1680 | DEC-094, DEC-090 | 2026-09-04 | zie onder |

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

## Golden 05, Boekdetail (proposed)

De pagina achter een cover, waar een boek zichzelf voorstelt en het lezen begint. Inhoud van paneel 5
van de comp, uitvoering van `06-film-detail.png` uit de iOS Unified-set. Drie frames, samen één
scherm: `05a` de canonieke staat op Dune, halverwege gelezen, `05b` dezelfde pagina voor een boek dat
nog niet begonnen is en niet in een reeks staat, `05c` een detailuitsnede van het actieblok in beide
staten zodat het verschil zonder de rest van het scherm te beoordelen is.

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
  vervangen, wordt hier niet beslist en mag er ook niet stilzwijgend uit worden afgelezen. Dat hoort
  bij de downloadfase, dezelfde die paneel 10 van de comp bedient. Let op bij het opschrijven van een
  fase-ID: de goedgekeurde serverroadmap loopt tot PS-13, en de e-booksfasen die daarboven genoemd
  worden (`PS-14` in golden 04, en de downloadfase hier) staan nog nergens als vastgelegde Phase ID.
- **Wat er onder de vouw staat.** De pagina scrollt, want de beschrijving is afgekapt. Of daar de
  volledige beschrijving, de reeks of aanbevelingen op volgen is niet vastgelegd.

**Bewuste verschillen met het beeld die geen goedkeuring nodig hebben.** De covers zijn getekend in
CSS en de reekstelling in de comp (`Dune 6 boeken`) staat hier niet, om dezelfde redenen als bij de
eerdere goldens. De tabbalk staat in beeld omdat de comp hem tekent; net als bij golden 02 en 04
dekt het echte scherm `MainScreen` af zodra het op de profielnavigator gepusht wordt, en die
kanttekening verandert hier niet.

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

`render.js` opent Chromium op 393×852 met `deviceScaleFactor: 3` en wacht op `document.fonts.ready`.
Op 3 september 2026 leverde deze route vanuit de repo-bron byte-identieke PNG's op (md5
`7a7211c4…` voor 00a, `f9c034d0…` voor 00b); een afwijking na een Chromium- of fontwissel is een
signaal om de golden opnieuw te laten beoordelen, niet om de PNG stil te overschrijven.
De maten van de tabbalk (baltop 768 pt, icoonmidden 788 pt, label 11 pt op 806 pt, home-indicator
op 839 pt) zijn gemeten op `01-series-landing.png` uit de iOS Unified-set.
