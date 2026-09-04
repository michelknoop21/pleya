# Roadmap deviation proposal: e-books als contentdomein in Pleya Server

**Status:** goedgekeurd 3 september 2026 met bindende correcties, vastgelegd als
[DEC-107](DECISIONS.md)
**Auteur:** Michel Knoop
**Betreft:** [docs/pleya-server-architecture.md](pleya-server-architecture.md) hoofdstuk 1.1, 23.1 en
23.2, [docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md](PLEYA-SERVER-REPLACEMENT-MATRIX.md) hoofdstuk 3 en
10, [docs/pleya-protocol/v1/openapi.yaml](pleya-protocol/v1/openapi.yaml)

Dit voorstel volgt de zes onderdelen uit
[hoofdstuk 23.1](pleya-server-architecture.md#231-de-roadmap-is-een-contract). Het is geschreven
voordat er een regel e-bookservercode, een migratie of een protocolwijziging bestaat, en het is
geen impliciet goedgekeurd implementatieplan. Wat hier staat is één vraag met een onderbouwd
antwoord: horen e-books bij het einddoel van Pleya Server, en zo ja, waar in de architectuur.

De lopende ontwikkelfase is PS-9. Dit voorstel wijzigt daar niets aan en vraagt geen vervroegde
uitvoering. De goedkeuring van dit voorstel voegt PS-14 en PS-15 aan de roadmap toe en geeft ze
**niet** vrij: het vrijgeven van PS-14 is een apart besluit.

De onderdelen 4.1, 4.2, 4.5, 5 en 7 dragen de correcties die bij de goedkeuring bindend zijn
gemaakt. Waar dit document eerder een keuze openliet, staat nu het besluit.

---

## 1. De oorspronkelijke aanname

De architectuurbaseline gaat er stilzwijgend van uit dat elke bibliotheek in Pleya Server
audiovisueel is. Dat staat nergens als regel, en juist daarom werkt het door tot in de constraints:

- `libraries.kind` accepteert `movies` en `shows`
  ([`0002_catalog.sql:20`](../pleya_server/internal/migrate/sql/0002_catalog.sql));
- `media_items.kind` accepteert `movie`, `show`, `season`, `episode`, met constraints die de keten
  show → season → episode modelleren (`0002_catalog.sql:48`);
- `media_versions` vereist `container` en `duration_ms`, `media_streams` kent `video`, `audio` en
  `subtitle` (`0002_catalog.sql:200`);
- de scanner leidt uit `lib.Kind` af welke naamparser en welk catalogusmodel gelden
  ([`scanner.go:597`](../pleya_server/internal/scanner/scanner.go)), met ffprobe als vaste
  analysestap ervoor.

De tweede aanname zit in de replacement matrix. Die beantwoordt de vraag wat er moet bestaan voordat
een gebruiker Plex kan uitschakelen, en deelt iedere Plex-verantwoordelijkheid in bij bestemming A,
B of C (matrix hoofdstuk 3). De aanname daaronder is dat de productscope van Pleya Server samenvalt
met wat Plex vandaag doet, plus wat de app er al omheen heeft.

Beide aannames waren tot 3 september 2026 correct, want er was niets in Pleya dat ze weersprak.

## 2. De nieuwe bevinding

**Er ligt sinds 3 september 2026 een goedgekeurd clientbesluit dat een servercapability veronderstelt
die geen Phase ID heeft.** Op `feat/ebooks` staat DEC-102 ("Mobiele primaire navigatie landt
vervroegd vanuit ebooks, als capability-gedreven vijfslots-balk") op `accepted`, met golden 00
(`docs/assets/ebooks/northstar/00-mobile-nav-books.png`) expliciet goedgekeurd. Dat besluit maakt de
vierde tabslot content- en capability-gedreven, en de eerste kandidaat is:

> **Boeken**, wanneer het actieve profiel een toegankelijke e-bookbibliotheek heeft (minimaal één
> boek zichtbaar voor dat profiel).

Bij dat besluit hoort een bindende inhoudelijke bron: de twaalfpanelen-comp
`ebooks-northstar-comp.png`, met Boeken-home, alle boeken, filters, zoeken, boekdetail,
inhoudsopgave, reader in drie thema's, readerinstellingen, zoeken in boek, downloads,
aanbevelingen en boekeninstellingen.

Aan de serverkant bestaat daar niets voor, en dat is geen achterstand maar een leegte:

- `epub`, `ebook` en `boeken` komen niet voor in `pleya-server-architecture.md` en niet in
  `PLEYA-SERVER-REPLACEMENT-MATRIX.md`;
- geen enkele fase, ook geen letterfase, draagt boeken;
- er is geen matrixregel, dus voor de Plex-off gate bestaat de functie niet (matrix
  onderhoudsregel 2: "Een functie zonder regel in deze matrix bestaat voor de gate niet").

**Plex is hier geen bron.** Plex Media Server levert geen e-books. De driedeling A/B/C uit
matrixhoofdstuk 3 is daarmee niet toepasbaar: er is geen Plex-verantwoordelijkheid om over te nemen,
bewust anders op te lossen of buiten scope te verklaren. Dit is een uitbreiding van de productscope
zelf, en die hangt boven de architectuurbaseline in plaats van eronder.

**Het protocol laat een nieuwe bibliotheeksoort wél toe, en zegt dat met zoveel woorden.**
`LibraryKind` in `openapi.yaml:1116-1122` draagt `x-unknown-safe: true` met de beschrijving:

> Er mag binnen v1 een soort bij komen. Een client die de soort niet kent toont de bibliotheek niet,
> en faalt niet.

`books` toevoegen is dus geen schending van compatibiliteitsregel 6, maar precies het mechanisme dat
regel 6 beschrijft. Wat wel geldt: het contract is bevroren zolang de lopende fase loopt, dus de
YAML gaat niet open zonder venster en zonder DEC.

**De unknown-safe belofte wordt in de Flutter-client aan de parsekant nagekomen en aan de
presentatiekant niet.** `PleyaLibraryKind.tryParse` geeft `null` bij een onbekende soort
(`lib/models/pleya_server/pleya_wire.dart:55-60`), met de doc-comment "the caller hides that library
rather than failing". Die caller bestaat niet: `libraryKindOf` vertaalt `null` naar
`MediaKind.unknown` (`lib/services/pleya_server_mappers.dart:61-65`), en `MediaKind.unknown` is een
geldige bibliotheeksoort die elders in de codebase juist getoond wordt, want Jellyfin gebruikt hem
voor gemengde bibliotheken (`lib/services/jellyfin_mappers.dart:300`). Een `books`-bibliotheek zou
in een bestaande build dus zichtbaar worden als gemengde bibliotheek, en leeg blijken.

> **Correctie van 3 september 2026, na verificatie. De alinea hierboven is onjuist en blijft staan
> omdat er een goedgekeurd besluit op rust.** Die caller bestaat wél. `fetchLibraries` filtert
> `library.kind != null` vóór de mapper
> (`lib/services/pleya_server_client/parts/browse.dart:36-51`), met de contractbelofte als comment
> erboven. Die code staat sinds `8342a8b` (19 augustus 2026) op `main` en zit dus in uitgeleverde
> builds. `PleyaServerMappers.library` heeft precies die ene aanroeper in productiecode, en
> `pleya_server_api_cache.dart` cachet uitsluitend items en geen bibliotheken, dus er is geen tweede
> route naar de mapper. `test/pleya_server/pleya_server_browse_test.dart:44` legt het gedrag al
> vast, met de fictieve soort `music`. De tak `null => MediaKind.unknown` in
> `pleya_server_mappers.dart:61-65` is daarmee onbereikbaar via de enige route ernaartoe: hij is
> dode code op de Pleya Server-route, geen defect dat zich manifesteert. Wat over `MediaKind.unknown`
> in de Jellyfin-code staat klopt, maar een Pleya Server-bibliotheek komt daar nooit met een
> onbekende soort aan.
>
> De bewering was al onjuist op het moment dat [DEC-107](DECISIONS.md) werd geschreven. De audit
> eronder las de mapper en niet de aanroeper.

**De serverkant faalt vandaag op twee verschillende manieren voor een onbekende soort, en één ervan
is stil.** De scanner weigert expliciet: `default: onbekende bibliotheeksoort %q`
(`scanner.go:697`). Het items-endpoint doet het omgekeerde: `kinds := []string{"movie"}`, en alleen
bij `lib.Kind == "shows"` wordt dat `show` (`internal/api/handlers_library.go:87-90`). Elke soort die
geen `shows` is, wordt daar als `movies` behandeld. Een `books`-bibliotheek zou een lege filmlijst
opleveren zonder fout.

**De rechtenlaag is wel al generiek.** `MayAccess` en `VisibleLibraries`
(`internal/catalog/permissions.go:65,93`) werken op `libraries.id` en `library_permissions`, met de
ladder view < download < manage uit DEC-098 §4 en de rolomzeiling voor owner en admin uit §2. Er zit
niets audiovisueels in.

## 3. Waarom de huidige roadmap daardoor niet meer klopt

**Er is een goedgekeurd clientbesluit zonder serverdrager.** DEC-102 op `feat/ebooks` is `accepted`,
niet `proposed`. De navigatiepolicy die eruit volgt vraagt aan het actieve profiel of het een
toegankelijke e-bookbibliotheek heeft. Zonder besluit hierover is die vraag onbeantwoordbaar, en
wordt slot 4 in de praktijk altijd door Live TV, Watchlist of Downloads gevuld. Dan is de
goedgekeurde golden een plaatje van iets dat niet bestaat.

**De matrix kan de vraag "hoort dit bij het eindproduct" voor boeken niet beantwoorden.** CLAUDE.md
schrijft voor om bij twijfel tegen de matrix te toetsen en niet tegen eigen inschatting. Die toets
levert nu geen uitkomst op, want er is geen regel en de driedeling past niet. Een werkregel die op
dit onderwerp geen antwoord geeft, is een gat in de baseline en geen vrijbrief om zelf te kiezen.

**"Niet in deze fase" is hier niet het geval, en dat is precies het probleem.** De regel uit
hoofdstuk 1.1 beschermt functies die nog geen Phase ID hebben maar wel bij het eindproduct horen. Of
boeken bij het eindproduct horen is nooit beslist. Zolang dat zo blijft, is elke serverkeuze over
boeken een productbesluit vermomd als implementatiedetail, en dat is de vorm van drift die 23.1
verbiedt.

**De protocolvriezing hangt aan de lopende fase, dus het venster moet expliciet bij een fase horen.**
Het PS-9-venster is open voor precies de zeven wijzigingen uit DEC-101 en sluit daarna. Een achtste
wijziging erbij schuiven omdat het zo uitkomt is exact wat de vriezing tegenhoudt.

## 4. De concrete voorgestelde wijziging

### 4.1 Het productbesluit eerst

> **E-books worden een contentdomein van Pleya Server, naast film en serie, met een eigen
> domeinmodel op dezelfde bibliotheek-, gebruikers- en rechtenfundering.**

**Besloten op 3 september 2026.** Dit is een productscope-uitbreiding, geen tijdelijke
clientfeature en geen gat in de Plex-vervanging. Alles hieronder is er de uitwerking van.

Wat het besluit uitdrukkelijk niet zegt: dat Pleya een Calibre-vervanger wordt, dat er
boekmetadataproviders komen, of dat de bibliotheek buiten EPUB iets anders leest. Die drie zijn
latere vragen met eigen besluiten.

### 4.2 Twee fasen, en een derde die benoemd wordt maar niet vrijgegeven

**PS-14, e-bookcatalogus en inhoud (server).**

| Veld | Inhoud |
| --- | --- |
| Phase ID | PS-14 |
| Doel | een `books`-bibliotheek wordt gescand, gecatalogiseerd en via het protocol ontsloten, inclusief cover en het EPUB-bestand zelf |
| Bijdrage aan einddoel | zonder servercatalogus is er geen bron waar een lezer boeken vandaan haalt |
| Afhankelijkheden | PS-2 (catalogus, scanner, storage locations), PS-9 (gebruikers, sessies, bibliotheekrechten) |
| Eerstvolgende fase | PS-15 |

In scope: `books` als bibliotheeksoort in database, configparser en protocol; het e-bookdomeinmodel;
een EPUB-analyser; de scannerdispatch per bibliotheeksoort; een eigen protocolresource voor lijst,
detail, cover en bestand; autorisatie via de bestaande `MayAccess`.

Buiten scope: leesvoortgang, bladwijzers, annotaties, de reader zelf, offline boeken, aanbevelingen,
boekmetadata uit externe providers, andere formaten dan EPUB, boeken in `/search` en in de hubs,
en beheer van de bibliotheek via een scherm.

**PS-15, de reader en leesvoortgang (client plus de server die hij nodig heeft).**

| Veld | Inhoud |
| --- | --- |
| Phase ID | PS-15 |
| Doel | een boek is in de mobiele app te lezen, en de leespositie reist mee tussen toestellen van dezelfde gebruiker |
| Afhankelijkheden | PS-14, DEC-102 op `feat/ebooks` |
| Eerstvolgende fase | PS-16, niet vrijgegeven |

Leesvoortgang zit bewust in PS-15 en niet in PS-14. De vorm van een leespositie volgt uit de
readerengine die de app gebruikt: een locator die naar een spine-item plus een offset of een CFI
wijst, is alleen te ontwerpen als bekend is wat de reader kan produceren en terugvinden. Dat veld in
PS-14 vastleggen zou een datamodel afdwingen met de kennis die PS-15 nog moet opleveren, en dat is
letterlijk de regel uit 23.1 die de `transcode_workers`-tabel uit v1 hield.

**PS-16, offline e-books en bladwijzers.** Benoemd en begrensd, niet vrijgegeven en niet
ontworpen. De scope wordt pas uitgewerkt na PS-15, maar het reservaat ligt vast, zodat "PS-16
bestaat" later niet betekent dat niemand weet wat hij moest opleveren:

> **Gereserveerd:** lokale EPUB-downloads met offline lezen, en bladwijzers die tussen toestellen
> van dezelfde gebruiker synchroniseren.
> **Niet impliciet meegenomen:** PDF of een ander formaat dan EPUB, DRM, annotaties en markeringen,
> en elke vorm van winkel of aankoop.

De twee kanten van scope discipline gelden ook hier: niet vooruitbouwen, en niet schrappen omdat het
nu niet nodig is. Wat buiten het reservaat valt, is daarmee niet uit het eindproduct geschreven; het
heeft alleen geen fase, en krijgt er pas een via een eigen besluit.

### 4.3 Plaats in de afhankelijkheidsgraaf

De graaf uit 23.2 krijgt er twee knopen bij, en geen nieuwe pijl naar een bestaande fase:

```
  P2["2. Catalogus (Go)"]  --> P14["14. E-bookcatalogus"]
  P9["9. Users + rechten"] --> P14
  P14 --> P15["15. Reader + leesvoortgang"]
```

PS-14 hangt aan PS-2 en PS-9, allebei fasen waarvan de afhankelijkheden gesloten zijn of die de
lopende fase zijn. PS-14 voegt geen afhankelijkheid toe aan PS-5, PS-6, PS-7, PS-8, PS-10, PS-11A of
PS-12, en verandert de vastgelegde doorloop (PS-5, PS-9, PS-11A, daarna PS-6 tot en met PS-8) niet.
Waar PS-14 en PS-15 in de tijd landen is een aparte keuze en geen onderdeel van dit voorstel.

**PS-11A is geen afhankelijkheid.** Bibliotheken ontstaan vandaag uit `PLEYA_SERVER_LIBRARIES` plus
een herstart, en dat mechanisme werkt voor een derde soort net zo goed als voor de eerste twee:

```
films=movies:/media/Films;series=shows:/media/Series;boeken=books:/media/Books
```

PS-11A wachten op zou PS-14 laten hangen aan een fase die hij niet nodig heeft, en dat is een
kunstmatige afhankelijkheid. Omgekeerd geldt wel iets: PS-11A moet ná dit voorstel drie soorten
kennen in plaats van twee, en dat staat in onderdeel 5.

### 4.4 Protocolimpact

Alle vier de voorgestelde contractwijzigingen zijn hieronder getoetst aan de zes regels uit
[hoofdstuk 12.3](pleya-server-architecture.md#123-versionering-en-compatibiliteitsregels).

| # | Wijziging | Regel 1 | Regel 2 | Regel 3 | Regel 4 | Regel 5 | Regel 6 | Oordeel |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `LibraryKind` krijgt `books` | n.v.t. | niets hernoemd of weg | betekenis `kind` ongewijzigd | geen aanvraagveld | geen aanvraagbody | veld is `x-unknown-safe: true` | toegestaan |
| 2 | `capabilities.ebooks` in `/info` | nieuw optioneel antwoordveld | n.v.t. | n.v.t. | n.v.t. | n.v.t. | geen enum | toegestaan |
| 3 | Eigen resource `/pleya/v1/ebooks/...` | additieve resource | n.v.t. | n.v.t. | geen verplicht veld in bestaande aanvraag | nieuwe body, eigen contract | eigen enums, per veld te markeren | toegestaan |
| 4 | `ItemKind` krijgt `book` | n.v.t. | n.v.t. | n.v.t. | n.v.t. | n.v.t. | zou mogen, maar wordt **niet** voorgesteld | afgewezen, zie 6 |

Wijziging 2 is de haak die DEC-102 nodig heeft: de client leest `capabilities.ebooks` en niet
`feature_level`, conform de regel dat capabilities altijd leidend zijn. Volgens correctie 7 uit het
masterplan onderhandelen additieve resources via `capabilities` en gaat `feature_level` daar niet
van omhoog; dit voorstel bumpt hem dus niet.

**Het venster, en de poort ervoor.** PS-14 heeft een eigen protocolvenster nodig met een eigen DEC
eronder, te openen bij de uitvoering van PS-14 en te sluiten zodra `scripts/check_protocol.sh` daarna
slaagt. Dit voorstel opent dat venster niet en raakt `openapi.yaml` niet aan.

Aan het openen van dat venster hangt een harde voorwaarde, bindend gemaakt bij de goedkeuring:

> **Een pre-books client mag een `books`-bibliotheek nooit presenteren als lege
> movie-bibliotheek of als zichtbare unknown-bibliotheek. Vóór het openen van het protocolvenster
> moet aantoonbaar vaststaan hoe bestaande clients een nieuwe unknown-safe `LibraryKind`
> daadwerkelijk behandelen, niet alleen hoe het schema zegt dat ze hem zouden moeten behandelen.**

`x-unknown-safe: true` bewijst compatibiliteit op de lijn. Het bewijst niet dat de client die
compatibiliteit ook uitvoert, en de bevinding in onderdeel 2 laat zien dat hij dat vandaag niet doet.
Dit is daarmee geen acceptatiecriterium dat aan het eind van PS-14 gehaald wordt, maar een poort die
vóór de eerste protocolwijziging dicht staat.

> **Correctie van 3 september 2026, na verificatie.** De halve zin "en de bevinding in onderdeel 2
> laat zien dat hij dat vandaag niet doet" is onjuist; zie de correctie in onderdeel 2. Het
> onderscheid tussen wat het schema belooft en wat een uitgeleverde build doet blijft staan, en de
> poort hierboven daarmee ook. Wat omdraait is de verwachte uitkomst: statisch gelezen verbergt een
> uitgeleverde app een `books`-bibliotheek al, dus de meting bevestigt waarschijnlijk een gesloten
> poort in plaats van een defect bloot te leggen.

**Wat intern mag blijven.** Het volledige e-bookdomeinmodel (publicaties, bestanden, bijdragers,
onderwerpen) is databasevorm en hoort niet in het contract. Alleen de velden die een client
werkelijk toont of nodig heeft komen op de lijn, en welke dat zijn is een ontwerpvraag voor PS-14
zelf, niet iets om hier alvast dicht te timmeren.

**Waarom een eigen namespace en geen `/items`.** De wire-`Item` draagt vandaag `versions`,
`streams`, `duration_ms` en `user_state.position_ms`. Een boek vult daar niets van in. Een resource
waarvan de helft van de velden per definitie leeg is bij een deelverzameling van de antwoorden, is
een veld waarvan de betekenis afhangt van een ander veld, en dat is de stilste vorm van breken uit
regel 3. Of de vorm van de e-bookresource daarnaast trekken van `Item` mag overnemen (paginering,
`Id`, `Timestamp`, artworkverwijzing) is een PS-14-ontwerpvraag; hergebruik van componenten is iets
anders dan hergebruik van de resource.

### 4.5 De mobiele productregel

> **iOS en iPadOS tonen de boekenfunctie. tvOS, macOS en desktop tonen hem niet. Dit is
> clientgedrag en geen beveiligingsgrens. De server autoriseert uitsluitend op gebruiker en
> bibliotheek, via het bestaande `MayAccess`/`library_permissions`-model.**

De rolverdeling erachter, en dit is de formulering die geldt boven elke andere in dit document:

> **De server levert feiten, de client beslist over presentatie.** De server zegt welke
> bibliotheken bestaan, van welke soort ze zijn, en of deze gebruiker erbij mag, via het gewone
> autorisatiemodel. Of daaruit een Boeken-bestemming volgt, beslist de client op basis van zijn
> platform en van wat hij ziet. De server bepaalt nooit of slot 4 Boeken wordt.

Concreet: op iOS en iPadOS leidt minstens één zichtbare `books`-bibliotheek tot
`BooksLibraryProvider.available` en wint Boeken de dynamische vierde slot; op tvOS levert dezelfde
gebruiker met dezelfde rechten dezelfde bibliotheken op, en kiest de client daar productmatig geen
Boeken-bestemming. Dat sluit aan op DEC-102 punt 5 (e) op `feat/ebooks`, dat tvOS en macOS al buiten
de vijfslots-balk houdt, en het vraagt geen enkele servercode.

Er komt **geen** zelfgerapporteerd platform- of readerveld aan login of `sessions`. Een client die
zijn eigen platform opgeeft, kan dat platform ook opgeven zonder het te zijn: zo'n veld zou een
grens suggereren die er niet is, en het zou de indruk wekken dat de vraag "mag dit toestel bij
boeken" beantwoord is terwijl alleen "welk toestel zegt het te zijn" beantwoord is.

Wat dit besluit expliciet openlaat: dezelfde gebruiker heeft op een tvOS-sessie dezelfde
bibliotheekrechten als op zijn iPhone, en kan de e-bookendpoints dus aanroepen. Voor de
productbelofte is dat geen probleem, want er is geen tvOS-reader die dat doet. Ontstaat later de
eis dat een gebruiker op het ene toestel wel en op het andere niet bij een bibliotheek mag, dan is
dat per-device autorisatie: een eigen architectuurvraag over de betekenis van een sessie, niet iets
dat met een capabilityveld op te lossen is.

### 4.6 De technische grens, op architectuurniveau

Zes grenzen, geen implementatieplan.

1. **`libraries.kind` wordt uitgebreid met `books`.** `libraries` blijft de gedeelde resource waar
   `library_permissions.library_id` aan hangt. Er komt geen `ebook_libraries`.
2. **`media_items.kind` krijgt geen `book`, en `media_versions`/`media_streams` dragen geen
   e-books.** Een EPUB heeft geen `duration_ms`, geen container in de zin van `media_versions`, en
   geen sporen. De `media_*`-tabellen blijven audiovisueel.
3. **Boeken krijgen een eigen publicatie- en bestandsdomein**, met dezelfde levenscyclusbegrippen
   die de scanner al hanteert (gezien, ontbrekend sinds, generatie), gekoppeld aan `libraries` en
   `storage_locations`.
4. **De scanner wordt niet gedupliceerd.** Eén wandeling, één inode- en signatuurvergelijking, één
   ontbrekend-bestand-levenscyclus, met een analysestap die per bibliotheeksoort verschilt. ffprobe
   draait alleen voor `movies` en `shows`. Welke vorm die dispatch krijgt is PS-14-werk; wat hier
   vastligt is dat de dure en bewezen NAS-logica gedeeld blijft en dat er geen tweede scanner naast
   de eerste komt.
5. **Leesvoortgang is geen kijkstatus.** `watch_states` draagt eigendom van een afspeelpositie met
   `owner_session_id` en `owner_lease_until`, en dat lost de vraag op welke speler de canonieke
   positie bezit. Een lezer heeft dat conflict niet. Het revisieprincipe mag hergebruikt worden waar
   de semantiek dat rechtvaardigt, de lease-semantiek niet. Vorm en tabel horen bij PS-15.
6. **Het EPUB-bestand gaat niet via `/stream`.** Zie 6 voor de afweging.

---

## 5. De gevolgen voor latere fasen

Per fase is nagegaan of hij aanneemt dat elke bibliotheek audiovisueel is. De aannames zijn met een
bestandsverwijzing gevonden waar ze in code staan, en met een fasetabel waar ze in de roadmap staan.

| Fase of plek | Aanname | Oordeel |
| --- | --- | --- |
| `handlers_library.go:87-90` | alles wat geen `shows` is, levert items van kind `movie` | **moet expliciet worden.** Een `books`-bibliotheek mag hier geen lege filmlijst opleveren |
| `scanner.go:697` | onbekende soort is een fout | **correct vandaag**, wordt in PS-14 een dispatch |
| `config/libraries.go:23,116` | twee soorten, en de foutmelding noemt ze | **moet mee** in PS-14 |
| `0002_catalog.sql:20` | CHECK op twee soorten | **moet mee** in PS-14, via een nieuwe migratie |
| `pleya_wire.dart:55`, `pleya_server_mappers.dart:61-65` | onbekende soort wordt verborgen | **klopt wel.** Het oordeel "klopt niet" is op 3 september 2026 ingetrokken: het filter zit in `browse.dart:45`, vóór de mapper. Zie de correctie in onderdeel 2 en de risicoparagraaf |
| PS-5 DeviceCapabilities | capabilities beschrijven decoder, display, audio, verbinding | **unaffected.** Een boek raakt geen enkel capabilityveld |
| PS-6 PlaybackPlan | elk item heeft versies en sporen | **unaffected zolang grens 2 geldt.** Boeken komen nooit in de planroute |
| PS-7 metadata | providerladder voor films en series | **niet uitbreiden.** Boekmetadata is een ander providerdomein en krijgt een eigen besluit als het ooit nodig is |
| PS-7N sidecars | `.nfo` met `<plot>`, coverage-gate van 80% | **unaffected.** Boeken dragen `metadata.opf`, een ander bestand met een andere gate. De coverage-gate van PS-7N gaat niet over boeken |
| PS-7A artworkformaten | `?width=` op artwork | **raakt boeken gunstig.** Een boekenraster heeft dezelfde behoefte als een posterraster; PS-14 bouwt daar niets voor vooruit |
| PS-8 transcoding | media hebben streams om te transcoderen | **unaffected** |
| PS-9C collecties en afspeellijsten | resources gedefinieerd over items | **beslist: unaffected.** Een boekenreeks is bibliografische metadata, geen collectie. Zie hieronder |
| PS-9P geschiedenis, favorieten, waarderingen | gedefinieerd over items en kijkstatus | **beslist: `play_history` blijft audiovisueel.** Leesstatus hoort in PS-15. Zie hieronder |
| PS-9T spoorvoorkeuren | audio- en ondertitelsporen | **unaffected** |
| PS-10 downloads | offline meenemen, afhankelijk van PS-8 wegens vooraf getranscodeerde varianten | **raakt PS-16, niet PS-14.** Een offline boek vraagt geen transcodering en mag die afhankelijkheid niet erven |
| PS-11A bibliotheekbeheer | toevoegen, hernoemen, verwijderen, scannen per bibliotheek | **moet drie soorten kennen.** Dat is een uitbreiding downstream, geen afhankelijkheid upstream |
| PS-11R realtime | scanvoortgang | **unaffected.** Een boekenscan is een scan |
| PS-12 Plex-migratie | alles komt uit een Plex-bibliotheek | **moet boeken uitsluiten.** Er is geen Plex-bron; boeken mogen niet stilzwijgend in de migratielogica belanden |
| PS-13 externe workers | transcodewerk verdelen | **unaffected** |
| Replacement matrix | elke regel is een Plex-verantwoordelijkheid | **productbesluit nodig.** Zie hieronder |
| Hoofdstuk 25, Definition of Done | de Plex-off gate telt blockers | **geen blocker.** Boeken kunnen de gate niet blokkeren, want Plex levert ze niet |

**Het matrixbesluit, genomen op 3 september 2026.** Onderhoudsregel 2 zegt dat een nieuwe
capability een regel in de matrix krijgt voordat hij ergens anders landt. Hoofdstuk 3 zegt dat elke
regel een Plex-verantwoordelijkheid is met bestemming A, B of C. E-books voldoen aan de eerste regel
en passen niet in de tweede. De uitkomst is een **aparte sectie "Buiten de Plex-vervanging"**, en
uitdrukkelijk geen gewone regel met bestemming A en een lege bronkolom: bestemming A betekent "Pleya
levert zelfstandig dezelfde productwaarde", en er is geen Plex-productwaarde om dezelfde van te zijn.

Aan die sectie hangt een voorwaarde, want een lijst zonder governance is een tweede roadmap die
niemand bewaakt:

> **De sectie telt niet mee in de Plex-off gate en niet in de completeness-telling van
> matrixhoofdstuk 9.1. Hij draagt wel dezelfde onderhoudsdiscipline als de rest van de matrix: per
> regel een Phase ID, een status uit hoofdstuk 4, het DEC-nummer waaronder hij is opgenomen, en zijn
> afhankelijkheden.**

**PS-9C, beslist.** Een boekenserie (`Dune #1`, `Dune #2`) is bibliografische metadata van het
e-bookdomein en hoort bij de publicatie in PS-14, niet bij collecties. PS-9C blijft voor echte
Pleya-collecties en afspeellijsten. Dat sluit een door een gebruiker gemaakte collectie "Mijn
favoriete Dune-boeken" later niet uit; dat is iets anders dan de serie `Dune`, en het is een vraag
voor PS-9C zelf.

**PS-9P, beslist.** `play_history` blijft audiovisueel. Een boek krijgt in PS-15 een actuele
leesstatus, in de orde van `unread`, `in_progress` en `completed` met een moment van uitlezen,
afgeleid uit de canonieke leesstatus. Een volledige historische reeks (eerste keer uitgelezen,
herlezen, derde keer) valt daar expliciet buiten. Wil iemand dat later wel, dan is dat een eigen
e-book-activiteitsmodel of een bewust generiek activiteitsmodel, met een eigen besluit.

---

## 6. Welke scope hierdoor vervalt, en welke alternatieven zijn afgewezen

**Er vervalt geen scope uit een bestaande fase.** Geen enkele fase levert iets minder op dan hij nu
belooft. PS-11A en PS-12 krijgen er werk bij; dat is uitbreiding en geen verplaatsing.

Wat wél vervalt, is de stilzwijgende aanname uit onderdeel 1: dat elke bibliotheek in Pleya Server
audiovisueel is. Die aanname wordt vervangen door een expliciete grens, namelijk dat `libraries`,
`storage_locations`, gebruikers, sessies, rechten en de scanprimitieven generiek zijn en dat de
`media_*`-tabellen dat niet zijn.

### Afgewezen alternatieven

**`book` toevoegen aan `media_items.kind`.** Dan draagt elk boek een `media_version` met een
verzonnen `duration_ms` en een `container` die "epub" zegt, en zou de vraag ontstaan wat een
`media_stream` van een boek is. De constraints in `0002_catalog.sql:48` modelleren bovendien de keten
show → season → episode; een vierde kind dat geen ouder en geen kind heeft, past daar alleen in door
de constraints losser te maken voor alle soorten. Dat maakt het model zwakker voor video om ruimte
te geven aan iets dat geen video is.

**EPUB uitleveren via `/stream`.** Poort 4 is gesloten met DEC-050: `/stream` draagt een zwakke
validator en Pleya belooft daar geen byte-identiteit. `docs/pleya-server-gates.md:198` zegt
expliciet waar byte-identiteit wél telt, namelijk bij een onderbroken download, en dat is PS-10. Een
reader opent een heel bestand en niet een venster erin, dus de leesroute is inhoudelijk een
bestandsoverdracht en geen streamsessie. Het streamtoken, de streamsessie met cookie uit DEC-051 en
de `Range`-semantiek van een speler lossen alle drie een probleem op dat een boek niet heeft.

**Een eigen `ebook_permissions`.** Dat zou de ladder uit DEC-098 §4 dupliceren, met twee plekken
waar owner en admin een rol omzeilen en twee plekken waar een niet-toegankelijke bibliotheek als
niet-bestaand behandeld moet worden. De bestaande laag doet dit al, en boeken hebben er geen extra
trede bij nodig.

**Een aparte `ebook_libraries`-tabel.** Die knipt de koppeling met `library_permissions.library_id`
door, en daarmee precies de reden om het bestaande rechtenmodel te hergebruiken.

**`media_files` verbreden tot een universele bestandstabel.** De tabel kent rollen (`media`,
`subtitle`, `artwork`) en hangt aan versies of items. Verbreden zou hem semantisch vervuilen voor
zijn huidige gebruikers. De scanprimitieven zijn te hergebruiken zonder de tabel te delen.

**Een tweede scanner naast de eerste.** Dat zou de wandeling, de inodedetectie, het mountgedrag, de
signatuurvergelijking en de ontbrekend-bestand-levenscyclus dupliceren, allemaal met tests eronder
die dan twee implementaties moeten bewaken.

**Een client-gerapporteerde mobile capability als toegangscontrole.** Zie 4.5.

**Wachten op PS-11A voor bibliotheekbeheer.** Bibliotheken komen vandaag uit configuratie; dat is
het mechanisme dat werkt, en het werkt voor een derde soort net zo goed.

---

## 7. Risicoanalyse

**Bestaande builds tonen een lege boekenbibliotheek.** Dit is het scherpste risico, omdat het
protocol iets belooft wat de client niet doet. Een build die vandaag in de App Store staat, krijgt
bij een `books`-bibliotheek een `MediaKind.unknown`-bibliotheek te zien en toont die. Drie mogelijke
antwoorden, te kiezen in PS-14: de bibliotheek pas serveren wanneer `capabilities.ebooks` door de
client is bevestigd, de clientkant repareren zodat `MediaKind.unknown` op een Pleya
Server-verbinding verborgen wordt, of het gedrag accepteren en documenteren. Bij de goedkeuring is
dit van acceptatiecriterium naar poort gepromoveerd: het antwoord moet er zijn en bewezen zijn
**vóór** het protocolvenster opengaat, niet vóór PS-14 sluit. De formulering staat in 4.4.

> **Correctie van 3 september 2026, na verificatie. Dit risico bestaat niet in de vorm waarin het
> hier staat, en de alinea blijft staan omdat de poort erop gebouwd is.** Een build die vandaag in
> de App Store staat verbergt een `books`-bibliotheek al, want `fetchLibraries` filtert een
> onbekende soort weg vóór de mapper (`browse.dart:36-51`, op `main` sinds `8342a8b`). De tweede van
> de drie genoemde antwoorden is daarmee al geïmplementeerd en de generieke regressietest bestaat
> al (`test/pleya_server/pleya_server_browse_test.dart:44`, met de fictieve soort `music`).
>
> De promotie van acceptatiecriterium naar poort blijft in stand. Een codelezing is geen
> runtimebewijs, en de vier meetpunten uit het bewijsplan gaan over het gedrag van een draaiende
> binary. Wat verandert is wat de meting naar verwachting oplevert: een bevestiging dat de
> bibliotheek werkelijk onzichtbaar blijft, in plaats van een defect. Verbergen is zelf ook een
> uitkomst die gecontroleerd hoort te worden, want een weggefilterde bibliotheek mag geen fout, geen
> blokkerende lege staat en geen achterblijvende rij uit de lokale cache opleveren.
>
> Wat wel overeind blijft is de serverkant: `handlers_library.go:87-90` behandelt elke soort die
> geen `shows` is als `movies`, en dat blijft acceptatiecriterium 4 van PS-14.

**De migratie raakt een bestaande database met data.** Het verruimen van een CHECK-constraint op
`libraries` is op zichzelf goedkoop, maar draait op de NAS tegen een gevulde catalogus. De migratie
hoort daarom niets anders te doen dan verruimen, zonder aanraking van bestaande rijen.

**Scannerdrift.** De grootste kans op stille schade is dat de dispatch per bibliotheeksoort de
gedeelde logica alsnog splitst, bijvoorbeeld door een tweede wandeling of een eigen
inodevergelijking voor boeken. De bestaande tests in `internal/scanner/` bewaken het gedeelde deel;
de acceptatiecriteria van PS-14 horen expliciet te eisen dat die tests ongewijzigd blijven slagen.

**PS-11A en PS-12 lopen achter de feiten aan.** Beide fasen zijn nog niet uitgevoerd en krijgen er
werk bij. Het risico is niet technisch maar administratief: als hun scope niet meteen wordt
bijgewerkt, staat er straks een beheerscherm met twee soorten en een migratiepad dat boeken
meeneemt.

**De DEC-nummering botst tussen branches, breder dan één nummer.** Een audit over alle lokale en
remote branches op 3 september 2026 (`docs/DECISIONS.md` per branch, 2568 regels, 92 verschillende
nummers) laat 23 nummers zien die twee of drie inhoudelijk verschillende besluiten dragen:
DEC-030 tot en met DEC-039, DEC-049, DEC-096 tot en met DEC-106, en DEC-091. Dat is geen incident
maar het gevolg van drie lijnen die onafhankelijk vanaf dezelfde basis doorgeteld hebben: de
Pleya Server-lijn, de TV- en mobiele designlijn, en de Pleya Verify-lijn.

Daaruit volgt het nummerbesluit bij de goedkeuring:

- de bestaande Pleya Server-**DEC-102** (`sid` door de authketen) **blijft staan**; er hangen
  verwijzingen en migratiecommentaar aan, en dat besluit is onderdeel van lopend PS-9-werk;
- de mobiele-navigatie-DEC op `feat/ebooks` wordt **hernummerd**. Die staat daar gecommit
  (`f60f940`), dus dat is een commit op die branch en geen werkboomwijziging, en hij hoort daarom
  niet thuis in dit voorstel of op deze branch;
- dit roadmapbesluit krijgt **DEC-107**, het eerste nummer dat op geen enkele branch voorkomt
  (hoogste gebruikte is DEC-092 op `feat/netflix-mobile`, zonder gaten eronder);
- voor de hernummering op `feat/ebooks` is **geen nummer gereserveerd**. Bij de goedkeuring van het
  PS-14-ontwerp op 3 september 2026 is vastgelegd dat ook de DEC onder de sterke validator van de
  boekroute zijn nummer pas bij het committen krijgt, na een verse audit. Wie het eerst commit krijgt
  het eerstvolgende vrije nummer; de ander schuift door. Een nummer vooraf claimen is precies de
  gewoonte die de 23 botsingen hierboven heeft opgeleverd.

De audit is een momentopname. Parallelle sessies kunnen een nummer claimen terwijl dit document
open staat, dus vóór een merge hoort de audit opnieuw te draaien in plaats van dat er op deze
uitkomst wordt vertrouwd.

**Reikwijdte van de comp.** De twaalfpanelen-comp toont ook downloads, aanbevelingen en zoeken in
een boek. Aanbevelingsrijen staan al als roadmap gap genoteerd in het PS-4E-voorstel, in afwachting
van een relatie-endpoint bij PS-7. Dit voorstel belooft die schermen niet en schrapt ze evenmin: ze
horen bij PS-16 of bij een fase die er nog niet is.

---

## 8. Wat hiermee vaststaat, en wat het volgende besluit is

Vastgelegd bij de goedkeuring van 3 september 2026:

1. e-books horen tot de productscope van Pleya Server (4.1);
2. de matrix krijgt een aparte sectie "Buiten de Plex-vervanging", met eigen onderhoudsdiscipline en
   buiten de Plex-off gate (5);
3. PS-14 is de eerst vrij te geven fase, met PS-2 en PS-9 als afhankelijkheden, gevolgd door PS-15;
   PS-16 is begrensd en niet vrijgegeven (4.2);
4. het protocolvenster voor PS-14 gaat pas open bij de uitvoering van PS-14, met een eigen DEC, en
   `openapi.yaml` blijft tot dat moment onaangeraakt (4.4);
5. vóór dat venster opengaat moet bewezen zijn hoe bestaande clients een onbekende `LibraryKind`
   werkelijk behandelen (4.4);
6. de mobiele grens is clientgedrag; de server levert feiten en er komt geen platformveld aan
   sessies of login (4.5);
7. `media_*` blijft audiovisueel (4.6);
8. een boekenreeks is geen PS-9C-collectie, en `play_history` blijft audiovisueel (5).

**Het eerstvolgende besluit is het vrijgeven van PS-14**, en dat is niet met dit document genomen.
Wat daarvoor eerst moet liggen: de fase zelf ontworpen, met scope, acceptatiecriteria,
stopcriterium en de poort uit 4.4 als expliciete voorwaarde. Zolang dat er niet is, blijft PS-9 de
lopende fase en is e-bookservercode te vroeg.

**Stand op 3 september 2026, later diezelfde dag.** Dat ontwerp ligt er, in
[docs/pleya-server-ps14-proposal.md](pleya-server-ps14-proposal.md), en is goedgekeurd met zeven
bindende beslissingen. Vrijgeven voor uitvoering is het niet: PS-14 is geblokkeerd op PS-9, en tot
dat moment blijft de zin hierboven onverkort gelden. Eén stuk werk mag wél al, en het is
uitdrukkelijk geen e-bookservercode: de generieke defectfix op de onbekende `LibraryKind` in de
client.

> **Correctie van 3 september 2026, na verificatie.** Die defectfix heeft geen werk meer: de client
> verbergt een onbekende soort al en de generieke regressietest bestaat al. Zie de correctie in
> onderdeel 2. Er is daarmee geen toegestane codewijziging; de volgorde is de correctie doorvoeren
> en daarna terug naar PS-9.

Eén afhankelijkheid loopt de andere kant op en verdient aandacht bij die planning: de client op
`feat/ebooks` heeft voor `BooksLibraryProvider.available` een echt servercontract nodig. Gaat die
branch verder dan mockups en het navigatieskelet voordat PS-14 ontworpen is, dan ontstaat er
tijdelijke providerlogica die daarna weer weg moet.

## 9. Roadmap Drift Check op dit voorstel zelf

Is er iets gebouwd dat niet in scope stond? Nee. Er is geen migratie geschreven, geen tabel
ontworpen tot op kolomniveau, geen endpoint gedefinieerd, geen regel Go of Dart gewijzigd, en
`openapi.yaml` is niet aangeraakt. De enige wijziging in de repository is dit bestand.

Is er scope blijven liggen? Ja, bewust: PS-15 en PS-16 zijn benoemd zonder uitwerking, en drie
open vragen (PS-9C, PS-9P en de matrixoptie) staan expliciet als open in plaats van dat ze hier
beantwoord worden.

Klopt de volgende fase nog? Ja. PS-9 blijft de lopende fase, de doorloop PS-5, PS-9, PS-11A, daarna
PS-6 tot en met PS-8 verandert niet, en PS-14 voegt geen afhankelijkheid toe aan een fase die al
gepland staat.
