# CLAUDE.md voor Pleya Server

Deze map is de Go-mediaserver. `README.md` ernaast beschrijft installeren, bedienen en wat er op de
NAS gemeten is; dat wordt hier niet herhaald. Dit bestand gaat over wat je moet weten voordat je een
regel in deze map wijzigt.

De werkregels per fase staan in de sectie Pleya Server van [../CLAUDE.md](../CLAUDE.md) en gelden
onverkort: lees hoofdstuk 23 plus je eigen fase, blijf binnen de Phase ID, bouw niets uit een latere
fase vooruit, en schrijf geen latere productvereiste weg. **De huidige fase is PS-9.**

Eén stuk werk loopt daar bewust naast: de lege hubs `continue_watching` en `next_up` in `handleHub`
zijn met [DEC-073](../docs/DECISIONS.md) aangemerkt als defect in het gesloten PS-4, en worden als
zodanig gecorrigeerd. Datzelfde besluit voegt PS-4E, PS-7N en PS-7A toe aan de roadmap; geen van
drieën is begonnen.

`internal/web/` hoort niet bij deze fase maar bij PS-3W, een aparte afwijking met een eigen voorstel in
[../docs/pleya-server-ps3w-proposal.md](../docs/pleya-server-ps3w-proposal.md).

## Er staat geen Go op deze machine, en dat is opzet

De toolchain draait in dezelfde gepinde image die de container bouwt. `go build` of `go test`
rechtstreeks aanroepen werkt niet.

```sh
scripts/go-tool.sh vet ./...
scripts/go-tool.sh test ./...
scripts/go-tool.sh test ./internal/scanner/ -run TestNaam -v
scripts/go-tool.sh mod tidy
```

Twee soorten tests vragen iets vooraf, en **slaan zichzelf over als het er niet is**. Een groene run
zonder deze twee bewijst dus minder dan hij lijkt: kijk naar de `--- SKIP`-regels voordat je "tests
groen" opschrijft.

```sh
scripts/test-image.sh                     # Go-toolchain plus dezelfde gepinde ffmpeg
eval "$(scripts/test-db.sh up)"           # wegwerp-Postgres, zet PLEYA_TEST_DATABASE_URL
GO_IMAGE=pleya-server-test:go-ffmpeg scripts/go-tool.sh test ./...
scripts/test-db.sh down
```

`testsupport.Pool(t)` geeft per test een vers schema in die ene database en ruimt het aan het eind
weer op, dus een test hoeft zelf niets te wissen. De schemateller staat achter geen mutex, dus zet er
geen `t.Parallel()` bij. De scannertests maken hun eigen mediabestanden met ffmpeg: de analyse
namaken bewijst niets over de analyse.

## Geen enkele CI-poort dekt deze map

Gecontroleerd: geen workflow in `.github/workflows/` noemt `pleya_server`, en `scripts/ci_checks.sh`
(de pre-commit-gate) is Flutter en Dart. Go-wijzigingen komen dus ongetoetst door de hook heen. Wat
er wel is, draai je zelf:

```sh
scripts/verify-local.sh        # vijftien secties, 72 controles, van go vet tot een kijkstatusronde
scripts/verify-protocol.sh     # antwoorden van een draaiende server tegen openapi.yaml
../scripts/check_protocol.sh   # het contract zelf, in een gepinde Python-container
```

Er is geen formatteringscontrole. `verify-local.sh` sectie 2 draait `go vet` en `go test`, meer niet.

## Wat waar staat

```
cmd/pleya-server/   main, bootstrap-identiteit, scanwerk als jobhandler, plus het subcommando
                    `healthcheck` dat de Dockerfile als HEALTHCHECK aanroept
internal/api/       HTTP-laag, wire-types, foutcodes, rate limiter, range en streamsessies
internal/auth/      Argon2id, tokens, streamsessies, ondertekensleutel op schijf
internal/catalog/   domeintypes, cursor, store gesplitst in lezen en schrijven
internal/config/    alle PLEYA_SERVER_*-variabelen, bibliotheken, inodevertrouwen
internal/ffprobe/   aanroep en omzetting naar detectiemetadata
internal/fileid/    de stat-tupel achter de zwakke validator, per platform
internal/id/        eigen UUIDv7, monotoon binnen een milliseconde
internal/jobs/      duurzame wachtrij in dezelfde database
internal/migrate/   voorwaartse migraties, sql/ als embed
internal/scanner/   walk, judge, signature, sidecars, inode per platform
internal/watch/     het conflictmodel uit DEC-049 als pure functie, plus zijn opslag
internal/testsupport/  wegwerpschema en mediabestanden voor tests
```

## Regels die je stil kunt breken

**Het wire-contract ligt vast.** `../docs/pleya-protocol/v1/openapi.yaml` is bevroren zolang de
lopende fase loopt, niet aan een vast fasenummer gehangen (DEC-068): een anker op een specifiek
nummer veroudert stilzwijgend zodra die fase een opengelaten voorganger heeft. Het venster ging twee
keer eerder open: bij het sluiten van PS-3, voor de drie poortbesluiten (DEC-049, DEC-050, DEC-051),
en voor PS-9, voor precies de zeven wijzigingen uit DEC-068 (gebruikers-, sessie- en
logout-endpoints, `device_id`/`device_name`, `capabilities.sessions`, nieuwe foutcodes). Dat venster
is na stap 1 van de PS-9-implementatievolgorde alweer gesloten. Een probleem daarin is een
protocolwijziging langs de zes compatibiliteitsregels uit hoofdstuk 3 van de specificatie, en niet een
aanpassing in de YAML omdat het zo uitkomt.

**Wire-types leven alleen in `internal/api`.** Domeintype en wire-type zijn twee dingen met een
expliciete mapper ertussen (hoofdstuk 12.1). De foutcode is het contract; het bericht is voor logs en
een client mag er nooit op matchen.

**Endpoints die er niet horen te zijn, blijven weg.** Sinds PS-4 antwoorden `stream/{version_id}`,
beide kijkstatus-endpoints en `POST /auth/stream-session`; `capabilities.watch_state`,
`watch_state_ownership` en `stream_sessions` staan op `true`. Wat er níét is blijft 404:
`playback/plan` (PS-6), sessies (PS-8), gebruikers (PS-9), verzamelingen (PS-9C), geschiedenis
(PS-9P) en beheer (PS-11A). `verify-local.sh` en `TestScopeBoundaryAfterPS4` controleren dat.

**Kijkstatus heeft een eigenaar.** De zes regels staan in
[DEC-049](../docs/DECISIONS.md); de beslissing zelf staat als pure functie in
`internal/watch/watch.go`, met de database eromheen in `store.go`. Wie een regel wijzigt raakt
`Decide` en niet een SQL-statement: een regel die alleen in een query bestaat is niet te testen
zonder een reeks aanvragen na te spelen. `Apply` vergrendelt de rij, want zonder dat lezen twee
gelijktijdige events dezelfde revision en is de causaliteitsclaim waardeloos.

**De `ETag` op `/stream` is zwak, en dat is een besluit.**
[DEC-050](../docs/DECISIONS.md) haalt de byte-identity-belofte uit het contract: Pleya beheert de
bestanden niet, en RFC 9110 §8.8.1 vraagt strict revision control of een hash over de bytes.
`If-Range` levert daarom altijd `200`. Schrijf nergens code die op een gelijke validator vertrouwt om
bytes aan elkaar te plakken.

**Tabellen uit latere fasen bestaan niet.** Geen `play_history`, `play_sessions`, `user_item_data`,
`external_ids`, `metadata_candidates` of `transcode_sessions`. `watch_states` en `stream_sessions`
staan er sinds PS-4; `users`, `sessions` en `library_permissions` sinds migratie 0007 (PS-9, DEC-065
en DEC-069). De lijst in hoofdstuk 17.2 (die van het protocol; het schema staat in hoofdstuk 16 en
17 van [de specificatie](../docs/pleya-protocol-v1.md)) beschrijft het hele v1-product en niet deze
fase; `verify-local.sh` en `internal/migrate/migrate_test.go` controleren allebei welke tabellen er
staan.

**`watch_states.subject` en `stream_sessions.subject` zijn sinds migratie 0007 `uuid` met een FK naar
`users(id)`.** De vaste string `"owner"` (het vroegere `api.SubjectOwner`, sinds AC2 verwijderd) is
daar niet meer geldig voor. `handlers_watch.go` en `authorize.go` lezen het subject nu overal via
`s.subjectID(r)` (`claims.Subject`, gevalideerd met `id.Parse`) rechtstreeks uit de context van de
aanvraag; `auth.Store.OwnerUserID(ctx)` blijft alleen bestaan voor setup, login en refresh, die geen
aanvraag met claims hebben om uit te lezen. De owner krijgt sinds PS-9 een echte, per installatie
verschillende `users.id` (vóór een migratie via `gen_random_uuid()`, bij een verse setup via
`id.New()`).

**Migraties gaan alleen vooruit.** Genummerd in `internal/migrate/sql/`, uitgevoerd bij het opstarten
onder een advisory lock, met een checksum per toegepaste migratie. De binary weigert te starten op een
nieuwere database, en `MinVersion` in `migrate.go` (nu 3) is de ondergrens aan de andere kant: onder
die schemaversie stopt hij ook. Hij blijft op 3 en niet op 4: hij bewaakt een database waar de
migraties zijn overgeslagen, en een schema 3 dat deze binary tegenkomt wordt gewoon naar 4 gebracht.
Neerwaartse migraties bestaan bewust niet: terugrollen gebeurt met een back-up.

**De ffmpeg-pin in de `Dockerfile` is hard**, en de basis is Debian en geen Alpine. Beide staan in
[DEC-044](../docs/DECISIONS.md#dec-044-debians-ffmpeg-blijft-in-de-image-en-ps-8-is-het-herzieningsmoment) en hoofdstuk 22 uitgelegd; een build die luid faalt op een
verdwenen versie is het doel, niet de bijwerking.

## Kleinigheden die tijd kosten

- **De code is Nederlands.** Commentaar, foutteksten en testnamen. Een pakketcommentaar legt uit
  waarom iets zo is en verwijst naar het hoofdstuk dat het vastlegt; volg dat, ook in nieuw werk.
- **`data/`, `.env`, `.responses/` en `.gocache/` staan in `.gitignore`.** De ondertekensleutel
  (`data/config/token-signing.key`, rechten 0600) staat bewust op schijf en niet in Postgres: een
  databasedump mag geen sessies opleveren.
- **`.dockerignore` houdt `scripts/`, `README.md` en `deploy-nas.sh` uit de image.** Een nieuw script
  dat de container nodig heeft, komt er dus niet vanzelf in.
- **De scanner leest bytes op mounts waar de inode niets betekent.** Dat is de duurste post in een
  ronde en het staat per root in de database, gemeten en niet aangenomen
  ([DEC-043](../docs/DECISIONS.md#dec-043-de-inodebetrouwbaarheid-staat-per-root-in-de-database-en-wordt-gemeten-en-niet-aangenomen)). `PLEYA_SERVER_INODE_TRUST` overrulen vraagt een meting
  over een echte umount, niet een containerherstart.
- **`grouping_key` is geen identiteit.** Hij hangt een nieuw gevonden bestand aan een bestaand item en
  komt nooit langs bij een bestand dat al bekend is ([DEC-040](../docs/DECISIONS.md#dec-040-grouping-key-en-identiteit-zijn-twee-dingen-in-het-catalogusschema)).
