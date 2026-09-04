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

Laatst bijgewerkt: 2026-09-04 (P0b gesloten). Bron voor de scope: `docs/pleya-server-rebaseline/`
deel I (slices) en deel O (Definition of Done).

---

## 1. Stand in één blik

| Blok | Slices | Gereed | Bezig | Open |
| --- | --- | --- | --- | --- |
| Fundament en integratie | S0 | 0 | 0 | 1 |
| Backend basis | S1 tot S6 | 0 | 0 | 6 |
| Web | S7 tot S13 | 0 | 0 | 7 |
| Clients en agents | S14, S16 | 0 | 0 | 2 |
| Uitgebreide scope | S17 tot S25 | 0 | 0 | 9 |
| Afronding | S15 | 0 | 0 | 1 |
| **Totaal** | **26** | **0** | **0** | **26** |

Gesloten vóór dit traject en niet in deze lijst: PS-0, PS-1, PS-2, PS-3, PS-3W, PS-4, PS-9.
Keuzefase na afronding: PS-12 (Plex-migratie). Buiten scope: PS-13, PS-16, app-reader (PS-15).

---

## 2. Slices

### S0 Fundament

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S0.1 | Proefmerge met `main` in een wegwerp-worktree, conflictlijst in `merge-log.md` | `[x]` | `docs/pleya-server-rebaseline/merge-log.md`: 196 tegen 49 commits, 14 conflictbestanden, 26 schoon; wegwerp-worktree opgeruimd | 2026-09-04 |
| S0.2 | Integratiebranch vanaf `main`, `feat/pleyaserver` erin gemerged | `[x]` | `integration/pleya-server-rebaseline` vanaf `a21b43c`, merge-commit `4e78b16` | 2026-09-04 |
| S0.3 | Veertien conflicten opgelost, codegen sluitend, geen testregressie | `[x]` | `4e78b16`: geen van de vijf voorspelde conflicten deed zich voor, maar de merge droeg wel main's `app_database.g.dart` (9379 regels) onder de samengevoegde bron (11706); codegen herstelde dat. `flutter analyze` 0/0, `flutter test` 6263 groen met 83 bekende falers (78 goldens, 5 die op `a21b43c` zelf ook falen, nagemeten), `drift_relations_test` groen. Webfallout apart in `d7ba84a` | 2026-09-04 |
| S0.4 | DEC-hernummering naar de eerstvolgende vrije reeks in de samengestelde boom (niet blind 096, VRAGENLIJST 59), mappingtabel, grep schoon | `[x]` | twaalf botsingen (063 tot 073 plus 093) naar 096 tot 107; mappingtabel onderaan `docs/DECISIONS.md`; 242 verwijzingen per regel geclassificeerd, geen anker gebroken (de ankers die niet kloppen deden dat op beide takken al) | 2026-09-04 |
| S0.5 | CI-jobs `pleya-server`, `pleya-web`, `protocol` groen | `[~]` | drie jobs in `.github/workflows/ci.yml` (RB-15); elke stap lokaal bewezen: `go build`, `go vet`, `go test ./...` tegen een echte Postgres, `check_protocol.sh`, web check, api:check, test (112) en build. De gehoste run staat nog open tot de branch gepusht is | |
| S0.6 | NAS-migratiefixture (schema 7, geanonimiseerd) | `[ ]` | | |
| S0.7 | Contracttest fake-server tegen `openapi.yaml` | `[ ]` | | |
| S0.8 | Vrijgavebesluit PS-14 en PS-11A vastgelegd | `[ ]` | | |

### S1 Beheer-basis

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S1.1 | Recovery-middleware, lichaamslimiet, securityheaders op de API | `[ ]` | | |
| S1.2 | `server_settings` met `GET`/`PATCH /settings`, grenzen, hot reload | `[ ]` | | |
| S1.3 | `GET /server` uitgebreid, `/server/environment`, `/server/log`, `connectivity-check`, `rotate-signing-key` | `[ ]` | | |
| S1.4 | `GET /stream-sessions`, `GET /users/me`, foutcode `auth.permission_not_allowed` | `[ ]` | | |
| S1.5 | API-tokens als sessies, `admin_audit` met het uitgebreide bereik | `[ ]` | | |
| S1.8 | HttpOnly-refreshcookie, web-origin, externe URL, CORS-beleid (RB-29) | `[ ]` | | |
| S1.6 | Capability `administration`, protocolvenster 1 dicht | `[ ]` | | |
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
| S12.1 | Mockup 51 (readerschil op `@readium/navigator`) goedgekeurd | `[ ]` | | |
| S12.2 | Spike Readium TypeScript Toolkit tegen het manifest; epub.js alleen als gedocumenteerde contingency | `[ ]` | | |
| S12.3 | Reader met leespositie en client-local instellingen | `[ ]` | | |

### S13 Browserspeler (PS-4W)

| # | Taak | Status | Bewijs | Datum |
| --- | --- | --- | --- | --- |
| S13.1 | Mockup 50 (spelerschil) goedgekeurd | `[ ]` | | |
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
| S22.6 | Mockup 36 goedgekeurd, scherm 29 en 36 gebouwd met provenance per veld | `[ ]` | | |
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

## 3. Poorten en releasevoorwaarden

| # | Poort | Status | Bewijs |
| --- | --- | --- | --- |
| P0 | Vragenlijst (`docs/pleya-server-rebaseline/VRAGENLIJST.md`) volledig beantwoord | `[x]` 4 sep 2026 | hoofdstuk 8; verwerking van 20 afwijkingen in de delen staat als P0a |
| P0a | De 20 afwijkingen uit VRAGENLIJST.md hoofdstuk 9 verwerkt in E, I, J, K, L, M, N | `[x]` 4 sep 2026 | E bijgestelde RB's en RB-29; I S1, S5, S6, S12, S18, S22, S24, S25; J venster 1, 0011, 0013, 0017; K.20; L; M.1; N.5 |
| P0b | Dezelfde afwijkingen doorgetrokken in D (mockup metadata-overrides), F, H, O en de masterlijsttaken (S1: cookie; S6: manifest; S22: overrides) | `[x]` 4 sep 2026 | D kop plus rijen 28, 29, 30, 31, 36, 37, 38 en de nummertabel in D.5; F auth (cookie, origin, audit), zoeken, artwork, reading, capabilities, uitgebreide scope, F.2; H kop, H.1 manifestrij, H.2 Readium Locator, H.4 locatorbinding, H.5, H.6; O kop, O.1 readerrij, O.2 functioneel, visueel, technisch, release, O.3; `DESIGN.md` h6 nummerregel; S1.8, S6.1 en S22.5 stonden al |
| P1 | Northstar-set goedgekeurd (consumer, beheer, setup) | `[x]` 4 sep 2026 | chatakkoord; APPROVED gemarkeerd met de laatste mockups erbij |
| P2 | Mockups 17, 18, 19, 28, 35 gereviewd en in het manifest, deel C en deel D | `[x]` 4 sep 2026 | reviewronde 3 in C.5 en C.6 (22 bevindingen, alle gecorrigeerd), manifest bijgewerkt, D.2 aangevuld, hele set opnieuw gerenderd (`f3d99e8`); akkoord Michel 4 sep 2026 |
| P3 | Zes mockups in één ronde: 11b downloads, 36 metadata-match en overrides, 37 transcode-sessies, 38 realtime-status, 50 speler, 51 reader; daarna APPROVED met SHA256SUMS | `[x]` 4 sep 2026 | zes gebouwd en zelf gereviewd (C.7, 6 bevindingen, alle gecorrigeerd); akkoord Michel 4 sep; set op APPROVED met `SHA256SUMS` over 46 schermen, 91 beelden, de bronnen, `web.css` en `build.mjs` |
| P4 | Branch merget schoon met `main` | `[~]` | gemeten en uitgeschreven in `merge-log.md`; de merge zelf wacht op een stilliggende `main` (vraag 58) |
| P5 | Locatorbesluit voor leesvoortgang | `[ ]` | |
| P6 | Protocolvensters 1 tot 8 geopend en gesloten | `[ ]` | |
| P7 | PS-5-hardwareronde | `[!]` uitgesteld | `docs/qa/ps5-hardware-round.md`, drie startvoorwaarden |
| P8 | Plex-off gate groen, migratie als keuze | `[ ]` | |

---

## 4. Hoe deze lijst wordt bijgehouden

1. Bij het starten van een taak: `[ ]` naar `[~]`.
2. Bij het afronden: `[x]` plus bewijs plus datum, in dezelfde commit als het werk.
3. Bij een blokkade: `[!]` plus de reden in de bewijskolom; een blokkade zonder reden is niet
   toegestaan.
4. Bij het sluiten van een slice: de tabel in hoofdstuk 1 bijwerken en een Roadmap Drift Check
   in `STATUS.md` (drie vragen uit architectuur 23.1).
5. Komt er werk bij dat hier niet staat, dan komt er eerst een regel bij, met een verwijzing
   naar de plek in `docs/pleya-server-rebaseline/` die het rechtvaardigt. Werk zonder regel is
   scope creep.
6. Deze lijst vervangt geen enkel ander document: `STATUS.md` blijft het sessielogboek,
   `docs/DECISIONS.md` de besluiten, deel I het plan. Hier staat alleen de stand.
