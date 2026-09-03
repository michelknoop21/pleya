# Ontwerpvoorstel PS-14: e-bookcatalogus en inhoud

**Status:** **goedgekeurd 3 september 2026 met zeven bindende beslissingen.** De implementatie is
**geblokkeerd op PS-9**: PS-14 is niet actief en er komt geen PS-14-productiecode voordat PS-9
formeel gesloten is. "Goedgekeurd" is hier uitdrukkelijk niet "vrijgegeven voor uitvoering"
**Datum:** 3 september 2026
**Auteur:** Michel Knoop
**Betreft:** vrijgave van **PS-14**, vastgelegd als fase in
[DEC-093](DECISIONS.md#dec-093-e-books-worden-een-contentdomein-van-pleya-server-als-ps-14-en-ps-15)
en onderbouwd in [docs/pleya-server-ebooks-proposal.md](pleya-server-ebooks-proposal.md)

DEC-093 heeft e-books tot productscope gemaakt en er twee fasen voor aangemaakt. Dat besluit sluit af
met de zin dat het vrijgeven van PS-14 een apart besluit is, en dat daarvoor eerst de fase zelf
ontworpen moet zijn: scope, acceptatiecriteria, stopcriterium en de poort uit 4.4 als expliciete
voorwaarde. Dit document is dat ontwerp.

Alles hieronder is getoetst tegen de code op `feat/pleyaserver`. Waar een bewering een bestand en een
regelnummer draagt, is die daar gecontroleerd en niet uit de architectuurtekst overgenomen.

> **Correctie van 3 september 2026, na verificatie.** Die toets heeft één bewering laten passeren.
> De clientbullet in hoofdstuk 5 las de mapper en niet de aanroeper, waardoor beslissing 1 op een
> onjuiste bevinding rust. De correcties staan bij de betrokken passages in hoofdstuk 5, 11.1, 11.3,
> 11.4 en bij beslissing 1.

De zeven beslissingen uit de review van 3 september 2026 zijn in de tekst verwerkt en staan bij
elkaar in [hoofdstuk 14](#14-de-zeven-bindende-beslissingen). Waar dit document eerder een keuze
openliet, staat nu het besluit.

---

## 1. Wat dit voorstel wel en niet doet

Het legt het ontwerp van PS-14 vast, en dat ontwerp is goedgekeurd. Wat het niet doet is de fase
openen. PS-14 is goedgekeurd en geblokkeerd op PS-9, en die twee woorden horen bij elkaar te blijven
staan: een fase die "goedgekeurd" heet en waarvan de blokkade in een voetnoot verdwijnt, is precies
de gate-erosie waarvoor de fasestructuur bestaat.

Eén stuk werk mag wél nu al, en het is geen PS-14-werk: de defectfix uit
[beslissing 1](#14-de-zeven-bindende-beslissingen).

> **Correctie van 3 september 2026, na verificatie.** Dat werk bestaat niet: de bevinding onder
> beslissing 1 is onjuist, de client verbergt een onbekende bibliotheeksoort al en de generieke
> regressietest bestaat al. Er is met dit voorstel geen toegestane codewijziging. Zie de correctie
> bij [beslissing 1](#14-de-zeven-bindende-beslissingen).

Het verandert de roadmap niet. PS-9 is de lopende fase, PS-14 hangt aan PS-2 en PS-9, en de
vastgelegde doorloop PS-5, PS-9, PS-11A, daarna PS-6 tot en met PS-8 blijft ongemoeid. Er is bij het
schrijven geen migratie gemaakt, geen tabel tot op kolomniveau vastgelegd, geen regel Go of Dart
gewijzigd, en `docs/pleya-protocol/v1/openapi.yaml` is niet aangeraakt.

De beslissingen staan in [hoofdstuk 14](#14-de-zeven-bindende-beslissingen) en niet verstopt in een
ontwerpparagraaf.

---

## 2. Scope

De fasetabel in [hoofdstuk 23](pleya-server-architecture.md#23-roadmap-in-dertien-fasen-plus-een-fundering)
noemt zes dingen. Ze staan hier in de volgorde waarin ze gebouwd worden, met per onderdeel wat er
concreet onder valt.

1. **`books` als bibliotheeksoort**, in de databaseconstraint, in de configparser en in het protocol.
2. **Een eigen publicatie- en bestandsdomein voor boeken**, gekoppeld aan `libraries` en
   `storage_locations`, naast en niet in de `media_*`-tabellen.
3. **Een EPUB-analyser** die uit een bestand haalt wat de catalogus nodig heeft: titel, auteur, taal,
   een identificatie, en de verwijzing naar de cover in de publicatie zelf.
4. **Een analysestap per bibliotheeksoort in de bestaande scanner.** Eén wandeling, één
   inodevergelijking, één ontbrekend-bestand-levenscyclus. ffprobe draait uitsluitend voor `movies`
   en `shows`.
5. **Een eigen protocolresource** voor lijst, detail, cover en het EPUB-bestand.
6. **Autorisatie via het bestaande model.** `MayAccess` en `VisibleLibraries`
   (`pleya_server/internal/catalog/permissions.go:65,93`) worden hergebruikt zoals ze zijn.

## 3. Non-scope

Uit de fasetabel: leesvoortgang, bladwijzers, annotaties, de reader, offline boeken, aanbevelingen,
boekmetadata uit externe providers, andere formaten dan EPUB, boeken in `/search` en in de hubs, en
bibliotheekbeheer via een scherm.

Daar komt de regel bij die op 3 september 2026 aan de fasetabel en aan DEC-093 punt 8 is toegevoegd:

> PS-14 bouwt geen infrastructuur vooruit voor PS-15 of PS-16 tenzij PS-14 die zelf aantoonbaar nodig
> heeft.

Die regel heeft in dit ontwerp al twee dingen weggehaald. Er komt geen tabel, kolom of endpoint voor
een leespositie, ook niet als voorbereiding. En hij loopt door tot in
[beslissing 2](#14-de-zeven-bindende-beslissingen), die de sterke validator op de boekroute
binnenhaalt: die validator is scope omdat acceptatiecriterium 3 hem nodig heeft, en alles wat er in
de praktijk omheen groeit is dat niet. Uitdrukkelijk buiten PS-14, ook als het onderweg handig lijkt:

- een generieke downloadmanager of downloadwachtrij;
- een persistent model voor gedeeltelijk opgehaalde bestanden;
- een API voor downloadstatus of voortgang;
- bladwijzer- of offline-state in welke vorm dan ook.

Dat is de PS-16-onderlaag, en die wordt hier niet vooruitgebouwd. Wat er wel komt staat in
[hoofdstuk 8](#8-de-bytes-cover-en-epub).

Twee grenzen uit DEC-093 gelden onverkort en zijn hier niet opnieuw afgewogen: `media_*` blijft
audiovisueel, en de mobiele beperking is clientgedrag zonder platformveld op login of `sessions`.

---

## 4. Afhankelijkheden, en waarom geen andere

**PS-2** levert wat PS-14 hergebruikt in plaats van nabouwt: `libraries`, `storage_locations`, de
wandeling, de inode- en signatuurvergelijking, en de levenscyclus van een verdwenen bestand
(`pleya_server/internal/scanner/scanner.go:209-300`). Zonder die laag zou er een tweede scanner
ontstaan, en dat is het alternatief dat het e-booksvoorstel expliciet afwijst.

**PS-9** levert de gebruiker en het bibliotheekrecht. `library_permissions` bestaat sinds
`0007_users_sessions.sql:51`, en `MayAccess` doet de ladder view < download < manage met de
rolomzeiling voor owner en admin. Acceptatiecriterium 2 van PS-14 is zonder die tabel niet te halen
en ook niet te testen.

**PS-9 is nog niet gesloten, en dat blokkeert de uitvoering.** De capabilities `Users` en `Sessions`
staan in `pleya_server/internal/api/handlers_auth.go:73,77` nog op `false`, met het commentaar dat de
vlaggen pas aangaan zodra de endpoints er zijn. Beslissing 6 maakt daar een harde grens van: het
ontwerp is goedgekeurd, de fase is niet actief, en er komt geen PS-14-productiecode voordat PS-9
formeel gesloten is. Overlappen is geen optie die opengelaten is; twee fasen die tegelijk lopen laten
de poorten van allebei eroderen.

**Waarom PS-11A geen afhankelijkheid is.** Bibliotheken ontstaan vandaag uit
`PLEYA_SERVER_LIBRARIES` plus een herstart, via `ParseLibraries`
(`pleya_server/internal/config/libraries.go:31`) en `SyncLibraries`
(`pleya_server/internal/catalog/store.go:53`). Dat mechanisme kent geen aantal soorten; het kent de
soorten die de parser toestaat. Een derde waarde toevoegen kost één regel in `LibraryKinds`
(`libraries.go:23`) en een aangepaste foutmelding op regel 116. Wachten op een beheerscherm zou PS-14
laten hangen aan een fase die hij niet nodig heeft.

**Waarom PS-7 en PS-7N geen afhankelijkheid zijn.** De metadata die PS-14 nodig heeft zit in het
EPUB-bestand zelf, in de OPF, en komt niet van een provider en niet uit een `.nfo`. De coveragegate
van 80 procent uit PS-7N gaat over `.nfo`-sidecars bij film en serie en zegt niets over boeken.

**Waarom PS-7A geen afhankelijkheid is, maar er wel werk bij krijgt.** Zie
[hoofdstuk 8](#8-de-bytes-cover-en-epub).

**Waarom PS-8 en PS-10 geen afhankelijkheid zijn.** Een EPUB wordt niet getranscodeerd en niet
opnieuw verpakt. De afhankelijkheid van PS-10 op PS-8 bestaat wegens vooraf getranscodeerde varianten
en mag door PS-16 niet geërfd worden; DEC-093 zegt dat al, en PS-14 raakt die route helemaal niet.

---

## 5. Wat de code vandaag doet, en waar een boek doorheen valt

Dit hoofdstuk is de grond onder de rest. Het e-booksvoorstel noemde drie plekken waar de aanname
"elke bibliotheek is audiovisueel" in code staat. Bij het nalopen bleken het er acht, en één ervan
verandert de vorm van het werk.

**De wandeling laat een EPUB niet eens binnen.** `Walk` gooit elk bestand weg waarvan
`nameparse.Classify` `KindOther` teruggeeft (`internal/scanner/walk.go:73-76`), en `Classify` kent
alleen video, ondertitel en afbeelding (`internal/nameparse/nameparse.go:60-70`). Een boekenroot
levert vandaag dus nul entries op. Erger: `scanRoot` breekt af zodra een root nul bestanden oplevert
terwijl er wel bekende paden zijn (`scanner.go:234-237`), een guard die bedoeld is voor een
ongemounte USB-schijf. Deze plek staat niet in het e-booksvoorstel, dat alleen de dispatch in `attach`
noemt.

**De tweedeling media-tegen-sidecar zit vóór de bibliotheeksoort.** `scanner.go:268-272` stuurt elk
bestand met `KindVideo` naar `processMedia` en al het andere naar `processSidecars`. Een boek is
geen van beide, en als sidecar zou het als ondertitel of artwork behandeld worden.

**ffprobe draait vóór de dispatch, niet erna.** `processMedia` analyseert elke gewijzigde kandidaat
parallel (`scanner.go:448-485`) en pas daarna kijkt `attach` naar `lib.Kind` (`scanner.go:600`). De
scope-eis "ffprobe alleen voor `movies` en `shows`" is dus niet te halen door de `switch` in `attach`
uit te breiden. De dispatch moet omhoog, naar het punt waar de kandidaten verdeeld worden. Dat is
precies de wijziging met de grootste kans op het risico dat de fasetabel noemt, namelijk dat de
gedeelde scanlogica alsnog splitst.

**De onbekende soort faalt luid op één plek en stil op een andere.** `attach` weigert expliciet
(`scanner.go:699`), maar het items-endpoint behandelt alles wat geen `shows` is als `movies`
(`internal/api/handlers_library.go:87-90`) en levert dan een lege filmlijst zonder fout.

**`item_count` telt uitsluitend `media_items`.** De subquery in `Libraries`
(`internal/catalog/store.go:104-110`) telt `kind IN ('movie', 'show')` binnen de bibliotheek. Een
`books`-bibliotheek rapporteert dus `item_count: 0`, en dat botst rechtstreeks met de clientpolicy
van DEC-069 op `feat/ebooks`, die de vierde tabslot geeft aan Boeken zodra er "minimaal één boek
zichtbaar voor dat profiel" is. Zie [hoofdstuk 9](#9-protocolwijzigingen).

**Een boekcover past niet op de bestaande artworkroute.** `ArtworkFile` joint `media_items`
(`internal/catalog/store_read.go:427-432`). Zolang boeken daar niet in staan, en dat is grens 2 uit
DEC-093, kan `/artwork/{id}` een boekcover niet oplossen.

**Een gewijzigde soort in de configuratie overschrijft de bestaande.** `SyncLibraries` doet
`ON CONFLICT (slug) DO UPDATE SET ... kind = EXCLUDED.kind` (`store.go:68-70`). Met twee soorten was
dat ongevaarlijk, want een bibliotheek van films naar series omzetten is een typefout die je meteen
ziet. Met drie soorten kan `films=books:/media/Films` een gevulde filmbibliotheek stilzwijgend tot
boekenbibliotheek maken, met alle `media_items` er nog aan. Beslissing 4 zet dat dicht; zie
[hoofdstuk 10](#10-migratie-en-compatibiliteit-met-een-gevulde-database).

**De rechtenlaag heeft niets audiovisueels.** `MayAccess` en `VisibleLibraries`
(`permissions.go:65,93`) werken op `libraries.id` en `library_permissions`. Hier hoeft niets aan.

**De clientkant komt zijn eigen doc-comment niet na.** `PleyaLibraryKind.tryParse` geeft `null` bij
een onbekende soort, met de tekst "the caller hides that library rather than failing"
(`lib/models/pleya_server/pleya_wire.dart:50-61`). De caller verbergt niets: `libraryKindOf` maakt er
`MediaKind.unknown` van (`lib/services/pleya_server_mappers.dart:61-65`), en het enige filter op de
bibliotheeklijst is `isMusicLibrary`, dat alleen `artist` weghaalt (`lib/utils/content_utils.dart:30-36`).
`getLibraryIcon` valt voor een onbekende soort terug op een mapicoon (`content_utils.dart:41-55`).
Dezelfde code staat op `main` en gaat dus mee in elke uitgeleverde build.

> **Correctie van 3 september 2026, na verificatie. Deze bullet is onjuist en blijft staan omdat
> beslissing 1 erop gebouwd is.** De caller verbergt wél: `fetchLibraries` filtert
> `library.kind != null` vóór `PleyaServerMappers.library`
> (`lib/services/pleya_server_client/parts/browse.dart:36-51`), met de contractbelofte als comment
> erboven. Die code staat sinds `8342a8b` (19 augustus 2026) op `main` en zit dus in elke
> uitgeleverde build. Het is de enige productieaanroeper van de mapper, en
> `pleya_server_api_cache.dart` cachet items en geen bibliotheken, dus er loopt geen tweede route
> naar `libraryKindOf` toe. `test/pleya_server/pleya_server_browse_test.dart:44` legt het gedrag al
> vast, met de fictieve soort `music`.
>
> Wat over `isMusicLibrary` en `getLibraryIcon` staat is op zichzelf waar, maar het wordt op de
> Pleya Server-route nooit met een onbekende soort bereikt: die is dan al weg. De tak
> `null => MediaKind.unknown` in `pleya_server_mappers.dart:61-65` is via die route onbereikbaar.

**Pleya Web heeft dezelfde val, en tegelijk niet.** De bibliothekenlijst tekent
`kind === 'shows' ? 'show' : 'movie'` (`pleya_web/src/routes/libraries/+page.svelte:22`), precies de
serverfout in de client herhaald. Alleen: de webbundel zit ingebed in de serverbinary
(`pleya_server/internal/web/web.go:24`, met een releasebuild die weigert te compileren zonder bundel
in `release.go:18`). Een server die `books` kan serveren levert per definitie de webclient mee die
`books` kent. Voor het web bestaat het probleem van een oudere client dus niet. Dat maakt de poort
uit [hoofdstuk 11](#11-de-poort-vóór-het-protocolvenster) kleiner dan hij op papier leek: hij gaat
uitsluitend over de Flutter-app.

> **Aanvulling van 3 september 2026, na verificatie.** Regel 22 is bovendien een icoonkeuze binnen
> `{#each session.libraries}` en geen zichtbaarheidsbeslissing: wat het web toont volgt volledig uit
> wat de server teruggeeft. Beide verboden uitkomsten van de poort zijn daar dus onbereikbaar zonder
> een server die `books` serveert, en die server draagt de bijgewerkte bundel in dezelfde commit.
> Regel 22 raakt de poort niet en is gewone PS-14-scope: op het moment dat `books` landt, krijgt de
> soort in diezelfde commit een eigen icoon en route. Dat de Flutter-app "de hele poort" is, blijft
> daarmee overeind, met de kanttekening uit de correctie op de clientbullet hierboven dat die app
> een onbekende soort vandaag al verbergt.

---

## 6. Het datamodel

**Migratie 0008 verruimt één constraint.** `libraries.kind` accepteert vandaag twee waarden
(`0002_catalog.sql:20`). De migratie laat `books` toe en raakt geen enkele bestaande rij aan. Het
bestand 0002 zelf wordt niet bewerkt: `migrate.go:204-207` weigert te starten zodra de checksum van
een toegepaste migratie verandert, en dat is opzet.

**Boeken krijgen een eigen publicatie- en bestandsdomein.** Twee tabellen, met dezelfde
identiteitsdiscipline als hoofdstuk 7.2 voor media voorschrijft: een pad is nooit een identiteit, en
een groeperingssleutel doet één ding.

- Een **publicatie** is één boek in één bibliotheek, met de bibliografische velden die het protocol
  toont, plus de reeksnaam en het nummer daarin. Een boekenreeks is bibliografische metadata en geen
  collectie; dat is DEC-093 punt 6 en het scheelt een tabel.
- Een **publicatiebestand** is één pad onder een `storage_location`, met dezelfde goedkope detectie
  als `media_files`: grootte, mtime, inode, signatuur, generatie, en de drieslag eerst gezien, laatst
  gezien, ontbrekend sinds.

`media_files` wordt niet verbreed. De tabel kent rollen die aan een versie of aan een item hangen
(`0002_catalog.sql:171-176`), en die constraint zou voor een boek losser moeten. Het e-booksvoorstel
wijst dat af, en dat blijft staan.

**Wat er bewust niet in gaat.** Bijdragers en onderwerpen als eigen tabellen worden pas gebouwd
zodra de detailresource ze werkelijk toont. Zolang een auteur één geordende lijst per publicatie is,
is een aparte tabel een abstractie zonder tweede gebruiker. Dit is de eerste toepassing van de regel
uit hoofdstuk 3 en hoort in de Roadmap Drift Check bij het sluiten van de fase terug te komen.

---

## 7. De scanner

Eén wandeling blijft één wandeling. Wat verandert is waar de bibliotheeksoort gelezen wordt.

**De accepteerbare bestandssoorten volgen uit de bibliotheek, niet uit de bestandsnaam alleen.**
`Classify` kijkt vandaag uitsluitend naar de extensie en weet niet in welke bibliotheek hij staat.
`.epub` daar onvoorwaardelijk aan toevoegen zou een filmbibliotheek boeken laten oppikken, die dan
als niet-gekoppelde bestanden blijven liggen. De wandeling krijgt daarom de verzameling soorten mee
die deze bibliotheek accepteert. Dat is een parameter op een bestaande functie, geen tweede
wandeling.

**De verdeling van kandidaten krijgt een derde emmer.** Naast media en sidecars komt er een emmer
voor publicatiebestanden. De beoordeling ervoor, `judge` (`scanner.go:359`), verandert niet: die
doet laag 1 en laag 2 en weet niets van inhoud.

**De analyse wordt per soort gekozen, vóór het analyseren.** Voor `movies` en `shows` blijft dat
ffprobe met dezelfde parallellisatie. Voor `books` is het de EPUB-analyser, die het bestand als zip
opent, `META-INF/container.xml` volgt naar de OPF en daar de bibliografische velden en de
coververwijzing uit leest. Het analyseresultaat gaat naar de publicatietabellen in plaats van naar
`media_versions`.

**Het bewijs dat de gedeelde laag niet gesplitst is, is de bestaande testsuite.** De tests in
`pleya_server/internal/scanner/` (`scanner_test.go`, `library_test.go`, samen 921 regels) bewaken de
wandeling, de hernoemdetectie, de signatuurvergelijking en de ontbrekend-bestand-levenscyclus. Ze
horen na PS-14 ongewijzigd te slagen. Een test die aangepast moet worden om groen te blijven is het
signaal dat de splitsing tóch is gebeurd, en dat is een reden om terug te gaan en niet om de test te
herschrijven.

---

## 8. De bytes: cover en EPUB

**De cover krijgt een eigen route.** `/artwork/{artwork_id}` kan een boekcover niet oplossen zolang
`ArtworkFile` op `media_items` joint. De cover van een EPUB zit bovendien meestal ín het bestand en
niet ernaast, dus de route levert bytes die uit de zip komen. Dat is een andere leesroute dan een
bestand op schijf openen, en het is de reden om hem niet in de bestaande handler te wringen.

**PS-7A krijgt er scope bij, en PS-14 bouwt daar niets voor vooruit.** PS-7A maakt `?width=` werkend
op artwork. Een boekenraster heeft dezelfde behoefte als een posterraster, maar de coverroute van
PS-14 levert de cover zoals hij is. De parameter, de cache en de afmetingenlogica horen bij PS-7A, en
die fase moet dan twee routes dekken in plaats van één. Dit is dezelfde soort uitbreiding downstream
als PS-11A en PS-12 al van DEC-093 kregen, en het hoort in de matrix bijgewerkt te worden op het
moment dat PS-14 sluit.

**Het EPUB-bestand gaat niet via `/stream`.** Dat is beslist in het e-booksvoorstel: het streamtoken,
de streamsessie met cookie uit DEC-051 en de `Range`-semantiek van een speler lossen alle drie een
probleem op dat een boek niet heeft.

**Hier zat de scherpste vraag van deze fase, en beslissing 2 beantwoordt hem.**
Acceptatiecriterium 3 in de fasetabel zegt "met een herstartbare overdracht". Poort 4 is gesloten met
DEC-050, en die zegt over de zwakke validator: "een gelijke validator zegt niets over de bytes, en
gelijkheid is daarom nergens in Pleya grond om ontvangen bytes aan later ontvangen bytes te plakken"
(`docs/pleya-server-gates.md:192-194`). Hervatten is precies dat plakken. Het gesloten besluit voegt
eraan toe dat byte-identiteit wél telt bij een onderbroken download, en dat dat PS-10 is, onder een
digest over het samengestelde bestand.

**Het besluit: criterium 3 blijft in PS-14 staan, met een sterke validator op de boekroute.** Niet
herformuleren, niet doorschuiven naar PS-16. De semantiek:

- de route draagt een sterke validator die precies één EPUB-representatie identificeert;
- hervatten gaat via de gewone `Range`- en `If-Range`-semantiek, en is alleen toegestaan wanneer die
  validator exact dezelfde representatie aanwijst;
- ontbreekt de validator, of wijkt hij af, dan worden er geen bytes gecombineerd en begint de
  overdracht opnieuw vanaf byte 0. Dat is de terugval en niet de foutmelding.

Let op wat hier omkeert ten opzichte van `/stream`. Daar levert `If-Range` altijd een 200 en nooit een
206 (`internal/api/handlers_stream.go:145,150-152`), juist omdat de validator zwak is. Op de boekroute is
een 206 na `If-Range` wél toegestaan, en dat mag uitsluitend omdat de validator daar sterk is. De twee
routes hebben dus expres verschillend gedrag op dezelfde header, en dat verschil hoort in de
specificatie te staan in plaats van uit de implementatie afgeleid te moeten worden.

**Hier hoort een eigen DEC onder, en die moet DEC-050 expliciet adresseren.** Geen impliciete
uitzondering: het besluit beschrijft waarom een EPUB van enkele megabytes anders ligt dan een
videobestand van tientallen gigabytes, waarom de zin "geen full-file hashing die alleen HTTP bedient"
uit DEC-050 daar niet door omvalt, en waar de grens ligt. Blijft dat verschil ongeschreven, dan is
het een gesloten poort openbreken met een uitzondering, en dat is precies wat de poortstructuur
tegenhoudt.

**Dit wordt geen offline-downloadlaag.** De validator bestaat omdat criterium 3 hem nodig heeft. De
opsomming in [hoofdstuk 3](#3-non-scope) zegt wat er niet omheen gebouwd wordt: geen
downloadmanager, geen persistent model voor halve bestanden, geen voortgangs-API, geen offline state.
PS-16 mag dat ontwerpen wanneer PS-16 aan de beurt is.

**Het nummer van die DEC staat nog niet vast.** De branchaudit van 3 september 2026 vond 23 nummers
die twee of drie verschillende besluiten dragen, en DEC-094 is daarom niet gereserveerd. Dit besluit
krijgt zijn nummer pas op het moment van committen, na een verse audit over alle branches. Landt het
eerder dan de hernummering van de mobiele-navigatie-DEC op `feat/ebooks`, dan schuift die laatste
door; dat is een uitkomst en geen conflict.

---

## 9. Protocolwijzigingen

Vijf wijzigingen, en één die uitdrukkelijk niet wordt voorgesteld. De toets is de zes regels uit
[hoofdstuk 12.3](pleya-server-architecture.md#123-versionering-en-compatibiliteitsregels), die
letterlijk ook in de specificatie zelf staan (`openapi.yaml:19-30`).

| # | Wijziging | 1 nieuw optioneel antwoordveld | 2 niets hernoemd of weg | 3 betekenis ongewijzigd | 4 geen nieuw verplicht aanvraagveld | 5 aanvraagbody gesloten | 6 enum alleen waar unknown-safe | Oordeel |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `LibraryKind` krijgt `books` | n.v.t. | ja | ja | n.v.t. | n.v.t. | `x-unknown-safe: true` op `openapi.yaml:1119` | toegestaan, achter de poort |
| 2 | `capabilities.ebooks` in `/info` | ja | ja | ja | n.v.t. | n.v.t. | geen enum | toegestaan |
| 3 | Resource `/pleya/v1/ebooks/...` | additieve resource | ja | ja | geen bestaande aanvraag geraakt | alleen GET, geen body | eigen enums, elk gemarkeerd | toegestaan |
| 4 | `item_count` gedocumenteerd voor `books` | n.v.t. | ja | zie hieronder | n.v.t. | n.v.t. | geen enum | toegestaan |
| 5 | Foutcode `library.wrong_kind` | n.v.t. | ja | ja | n.v.t. | n.v.t. | patroon, geen enum | toegestaan |
| A | `ItemKind` krijgt `book` | n.v.t. | n.v.t. | n.v.t. | n.v.t. | n.v.t. | zou mogen | **afgewezen** |

**Wijziging 1** is het mechanisme dat regel 6 beschrijft en geen uitzondering erop. Het veld draagt
de markering al, met de tekst dat een client die de soort niet kent de bibliotheek niet toont en niet
faalt. Dat is precies de belofte die hoofdstuk 5 als niet-nagekomen aanwijst, en daarom hangt deze
wijziging achter de poort.

**Wijziging 2** is de haak die de clientpolicy van DEC-069 nodig heeft. Capabilities zijn leidend,
`feature_level` gaat er niet van omhoog: correctie 7 uit het masterplan zegt dat additieve resources
via `capabilities` onderhandelen. De vlag hoort te volgen wat er werkelijk staat, dezelfde regel als
bij `WatchState`, die aan de aanwezigheid van de watch-store hangt
(`internal/api/handlers_auth.go:65`).

**Wijziging 3** krijgt een eigen namespace omdat de wire-`Item` velden draagt die een boek per
definitie leeg laat: `versions`, `streams`, `duration_ms`, `user_state.position_ms`. Een veld waarvan
de betekenis afhangt van een ander veld is de stilste vorm van breken uit regel 3. Componenten mogen
wel gedeeld worden: `Id`, `Timestamp` en de pagineringsvorm zijn generiek.

**Wijziging 4 verdient de toets op regel 3 uitgeschreven,** want daar zit de enige plek waar dit
voorstel dicht bij een betekeniswijziging komt. Beslissing 3: `item_count` telt publicaties.

`item_count` is in de YAML alleen getypeerd (`openapi.yaml:1131`) en heeft daar geen beschrijving. De
betekenis staat in Go: "uitsluitend wat de bibliotheek op het hoogste niveau toont"
(`store.go:101-103`). Die betekenis wordt behouden en niet opgerekt: het veld is het aantal
top-level entiteiten dat de bibliotheek representeert. Voor `movies` en `shows` zijn dat de bestaande
media-entiteiten, voor `books` zijn dat de publicaties. De berekening verandert, de betekenis niet,
en de YAML krijgt die betekenis er voor het eerst bij geschreven.

Dat is bewust één regel voor drie soorten, en niet drie regels naast elkaar. Er komt dus ook geen
speciaal clientgedrag bij: een client die vandaag "aantal items in deze bibliotheek" toont, blijft
precies dat tonen. Er is bovendien geen bestaande client die het verschil kan waarnemen, want zolang
de poort dicht is ziet een pre-books client geen boekenbibliotheek.

Het alternatief, `item_count` op nul laten en het aantal in de e-bookresource zetten, is afgewezen.
Nul teruggeven is semantisch onjuist zodra de server in diezelfde bibliotheek wél boeken toont, en het
levert in `/libraries` precies de lege bibliotheek op die de poort verbiedt, dan veroorzaakt door de
server zelf in plaats van door een oude client.

**Wijziging 5** vervangt het stille gedrag van `handlers_library.go:87-90`. De foutcode is een
patroon met een vast voorvoegsel (`openapi.yaml:920-923`) en geen enum, dus regel 6 is niet van
toepassing. Een client die de code niet kent valt terug op een generieke fout: codes worden alleen in
de authketen op naam vergeleken, met een if-reeks die doorvalt
(`lib/services/pleya_server_auth_service.dart:221-229`). Het alternatief, een lege pagina teruggeven,
is dezelfde lege bibliotheek als hierboven.

**Wijziging A blijft afgewezen** op de gronden uit het e-booksvoorstel: de ketenconstraint in
`0002_catalog.sql:64-70` modelleert show naar season naar episode, en een vierde soort zonder ouder
en zonder kind past daar alleen in door die constraint voor álle soorten losser te maken.

**Het venster.** Al deze wijzigingen horen in één protocolvenster met één DEC eronder, geopend bij de
uitvoering van PS-14 en gesloten zodra `scripts/check_protocol.sh` daarna slaagt. Dat script weigert
elk enum-veld zonder `x-unknown-safe` (`scripts/check_protocol.py:96-129`), dus de enums van de
nieuwe resource moeten die markering dragen voordat het venster dicht kan.

---

## 10. Migratie en compatibiliteit met een gevulde database

De NAS draait een gevulde catalogus. Wat 0008 daar doet, en wat er misgaat als het misgaat:

**De verruiming zelf is goedkoop.** Een CHECK-constraint op `libraries` vervangen betekent hem laten
vallen en opnieuw aanmaken. Postgres neemt daarvoor een ACCESS EXCLUSIVE lock en valideert de
bestaande rijen. `libraries` telt een handvol rijen, dus dat is een fractie van een seconde en er
wordt geen tabel herschreven. `NOT VALID` is bij deze omvang overbodige complexiteit.

**Geen bestaande rij wordt aangeraakt.** De migratie voegt geen kolom toe aan `libraries`, verandert
geen waarde en verplaatst geen data. De nieuwe tabellen zijn leeg tot de eerste scan van een
boekenbibliotheek.

**Terugrollen kost meer dan een oudere image.** Migraties zijn voorwaarts en er zijn geen
neerwaartse migraties (`migrate.go:1-7`). Na 0008 weigert een binary die de migratie niet kent te
starten met `ErrDatabaseNewer` (`migrate.go:193-195`). Terug naar de vorige serverversie is dus een
image terugzetten én de database terugzetten, niet alleen het eerste. Dat hoort in de
uitrolvolgorde te staan voordat de container op de NAS ververst wordt.

**Een server zonder boekenbibliotheek merkt niets.** Zolang `PLEYA_SERVER_LIBRARIES` geen `books`
bevat, blijft `libraries` inhoudelijk gelijk, staat `capabilities.ebooks` op `false` en levert de
e-bookresource een lege lijst. Dat is ook het pad waarop de migratie op de NAS eerst kan draaien,
los van het moment waarop er werkelijk een boekenbibliotheek bij komt.

**Er is één configuratiepad dat data kan beschadigen, en dat wordt in PS-14 dichtgezet.**
`SyncLibraries` schrijft de soort uit de configuratie onvoorwaardelijk over de bestaande heen
(`store.go:68-70`). Een typefout die een gevulde filmbibliotheek op `books` zet, laat de
`media_items` staan terwijl het items-endpoint voortaan weigert en de scanner de root anders
classificeert. Dat is geen theoretisch geval: de slug is de matchsleutel en `films` blijft `films`.

Beslissing 4 legt het gedrag vast:

- is de bibliotheek leeg, dan mag de soort veranderen;
- is hij niet leeg, dan weigert het opstarten met een duidelijke fout die zegt welke bibliotheek het
  betreft, welke soort er staat en welke er gevraagd wordt;
- die weigering is atomair. `SyncLibraries` draait al in één transactie (`store.go:54-58`), en de
  controle hoort daarbinnen, zodat er nooit een halve wijziging achterblijft. Stilzwijgend
  overschrijven vervalt, gedeeltelijk migreren komt er niet voor in de plaats.

**"Niet leeg" betekent alle catalogusinhoud aan die bibliotheek, niet één tabel.** De controle kijkt
naar `media_items` en `storage_locations` én naar de nieuwe publicatietabellen. Alleen naar de
boekentabel kijken zou de gevaarlijkste richting missen, namelijk een gevulde filmbibliotheek die
naar `books` wordt omgezet: die heeft nul publicaties en zou de controle glansrijk passeren.

Dit hoort in PS-14 en niet in PS-11A, omdat het toevoegen van de derde soort het bestaande gevaar
werkelijk bereikbaar maakt. Met twee soorten was `films=shows:...` een typefout die je meteen zag.

---

## 11. De poort vóór het protocolvenster

DEC-093 punt 7 zet er een harde voorwaarde voor de eerste protocolwijziging:

> Er moet aantoonbaar vaststaan hoe bestaande clients een nieuwe unknown-safe `LibraryKind`
> daadwerkelijk behandelen, niet alleen hoe het schema zegt dat ze hem zouden moeten behandelen. Een
> pre-books client mag een `books`-bibliotheek nooit tonen als lege movie-bibliotheek of als
> zichtbare unknown-bibliotheek.

### 11.1 Welke clients het betreft

**Pleya Web valt af, en niet omdat het risico klein is.** De bundel zit ingebed in de serverbinary
(`internal/web/web.go:24`) en een releasebuild weigert te compileren zonder bundel
(`internal/web/release.go:18`). Een server die `books` serveert draagt dus per definitie de webclient
die `books` kent. De fix in `libraries/+page.svelte:22` moet in dezelfde commit als de serverwijziging
zitten, en daarmee is er geen veld waar een oudere webclient bestaat.

**De Flutter-app is de hele poort.** Die wordt los gedistribueerd en kan ouder zijn dan de server.
`main` draagt `add_pleya_server_screen.dart` zonder vlag of debugconditie, dus elke uitgeleverde
build kan verbinding maken met een Pleya Server. Statisch lezen zegt dat zo'n build een tegel
"Boeken" met een mapicoon toont die leeg opent. Dat is precies wat de poort verbiedt, en het is
precies de lezing die de poort niet als bewijs accepteert.

> **Correctie van 3 september 2026, na verificatie.** De voorlaatste zin is onjuist. Statisch lezen
> zegt het omgekeerde: `fetchLibraries` filtert een onbekende soort weg vóór de mapper
> (`browse.dart:36-51`, op `main` sinds `8342a8b`), dus zo'n build toont die tegel niet. De laatste
> zin blijft onverkort staan, en juist die draagt de poort: een lezing is geen bewijs, in welke
> richting hij ook uitvalt.
>
> De poort blijft daarmee bestaan en verandert van verwachting. Laag C bewijst nu dat een
> uitgeleverde binary een `books`-bibliotheek werkelijk verbergt op de vier meetpunten uit 11.2, in
> plaats van dat zij een defect blootlegt. Verbergen is zelf ook een uitkomst die gemeten hoort te
> worden: een weggefilterde bibliotheek mag geen fout opleveren, geen blokkerende lege staat, en na
> herstarten geen rij die uit de lokale cache terugkomt. De Flutter-app blijft de hele poort.

### 11.2 Het bewijsplan

Drie lagen, van goedkoop naar bindend. Alleen laag C sluit de poort.

**Laag A, de codelezing.** Staat in hoofdstuk 5, met bestand en regelnummer. Dit is de laag die de
poort expliciet onvoldoende noemt, en hij staat er alleen om de verwachting scherp te hebben voordat
er gemeten wordt.

**Laag B, een test tegen de uitgeleverde bron.** Een test die een `/libraries`-antwoord met
`kind: "books"` door `PleyaServerMappers.library` haalt en daarna door de widget die de
bibliothekenlijst tekent, met een assertie op wat er zichtbaar is. Voor Pleya Web hetzelfde met een
vitest op de bibliothekenroute. Deze laag is deterministisch, draait in CI en houdt het antwoord
waar. Hij bewijst gedrag van code, niet van een binary.

**Laag C, een meting tegen een uitgeleverde binary.** Voor een echte build is een server nodig die
`books` zegt, en die mag er nog niet zijn. De oplossing is een omkeerproxy vóór de draaiende server
die precies twee antwoorden herschrijft: aan `GET /pleya/v1/libraries` wordt één regel toegevoegd met
`kind: "books"`, en `GET /pleya/v1/libraries/{die id}/items` levert een lege pagina. Verder gaat alles
ongewijzigd door. Er komt geen regel servercode bij, geen migratie, en `openapi.yaml` blijft dicht.

**De proxy gaat in de repository** (beslissing 5). Hij is geen eenmalige debughack maar
bewijsinfrastructuur onder een bindende protocolpoort, en bewijs dat na één sessie verdwijnt is geen
bewijs: de poort moet over een jaar nog opnieuw te lopen zijn. Vier eisen eromheen:

- hij staat bij het acceptatietestgereedschap en niet bij de productiecode;
- hij zit in geen enkele productiebuild en in geen enkel release-artefact, en de bestaande
  scheidingen zijn daar de plek voor: de serverbinary bouwt met `-tags release` (`internal/web/release.go`)
  en de Docker-image bevat alleen wat daarin meegaat;
- hij herschrijft deterministisch precies de noodzakelijke antwoorden en werkt verder als
  transparante proxy, zodat er geen tweede verklaring is voor wat een build doet;
- hij is het instrument en niet het bewijs. Het bewijs zijn de draaiende iOS-, tvOS- en
  desktopbuilds met de schermafbeeldingen erbij.

Wat er gemeten wordt, per platform, met een schermafbeelding als bewijs:

1. Verschijnt de bibliotheek in de zijbalk of het bibliothekenoverzicht, en hoe heet en oogt hij.
2. Wat gebeurt er bij openen: een lege lijst, een foutmelding, of een crash.
3. Wat doet zoeken, en wat doen de hubs, met die bibliotheek in de lijst.
4. Wat gebeurt er na herstarten van de app, met de bibliotheek in de lokale cache.

Minimaal iOS, tvOS en één desktopplatform, dezelfde spreiding als de hardwarerondes die dit project
al kent. De uitkomst hoort in `docs/` te landen naast dit voorstel, want de poort is pas dicht als
het antwoord opgeschreven staat.

### 11.3 Het antwoord dat de poort sluit

Meten is de helft. De poort eist ook dat de gevonden situatie opgelost is voordat het venster opengaat.
Het e-booksvoorstel liet daar drie opties open. Twee vallen af zodra je ze concreet maakt.

**"De bibliotheek pas serveren als de client `capabilities.ebooks` bevestigt" kan niet.** `/libraries`
is een GET zonder clientverklaring, en de server weet niet wat de client verstaat. Een nieuw
verplicht aanvraagveld breekt regel 4. Een nieuw optioneel veld moet volgens dezelfde regel een
default hebben die het oude gedrag reproduceert, en het oude gedrag is "alle bibliotheken". De
default "verberg boeken" zou het gedrag van een ongewijzigde aanvraag veranderen, en dan is het regel
3 in plaats van regel 4. Er is geen vorm waarin dit klopt.

**"Accepteren en documenteren" is het gedrag dat de poort letterlijk verbiedt.**

**Wat overblijft is de clientfix, plus een uitrolvolgorde.** De fix zelf is klein: de mapper laat een
bibliotheek met een onbekende soort weg in plaats van hem als `MediaKind.unknown` door te geven.
Daarmee doet de code wat zijn eigen doc-comment op `pleya_wire.dart:50-51` al belooft. De volgorde
eromheen is het echte werk: de eerste server die `books` serveert mag pas draaien op een huishouden
waar een app-build met die fix beschikbaar is. Voor dit product, één huishouden en één NAS onder
eigen beheer, is dat een uitrolafspraak en geen protocolmechanisme.

> **Correctie van 3 september 2026, na verificatie.** Die clientfix is er al. `fetchLibraries` laat
> een bibliotheek met een onbekende soort weg vóór de mapper (`browse.dart:36-51`), sinds `8342a8b`
> op `main`, en doet daarmee precies wat de doc-comment op `pleya_wire.dart:50-51` belooft. Er valt
> hier niets te repareren en er is dus ook geen uitrolvolgorde nodig: elke uitgeleverde build
> voldoet al aan de eis, ook een oude.
>
> Wat de poort daarmee nog moet sluiten, is niet een fix maar een meting. Laag C moet aantonen dat
> dat filter zich in een draaiende binary ook werkelijk zo gedraagt, op de vier meetpunten uit 11.2.
> Valt die meting uit zoals de code doet verwachten, dan is de poort dicht zonder codewijziging.
> Valt zij anders uit, dan is er alsnog een defect en komt de vraag naar een fix terug.

### 11.4 De fix is een PS-3-defect, en hij is generiek

Beslissing 1: dit is een bestaand defect in het gesloten PS-3 en geen PS-14-werk. De code spreekt
zijn eigen doc-comment tegen, en dat is waar met of zonder e-books. DEC-073 heeft dat onderscheid al
gemaakt voor de lege hubs `continue_watching` en `next_up`, aangemerkt als defect in het gesloten
PS-4 en gerepareerd terwijl PS-9 liep (commit `64efddd`). Dezelfde redenering, dezelfde uitkomst: de
fix mag landen vóór PS-14 en vóór het sluiten van PS-9.

**De regressietest gebruikt geen `books`.** Hij voert een fictieve toekomstige soort op, iets in de
orde van `kind: "sculptures"`, die in geen enkele fase voorkomt en dat ook nooit gaat doen. Dat is
het verschil tussen twee dingen die er hetzelfde uitzien:

- unknown-safety werkelijk repareren, wat de belofte is die het contract op `openapi.yaml:1119` doet
  voor elke soort die er ooit bij komt;
- een test schrijven die toevallig groen wordt zodra `books` bestaat, en daarmee e-booklogica
  vooruitbouwen onder de naam van een defectfix.

Een test op `books` zou bovendien de dag dat PS-14 landt van betekenis veranderen, want dan is die
soort niet meer onbekend. Dezelfde behandeling geldt voor de webkant in
`pleya_web/src/routes/libraries/+page.svelte:22`.

> **Correctie van 3 september 2026, na verificatie. Deze paragraaf vervalt en blijft zichtbaar staan
> omdat beslissing 1 erop rust.** Er is geen PS-3-defect. De client verbergt een onbekende soort al,
> één laag hoger dan waar de audit keek (`browse.dart:36-51`, op `main` sinds `8342a8b`), en de
> generieke regressietest bestaat al: `test/pleya_server/pleya_server_browse_test.dart:44` gebruikt
> de fictieve soort `music`, precies om de reden die hierboven staat, namelijk unknown-safety
> repareren zonder `books` vooruit te bouwen. De redenering over het verschil tussen een generieke
> test en een `books`-test blijft geldig; alleen is zij al toegepast en niet meer uit te voeren werk.
>
> Het DEC-073-precedent is daarmee niet nodig, en er komt geen commit uit deze beslissing voort. De
> webkant erft die behandeling niet: regel 22 kiest een icoon en beslist niets over zichtbaarheid,
> en de webbundel is lockstep met de binary. Wat daar moet gebeuren hoort bij PS-14 zelf, in de
> commit die `books` invoert. Zie de aanvulling in [hoofdstuk 5](#5-wat-de-code-vandaag-doet-en-waar-een-boek-doorheen-valt).

---

## 12. Acceptatiecriteria

De vier uit de fasetabel blijven staan en krijgen er drie bij. Beslissing 7 maakt criteria 5 tot en
met 7 canoniek: ze staan in de fasetabel in `docs/pleya-server-architecture.md` en niet alleen hier,
want een criterium dat alleen in een voorstel leeft telt bij het sluiten van een fase niet mee.

1. Een `books`-bibliotheek uit `PLEYA_SERVER_LIBRARIES` wordt gescand zonder dat de gedeelde
   scannertests wijzigen.
2. Een gebruiker zonder recht op die bibliotheek krijgt haar niet te zien en kan haar inhoud niet
   opvragen, aantoonbaar via dezelfde autorisatiematrix als de rest.
3. Een EPUB is via het protocol op te halen, met een herstartbare overdracht: hervatten via
   `Range`/`If-Range` slaagt zolang de sterke validator dezelfde representatie aanwijst, en begint
   opnieuw vanaf byte 0 zodra hij ontbreekt of afwijkt.
4. Het items-endpoint behandelt een `books`-bibliotheek niet langer als `movies`.
5. Een scan van een filmbibliotheek draait geen enkele EPUB-analyse, en een scan van een
   boekenbibliotheek draait geen enkele ffprobe. Aantoonbaar met een teller of een log, niet met een
   redenering.
6. `item_count` van een boekenbibliotheek telt publicaties, en de betekenis staat in `openapi.yaml`.
7. `scripts/check_protocol.sh` slaagt met het venster weer dicht, inclusief de
   `x-unknown-safe`-markering op elke nieuwe enum.

Criterium 5 is er omdat het risico van deze fase niet is dat er iets niet werkt, maar dat de gedeelde
scanlogica ongemerkt in tweeën gaat. Een teller die nul is, is daar het goedkoopste bewijs voor.

---

## 13. Stopcriterium

De fasetabel zegt: een boek op de NAS is via de API te vinden, te openen en op te halen door de
gebruiker die er recht op heeft. Scherper geformuleerd, zodat er niets aan uit te leggen valt:

> Op de NAS staat een boekenbibliotheek met echte EPUB-bestanden. Een gebruiker met leesrecht haalt
> de lijst op, opent één titel, krijgt de cover en haalt het bestand binnen. Een tweede gebruiker
> zonder recht op die bibliotheek krijgt op elk van die drie aanroepen een 404. Alles met `curl`
> tegen de draaiende container, zonder client.

**Wat de fase expliciet beëindigt, ook als er nog wensen liggen.** Er is geen reader, geen
leespositie, geen bladwijzer, geen boek in `/search`, geen boek in een hub, geen filter op auteur of
onderwerp, en geen beheerscherm. Staat een van die dingen er wel, dan is de fase niet af maar
overschreden, en hoort het eruit voordat er wordt afgesloten.

Datzelfde geldt een laag dieper, en dat is de aanscherping bij beslissing 2. De sterke validator hoort
erbij. Een downloadmanager, een model voor halve bestanden, een voortgangs-API of offline state horen
er niet bij, ook niet in aanleg, ook niet als de validator ze onderweg voor de hand laat lijken
liggen.

---

## 14. De zeven bindende beslissingen

Genomen bij de review van 3 september 2026. Ze zijn hierboven in de tekst verwerkt; deze lijst is de
korte vorm, niet een tweede versie ernaast.

**1. De onbekende bibliotheeksoort in de client is een bestaand PS-3-defect, geen PS-14-werk.**
Repareren onder het precedent van DEC-073, los van PS-14. De regressietest is generiek en gebruikt
een fictieve toekomstige soort, niet `books`, zodat er unknown-safety wordt gerepareerd en geen
e-booklogica vooruitgebouwd. Deze fix mag landen vóór PS-14 en vóór het sluiten van PS-9. Uitwerking
in [11.4](#114-de-fix-is-een-ps-3-defect-en-hij-is-generiek).

> **Correctie van 3 september 2026, na verificatie. Deze beslissing heeft geen werk meer en blijft
> staan zoals zij is genomen.** De bevinding eronder is onjuist en was dat al bij de goedkeuring:
> de client verbergt een onbekende bibliotheeksoort al vóór de mapper (`browse.dart:36-51`, op
> `main` sinds `8342a8b`), en de generieke regressietest met een fictieve soort bestaat al
> (`test/pleya_server/pleya_server_browse_test.dart:44`). Er is dus geen PS-3-defect, geen fix onder
> het DEC-073-precedent, en met dit voorstel geen toegestane codewijziging. De overige zes
> beslissingen zijn ongewijzigd van kracht.

**2. Acceptatiecriterium 3 blijft in PS-14, met een sterke validator en een eigen DEC.** Niet
herformuleren en niet doorschuiven naar PS-16. Hervatten via de gewone `Range`- en
`If-Range`-semantiek, uitsluitend wanneer de validator exact dezelfde EPUB-representatie aanwijst;
ontbreekt hij of wijkt hij af, dan wordt er niets gecombineerd en begint de overdracht vanaf byte 0.
De nieuwe DEC beschrijft expliciet hoe dit zich tot DEC-050 verhoudt, zonder impliciete uitzondering.
Dit wordt geen generieke offline-downloadlaag voor PS-16. Het DEC-nummer wordt pas op het moment van
committen bepaald, na een verse branchaudit: DEC-094 is niet gereserveerd, en landt dit besluit
eerder dan de hernummering op `feat/ebooks`, dan schuift die door. Uitwerking in
[hoofdstuk 8](#8-de-bytes-cover-en-epub).

**3. `item_count` telt publicaties.** De bestaande betekenis blijft: het aantal top-level entiteiten
dat de bibliotheek representeert, voor `movies` en `shows` de media-entiteiten, voor `books` de
publicaties. Nul teruggeven is semantisch onjuist zodra de server in die bibliotheek boeken toont.
Geen speciaal clientgedrag. Uitwerking in [hoofdstuk 9](#9-protocolwijzigingen).

**4. `SyncLibraries` mag een niet-lege bibliotheek niet van soort laten veranderen.** Leeg mag, niet
leeg weigert atomair met een duidelijke fout. Nooit gedeeltelijk migreren, nooit stilzwijgend
overschrijven. De leegtecontrole kijkt naar alle catalogusinhoud aan die bibliotheek en niet
uitsluitend naar de nieuwe tabellen. Dit is PS-14-scope omdat de derde soort het bestaande gevaar
bereikbaar maakt. Uitwerking in [hoofdstuk 10](#10-migratie-en-compatibiliteit-met-een-gevulde-database).

**5. Het laag-C-proxytuig gaat in de repository.** Bewijsinfrastructuur onder een bindende
protocolpoort, niet een debughack. Bij het acceptatietestgereedschap, buiten productiebuilds en
release-artefacten, deterministisch in wat het herschrijft en verder transparant. De builds en de
schermafbeeldingen blijven het bewijs; de proxy is het instrument. Uitwerking in
[11.2](#112-het-bewijsplan).

**6. PS-14 is goedgekeurd en niet actief.** De status is "goedgekeurd, geblokkeerd op PS-9" en
uitdrukkelijk niet "vrijgegeven voor uitvoering". Geen PS-14-productiecode totdat PS-9 formeel
gesloten is. Dat voorkomt de parallelle gate-erosie waarvoor de fasestructuur bestaat.

**7. Acceptatiecriteria 5, 6 en 7 worden canoniek onderdeel van de PS-14-fasetabel.** Geen ffprobe
op boeken, een correcte `item_count` voor `books`, en `check_protocol.sh` volledig groen met het
venster dicht. Uitwerking in [hoofdstuk 12](#12-acceptatiecriteria).

**De aanscherping op beslissing 2.** De regel "geen vooruitgebouwde onderlaag" geldt ook hier. De
sterke validator is PS-14-scope omdat criterium 3 hem nodig heeft. Een generieke downloadmanager, een
persistent model voor gedeeltelijk opgehaalde bestanden, een downloadstatus-API en elke vorm van
bladwijzer- of offline-state zijn dat nadrukkelijk niet.

### Wat er hierna nog moet gebeuren

Geen open besluiten meer, wel volgorde. De defectfix uit beslissing 1 mag nu (vervallen op
3 september 2026 na verificatie: er is geen defect, dus ook geen fix; zie de correctie bij
beslissing 1). PS-14 zelf wacht op het sluiten van PS-9. Het protocolvenster gaat pas open bij de uitvoering, en pas nadat de poort uit
[hoofdstuk 11](#11-de-poort-vóór-het-protocolvenster) met laag C gesloten is. De DEC onder beslissing
2 krijgt zijn nummer op het moment van committen.

---

## 15. Roadmap Drift Check op dit voorstel zelf

**Is er iets gebouwd dat niet in scope stond?** Nee. De enige wijzigingen in de repository zijn dit
bestand, de PS-14-fasetabel en DEC-093. Er is geen migratie, geen Go, geen Dart, en `openapi.yaml`
is niet aangeraakt. De defectfix uit beslissing 1 was toegestaan maar nog niet gemaakt; op
3 september 2026 bleek er niets te repareren, zodat er nu geen toegestane codewijziging is.

**Is er scope blijven liggen?** Ja, bewust. Het datamodel is op tabelniveau beschreven en niet op
kolomniveau, en bijdragers en onderwerpen zijn uitgesteld tot de detailresource ze nodig heeft. Wat
níét is blijven liggen zijn de besluiten: de zeven punten die eerder openstonden zijn beslist en
staan in hoofdstuk 14.

**Klopt de volgende fase nog?** Ja. PS-9 blijft de lopende fase en blokkeert PS-14 tot hij sluit.
PS-14 voegt geen afhankelijkheid toe aan een fase die al gepland staat, en de doorloop PS-5, PS-9,
PS-11A, daarna PS-6 tot en met PS-8 verandert niet. PS-7A krijgt er werk bij en PS-15 erft niets
vooruitgebouwds.
