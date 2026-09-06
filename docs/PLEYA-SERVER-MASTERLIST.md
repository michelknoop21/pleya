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

Laatst bijgewerkt: 2026-09-06 (S2.2 gesloten, venster 2 open met DEC-113). Bron voor de scope:
`docs/pleya-server-rebaseline/` deel I (slices) en deel O (Definition of Done).

---

## 1. Stand in één blik

| Blok | Slices | Gereed | Bezig | Open |
| --- | --- | --- | --- | --- |
| Fundament en integratie | S0 | 1 | 0 | 0 |
| Backend basis | S1 tot S6 | 1 | 1 | 4 |
| Web | S7 tot S13 | 0 | 0 | 7 |
| Clients en agents | S14, S16 | 0 | 0 | 2 |
| Uitgebreide scope | S17 tot S25 | 0 | 0 | 9 |
| Afronding | S15 | 0 | 0 | 1 |
| **Totaal** | **26** | **2** | **1** | **23** |

Per taak, en dat is de maat die telt: **148 taken, 20 gereed, 0 bezig, 128 open.** S0 en S1 zijn
allebei dicht, met acht van acht; de twee andere gereed-vinkjes zijn mockupgoedkeuringen die met
poort P3 al binnen waren (S12.1 en S13.1).

Gesloten vóór dit traject en niet in deze lijst: PS-0, PS-1, PS-2, PS-3, PS-3W, PS-4, PS-9.
Keuzefase na afronding: PS-12 (Plex-migratie). Buiten scope: PS-13, PS-16, app-reader (PS-15).

**Waar het nu op wacht.** S0 is dicht en de Roadmap Drift Check erop staat in `STATUS.md`. **PS-11A
loopt**, en **S1 is dicht**: S1.7 sloot de drie-rollen-ronde plus K rij 1, en S1.6 landde de laatste
drie rijen van venster 1 en sloot het venster. **S2** (bibliotheken, opslag, scans) loopt: S2.1
landde de migratie en de `managed`-kolom, en S2.2 opende protocolvenster 2 met [DEC-113](DECISIONS.md)
en landde de CRUD op `/libraries` (drie van de tien wijzigingen uit J.3). Venster 2 sluit pas met
S2.6. Het venster voor S1 ging open met [DEC-110](DECISIONS.md), werd op één punt gecorrigeerd door
[DEC-111](DECISIONS.md) (venster 1 voegt twee foutdomeinen toe en niet één) en is met S1.6 gesloten
met [DEC-112](DECISIONS.md); `openapi.yaml` is daarmee weer bevroren. PS-14 blijft gesloten tot
PS-11A af en geïntegreerd bewezen is; dat is een volgorde, geen voorkeur.


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
| 1, loopt | S1, S2 | 4 | beheer-backend compleet: instellingen, diagnostiek, tokens, audit, bibliotheken, opslag, scans | niets |
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
van de 130 resterende. Hij blokkeert alleen S15.

### 2.3 Wat op een besluit wacht en niet op code

| Wat | Blokkeert | Stand |
| --- | --- | --- |
| **P5, het locatorbesluit** (Readium Locator plus publicatie-digest, S6.1) | S6, en via S6 ook S9, S12, S14, S16, S20 en S21 | open; RB-12 is bijgesteld in deel E, het besluit zelf moet nog als DEC |
| **Pushen naar `origin`** | niets technisch, wel elk verlies bij een schijfstoring | de branch bestaat op `origin` maar loopt er dertien commits op voor; pushen vraagt Michels go |
| **PS-12 vrijgeven** | niets; het is een keuzefase | pas ná S15, met een eigen besluit |
| Mockups 50, 51 en 36 | S12.1, S13.1, deel van S22.6 | goedgekeurd met poort P3 op 4 september; S12.1 en S13.1 zijn daarmee gesloten, S22.6 houdt de bouw van scherm 29 en 36 over |

### 2.4 De poorten die nog dicht staan

P5 (locator), P6 (acht protocolvensters geopend en gesloten), P7 (PS-5-hardwareronde, uitgesteld),
P8 (Plex-off gate). Van de acht protocolvensters is er één geopend én weer gesloten: venster 1, bij
S1, met alle zeventien rijen erin ([DEC-110](DECISIONS.md), [DEC-111](DECISIONS.md),
[DEC-112](DECISIONS.md)). Er staat er nu geen open. De volledige stand staat in hoofdstuk 4.

### 2.5 Twee dingen die deze planning kunnen omgooien

**Een protocolvenster dat te vroeg dichtgaat.** Elk venster opent en sluit met een DEC, en een rij
die er niet in zat kost een nieuw besluit plus een nieuwe compatibiliteitstoets. De zeventien rijen
van venster 1 landen daarom per commitgrens en niet in één klap, en dat patroon geldt voor de zeven
vensters erna net zo.

Dat de lijst uitputtend is telt daarbij dubbel: rij 11 (`auth.permission_not_allowed`) stond er als
losse foutcode in, en zonder die regel zou S1.4 een nieuwe code hebben moeten uitstellen tot venster
2, of de bestaande 404 hebben moeten laten staan die een beheerder liet zoeken naar een gebruiker die
er gewoon was.

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
| S1.4 | `GET /stream-sessions`, `GET /users/me`, foutcode `auth.permission_not_allowed` | `[x]` | **Drie wijzigingen, drie verschillende klassen.** `GET /stream-sessions` is klasse admin en geeft de browserstreamsessies die op dit moment nog bytes kunnen ophalen, met gebruiker, toestel, item en positie (J.2 rij 8). `GET /users/me` is klasse authenticated en geeft elke rol `200` op zichzelf (rij 9). `auth.permission_not_allowed` is `409` op `PUT /users/{id}/permissions` wanneer `manage` naar een `restricted` gaat (rij 11), waar tot nu toe `auth.user_not_found` stond met de aantekening dat een eigen code in het eerstvolgende venster hoorde. **Waarom die 409 geen 404 is.** De 404-regel verbergt het bestaan van iets dat de aanvrager niet mag zien, en de aanvrager is hier per definitie een beheerder die de gebruiker en de bibliotheek allebei al mag zien; er valt niets te verbergen, alleen iets uit te leggen. Dat maakt hem de enige code in het `auth.`-domein die geen 404 is, met die redenering erbij in hoofdstuk 7.1 en 16.3. **Waar de query woont.** `internal/diag/ActiveStreams` en niet `internal/auth`: de vraag spant `stream_sessions`, `users`, `sessions`, `media_versions`, `media_items` en `watch_states` samen, en `diag` is de store die er al is voor beheermetingen die door de lagen heen lezen. "Actief" is precies wat `auth.VerifyStreamSession` accepteert, inclusief de koppeling met de auth-sessie; ruimer tellen zou iemand tonen die op zijn eerstvolgende aanvraag een 401 krijgt. **K rij 5 en 15.** Het antwoord draagt de sessie-id (niet geheim, hij reist als `ss` in de media-URL) en niet het geheim, de hash ervan, het accesstoken of het refreshtoken; `TestStreamSessionsCarryNoSecrets` doorzoekt het lichaam op alle vier. **Autorisatiematrix** (hoofdstuk 16.4) van eenentwintig naar drieëntwintig regels; regel 22 is `GET /users/me` met de expliciete redenering waarom elke rol daar `200` krijgt, regel 23 is `GET /stream-sessions`. Hoofdstuk 17b.6 is nieuw, hoofdstuk 18 gaat van tweeëndertig naar vierendertig operaties, en `pleya_server/README.md` volgt. **Contract.** Drie J.2-rijen erbij (8, 9 en 11), met `StreamSessionSummary` en `StreamSessionList` als schema's, `stream_session_list.json` en `error_permission_not_allowed.json` als fixtures en hun manifestregels. **Bewijs.** `scripts/go-tool.sh vet ./...` schoon en `test ./...` groen met de wegwerp-Postgres en de ffmpeg-image, nul `--- SKIP`; `check_protocol.sh` groen (30 paden, 72 componenten, 14 enums, 56 fixtures, 7 foutdomeinen); echte vangst met `PLEYA_RESPONSE_DIR=/src/.responses` gevolgd door `check_server_responses.py`: 40 antwoorden, 20 van 20 schema's gedekt, met `StreamSessionList` erbij; `pleya_web` `api:generate` plus `api:check` sluitend, `check` 0/0 over 546 bestanden, `test` 114 groen, `build` groen; `flutter test test/pleya_server/` 246 groen (de fixturetelling van 54 naar 56, `StreamSessionList` expliciet uitgesteld naar de webbeheerder, `User` stond al in die lijst). **Elf negatieve controles**, elk gedraaid en rood bevonden: `requireAdmin` vervangen door `resolveRequester` op `/stream-sessions`; de `revoked_at`-clausule uitgeschakeld; de `expires_at`-clausule uitgeschakeld; de koppeling met de auth-sessie uitgeschakeld; de kijkstatus niet gekoppeld; de duur ook zonder positie meesturen; de hash van het sessiegeheim in het antwoord; `/users/me` achter `requireAdmin`; `/users/me` dat de owner teruggeeft in plaats van de aanvrager; de oude 404 terug op manage-voor-restricted; de nieuwe code als 404 in het register. **Een twaalfde controle kwam eerst groen terug en heeft de test veranderd.** Met de hele WHERE-clausule op `true` bleef `TestStreamSessionsOnlyListWhatCanStillStream` groen, omdat `CreateStreamSession` bij elke nieuwe sessie de verlopen en ingetrokken rijen van hetzelfde subject opruimt: de rij die weggefilterd moest worden stond er bij het opvragen niet eens meer. De test opent nu eerst alle drie de sessies en draait er pas daarna aan, en dan bijten beide clausules. **Eén tak is niet getoetst en staat er daarom bij**: `Options.Diag == nil` antwoordt `server.internal` in plaats van een lege lijst, maar productie zet die store altijd en geen test bouwt een server zonder. | 2026-09-05 |
| S1.5 | API-tokens als sessies, `admin_audit` met het uitgebreide bereik | `[x]` | **Drie endpoints, één architectuurkeuze.** Een API-token is geen apart credentialtype maar een rij in `sessions` met `kind = 'api'`, de tokennaam als `device_name` en de SHA-256 van het geheim in `token_hash` (RB-20). Daarmee is er één intrekkingspad (`DELETE /sessions/{id}`), één register en één overzicht; een tokenmodel ernaast zou de vraag "is dit credential nog geldig" op twee plekken beantwoordbaar maken en op één plek te vergeten. `POST /auth/api-tokens` geeft het geheim precies één keer (J.2 rij 12), `GET /auth/api-tokens` geeft de lijst zonder geheimen en `Session` groeit met `kind`, `scope` en `expires_at` (rij 13), `GET /audit` is de klasse-admin lijst met `?source=`, `?limit=` en `?cursor=` (rij 14). `capabilities.api_tokens` is de zevende vlag. **Het voorvoegsel is functioneel.** Elk geheim begint met `plyat1_`, en `authenticated()` kiest daarop zijn verificatiepad in plaats van eerst een handtekening te proberen en bij elke mislukking de database te bevragen; dat zou een stroom onzin-tokens een gratis query per aanvraag maken. Het maakt een gelekt geheim bovendien vindbaar in een logbestand of een repository. **K rij 22, en één gat dat er niet in stond.** Bereik nooit boven de rol van de **eigenaar** (niet die van de aanvrager, anders is `user_id` een manier om een lid beheerrechten te geven zonder zijn rol te wijzigen), standaard negentig dagen, hash-only opslag, intrekbaar als sessie. Het bereik begrenst daarnaast de adminklasse: een `read`- of `maintenance`-token zakt door `requireAdmin` met dezelfde 404 als een lid, byte-gelijk. Dat is de vorm die Michel op 5 september koos boven een volledige scope-matrix per route, die de indeling zou verzinnen die S16 en S25 horen te bezitten. **Het gat**: `ScopeWithinRole` toetst het bereik tegen de rol, en de rol van een leestoken van een beheerder is `admin`, dus die controle alleen laat een `read`-token een `admin`-token minten. `POST /auth/api-tokens` weigert daarom elke aanvraag die zelf met een token onder bereik `admin` binnenkomt. Dat staat in geen enkel plan, is hier gevonden, en staat als eigen alinea in hoofdstuk 17c.2. **Het auditbereik is dat van VRAGENLIJST 23 en niet van J.2.** Elf schrijfhaken: setup, login geslaagd, login geweigerd, login geblokkeerd door de limiter, gebruiker aanmaken, wijzigen, verwijderen, rechten zetten (ok en geweigerd), instellingen wijzigen (ok en geweigerd), token aanmaken (ok en geweigerd), sessie intrekken, uitloggen en sleutelrotatie (ok en geweigerd). Eruit blijven catalogusreads, playbackticks en leesvoortgang. Geheimen gaan nooit mee in `detail`: een mislukte login draagt de geprobeerde naam en niet het wachtwoord, een mislukte setup de reden en niet de code, een gewijzigde instelling de sleutelnaam en niet de waarde. `detail` staat helemaal niet in het antwoord, want vrije vorm in een antwoord is de weg waarlangs er ooit iets in belandt dat er niet in hoort. De schrijfronde draait op `context.WithoutCancel`: een client die de verbinding verbreekt tussen de commit en de auditregel zou anders een handeling opleveren die gebeurd is en niet in het log staat. **De retentie hoort bij S1.5 en niet bij S15**, besloten op 5 september 2026: F rij 34 zet `admin_audit` inclusief de negentig dagen op S1, en de S15-regel gaat over `stream_sessions`. `housekeeping()` kreeg er één regel bij, en `audit.Retention` is bewust geen instelling: een bewaartermijn die een beheerder kan verlagen, kan een aanvaller met beheerrechten verlagen. **Autorisatiematrix** (hoofdstuk 16.4) van drieëntwintig naar zesentwintig regels. Regel 24 en 25 zijn niet admin-only, en dat is een keuze met reden: RB-20 beschrijft een token dat een gebruiker voor zichzelf maakt, en admin-only zou een lid dwingen een beheerder te vragen die alleen een token met de rechten van dat lid kán maken. Hoofdstuk 17c is nieuw, hoofdstuk 18 gaat van vierendertig naar zevenendertig operaties, `pleya_server/README.md` volgt. **Contract.** Drie J.2-rijen erbij (12, 13 en 14) met `ApiToken`, `ApiTokenList`, `ApiTokenCreated`, `ApiTokenRequest`, `ApiTokenScope`, `SessionKind`, `AuditEntry`, `AuditPage`, `AuditSource` en `AuditOutcome` als schema's, `auth.scope_exceeds_role` als foutcode, en vijf fixtures met hun manifestregels (`api_token_list.json`, `api_token_created.json`, `audit_page.json`, `error_scope_exceeds_role.json`, `session_list_api_token.json`). `AuditPage` hangt aan het gedeelde `Page`-schema, zodat `next_cursor` er altijd in staat en een client niet twee controles hoeft te doen waar er één hoort. **Bewijs.** `scripts/go-tool.sh vet ./...` schoon en `test ./...` groen met de wegwerp-Postgres en de ffmpeg-image, nul `--- SKIP`; `check_protocol.sh` groen (32 paden, 82 componenten, 18 enums, 61 fixtures, 7 foutdomeinen); echte vangst met `PLEYA_RESPONSE_DIR=/src/.responses` gevolgd door `check_server_responses.py`: 44 antwoorden, 23 van 23 schema's gedekt, met `ApiTokenList`, `ApiTokenCreated` en `AuditPage` erbij; `pleya_web` `api:generate` plus `api:check` sluitend, `check` 0/0 over 546 bestanden, `test` 114 groen, `build` groen; `flutter test test/pleya_server/` 247 groen (de fixturetelling van 56 naar 61, de drie nieuwe schema's expliciet uitgesteld naar de webbeheerder). **Negentien negatieve controles, achttien rood bevonden**: de vervalcontrole uit; de intrekkingscontrole in de database uit; het bereik mag boven de rol; het bereik begrenst de adminklasse niet; een leestoken mag tokens minten; iedereen mag de tokens van een ander zien; `/audit` zonder adminpoort; de haak op `PATCH /settings` weg; de haak op een mislukte login weg; een geslaagde login zonder identiteit; het tokenoverzicht toont verlopen tokens; de cursor van `/audit` staat stil; de bewaartermijn op dertig dagen; een catalogusread in het auditlog; het geheim onversleuteld in de database; de hash van het geheim in het lijstantwoord; de sessie zonder soort; het voorvoegsel niet herkend. **Eén controle kwam groen terug en dat is de bedoeling**: alleen `sessionLives` uitschakelen op het API-tokenpad laat `TestRevokedAPITokenIsRejectedWithinTwoSeconds` groen, omdat `VerifyAPIToken` `revoked_at` zelf leest. De twee overlappen bewust, want het register geeft de garantie van twee seconden zonder databaseronde en de query overleeft een herstart van het proces; `TestRevokedAPITokenStaysDeadAfterTheRegisterIsGone` klemt de andere kant. **Eén tak is niet getoetst en staat er daarom bij**: `Options.Audit == nil` schrijft stil niets en antwoordt `server.internal` op `GET /audit`, maar productie zet die store altijd en geen test bouwt een server zonder. | 2026-09-05 |
| S1.8 | HttpOnly-refreshcookie, web-origin, externe URL, CORS-beleid (RB-29) | `[x]` | **Drie vragen die eerst opgeschreven zijn, en toen pas gebouwd.** (1) *K rij 7 tegen RB-29.* Een cookie draagt in dit protocol nooit een identiteit, alleen een handeling: `pleya_refresh` autoriseert uitsluitend `POST /auth/refresh`, en dat is geen belofte maar een `Path`. Staat nu in hoofdstuk 17d.2 van de specificatie, als regel 27 van de autorisatiematrix, en als K.2a in het securityplan; K rij 7 zelf noemt de twee cookies nu bij naam. (2) *Instellingen of velden op `Server`.* Alle drie zijn instelling; `web_origin` staat daarnaast op `ServerDetail` voor klasse admin, `cors_origins` niet, want een lijst vertrouwde origins is beleid en vertelt wie het proberen waard is. Er komt **geen aparte `external_url`**: dat is dezelfde vraag als `public_url`, die met S1.3 al de zevende instelling werd en al een lezer heeft. `cors_origins` is de eerste lijstwaarde en gaat als JSON-array de `jsonb`-kolom in, niet als gescheiden tekst: dat laatste knipt een waarde met een scheidingsteken stil in tweeën. Vastgelegd in 17d.3 en als noot onder de J.2-tabel. (3) *De zes compatibiliteitsregels.* `credential_mode` is een nieuw optioneel aanvraagveld achter `capabilities.cookie_auth` (regel 4 en 5); `RefreshRequest.refresh_token` gaat van verplicht naar optioneel, en dat is verruimen. Het scherpste punt is `TokenPair.refresh_token`, dat uit `required` gaat: het veld is niet weg maar voorwaardelijk, en de voorwaarde ligt volledig bij de client, die hem altijd krijgt zolang hij `credential_mode` niet stuurt. De afweging tegen een `oneOf` met een tweede antwoordschema staat er met de reden bij (dat maakt van elk login-antwoord een unie in elke gegenereerde client). De toets staat als tabel in 17d.1. **Wat er gebouwd is.** `internal/config/origin.go` (`NormalizeOrigin`, `NormalizeOrigins`, `MaxCORSOrigins`), `internal/api/origin.go` (`requestIsSecure`, `requestOrigin`, `originAllowed`, de CORS-middleware met preflight), `credential_mode` op login en refresh, `web_origin` en `cors_origins` als achtste en negende instelling met hun grens, `capabilities.cookie_auth`, foutcode `auth.origin_rejected` 403, en `PLEYA_SERVER_WEB_ORIGIN` / `PLEYA_SERVER_CORS_ORIGINS` als omgevingslaag. Geen migratie nodig: `server_settings.value` is `jsonb`. **Twee keuzes die het model dichtzetten.** De cookie is `SameSite=Strict` en de CORS-laag stuurt nooit `Access-Control-Allow-Credentials`, dus cookiemodus is per constructie same-site en het third-party-cookieontwerp dat RB-29 uitsluit is niet te bouwen in plaats van alleen verboden. En de origin-controle staat vóór de rate limiter, zodat een vreemde pagina de inlogemmer van een huisgenoot niet leeg kan trekken. **Bewijslast van K rij 20, en wat er open blijft.** Servergedrag: `Set-Cookie` draagt `HttpOnly`, het antwoord draagt de sleutel `refresh_token` niet (niet alleen leeg), verversen werkt met alleen de cookie en roteert hem, en een cookiemodus-aanvraag van een vreemde of ontbrekende origin geeft 403. De browserkant van K rij 20 (`document.cookie`, F5) hoort bij de slice die de webclient werkelijk op cookiemodus zet: S1 heeft in deel I expliciet **Frontend: geen**, en `pleya_web` blijft in tokenmodus. Dat is genoteerd en niet weggeschreven. **Bijvangst, binnen K rij 8 en dus binnen S1.** De streamsessie-cookie zette `Secure` op `r.TLS != nil` en bleef daarmee achter een TLS-terminerende proxy zonder `Secure` staan; hij gebruikt nu dezelfde `requestIsSecure`, die `X-Forwarded-Proto` alleen van een vertrouwde proxy gelooft. **Contract.** J.2 rij 16 erin, met `CredentialMode` en `SettingStringList` als nieuwe schema's, `cookie_auth` op `Capabilities`, `web_origin` op `ServerDetail` en `Settings`, `cors_origins` op `Settings`, een 403 op login en refresh, en `error_origin_rejected.json` als fixture. Hoofdstuk 17d is nieuw, matrixregel 27 erbij (26 naar 27), hoofdstuk 18 blijft op zevenendertig operaties want dit is een modus en geen endpoint. **Bewijs.** `go-tool.sh vet ./...` schoon en `test ./...` groen met de wegwerp-Postgres en de ffmpeg-image, nul `--- SKIP`; `check_protocol.sh` groen (32 paden, 84 componenten, 19 enums, 62 fixtures, 7 foutdomeinen); echte vangst met `PLEYA_RESPONSE_DIR=/src/.responses` gevolgd door `check_server_responses.py`: 47 antwoorden, 23 van 23 schema's gedekt, met beide vormen van `TokenPair` erin; `pleya_web` `api:generate` plus `api:check` sluitend, `check` 0/0 over 546 bestanden, `test` 114 groen, `build` groen; `flutter test test/pleya_server/` 248 groen (de fixturetelling van 61 naar 62). **Een gat in de vangst dat hier gedicht is.** De opvangfunctie ontdubbelde op schema, methode, pad en status, dus van de twee vormen van `TokenPair` op `/auth/login` zou er precies één bij de contractpoort komen, en welke hing af van de volgorde van de tests. `recordVariant` geeft de tweede vorm een eigen bestandsnaam; de manifestregel blijft zeggen wat er werkelijk is opgehaald. **Drieëntwintig negatieve controles, tweeëntwintig meteen rood**: origin altijd toegestaan; alleen same-origin (web_origin en cors_origins genegeerd); lege Origin toegelaten; cookie zonder HttpOnly; cookie op SameSite=Lax; refresh_token toch in het lichaam; `omitempty` eraf; onbekende credential_mode valt terug op token; origin-controle ná de rate limiter; `X-Forwarded-Proto` van elk adres geloofd; alleen `r.TLS` telt; geen wissen van een dode cookie; twee credentialbronnen stil verrekend; CORS met Allow-Credentials; CORS die elke origin echoot; `Vary: Origin` weg; preflight valt door naar de mux; streamsessie-cookie terug op `r.TLS`; auditregel bij een geweigerde origin weg; `cors_origins` laat `*` door; origin met een pad geaccepteerd; dubbele origins stil geslikt. **De drieëntwintigste kwam groen terug en heeft de test veranderd**: `RefreshCookiePath` verbreden naar `/pleya/v1` bleef groen, omdat de test hem met de constante zelf vergeleek en de vier 401-controles eronder óók groen blijven met een breed pad. Dat is geen toeval maar de aard van de zaak: de server leest deze cookie nergens als identiteit, dus geen serverzijdige meting ziet het verschil tussen een smal en een breed pad. Het pad is een instructie aan de browser. De test vergelijkt nu met de letterlijke waarde, en dan bijt de mutatie wél. | 2026-09-05 |
| S1.6 | Capability `administration`, `mcp` en `server_name` bij setup; protocolvenster 1 dicht | `[x]` | **De laatste drie rijen van venster 1, en het venster dicht met [DEC-112](DECISIONS.md).** Rij 1 is `capabilities.administration`: één vlag voor de zes beheerroutes die S1.2 tot en met S1.5 bouwden, en niet zes vlaggen, want ze kwamen samen en het antwoord zou zes keer hetzelfde zijn. Rij 15 is `capabilities.mcp` op `false` plus `ServerDetail.mcp{enabled, url, tool_count}` voor klasse admin, met `enabled: false` en `tool_count: 0`. Er komt geen MCP-code bij; dat is slice S16. Wat hier gebeurt is de **vorm** vastleggen, want het contract gaat met deze commit weer op slot en een boolean plus een object van drie velden zou anders een eigen venster kosten. Het object staat er altijd en niet pas wanneer de laag aanstaat: een afwezig object zegt dat deze server de vraag niet kent, en dat wordt straks onwaar terwijl het antwoord hetzelfde blijft.
**Rij 10 is de enige met gedrag erachter, en dat was een keuze.** J.2 noemt `SetupRequest.server_name` zonder te zeggen wat de server ermee doet, en een schema zonder handler komt door de contractpoort omdat die alleen naar de vorm kijkt. `POST /auth/setup` schrijft nu werkelijk de instelling `server_name`, via dezelfde `settings.Parse` als `PATCH /settings` zodat de grenzen niet uit elkaar kunnen lopen. De toets staat **vóór** het inwisselen van de setupcode: die is eenmalig, dus een naam van vijfenzestig tekens zou hem anders opbranden en een eigenaar zonder naam achterlaten. `Info.server.setup_accepts_name` is de onderhandeling die regel 5 van hoofdstuk 3 vraagt (`SetupRequest` blijft gesloten), en hij hangt aan de opslag: zonder `server_settings` is er niets om de naam in te bewaren.
**Bijvangst.** `TestInfoBeforeAndAfterSetup` verbood de kale woorden `name` en `version` als substring in `/info`. Dat werkte tot er een veld bestond waar die letters onschuldig in voorkomen, en `setup_accepts_name` is dat veld. De lijst noemt de sleutels nu met hun JSON-vorm, plus `build`, zodat de meting over velden gaat en niet over letters. Tweede bijvangst: hoofdstuk 17b telde acht beheervelden op `GET /server` terwijl `web_origin` er met S1.8 al bij was gekomen; het zijn er tien, en regel 17 van de autorisatiematrix telt ze niet meer op omdat een aantal in die kolom bij elke slice stil veroudert.
**Bewijs:** `go-tool.sh vet ./...` en `test ./...` groen met database; `check_protocol.sh` groen (32 paden, 84 componenten, 19 enums, 7 foutdomeinen, 64 fixtures); een vangst van 47 antwoorden met `check_server_responses.py` 23 van 23 schema's; `flutter test test/pleya_server/` 250 groen; `bun run api:generate`, `api:check`, `check`, `test` en `build` in `pleya_web` groen; `ci_checks.sh` groen. Twee fixtures erbij (`info_administration.json`, `setup_request_with_name.json`), `server_detail_admin.json` draagt het mcp-object, de manifestlijst gaat van 62 naar 64 en de telling in `pleya_wire_contract_test.dart` mee; `SetupRequest` komt op de uitgestelde lijst daar, want de app stelt zijn setupbody als een letterlijke map samen. **Negatieve controles, zeven, alle zeven rood:** de `Apply` bij setup uitgezet; de naamtoets ná `CompleteSetup` gezet; de naam altijd wegschrijven ook zonder veld; `administration` op false; `mcp` op true; het mcp-object naar de velden voor iedereen verplaatst; `DisallowUnknownFields` weg | 2026-09-05 |
| S1.7 | Drie-rollen-test over elke nieuwe route (plus K rij 1) | `[x]` | **Twee tabellen, één referentie.** `internal/api/authorize_matrix_test.go` is de uitbreiding van `authorize_test.go` die DEC-105 vraagt, in een eigen bestand omdat dat er al bijna negenhonderd telt. De rollentabel dekt matrixregel 16 tot en met 26 als **probes** en niet als endpoints: regel 24 en 25 zijn elk twee probes (zonder `user_id` over jezelf, met `user_id` over een ander), en daarmee hebben ze de gewone vorm in plaats van een uitzondering. De cel is een uitkomst uit een gesloten paar, `answers` of `refused`, waardoor regel 17 (`GET /server`) en regel 22 (`GET /users/me`) als vier keer `answers` in dezelfde tabel passen; dat is geen lege cel, want een `requireAdmin` die daar per ongeluk op staat blijft voor owner en admin groen. Regel 27 is klasse public en heeft geen identiteit, dus die krijgt een **tweede as** met dezelfde tweedeling: actoren zijn herkomsten, de canonieke weigering is `403 auth.origin_rejected`, en hij draait op login én refresh, vóór en ná het zetten van `web_origin` en `cors_origins`. Van de vier gevallen die niet op drie vaste kolommen passen blijven er zo nul over als uitzondering. Vier rollen en niet drie: `admin` staat erbij, anders is "een beheerder komt erbij" onbewezen.
**De byte-gelijkheid heeft nu één referentie.** Hij stond op zes plekken tegen twee verschillende ijkpunten: vier tests vergeleken met `PATCH /users/{bestaande ander}` door een lid, één met de weigering van een lid op `/settings`, terwijl K rij 2 letterlijk een niet-bestaand id noemt. `e.canonicalNotFound()` is nu het enige ijkpunt, en het is de sterkste van de twee: `PATCH /users/{id}` op een id dat niet bestaat, gedaan door de owner. Diezelfde functie legt vast dat de oude referentie er byte-gelijk aan is. De ronde **vervangt** de vijf verspreide `ThreeRoles`-tests (`settings_test.go`, `server_admin_test.go`, `stream_sessions_test.go`, `api_tokens_test.go`, `audit_test.go`) plus de twee origin-tests in `cookie_auth_test.go` die alleen login dekten; op elke plek staat een regel die zegt waarheen. `TestAPITokenScopeCapsTheAdminClass` behield zijn eigen claim (K rij 22) en toetst hem nu tegen dezelfde referentie.
**K rij 1 hoort bij S1.7 en niet bij S1.6, en dat is hier vastgelegd.** Hij heeft geen eigen S1.x-regel; K.2 wijst hem toe aan slice S1. S1.6 is een contracttaak (venster dicht), S1.7 is de ronde die de dekking uitputtend maakt, en K rij 1 is precies wat die ronde niet-tautologisch maakt: een route die er later bijkomt valt er vanzelf in. Het is een toewijzing binnen de slice, geen roadmapwijziging. `web_routes_test.go` lost het enumeratieprobleem niet op (die houdt een eigen rij paden bij, en dat mag daar want de vraag gaat over vijf uitgekozen paden), dus `routes()` in `server.go` vult de mux nu uit `routeTable()` en is de enige plek die `s.mux.Handle` aanroept; `publicPatterns` is de ene regel uit K rij 1. `routes_internal_test.go` loopt die tabel af, zonder database. Bevinding onderweg: status plus foutcode onderscheidt de publieke POST's niet van een beveiligde route (login, setup en refresh geven op een leeg lichaam ook 401), dus de meting is "de weigering die zegt dat er geen credential kwam", en de acht patronen in `publicPatterns` zijn er acht en geen zeven: `/` (de bundel) en `/pleya/v1/` (de terugval die niets uitvoert) staan er met hun reden bij.
**Dekking is mechanisch.** `TestAuthorizationMatrixCoversEveryRowFromSixteen` leest hoofdstuk 16.4 van `docs/pleya-protocol-v1.md` werkelijk (niet met de hand gespiegeld zoals `TestErrorRegisterMatchesTheSpecification`) en eist een probe voor elke regel vanaf 16. Een latere slice die een matrixregel bijzet zonder ronde krijgt daar rood. **Bewijs:** `go-tool.sh vet ./...` en `test ./...` groen met database, nul `--- SKIP`; `check_protocol.sh` groen (32 paden, 84 componenten, 19 enums, 7 foutdomeinen); vangst van 47 antwoorden, `check_server_responses.py` 23 van 23 schema's; `ci_checks.sh` groen. **Negatieve controles, acht, alle acht rood:** `/audit` zonder `authenticated`; een spookregel in `publicPatterns`; `/info` eruit; de weigering van `requireAdmin` van bericht veranderd; `/audit` zonder `requireAdmin`; `requireAdmin` óp `/users/me`; een regel 28 in de specificatie zonder probe; `originAllowed` die elke niet-lege origin toelaat | 2026-09-05 |

### S2 Bibliotheken, opslag, scans

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S2.1 | Migratie `0009`, `managed`, scaninstellingen op `libraries` | `[x]` | **Schema, geen contract.** `0009_libraries_managed.sql` voegt `managed` (`config`/`db`, default `config`), `scan_interval_seconds` (nullable, `NULL` betekent de globale interval) en `scan_on_start` (default `true`, het gedrag dat elke bibliotheek al had) toe aan `libraries`. Geen endpoint raakt de lijn in deze commit, dus geen wire-wijziging en geen protocolvenster nodig; venster 2 opent bij S2.2, wanneer `Library` voor het eerst met deze velden over de lijn gaat. **Eigenaarschap.** `SyncLibraries` (`internal/catalog/store.go`) zet `managed = 'config'` expliciet op elke rij die uit `PLEYA_SERVER_LIBRARIES` komt, in plaats van op de kolomdefault te leunen; de default zelf is voor een rij die buiten dat pad om ontstaat. De `ON CONFLICT DO UPDATE` krijgt hier nog geen guard tegen het overschrijven van een `db`-beheerde rij: die rij bestaat nog niet vóór S2.5 (adopt), en een guard zonder aanroeper is vooruitbouwen. Dat staat als redenering in de code zelf. **Bewijs.** `scripts/go-tool.sh vet ./...` schoon; `test ./...` groen met de wegwerp-Postgres, nul `--- SKIP` (`TestSyncLibrariesIsConfigManagedWithScanDefaults` in `internal/catalog/store_write_test.go` dekt de defaults en de idempotentie van een herhaalde sync); `check_protocol.sh` ongewijzigd groen (24 paden, 7 foutdomeinen, contract onaangeraakt); `ci_checks.sh` groen (dart format, codegen, native format, analyze, dart_code_linter); `flutter test test/pleya_server/` 250 groen. | 2026-09-06 |
| S2.2 | CRUD op `/libraries` met `confirm` bij verwijderen | `[x]` | **Venster 2 open.** [DEC-113](DECISIONS.md) opent het protocolvenster voor de tien wijzigingen van J.3 in één keer, net als DEC-110 voor venster 1; deze commit landt er drie van (`POST`/`PATCH`/`DELETE /libraries`) plus de `Library`-uitbreiding met `managed`, `scan_interval_seconds` en `scan_on_start`, alle drie alleen voor klasse admin. Geen nieuw foutdomein: `library.slug_taken`, `library.not_empty` en `library.confirm_mismatch` vallen in het bestaande domein `library`, `storage.root_not_offered` in het bestaande `storage`. Het achtste domein (`job`) komt pas met S2.4. **Geen bestand aangeraakt.** `root_paths` worden uitsluitend structureel gevalideerd (absoluut pad, geen overlap met een bestaande root of binnen dezelfde aanvraag): `CreateLibrary`/`UpdateLibrary` in `internal/catalog/store_write.go` roepen `mounts.Inspect` nergens aan, want die doet ook een schrijfprobe (`os.CreateTemp`), en die op een door de client verzonnen pad loslaten zou K rij 10 juist schenden vóórdat S2.3 de echte mount-opsomming bouwt. `fs_type`/`inode_trusted` blijven op hun kolomdefault tot een latere scan of S2.3 ze meet. **Slug wordt afgeleid.** `slugify` in de catalog-laag maakt van de titel een slug (kleine letters, cijfers, koppeltekens, terugval op `library` als er niets bruikbaars overblijft); een botsing, ook met een `config`-beheerde bibliotheek, geeft `library.slug_taken`. **Een gotcha die de eerste testronde ving.** `UpdateLibraryRequest.ScanIntervalSeconds` moest `json.RawMessage` zijn en niet `*json.RawMessage`: encoding/json zet een pointer-naar-Unmarshaler bij het JSON-literaal `null` zelf al op nil, vóórdat `RawMessage`s eigen `UnmarshalJSON` ooit wordt aangeroepen, en dan zijn "niet meegestuurd" en "meegestuurd met null" niet meer te onderscheiden, hetzelfde ongeval als bij een kale `*int`. Een niet-pointer `json.RawMessage` bewaart bij `null` de letterlijke bytes en laat het veld bij afwezigheid op zijn Go-zero (nil slice) staan, en dat onderscheid is precies waarom `scan_interval_seconds` driewaardig moet zijn (afwezig, `null`, een getal). **Autorisatiematrix.** Van zevenentwintig naar dertig regels (28, 29, 30), tabelgedreven in `matrixProbes()`; regel 30 (DELETE) blijft op de bevestigingsfout staan, hetzelfde patroon als regel 21 (`rotate-signing-key`), zodat de probe voor owner én admin herhaalbaar is zonder de fixturebibliotheek leeg te trekken. **Bewijs.** `go-tool.sh vet ./...` schoon; `test ./...` groen met de wegwerp-Postgres, nul `--- SKIP` (acht nieuwe tests in `internal/catalog`, negen in `internal/api/handlers_admin_libraries_test.go`, drie nieuwe matrixregels); `check_protocol.sh` groen (33 paden, 88 componenten, 20 enums, 7 foutdomeinen); echte vangst van 52 antwoorden via `check_server_responses.py`: 24 van 24 schema's gedekt, met `Library`, `CreateLibraryRequest` en de nieuwe foutcodes erbij; `pleya_web` `api:generate` plus `api:check` sluitend, `check` 0/0, `test` 114 groen, `build` groen; `flutter test test/pleya_server/` 255 groen (`Library` kreeg een parser naast `LibraryList`, de drie requestschema's zijn uitgesteld net als `SetupRequest`, manifest van 64 naar 72 fixtures); `ci_checks.sh` twee keer groen. | 2026-09-06 |
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
