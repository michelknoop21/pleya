# E. Architectuurbesluiten

Voorstellen, genummerd RB-1 tot RB-28. Ze krijgen pas een DEC-nummer tegen de geïntegreerde
boom (deel M). Elk besluit noemt wat het vastlegt, waarom, en wat er is afgewezen. Waar een
besluit een productkeuze is die Michel moet bevestigen staat dat erbij; de rest volgt uit code,
goedgekeurde DEC's of de design-authority en vraagt geen keuze.

## RB-1 De webshell: topnav boven 900, tabbalk eronder, geen zijrail

Boven 900 px de TV-topnav op webmaat; eronder de iOS-kop en de vijfslots-tabbalk. De `NavRail`
van PS-3W vervalt. Reden: geen enkele goedgekeurde set van de Unified 2026-familie heeft een
zijrail (DEC-063 op main haalde hem van TV, DEC-090 heeft hem niet op iOS), en de web-eis uit
PS-4E is herkenbaarheid zonder uitleg. Afgewezen: de rail houden en alleen restylen, omdat de
rail de enige plek zou zijn waar Pleya anders navigeert dan op elk ander scherm.

## RB-2 Design-authority voor web

Rangorde: (1) de goedgekeurde webset in `docs/assets/pleya-web-northstar/` plus deel D; (2)
voor gedeelde primitieven de iOS-set (DEC-090) onder 900 px en de TV-set (main, 3 september)
erboven; (3) `tokens.css` met `mono_theme.dart` als bron. De twee open details uit DEC-090
worden voor web ingevuld als "Meer info" en een tijdelijke segmentindicator. Dit vervangt
hoofdstuk 8 van het masterplan van 21 augustus als frontend-authority. **Vraagt goedkeuring van
de set.**

## RB-3 Boeken op het web: catalogus, detail, download en Verder lezen in dit traject; de reader
als eigen slice

De webclient toont het Boeken-slot zodra een zichtbare boekenbibliotheek bestaat, en levert
landing, alle boeken, detail, download en de weergave van leesvoortgang. De webreader is slice
S12 en start pas nadat het locatormodel van PS-15 vastligt. Reden: DEC-093 legt de mobiele
beperking vast als clientgedrag; de webclient is het primaire beheer- en desktoppad en er is
geen productreden om boeken daar te verbergen. De reader hangt aan een locatorbesluit dat de
app-reader op `feat/ebooks` nog niet genomen heeft. Afgewezen: web zonder boeken (de admin moet
een boekenbibliotheek kunnen zien scannen), en een webreader vóór het locatorbesluit (twee
locatormodellen die nooit meer samenkomen).

## RB-4 Leesvoortgang is een eigen domein, geen kijkstatus

Nieuwe tabel `reading_states` met (`user_id`, `publication_id`) als sleutel, een `locator`
(jsonb: EPUB CFI plus spine-index en fractie), `progress` als fractie, `finished`, `revision`
en `updated_at`. Geen `owner_session_id`, geen lease: een lezer heeft het conflict van twee
spelers niet. Wat wél overgenomen wordt is het revisieprincipe: een schrijver stuurt
`base_revision`, de server wint bij een oudere basis en antwoordt met de actuele staat. Wire:
`reading_state` op `Publication`, `POST /reading-state`, hub `continue_reading` als
`GET /reading-state?in_progress=true`. Afgewezen: een generiek `progress`-model over beide
(`watch_states` draagt lease-semantiek die boeken niet hebben; een gedeelde tabel maakt de
kijkstatuscode complexer voor een tweede gebruiker die er niets aan heeft), en `watch_states`
hergebruiken met `position_ms` als paginanummer (semantiekwijziging, regel 3).

## RB-5 Zoeken blijft per domein, de client sectioneert


**Bijgesteld op 4 september 2026 (VRAGENLIJST 34, 29).** Server-side is de zoekmachine PostgreSQL met exacte en prefixmatches, Full Text Search én `pg_trgm` voor fuzzy, met één deterministische ranking over titel, serie, acteur en auteur; geen embeddings. Genres houden een displaynaam en een genormaliseerde facetkey (Unicode casefold, trim, whitespace).

`GET /search` blijft audiovisueel (DEC-045). Boeken en auteurs komen uit `GET /ebooks?q=`. De
webclient doet twee aanvragen en toont secties; geen samengevoegde ranking, geen projectielaag,
omdat er op Pleya Server precies één bron is. Server-side gaat de ILIKE achter een
`pg_trgm`-index, zonder semantiekwijziging. Unified search over meerdere servers blijft een
clientprojectie (DEC-066 op main) en raakt de server niet. Afgewezen: `ItemKind: book` (ps14-
voorstel wijziging A) en een `/search` die twee resourcevormen mengt.

## RB-6 Beheer-API: dezelfde resources, schrijfbaar, klasse `admin`, capability `administration`

Geen aparte `/admin`-namespace op de server. `POST /libraries`, `PATCH` en `DELETE
/libraries/{id}`, `POST /libraries/{id}/scan`, `POST /libraries/{id}/adopt`; nieuwe resources
`/storage/roots`, `/jobs`, `/scans`, `/settings`, `/server/environment`, `/server/log`,
`/server/connectivity-check`, `/server/rotate-signing-key`. Alles klasse `admin`, 404 voor wie
het niet mag (bestaande regel in `authorize.go`). `capabilities.administration: true` zodra de
set compleet is. Reden: de webclient praat alleen `/pleya/v1` (DEC-046), en een resource die al
bestaat krijgt geen tweede pad om schrijfbaar te worden. Afgewezen: een `/admin/*`-prefix
(zou twee representaties van dezelfde bibliotheek opleveren).

## RB-7 Afgeleide artworkformaten zijn verplicht in dit traject


**Bijgesteld op 4 september 2026 (VRAGENLIJST 27).** Twee ladders: poster en boekcover 240, 480, 960, 1920; backdrop en hero 480, 960, 1920, 3840. Alleen on-demand, nooit boven de bronresolutie; `width` normaliseert naar een ladderwaarde.

PS-7A wordt uitgevoerd in slice S4 en dekt posters, backdrops en boekcovers. Een vaste ladder
240, 480, 960, 1920 breed; de server rondt `?width=` op naar de eerstvolgende trede, cachet op
schijf in `CacheDir`, single-flight per (id, trede), sterke `ETag` op het afgeleide bestand
(content-hash van het cachebestand, wat DEC-050 niet raakt: dat besluit gaat over `/stream`).
Reden: het northstar-raster toont 8 posters naast elkaar op 1600 en op 393 bij DPR 2 vraagt een
kaart van 110 pt een beeld van 220 px; originelen van 1500 px per kaart maken de webclient op
een NAS en op mobiel onbruikbaar, en `srcset` in de client is de standaardoplossing die deze
ladder nodig heeft. Afgewezen: uitstel houden (het responsieve ontwerp maakt de oude defer
onhoudbaar) en client-side schalen (de bytes zijn dan al over de lijn).

## RB-8 Bibliotheken: derde soort, `managed`, instellingen op de rij

`libraries.kind` krijgt `books`; `libraries.managed` (`config` of `db`) legt vast wie de bron
is; `scan_interval_seconds` en `scan_on_start` komen als kolommen op `libraries`, niet in een
aparte `library_settings`-tabel (één rij, één eigenaar). De `.env`-overname uit PS-11A
criterium 7 blijft: dezelfde id en slug, daarna negeert de server de `.env`-regel en logt dat.
Een niet-lege bibliotheek verandert nooit van soort (ps14 beslissing 4).

## RB-9 Capabilities blijven de waarheid, `feature_level` blijft 1


**Bijgesteld op 4 september 2026 (VRAGENLIJST 35).** Level 1 is de verwachte uitkomst van een volledig additieve diff, geen onaantastbare regel. Blijkt aan het eind van een venster één wijziging werkelijk te breken, dan gaat het level of de versie passend omhoog; een breaking change wordt nooit verborgen om op 1 te blijven.

Nieuwe vlaggen: `administration`, `ebooks`, `filters`, `reading_state`, `artwork_sizes`. Elke
vlag hangt aan een concrete voorwaarde in code (zoals `watch_state` aan de store), nooit aan een
literal die per ongeluk waar blijft. `feature_level` gaat niet omhoog: geen enkele wijziging
verandert globale semantiek (masterplan correctie 7).

## RB-10 Het protocolvenster gaat per slice open en dicht

Vier vensters, elk met een eigen DEC en een uitputtende lijst: S1 (settings, server, admin-
klasse), S2 (libraries schrijfbaar, storage, jobs, scans), S3 (ebooks), S5 en S6 (filters,
facetten, reading-state). Elk venster sluit met `scripts/check_protocol.sh` groen én de
fake-server van Pleya Verify bijgewerkt (RB-14). Afgewezen: één venster voor het hele traject,
omdat de vriezingsregel uit CLAUDE.md juist bestaat om "even open laten staan" te voorkomen.

## RB-11 Integratie: eerst `main` in, dan pas bouwen; DEC-nummers volgen `main`

Slice S0 maakt `integration/pleya-server-rebaseline` van `main`, merget `feat/pleyaserver`
en lost de vier bekende conflicten op. De server-DEC's 063 tot 073 en 093 worden bij die merge
hernummerd naar de eerste vrije nummers op `main` (096 en verder), met een mappingtabel in
`docs/DECISIONS.md` en een grep over `docs/` en `pleya_server/` die geen oude verwijzing meer
vindt. `feat/netflix-mobile` en `feat/ebooks` mergen niet in dit traject; zij hernummeren bij
hun eigen merge tegen de dan geldende `main`. Reden: `main` is de enige lijn die alle andere
lijnen al één keer heeft opgenomen.

## RB-12 Locator voor leesvoortgang: Readium Locator, engine Readium TypeScript Toolkit


**Bijgesteld op 4 september 2026 (VRAGENLIJST 15, 26).** Vervangt de CFI-plus-spine-formulering. Canoniek is een Readium-compatible Locator: `href`, `type`, `locations.progression`, `locations.totalProgression`, `locations.position` waar beschikbaar, optioneel `locations.partialCfi`, optionele `text`-context voor bladwijzers, plus een publicatie-revisie of digest naast de locator zodat hij nooit blind op een vervangen EPUB wordt toegepast; spine-index is afgeleide informatie. De webreader is de Readium TypeScript Toolkit met de chromeless `@readium/navigator`-laag; de Go-kant levert een Readium Web Publication Manifest en de resources (`GET /ebooks/{id}/manifest`, `GET /ebooks/{id}/resources/{path}`). Geen tweede engine als runtimefallback; epub.js alleen als gedocumenteerde contingency na een spike met een aantoonbare blocker. Dit bindt ook de app-reader op `feat/ebooks`.

De server bewaart een locator als `{cfi, spine_index, fraction}` en valideert alleen de vorm.
CFI is de enige locator die twee verschillende readerengines kunnen produceren en terugvinden;
spine-index en fractie zijn de terugval voor een engine die geen CFI heeft en voor de
voortgangsbalk. **Dit is een cross-clientbesluit dat de app-reader op `feat/ebooks` bindt** en
hoort vóór S6 als DEC vastgelegd te worden. De keuze van de webreaderengine (S12) volgt eruit;
een engine zonder CFI valt af.

## RB-13 Serverbeheer op de app

Geen beheerschermen in de Flutter-app in dit traject; de app leest `administration` en toont
alleen de ingang naar de webclient (URL uit `GET /server`). Dat is de grens die PS-3W-voorstel
5.4 al trok.

## RB-14 Pleya Verify en de webclient

De webclient wordt getest met Playwright tegen de echte Go-binary (bestaand, `e2e-stack.sh`);
Verify krijgt geen browserdriver. Wat er wél bij komt: een contracttest die
`pleya_verify/fixture_server/lib/src/pleya_fake_server.dart` tegen `openapi.yaml` legt, zodat
een protocolwijziging niet groen kan blijven op een dode fake, en één Verify-scenario per
golden journey die een app raakt (deel L).

## RB-15 CI voor Go en web is voorwaarde, geen sluitstuk

`.github/workflows/ci.yml` krijgt drie jobs erbij: `pleya-server` (vet, test met Postgres-
service, `verify-protocol.sh`), `pleya-web` (check, test, build, e2e tegen de wegwerpstack) en
`protocol` (`check_protocol.sh`). Zonder deze drie is "gecontroleerde ontwikkelstroom" een
belofte zonder bewijs.

## RB-16 De grens tussen serverinstelling en host-config

| Blijft omgeving (alleen-lezen in Diagnostiek) | Wordt serverinstelling (`server_settings`, via `PATCH /settings`) | Blijft client-local |
| --- | --- | --- |
| `DATABASE_URL`, `HTTP_ADDR`, `CONFIG_DIR`, `CACHE_DIR`, `TRANSCODE_DIR`, `MEDIA_DIRS`, `INODE_TRUST`, `LOG_LEVEL`, `FFPROBE_PATH`, `FFPROBE_TIMEOUT`, `JOB_WORKERS`, `SHUTDOWN_TIMEOUT`, `SETUP_CODE_TTL`, `WATCH_LEASE`, vertrouwde proxy's | servernaam, publiek adres, scaninterval en scan-bij-start (standaard, per bibliotheek overrulebaar), `access_token_ttl`, `refresh_token_ttl`, `refresh_grace_window`, `stream_token_ttl`, `stream_session_ttl`, `stream_sessions_max`, artworkladder aan/uit | thema, taal, afspeelvoorkeuren, readerinstellingen, home-indeling |

Regel: wat de server nodig heeft om te starten of wat het bestandssysteem raakt is omgeving;
wat het gedrag van een draaiende server wijzigt en veilig op afstand te veranderen is, is een
instelling; een instelling in `.env` blijft werken als standaard en de databasewaarde wint. Een
instelling met een veiligheidsgrens (TTL's) heeft een boven- en ondergrens in code.

## RB-17 Hardening die dit traject meeneemt

Rate limit op `/auth/refresh`, opruimjob voor verlopen `stream_sessions`, begrensde backoff op
`probe_attempts`, een panic-recovery-middleware met een protocolvormige 500, en een
lichaamslimiet op elke schrijvende beheeraanvraag. Geen ervan verandert het contract.

## RB-18 De grens van "af": het totaalplan, met Plex-migratie als keuze

Beslist door Michel op 4 september 2026. Dit traject is af wanneer alle Plex-off blockers uit
de replacement matrix `Productgereed` zijn en de `PLEX_OFFLINE_REPLACEMENT_GATE` uit hoofdstuk 25
slaagt, met uitzondering van de categorie migratie: PS-12 is een keuzefase die pas na afronding
en op uitdrukkelijk besluit start, nooit automatisch. Buiten scope blijven PS-13 (externe
transcode-workers, schaalvraag zonder blocker), PS-16 (offline boeken, gereserveerd) en de
app-reader (PS-15 op `feat/ebooks`). Alles wat de matrix in 5.1 tot 5.17 als (A) benoemt en aan
een fase hangt, heeft in deel I een slice.

## RB-19 MCP is een dunne laag op dezelfde API, in dezelfde binary

Pleya Server biedt een MCP-server aan op `/mcp` met het Streamable HTTP-transport, in dezelfde
binary en op dezelfde origin. Elke tool is een één-op-één-afbeelding van een operatie uit
`openapi.yaml` en roept dezelfde servicelaag aan als de HTTP-handler; er is geen tweede
autorisatie, geen tweede validatie en geen tweede representatie. Lezende tools bestaan voor
elke gebruiker binnen zijn zicht (catalogus, zoeken, eigen voortgang); beherende tools voor
`owner` en `admin`; de drie destructieve tools (`library_delete`, `user_delete`,
`signing_key_rotate`) vragen een `confirm`-argument met dezelfde waarde als de HTTP-variant.
Toolresultaten zijn data en nooit instructies: titels, samenvattingen en logregels komen
ongewijzigd maar als tekst terug, en de serverkant voegt er geen prompttekst aan toe. Reden:
DEC-082 op `main` trok dezelfde grens voor Pleya Verify (dunne adapter, geen tweede
implementatie), en DEC-046 zegt dat een client via het protocol nooit meer rechten krijgt dan
het protocol geeft. Afgewezen: een losse stdio-adapter (onbruikbaar op een NAS voor een agent
op een ander toestel) en een eigen toolset met "handige" samengestelde acties (een tweede
API-oppervlak dat de matrix van DEC-072 ontloopt). Capability `mcp`; uitschakelbaar in
Beveiliging; de HTTP-API blijft dan werken.

## RB-20 API-tokens zijn sessies


**Bijgesteld op 4 september 2026 (VRAGENLIJST 17, 23).** TTL is absoluut (geen sliding expiry); rotatie met overlap zodat een integratie zonder downtime wisselt. Het auditlog dekt naast mutaties ook securityrelevante logins (geslaagd en mislukt), token aanmaken, intrekken en roteren, rol- en permissiewijzigingen, onderhoudsmodus, MCP-mutaties en securitygevoelige configuratiewijzigingen; catalogusreads, playbackticks en readerreads niet.

Een agent kan de refreshflow niet lopen. Daarom krijgt een gebruiker (zelf, of een beheerder
namens iemand) een API-token: een langlevende bearer met een naam, een bereik (`admin`,
`maintenance`, `read`) dat nooit boven de rol van de gebruiker uitkomt, en een vervaldatum. Het
token is een rij in `sessions` met `kind = 'api'` en `device_name` = tokennaam, en alleen een
hash wordt bewaard. Het staat bij Ingelogde toestellen, wordt met `DELETE /sessions/{id}`
ingetrokken en valt onder dezelfde in-process intrekking. Elke mutatie via een API-token, en
via een gewone sessie in beheer, landt in `admin_audit` met wie, welke sessie, welke operatie
en de uitkomst. Afgewezen: een apart tokenmodel naast sessies (twee intrekkingspaden), en
tokens zonder vervaldatum als standaard (de standaard is 90 dagen, "nooit" is een bewuste keuze
in het formulier).

## RB-21 PlaybackPlan en transcode volgen hoofdstuk 10 en 11 van de architectuur


**Bijgesteld op 4 september 2026 (VRAGENLIJST 37, 38, 39, 40, 41).** VAAPI, QSV en NVENC zijn alle drie first-class backends met runtime-detectie; voorkeur is de passende hardware-encoder voor bron en doelcodec, daarna software. Nooit upscalen; 4K bij voorkeur direct play, anders gecontroleerd naar 1080p. Gelijktijdige sessies en het quotum van de transcodemap zijn instellingen met grenzen; cachebeheer beschermt actieve sessies. Ondertitels: bitmap (PGS, VobSub/DVD) en ASS/SSA met niet-vertaalbare styling worden ingebrand, gewone tekst wordt WebVTT. Heartbeatinterval korter dan de time-out van 60 s.

`POST /playback/plan` neemt de `DeviceCapabilities` uit PS-5 (de client is de enige die scherm,
uitgang, decoder en verbinding kent) en antwoordt met `{delivery_mode, version_id, reason{code,
params}}`: direct play als standaard, remux of transcode als uitzondering met een sessie en een
levenscyclus, fMP4 en HLS, geen DASH (DEC-036). De planner filtert op harde beperkingen en scoort
op zachte voorkeuren, tabelgedreven getest. Een transcode-sessie is een ffmpeg-kindproces met een
vaste argumentlijst (nooit uit invoer), een time-out zonder client-heartbeat, en een map onder
`TranscodeDir` die bij het opruimen van de sessie weggaat. Hardwareversnelling wordt bij het
opstarten gedetecteerd en als servercapability getoond, nooit aangenomen. Capabilities
`playback_plan` en `transcode` gaan pas aan als het pad echt werkt. De browserspeler krijgt
hls.js voor het transcodepad; Safari speelt HLS native.

## RB-22 Downloads naar de app: het originele bestand of een omgezette versie, altijd met digest

`POST /downloads` vraagt een download aan (origineel of een trede uit de ladder), de server
levert via `GET /downloads/{id}/file` met een sterke digest over het samengestelde bestand
(dat is de byte-identiteit die DEC-050 voor `/stream` uitsloot en voor downloads juist vroeg).
Het recht `download` per bibliotheek beslist; sync-back van offline kijkstatus gebruikt de
bestaande wachtrij en `POST /watch-state` met `backlog`. Boeken blijven de EPUB-route.

## RB-23 Verzamelingen en afspeellijsten zijn serverresources per gebruiker

`collections` (eigenaar, titel, zichtbaarheid: privé, iedereen, per gebruiker) met `collection_items`
zonder volgorde, en `playlists` met `playlist_items` mét volgorde en alleen de eigenaar. Beide
leven op de server en niet in de app; de app en het web spreken dezelfde resources. Slimme
lijsten (B5) niet in dit traject.

## RB-24 De persoonlijke laag: geschiedenis, favorieten, waarderingen, spoorvoorkeuren

`play_history` schrijft één rij per afgesloten afspeelsessie (start, einde, positie, toestel),
gevoed door de bestaande watch-state-events en niet door een tweede rapportage;
`favorites(user, item)`; `ratings(user, item, value)`; `track_preferences(user, item_or_show,
audio, subtitle)`. Capabilities `history`, `favorites`, `ratings`, `track_preferences`.
"Bekeken door" op detail leest `play_history` binnen het huishouden.

## RB-25 Realtime: één websocket-hub met volgnummers, polling blijft de correcte weg

`GET /events` (websocket, bearer via eerste bericht, nooit in de URL) levert events met een
oplopend volgnummer per verbinding en `since=` om een gat te dichten: scanvoortgang,
watch-state van een ander toestel, sessiestatus, serverbrede meldingen. Elke event is ook via een
gewone aanvraag op te halen; een client zonder websocket blijft volledig functioneel (masterplan
correctie 6). Events zijn per gebruiker gefilterd op zicht. Capability `realtime`.

## RB-26 Back-up, restore en upgrade zijn serverfuncties met een controleerbare uitkomst


**Bijgesteld op 4 september 2026 (VRAGENLIJST 54, 55).** Doel (default `/backups`), tijdstip (03:30) en retentie (14) zijn instellingen. De back-up bevat database plus instance-, config- en cryptografische state met veilig verpakte secrets; de server waarschuwt als het doel op hetzelfde failure-domain staat en ondersteunt een off-host of NAS-gemount doel; de wekelijkse hersteltest draait migraties, schema en kernqueries in een geïsoleerde tijdelijke database.

Een back-up is `pg_dump` plus `/config` in een tar onder `BackupDir`, gepland en handmatig,
met een wekelijkse hersteltest in een wegwerpschema die de titels natelt. Restore zet de server
in onderhoudsmodus, laadt de back-up en herstart; de bevestiging noemt wat er verloren gaat.
Upgrade is de image wisselen; de server maakt vóór de eerste migratie zelf een back-up en start
niet als dat mislukt; een database nieuwer dan de binary geeft een duidelijke weigering. De
vier faalpaden (schijf vol, database weg, transcoder-crash, kapot bestand) krijgen elk een
foutcode en één test die ze als set draait.

## RB-27 Metadata-providers: automatisch matchen en inladen, handmatige correctie wint altijd


**Bijgesteld op 4 september 2026 (VRAGENLIJST 44 tot 53).** Precedence per veld: handmatige of gepinde override, dan sidecar, dan provider, dan technisch uit het bestand afgeleid. Beheer krijgt per-field overrides (titel, sorteertitel, jaar, beschrijving, genres, releasedatum en overige presentatievelden) met zichtbare provenance, expliciet handmatig, terug te zetten naar sidecar of provider, nooit door een scan overschreven; bevestigen, afwijzen, fix-match en artwork kiezen blijven daarnaast. Artworkselectie is type-aware (poster en cover: nl, taalneutraal, en; backdrop en hero: taalneutraal, nl, en; daarna kwaliteit, votes, aspect) en een gekozen artwork wordt gepind. Externe id koppelt direct; titel plus jaar alleen als mediatype klopt en het resultaat ondubbelzinnig is. Een providerronde na een scan raakt alleen nieuwe, gewijzigde, ongematchte of dirty items. De TMDB-sleutel is servergebonden, gemaskeerd na opslaan, nooit teruggeleverd. Provider-rating en persoonlijke `user_rating` blijven gescheiden.

Providerabstractie met TMDB als eerste implementatie, de kandidatenlaag uit hoofdstuk 8.2 (een
provider schrijft nooit op het canonieke record), de driestapsmatch uit 19.1 met ambiguïteit die
nooit vanzelf resolvet, en een providerronde als job met exponentiële vertraging op rate limits.
Wat automatisch gebeurt na een scan: matchen, samenvatting, genres, kijkwijzer, cast, regie,
beoordelingen, en artwork (poster, backdrop, logo) ophalen en in `CacheDir` opslaan op de ladder
uit RB-7. Sidecars (S4) blijven laag 2 en winnen van de provider waar ze bestaan; een
handmatige correctie (kandidaat bevestigen of afwijzen, artwork kiezen uit kandidaten) overleeft
drie providerrondes. Attributie is zichtbaar op elk scherm dat providerdata toont. De open
productbesluiten uit de matrix worden zo ingevuld: B1 alleen bevestigen of afwijzen (geen vrije
editor), B2 fix-match tegen de provider, B3 kiezen uit kandidaten zonder upload (mounts blijven
alleen-lezen; gekozen artwork leeft in de cache), B4 extra's uit de bestandsboom herkennen, B8
ondertitels zoeken via de server als latere uitbreiding op dezelfde providerlaag. SSRF-grens:
alleen vooraf bekende providerhosts, geen redirects naar buiten die lijst.

## RB-28 Remote hardening en observability


**Bijgesteld op 4 september 2026 (VRAGENLIJST 56, 57).** Metrics standaard op loopback maar met een configureerbare private bind (nooit publiek standaard), zodat een container-netwerk ze kan lezen. De canonieke Pleya Web-origin en de externe base-URL van déze server zijn twee aparte instellingen, naast trusted-proxy-CIDR's (alleen daarvan worden Forwarded-headers geloofd) en een expliciet CORS- en originbeleid.

Vertrouwde proxy's uit de omgeving, externe hostnaam uit `public_url`, subpad-montage, rate
limits op auth, Prometheus-metrics op loopback, `/healthz` en `/readyz` (bestaan), en een
publieke-endpointlijst van één regel met één test. Geen tunnel of relay in de binary (DEC-037).

## RB-29 Authfundering voor de webclient: HttpOnly-refreshcookie, same-origin als voorkeur

**Bijgesteld op 4 september 2026 (VRAGENLIJST 19, 57).** Vóór beheer via de webapp beschikbaar
komt (S1) krijgt de webclient een refreshcredential als HttpOnly-, Secure-cookie met een passende
SameSite-policy, nooit leesbaar door JavaScript; het accesstoken is kortlevend en leeft alleen in
geheugen; refreshrotatie blijft; Origin- en CSRF-bescherming waar de topologie dat vereist. De
voorkeur is dat web en server same-origin zijn (de bundel in de binary, zoals nu op
`web.pleya.app`). Wijkt de web-origin af van de server-origin, dan is een expliciet ontworpen
BFF- of auth-flow verplicht; een ontwerp dat leunt op third-party cookies tussen `web.pleya.app`
en willekeurige Pleya Server-origins is uitgesloten. Dit vervangt K.20 en PS-3W 4.2 "uitgesteld".
