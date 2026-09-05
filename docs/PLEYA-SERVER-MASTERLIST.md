# Pleya Server masterlijst

De afvinklijst voor de ontwikkeling van Pleya Server. Dit bestand is de enige plek waar de
voortgang staat: één regel per taak, met status, bewijs en datum. Wie wil weten hoe ver het
staat, leest dit; wie wil weten waarom iets zo is, leest `docs/pleya-server-rebaseline/`.

**Bijwerken is onderdeel van het werk, niet iets achteraf.** Elke commit die een taak afmaakt,
zet in dezelfde commit de status om en vult het bewijs in. Een taak die zonder bewijs op
`gereed` staat, telt als open.

| Legenda | Betekenis |
| --- | --- |
| `[ ]` open | nog niet begonnen |
| `[~]` bezig | er ligt werk, nog niet af |
| `[x]` gereed | af, met bewijs in de kolom ernaast |
| `[!]` geblokkeerd | wacht op iets, met de reden erbij |
| `[-]` vervallen | bewust niet gedaan, met de reden erbij |

Bewijs is een commit-sha, een testnaam, een meting of een bestandspad. "Werkt" is geen bewijs.

Laatst bijgewerkt: 2026-09-05 (S1.3 gesloten, planning als hoofdstuk 2 erbij). Bron voor de scope: `docs/pleya-server-rebaseline/`
deel I (slices) en deel O (Definition of Done).

---

## 1. Stand in één blik

| Blok | Slices | Gereed | Bezig | Open |
| --- | --- | --- | --- | --- |
| Fundament en integratie | S0 | 1 | 0 | 0 |
| Backend basis | S1 tot S6 | 0 | 1 | 5 |
| Web | S7 tot S13 | 0 | 0 | 7 |
| Clients en agents | S14, S16 | 0 | 0 | 2 |
| Uitgebreide scope | S17 tot S25 | 0 | 0 | 9 |
| Afronding | S15 | 0 | 0 | 1 |
| **Totaal** | **26** | **1** | **1** | **24** |

Per taak, en dat is de maat die telt: **148 taken, 13 gereed, 2 bezig, 133 open.** S0 is dicht met
acht van acht. S1 staat op drie van acht en is de lopende slice; de twee andere gereed-vinkjes zijn
mockupgoedkeuringen die met poort P3 al binnen waren (S12.1 en S13.1).

Gesloten vóór dit traject en niet in deze lijst: PS-0, PS-1, PS-2, PS-3, PS-3W, PS-4, PS-9.
Keuzefase na afronding: PS-12 (Plex-migratie). Buiten scope: PS-13, PS-16, app-reader (PS-15).

**Waar het nu op wacht.** S0 is dicht en de Roadmap Drift Check erop staat in `STATUS.md`. **PS-11A
loopt**, en S1 is de lopende slice. Het protocolvenster voor S1 is geopend met
[DEC-110](DECISIONS.md) en staat nog open: het sluit bij S1.6. [DEC-111](DECISIONS.md) corrigeert
DEC-110 op één punt: venster 1 voegt twee foutdomeinen toe en niet één. PS-14 blijft gesloten tot PS-11A af en
geïntegreerd bewezen is; dat is een volgorde, geen voorkeur.


---

## 2. Planning: de volgorde van hier naar af

Dit hoofdstuk beslist niets. De afhankelijkheidsgraaf staat in
`docs/pleya-server-rebaseline/I-master-implementation-plan.md` (I.1), de stand per taak in
hoofdstuk 3 hieronder; wat hier staat is die twee naast elkaar gelegd, zodat de vraag "wat moet er
nog gebeuren en in welke volgorde" één antwoord heeft. Wie een andere volgorde kiest die dezelfde
afhankelijkheden respecteert doet niets fout.

### 2.1 De golven

Elke golf is een topologisch niveau: alles erin kan pas beginnen als de golf ervoor staat, en
binnen een golf is de volgorde vrij. De kolom "taken" telt wat er open of bezig is.

| Golf | Slices | Taken | Wat het oplevert | Wacht op |
| --- | --- | --- | --- | --- |
| 1, loopt | S1, S2 | 11 | beheer-backend compleet: instellingen, diagnostiek, tokens, audit, bibliotheken, opslag, scans | niets |
| 2 | S3, S4, S5, S6 | 22 | de catalogus verbreedt: boeken, `.nfo`-sidecars, artworkladder, filters en facetten, leesvoortgang | S1 voor S2; poort P5 vóór S6 |
| 3 | S14, S16 | 12 | de Flutter-clients en de MCP-beheerlaag komen op het verbrede contract | S1, S3, S5, S6 |
| 4 | S7, S8, S9, S10, S11, S12, S13 | 32 | Pleya Web: shell en designsysteem, consumer, boeken, beheer, setup-wizard, reader, speler | S7 kan meteen; de rest hangt aan golf 2 en 3 |
| 5 | S17, S18, S23 | 15 | afspelen op eigen kracht: PlaybackPlan, transcode, downloads | S14 |
| 6 | S19, S20, S21 | 15 | verzamelingen en afspeellijsten, persoonlijke laag, realtime | S1, S6, S2 |
| 7 | S22 | 9 | metadata-providers met automatisch matchen en artwork | S4 |
| 8 | S24, S25 | 11 | remote hardening en observability, back-up, restore, upgrade, faalpaden | S1, S2 |
| slot | S15 | 8 | hardening, veertien golden journeys, documentatie, Plex-off gate, merge naar `main`, NAS | alles |
| keuze | PS-12 | 0 | Plex-migratie, met een eigen vrijgave na S15 | Michel |

**S22 staat laat en hoeft dat niet.** Hij kan starten zodra S4 staat, en hij is de zwaarste losse
slice die er is. Hij staat hier achteraan omdat hij niets blokkeert, niet omdat hij moet
wachten; wie ruimte heeft trekt hem naar voren.

### 2.2 De kritieke lijn

`S1 → S3 → S5 en S6 → S14 → S17 → S18 → S23 → S15`. Vertraging daarop schuift de release op;
vertraging op de rest niet, zolang alles vóór S15 klaar is. Deel I noemt dezelfde lijn, met S22 als
zwaarste slice ernaast.

De web-tak (S7 tot S13) hangt er in zijn geheel naast en is qua taken de grootste van allemaal: 32
van de 135 resterende. Hij blokkeert alleen S15.

### 2.3 Wat op een besluit wacht en niet op code

| Wat | Blokkeert | Stand |
| --- | --- | --- |
| **P5, het locatorbesluit** (Readium Locator plus publicatie-digest, S6.1) | S6, en via S6 ook S9, S12, S14, S16, S20 en S21 | open; RB-12 is bijgesteld in deel E, het besluit zelf moet nog als DEC |
| **Pushen naar `origin`** | niets technisch, wel elk verlies bij een schijfstoring | de branch bestaat op `origin` maar loopt er dertien commits op voor; pushen vraagt Michels go |
| **PS-12 vrijgeven** | niets; het is een keuzefase | pas ná S15, met een eigen besluit |
| Mockups 50, 51 en 36 | S12.1, S13.1, deel van S22.6 | goedgekeurd met poort P3 op 4 september; S12.1 en S13.1 zijn daarmee gesloten, S22.6 houdt de bouw van scherm 29 en 36 over |

### 2.4 De poorten die nog dicht staan

P5 (locator), P6 (acht protocolvensters geopend en gesloten), P7 (PS-5-hardwareronde, uitgesteld),
P8 (Plex-off gate). Van de acht protocolvensters is er één open: venster 1, bij S1, met zeven van
zeventien rijen erin. De volledige stand staat in hoofdstuk 4.

### 2.5 Twee dingen die deze planning kunnen omgooien

**Een protocolvenster dat te vroeg dichtgaat.** Elk venster opent en sluit met een DEC, en een rij
die er niet in zat kost een nieuw besluit plus een nieuwe compatibiliteitstoets. De zeventien rijen
van venster 1 landen daarom per commitgrens en niet in één klap, en dat patroon geldt voor de zeven
vensters erna net zo.

**De hardwareronde.** P7 is uitgesteld en niet vervallen: `docs/qa/ps5-hardware-round.md` noemt drie
startvoorwaarden. Hij moet uiterlijk vóór de eerstvolgende publieke release die PS-5- of PS-9-gedrag
bevat, en hij staat als S15.6 in de laatste golf. Blijft hij daar liggen, dan schuift de release en
niet de bouw.

---

## 3. Slices

### S0 Fundament

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S0.1 | Proefmerge met `main` in een wegwerp-worktree, conflictlijst in `merge-log.md` | `[x]` | `docs/pleya-server-rebaseline/merge-log.md`: 196 tegen 49 commits, 14 conflictbestanden, 26 schoon; wegwerp-worktree opgeruimd | 2026-09-04 |
| S0.2 | Integratiebranch vanaf `main`, `feat/pleyaserver` erin gemerged | `[x]` | `integration/pleya-server-rebaseline` vanaf `a21b43c`, merge-commit `4e78b16` | 2026-09-04 |
| S0.3 | Veertien conflicten opgelost, codegen sluitend, geen testregressie | `[x]` | `4e78b16`: geen van de vijf voorspelde conflicten deed zich voor, maar de merge droeg wel main's `app_database.g.dart` (9379 regels) onder de samengevoegde bron (11706); codegen herstelde dat. `flutter analyze` 0/0, `flutter test` 6263 groen met 83 bekende falers (78 goldens, 5 die op `a21b43c` zelf ook falen, nagemeten), `drift_relations_test` groen. Webfallout apart in `d7ba84a` | 2026-09-04 |
| S0.4 | DEC-hernummering naar de eerstvolgende vrije reeks in de samengestelde boom (niet blind 096, VRAGENLIJST 59), mappingtabel, grep schoon | `[x]` | twaalf botsingen (063 tot 073 plus 093) naar 096 tot 107; mappingtabel onderaan `docs/DECISIONS.md`; 242 verwijzingen per regel geclassificeerd, geen anker gebroken (de ankers die niet kloppen deden dat op beide takken al) | 2026-09-04 |
| S0.5 | CI-jobs `pleya-server`, `pleya-web`, `protocol` groen | `[x]` | run `33909897646` op `integration/pleya-server-rebaseline`: Pleya Server (Go), Pleya Web en Protocol Contract alle drie groen. Vier ronden nodig; drie fouten die alleen op een Linux-runner bovenkwamen, elk apart gecommit. `Code Analysis` en `Unit Tests` blijven rood, maar zijn dat op `main` zelf ook: 53 falers daar, 53 hier, met 117 tests meer die slagen | 2026-09-04 |
| S0.6 | NAS-migratiefixture (schema 7, geanonimiseerd) | `[x]` | `pleya_server/internal/testsupport/fixtures/nas-schema7.sql`, een gerichte steekproef uit de draaiende NAS: 131 items, 242 versies, 712 bestanden, 964 streams, alle 4 kijkstatussen en alle 219 refreshtokens. `TestNASFixtureSurvivesMigrationToHead` en `TestNASFixtureCoversTheShapesItWasSampledFor` in `internal/migrate/nas_fixture_test.go` zijn groen; negatieve controle gedraaid (fixture zonder `watch_states` laat beide falen). Lekcontrole: 2495 identificerende waarden uit de ruwe vangst, geen ervan in de fixture, en de controle slaat wel aan op een vervuilde kopie. De structuur van de draaiende database is gelijk aan wat `0001` tot en met `0007` opleveren. Herkomst, bemonstering en grenzen in `docs/pleya-server-nas-fixture.md`; de migratiestap is nu leeg omdat NAS en code beide op 7 staan, en dat staat er expliciet bij | 2026-09-04 |
| S0.7 | Contracttest fake-server tegen `openapi.yaml` (**poort P9**, blokkerend voor "contractueel compleet") | `[x]` | **De dekkingslijst.** `scripts/check_server_responses.py` leidt hem nu af uit `openapi.yaml`: elk schema dat het contract als JSON-antwoordlichaam noemt, met de `components/responses`-indirectie opgelost en niet-JSON-lichamen (artwork, ondertitels, stream) eruit. Dat brengt de eis van 8 naar 15 en dekt `UserList`, `SessionList` en `LibraryPermissionList`. Uit de vangst afleiden zou de poort tautologisch maken; uit het contract afleiden laat hem vanzelf meegroeien. Echte vangst van 32 antwoorden lokaal gedraaid met `GO_IMAGE=pleya-server-test:go-ffmpeg` en `PLEYA_RESPONSE_DIR=/src/.responses` (het containerpad binnen de mount, daar ging het eerder mis): alle 15 gedekt, alle 32 valide. Negatieve controle: met `UserList`, `SessionList` en `LibraryPermissionList` uit de vangst geeft de oude poort exit 0 met "de server houdt zich aan het contract" en de nieuwe exit 1 met de drie endpoints erbij. De afleiding heeft zes eigen controles op een verzonnen contract (`bijt de afleiding`). **De fake server.** `pleya_verify/fixture_server/test/pleya_fake_server_contract_test.dart` legt 15 antwoorden vast in dezelfde manifestvorm en toetst ze met dezelfde validator, via `--subset` omdat die fixture bewust 10 van de 15 schema's bedient. Hij vond bij de eerste run meteen drift: `LibraryKind` is `movies`/`shows` en de seed gebruikte het enkelvoud. Negatieve controle: `protocol.major` op een string zetten geeft exit 1 met de veldnaam erbij. Beide controles draaien in CI, in `pleya-server` en in `protocol`. | 2026-09-04 |
| S0.8 | Vrijgavebesluit PS-14 en PS-11A vastgelegd | `[x]` | [DEC-108](DECISIONS.md#dec-108-ps-11a-is-de-eerstvolgende-fase-ps-14-blijft-gesloten-en-loopt-er-niet-naast): PS-11A vrijgegeven zodra de blokkerende S0-poorten groen zijn, PS-14 blijft gesloten en mag er niet naast lopen | 2026-09-04 |

### S1 Beheer-basis

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S1.1 | Recovery-middleware, lichaamslimiet, securityheaders op de API | `[x]` | `pleya_server/internal/api/middleware.go`: `chain()` legt de volgorde vast (logging, recovery, securityheaders, lichaamslimiet) en `Handler()` en de tests gebruiken diezelfde functie, zodat een test geen volgorde kan bewijzen die niet draait. Een panic komt terug als `server.internal` 500 met `details.request_id`, en die id is dezelfde als op de logregel met de stack; de stack blijft in het log. `http.ErrAbortHandler` gaat door, anders wordt elke afgebroken seek een foutmelding, en een panic ná het eerste blok plakt geen envelop achter een half antwoord. De lichaamslimiet verhuisde van `decodeBody` (alleen auth) naar de middleware en gebruikt `http.MaxBytesReader` in plaats van `io.LimitReader`, want die laatste kapt stil af. `X-Content-Type-Options: nosniff` en `Referrer-Policy: no-referrer` staan nu ook op `/pleya/v1`, op de heenweg gezet zodat ze ook op het 500-antwoord staan. Zes tests in `middleware_internal_test.go`, elk met een negatieve controle die rood draaide: recovery eruit, securityheaders eruit, `MaxBytesReader` terug naar `LimitReader`, `Flush` van de wrapper af. **Bijvangst.** `statusRecorder` slikte `http.Flusher` op, waardoor de doorspoellus in `handlers_stream.go:284` sinds de logging-middleware stil oversloeg: hij testte rechtstreeks op de interface en die assertie was altijd false. `Flush` en `Unwrap` staan er nu op, met een test die het bewaakt. Bewijs: `go test ./...` groen, `check_server_responses.py` 15 van 15 op een echte vangst van 33 antwoorden, `check_protocol.sh` groen | 2026-09-05 |
| S1.2 | `server_settings` met `GET`/`PATCH /settings`, grenzen, hot reload | `[x]` | **Migratie.** `0008_server_settings.sql` volgt J.6 en draagt ook 0008b (`sessions.kind`, `scope`, `token_hash`, `expires_at` en `admin_audit`), want J.6 zet die in hetzelfde bestand en 0009 hoort bij S2; de endpoints erop komen met S1.5. De tabellencontrole in `internal/migrate` noemt beide nieuwe tabellen, en de NAS-fixture van S0.6 migreert door naar 8. **Laagmodel.** `internal/settings/` houdt zes sleutels met de grenzen uit K rij 14 (naam 1 tot 64 tekens, access 1m tot 60m, refresh 24h tot 2160h, stream 1m tot 15m, streamsessie 5m tot 120m, streamsessies 1 tot 32). De omgeving is de onderste laag, de tabel de bovenste, en `source` per sleutel zegt welke van de twee levert. Bindadres, proxy's, paden en sleutel staan er bewust niet in; `TestDangerousKeysAreNotSettings` legt dat vast op de plek waar het te breken is. **Hot reload is gemeten en niet aangenomen.** Na `PATCH access_token_ttl=30m` draagt het eerstvolgende token 1800000 ms in plaats van 900000, toont `GET /server` de nieuwe naam, en weigert met `max_stream_sessions: 1` de tweede streamsessie met 429. Daarvoor werd `MaxActiveStreamSessions` van constante naar parameter van `CreateStreamSession`. **Grenzen en weigeringen.** Drie rollen op beide endpoints, met de weigering van een lid byte-gelijk aan die van een beheerhandeling op een ander; een waarde buiten de grens geeft 400 `settings.invalid_value` met `field`, `minimum` en `maximum`; een onbekende sleutel valt op de gesloten body; een patch met een geldige en een ongeldige sleutel wijzigt er nul; een waarde in de tabel die de grenzen niet meer haalt wordt overgeslagen en de omgeving wint. Regel 16 van de autorisatiematrix (hoofdstuk 16.4) is de bijbehorende rij, conform K.3. **Bewijs.** `go test ./...` groen met de ffmpeg-image en de wegwerp-Postgres (twaalf tests in `internal/settings`, acht in `internal/api/settings_test.go`); `check_protocol.sh` groen (24 paden, 49 fixtures, 7 foutdomeinen); `check_server_responses.py` op een echte vangst van 35 antwoorden: 16 van 16 gedekt, met `Settings` op beide endpoints; web `check` 0/0 over 546 bestanden, `api:check` bij, `test` 114 groen, `build` groen; `flutter test test/pleya_server/` 243 groen. **Bijvangst.** Twee lijsten in `pleya_server/README.md` liepen sinds PS-9 achter (dertien tabellen, achttien operaties) en stonden naast de nieuwe sectie te tegenspreken; ze staan nu op achttien tabellen en achtentwintig operaties. Hoofdstuk 18 van de protocolspecificatie telde er vijfentwintig waar er zesentwintig stonden | 2026-09-05 |
| S1.3 | `GET /server` uitgebreid, `/server/environment`, `/server/log`, `connectivity-check`, `rotate-signing-key` | `[x]` | **Vier endpoints en acht velden.** `GET /server` groeit met de klasse van de aanvrager en niet met een parameter: een lid krijgt het antwoord dat het altijd kreeg, een beheerder krijgt er `public_url`, `listen`, `behind_proxy`, `trusted_proxies[]`, `build`, `database{version,schema}`, `ffprobe{found,version}` en `health{ready,jobs_running,jobs_failed}` bij. `GET /server/environment`, `GET /server/log?level=&limit=`, `POST /server/connectivity-check` en `POST /server/rotate-signing-key` staan er als klasse admin naast. `requesterIsAdmin` is bewust verdraagzaam waar `requireAdmin` dat niet is: op `GET /server` is "geen beheerder" het antwoord wanneer de rollenquery hapert, want dat is het endpoint waarmee een client zijn kop tekent. **K rij 11.** Het log komt uit `internal/logging/ring.go`, een ringbuffer van 500 regels in het geheugen, en nooit uit een bestand; de bovengrens van `?limit=` is diezelfde 500. De redactie zit op de weg de buffer **in**, zodat er geen leespad is dat hem kan overslaan en een token ook niet in het geheugen blijft wachten op een lezer. `internal/logging/redact.go` is de derde port van de denylist van de app en draait op de gedeelde vectoren uit `pleya_verify/redact/cases.json`: alle 18 groen, met de lookaround en de terugverwijzing vertaald naar RE2 (gevangen voorafgaand teken, gecontroleerde waarde, en drie scheidingstekens die in de vervanger vergeleken worden). `scripts/go-tool.sh` koppelt de repository-wortel daarvoor alleen-lezen op `/repo`; een kopie toetsen zou de vraag die de test stelt onbeantwoordbaar maken. `GET /server/environment` toont alleen `PLEYA_SERVER_*` plus een gemaskeerde `DATABASE_URL`, en een naam die een geheim aankondigt gaat er per woord in zijn geheel af (`PLEYA_SERVER_ACCESS_TOKEN_TTL` wordt `[REDACTED]`; de TTL staat met bron en grens in `GET /settings`). **K rij 13.** `public_url` is de zevende instelling geworden, met een vormgrens in plaats van een lengtegrens: absolute http(s)-URL, geen inloggegevens, querystring of fragment, en geen letterlijk privé-, loopback- of link-local-adres. Een **naam** wordt niet opgezocht, en de omgevingslaag valt er buiten, allebei met de reden erbij in hoofdstuk 17a.2 van de specificatie. De check zelf heeft geen aanvraagbody, kent daardoor maar één doel, heeft een vaste time-out van 5 s en volgt geen omleidingen; `api.NewProbeClient` is gedeeld met de test, zodat het omleidingsbeleid dat getoetst wordt dat van de server is. `range_intact` vraagt zestien bytes van de bundel en eist `206` met `Content-Range`, want een proxy die ranges wegbuffert breekt direct play uit PS-4. **K rij 15 en 16.** `rotate-signing-key` vraagt `confirm: "rotate"`, trekt **eerst** elke sessie in en vervangt **daarna** pas de sleutel (andersom laat een mislukte schrijfactie dode accesstokens naast levende refreshtokens achter, en dan logt elke client zich meteen weer in), schrijft de sleutel via een tijdelijk bestand met rename op 0600, en antwoordt 204 zonder de sleutel. `TestAdminAnswersCarryNoSecrets` doorzoekt alle vijf de antwoorden op het DSN-wachtwoord, de ondertekensleutel, het accesstoken en het refreshtoken. **Afwijking, expliciet.** J.2 laat de foutkolom van rotate-signing-key leeg terwijl K rij 16 een 409 eist; K is de specifiekere en is gevolgd, met `server.confirm_mismatch` in het domein dat DEC-111 al had geopend. Het foutpatroon in het contract draagt die code dus zonder schemawijziging. **Contract.** Zeven van de zeventien J.2-rijen staan er nu in (foutdomein, settings, `GET /server`, environment, log, connectivity-check, rotate), elk met fixture en manifestregel: `server_detail_admin.json`, `server_environment.json`, `server_log.json`, `connectivity_check.json`, `error_confirm_mismatch.json`, plus `public_url` in `settings.json`. Autorisatiematrix (hoofdstuk 16.4) van zestien naar eenentwintig regels; hoofdstuk 17b is nieuw; hoofdstuk 18 van achtentwintig naar tweeëndertig operaties. **Bewijs.** `scripts/go-tool.sh vet ./...` schoon en `test ./...` groen met de wegwerp-Postgres en de ffmpeg-image, nul `--- SKIP`; `check_protocol.sh` groen (28 paden, 70 componenten, 14 enums, 54 fixtures, 7 foutdomeinen); echte vangst met `PLEYA_RESPONSE_DIR=/src/.responses` gevolgd door `check_server_responses.py`: 19 van 19 schema's gedekt, met `ServerEnvironment`, `ServerLog` en `ConnectivityCheck` erbij; `pleya_web` `api:generate` plus `api:check` sluitend, `check` 0/0 over 546 bestanden, `test` 114 groen, `build` groen; `flutter test test/pleya_server/` 245 groen (de drie nieuwe schema's zijn expliciet uitgesteld naar de webbeheerder, `ServerDetail` niet, want die parst beide fixtures). **Zeventien negatieve controles**, elk gedraaid en rood bevonden: identiteits-`Redact`; buffer zonder redactie; kapotte ringomloop; ongefilterde Postgres-versie; iedereen beheerder; `requireAdmin` vervangen door `resolveRequester`; weggevallen naamruimtefilter op de omgeving; ongemaskeerde DSN; `probeInfo` die bereikbaarheid beweert; client die omleidingen volgt; `probeRange` die altijd intact zegt en die altijd niet-intact zegt; rotatie zonder intrekking; toegelaten privé-adres; rotatie zonder `confirm`; weggevallen vormcontrole bij het opstarten; proxycontrole die elk adres vertrouwt. Eén achttiende mutatie kwam gróén terug en staat er daarom bij: `probeRange` die ook een `200` als intact telt, wordt door `TestConnectivityCheckSeesABrokenRange` niet gevangen, omdat de kapotte proxy in dat scenario ook geen `Content-Range` zet en meer bytes stuurt dan gevraagd. De twee vervangende controles (`probeRange` die altijd waar of altijd onwaar geeft) klemmen de eigenschap wel van twee kanten; de statusregel afzonderlijk is niet geïsoleerd getoetst. | 2026-09-05 |
| S1.4 | `GET /stream-sessions`, `GET /users/me`, foutcode `auth.permission_not_allowed` | `[ ]` | | |
| S1.5 | API-tokens als sessies, `admin_audit` met het uitgebreide bereik | `[ ]` | | |
| S1.8 | HttpOnly-refreshcookie, web-origin, externe URL, CORS-beleid (RB-29) | `[ ]` | | |
| S1.6 | Capability `administration`, protocolvenster 1 dicht | `[~]` | venster geopend met [DEC-110](DECISIONS.md) op 5 sep 2026, voor precies de zeventien wijzigingen uit J.2; sluit zodra `openapi.yaml`, de fixtures en de gegenereerde webclient bij zijn en `check_protocol.sh` groen is. Eerste stukken staan: het foutdomein, met S1.2 rij 2 (`GET`/`PATCH /settings` met `Settings`, `SettingsPatch` en de vier hulpschema's), en met S1.3 de rijen 3 tot en met 7 (`GET /server` uitgebreid, `/server/environment`, `/server/log`, `connectivity-check`, `rotate-signing-key`) plus `public_url` als zevende instelling binnen het schema van rij 2. Zeven van de zeventien staan er dus in; tien te gaan (rij 1, 8 tot en met 16). [DEC-111](DECISIONS.md#dec-111-venster-1-voegt-twee-foutdomeinen-toe-niet-een-settings-komt-er-naast-server-bij) telt er twee in plaats van één (`server` en `settings`), het patroon in `openapi.yaml` draagt ze, `error_server_internal.json` en `error_settings_invalid_value.json` leggen ze vast, elke operatie draagt `500 InternalError`, en `check_error_domains` in `check_protocol.py` meet de andere kant op (patroon terug op vijf domeinen: twee regels rood). Met het domein erbij gaat `writeInternal` mee van `storage.unavailable` naar `server.internal`, met twee tests die de twee kanten van dat onderscheid vastleggen. De overige rijen van J.2 landen bij de commitgrens die ze bedient, want de contractpoort eist dekking voor elk antwoordschema en zou anders rood staan tot S1.6 | |
| S1.7 | Drie-rollen-test over elke nieuwe route | `[ ]` | | |

### S2 Bibliotheken, opslag, scans

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S2.1 | Migratie `0009`, `managed`, scaninstellingen op `libraries` | `[ ]` | | |
| S2.2 | CRUD op `/libraries` met `confirm` bij verwijderen | `[ ]` | | |
| S2.3 | `GET /storage/roots` uit de mounts, recheck | `[ ]` | | |
| S2.4 | Scans en jobs over HTTP, annuleren, retry, backoff op `probe_attempts` | `[ ]` | | |
| S2.5 | `.env`-overname met dezelfde id en slug | `[ ]` | | |
| S2.6 | Migratietest op de NAS-fixture, protocolvenster 2 dicht | `[ ]` | | |

### S3 Boekencatalogus (PS-14)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S3.1 | Migratie `0010`, `publications`, `publication_files`, soort `books` | `[ ]` | | |
| S3.2 | EPUB-analyser met zip- en XML-grenzen | `[ ]` | | |
| S3.3 | Scannerdispatch per bibliotheeksoort, bestaande scannertests ongewijzigd groen | `[ ]` | | |
| S3.4 | `/ebooks`-resources, `item_count`, `library.wrong_kind` | `[ ]` | | |
| S3.5 | Cover- en bestandsroute met sterke validator | `[ ]` | | |
| S3.6 | Capability `ebooks`, protocolvenster 3 dicht | `[ ]` | | |

### S4 Sidecars en artworkladder (PS-7N, PS-7A)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S4.1 | `.nfo`-parser inclusief cast en regie | `[ ]` | | |
| S4.2 | Dekkingsmeting met de 80%-poort per bibliotheek | `[ ]` | | |
| S4.3 | Velden op `Item`, migratie `0011` | `[ ]` | | |
| S4.4 | Artworkladder met cache en single-flight | `[ ]` | | |
| S4.5 | Boekcovers op dezelfde ladder | `[ ]` | | |
| S4.6 | Beheerendpoints artworkcache, YAML-tekst rechtgezet | `[ ]` | | |

### S5 Filters, facetten, zoeken

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S5.1 | Migratie `0012`, `pg_trgm` en indexen | `[ ]` | | |
| S5.2 | Filterparameters en extra sorteringen | `[ ]` | | |
| S5.3 | Facetten-endpoint met tellingen | `[ ]` | | |
| S5.4 | Boekenzoekweg en auteurs | `[ ]` | | |
| S5.5 | Injectietest en meting op de NAS, capability `filters`, venster 4 deel 1 | `[ ]` | | |

### S6 Leesvoortgang (PS-15 server)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S6.1 | DEC Readium Locator plus publicatie-digest, manifest en resources (RB-12 bijgesteld) | `[ ]` | | |
| S6.2 | Migratie `0013`, `reading_states`, pure functie | `[ ]` | | |
| S6.3 | `POST`/`GET /reading-state`, hydratie op `Publication` | `[ ]` | | |
| S6.4 | Toestelnaam bij laatst gekeken | `[ ]` | | |
| S6.5 | Capability `reading_state`, venster 4 deel 2 | `[ ]` | | |

### S7 Webshell en designsysteem

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S7.1 | Tokens, capsuleknop, base.css | `[ ]` | | |
| S7.2 | Layouts, topnav, mobiele kop, tabbalk met capability-slot | `[ ]` | | |
| S7.3 | Primitieven (chips, skelet, veld, paneel, tabel, tegel, alert, dialoog, stappen) | `[ ]` | | |
| S7.4 | `MediaCard` met alle staten uit scherm 16, hero, rail, `srcset` | `[ ]` | | |
| S7.5 | Nederlandse locale | `[ ]` | | |
| S7.6 | Bestaande zeven routes gemigreerd, axe groen op vijf breedtes | `[ ]` | | |

### S8 Web consumer (PS-4E)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S8.1 | Home met zes rijen, lege rij verdwijnt | `[ ]` | | |
| S8.2 | Films- en Series-landing | `[ ]` | | |
| S8.3 | Complete catalogus met filters en facetten | `[ ]` | | |
| S8.4 | Zoeken gesectioneerd, lege staat met uitweg | `[ ]` | | |
| S8.5 | Film- en seriedetail herschreven en gesplitst | `[ ]` | | |
| S8.6 | Mijn Pleya en staten | `[ ]` | | |
| S8.7 | PS-4E criteria 1, 2, 4, 5 gehaald | `[ ]` | | |

### S9 Web Boeken

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S9.1 | API-laag en kaarten met cover-fallback | `[ ]` | | |
| S9.2 | Landing en alle boeken met filters | `[ ]` | | |
| S9.3 | Boekdetail, ambience, downloaden | `[ ]` | | |
| S9.4 | Home-rijen en zoeken met boeken en auteurs | `[ ]` | | |

### S10 Web beheer (PS-11A frontend)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S10.1 | Adminlayout met zijbalk en rolgate | `[ ]` | | |
| S10.2 | Overzicht, bibliotheken, bewerken, verwijderen | `[ ]` | | |
| S10.3 | Opslag, scans en taken | `[ ]` | | |
| S10.4 | Gebruikers en gebruiker | `[ ]` | | |
| S10.5 | Media, metadata, netwerk, beveiliging, diagnostiek | `[ ]` | | |
| S10.6 | Agents en API-tokens (scherm 34), mobiele index (33) | `[ ]` | | |
| S10.7 | Als lid 404 op elke `/admin`-route, zonder beheeraanvraag | `[ ]` | | |

### S11 Setup-wizard

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S11.1 | Vier stappen, hervatbaar, gedane stappen overgeslagen | `[ ]` | | |
| S11.2 | Overnamevariant bij `.env`-bibliotheken | `[ ]` | | |
| S11.3 | Golden journey 1 groen | `[ ]` | | |

### S12 Webreader (PS-15W)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S12.1 | Mockup 51 (readerschil op `@readium/navigator`) goedgekeurd | `[x]` | gedekt door poort P3: mockup 51 is gebouwd, gereviewd (C.7) en op 4 september door Michel goedgekeurd, en zit met zijn gerenderde beeld in de APPROVED set met `SHA256SUMS`. Deze rij stond nog open omdat P3 zes mockups in één ronde afvinkte en de slice-rijen niet meebewogen | 2026-09-04 |
| S12.2 | Spike Readium TypeScript Toolkit tegen het manifest; epub.js alleen als gedocumenteerde contingency | `[ ]` | | |
| S12.3 | Reader met leespositie en client-local instellingen | `[ ]` | | |

### S13 Browserspeler (PS-4W)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S13.1 | Mockup 50 (spelerschil) goedgekeurd | `[x]` | gedekt door poort P3, op dezelfde grond als S12.1: gebouwd, gereviewd (C.7), akkoord Michel 4 september, in de APPROVED set met `SHA256SUMS` | 2026-09-04 |
| S13.2 | Schil met `<video>` op de streamsessie | `[ ]` | | |
| S13.3 | Kijkstatus met `session_id` en `base_revision` | `[ ]` | | |
| S13.4 | Ondertitelconversie naar WebVTT | `[ ]` | | |

### S14 Flutter-clients op het contract

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S14.1 | Nieuwe capabilities in `pleya_wire.dart` | `[ ]` | | |
| S14.2 | `_postJson`-fout dicht met regressietest | `[ ]` | | |
| S14.3 | Filterstubs vervangen, `refreshLibraryMetadata` werkend | `[ ]` | | |
| S14.4 | `PleyaServerBooksSource` met mappers | `[ ]` | | |
| S14.5 | Artworkladder in de imagecache-URL | `[ ]` | | |
| S14.6 | Verify-scenario voor de boekenbron | `[ ]` | | |

### S15 Hardening, journeys, docs, release

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S15.1 | Rate limit op `/auth/refresh`, opruimjob streamsessies | `[ ]` | | |
| S15.2 | Golden journeys 1 tot 14 groen | `[ ]` | | |
| S15.3 | Securitymatrix K.2 volledig groen, vastgelegd in `docs/qa/` | `[ ]` | | |
| S15.4 | Documentatie uit deel M compleet | `[ ]` | | |
| S15.5 | `PLEX_OFFLINE_REPLACEMENT_GATE` groen (migratie als keuze) | `[ ]` | | |
| S15.6 | PS-5-hardwareronde afgerond | `[ ]` | | |
| S15.7 | Merge naar `main`, NAS uitgerold | `[ ]` | | |
| S15.8 | Tweede TestFlight-gate tegen de releasecandidate (vraag 62) | `[ ]` | | |

### S16 MCP-beheerlaag

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S16.1 | Transport en toolregister op `/mcp` | `[ ]` | | |
| S16.2 | Leestools met dezelfde autorisatie | `[ ]` | | |
| S16.3 | Beheertools, destructief met `confirm` | `[ ]` | | |
| S16.4 | Auditlog en scherm 34 gevuld | `[ ]` | | |
| S16.5 | Generator uit `openapi.yaml`, contracttest tool tegen operatie | `[ ]` | | |
| S16.6 | Golden journey 8 groen | `[ ]` | | |

### S17 PlaybackPlan (PS-6)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S17.1 | Planner als pure functie met tabeltests | `[ ]` | | |
| S17.2 | `POST /playback/plan` met reden als code en parameters | `[ ]` | | |
| S17.3 | App en web sturen capabilities en volgen het plan | `[ ]` | | |
| S17.4 | Capability `playback_plan`, venster 5 deel 1 | `[ ]` | | |

### S18 Transcode (PS-8)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S18.1 | Migratie `0014`, sessiemodel | `[ ]` | | |
| S18.2 | ffmpeg-supervisie met vaste argumenten en time-out | `[ ]` | | |
| S18.3 | fMP4 en HLS, browserspeler met hls.js | `[ ]` | | |
| S18.4 | Hardwareversnelling gedetecteerd en zichtbaar | `[ ]` | | |
| S18.5 | Beheer: sessies zien en stoppen, instellingen; scherm 37 gebouwd | `[ ]` | | |
| S18.6 | Capability `transcode`, venster 5 deel 2, journey 9 | `[ ]` | | |

### S19 Verzamelingen en afspeellijsten (PS-9C)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S19.1 | Migratie `0015`, tabellen en zichtbaarheid | `[ ]` | | |
| S19.2 | Endpoints inclusief herordenen | `[ ]` | | |
| S19.3 | Web: schermen 17 en 18, "Toevoegen aan" op de kaart | `[ ]` | | |
| S19.4 | App: bestaande members geïmplementeerd | `[ ]` | | |
| S19.5 | Venster 6 deel 1, journey 11 | `[ ]` | | |

### S20 Persoonlijke laag (PS-9P, PS-9T)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S20.1 | Migratie `0016`, geschiedenis uit watch-state-events | `[ ]` | | |
| S20.2 | Favorieten en waarderingen | `[ ]` | | |
| S20.3 | Spoorvoorkeuren over toestellen | `[ ]` | | |
| S20.4 | Web scherm 19 en "Bekeken door" op detail | `[ ]` | | |
| S20.5 | App: `setFavorite`, `rate`, spoorkeuze | `[ ]` | | |
| S20.6 | Venster 6 deel 2 | `[ ]` | | |

### S21 Realtime (PS-11R)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S21.1 | Hub met volgnummers, `GET /events` met bearer in het eerste bericht | `[ ]` | | |
| S21.2 | Events gefilterd per zicht, `since=` dicht een gat | `[ ]` | | |
| S21.3 | Web en app abonneren met terugval op polling; scherm 38 gebouwd | `[ ]` | | |
| S21.4 | Capability `realtime`, venster 7 deel 1, journey 12 | `[ ]` | | |

### S22 Metadata-providers (PS-7)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S22.1 | Providerabstractie en kandidatenlaag, migratie `0017` | `[ ]` | | |
| S22.2 | TMDB-implementatie met rate-limit-backoff | `[ ]` | | |
| S22.3 | Automatisch matchen met driestapsregel en ambiguïteitslijst | `[ ]` | | |
| S22.4 | Automatisch artwork ophalen naar de cache op de ladder | `[ ]` | | |
| S22.5 | Correcties: bevestigen, afwijzen, fix-match, artwork kiezen met pin, per-field overrides met provenance | `[ ]` | | |
| S22.6 | Mockup 36 goedgekeurd, scherm 29 en 36 gebouwd met provenance per veld | `[~]` | de goedkeuring van mockup 36 is binnen met poort P3 (4 september); wat deze rij openhoudt is het bouwen van scherm 29 en 36 in `pleya_web` | |
| S22.7 | Attributie zichtbaar in web en app | `[ ]` | | |
| S22.8 | Correctie overleeft drie rondes, SSRF-grens getest, venster 8 | `[ ]` | | |
| S22.9 | PS-7 criteria 1 tot 4 op de NAS, journey 14 | `[ ]` | | |

### S23 Downloads (PS-10)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S23.1 | Migratie `0018`, `POST /downloads` met recht `download` | `[ ]` | | |
| S23.2 | Levering met digest, hervatten alleen bij gelijke digest | `[ ]` | | |
| S23.3 | App: bestaande wachtrij op de nieuwe bron, sync-back | `[ ]` | | |
| S23.4 | Web toont downloads op Mijn Pleya (scherm 11b) | `[ ]` | | |
| S23.5 | Capability `downloads`, venster 5 deel 3, journey 10 | `[ ]` | | |

### S24 Remote hardening (PS-11)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S24.1 | Vertrouwde proxy's, publieke URL, subpad | `[ ]` | | |
| S24.2 | Rate limits en de publieke-endpointlijst als test | `[ ]` | | |
| S24.3 | Prometheus-metrics op loopback | `[ ]` | | |
| S24.4 | Range-testset door twee proxy-opstellingen | `[ ]` | | |
| S24.5 | Deploymentrecepten in de operatordoc | `[ ]` | | |

### S25 Back-up, restore, upgrade, faalpaden (PS-11B)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S25.1 | Migratie `0019`, back-up gepland en handmatig | `[ ]` | | |
| S25.2 | Wekelijkse hersteltest met natellen | `[ ]` | | |
| S25.3 | Restore met onderhoudsmodus en bevestiging | `[ ]` | | |
| S25.4 | Upgrade-guard: back-up vóór migratie, weigering op nieuwere database | `[ ]` | | |
| S25.5 | Vier faalpaden met foutcodes en settest | `[ ]` | | |
| S25.6 | Scherm 35 gebouwd, journey 13 | `[ ]` | | |

### PS-12 Plex-migratie (keuzefase)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| PS-12.0 | Vrijgavebesluit door Michel na afronding van S15 | `[ ]` | | |

Start niet automatisch. Zolang PS-12.0 open staat, is geen enkele PS-12-taak toegestaan.

---

## 4. Poorten en releasevoorwaarden

| # | Poort | Status | Bewijs |
| --- | --- | --- | --- |
| P0 | Vragenlijst (`docs/pleya-server-rebaseline/VRAGENLIJST.md`) volledig beantwoord | `[x]` 4 sep 2026 | hoofdstuk 8; verwerking van 20 afwijkingen in de delen staat als P0a |
| P0a | De 20 afwijkingen uit VRAGENLIJST.md hoofdstuk 9 verwerkt in E, I, J, K, L, M, N | `[x]` 4 sep 2026 | E bijgestelde RB's en RB-29; I S1, S5, S6, S12, S18, S22, S24, S25; J venster 1, 0011, 0013, 0017; K.20; L; M.1; N.5 |
| P0b | Dezelfde afwijkingen doorgetrokken in D (mockup metadata-overrides), F, H, O en de masterlijsttaken (S1: cookie; S6: manifest; S22: overrides) | `[x]` 4 sep 2026 | D kop plus rijen 28, 29, 30, 31, 36, 37, 38 en de nummertabel in D.5; F auth (cookie, origin, audit), zoeken, artwork, reading, capabilities, uitgebreide scope, F.2; H kop, H.1 manifestrij, H.2 Readium Locator, H.4 locatorbinding, H.5, H.6; O kop, O.1 readerrij, O.2 functioneel, visueel, technisch, release, O.3; `DESIGN.md` h6 nummerregel; S1.8, S6.1 en S22.5 stonden al |
| P1 | Northstar-set goedgekeurd (consumer, beheer, setup) | `[x]` 4 sep 2026 | chatakkoord; APPROVED gemarkeerd met de laatste mockups erbij |
| P2 | Mockups 17, 18, 19, 28, 35 gereviewd en in het manifest, deel C en deel D | `[x]` 4 sep 2026 | reviewronde 3 in C.5 en C.6 (22 bevindingen, alle gecorrigeerd), manifest bijgewerkt, D.2 aangevuld, hele set opnieuw gerenderd (`f3d99e8`); akkoord Michel 4 sep 2026 |
| P3 | Zes mockups in één ronde: 11b downloads, 36 metadata-match en overrides, 37 transcode-sessies, 38 realtime-status, 50 speler, 51 reader; daarna APPROVED met SHA256SUMS | `[x]` 4 sep 2026 | zes gebouwd en zelf gereviewd (C.7, 6 bevindingen, alle gecorrigeerd); akkoord Michel 4 sep; set op APPROVED met `SHA256SUMS` over 46 schermen, 91 beelden, de bronnen, `web.css` en `build.mjs` |
| P4 | Branch merget schoon met `main` | `[x]` 4 sep 2026 | merge-commit `4e78b16` op `integration/pleya-server-rebaseline` vanaf `a21b43c`; veertien conflicten opgelost, codegen sluitend, geen testregressie. De twee stille mergefouten (`app_database.g.dart`, `schema.d.ts`) en de `--ours`-fout op `CLAUDE.md` en `docs/RELEASES.md` zijn apart gerepareerd en worden nu bewaakt door `scripts/check_authority_merge.sh` in CI De dagelijkse merge van dezelfde avond staat als `a1734ead` (`main` op `9b181ff5`, vier conflicten, LANG1 hernummerd naar DEC-109); hoofdstuk 7 van `merge-log.md` |
| P5 | Locatorbesluit voor leesvoortgang | `[ ]` | |
| P6 | Protocolvensters 1 tot 8 geopend en gesloten | `[ ]` | |
| P7 | PS-5-hardwareronde | `[!]` uitgesteld | `docs/qa/ps5-hardware-round.md`, drie startvoorwaarden |
| P8 | Plex-off gate groen, migratie als keuze | `[ ]` | |
| P9 | Contractdekking compleet: de dekkingslijst in `scripts/check_server_responses.py` dekt elk schema dat de server werkelijk teruggeeft, inclusief `UserList`, `LibraryPermissionList` en `SessionList` | `[x]` 4 sep 2026 | **De dekkingslijst.** `scripts/check_server_responses.py` leidt hem nu af uit `openapi.yaml`: elk schema dat het contract als JSON-antwoordlichaam noemt, met de `components/responses`-indirectie opgelost en niet-JSON-lichamen (artwork, ondertitels, stream) eruit. Dat brengt de eis van 8 naar 15 en dekt `UserList`, `SessionList` en `LibraryPermissionList`. Uit de vangst afleiden zou de poort tautologisch maken; uit het contract afleiden laat hem vanzelf meegroeien. Echte vangst van 32 antwoorden lokaal gedraaid met `GO_IMAGE=pleya-server-test:go-ffmpeg` en `PLEYA_RESPONSE_DIR=/src/.responses` (het containerpad binnen de mount, daar ging het eerder mis): alle 15 gedekt, alle 32 valide. Negatieve controle: met `UserList`, `SessionList` en `LibraryPermissionList` uit de vangst geeft de oude poort exit 0 met "de server houdt zich aan het contract" en de nieuwe exit 1 met de drie endpoints erbij. De afleiding heeft zes eigen controles op een verzonnen contract (`bijt de afleiding`). |

---

## 5. Hoe deze lijst wordt bijgehouden

1. Bij het starten van een taak: `[ ]` naar `[~]`.
2. Bij het afronden: `[x]` plus bewijs plus datum, in dezelfde commit als het werk.
3. Bij een blokkade: `[!]` plus de reden in de bewijskolom; een blokkade zonder reden is niet
   toegestaan.
4. Bij het sluiten van een slice: de tabellen in hoofdstuk 1 en 2.1 bijwerken en een Roadmap Drift
   Check in `STATUS.md` (drie vragen uit architectuur 23.1).
5. Komt er werk bij dat hier niet staat, dan komt er eerst een regel bij, met een verwijzing
   naar de plek in `docs/pleya-server-rebaseline/` die het rechtvaardigt. Werk zonder regel is
   scope creep.
6. Deze lijst vervangt geen enkel ander document: `STATUS.md` blijft het sessielogboek,
   `docs/DECISIONS.md` de besluiten, deel I het plan. Hier staat alleen de stand.
