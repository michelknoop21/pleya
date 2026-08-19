# Changelog

Sessie-voor-sessie logboek. Nieuwste bovenaan.

## [2026-08-19] PS-3: Pleya Server is een backend in de app

Vanaf hier staat een Pleya Server-bibliotheek náást Plex en Jellyfin, in dezelfde app, in dezelfde
zoekresultaten, op dezelfde schermen. Alleen lezen: bladeren, zoeken, bibliotheeklijsten, hubs en
artwork. Afspelen is PS-4 en zit er niet half in.

### Added
- **`MediaBackend.pleyaServer` en `ConnectionKind.pleyaServer`**, met een vijfde `MediaItem`-variant. `MediaBackend.fromString` kende de nieuwe waarde niet en zou hem stil als Plex hebben gelezen; de idlijst komt nu uit `values` in plaats van uit een tweede handgeschreven lijst, en er staat een test op.
- **Handgeschreven wire-types voor Pleya Protocol v1**, met een contracttest tegen dezelfde 25 fixtures en hetzelfde manifest als `check_protocol.sh`. Geen Dart-generator: die toevoegen is nieuwe infrastructuur zonder aangetoonde noodzaak.
- **Een authservice en een sessie.** Verversen is single-flight, want het refreshtoken roteert bij elk gebruik en twee gelijktijdige verversingen zijn per definitie hergebruik. Het nieuwe token wordt weggeschreven vóór het accesstoken wordt uitgedeeld.
- **`PleyaServerClient` met capabilities uit `GET /info`.** Een vlag staat aan als de server hem aanbiedt én deze build hem geïmplementeerd heeft. Vóór het eerste antwoord claimt de client niets, ook browse niet.
- **Bladeren met een cursorvertaling.** De app telt in offsets en het protocol pagineert met cursors; een ledger onthoudt welke cursor welke offset opende en de client loopt de rest, begrensd op tien pagina's.
- **Zoeken volgens DEC-045 en artwork via `GET /artwork/{id}`**, plus registratie in `multi_server_manager`, de profielbinder en het toevoegscherm.

### Changed
- **`data_aggregation_service` kreeg geen enkele regel**, en dat is nu een test. Een broncontrole faalt zodra die laag of `multi_server_provider` op een backend gaat vertakken.
- **De alfabetische sprongbalk staat op `AlphaBarMode.none`** en filters zijn er niet. Het bevroren contract kent geen `firstCharacter`-endpoint en geen filterparameter, en client-side over een gecursorde lijst filteren verplaatst het probleem naar de verkeerde kant van de grens. Zie G13 in de replacement matrix.
- **`watchlist_availability_resolver` telt Pleya Server niet mee** in de noemer van `coverageComplete`. Er is geen `external_ids` tot PS-7, dus `findByIdentity` kan er alleen null antwoorden, en meetellen zou betekenen dat een server die structureel niets kan beantwoorden toch als bevraagd geldt.

### Decisions
- [DEC-048](DECISIONS.md#dec-048-artwork-van-een-pleya-server-reist-met-een-header-via-een-register-per-origin): artwork reist met een bearer-header via een register per origin, aangehecht op het ene punt waar elke artwork-download langs komt. Het contract staat geen token in de querystring toe en blijft ongewijzigd.

### Tests
Honderdachtentachtig tests in `test/pleya_server/`, waaronder de zoekschermen op 390, 1440 en 1920
breed met TV-detectie aan, tegen een echte `PleyaServerClient` die tegen een nagebootste server praat
die het contract spreekt inclusief cursors. De volledige suite staat op 3695 en is groen;
`scripts/ci_checks.sh`, `scripts/check_protocol.sh`, `go vet ./...` en `go test ./...` ook.

**Niet gemeten:** de verbinding is niet tegen de draaiende server op de DS920+ gelegd. De stack
draait niet en er is niets uitgerold. De fase staat daarom op "ter goedkeuring" en niet op "gesloten".

## [2026-08-19] Het stopcriterium van PS-3W op de NAS, en de artworkmeting met getallen

De fase stond gesloten met de acceptatiecriteria beschreven maar twee ervan zonder meting eronder.
Die zijn nu gedaan, op de DS920+ en niet op een nagebootste stack.

### Tests
- **62 end-to-end-tests groen tegen de DS920+**, dezelfde suite die tegen de wegwerpstack draait, via `nas-tunnel.ts` en met de inloggegevens uit de omgeving. De echte bibliotheek draagt 563 items in drie bibliotheken, en zoeken op `sea` geeft daar 24 treffers zonder seizoenen. De limiter op `/auth/login` staat een suite van tweeënzestig inlogbeurten toe omdat een geslaagde poging de emmer teruggeeft (`internal/api/limiter.go:65`).
- **De artworkmeting op vijfhonderd posters.** 28 van 104 cellen bij binnenkomst, 500 uitstaande object-URL's en 7,3 MB heap tijdens het raster, 0 object-URL's en 1,8 MB erna, 0,2 MB verschil tussen ronde 1-5 en 6-10 van tien keer heen en weer. De drie voorwaarden uit onderdeel 4.2 van het voorstel zijn alle drie gehaald, in drie opeenvolgende ronden met dezelfde uitkomst.
- **De unauthenticated kant van de uitrol gemeten op de NAS zelf**: de bundel op `/`, de SPA-terugval op een frontendroute, `/healthz`, `/readyz` en `/pleya/v1` met voorrang, een jaar cache op een gehasht bestand en `no-cache` op `index.html`, de securityheaders aanwezig en geen CORS-header.

### Fixed
- **De artworkmeting kan niet meer stil de verkeerde bibliotheek pakken.** De eerste ronde koos een bibliotheek van twee items terwijl die van vijfhonderd er al stond, en het oordeel kwam op GEHAALD uit: twee posters ruimen altijd netjes op. `measure-artwork.ts` stopt nu met een fout zodra de grootste bibliotheek kleiner is dan het doelaantal.

### Changed
- **De eigenaar van de NAS-instantie is opnieuw ingericht.** Het wachtwoord was sinds 19 augustus nergens meer terug te vinden en PS-2 kent geen endpoint om het te wijzigen, dus kon niemand op die server inloggen. De bootstrap heeft hem opnieuw gezet; de inloggegevens staan nu in de vault. De catalogus, de bibliotheken en de media zijn niet aangeraakt.

## [2026-08-19] PS-2 en PS-3W gesloten, en de matrix telt weer wat er staat

Twee fasen stonden inhoudelijk af zonder formeel afgesloten te zijn. PS-2 droeg
`opgeleverd, ter goedkeuring` en had nooit een Roadmap Drift Check gehad; PS-3W had helemaal geen
statusrij en geen Uitkomst, terwijl PS-0 en PS-1 die allebei wel hebben. Beide zijn nu gesloten en
bevroren volgens dezelfde conventie, met de acceptatiecriteria per stuk en de drift check erbij.
Aan de besluiten van geen van beide fasen is iets veranderd.

De drift checks liepen langs de code en niet langs het geheugen. PS-2: geen provideraanroep, geen
uitgaande HTTP-client in `internal/`, en elf tabellen die één identiteit dragen. PS-3W: geen
`<video>`, geen kijkstatusaanroep, geen beheerendpoint en geen regel in `lib/`; de enige treffer op
`watch-state` staat in de gegenereerde `schema.d.ts` en komt dus uit het contract.

### Changed
- **De replacement matrix vertelde het tegenovergestelde van de repository.** Hoofdstuk 9.1 zei "er is nog geen regel servercode geschreven" terwijl er een catalogus en een webclient draaien. Zeventien capabilities staan nu op `Technisch gereed` en acht Plex-off blockers zijn dicht.
- **G5, G9 en G11 zijn uit de gattenlijst.** De PS-1-afwijking wees ze op 18 augustus toe aan PS-4, PS-3 en PS-2. Onderhoudsregel 3 vraagt een goedgekeurd voorstel plus een Phase ID, en aan beide is voldaan. G11 staat op `Technisch gereed` omdat PS-2 hem opleverde; G5 en G9 op `In roadmap`.
- **De tellingen zijn uit de tabel geteld en niet overgeschreven.** Twee ervan klopten niet: 9.1 gaf 24 blockers zonder fase waar hoofdstuk 7 er 22 gaf, en 22 plus vijftien niet-blokkerende gaps was 37 terwijl de tabel er 39 droeg. De nieuwe telling draagt een kolom "vorige ronde", zodat een verschil dat niemand kan verklaren opvalt als een telfout.

### Fixed
- **De alfabetische sprongbalk hing aan een fase die hem niet kan leveren.** De regel stond op `PS-1, PS-3`, terwijl het bevroren contract geen `firstCharacter`-endpoint kent. Hij was al een gap en is nu ook zonder fase.
- **Filters stonden op `In roadmap` bij PS-1 en PS-3, en dat kan niet.** `/libraries/{id}/items` draagt `limit`, `cursor` en `sort` en verder niets. De regel is nu **G13**, een Plex-off blocker zonder fase. Client-side filteren over een gecursorde lijst van duizenden items lost het niet op maar verplaatst het naar de verkeerde kant van de grens. Sorteren blijft wél bij PS-3: `title`, `added_at` en `year` staan in beide richtingen in het contract.

### Docs
- `CLAUDE.md` geeft PS-3 vrij en bevriest het protocol voor de duur van die fase.

## [2026-08-19] Vier integriteitsgebreken uit de PS-2-scanner

Een externe review vond vier gebreken in de PS-2-servercode. Geen ervan werd door een test gedekt,
en drie ervan kostten stilzwijgend data of toonden metadata die niet meer bij de bytes op schijf
hoorde. Het contract is niet aangeraakt.

### Fixed
- **Een gedeeltelijk gewandelde root veroorzaakt geen `MarkMissing` en geen `PruneEmpty` meer.** `filepath.WalkDir` doet `fs.SkipDir` zodra een map niet te lezen is, en dan ontbreekt de hele subboom in `seenPaths`. `MarkMissing` merkte die bestanden als verdwenen aan en `PruneEmpty` verwijderde daarna hun versies, met `ON DELETE CASCADE` de bestandsrijen erachteraan. De bestaande guard vangt alleen het alles-of-niets-geval: één gezien bestand van vijfduizend passeerde hem volledig. Een root die met een harde fout terugkomt telt nu ook als onvolledige dekking, en dan blijft het opruimen voor de hele bibliotheek achterwege.
- **Een mislukte analyse laat de versie, de duur en de sporen los**, volgens [DEC-047](DECISIONS.md#dec-047-een-mislukte-analyse-laat-de-versie-los). De faalvariant schreef de nieuwe inhoud weg en liet de metadata van de vorige staan, waardoor `PruneEmpty` het bestand als aanwezig bleef zien. Bij een gestapelde versie wordt de duur herberekend op de delen die het wel overleven.
- **Een verplaatste sidecar volgt het eigenaarschap dat uit zijn pad volgt.** Gelijke bytes leverden `actionUnchanged` op en dan werd het opnieuw koppelen overgeslagen, terwijl `anchors` zijn kaarten op de map en de basisnaam bouwt. Vindt de sidecar op zijn nieuwe plek geen eigenaar, dan wordt de oude koppeling losgemaakt in plaats van blijven staan.
- **Een cursor met een verkeerd getypeerde sorteersleutel levert `library.cursor_invalid` op** in plaats van een interne fout. De sleutel ging met een cast de SQL in en klapte daar op een typefout, die gewrapt in de default van `writeStoreError` viel. De numerieke sorteringen worden nu in `DecodeCursor` getoetst; voor `added_at`, waar de sleutel Postgres-tekst is en geen RFC3339, vertaalt een vangnet SQLSTATE `22P02` en `22007` naar dezelfde foutcode. Dat vangnet grijpt alleen met een cursor in het spel, zodat een ontbrekende tabel geen gebruikersfout wordt.

### Changed
- **De wandeling over een root is injecteerbaar**, net als de prober al was. De testcontainer draait als root, dus een map met `chmod 000` levert daar gewoon zijn inhoud op en een gedeeltelijk gelezen root was anders niet betrouwbaar na te bootsen.

### Tests
Acht regressietests erbij, vijf bij de fixes en drie uit de eindreview, alle acht eerst zien falen op
de regel die ze bewaken. Drieëntwintig tests in `internal/scanner` en `internal/catalog` draaien
zonder één overgeslagen test tegen een echte Postgres en dezelfde gepinde ffmpeg als de
productie-image. `go test ./...` en `go vet ./...` zijn schoon, en `verify-local.sh` komt op 62
geslaagd en 0 gefaald.

## [2026-08-19] G11 zat al in de PS-1-afwijking, dus de matrix wacht op de drift check

Een voorstel om edities als aparte roadmap deviation binnen PS-2 vast te leggen bleek een besluit te
herhalen dat er al lag. `docs/pleya-server-ps1-scope-deviation.md` wees G11 op 18 augustus aan PS-2
toe, begrensd tot de `{edition-...}`-conventie in de bestandsnaam, en de PS-2-implementatie blijft
binnen die grens. Er is dus geen tweede voorstel nodig en geen nieuwe DEC.

De implementatie is nagelopen in plaats van aangenomen: `internal/migrate/sql/0002_catalog.sql:97`
draagt de kolom op `media_versions`, `internal/nameparse/nameparse.go:38` leest de marker en strijkt
hem uit de titel, en `internal/scanner/scanner.go:562` en `:631` geven hem door aan `ResolveVersion`.
`TestParseMovie` en `TestMultipleVersionsAndEditions` slagen, de tweede tegen een echte Postgres met
ffprobe uit de testimage. Protocolimpact is er niet: `edition` staat al in het bevroren
`openapi.yaml` en in de fixture `item_movie_with_edition.json`, dus PS-2 vult een veld in dat PS-1
had vastgelegd.

Wat wel openstaat is boekhouding, en die is breder dan G11. Hoofdstuk 5 van de replacement matrix
zet G5, G9 en G11 nog op `Roadmap gap` terwijl hoofdstuk 7 hun fase al noemt. Onderhoudsregel 1 laat
de status verspringen bij het afsluiten van een fase, en PS-2 loopt nog, dus dit gaat mee in de
Roadmap Drift Check van PS-2: Phase ID erin, de drie uit de gattenlijst, de telling in 9.1 van 37
naar 34 gaps en van 24 naar 21 blockers zonder fase, en de zin dat er nog geen regel servercode
geschreven is eruit.

Geen bestand in `pleya_server/` of `docs/` gewijzigd door deze ronde.

## [2026-08-19] PS-2 bouwt de read-only catalogus

Een Go-service die een bestandsboom scant, de catalogus in Postgres bijhoudt en de leeskant van het
protocol serveert. Elfduizend regels Go in negentien testbestanden en drie migraties. Het contract
uit PS-1 is niet aangeraakt.

### Added
- **Twaalf tabellen in drie migraties**, uitgevoerd bij het opstarten met een advisory lock, een checksum per toegepaste migratie, en een weigering te starten als de database nieuwer is dan de binary. `/readyz` wordt pas groen nadat ze gedraaid zijn.
- **De scanner met de drie lagen uit hoofdstuk 7.3.** Eén `stat` per bestand; bij verschil of bij een mount waar de inode niets betekent een hash over kop en staart plus de grootte; en alleen daarna ffprobe. Een tweede ronde zonder wijzigingen schrijft geen enkele rij in `media_files`.
- **ffprobe met een detectionStatus en een source per veld**, volgens hoofdstuk 7.4, opgeslagen als `jsonb`. De lijn draagt het nog niet; dat is PS-6. Wat er niet gebeurt is interpreteren: `color_transfer` en het Dolby Vision-configuratierecord gaan er rauw in, want er een HDR-oordeel van maken is planner-beleid.
- **Negen leesendpoints**, met cursorpaginering, sorteren, zoeken over alle bibliotheken, home-bouwstenen, en het leveren van artwork en losse ondertitels van schijf.
- **De bootstrap-auth uit specificatie 6.5.** Een setupcode op de console bij de eerste start, Argon2id in PHC-vorm, refreshtokens die roteren met hergebruikdetectie, en een streamtoken dat één mediaresource opent en verder niets. De ondertekensleutel staat in `/config` met rechten 0600 en niet in Postgres.
- **Een jobrunner in dezelfde database**, met `FOR UPDATE SKIP LOCKED`, backoff met een dak, en een dedupe key die een tweede scanverzoek voor dezelfde bibliotheek eruit houdt zolang het eerste loopt.
- **ffmpeg 5.1.9 in de image**, op een exacte versie gepind.
- **`scripts/verify-protocol.sh`**, dat de antwoorden van een draaiende server vastlegt en met `scripts/check_server_responses.py` tegen hetzelfde `openapi.yaml` houdt waar ook de fixtures tegen valideren. Negentien antwoorden, acht schema's, alle gedekt.
- **`scripts/test-db.sh` en `scripts/test-image.sh`**, die een wegwerp-Postgres en een Go-toolchain met dezelfde gepinde ffmpeg klaarzetten. Staan ze er niet, dan slaan de tests zichzelf over in plaats van te falen.

### Changed
- **`scripts/verify-local.sh` telt veertien secties** in plaats van dertien. De nieuwe sectie zet de catalogus neer met ffmpeg uit de image zelf, wisselt de setupcode in, bladert erdoorheen, controleert dat streaming en kijkstatus 404 geven, en herstart de container om te zien of de ids blijven staan.
- **`compose.yaml` kent een tweede mediavolume.** De bibliotheek op deze NAS staat over btrfs en fuseblk.ntfs verspreid, en juist dat verschil is wat de scanner moet meten.

### Zes besluiten
`DEC-040` tot en met `DEC-045`. De grouping key is geen identiteit en heet daarom niet zo. Media,
ondertitels en artwork delen één bestandstabel, want die 5578 losse `.srt`-bestanden hebben dezelfde
goedkope detectie nodig als de media ernaast. De jobtabel is eigen werk en beantwoordt de open vraag
uit 17.1 niet. De inodebetrouwbaarheid staat per root in de database, wordt gemeten en niet
aangenomen, en een gunstige ronde zet een root niet vanzelf op vertrouwen. Debians `ffmpeg` blijft in
de image, met PS-8 als vastgelegd moment om `--disable-avdevice` mee te nemen. En zoeken levert
standaard films, series en afleveringen, geen seizoenen.

### Wat er groter van werd
De image gaat van 81 MB naar 543 MB, gemeten met `du -sx /` in de amd64-image. Daarvan is 459 MB
gedeelde bibliotheken, en 159 MB daarvan zijn Mesa, LLVM, z3 en de DRI-drivers die Pleya nergens voor
gebruikt. Ze komen mee via een keten die van begin tot eind uit harde `Depends` bestaat, dus
`--no-install-recommends` verandert er niets: `ffprobe → libavdevice59 → libgl1 → libglx0 →
libglx-mesa0 → libgl1-mesa-dri → libLLVM-15 + libz3`. `libavdevice` is de component voor webcams en
schermopname, die een mediaserver niet aanraakt, maar Debian linkt hem mee in `ffprobe`. Zelf bouwen
met `--disable-avdevice` scheelt die 159 MB en verlegt de CVE-bewaking van Debian naar ons; dat
gebeurt bij PS-8, dat de ffmpeg-bouw toch aanraakt voor QuickSync. Zie `DEC-044`.

### Zoeken laat seizoenen eruit
Op de echte bibliotheek levert `sea` 24 bruikbare treffers naast 396 seizoenen, en `season` er 5
naast diezelfde 396. Een seizoen heet `Season 3` en draagt niets van wat iemand intypt: hij matcht
alleen op termen die toevallig in het woord `Season` zitten, en dan komen ze met honderden tegelijk.
Zonder `kind` levert `GET /pleya/v1/search` daarom `movie`, `show` en `episode`; met `kind=season`
komen seizoenen gewoon terug, en verder staan ze in `/items/{id}/children`. Afleveringen blijven erin,
want die hebben een echte titel. Hoofdstuk 10 en de `description` van `/search` zeggen dat nu ook. De
wijziging is langs de zes compatibiliteitsregels getoetst: geen veld erbij of weg, `kind` blijft
optioneel en behoudt zijn betekenis, `ItemKind` ongewijzigd. Zie `DEC-045`.

### Wat er bewust niet in zit
Geen streaming, geen kijkstatus in welke richting dan ook, geen metadata-providers, geen afspeelplan,
geen gebruikersmodel. `GET /pleya/v1/stream/{version_id}` en beide kijkstatus-endpoints geven een 404,
en `capabilities.watch_state` staat op `false`. Poort 3 en poort 4 zijn niet aangeraakt en staan nog
steeds open.

### Op de echte bibliotheek
Uitgerold op de DS920+ en over de volledige bibliotheek gedraaid: 28.986 bestanden, 6.951 analyses,
7.300 items, nul fouten. Elke ronde daarna draaide ffprobe geen enkele keer en de item-ids waren na
een herstart byte-identiek. In rust merkt de scanner nog 108 bestanden als gewijzigd aan, en dat is
exact het aantal dat nergens aan hangt; de andere 28.878 worden met rust gelaten. Kids staat volledig op btrfs en was in nul seconden klaar; Films en Series
staan op de NTFS-schijf, waar laag 2 voor elk bestand draait en samen 10,7 GB leest tegen ongeveer
6 MB/s.

Die ronde legde ook drie fouten in de naamherkenning bloot, samen goed voor 5.841 van de 19.450
losse bestanden die nergens aan hingen. De afleveringsminiatuur `<aflevering>-thumb.jpg` viel buiten
de lijst met achtervoegsels, en dat zijn er 5.001. Een taal met een teller erachter (`nl_2`, `nl_3`)
werd niet als taal gelezen. En een onbekend woord achter de taal (`.nl.synced.srt`) brak de
ontleding af, waarna de naam van het mediabestand niet meer klopte.

De derde is de interessante, want het was een volgordefout. Zolang niet vaststaat welk mediabestand
erbij hoort moet elk onbekend woord als deel van de titel gelden, anders eet de ontleding de naam
op. De scanner zoekt nu eerst op een steeds kortere prefix tegen de mediabestanden die werkelijk in
die map staan, en leest taal en markeringen pas daarna uit wat erachter staat. Wat overblijft zijn
echte wezen: mappen met alleen een poster waar de film niet meer staat, en Plex-restanten waar de
geoptimaliseerde versie verdwenen is maar de ondertitel bleef.

Wat de ronde niet beantwoordde is de inodevraag zelf. Een herstart van de container laat de mount
staan, dus dat het aantal mismatches nul bleef bewijst niets. Daarvoor is een reboot of een
`umount` gevolgd door `mount` nodig.

### Verificatie
`scripts/check_protocol.sh` onveranderd groen. `scripts/verify-local.sh`: 54 controles.
`scripts/verify-protocol.sh`: 19 antwoorden tegen `openapi.yaml`, alle acht schema's gedekt. De
acceptatiecriteria staan als test: duizend bestanden scannen volledig, een tweede ronde draait
ffprobe nul keer, een hernoemd bestand behoudt zijn item-id, en `/readyz` wordt pas groen na een
geslaagde migratie.

## [2026-08-18] PS-1 goedgekeurd en bevroren, PS-2 vrijgegeven

Twee poorten dicht. De goedkeuring was inhoudelijk akkoord met het contract, met de opdracht om drie
formuleringen hard te maken voordat het dichtging. Alle drie zijn compatibiliteits- of
beveiligingsinvarianten; geen ervan voegt een endpoint, een veld of een categorie persistente state
toe.

### Changed
- **"Een veld toevoegen mag altijd" verzweeg twee gevallen.** Hoofdstuk 3 telt nu zes regels in plaats van vier. Een nieuw veld mag in een antwoord. Een nieuw verplicht veld in een aanvraag is breken, in de querystring net zo goed als in de body. En omdat elk verzoekschema `additionalProperties: false` draagt wijst een server een nieuw optioneel aanvraagveld af in plaats van het stil te laten vallen, dus een client stuurt zo'n veld pas nadat `capabilities` of `feature_level` zegt dat de server het kent.
- **Enums hadden geen uitspraak.** Een nieuwe waarde is alleen compatibel waar het veld unknown-safe is. Vier velden zijn dat: `auth.methods[]`, `Library.kind`, `Item.kind` en `SubtitleStream.format`, elk met de vastgelegde terugval dat een client de waarde overslaat in plaats van te falen. De rest is gesloten, inclusief `profile` en de enums in een aanvraag.
- **Hoofdstuk 6.5 benoemde welke auth-state mag bestaan, niet hoe die bewaard wordt.** Vier eigenschappen liggen nu vast, omdat ze de opslagvorm bepalen en na PS-2 een migratie kosten: de setupcode is kortlevend en eenmalig en staat persistent niet leesbaar opgeslagen; een refreshtoken is een ondoorzichtig geheim waarvan alleen een niet-terugrekenbare identificatie met vervalmoment en ingetrokken-vlag in de database staat; de Argon2id-parameters van een bestaande hash staan in de hash zelf, dus verifiëren hangt niet van de configuratie af en zwaarder hashen vraagt geen schemawijziging; en de ondertekensleutel leeft alleen in de eigen persistente `/data`, niet in Postgres en niet in Git.
- **Architectuur 12.3 en 16.3 lopen mee**, zodat de baseline en de specificatie hetzelfde zeggen. 16.3 zei dat de Argon2id-parameters in de configuratie staan; dat klopt voor een nieuwe hash en niet voor het verifiëren van een bestaande.

### Added
- **`x-unknown-safe` op elk enum in `openapi.yaml`**, met een controle in `scripts/check_protocol.py` die een enum zonder die markering afkeurt. Zonder die controle erft een nieuw enum-veld stilzwijgend een keuze die niemand gemaakt heeft; nu dwingt het veld de keuze af op het moment dat het wordt toegevoegd. Alle acht enums dragen hem.

### Poorten
Poort 1 (wire-contract) en poort 2 (bootstrap-authflow) zijn dicht, vastgelegd in
`docs/pleya-server-gates.md`. Poort 3 (conflictmodel voor kijkstatus) en poort 4 (byte-validator
achter de `ETag`-belofte) blijven open en horen dicht vóór PS-4. Ze raken PS-2 niet.

### PS-1 is bevroren
Zolang PS-2 gebouwd wordt verandert er niets cosmetisch aan het protocol. Legt PS-2 een echt probleem
bloot, dan is dat een protocolwijziging met een compatibiliteitstoets langs de zes regels, en geen
aanpassing in de YAML omdat het zo uitkomt.

### Verificatie
`scripts/check_protocol.sh` in de gepinde container: OpenAPI 3.1 geldig (16 paden), alle
verwijzingen komen uit, alle acht enums dragen `x-unknown-safe`, 25 fixtures valideren, en de drie
ingevoerde fouten worden alle drie afgekeurd.

## [2026-08-18] PS-1 legt het wire-contract vast, en vindt onderweg vier gaten

Alleen tekst en schema's, zoals de fase voorschrijft. Geen regel Go of Dart.

### Added
- **`docs/pleya-protocol/v1/openapi.yaml`**, contractueel leidend. Zeventien endpoints: ontdekken, authenticeren, bladeren, zoeken, home-bouwstenen, artwork, ondertitels, streamen en kijkstatus. OpenAPI 3.1 en geen losse JSON-schema's, omdat die alleen bodies dekken terwijl methode, pad, headers, authenticatieklasse, `Range`, `If-Range`, statuscodes en responseheaders net zo goed contract zijn.
- **`docs/pleya-protocol-v1.md`**, de prozaspecificatie die uitlegt en motiveert. Botsen de twee, dan wint het contract en is de proza de fout.
- **25 fixtures plus een manifest** onder `docs/pleya-protocol/v1/examples/`. Ze zijn de koppeling tussen de fasen: PS-2 valideert zijn antwoorden ertegen, PS-3 draait er contracttests mee, en beide lezen hetzelfde manifest.
- **`scripts/check_protocol.sh`**, dat het document als OpenAPI 3.1 valideert in een gepinde container, controleert dat elke verwijzing uitkomt, elke fixture tegen zijn schema toetst, en drie plausibele fouten invoert om te bewijzen dat de validator werkelijk afkeurt.
- **`DEC-030` tot en met `DEC-037`**, geschreven zoals hoofdstuk 24.1 voorschrijft zodra fase 1 wordt ingepland.
- **`docs/pleya-server-gates.md`**, met de vier uitvoeringspoorten en hun stand.

### Vier gaten in de architectuur gesloten
- **Snake_case op de lijn, zonder uitzondering.** Elk JSON-blok in hoofdstuk 12 is snake_case, maar 7.4 schrijft `detectionStatus` en 18 `deliveryMode`. Die twee heten op de lijn `detection_status` en `delivery_mode`.
- **Artwork had geen fase.** 12.2 noemt het niet als PS-1-oppervlak en metadata staat in PS-7, terwijl PS-3 een bladerscherm tekent. De vorm ligt nu in PS-1 vast en de inhoud komt in PS-2 uit de 2923 `.jpg`-bestanden die al op schijf staan.
- **Een versie met meerdere bestanden had geen regel.** Die blijft geldig in het domeinmodel; `file_count` staat op elke versie en alleen direct play begrenst zich in v1 tot één bestand. De begrenzing zit in de levering en niet in het model, zodat aaneenschakeling later geen catalogusmigratie vraagt.
- **Meerdere bereiken in één `Range`.** Pleya bouwt geen `multipart/byteranges` en antwoordt met het volledige bestand als `200`. Dat is de toegestane terugval; een `416` zou een speler breken die het toch probeert.

### Twee dingen die het contract sluiten
- **De bootstrap-authflow.** Het protocol geeft tokens uit terwijl PS-2 geen `users` en geen `sessions` heeft. Hoofdstuk 6.5 somt daarom uitputtend op welke persistente auth-state een server wel mag hebben: één credential met Argon2id, een ondertekensleutel op schijf en niet in de database, per refreshtoken een identificatie met vervalmoment en ingetrokken-vlag, en de setupcode. Meer niet.
- **Kijkstatus heeft nu ook een leescontract.** De toestand reist mee als `user_state` in elk itemantwoord, plus een lijstendpoint met `updated_since` voor de offline-laag. `session_id` is client-generated, want er zijn bewust geen serverzijdige playbacksessies en zonder die regel had het veld geen herkomst.

### De vierde poort is nieuw en is de zwaarste
De belofte in hoofdstuk 11.1 dat de `ETag` verandert zodra de bytes veranderen volgt **niet** uit
`(MediaFile.id, generation)`. `generation` loopt alleen op wanneer de drielagige detectie iets
aanmerkt, en laag 2 is een hash over de eerste en de laatste megabyte. Hoofdstuk 7.2 zegt zelf dat
zo'n signature nooit gelijkheid bewijst en noemt precies het geval: een remux die het midden
verandert terwijl kop en staart intact blijven. Dat bestand houdt dan dezelfde `ETag`, `If-Range`
slaagt, en de speler plakt oude en nieuwe bytes aan elkaar. De validatorstrategie moet vastliggen
vóór PS-4, en elk bestand volledig hashen is niet de enige uitweg en waarschijnlijk niet de juiste.

### Roadmap Drift Check
Geen implementatie in Go of Dart. Geen `PlaybackPlan`, geen transcode-sessies, geen downloads, geen
gebruikers of rechten, geen wijziging aan `share_server`. Er staat geen endpoint in het contract dat
alleen een latere fase nodig heeft.

## [2026-08-18] PS-0 Docker Foundation draait op de DS920+ naast Plex

De eerste servercode. De service doet niets, en dat is de bedoeling: wat hier faalt ligt aan de
container en niet aan het product.

### Added
- **`pleya_server/`**, een Go-service met vier pakketten. Configuratie uit omgevingsvariabelen met een werkende default voor alles behalve de databaseverbinding, gestructureerde JSON-logs met een `component`-veld, een lui verbindende `pgxpool`, en `/healthz` plus `/readyz`. Het onderscheid tussen die twee is het punt: `/healthz` zegt of het proces leeft en wordt niet rood van een database die even weg is, `/readyz` pingt en geeft 503 zodra dat niet lukt. Omdat de pool lui verbindt houdt een Postgres die tien seconden later opkomt de server niet tegen, en is er geen retrylus nodig.
- **`internal/mounts`**, dat bij elke start per pad meet of hij bestaat, leesbaar en beschrijfbaar is, read-only gemount staat en op welk bestandssysteem hij ligt. Het bestandssysteemtype staat erbij omdat de verandersdetectie van de scanner straks op stabiele inodes leunt en een van de mediamounts op deze NAS `fuseblk.ntfs` is.
- **Multi-stage image op Debian bookworm-slim**, non-root, met de binary als eigen healthcheck omdat er geen curl in zit. Debian en geen Alpine is een keuze voor later: hoofdstuk 22 vraagt om een gepinde ffmpeg, en de Intel-mediastack die de DS920+ nodig heeft is op glibc een pakket. Er zit nu nog geen ffmpeg in.
- **Compose-stack met Postgres 18.6 zonder hostpoort**, in een eigen privaat netwerk, met drie schrijfbare mounts voor drie verschillende levensduren: `/config` duurzaam en de back-up-eenheid, `/cache` herbouwbaar, `/transcode` vluchtig. Op één volume neemt een vollopende scratch de database mee.
- **`scripts/verify-local.sh`**, dertien stappen van broncode tot draaiende stack, en `scripts/go-tool.sh`, dat de toolchain in de gepinde builder-image draait zodat er geen Go op de ontwikkelmachine hoeft te staan.
- **`docs/pleya-server-ps0-proposal.md`**, de goedgekeurde afwijking met de zes onderdelen uit 23.1, plus PS-0 als fase in het architectuurdocument.

### Gemeten op de DS920+
- PostgreSQL 18.6 draait op **kernel 4.4.302 met cgroups v1**. Dat was het grootste onbewezen risico van de hele opzet.
- `read_only` en `cap_drop: ALL` worden werkelijk toegepast: schrijven naar `/` faalt en `CapEff` is `0000000000000000`. `no-new-privileges` is gezet maar op deze kernel niet uit `/proc` af te lezen.
- Idle **0,00% CPU en 10,6 MiB** voor de server, 0,00% en 27,3 MiB voor Postgres. Plex stond op hetzelfde moment op 2,03% en 1,495 GiB.
- Media lezen lukt, schrijven geeft `Read-only file system`. Persistentie overleeft een herstart, uitval van de database maakt `/readyz` rood en herstel maakt hem weer groen zonder rebuild, en SIGTERM geeft exitcode 0.
- Plex draaide er ongewijzigd naast, voor en na.

### Fixed
- **Postgres 18 zet `PGDATA` op `/var/lib/postgresql/18/docker`**, niet meer op `/var/lib/postgresql/data`. Het volume aan het oude pad hangen levert een stack op die draait en niets bewaart, en dat was pas bij de persistentietest opgevallen.
- **`statfs` meldt een read-only bind mount als beschrijfbaar** op de laag die Docker Desktop gebruikt, omdat die `ST_RDONLY` niet doorgeeft. De `:ro`-controle leest daarom `/proc/self/mountinfo`, wat meteen een echte bestandssysteemnaam per mount oplevert in plaats van een magic.

### Niet gebouwd
Geen protocol, geen `/pleya/v1`, geen schema, geen tabel, geen scanner, geen ffprobe, geen ffmpeg,
geen metadata, geen streaming, geen kijkstatus, geen gebruikers, geen authenticatie. De replacement
matrix is inhoudelijk niet aangeraakt.

### Gesloten
PS-0 is gesloten en bevroren. De drift check is schoon: geen tabel, geen protocolendpoint en geen
ffmpeg in de image, en `lib/`, `server/` en `share_server/` zijn niet aangeraakt. Er gaat niets meer
bij aan de fundering voordat serverfunctionaliteit erom vraagt, en de 93 MB image blijft zoals hij
is omdat de glibc-basis voor de latere ffmpeg-route gekozen is.

`no-new-privileges` staat als verificatiebeperking van DSM 7.3.2 genoteerd en niet als openstaand
punt: de optie wordt toegepast, alle capabilities zijn weg en het proces draait non-root. De
`fuseblk.ntfs`-mount blijft bewust ongemeten; dat is een vraag van PS-2, die de meting kant en klaar
aantreft omdat de server bij elke start het bestandssysteemtype per mediamount logt.

## [2026-08-18] De replacement matrix maakt zichtbaar wat er nog tussen Pleya Server en Plex-off staat

Document-only. De roadmap is niet gewijzigd; de gaten zijn vastgelegd als bevinding.

### Added
- **`docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md`**, 156 capabilities over 17 domeinen, opgebouwd uit de codebase en niet uit kennis van Plex. Bronnen zijn `lib/media/media_server_client.dart` (ruim tachtig members), de twintig vlaggen in `lib/media/server_capabilities.dart` die elk hun Plex-endpoint benoemen, de aparte Live TV-interfaces, en `lib/metadata_edit/` voor de schrijfkant. Per capability staat er wat Plex vandaag levert, wat Pleya Server ervoor in de plaats zet, welke van de drie bestemmingen dat is, welke fase hem draagt, zijn status, of hij de Plex-off gate blokkeert, en waaraan je ziet dat hij klaar is.
- **Hoofdstuk 25 in het architectuurdocument: Definition of Done en `PLEX_OFFLINE_REPLACEMENT_GATE`.** Volwaardig betekent dat elke blocker op Productgereed staat, dat de gate slaagt zonder één runtimeaanroep naar Plex, en dat geen enkele overige capability bij vrijgave nog op onbekend staat. De gate heeft zeven categorieën en één rode maakt hem rood. Erbij hoort de harde regel dat alleen het migratiegereedschap, de Plex-adapter en een in de fase beschreven tijdelijke fallback Plex mogen lezen; verborgen fallback wordt niet geaccepteerd.
- **Hoofdstuk 1.1: het einddoel is niet onderhandelbaar.** Met de regel die de rest beschermt: "niet in deze fase" is iets anders dan "niet nodig voor het eindproduct". Een functie verdwijnt niet uit het eindproduct omdat hij nog geen Phase ID heeft.
- **PS-1 kreeg één ontwerpcontrole**, en verder niets. Scope, out-of-scope, acceptatiecriteria en stopcriterium zijn ongewijzigd. De vraag bij elke fundamentele protocolkeuze is of hij later uitbreidbaar is naar de replacement-capabilities zonder breaking herbouw. Nee betekent de blocker rapporteren, niet de latere feature alvast specificeren.

### Changed
- **23.1 kijkt nu twee kanten op.** De bestaande anti-driftregel verbood vooruitbouwen. Erbij komt het spiegelbeeld: schrap, versimpel of herdefinieer ook geen latere productvereiste omdat die nu niet nodig is, en een keuze die een latere essentiële serverfunctie onmogelijk of onevenredig duur maakt is een architectuurblocker. Samengevat: build for extension is niet hetzelfde als build the extension early.
- **`CLAUDE.md` kreeg een zevende werkregel** plus dezelfde bidirectionele scope-discipline, zodat de matrix de bron is bij twijfel of iets nog bij het eindproduct hoort.

### Notes
- **De telling is de eigenlijke opbrengst.** 104 van de 156 capabilities zijn Plex-off blocker. Achtenzeventig daarvan hangen aan een bestaande fase; zesentwintig aan geen enkele, waarvan twee eerst een productbesluit vragen. In totaal zijn er 37 roadmap gaps en 11 open productbesluiten.
- **Twaalf gaten met de grootste gevolgen**, gegroepeerd: verzamelingen en afspeellijsten (volledige CRUD in de client, nergens in de roadmap), kijkgeschiedenis, favorieten en waarderingen, intro- en aftitelingsmarkers, externe ondertitels als sidecar, bibliotheekbeheer vanuit de client, back-up en restore en upgrade en terugrollen, de faalpaden als samenhangend geheel, home-rijen, beoordelingen, edities, en afspeellijsten in de migratie.
- **Twee fasen spreken elkaar tegen over realtime.** Hoofdstuk 14 beschrijft een websocket-hub, PS-2 zet hem expliciet buiten scope, en PS-11 gaat ervan uit dat hij bestaat ("websockets door de proxy"). Geen enkele fase bouwt hem. Het is geen blocker, want elk event is ook op te halen met een gewone aanroep, maar de tegenstrijdigheid hoort weg voordat PS-11 begint.
- **Vier fasen kunnen technisch gereed zijn terwijl het product dat niet is:** PS-2, PS-4, PS-7 en PS-11. Daarom meet de gate op productniveau en niet op endpointniveau.
- Nagelopen: alle interne ankers in beide documenten resolven, de twintig `ServerCapabilities`-vlaggen komen alle twintig in de matrix terug, en de anti-slop-check is schoon. Bekend en niet in dit spoor gerepareerd: de verwijzingen `DECISIONS.md#dec-014` en `#dec-025` gebruiken de projectconventie van een kort anker, dat GitHub niet resolvet naar de volledige kop.

## [2026-08-18] Het architectuurdocument is een goedgekeurde baseline, en de werkregels staan in CLAUDE.md

Document-only. Spoor gesloten; de eerstvolgende beslissing is wanneer PS-1 wordt vrijgegeven.

### Changed
- **`docs/pleya-server-architecture.md` draagt bovenaan zijn eigen status.** Architectuurbaseline goedgekeurd, uitvoering niet vrijgegeven. Dat voorkomt dat een sessie maanden later het document als eerste concept behandelt en fundamentele keuzes opnieuw openbreekt.
- **De twee open vragen zijn gates geworden** in plaats van losse aandachtspunten. Hoofdstuk 24.2 opent met een tabel: het conflictmodel voor kijkstatus moet beslist zijn voordat PS-4 begint, en de regel voor de content fingerprint voordat er scannerlogica komt die op relocatie leunt. Een fingerprint die later van definitie verandert maakt elke eerder vastgelegde koppeling onbetrouwbaar.
- **`STATUS.md` noemt nog één concrete vervolgactie.** PS-1 start pas na expliciete vrijgave, en die komt na 2.8.0.

### Added
- **Een sectie in `CLAUDE.md` met de werkregels voor elk Pleya Server-werk.** Zes regels: eerst hoofdstuk 23 plus de eigen fase lezen, uitsluitend binnen de huidige Phase ID werken, de roadmap niet stilzwijgend wijzigen, geen werk uit een latere fase vooruit voeren, bij een noodzakelijke afwijking eerst een deviation proposal, en stoppen bij het stopcriterium. Die staan daar en niet in het architectuurdocument zelf, omdat `CLAUDE.md` elke sessie meelaadt en de discipline dus niet afhangt van wat er nog in het contextvenster past.

## [2026-08-18] Reviewronde op het architectuurdocument: acht aanscherpingen vóór implementation freeze

Document-only, `docs/pleya-server-architecture.md`. De architecturale kern is ongewijzigd; wat er
veranderde zijn de grenzen die tijdens implementatie het makkelijkst vervagen.

### Changed
- **Fase 1 mag niet langer vooruitontwerpen.** Hoofdstuk 12.2 legt vast dat PS-1 uitsluitend het protocoloppervlak specificeert dat nodig is tot en met PS-4, met een tabel die per oppervlak de fase noemt die het introduceert. De transcode-sessie-endpoints in hoofdstuk 11.2 waren daar een schending van en staan nu als voorgenomen vorm, vast te leggen in PS-8.
- **`feature_level` is ondergeschikt aan `capabilities`.** Level N betekent uitsluitend dat de implementatie alle protocolfeatures tot en met N begrijpt, en nooit dat een functie beschikbaar is. Een client die uit een hoog level afleidt dat transcoding bestaat terwijl de capability `false` is, redeneert fout.
- **Scan-signature, `MediaFile.id` en content fingerprint zijn drie dingen** (hoofdstuk 7.2, nieuw). Een hash over kop en staart bewijst niets over het middenstuk, dus hij mag nooit op zichzelf "gegarandeerd hetzelfde bestand" betekenen. De signature is een scanoptimalisatie, de id is de identiteit, en de fingerprint is apart bewijs voor relocatie tussen mounts.
- **`confidence` is vervangen door `detectionStatus` plus `source`.** Eén generieke score van hoog tot laag verbergt dat een `inferred` Dolby Vision-profiel gevaarlijker is dan een `inferred` kanaalindeling. De statussen zijn `confirmed`, `inferred` en `unknown`; de bronnen zijn opgesomd. Beleid hangt aan de combinatie van eigenschap en status.
- **De planner is een filter met een score, geen boom van takken.** Harde beperkingen elimineren kandidaatplannen, zachte voorkeuren scoren wat overblijft, en een lege verzameling is een expliciete fout met reden in plaats van wat de laatste `else` toevallig oplevert.
- **Redenen zijn domeincodes met parameters**, bijvoorbeeld `audio.truehd_passthrough_unsupported` met bron- en doelcodec. Een i18n-sleutel van de app in een serverantwoord zou het hernoemen van een vertaalsleutel tot breaking change maken.
- **Bootstrap-identiteit staat los van multi-user** (hoofdstuk 13.1a, nieuw). Vóór PS-9 bestaat er precies één server-owner-identiteit, zonder profielen, rollen of bibliotheekrechten. Dat voorkomt dat fase 2 alvast `users` en `sessions` aanlegt omdat er toch tokens nodig zijn.
- **Streamtokens zijn kortlevend en smal, niet eenmalig.** Een speler doet een `HEAD`, een openingsrange, een range per seek, retries en bij HLS een request per segment; een token dat na de eerste verzilvering vervalt breekt op de tweede. Nu twee tot vijf minuten geldig, gebonden aan gebruiker, resource en eventueel sessie.
- **De `ETag` hoeft geen contenthash te zijn.** De eis is dat de validator verandert zodra de bytes veranderen; `(MediaFile.id, generation)` voldoet. Een hash over tachtig gigabyte berekenen om een header te zetten is precies het werk dat een NAS onbruikbaar maakt.
- **`transcode_workers` is uit v1 verdwenen.** De vorm van die tabel volgt uit keuzes die nog niet gemaakt zijn (registratie, capabilities, push of pull, opslagzicht, segmentroutering), dus hem nu ontwerpen levert een verkeerde tabel op die daarna meereist. Fase 8 krijgt een lokale executor, fase 13 voegt de tabel toe met een migratie.

### Added
- **23.1 kreeg er een anti-driftregel bij.** Een latere fase mag geen datamodel, interface of infrastructuur afdwingen in een eerdere fase uitsluitend om een migratie te vermijden. Bouw voor uitbreidbaarheid, bouw de uitbreiding niet vooruit. Die regel houdt zowel `transcode_workers` als het sessiecontract uit fase 1.
- **Twee open vragen erbij.** Het conflictmodel voor kijkstatus moet beantwoord zijn vóór PS-4: "hoogste positie wint" faalt zichtbaar wanneer iemand een film bewust opnieuw begint, dus kijkstatus wordt een gebeurtenis met `session_id`, positie, duur, tijdstempel, `completed` en `explicit_action`, waarbij expliciete intentie altijd van heuristiek wint. En wanneer de content fingerprint verplicht wordt is een beslissing voor het moment dat de eerste bibliotheek verhuist.

### Notes
- **Het publieke `/info`-antwoord geeft minder prijs.** Servernaam, versie en buildnummer staan nu achter authenticatie. Fingerprinting is voor een huisserver geen groot risico, maar een versienummer aan de buitenkant vertelt een scanner welke bekende zwakke plekken het proberen waard zijn.
- Opnieuw geverifieerd na de ronde: 64 interne ankers resolven, 16 regelverwijzingen kloppen, 6 Mermaid-blokken parsen, `anti-slop-check.sh` schoon.

## [2026-08-18] Pleya Server: het onderzoek keerde de opdracht om

Document-only. Geen commit, geen wijziging aan `lib/`, `share_server/` of `server/`.

### Added
- **[docs/pleya-server-architecture.md](pleya-server-architecture.md)**, 1870 regels, 24 hoofdstukken plus een bijlage. Ontwerp voor een eigen mediaserver in Go, met als einddoel dat Pleya zonder Plex kan functioneren en Plex en Jellyfin optionele adapters worden.
- **Een roadmap van dertien fasen**, elk met Phase ID, doel, bijdrage aan het einddoel, scope, expliciete out-of-scope, afhankelijkheden, acceptatiecriteria, stopcriterium, risico's, tests en een Roadmap Drift Check. Fase 3 is de eerste die de app raakt.
- **Acht voorgestelde DEC-besluiten** (DEC-030 tot en met DEC-037), samengevat in hoofdstuk 24. Ze worden pas als ADR geschreven wanneer fase 1 wordt ingepland, dus [DECISIONS.md](DECISIONS.md) is ongewijzigd en `DEC-029` blijft de laatste bestaande.

### Notes
- **De aanname dat de client eerst van Plex losgemaakt moet worden klopt niet.** `lib/media/media_server_client.dart` is 766 regels met ruim tachtig members en draagt al vier implementaties, waarvan `LocalFolderClient` (1376 regels) en `PleyaShareClient` (917) geen enkele Plex-eigenschap hebben. `ServerCapabilities` heeft negentien vlaggen, `ConnectionKind` vier waarden, en `data_aggregation_service.dart` (623 regels) noemt Plex en Jellyfin alleen nog in doc-comments. Er staan 125 backend-vertakkingen in 52 bestanden, en een deel daarvan is legitiem omdat de backends echt verschillen.
- **Fase B uit de opdracht draait al.** `share_server/` staat op de NAS in Docker met read-only mounts, met `scanner.dart`, code-pairing via challenge/response in `pairing.dart`, range-streaming en kijkvoortgang per gast.
- **Het echte gat zit in de playbackbeslissing.** De client stelt geen enkele device-capability vast. `lib/services/plex_client.dart:3072-3110` bouwt `X-Plex-Client-Profile-Extra` uit een vaste clause-lijst en `lib/services/jellyfin_client/parts/playback.dart:504-543` stuurt een hardgecodeerde `DeviceProfile`; op een Apple TV 4K gaat dezelfde JSON de lijn over als op een oude tablet. De enige knop is `TranscodeQualityPreset`, dat in zijn doc-comment naar Plex Web's tabel verwijst. De client neemt dus te weinig verantwoordelijkheid en niet te veel.
- **Het eigen protocol spreekt vandaag Plex.** `lib/services/pleya_share/pleya_share_protocol.dart:14` serveert op `/library` letterlijk de freezed `MediaItem` als JSON, en `share_server/lib/src/server.dart:330-336` zet `viewOffsetMs` en `viewCount` in het antwoord. Server en client zitten daarmee compile-time aan hetzelfde model vast. Het ontwerp trekt daaruit de regel dat wire-types en domeintypes twee dingen zijn.
- **Een transcode-sessie wordt nergens afgesloten.** `universal/stop` komt nul keer voor in `lib/`. Plex ruimt verweesde sessies zelf op na een timeout, dus het gat wordt pas zichtbaar zodra Pleya Server zelf transcodeert. Fase 8 bouwt beide kanten tegelijk, met een watchdog als garantie en de `DELETE` als beleefdheid.
- **Pleya Share blijft een eigen product**, geen voorloper. Ander eigenaarschap, andere levensduur, ander vertrouwensmodel. Gedeeld wordt een protocolvocabulaire met een profielbegrip (`minimal`, `full`), niet de runtime; `share_server` overzetten is optioneel en geen voorwaarde voor v1.
- **Het document is zelf nagelopen.** Alle 16 `bestand:regel`-verwijzingen nagelopen tegen de code (twee gecorrigeerd), alle padverwijzingen bestaan, alle 5 Mermaid-blokken parsen, alle 54 interne ankers resolven, en `anti-slop-check.sh` is schoon.
- **Eén bug gevonden en bewust laten staan.** `lib/widgets/new_content_badge.dart:36` bepaalt het NEW-label met `(item.viewCount ?? 0) == 0`, waardoor een half bekeken titel "NEW" kan tonen. Staat in de backlogtabel van hoofdstuk 24 en als blocker in `STATUS.md`.
- **Vier vragen blijven bewust open.** De keuze van metadata-providers naast TMDB, het schedulingmodel voor externe transcode-workers, de jobbibliotheek op Postgres, en de vraag of `MediaServerClient` opgesplitst moet worden. Die laatste krijgt een meting in fase 4 met een concreet criterium in plaats van een voorspelling.

## [2026-08-18] Releasenotes gaan mee de build in, en de lane leest ze terug

Op `main`, vijf commits van `34f2c5f` tot `8e84f3a`.

### Added
- **Elke TestFlight-build krijgt de publieke releasenotes als "What to Test".** `apply_release_notes` haalt de tekst voor het buildnummer uit `docs/RELEASES.md` via `release_notes_for`, `testflight_notes` maakt er platte tekst van en `set_build_notes` schrijft hem op de build. De external-lane geeft geen ipa mee, dus `local_build_number` leest het nummer uit `pubspec.yaml`; ontbreken de notities daar, dan stopt `required_notes_for` de lane in plaats van een lege tekst te uploaden.
- **`fastlane notes build:227`** zet de notities los op een bestaande build, voor het geval `/update-docs` pas na de upload draait.

### Fixed
- **Een geslaagde schrijfactie was geen bewijs dat een tester de tekst ziet.** `verify_build_notes` leest de beta build localizations terug en vergelijkt ze met wat er gestuurd is, met genormaliseerde regeleindes aan beide kanten. Het veld heeft een lengtegrens, Apple normaliseert regeleindes, en een build met meerdere locales kan er één missen: dat zijn drie manieren waarop een `200` alsnog niets oplevert. Zonder localization of bij een afwijking stopt de lane.
- **De gegenereerde werklijst uit de releasenotes stond op de site.** Alles tussen de `BEGIN GENERATED`- en `END GENERATED`-markers is een ruwe lijst commit-onderwerpen in de taal waarin ze gecommit zijn, bedoeld als invoer voor de volgende herschrijfronde. `website/src/lib/server/releases.ts` knipt dat blok er nu uit, want het zette Nederlandse commitregels onder "Unreleased" op de live pagina.

### Changed
- **De handleiding op pleya.app bijgewerkt** op zeven hoofdstukken: FAQ, film- en seriedetails, aanvragen, instellingenoverzicht, ondertitels en audio, het homescherm en de speler. `docs/manual/SCREENSHOTS.md` kreeg er één openstaande schermafbeelding bij.

## [2026-08-17] Drie tvOS-ingrepen: overlappende herotekst, onzichtbare focus, en het canvas dat maar half zo groot was

Op `main`, drie commits: `d16fa4f`, `e2c123f`, `0f780f9`.

### Fixed
- **De herotekst op Libraries liep over de kop van de eerste posterrij.** De onderrand van het tekstblok kwam uit `firstHubPeekHeight`, de peek-formule van het TV-homescherm. Daar hangt de rail in een `AnimatedSlide` die hem precies op die peek houdt, dus daar klopt hij. Op Libraries staat de rail gedokt op `bottom: 0` en meet hij zichzelf op zijn volle `railHeight`, die groter is met de focusreserve, de peek van de volgende hub en de onderpadding. Het verschil is precies de strook waar het rijlabel staat, en `_RailBackgroundBleed` tekent daar een verloop van 0,7 in plaats van een dekkend vlak, dus de twee teksten mengden zichtbaar. `TvBrowseRailLayout.heroBottomInsetForDockedRail` staat nu naast `firstHubPeekHeight` en legt in zijn dartdoc vast wanneer je welke nodig hebt. Zie [DEC-027](DECISIONS.md#dec-027).
- **De bovengrens die een minimale hoogte voor het infoblok reserveerde is weg.** Die kon de onderrand terug de rail in duwen, precies de fout die hierboven wordt gerepareerd. Bij weinig hoogte laat het blok nu synopsisregels vallen in plaats van zichzelf als geheel te verkleinen, zodat de titel op leesafstand leesbaar blijft. Dat gaat via `TvSpotlightBackground.constrainInfoToAvailableHeight`, expliciet per scherm aan te zetten: afleiden uit "heeft geen knoppen" zou stilletjes omslaan zodra Libraries er een krijgt.
- **De gefocuste settings-rij was op tv niet van een ongefocuste te onderscheiden.** De markering was er nog, hij werd overgeschilderd. Een settings-rij is een kale `ListTile`, en die laat zijn focus-highlight tekenen als inkt op de dichtstbijzijnde `Material`, hier de Scaffold. Flutter tekent die inkt vóór de widgets eronder, dus toen `SettingsGroup` er een dekkende kaart van `t.surface` tussen zette landde de highlight op de Scaffold en legde de kaart hem meteen weer toe. Een gefocuste rij was daardoor pixelidentiek aan een ongefocuste, terwijl navigeren gewoon bleef werken. `SettingsPage._grouped()` vouwt alle rijenlijsten tot kaarten, dus elk subscherm ging in één keer mee. De kaart heeft nu een eigen transparante `Material`, en elke rij loopt door `SettingRowFocus` met `descendantsAreFocusable: false`, zodat er precies één focus-eigenaar per rij is en de D-pad één stop per rij krijgt.

### Changed
- **De Apple TV-vergroting van 2,00 naar 1,85.** Pleya tekent op tvOS niet op het oppervlak dat het systeem aanlevert maar op de helft daarvan, waarna `_AppleTvScale` de uitvoer weer opblaast. Het canvas is daardoor 960x540, en `TvLayoutConstants.scaleForHeight` ziet 540, rekent 0,5 en wordt door zijn eigen clamp op 0,85 gezet: netto 1,7 keer zo groot als het ontwerpdoel van 1080 hoog. Met 1,85 wordt het canvas 1038x584. Zie [DEC-028](DECISIONS.md#dec-028).

### Added
- **`test/widgets/tv_hero_rail_clearance_test.dart`** zet de echte hero boven een echte gedokte rail met twee hubs en meet de vier tekstblokken met `getRect`. Eén test laat zien dat de oude peek-formule daar daadwerkelijk overlap oplevert, zodat de assertie aantoonbaar kan falen.
- **`test/screens/settings/settings_row_focus_test.dart`** bewijst dat het focusvlak van de gefocuste rij verschilt van dat van de buren in donker én licht, dat er precies één rij gemarkeerd is, dat de markering niet achterblijft, dat `getRect` voor en na focus identiek is, en dat omlaag van rij één direct op rij twee landt.

### Notes
- **De meting waar dit allemaal op hangt.** Een tijdelijke logregel in de hero gaf `size=Size(960.0, 540.0) dpr=4.0 textScaler=geen`. Onafhankelijke controle op de schermafdruk: de icoonbadge in Instellingen is 36 logische punten en meet 138 fysieke pixels, wat dpr 4 bevestigt. De logregel is daarna verwijderd.
- **De richtwaarden uit de opdracht klopten grotendeels niet.** De tekst is op tv niet groot, de chrome eromheen wel. Een settings-rij heeft een titel van 13 punten en is 81 punten hoog door de badge van 36 en de padding; de hele instellingen-stack heeft geen enkele tv-tak voor maatvoering. `FocusTheme.focusScale` is 1,05 en niet 1,08, `TvLayoutConstants.horizontalInset` is 72 en niet 48, en de icooncontainer is 36 en dus al kleiner dan het voorstel van 38 tot 40. Fonts verkleinen zou hier de verkeerde knop zijn.
- **Meerdere plekken kiezen bewust een grotere maat voor tv en vermenigvuldigen die daarna met 0,85**, waardoor de tv-waarde logisch kleiner uitkomt dan de mobiele: de actieknop op het detailscherm is 46 × 0,85 = 39,1 tegen 48,0 op mobiel, het afspeelicoon 18,7 tegen 20,0, het afspeellabel 14,5 tegen 16,0. Op het scherm zijn ze alsnog groter door de globale factor. Wie alleen de logische getallen leest, leest het omgekeerde van wat de gebruiker ziet.
- **Nog niet aangeraakt, bewust:** de rijhoogtes, de bibliotheekkop, de railmaten en de focusschaal halen hun ruimte uit dezelfde marge die de schaalwijziging al vrijmaakt. Samen uitgevoerd zou je twee keer verkleinen en niet meer weten welke wijziging het effect gaf. De clamp in `scaleForHeight` blijft ook staan: bij 584 punten blijft die actief, dus die factor is nog steeds een constante en geen tweede schaalmechanisme dat meebeweegt.
- **Losse opruiming gevonden, niet gedaan:** `mono_theme.dart:129-136` gebruikt `textTheme.copyWith` voor `displayLarge` en `titleMedium`. `copyWith` op een `TextTheme` vervángt de stijl, dus die twee verliezen hun `fontSize` en `height` uit `Typography.englishLike2021` en vallen terug op de omringende `DefaultTextStyle`. Bewust niet in deze ronde gerepareerd, want dan verandert typografie tegelijk met de schaal.

## [2026-08-17] Dependency-onderhoud kreeg een proces, en dat proces ving meteen twee stille regressies

Op branch `deps/onderhoudsronde-aug2026`, zeven commits vanaf `e9b1b0b`.

### Added
- **`scripts/check_updates.sh` zet elke pin in één rapport.** Tot nu toe had alleen MPVKit een controle; de Flutter-SDK, de tvOS-engine, libmpv-android, libdovi, libass, de zeven git-forks, de Dart-pakketten en de GitHub Actions werden pas zichtbaar als iemand er toevallig naar keek. Elke pin wordt gelezen uit het bestand dat hem echt gebruikt. Vier statussen in plaats van twee: `CURRENT`, `BLOCKED`, `OUTDATED`, `UNKNOWN`. Exitcodes 0, 1 (`OUTDATED` binnen `--strict-through-ring N`) en 2 (`UNKNOWN`), waarbij 2 van 1 wint, want een incompleet rapport zegt niets over wat er nog meer misging. `check_mpvkit_update.sh` blijft bestaan en wordt hiervandaan aangeroepen.
- **`scripts/classify_lock_diff.sh` bepaalt per gewijzigd pakket het bewijsniveau.** Plugin met gewijzigde platformcode is ring 3, plugin met identieke native kant en codegen-deelnemers zijn ring 2, de rest ring 1. Ontbreekt een van beide bronnen in de pub-cache, dan is de uitkomst `UNKNOWN` en promoveert die mee. Elke regel draagt zijn eigen `classificationEvidence`, dus een uitkomst is naleesbaar in plaats van te geloven. Zes fixtures in `test/fixtures/lock_diff/`.
- **`.fvmrc` is de enige bron voor de Flutter-versie**, met `scripts/check_flutter_version.sh` als preflight in `ci_checks.sh`, `codegen.sh` en `testflight_release.sh`. De tien losse `flutter-version: "3.44.0"`-regels in `ci.yml` en `build.yml` zijn vervangen door `flutter-version-file: .fvmrc`; `subosito/flutter-action` leest datzelfde bestand met `jq -r '.flutter'`. `pubspec.yaml` kan die rol niet spelen, want `environment.flutter` is hier een range.
- **`test/database/drift_relations_test.dart`** bewaakt de gegenereerde drift-relaties rechtstreeks: de foreign key, de `ON DELETE CASCADE`, de writepropagatie en de reference manager.
- **Workflow `dependency-health`**, wekelijks plus `workflow_dispatch`, op `--strict-through-ring 1`. Bewust geen scheduled variant van de PR-CI: zodra `checkout@v8` uitkomt zou "CI" anders elke week rood staan terwijl `main` prima is.

### Fixed
- **De committede `.g.dart`-bestanden waren geformatteerd met een andere SDK dan CI draait.** Homebrew-Flutter 3.44.4 op PATH, CI op 3.44.0, en `dart format` breekt argumentenlijsten in die twee versies anders af: 4001 regels verschil over twintig bestanden zonder dat er iets aan de bronnen veranderde. Geen van beide gates zag dat, want de codegen-freshness-check vergelijkt mtimes en de format-check slaat `*.g.dart` juist over. Aantoonbaar alleen opmaak: beide kanten door dezelfde formatter halen maakt ze byte-identiek.

### Changed
- **27 ring-1-pakketten bijgewerkt, `pubspec.yaml` ongemoeid.** Niet blind `flutter pub upgrade` gecommit: eerst een verkenning naar een kopie (64 gewijzigd, ring1=42 ring2=11 ring3=11), die geklassificeerd, de kopie weggegooid, en daarna gericht opgewaardeerd in twee golven. Golf A telde 21 leaf- en runtimepakketten, golf B zeven uit de build-stack; beide lieten de gegenereerde diff leeg.
- **GitHub Actions bijgewerkt**, elke major tegen zijn release notes gelegd: `checkout` v4 naar v7, `cache` v4 naar v6, `upload-artifact` v4 naar v7, `download-artifact` v4 naar v8, `setup-java` v4 naar v5, `attest-build-provenance` v2 naar v4.
- **Third-party actions staan nu op een volledige commit-SHA** met de leesbare versie als comment: `awalsh128/cache-apt-pkgs-action` (stond op `@latest`), `vedantmgoyal9/winget-releaser`, `softprops/action-gh-release` (v1 naar v3), `subosito/flutter-action` en `dart-lang/setup-dart`.

### Notes
- **Het ringbeleid ving meteen twee dingen die de classifier zelf niet zag.** Beide kwamen er als ring 1 uit; de bewijsstap haalde ze eruit.
  - De analyzer-stack (`analyzer` 10.0.1 naar 10.2.0 en drie meebewegers) laat `drift_dev` zonder compilefout de hele relatie tussen `connections` en `profile_connections` uit `app_database.g.dart` weglaten: de foreign key, de `ON DELETE CASCADE`, de `StreamQueryUpdateRules`-writepropagatie en de `$$ConnectionsTableReferences`-manager. 298 regels weg, geen waarschuwing, `flutter analyze` groen. Zie [DEC-026](DECISIONS.md#dec-026).
  - `rate_limiter` 1.1.0 leest de tijd via `package:clock` in plaats van `DateTime.now()`. Onder de fake clock van `flutter_test` vuurt de zoekdebounce daardoor anders en vallen twee TV-focustests in `search_screen_test.dart` om. Ring 2: dat vraagt eerst aanpassing van die tests.
- **`upload-artifact` en `download-artifact` horen niet op hetzelfde majornummer.** Download kreeg in v5 een eigen breaking change (het pad bij een download op artifact-id) en loopt sindsdien één major voor; v8 is de tegenhanger van upload v7. Die v5-wijziging raakt ons niet: alle tien de downloads in `build.yml` halen op `name:`, geen enkele op `artifact-ids:`.
- **De breaking change in `checkout` v5 tot en met v7** gaat over veiliger defaults voor `pull_request_target`. Geen enkele workflow gebruikt die trigger.
- **Eén plat getal voor lockfile-achterstand bleek onbruikbaar.** Van de 32 pakketten die binnen hun constraint hoger kunnen zijn er zeventien plugins met platformcode. De achterstand wordt daarom gesplitst per ring, plus een meting die verder gaat dan `pub outdated`: kán het pakket op eigen kracht bewegen? Voor `drift`, `slang`, `sqlite3`, `sqlparser` en `json_annotation` is dat nee, dus die set is ring 2.
- **Bewust blijven liggen**, elk als eigen ring-3-set voor een volgende cyclus: libass 0.18.3, MPVKit 1.0.17, tvOS-engine `+5`, Flutter 3.47 (geblokkeerd tot `edde746/flutter-tvos` een 3.47-lijn publiceert), `file_picker` 10 naar 12, `saf_stream`, `saf_util` en `sqlite3_flutter_libs` 0.6.0+eol.
- Nog geen Renovate of Dependabot: eerst één of twee cycli met dit rapport draaien om te zien welke checks betrouwbaar zijn.

## [2026-08-17] De kijklijst-kaart paste niet in zijn cel, en het accountmenu stond dubbel

### Dependencies
- **`mobile_scanner` 5.2.3 → 7.4.0, ring 3, bewust geaccepteerd.** De iOS-simulator kon niet bouwen op Apple Silicon omdat GoogleMLKit geen arm64-slice levert, en sinds iOS 18 is er geen x86_64-simulator om op terug te vallen. In 7.x is ML Kit op iOS vervangen door Apple's Vision-framework, dus de arm64-uitsluiting is weg. De Dart-API die Pleya gebruikt (`MobileScanner(onDetect:)`, `barcode.rawValue`) is broncompatibel en het scanscherm is niet aangeraakt. `mobile_scanner` staat alleen in `ios/Podfile.lock`, dus tvOS en macOS vallen buiten de impact. Dat de simulator bouwt bewijst een gezonde iOS-build, niet dat scannen werkt: de decoder is juist het onderdeel dat wisselde en een simulator heeft geen camera. Daarom staat er nu een verplichte smoketest op fysieke hardware in [TESTFLIGHT.md](TESTFLIGHT.md), af te vinken vóór de eerstvolgende iOS-upload. Zie [DEC-024](DECISIONS.md#dec-024).

### Fixed
- **Metadata van rij 1 werd over de posters van rij 2 getekend in de Kijklijst.** Op TV liep de titel van een speelbare kaart de rij eronder in, verdween sommige metadata achter een poster, en waren posters binnen dezelfde rij ongelijk hoog. Oorzaak: `MediaCard.height` is in standard-grid-modus de **poster**hoogte, niet de kaarthoogte, en `WatchlistCard` gaf de hele celhoogte door. Elke speelbare kaart werd daarmee 32 logische pixels hoger dan zijn cel, en `SliverGrid` klipt niet. Dezelfde fout zat in de kijklijst-rail op Mijn Pleya. De insets, de gap en de gereserveerde teksthoogte verschilden bovendien tussen de twee kaarttakken, dus posters lagen niet op dezelfde pixel.
- Nieuw `lib/widgets/media_card_grid_layout.dart` (`MediaCardGridLayout`, zusje van `MediaCardListLayout`) bezit die geometrie: 2:3 gemeten over de posterbreedte, plus een captionreserve die met de systeemtekstgrootte meeschaalt. `WatchlistCard` heeft geen `height`-parameter meer, dus celhoogte en kaarthoogte kunnen niet meer uit elkaar lopen. `MediaCard` zelf is alleen van commentaar voorzien; `hub_section`, `tv_browse_rail` en `extras_section` rekenen op het huidige gedrag en blijven ongemoeid.
- Bewijs: met de fix teruggedraaid vallen zes nieuwe geometrietests om met `A RenderFlex overflowed by 32 pixels on the bottom`, exact het voorspelde getal. Met de fix erin is de volledige suite groen.

### Changed
- **Op mobiel is Mijn Pleya de enige persoonlijke ingang.** De avatar met accountmenu rechtsboven in de Home-header verdwijnt daar; Profielen, Opties en Uitloggen staan nu onderaan Mijn Pleya, en de Mijn Pleya-tab draagt de echte profielavatar in plaats van een generiek persoon-icoon. Desktop en tvOS houden het menu, want hun sidebar rendert Mijn Pleya bewust nooit. Eén predicaat (`showsHeaderAccountMenu`) stuurt beide kanten, met dezelfde `isMobile` als de gate op de tab, zodat de acties nooit op twee plekken staan en nooit op geen enkele. Zie [DEC-023](DECISIONS.md#dec-023).
- Uitloggen en het openen van de profielkiezer verhuisden naar `lib/services/account_ui_actions.dart`, naar het model van `WatchlistUiActions`. Dat haalde elf imports uit `discover_screen.dart`, waaronder `auth_screen.dart` en vier registries.

### Notes
- Het twee-personen-icoon in de Home-header is **Samen Kijken** en het telefoon-icoon is de **Companion Remote**. Geen van beide is een accountknop, dus beide blijven staan.
- Het oude menu toonde als eerste items de *andere* profielen, als snelwissel. Die snelwissel kost op mobiel nu een tik meer, via de identiteit bovenaan Mijn Pleya naar `ProfileSwitchScreen`. Dat scherm doet meer dan wisselen (beheren, PIN, verwijderen, Plex-account afmelden), dus een tweede dunnere wisselaar is bewust niet gebouwd.

## [2026-08-17] Copyright gezet, en de indiencheck opgeschreven

### Fixed
- **Het copyright-veld blokkeerde "Add for Review".** Alleen App Store Connect, geen code. Alle drie de 2.8.0-versies stonden op `Buildmind`, een naam zonder jaartal, en dat is niet wat Apple in dat veld verwacht. Gezet op `2026 Michel Knoop` met `PATCH /v1/appStoreVersions/<id>` (drie keer), en teruggelezen: alle drie geven nu `copyright='2026 Michel Knoop'` en staan nog op `PREPARE_FOR_SUBMISSION`.

### Changed
- `docs/TESTFLIGHT.md` kreeg de sectie "Indienen voor review": de veldenchecklist per platform met per veld of de API hem kan zetten, de version-id's van 2.8.0, en de volgorde bij een hertest na afwijzing. "Add for Review" noemt alleen het eerste veld dat het mist, dus zonder lijst vind je de volgende blokkade pas na de volgende poging. Dit is dezelfde valkuil als bij het versienummer, de export compliance en de buildkoppeling.

### Notes
- **Screenshots zijn de enige harde blokkade die overblijft.** tvOS en macOS hebben er geen enkele; die erven niet van iOS. iOS heeft 6× iPhone 6.5" en 2× iPad 12.9". Verder is elk versierecord compleet: beschrijving, keywords, support- en marketing-URL, reviewnotities, demo-account `applereview`, contactpersoon en bijlage staan op alle drie. App-niveau ook: categorie Entertainment, leeftijdsclassificatie 4+, privacybeleid-URL, `contentRightsDeclaration` op `DOES_NOT_USE_THIRD_PARTY_CONTENT`, prijs met basisterritorium NLD, 175 van 175 territoria.
- **Build 221 bestaat wél en hangt aan tvOS**, anders dan de notitie van eerder vandaag meldde. tvOS 2.8.0 draagt build 221 (geüpload 17 augustus, `VALID`, `IN_BETA_TESTING`, export compliance beantwoord); iOS en macOS staan op 220. Geen blokkade, maar de drie platforms lopen dus niet meer gelijk.
- **App Privacy en de EU DSA trader status zijn niet gecontroleerd.** De API-sleutel (rol App Manager) kan ze niet lezen: `appDataUsages` en `appDataUsagePublishState` geven HTTP 404 als relatie op `/v1/apps/<id>`, geen 403. Een sessie in de webinterface was er ook niet (geen Apple-cookies lokaal, en de login vraagt 2FA). Beide staan vermoedelijk goed omdat de iOS-inzending van 6 juli door de indienstap kwam, maar dat is een afleiding en geen meting.

## [2026-08-17] De reviewbuild gekoppeld, en het koppelen geautomatiseerd

### Fixed
- **De drie App Store-versies hingen nog aan de afgewezen build 156.** Alleen App Store Connect, geen code. iOS en tvOS 2.8.0 stonden op build 156 (de build die Apple op 6 juli afwees), macOS had helemaal geen build, terwijl build 220 sinds 15 augustus op alle drie de platforms `VALID` in TestFlight stond. Een reviewer die nu hertest had dus opnieuw de build zonder de inlogfix van `21eb01b` gekregen. Gekoppeld met `PATCH /v1/appStoreVersions/<id>/relationships/build` (drie keer HTTP 204); iOS ging daarmee van `REJECTED` naar `PREPARE_FOR_SUBMISSION`, en alle drie de versies dragen nu build 220 met export compliance al beantwoord.

### Added
- **De TestFlight-lanes koppelen de build zelf aan het versierecord** (`fastlane/Fastfile`). Een upload zet de build in TestFlight, niet in de versie die je indient; die tweede stap was handwerk en ging daarom mis. `ios_beta`, `tvos_beta` en `macos_beta` wachten na de upload op processing (`wait_for_build`) en selecteren de build in de bewerkbare versie van dat platform (`attach_build_to_version`, via `Spaceship::ConnectAPI` `select_build`). In `beta` gebeurt dat pas ná alle drie de uploads, anders staat platform twee te wachten op Apple's processing van platform één. Koppelen is nooit fataal en slaat een versie in review of live over met een melding; wachttijd via `ASC_ATTACH_TIMEOUT` (default 1800s). Losse lane `attach_builds [platform:ios] [build:220]` voor handwerk en herstel. Geverifieerd tegen App Store Connect: alle drie de platforms melden "build 220 was al gekoppeld", dus de idempotente tak klopt.

### Changed
- `docs/TESTFLIGHT.md` kreeg de sectie "Build koppelen aan het App Store-versierecord", met de reden erbij zodat dit niet opnieuw stil misgaat.
- `docs/app-review-reply-2026-08.md` bijgewerkt: de verificatie van de demoserver van vandaag staat erin, plus het aanbod van een schermopname en de instructie om de reply samen met de herindiening te versturen.
- `add_testers` maakt geen eigen Spaceship-token meer aan maar gebruikt de gedeelde `spaceship_app`-helper.

### Notes
- Demoserver opnieuw gemeten: `demo.pleya.app` antwoordt in 296 ms (Jellyfin 10.11.11), het account `applereview` authenticeert, en de bibliotheek geeft de drie rechtenvrije Blender-films terug. De "Authentication timed out" van de reviewer kwam dus niet daarvandaan.
- **Build 221 staat niet in App Store Connect.** De upload die in STATUS als lopend stond heeft geen enkel platform bereikt; het hoogste nummer is op alle drie 220 (15 augustus).
- Zie [DEC-022](DECISIONS.md#dec-022).

## [2026-08-17] Kijklijst afgemaakt, en de Plex-cloudgrens getrokken

### Fixed
- **De servertoken van je eigen mediaserver ging mee naar `epg.provider.plex.tv`** (`lib/services/plex_client/parts/live_tv.dart`, `lib/services/plex_cloud_http_client.dart`, `lib/services/plex_epg_client.dart`, `lib/services/livetv/plex_favorite_channels_service.dart`, commits `a089264`, `74ce20f`, `20ed398`, `2f171c4`). De favorieten van Live TV werden opgehaald en weggeschreven via `_http`, de `FailoverHttpClient` van `PlexClient`, die `config.headers` als defaults draagt met de PMS-token erin; `MediaServerHttpClient._send:288` merget die ook bij een absolute URL. Gemeten tegen een echt account: die host accepteert de servertoken (200), weigert een verzoek zonder token (401) en accepteert de plex.tv-accounttoken net zo goed (200). Weglaten was dus geen optie, verhuizen wel. `PlexCloudHttpClient` is nu de transportgrens naar plex.tv: geen `baseUrl`, geen `defaultHeaders`, nooit een `FailoverHttpClient`, en de token als verplichte parameter per call. `PlexWatchlistClient` staat er ook op, zodat Live TV geen uitzondering werd maar het patroon volgde. De scopecheck zit in `PlexFavoriteChannelsService`, die per operatie opnieuw om user-scoped auth vraagt en de owner-fallback weigert. Zonder scope is de functie afwezig en niet stuk: geen store, geen ster, geen schrijfactie, geen foutmelding. Zie [DEC-021](DECISIONS.md#dec-021).
- **Een mislukte lees van de favorietenlijst wiste je favorieten** (`lib/screens/livetv/live_tv_screen.dart`, `lib/screens/livetv/live_tv_favorites.dart`, commits `2f171c4`, `8f7f937`). `getFavoriteChannels()` ving elke fout af en gaf `[]`, `_loadFavorites` maakte daar een lege lijst van terwijl de store- en source-maps al gevuld waren, en één ster aantikken schreef die leegte terug als de volledige lijst van het account. Een `sharedFullList`-write eist nu een geslaagde lees van precies dezelfde store-instantie binnen dezelfde favorietengeneratie. Dat leesbewijs is een eigen type (`FavoriteStoreReadProof`) in plaats van een set naast een teller, zodat de regel niet stil kan verzwakken als iemand later een `clear()` vergeet.
- **De leescall van de favorieten kon je eigen server offline melden.** `FailoverHttpClient` overridet alleen `get` (`failover_http_client.dart:78`), dus een 5xx van de cloudhost kon de endpoint-cascade van de mediaserver starten en in het uiterste geval `onAllEndpointsExhausted` vuren. Dat pad bestaat niet meer.

### Added
- **Sorteren op de kijklijst: recent toegevoegd, titel, jaar** (`lib/media/watchlist_entry.dart`, `lib/widgets/watchlist_sort_sheet.dart`, `lib/screens/watchlist_screen.dart`, commit `3634fa0`). Het plan beloofde drie ordeningen en offline expliciet "sorteren blijft actief", maar het scherm kende alleen de volgorde van toevoegen. Sorteren gebeurt volledig over de entries in het geheugen: geen refetch, geen availability-resolve, en daarom blijft het offline werken terwijl het filter Beschikbaar verdwijnt. De comparators zijn totaal gemaakt zodat de mergevolgorde niet in het resultaat lekt: titel valt terug op jaar en dan op key (een remake en het origineel delen hun titel), jaar sorteert nieuwste eerst met een ontbrekend jaar achteraan in plaats van als jaar nul.
- **Nederlandse vertalingen voor de kijklijst en Mijn Pleya** (`lib/i18n/nl.i18n.json`, commit `195904e`). Kijklijst is de gekozen term, ook in de navigatie en de meldingen na een mutatie.

### Changed
- **`LiveTvSupport` splitst in server en opslag** (`lib/media/live_tv_support.dart`, commit `b4bc5d9`). `buildFavoriteChannelSource` blijft serverkennis, de vier opslag-members zitten op `LiveTvFavoritesStore`, en `LiveTvSupport.favorites` geeft de store die de server zelf bezit. Jellyfin geeft zichzelf terug en verandert twee regels; Plex geeft `null`, bewust en niet een stub met mode `none`, want Plex-favorieten bestaan wél en wonen alleen elders.
- **De favorietenregels van het Live TV-scherm staan naast het scherm** (`lib/screens/livetv/live_tv_favorites.dart`, commit `e41975c`), zodat een regel die beslist of een volledige lijst overschreven mag worden testbaar is zonder widgetboom. Daar staat ook het onderscheid dat de degraded state draagt: `isFavoriteCapable` stuurt zichtbaarheid, `canToggleFavorite` de bevoegdheid van dit moment.
- **`myPleya.settings` en `myPleya.switchProfile` verwijderd** ten gunste van `common.settings` en `screens.switchProfile`; de profielkop in Mijn Pleya draagt nu een Semantics-label, zodat een avatar met een naam ernaast ook hoorbaar een knop is.

### Notes
- **De scope van `favoriteChannels` is niet vastgesteld.** Het testaccount heeft geen provider met het `livetv`-protocol, dus er bestaat geen geldige `source` en er kon geen onderscheidende regel worden weggeschreven; een synthetische regel wordt geweigerd met 400 `Bad source value`. User-scoped auth is dus de gekozen veilige faalrichting en geen gemeten eigenschap. De gesaniteerde meting staat in `test/fixtures/livetv/`, inclusief een afleiding die achteraf ongeldig bleek en als zodanig gemarkeerd is: het meetscript concludeerde "account/owner-scoped" uit twee lege antwoorden.
- De kijklijst kreeg zijn beslissing in [DEC-020](DECISIONS.md#dec-020) (commit `dd75c69`), de cloudgrens in [DEC-021](DECISIONS.md#dec-021) (commit `d867260`).
- 3264 tests groen, 50 nieuwe. `scripts/ci_checks.sh` schoon op alle zes de gates.

## [2026-08-16] Mijn Pleya en de kijklijst

### Added
- **De universele kijklijst, gevoed door de Plex-watchlist en Jellyfin-favorieten** (`lib/media/watchlist_*.dart`, `lib/services/plex_watchlist_client.dart`, `lib/services/watchlist/`, `lib/providers/watchlist_provider.dart`, `lib/screens/watchlist_screen.dart`, commits `310ace8` tot en met `11ec313`). Titels die je op je telefoon aan je kijklijst zet bestonden in Pleya niet. Het contract is eerst gemeten en gesaniteerd vastgelegd in `test/fixtures/watchlist/`, en die meting sneuvelde vier planaannames: het padsegment `available` gaat over streamingdiensten en niet over eigen servers, de lijst draagt geen `watchlistedAt` per titel terwijl de serverkant wel op `watchlistedAt:desc` sorteert, dubbel toevoegen geeft 200, en alle beeld-URL's zijn absolute publieke CDN-links die zonder header laden.
- **Mijn Pleya op mobiel** (`lib/screens/my_pleya_screen.dart`, `lib/navigation/navigation_tabs.dart`, `lib/screens/main_screen.dart`, commit `7c4f06c`), met Watchlist als eigen bestemming in de sidebar op desktop en TV. Downloads, Verzoeken en Instellingen zijn op mobiel geen bar-items meer maar ingangen binnen Mijn Pleya, dus die zijn daar twee tikken in plaats van één.
- **Toevoegen en verwijderen vanaf het detailscherm, het contextmenu en de sheet** (`lib/services/watchlist_ui_actions.dart`, commit `11ec313`), alleen op film en serie en alleen online. Offline verdwijnt de actie in plaats van te falen, want een kijklijstmutatie wordt geweigerd en niet in de wachtrij gezet.

### Notes
- Een entry draagt meerdere memberships, want dezelfde film kan tegelijk een Plex-watchlistregel en een Jellyfin-favoriet zijn. Verwijderen haalt hem overal weg en is compenserend: lukt de compensatie niet, dan volgt `partiallyFailed` en leest de provider de lijst terug in plaats van te raden. Alle state is genamespaced op profiel plus echte gebruiker. Zie [DEC-020](DECISIONS.md#dec-020).
- Artwork gaat via `MediaImageHelper.catalogPosterUrl` over images.plex.tv zonder auth, met een invariant-test die voorkomt dat er ooit een accounttoken in een persistente image-cachekey belandt.

## [2026-08-15] Het systeemtoetsenbord op Apple TV reageert weer op de Siri Remote

### Fixed
- **Klikken op een letter in het tvOS-systeemtoetsenbord deed niets** (`tvos/Runner/AppDelegate.swift`, `Runner-Bridging-Header.h`, `NativeTextEntryViewController.swift`, `NativeTextEntryPlugin.swift`, commit `6bab0ca`, tvOS-build 219). Vegen werkte, dictatie werkte, continuity-typen werkte, alleen de klik kwam nooit aan. De oorzaak zat in de gepinde fork-engine en is uit de binary bewezen: `-[UIApplication(FlutterTvosPressEvents) flutterTvos_sendEvent:]` slaat de originele `sendEvent:` over zodra `FlutterTvosHandlePressesEvent` `YES` teruggeeft, en `-[FlutterViewController tvosHandlePressFromUIEvent:]` eindigt in `synthesizeRemotePressType:`, die onvoorwaardelijk `YES` retourneert (`mov w0, #0x1` op `0x4b828`; er is geen enkel pad dat 0 geeft). Een select-press werd dus geclaimd op de allereerste hop, voordat UIKit zijn responder chain begon. Vegen bleef werken omdat de swizzle bovenaan bailt op `[event type] != 3`: dat is `UIEventTypeTouches`, geen press. De scheidslijn in het symptoom viel exact samen met de scheidslijn UITouch/UIPress.

  `PleyaFlutterViewController` beantwoordt die vraag nu zelf en geeft `false` zolang een native tekstinvoersessie loopt, **zonder `super` aan te roepen**: super is wat de press synthetiseert en `flutter/keydata` post, dus meelopen zou het achtergrondlek terugbrengen. De selector staat in geen publieke header en wordt gedeclareerd als categorie in `Runner-Bridging-Header.h` (was 0 bytes); Swift importeert hem als `tvosHandlePress(fromUIEvent:)`, geverifieerd met `swiftc -typecheck` tegen de gepinde `Flutter.framework`. Het eigendomsvenster is aan beide kanten aan de responder-staat gekoppeld: aan bij een geslaagde `becomeFirstResponder`, uit in het opruimpad van `NativeTextEntryField.finish` ná de dismissal. Zie [DEC-019](DECISIONS.md#dec-019).

### Changed
- **De Dart-gates zijn vangnet geworden in plaats van het normale pad.** `_blockKeysDuringSession` en de sessie-gate in `apple_tv_remote_touch_service.dart` blijven staan, maar verschijnt hun logregel tijdens een sessie, dan heeft de native hook gefaald. De `requestClose()`-uitzondering voor Back is vervallen: Menu gaat nu met de rest naar UIKit. Eén legitieme trefkans blijft over, de key-up van de select die het toetsenbord opende.
- **Startup-guard tegen een stille engine-bump.** `AppDelegate` logt `FlutterViewController.instancesRespond(to:)` op de selector. Nadrukkelijk op de superclass en niet op een instance: de eigen subklasse implementeert hem, dus een instance zou altijd ja zeggen en de guard waardeloos maken.
- **`scripts/tvos_sim.sh check-select`** meet nu of `textChanged length=N` oploopt én of de Dart-vangnetten stil bleven. Alleen het eindresultaat controleren bewijst de eigendomsoverdracht niet, en juist dat gat liet deze bug langs `check-keyboard` glippen. Op de simulator faalt de check zolang Connect Hardware Keyboard aanstaat, want Return submit dan in plaats van een letter te kiezen.

### Notes
- Twee correcties op eerdere aannames. De gate uit DEC-017 was **niet** de oorzaak: select werd al door de engine opgeslokt vóór die commit, en wat DEC-017 deed was het achtergrondlek dichten. En er is nooit een app-side override geweest, ondanks een geheugennotitie die het tegendeel beweerde; die is gecorrigeerd.
- Meegemerged uit `test`: de hero die verdween nadat het zoektoetsenbord open was geweest, en de watch-state-sync waarbij een tweede apparaat dat verder keek nu wint van een verouderde lokale positie. 2935 tests groen.
- Losse defecten, genoteerd maar bewust niet meegefixt: `forwardedPressCount` telt tijdens een sessie nu nul, waardoor de watchdog altijd `KEYBOARD_UNAVAILABLE` kiest in plaats van `KEYBOARD_DEAD`; en de play/pause-afvang in `AppDelegate.swift` vergelijkt tegen een presstype dat door dezelfde raw-value-mismatch als Menu (2040/2041 tegenover 4/5) waarschijnlijk nooit matcht.

## [2026-08-14] Apple TV: toetsenbord, skip-knoppen, autoplay, scrubben en de log-upload

### Fixed
- **De D-pad bediende de UI achter het systeemtoetsenbord** (`lib/services/apple_tv_native_text_entry.dart`, `lib/services/apple_tv_remote_touch_service.dart`, `tvos/Runner/NativeTextEntryViewController.swift`, `lib/screens/search_screen.dart`, commits `5dba184` + `c8ae4b7`). Select op een letter liet het scherm eronder scrollen en de focus verspringen. De diagnose uit DEC-011 bleek onvolledig: de tvOS-fork-engine swizzlet `sendEvent:` op `UIApplication` én `UIWindow` en levert elke press rechtstreeks als key event aan Dart, buiten de responder chain om, met een window-scan die de root-controller altijd vindt. Alle first-responder- en `pressesBegan`-logica draait dus op een pad dat bij een open toetsenbord nooit wordt uitgevoerd. Tweede valkuil: een `HardwareKeyboard`-handler die `true` teruggeeft stopt de focus-tree-walk niet, want `KeyEventManager` roept `_dispatchKeyMessage` onvoorwaardelijk aan. De gate zit nu op `FocusManager.addEarlyKeyEventHandler`, die vóór die walk draait en dus voor elk invoerveld tegelijk geldt. Back sluit de sessie via `requestClose()` en wordt daarna alsnog geconsumeerd. Aan Swift-kant meldt `finish()` pas ná de dismissal-transitie, zodat de vlag niet uitgaat terwijl het toetsenbord nog op het scherm staat. Zie [DEC-017](DECISIONS.md#dec-017).
- **De skip- en volgende-aflevering-knop waren met de remote nauwelijks te bereiken** (`lib/widgets/video_controls/parts/key_events.dart`, `parts/visibility.dart`, `parts/markers.dart`, `widgets/skip_marker_button.dart`, commit `2dfbcd4`). De knop staat als sibling búiten de `FocusScope` van de bediening, en de root-keyhandler consumeerde alle richtingstoetsen: omhoog opende de bediening met focus op afspelen/pauzeren, omlaag opende het TV-infopaneel, en de knop was nooit kandidaat. De enige route liep via de tijdlijn. Omhoog springt er nu rechtstreeks naartoe zolang hij zichtbaar is, omhoog/links/rechts geven de focus terug zodat hij geen doodlopende weg meer is, en auto-hide dismisst hem niet langer terwijl hij focus heeft.
- **Tijdens de aftiteling stonden er twee volgende-aflevering-knoppen** (`lib/screens/video_player/parts/playback_prompts.dart`, `lib/widgets/video_controls/parts/markers.dart`, zelfde commit). Bij credits-tot-einde wordt de skip-knop zelf "Next Episode", terwijl de Play Next-kaart op vrijwel dezelfde plek verschijnt. De uitsluiting bestond al via `hasPlayNextPrompt`, maar liep achter een `await` op de instellingen, dus in dat venster stonden beide op het scherm. De promptstatus en het wissen van de marker gebeuren nu synchroon vóór die await.
- **De focusring paste niet om de knop** (`lib/screens/video_player/widgets/player_prompt_overlays.dart`, `widgets/skip_marker_button.dart`, zelfde commit). "Play Next" is een `FilledButton` met themaradius 4 en "Cancel" een `OutlinedButton` met de Material-standaard `StadiumBorder`, terwijl beide een pilvormige ring krijgen. Beide staan nu lokaal op `StadiumBorder`; `mono_theme.dart` blijft ongemoeid. De skip-knop gebruikte een achtergrondtint die onzichtbaar was achter zijn eigen dekkende witte vlak en tekent nu een ring. De drie labels liepen hardgecodeerd in het Engels en gaan nu via slang.
- **Autoplay sloeg de volgende aflevering stil over** (`lib/screens/video_player/parts/episode_navigation.dart`, `parts/playback_prompts.dart`, `lib/screens/video_player_screen.dart`, commit `ee96f6c`). Drie onafhankelijke breekpunten. De laadvlaggen bleven staan bij elk van de twaalf `!isCurrentReload()`-uitgangen in `_reloadMediaInPlace`, waarna `_playNext()` de rest van de sessie zwijgend afketste; opruimen gebeurt nu in een `finally`, behalve wanneer een nieuwere herlaadpoging eigenaar is geworden. Een einde-bestand tijdens een overgang of achter de nog-aan-het-kijken-vraag verdween voorgoed, terwijl mpv `eof-reached` per bestand maar één keer flipt; dat wordt nu onthouden en opnieuw afgespeeld zodra het scherm vrij is, met een controle dat de speler nog aan het eind van hetzelfde bestand staat. En bij een korte aflevering die eindigde voordat de volgende bekend was sloot de speler; er wordt nu maximaal drie seconden op de lopende ophaal gewacht. De countdown zit in `lib/screens/video_player/auto_play_countdown.dart` en elke beslissing logt op infoniveau.
- **De log-upload faalde altijd met dezelfde nietszeggende melding** (`lib/screens/settings/logs_screen.dart`, `lib/utils/log_upload.dart`, commit `73ba2b8`). De relay leefde gewoon; de client hield zich niet aan het contract. De statuscode werd nooit gelezen, dus elke weigering liep via `jsonDecode` op een `text/plain`-body naar een lege `catch`. Daaronder zat een echte contractfout: de server accepteert 1 MB en de logbuffer mag 5 MB worden, zonder afkapping. De body wordt nu op UTF-8-bytelengte afgekapt tot 900 KB op een regelgrens, nieuwste regels eerst, met een markering erboven. Per uitkomst is er een eigen melding (te groot, te snel achter elkaar inclusief de wachttijd, geweigerd, serverfout, geen verbinding), de knop blokkeert tijdens een upload, en het verzoek wordt afgebroken zodra niemand er nog op wacht. Dat laatste voorkwam dat de dialoog "duurde te lang" meldde terwijl de log wél opgeslagen werd en de code onbereikbaar bleef.
- **Geen enkele macOS-build in TestFlight was installeerbaar sinds build 196** (`macos/Runner/Info.plist`, commit `9c896d7`). `ITSAppUsesNonExemptEncryption` ontbrak, dus Apple zette elke upload op `MISSING_EXPORT_COMPLIANCE` en daarmee was hij voor geen enkele tester zichtbaar. iOS en tvOS hadden de sleutel al. De upload zelf slaagt en `processingState` wordt gewoon `VALID`, dus de release-lane meldt misleidend succes. De al geüploade builds 214 en 216 zijn losgetrokken via `PATCH /v1/builds/{id}` met `usesNonExemptEncryption: false`. Zie [DEC-018](DECISIONS.md#dec-018).

### Added
- **Positie kiezen op de voortgangsbalk** (`lib/widgets/video_controls/desktop_video_controls.dart`, commit `d9706ad`). Select op de gefocuste tijdlijn pauzeert en opent een previewpositie met vastgezette thumbnail: links en rechts verschuiven alleen die preview, select bevestigt via `onSeekEnd` (en levert daarmee ook `onSeekCompleted` voor Watch Together), terug annuleert zonder te springen. Links of rechts op een gepauzeerde video stapt er impliciet in, alleen bij D-pad-navigatie. De bouwstenen lagen er al: `_timelinePreviewPosition`, `_flushTimelinePreviewSeek`, de BIF/trickplay-thumbnails en `PlayerChromeHold.scrub` stonden alleen achter de transcoding-tak.
- **De spoelsnelheid loopt op met het tempo van klikken** (zelfde commit). De acceleratie hing aan `KeyRepeatEvent`, en die komt alleen van een fysieke D-pad-hold: touchpad-swipes sturen los een down en een up, dus die bleven eeuwig op de basisstap van 10 seconden steken. De streak is nu tijdgebaseerd met een venster van 800 ms en reset bij richtingswissel; de bestaande tiers (1,5x tot 10x) en de clamp blijven. De scrub-thumbnail verschijnt daardoor ook bij swipes.

### Notes
- 2925 tests groen, `flutter analyze` zonder waarschuwingen. TestFlight 2.8.0: tvOS build **216**, macOS build **216**, iOS build **215** (nummers geverifieerd via de ASC-API, niet afgeleid uit de lane-output).
- De iOS-lane hing 32 minuten op `xattr -r -d com.apple.FinderInfo` met een `build/`-map van 13 GB. Opgelost door de map te verwijderen en een reaper mee te draaien die alleen een `xattr`-proces boven de 45 seconden afbreekt. Bekend patroon, zie de toolchain-notitie in STATUS.md.
- Nog te doen op een fysieke Apple TV: de gezamenlijke regressieronde over deze vijf punten. Alles is unit- en widget-gedekt, maar de remote zelf is niet te simuleren.
- Er staan twee app-records in App Store Connect: `nl.michelknoop.pleya` (`6787464031`, actueel) en `nl.michelknoop.plexflixnetwork` (`6786811460`, oud, blijft rond build 140 hangen).

## [2026-08-11] Opruimronde: dode Live TV-interface, eenmalige abstracties, no-op-vlaggen

### Removed
- **41 nooit-aangeroepen leden uit `LiveTvSupport`** (commits `d0ad971`, `e9b9fe5`). Grabber-beheer, de EPG-lineup-wizard, DVR-CRUD, media-providers, sessiedetails en de twee notificatie-URI's stonden in vier lagen tegelijk: de interface, `NoopLiveTvSupport`, een rij `UnimplementedError`-gooiers in de Jellyfin-adapter en de Plex-adapter met de `PlexClient`-implementaties eronder. Callers waren er nul. `buildNotificationWebSocketUri` en `buildNotificationEventSourceUri` hoorden er sowieso niet: het zijn geen live-TV-operaties, en de noop-variant gaf een lege `Uri()` terug in plaats van te weigeren, wat een stille verkeerde verbinding zou opleveren zodra iemand ze wél ging gebruiken. Vijf modelbestanden (`livetv_lineup`, `livetv_server_status`, `livetv_session`, `media_grabber_device`, `media_provider_info`) hingen alleen aan die leden en zijn mee verdwenen.
- **`ConnectionAuthService`** (`lib/connection/connection_auth_service.dart`, commit `24fe41e`). Eén implementatie, en geen enkele call-site die op het abstracte type leunde. `JellyfinConnectionAuthService` houdt `validate`/`refresh`/`signOut` gewoon als eigen methoden.
- **`TvLayoutConstants.heroContentMaxWidth`** en de prefs `preferred_video_codec` / `preferred_audio_codec` (commit `c605852`). De constante had nul lezers; de twee codec-prefs werden nergens uitgelezen, alleen netjes meegereset. De export-test gebruikt nu `subtitle_text_color` als representatieve string-pref.

### Changed
- **DVR-operaties zitten in een eigen `LiveTvDvrSupport`** (`lib/media/live_tv_dvr_support.dart`, commit `208cd6e`). Alleen Plex implementeert opnameregels en gidsherlaad, dus `MediaServerClient.liveTvDvr` is `null` op Jellyfin, lokale mappen en Pleya Share. Dat vervangt `ServerCapabilities.liveTvDvr` als beveiliging op de aanroeppaden: waar die vlag eerst een afspraak was die drie callers vergaten (`livetv_recording_actions.dart`, `record_options_sheet.dart`, `program_details_sheet.dart`), wijst de compiler ze nu aan. Gedragsnuance: `program_details_sheet` zette `_checkedMapping` voorheen via een gevangen `UnimplementedError`, nu via een expliciete null-check.
- **Hold-to-2x draait op `TemporaryOverride`** (`video_controls.dart`, `parts/playback_input.dart`, commit `e6133c5`). De twee losse velden `_isLongPressing` en `_rateBeforeLongPress` waren precies de constructie waar de gotcha in CLAUDE.md voor waarschuwt. `engage` capture't nu eenmalig en `release` herstelt eenmalig. Daarmee heeft `lib/utils/temporary_override.dart` een echte gebruiker en kon de `ignore_for_file: unused-code, unused-files` uit de kop weg (zie de "Changed"-notitie van 2026-08-06, die daarmee vervalt).
- **`kBlurArtwork` is een dart-define geworden** (`lib/utils/obfuscation_utils.dart`, commit `187f4a1`). Screenshot-builds draaien voortaan met `--dart-define=BLUR_ARTWORK=true` in plaats van een handmatige const-flip in de bron. De waarde blijft `const`, dus een gewone build shaket het hele blur-pad er nog steeds uit. Toegevoegd aan de env-tabel in `docs/release-baseline.md`.
- **TV-tekstinvoerdiagnostiek hangt aan de bestaande debug-pref** (`lib/utils/text_input_diagnostics.dart`, commit `7ecaffd`). Het `enabled`-veld stond hard op `false` en had geen schakelaar in de UI, dus de logregels waren onbereikbaar. Ze gaan nu via `appLogger.d`, waarmee "debug logging" in Instellingen de enige knop is.
- **Twee handgeschreven `_listEquals`-kopieën vervangen door `ListEquality`** uit `package:collection` (`host_playback_coordinator.dart`, `guest_playback_reconciler.dart`, commit `a3e71dd`). Zelfde patroon als `playback_state.dart:149` al gebruikte, en het houdt beide services Flutter-vrij.

### Notes
- Vier vondsten uit de audit zijn bewust blijven staan. De donatie-flow is een gedocumenteerd patroon in `docs/DECISIONS.md`. `TemporaryOverride` krijgt juist een gebruiker in plaats van de prullenbak. De `kBlurArtwork`-callsites horen bij een levende screenshot-feature. En de Plex-adapter platslaan in `PlexClient` zou een klasse van 4315 regels nog eens ~62 publieke namen geven, terwijl de adapters na deze sanering dun genoeg zijn.
- Geverifieerd met `scripts/ci_checks.sh` volledig groen (format, codegen-freshness, analyze, unused-code, unused-files) en **2888 tests groen**. Netto 1384 regels minder in `lib/` en `test/`.
- Handmatig nog te doen zodra er weer ingelogd kan worden: Live TV openen op een Plex-server (gids laadt, opname plannen zichtbaar) en op een Jellyfin-server (kanalen en favorieten, geen DVR-knoppen). Dat dekt de gedragsnuance in `program_details_sheet`.

## [2026-08-10] — Inloggen: de Apple-afwijzing dichtgezet en het lege profielscherm op macOS

### Fixed
- **De uitweg naar Jellyfin kwam vijf minuten te laat** (`lib/screens/auth/plex_pin_auth_flow.dart`, commit `6f4d6d9`, iOS-build 213 / tvOS + macOS 214). App Review wees de indiening van 6 juli af op 2.1(a) met *"the app displayed 'Authentication timed out'"*. Dat is geen Jellyfin-bug: die string komt uit precies één plek — de Plex PIN-flow — dus de reviewer koos "Sign in with Plex" en typte daar het Jellyfin-demoaccount in. Zo'n PIN wordt nooit geclaimd. Sinds `93e82da` bestond de knop "Using a Jellyfin server?" al, maar alleen in `_buildErrorBlock`, en de poll staat sinds diezelfde commit op vijf minuten: de uitweg verscheen dus pas ná vijf minuten staren. Hij hangt nu ook onder de PIN zelf, in beide vormen (QR en browser-wachtend), als ingetogen tekstknop en alleen wanneer de ouder een route aanbiedt — het toevoegen van een Plex-account vanuit Instellingen verandert dus niet. Geen nieuwe i18n-string nodig. Zie [DEC-015](DECISIONS.md#dec-015).
- **Diezelfde uitweg brak de lopende poging niet af** (zelfde commit). `_switchToJellyfin()` deed alleen `_clearError()` + callback, wat veilig was zolang de knop pas ná de time-out bestond. Tijdens het pollen niet: de ouder pusht `AddJellyfinScreen` bóven deze widget, die dus blijft leven en doorpollt, en een alsnog geclaimde PIN laat `_connectToAllServersAndNavigate` een `pushReplacement` doen — dwars door het Jellyfin-scherm heen. De knop bumpt nu `_attemptId` (waarmee `shouldCancel` aanslaat) en zet de poll-toestand terug vóór de callback.
- **Het profielscherm op macOS was leeg tot een druk op Esc** (`lib/screens/profile/profile_switch_screen.dart`, commit `fd87cad`). Twee oorzaken over elkaar. De `StreamBuilder` stond op `initialData: ProfilesView.empty` en las `connectionState` noch `hasError`, dus "nog niet geladen", "leeg" en "stilgevallen" zagen er identiek uit — permanent en zonder feedback. En de toevoeg-knop stond als eigen sliver structureel ónder een viewport-vullende `SliverFillRemaining`: op TV trok de initiële focus hem in beeld, maar macOS start in pointer-modus (`input_mode_tracker.dart:58`) en `FocusedScrollScaffold._requestInitialFocus()` is expliciet gated op keyboard-modus, dus daar deed niets dat. Er lag niets overheen; de knop stond onder de vouw. Nu drie toestanden, en de knop zit in de lege staat zelf met `hasScrollBody: false`. De focus-gate bleef ongemoeid, dus op TV verandert er niets. Zie [DEC-016](DECISIONS.md#dec-016).

### Added
- **Diagnostiek in de gecombineerde profielstream** (`lib/profiles/profiles_view.dart`). `_combineLatest4` emit pas als álle vier de bronnen een waarde hebben, dus één stille bron houdt het scherm voorgoed leeg — en statisch lezen wijst niet aan wélke. Na drie seconden zonder emissie logt hij nu welke slots gevuld zijn en welke niet (`received: [...] / pending: [...]`), en de eerste lege snapshot logt de vier invoergroottes. Dat scheidt "een stream vult zijn slot nooit" (verdachte: `ConnectionRegistry.watchConnections()`, de enige met `asyncMap` + crypto per rij) van "`connectionsById` komt leeg binnen waardoor `profile_merge.dart:19` alle Plex Home-profielen weggooit". Op infoniveau, want `appLogger.d` wordt in de app-log gefilterd.
- **Testdekking waar die nul was** (8 tests). `test/screens/auth/plex_pin_auth_flow_test.dart` (nieuw) drijft de poll-UI zonder plex.tv te raken via een `authServiceFactory`-seam plus `MockClient`; `test/screens/profile/profile_switch_screen_test.dart` dekt nu spinner-versus-leeg, de knop zonder scrollen, de lege staat op een korte viewport, de tegenspraak-fouttoestand en de bezinkdeadline. Totaal 2875 → 2883 groen.

### Changed
- **`docs/APP_REVIEW_NOTES.md`**: de waarschuwing tegen "Sign in with Plex" en de Jellyfin-stappen staan nu bovenaan in plaats van onder de rejectie-historie — twee reviewrondes strandden op dezelfde verwisseling. Conceptantwoord voor de Resolution Center in `docs/app-review-reply-2026-08.md`.
- **App Store Connect (app-id `6787464031`) via de API bijgewerkt.** De versie-records voor macOS en tvOS stonden nog op **1.0** terwijl de builds op 2.8.0 zitten; daardoor kon er geen build gekoppeld worden, wat verklaart waarom die twee platforms nooit zijn ingediend. Beide naar **2.8.0** gezet (iOS stond er al op, status REJECTED). De reviewnotities van alle drie de records beginnen nu met dezelfde Plex-waarschuwing.

### Nog te doen
- **Toestelverificatie van beide fixes.** iPad: bewust "Sign in with Plex" kiezen met het demoaccount — de Jellyfin-uitweg hoort meteen zichtbaar te zijn. macOS: koud starten en kijken wélke toestand verschijnt, plus de nieuwe `profiles_view`-regel in Instellingen → Logs. Tegenproef: een pijltje omlaag in plaats van Esc; doet dat hetzelfde, dan is de focus-scrollketen bevestigd als het onthullende mechanisme. tvOS mag niet veranderen.
- **Het antwoord aan App Review versturen** en 2.8.0 opnieuw indienen, nu met build 213/214 koppelbaar op alle drie de platforms.

## [2026-08-09] — Atmos: zelfcorrigerende passthrough, en de diagnose die twee sporen doodverklaarde

### Fixed
- **`auto` stuurde een bitstream naar een sink die hem niet nam** (`lib/services/audio_output_decision.dart`, commit `a0a2018`, build 211). Regressie uit build 207: op een Apple TV via HDMI met een E-AC3-track gaf de speler geen geluid en liep hij vast op de audiorenderer. De auto-beslissing koos op een digitale poort met een Dolby-codec voor passthrough zonder dat ooit was vastgesteld dat de andere kant hem accepteert. `auto` bitstreamt daarom voorlopig nooit meer; passthrough blijft een bewuste keuze van de gebruiker.

### Added
- **Passthrough die zichzelf corrigeert in plaats van stil te vallen** (`lib/services/audio_output_coordinator.dart`, `lib/screens/video_player_screen.dart`, commit `87844bb`, build 212). De ontbrekende schakel was geen code maar een signaal: mpv meldt zelf dat de compressed renderer faalt, maar `msg-level` stond op `all=error`, dus die waarschuwing bereikte de app nooit. Nu staan `ad_spdif` en `ao` op `warn` — ook zonder debug-logging — en luistert de coordinator op de bestaande logstream. Mislukt de bitstream, dan valt de app binnen een seconde terug op PCM, meldt dat, en onthoudt de route in een statische `_bitstreamBlocked` zodat de volgende aflevering niet opnieuw stalt. Een stall-watchdog dekt het geval waarin mpv niets zegt maar de positie stilstaat.
- **`current-ao` en `audio-out-params/format` in de performance-HUD** (`lib/widgets/video_controls/widgets/performance_overlay/*`, `android/.../mpv/MpvPlayerCore.kt`). De enige in-app manier om te zien of de bitstream écht buiten komt: `avfoundation` + `spdif-eac3` betekent dat hij loopt, `audiounit` + `s16`/`float` betekent dat mpv decodeert, wat de instelling ook zegt. Toegevoegd aan het mpv-pad én het Android-mpv-fallbackpad.
- **`server/README.md` en `server/deploy-nas.sh`**: de relay die `ice.pleya.app` bedient is nu deploybaar. Zie [DEC-014](DECISIONS.md#dec-014).

### Changed
- **`server/Caddyfile` en `server/docker-compose.yml` stonden nog op `ice.plezy.app`** — upstream's domein, dat naar een server van edde746 wijst. De rebrand had de app-kant omgezet naar `ice.pleya.app` maar de serverkant niet, en die hostnaam is nooit aangemaakt. Omgezet, `bugs`-container eruit, Caddy naar een `vps`-profile en `cloudflared` erbij.

### Diagnose (nog geen fix)
Een iOS-log van build 211 met Ted Lasso S4E1 verschoof het onderzoek beslissend:

- **De bitstream-keten wérkt.** `Selected decoder: spdif_eac3` → `AO: [avfoundation] … spdif-eac3` → `EAC3 config: … JOC=yes`. De compressed stream mét Atmos-objecten bereikt de AVSampleBufferAudioRenderer. `audiounit does not support spdif formats` is de normale doorval, geen fout, en de route-check van de fork is expliciet `(diagnostic only)` — hij blokkeert niets.
- **`audio-exclusive` is een dood spoor.** De AO-lijst in de meegeleverde libmpv is `audiounit, avfoundation, lavc, null, pcm`; `coreaudio` en `wasapi` — de enige twee consumenten van die optie — ontbreken.
- **Een MPVKit-bisect is niet nodig**: de Atmos-sink in 1.0.16 is aantoonbaar functioneel.
- **De app kan niet zien dát Atmos werkt.** Tijdens de lopende bitstream logt de fork `audio rendering mode: not-applicable`. De app leest exact dezelfde `AVAudioSession.renderingMode` (`AudioSessionPlugin.swift:137`) en `audioRenderingLabel()` mapt dat op `null`, dus de badge zwijgt precies wanneer hij iets zou moeten zeggen. `AudioOutputCoordinator.decision` bestaat, is gedocumenteerd "for the player's rendering badge", en heeft geen enkele lezer.
- **Loudness-normalisatie en passthrough sluiten elkaar uit** en niets coördineert dat. Voor afspeelsnelheid bestaat die guard al (`player_native.dart:311-323`). Android TV arbitreert het conflict zelfs al, maar andersom: `ExoPlayerCore.kt:1952-1955` blokkeert direct output zodra normalisatie aanstaat, terwijl de coordinator `passthrough` blijft rapporteren — daar liegt de badge vandaag. Zie [DEC-013](DECISIONS.md#dec-013).

### Nog te doen
- **De meting op de Apple TV zelf ontbreekt nog.** Alle logs tot nu toe komen van de iPhone. Build 212 staat al op het toestel, dus de meting kan zonder nieuwe build.
- Implementatie van DEC-013 (arbiter, badge uit de beslissing, `auto` op digitale poorten). Plan: `~/.claude/plans/pleya-v2-8-0-211-ios-smooth-frog.md`.

## [2026-08-08] — Blu-ray ISO's en uitgepakte BDMV-mappen afspelen

### Added
- **Een `.iso` is geen stream maar een UDF-filesysteem**, dus mpv kon hem niet demuxen en een ISO was simpelweg onzichtbaar in de app (commit `de48dbb`). De zware helft bleek al aanwezig: de meegeleverde mpv is gebouwd met `-Dlibbluray=enabled`, linkt `bd_open`/`bd_get_main_title`, en `Libbluray.framework` zit in de bundle. Die libbluray bevat udfread en opent een `.iso` rechtstreeks zonder mounten — er was dus geen fork-rebuild nodig, alleen de Dart-kant die mpv vertelt dat dit een schijf is. `detectDiscSource()` (`lib/mpv/disc_source.dart`, nieuw) classificeert een pad als ISO, BDMV-map of gewoon bestand; `player_native.dart`, `local_folder_client.dart` en de speler-foutafhandeling sluiten daarop aan. 97 regels tests in `test/mpv/disc_source_test.dart`.

## [2026-08-07] — Atmos-grondslag op Apple, en Seerr zegt wat er misging

### Added
- **Dolby Atmos en spatial audio op iOS en tvOS** (commit `87c5e04`, build 207). Op AirPods gaf de app stereo waar andere spelers Atmos gaven, en de oorzaak zat niet in mpv: de app riep nergens `setSupportsMultichannelContent(true)` aan. Zonder die opt-in rapporteert de route twee kanalen, ziet `ao_audiounit` `outputNumberOfChannels <= 2` en downmixt hard naar stereo — er valt dan niets meer te spatializen. Daarbovenop sloot `supportsAudioPassthrough()` iOS en Apple TV uit, dus het bitstream-pad lag óók dicht. Nieuw: `shared/apple/AudioSession/AudioSessionPlugin.swift` zet de sessie op `.moviePlayback` plus de multichannel-opt-in en publiceert route-, spatial- en renderingMode-wijzigingen; `AudioOutputCoordinator` en de pure `decideAudioOutput()` kwamen erbij met 385 regels tests.
  - Let op: dezelfde commit introduceerde de auto-passthrough die in build 211 werd teruggedraaid, zie de entry van 2026-08-09.

### Fixed
- **Ontdekken toonde altijd "Something went wrong. Try again."** (commit `24f9054`). `SeerrClient` onderscheidt 401 en 403 netjes en de teksten `errorAuth`/`errorForbidden` bestonden al, maar het scherm keek alleen naar `isNetwork`. Een verlopen sessie of een ontbrekend recht las dus als "probeer opnieuw", terwijl opnieuw proberen daar per definitie niets aan verandert. De soort fout wordt nu geclassificeerd in `lib/utils/seerr_error_message.dart` en per rij bijgehouden; faalt alles, dan wint de meest specifieke melding.

---

Ouder dan dit (3 juli tot en met 6 augustus 2026): zie
[docs/archive/CHANGELOG-tot-2026-08-06.md](archive/CHANGELOG-tot-2026-08-06.md).
