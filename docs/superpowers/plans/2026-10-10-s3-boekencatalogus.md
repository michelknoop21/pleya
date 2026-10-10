# Pleya Server S3: boekencatalogus (PS-14), pakket A van contractvenster 3

Werkmap: `pleya_server/` plus `docs/pleya-protocol/`, de bibliotheekroutes in `pleya_web/`, de
Dart-contracttest in `test/pleya_server/` en fixtures in `pleya_verify/fixture_server/`. Branch: een
nieuwe `feat/pleya-server-s3-boeken`, afgesplitst van `github/main`. Masterlijstrijen: S3.1 tot en
met S3.6, plus de voorgestelde S3.0.

Doel: een `books`-bibliotheek uit `PLEYA_SERVER_LIBRARIES` of `POST /libraries` wordt gescand zonder
de gedeelde scanlogica te splitsen, en een gebruiker met leesrecht haalt via `/ebooks` de lijst, één
titel, de cover en het EPUB-bestand op, met een hervatbare overdracht onder een sterke validator.
Het contract is pakket A uit [docs/pleya-server-contract-window-3.md](../../pleya-server-contract-window-3.md),
hoofdstuk 2 en 8, en niets daarbuiten.

Buiten deze slice: zoeken en filteren op `/ebooks` en de auteurs- en reekslijsten (pakket D2, S5.4),
de artworkladder voor covers (S4.5; `width` wordt in S3 gelezen en levert het origineel), manifest en
publicatiebestanden (pakket E), leesvoortgang (pakket F), boekschermen op web (S9) en in de app
(S14). Ook buiten: elke downloadmanager, elk model voor halve bestanden, elke downloadstatus-API
(PS-14 hoofdstuk 3, aanscherping bij beslissing 2).

Bronnen, in deze volgorde lezen: DEC-149 (PR #250), [docs/pleya-server-ps14-proposal.md](../../pleya-server-ps14-proposal.md)
(hoofdstuk 5 tot en met 14, de zeven bindende beslissingen), het contractvoorstel hoofdstuk 1 en 2,
rebaseline H.1 tot en met H.3 en J.6 (`0013`), K (security), DEC-050 en specificatie 13.2 (waarom
`/stream` geen `206` na `If-Range` geeft), DEC-128 punt 7 en 8.

## Preflight (uitgevoerd 2026-10-10)

| Controle | Uitkomst |
| --- | --- |
| `git fetch github`, `git log github/main` | `main` voorbij `7ebcdb80`; venster 2 dicht (DEC-146). Geen S3-commit op een remote branch. |
| Open PR's | #250 legt DEC-149 vast: PS-14 vrijgegeven, S3 vrij, en S3.1 pas na het ontwerp van venster 3 met een eigen DEC. Geen PR raakt `internal/scanner`, `internal/catalog`, `/ebooks` of `openapi.yaml`. |
| Worktrees | `feat/ebooks` (app-kant, stil sinds 6 september) en `pleya-docs-ps14` (masterlijst en DECISIONS). Geen worktree met serverwerk aan boeken. |
| Code | `LibraryKinds = {"movies","shows"}` (`internal/config/libraries.go:23`); `Classify` kent video, ondertitel, beeld (`internal/nameparse/nameparse.go:60`); `processMedia` probeert vóór `attach` naar de soort kijkt (`internal/scanner/scanner.go:518`, `:664`); `Store.LibraryIsEmpty` kijkt alleen naar `media_items` (`internal/catalog/store_write.go:812`); `Store.DeleteLibrary` is één `DELETE` die op cascade leunt (`:825`); `handleArtwork` leest `width` en levert het origineel (`internal/api/handlers_media.go:29`); de Dart-contracttest telt 78 fixtures (`test/pleya_server/pleya_wire_contract_test.dart:156`). Migraties tot en met `0012`. |
| Voorwaarden | de poortmeting laag C, de venster-DEC en de validator-DEC bestaan nog niet; zie taak 0 en 0b. |

Herhaal deze preflight bij de start; het geplande migratienummer `0013` geldt alleen als er op dat
moment niets anders boven `0012` staat.

## Volgorde en poorten

1. Taak 0, de laag C-meting (DEC-128 punt 7), met verslag.
2. De venster-DEC (contractvoorstel hoofdstuk 11), genomen door Michel en vastgelegd door de eigenaar
   van DECISIONS. DEC-149 zegt: eerst het venster met een eigen DEC, pas daarna S3.1.
3. Taak 1 tot en met 4.
4. De validator-DEC (taak 0b), vóór taak 5; hij dekt de sterke `ETag` van cover én bestand.
5. Taak 5 tot en met 7.

## Global Constraints

- Geen vermelding van AI, model of leverancier in code, comments, commits of documenten; geen
  `Co-Authored-By` of sessieregel. Auteur is Michel Knoop.
- Commits met `SKIP_HOOKS=1`. Toegestane paden: `pleya_server/`, `docs/`,
  `pleya_verify/fixture_server/`; in `pleya_web/`: `src/routes/libraries/`, `src/routes/server/+page.svelte`
  (toont `library.kind` als tekst), nieuwe componenten en hun tests in `src/lib/components/` (de
  logica hoort daar en niet in een route, want de webtests staan naast de componenten),
  `src/lib/i18n/web.ts` en `src/lib/api/schema.d.ts` (opnieuw gegenereerd, nooit met de hand); en
  `test/pleya_server/pleya_wire_contract_test.dart`. Geen Dart in `lib/`.
- Geen overschrijding van het contract: alleen wat pakket A noemt. Een veld, parameter of route die
  daar niet staat is een vraag aan de eigenaar, geen commit.
- `scripts/check_protocol.sh` en `pleya_server/scripts/verify-protocol.sh` groen na elke commit.
  Daarom landt de YAML van een onderdeel in dezelfde commit als de handler die het antwoord levert:
  `check_server_responses.py` eist dat elk antwoordschema door een echte serverrespons gedekt wordt,
  en een commit met alleen contract maakt `verify-protocol.sh` rood. Zo ging S2 ook.
- Go alleen via `pleya_server/scripts/go-tool.sh`. Volledige suite met
  `GO_IMAGE=pleya-server-test:go-ffmpeg scripts/go-tool.sh test ./...` na
  `eval "$(scripts/test-db.sh up)"` en `scripts/test-image.sh`, met **0 SKIP**: tel met
  `go-tool.sh test -v ./... | grep -c -- '--- SKIP'` en zet de uitkomst in het taakrapport.
- Raadpleeg Context7 voor elke Go-, pgx-, Svelte- of vitest-API die nog niet in de codebase staat
  (`archive/zip`, `encoding/xml` met `Strict`, `http.ServeContent`), met bronvermelding in het
  rapport.
- Bestanden onder 400 regels; één verantwoordelijkheid per bestand. `scanner.go` is al groot: de
  dispatch per soort gaat naar een eigen bestand.
- Commentaar in het Nederlands, het waarom, in de stijl van de omliggende bestanden.
- Bewijs per taak: testuitvoer, de SKIP-telling, en bij contracttaken de uitvoer van beide
  protocolscripts. Rapport en briefs in `.superpowers/sdd/2026-10-10-s3-boekencatalogus/`.
- Geen `git push`, geen merge. `docs/PLEYA-SERVER-MASTERLIST.md` en `docs/DECISIONS.md` alleen via
  de eigenaar van die bestanden; dit plan levert de tekst aan in taak 7.
- Taken strikt na elkaar; elke taak eindigt met een eigen commit.

## Niveau en review

Twee niveaus. **Protocol en security**: werk aan het contract, aan onvertrouwde invoer, aan
autorisatie of aan data-integriteit; de uitvoerder heeft het PS-14-voorstel volledig gelezen.
**Mechanisch**: werk dat een vastgelegd ontwerp volgt zonder eigen keuzes.

| Taak | Onderwerp | Niveau | Review |
| --- | --- | --- | --- |
| 0 | Poortmeting laag C: proxy en meetverslag | protocol en security (proxy); meting door Michel op hardware | eigen gate |
| 0b | Tekst voor de validator-DEC | protocol en security | eigenaar DECISIONS |
| 1 | Migratie, soort `books`, leegtecontrole, verwijderen (S3.1) | protocol en security | groep 1 |
| 2 | EPUB-analyser met zip- en XML-grenzen (S3.2) | protocol en security | groep 1 |
| 3 | Scannerdispatch per soort (S3.3) | protocol en security | groep 1 |
| 4 | Contract en handlers voor lijst, detail, `item_count`, `library.wrong_kind` (S3.4) | protocol en security | groep 2 |
| 5 | Cover- en bestandsroute met sterke validator (S3.5) | protocol en security | groep 2 |
| 6 | Capability, webafhandeling, fake-server, NAS-stopcriterium (S3.6) | mechanisch | lichte review |
| 7 | Bookkeeping-tekst voor masterlijst en gates | mechanisch | eigenaar |

Groep 1 (taak 1 tot en met 3) en groep 2 (4 en 5) krijgen elk één gebundelde review door
een reviewer die niets bouwde, met Critical, Important en Minor. Het risico in groep 1 is
datacorruptie en een gesplitste scanner, in groep 2 een lek in autorisatie of een validator die
liegt. Taak 6 is mechanisch, op de webafhandeling na, die in de lichte review expliciet bekeken wordt.

## Task 0: Poortmeting laag C (voorgestelde S3.0)

DEC-128 punt 7 en DEC-149 punt 4: vóór `books` in het contract landt, staat vast hoe uitgeleverde
app-builds de soort werkelijk behandelen. PS-14 beslissing 5 legt het instrument vast.

Bouw een omkeerproxy onder `pleya_server/tools/books-gate-proxy/` (eigen `main`, build tag
`gatetool`, buiten `-tags release` en buiten de Docker-image). Hij herschrijft precies twee
antwoorden: `GET /pleya/v1/libraries` krijgt één extra regel met `kind: "books"`, en
`GET /pleya/v1/libraries/{die id}/items` geeft een lege pagina. Al het andere gaat ongewijzigd door.

Tests: een Go-test met `httptest` die bevestigt dat alleen die twee antwoorden veranderen, en een
controle dat `go build -tags release ./cmd/...` het pakket niet meeneemt. Negatieve controle:
verander het herschreven pad en zie de eerste test falen.

Meting, door Michel op hardware: iOS, tvOS en één desktopbuild uit TestFlight of de laatste release,
op de vier meetpunten uit PS-14 11.2, met schermafbeeldingen. Verslag in
`docs/pleya-server-ps14-gate-c.md`. Zonder verslag geen venster-DEC, en zonder venster-DEC start
taak 1 niet.

Commit: `feat(pleya-server): omkeerproxy voor de PS-14-poortmeting, buiten de releasebuild`.

## Task 0b: Tekst voor de validator-DEC

Schrijf de DEC-tekst die PS-14 beslissing 2 vraagt en lever hem aan de eigenaar van DECISIONS. Hij
adresseert DEC-050 expliciet: de digest wordt bij de scan berekend over een bestand van enkele
megabytes (meet de grootste EPUB op de NAS en noem het getal); hij bedient twee lezers (de `ETag` en
de publicatiedigest van P5), dus de zin "geen full-file hashing die alleen HTTP bedient" valt er niet
door om; de grens is de route: `/stream` houdt zijn zwakke validator. Het besluit dekt ook de sterke
`ETag` van de coverroute (A5), die eveneens bytes uit een niet door Pleya beheerd bestand belooft. Geen commit in deze repo tenzij
de eigenaar daarom vraagt; zonder geaccepteerde DEC start taak 5 niet.

## Task 1: Migratie, soort `books`, leegtecontrole, verwijderen (S3.1)

**Migratie** `00NN_books.sql` (gepland `0013`): `libraries.kind` CHECK opnieuw met `books`;
`publications` en `publication_files` zoals H.2, met de indexen en foreign keys uit J.6 0013
(`library_id` RESTRICT, `publication_id` CASCADE, `storage_location_id` RESTRICT). `content_sha256`
is `NOT NULL`. Geen backfill. `0002` blijft onaangeroerd (checksum).

**Configuratie**: `LibraryKinds` krijgt `books`, foutmelding op de parserregel bijgewerkt.

**Leegte, één definitie.** Breid de bestaande `Store.LibraryIsEmpty`
(`internal/catalog/store_write.go:812`) uit: leeg is geen `media_items` én geen `publications` aan de
bibliotheek. Geen nieuwe functie ernaast. Gebruik hem op twee plekken: `PATCH /libraries/{id}`
(bestaat al, `library.not_empty`) en de soortwissel in `SyncLibraries` (PS-14 beslissing 4). Die
laatste weigert binnen dezelfde transactie een wissel op een niet-lege bibliotheek, met een fout
die bibliotheek, huidige en gevraagde soort noemt; geef `LibraryIsEmpty` daarvoor een variant die op
een `pgx.Tx` draait, met dezelfde query.

**Verwijderen.** `Store.DeleteLibrary` (`:825`) is één `DELETE` die op de cascade uit `0002` leunt.
Met `publications.library_id` RESTRICT faalt dat voor een boekenbibliotheek, en
`publication_files.storage_location_id` RESTRICT blokkeert ook het wegvallen van de
`storage_locations`. Maak er één transactie van: eerst de publicaties van de bibliotheek
verwijderen (hun bestanden gaan mee via `publication_id` CASCADE), het aantal tellen en loggen, dan
de bibliotheek. J.6 koos RESTRICT juist zodat dat aantal zichtbaar wordt. Geen bestand op schijf
wordt aangeraakt, zoals nu.

Interfaces: publicatietypes in `internal/catalog/publications.go` (nieuw).

Tests: migratietest op de NAS-fixture (`nas_fixture_test.go`): na de migratie dezelfde ids, slugs,
`managed`, `watch_states` en `item_count` (J.7). Soortwissel: `films=books:/media/Films` op een
gevulde filmbibliotheek weigert en laat geen rij gewijzigd achter; op een lege bibliotheek slaagt
hij. Verwijderen: een boekenbibliotheek met twee publicaties gaat weg, het log noemt 2, en er blijft
geen `publication_files`-rij over; een filmbibliotheek verwijderen werkt ongewijzigd (bestaande
tests groen). Negatieve controles: haal `publications` uit `LibraryIsEmpty` en zie de test met een
gevulde boekenbibliotheek die naar `movies` gaat falen; haal de publicatiestap uit `DeleteLibrary`
en zie de verwijdertest falen op de foreign key.

Commit: `feat(pleya-server): soort books, publicatietabellen, één leegtecontrole en verwijderen met RESTRICT (S3.1)`.

## Task 2: EPUB-analyser met zip- en XML-grenzen (S3.2)

Nieuw pakket `internal/ebooks/epub`. Het enige onderdeel dat onvertrouwde bestanden ontleedt, dus de
grenzen zijn het werk.

```go
type Limits struct {
    MaxEntries    int   // aantal zip-entries
    MaxEntryBytes int64 // uitgepakt, per entry die gelezen wordt
    MaxTotalBytes int64 // uitgepakt, opgeteld over alle gelezen entries
    MaxRatio      int   // uitgepakt gedeeld door gecomprimeerd, per entry
    MaxXMLBytes   int64 // container.xml en OPF
    MaxXMLDepth   int
}
func DefaultLimits() Limits
type Metadata struct { /* velden van Publication uit het contract, plus CoverHref, CoverMediaType */ }
func Analyze(r io.ReaderAt, size int64, lim Limits) (Metadata, error)
func ReadEntry(r io.ReaderAt, size int64, href string, lim Limits) (io.ReadCloser, string, error)
func Digest(r io.Reader) (string, error) // SHA-256, hex
```

Regels: `mimetype` moet `application/epub+zip` zijn; `META-INF/container.xml` naar de OPF; XML met
`Decoder.Strict` en een `DOCTYPE` geweigerd (geen entiteiten, geen externe verwijzingen); paden
genormaliseerd met `path.Clean`, en een voorloopslash, `..` buiten de root, een backslash of een NUL
geweigerd. Deze normalisatie wordt de functie die pakket E en F later hergebruiken. Een
`META-INF/encryption.xml` met iets anders dan lettertype-obfuscatie geeft `ErrEncrypted`: Pleya doet
geen DRM, het bestand wordt gelogd en overgeslagen. `description` gaat naar platte tekst. Cover via
`properties="cover-image"`, anders de EPUB 2-`meta name="cover"`, anders geen.

Tests met fixtures die de test zelf bouwt: een geldige EPUB 3 en EPUB 2; een zip-bom (ratio boven de
grens); te veel entries; een entry met `../../etc/passwd`; een `DOCTYPE` met entiteiten; een OPF
boven `MaxXMLBytes`; diepte boven de grens; ontbrekende `container.xml`; `encryption.xml` met een
Adobe-algoritme; een HTML-beschrijving met `<script>`. Fuzztest `FuzzAnalyze` met de geldige
fixtures als corpus, 60 seconden in het rapport. Negatieve controle per grens: verhoog de grens in de
test tot boven de fixture en zie de test falen.

Commit: `feat(pleya-server): EPUB-analyser met grenzen op zip, XML en paden (S3.2)`.

## Task 3: Scannerdispatch per soort (S3.3)

`Walk` krijgt de soorten die de bibliotheek accepteert (parameter op de bestaande functie, geen
tweede wandeling). `Classify` krijgt `KindEbook` voor `.epub`, die alleen in een `books`-bibliotheek
wordt doorgelaten. De verdeling na `judge` krijgt een derde emmer. De analyse wordt per soort gekozen
vóór het analyseren: ffprobe voor `movies` en `shows`, de analyser uit taak 2 voor `books`. Nieuwe
bestanden `internal/scanner/dispatch.go` en `internal/scanner/publications.go`; `scanner.go` krijgt
alleen de aanroep.

Tellers op `Stats`: `ProbesRun` en `EpubsAnalyzed` (acceptatiecriterium 5). De guard bij nul
bestanden (`scanRoot`) geldt ongewijzigd ook voor boekenroots.

Tests: een boekenbibliotheek met drie EPUB's en één `.mkv` levert drie publicaties en nul probes;
een filmbibliotheek met een `.epub` levert nul analyses; hernoemen van een EPUB behoudt het
publicatie-id; een verdwenen EPUB krijgt `missing_since`. **De bestaande tests in
`internal/scanner/` blijven ongewijzigd groen**: `git diff --stat github/main -- internal/scanner/scanner_test.go internal/scanner/library_test.go`
is leeg (PS-14 hoofdstuk 7). Negatieve controle: laat de dispatch ffprobe ook voor `books` aanroepen
en zie de nul-probes-test falen.

Commit: `feat(pleya-server): scannerdispatch per bibliotheeksoort, boeken zonder ffprobe (S3.3)`.

**Gebundelde review groep 1** na deze taak.

## Task 4: Contract en handlers voor `/ebooks`, `item_count`, `library.wrong_kind` (S3.4)

Eén commit, omdat `verify-protocol.sh` anders rood wordt.

**Contract.** `openapi.yaml`: A1 tot en met A4 en A7 tot en met A10 uit het contractvoorstel, exact,
inclusief de zin dat een client `kind: books` pas stuurt wanneer `capabilities.ebooks` waar is
(de vlag zelf staat met default `false` in het schema; de server zet hem in taak 6 aan). A5 en A6
komen in taak 5, samen met hun handlers. Fixtures uit hoofdstuk 7 van het voorstel voor deze
onderdelen, opgenomen in `examples/manifest.json`. `pleya_web/src/lib/api/schema.d.ts` opnieuw
gegenereerd. `test/pleya_server/pleya_wire_contract_test.dart`: het aantal fixtures van 78 naar 84,
en `Publication` en `PublicationPage` in `deferredSchemas` met de toelichting "app-consument in S14".
Specificatie `docs/pleya-protocol-v1.md`: 3.2 (`Library.kind` noemt `books`), 7.1
(`library.wrong_kind`), 9.1, een nieuw hoofdstuk voor `/ebooks`, de twee afwijkingen van het
PS-14-voorstel uit hoofdstuk 1 van het contractvoorstel, en 16.4 met de nieuwe matrixregels.

**Handlers.** `internal/api/handlers_ebooks.go` (nieuw), leesfuncties in
`internal/catalog/store_publications.go` (nieuw). Autorisatie via `MayAccess` en `VisibleLibraries`
zonder wijziging. `item_count` telt publicaties voor `books`. `/libraries/{id}/items` op een
boekenbibliotheek en `/ebooks?library_id=` op een andere soort geven `library.wrong_kind`, maar pas
nadat de zichtbaarheid gecontroleerd is: een onzichtbare bibliotheek geeft eerst `404`. De cursor
volgt de bestaande bewaking per sortering. De vangst voor `verify-protocol.sh` krijgt een
boekenbibliotheek, zodat `Publication` en `PublicationPage` door echte antwoorden gedekt zijn.

Tests: matrixtests in de stijl van `authorize_matrix_test.go`: gebruiker zonder recht krijgt `404` op
lijst en detail; `restricted` ziet alleen toegewezen bibliotheken; `/ebooks?library_id=` op een
onzichtbare filmbibliotheek geeft `404` en niet `400`. `item_count` op een boekenbibliotheek met twee
publicaties is 2. Negatieve controles: verwijder de bibliotheekautorisatie uit de detailhandler en
zie de matrixtest falen; zet de soortcontrole vóór de zichtbaarheidscontrole en zie de `404`-test
falen.

Acceptatie: `scripts/check_protocol.sh`, `verify-protocol.sh` en
`flutter test test/pleya_server/pleya_wire_contract_test.dart` (gepinde SDK) groen; de negatieve
controles van `check_protocol.sh` bijten nog (een tijdelijke enum zonder `x-unknown-safe` faalt).

Commit: `feat(pleya-server): /ebooks-lijst en -detail met contract, item_count voor boeken, library.wrong_kind (S3.4)`.

## Task 5: Cover- en bestandsroute met sterke validator (S3.5)

Pas na de validator-DEC. Eén commit met de YAML voor A5 en A6, hun matrixregels in 16.4, de
specificatietekst over de validator naast 13.2 (de twee routes gedragen zich expres verschillend op
`If-Range`) en de handlers. Cover: bytes uit de zip via `ReadEntry` met dezelfde grenzen, content-type
uit het OPF, `ETag` uit digest plus coverpad, `width` gelezen en genegeerd met dezelfde
commentaartekst als `handleArtwork`; na S4.5 komt de trede in de `ETag`. Bestand: `ETag: "<sha256>"`, `Content-Disposition` met
`filename*`, `Range` en `If-Range` volgens RFC 9110. Alleen wanneer `If-Range` exact de huidige
sterke validator noemt een `206`; anders `200` vanaf byte 0. Wijkt grootte of mtime op schijf af van
de rij, dan levert de server geen `206` en markeert hij het bestand voor de volgende scan: een sterke
validator mag niet liegen.

Tests: matrixtests voor cover en bestand (`404` zonder recht); `Range` zonder `If-Range` geeft `206`; `If-Range` met de juiste `ETag` geeft `206`; met een
andere of een zwakke `ETag` `200` met het hele bestand; een na de scan vervangen bestand geeft geen
`206`; een onvervulbaar bereik geeft `416` `playback.range_not_satisfiable`; `/stream` ongewijzigd
(bestaande tests groen). Negatieve controle: laat de handler `If-Range` negeren en zie de test met
de afwijkende `ETag` falen.

Commit: `feat(pleya-server): cover en EPUB met sterke validator en hervatbare overdracht (S3.5)`.

**Gebundelde review groep 2** na deze taak.

## Task 6: Capability, webafhandeling, fake-server, stopcriterium (S3.6)

**Capability.** `capabilities.ebooks` op `true`: de vlag volgt de software (contractvoorstel
hoofdstuk 1, bewuste afwijking van PS-14 hoofdstuk 10).

**Pleya Web, een echte afhandeling.** Een boekenbibliotheek in de webclient mag niet naar
`/libraries/{id}` linken, want die pagina vraagt `/items` en krijgt `library.wrong_kind` als
foutstaat. Tot S9 de boekschermen levert:

- Nieuw `src/lib/components/LibraryTile.svelte` met een kleine helper `libraryKind.ts` ernaast
  (icoon en of de soort te openen is). `routes/libraries/+page.svelte` gebruikt de tegel: een
  `books`-bibliotheek krijgt een eigen icoon en de telling, zonder link (geen knop die naar niets
  leidt). De icoonkeuze op regel 22 (`kind === 'shows' ? 'show' : 'movie'`) verdwijnt, en een
  onbekende soort valt niet langer stil terug op `movie`.
- `routes/libraries/[id]/+page.svelte`: de keuze of er items geladen worden gaat naar een functie
  in `src/lib/components/libraryKind.ts`, `itemsLoaderFor(kind, client)`, die voor `books` en voor
  een onbekende soort `null` teruggeeft. Bij `null` roept de pagina `libraryItems` niet aan en toont
  ze een staat zonder fout die zegt dat boeken in deze versie van de webclient nog niet te openen
  zijn. De route zelf heeft dan geen logica die een eigen test vraagt.
- `routes/server/+page.svelte` toont `library.kind` als ruwe tekst; die regel gaat via dezelfde
  helper naar een vertaalde soortnaam. Elke andere plek die `session.libraries` tekent (zoek met
  `grep -rn "session.libraries" src`) volgt dezelfde regel.
- Teksten via `t()`, sleutels in `src/lib/i18n/web.ts`.

Vitest, in `src/lib/components/LibraryTile.test.ts` en `libraryKind.test.ts`: een `books`-tegel
rendert zonder `href`; `itemsLoaderFor('books', client)` geeft `null` en de mock-client telt nul
aanroepen van `libraryItems`; voor `movies` en `shows` roept de loader `libraryItems` precies één
keer aan; een fictieve soort `sculptures` krijgt geen filmicoon en geen loader. Negatieve controle:
laat `itemsLoaderFor` voor elke soort een loader geven en zie de `books`-test falen. `bun run check`,
`bun run test`, `bun run build` groen.

**Fake-server en suite.** `pleya_verify/fixture_server` serveert de nieuwe fixtures. Volledige suite
met 0 SKIP, beide protocolscripts groen.

**Stopcriterium** (PS-14 hoofdstuk 13) op de NAS, na Michels go voor de deploy en met credentials
via `/grant`: een boekenbibliotheek met echte EPUB's; gebruiker met recht haalt lijst, detail, cover
en bestand met `curl`; een tweede gebruiker zonder recht krijgt op elk ervan `404`; een onderbroken
download hervat met `Range` en `If-Range`, en de SHA-256 van het resultaat is gelijk aan
`file.sha256`. Uitvoer in het rapport.

Commit: `feat(pleya-server): capability ebooks aan, boekenbibliotheken netjes in Pleya Web (S3.6)`.

## Task 7: Bookkeeping

Aan de eigenaar van de masterlijst en DECISIONS, met het tekstblok uit hoofdstuk 10 van het
contractvoorstel als basis: S3.0 tot en met S3.6 met bewijs, S3.6 als "pakket A van venster 3
geland", de regel in `docs/pleya-server-gates.md`, de matrixregel in hoofdstuk 11 van de replacement
matrix, en de opmerking dat PS-7A er een tweede route bij heeft (PS-14 hoofdstuk 8). Het venster
blijft open voor de andere pakketten.

## Open punten voor de eigenaar

- De masterlijst heeft geen rij voor de laag C-meting. Voorstel: S3.0.
- Taak 0 en de stap op de NAS in taak 6 vragen hardware en een deploy-go; die kan dit plan niet zelf
  afvinken.
