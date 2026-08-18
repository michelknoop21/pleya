# Roadmap deviation proposal: drie gaten en artwork binnen PS-1 tot PS-4

**Status:** goedgekeurd, 18 augustus 2026
**Auteur:** Michel Knoop
**Betreft:** [docs/pleya-server-architecture.md](pleya-server-architecture.md) hoofdstuk 23,
[docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md](PLEYA-SERVER-REPLACEMENT-MATRIX.md) hoofdstuk 7

Dit voorstel volgt de zes onderdelen uit
[hoofdstuk 23.1](pleya-server-architecture.md#231-de-roadmap-is-een-contract). Het is vastgelegd
voordat er een regel protocol is opgeschreven.

---

## 1. De oorspronkelijke aanname

De roadmap gaat ervan uit dat PS-1 tot en met PS-4 samen een bruikbare mijlpaal opleveren: een
gebruiker kan bladeren, zoeken, een film starten en zijn kijkpositie terugvinden. De replacement
matrix is daarnaast een lijst bevindingen, waarvan de gaten later een fase krijgen.

Achter beide zit dezelfde aanname: dat de capabilities zonder fase buiten dit venster vallen, en dat
het venster dus intern compleet is.

## 2. De nieuwe bevinding

Van de twaalf gegroepeerde gaten uit hoofdstuk 7 van de matrix vallen er drie binnen PS-1 tot PS-4,
en de bibliotheek waarop dit gebouwd wordt maakt twee daarvan onontkoombaar.

De testbibliotheek op `/volume1/Intern_PlexMedia` bevat 2601 videobestanden en daarnaast **5578 losse
`.srt`-bestanden** en 2923 `.jpg`-bestanden. Dat zijn geen uitzonderingen maar de normale vorm van
deze collectie.

| Gat | Hoort volgens de matrix in | Wat er zonder gebeurt |
| --- | --- | --- |
| **G5** externe ondertitels als los bestand | PS-4 | geen enkele film toont ondertitels |
| **G11** edities | PS-2 | een Director's Cut en de bioscoopversie staan als twee identieke titels |
| **G9** home-rijen, bouwstenen | PS-3 | het homescherm is leeg bij een Pleya Server-verbinding |

Daarbovenop een vierde bevinding die niet uit de matrix komt maar uit het architectuurdocument zelf.
[Hoofdstuk 12.2](pleya-server-architecture.md#122-welk-oppervlak-wanneer-wordt-gespecificeerd) noemt
artwork niet als PS-1-oppervlak, en metadata staat in PS-7. PS-3 tekent wel een bladerscherm. Er is
dus geen fase die de weg van een poster naar het scherm dekt, terwijl er 2923 posters op schijf
staan.

## 3. Waarom de huidige roadmap daardoor niet meer klopt

Het stopcriterium van PS-4 is dat een huishouden een avond films kan kijken vanaf Pleya Server. Een
film zonder ondertitels haalt dat criterium niet in een huishouden waar bij vrijwel elk bestand een
ondertitel ligt. Het criterium is dan formeel gehaald en feitelijk niet, en dat is precies het
onderscheid dat
[hoofdstuk 4 van de matrix](PLEYA-SERVER-REPLACEMENT-MATRIX.md#4-statussen) tussen technisch gereed
en productgereed maakt.

Hetzelfde geldt voor de andere twee, zij het minder hard. Een catalogus die dubbele titels toont is
niet af, en een leeg homescherm is de eerste indruk van het product.

Artwork is een ander soort probleem. Het is geen gat in de matrix maar een gat tussen twee
hoofdstukken: het oppervlak wordt nergens gespecificeerd en de inhoud komt pas in PS-7. Wachten tot
PS-7 zou betekenen dat het endpoint dan alsnog aan v1 wordt toegevoegd, wat mag, maar het betekent
ook dat PS-3 een tekstlijst oplevert en dat de vorm van het endpoint ontworpen wordt zonder dat er
ooit een client op heeft gedraaid.

## 4. De concrete voorgestelde wijziging

**G5 gaat naar PS-4.** De scanner registreert ondertitelbestanden naast hun media, en het protocol
levert ze als losse sporen naast de videostream. Alleen bestanden die er al liggen; zoeken en
downloaden van ondertitels blijft buiten scope.

**G11 gaat naar PS-2.** De scanner leest `{edition-...}` uit de bestandsnaam en zet het op de versie.
Alleen die conventie, geen editie-detectie uit metadata.

**G9 gaat naar PS-3, uitsluitend de bouwstenen.** De server levert recent toegevoegd, verder kijken
en volgende aflevering. De bestaande aanbevelingsmotor in de client bouwt daar de rijen mee. Elke
vorm van verrijking blijft PS-7.

**Artwork krijgt zijn vorm in PS-1 en zijn inhoud in PS-2.** PS-1 legt
`GET /pleya/v1/artwork/{id}` vast met een maatparameter en een gedocumenteerde 404 zolang er geen
afbeelding is. PS-2 serveert uitsluitend afbeeldingen die de scanner al op schijf tegenkomt.
Providers, kandidaten, curatie en handmatige correctie blijven onaangeroerd in PS-7.

Dit is geen uitzondering op acceptatiecriterium 6 van PS-1 maar een toepassing ervan: de regel is dat
er geen endpoint in mag waar PS-2 tot en met PS-4 niet om vraagt, en PS-3 vraagt hierom.

## 5. De gevolgen voor latere fasen

PS-7 verliest niets. Het krijgt providers, kandidaten, de driestapsmatch, curatie en handmatige
correctie, precies zoals beschreven. Wat er verandert is dat het endpoint waarop dat straks landt al
bestaat en al gebruikt is, wat het risico op een breaking wijziging in v1 verkleint in plaats van
vergroot.

PS-9 verliest niets. G2 kijkgeschiedenis en G3 favorieten en waarderingen blijven daar liggen.

De negen overige gaten uit hoofdstuk 7 van de matrix bewegen niet en houden hun status `Roadmap gap`.
Dit voorstel raakt G1, G2, G3, G4, G6, G7, G8, G10 en G12 niet.

De matrix zelf wordt in deze fase niet gewijzigd. G5, G9 en G11 krijgen hun Phase ID wanneer de fase
die hen draagt wordt afgesloten, volgens onderhoudsregel 3 uit hoofdstuk 10 van dat document.

## 6. Welke scope hierdoor vervalt

Geen. Er wordt scope toegevoegd aan drie fasen en er verdwijnt nergens iets.

Wat wel expliciet begrensd is: G5 dekt uitsluitend bestanden die al op schijf liggen, G11 uitsluitend
de naamgevingsconventie, G9 uitsluitend de bouwstenen, en artwork uitsluitend wat de scanner
tegenkomt. Elk van de vier heeft een grotere vorm die in een latere fase hoort, en die grotere vorm
wordt hier niet vooruitgebouwd.
