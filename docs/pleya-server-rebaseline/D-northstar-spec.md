# D. Northstar-specificatie

Per scherm: route, doel, gebruiker, data, componenten, interacties, responsief gedrag, staten,
en wat het scherm van de backend vraagt. De beelden staan in `docs/assets/pleya-web-northstar/`.
Endpoints zonder ster bestaan op `5eebb83`; een ster (*) betekent nieuw of gewijzigd, met de
slice uit deel I waar het landt.

**Bijgesteld op 4 september 2026** met de afwijkingen uit `VRAGENLIJST.md` hoofdstuk 8: de
Readium-manifestlaag voor de webreader (15, 26), de HttpOnly-refreshcookie en het originmodel
(19, 57), per-field metadata-overrides met provenance (53), de twee artworkladders (27), de drie
hwaccel-backends (37) en de uitgebreide auditscope (23). De zes ontbrekende schermen staan
onderaan in D.5 met hun nummer.

## D.1 Gedeelde shell en componenten

**Shell.** Boven 900 px een sticky topnav van 64 px: wordmark links, cluster Home · Series ·
Films · Boeken · Mijn Pleya gecentreerd, rechts een inline zoekveld, de Beheer-pil (alleen
`owner` en `admin`, amber) en de avatar. Onder 900 px de iOS-kop (wordmark, zoekicoon, avatar)
en een vaste tabbalk met vijf slots. Boeken verschijnt in beide alleen wanneer `GET /libraries`
minstens één bibliotheek met `kind: books` teruggeeft die deze gebruiker mag zien. Zonder
boekenbibliotheek zijn er vier slots; de webclient vult het vierde slot niet met Live TV of
Downloads omdat de server die capabilities niet heeft.

**Componenten** (namen zoals ze in `pleya_web/src/lib/components/` moeten komen):

| Component | Bestaat | Wat verandert |
| --- | --- | --- |
| `TopNav`, `TabBar`, `MobileHeader` | `NavRail`, `BottomBar` | nieuw: rail vervalt, tabbalk krijgt vijf slots en het Beheer-item vervalt op smal (ingang via Mijn Pleya) |
| `Hero` | ja | 21:9 op ≥1200, 16:9 op 1024, portret 520 px op smal; scrim links op breed, onder op smal; `Meer info` als tweede knop; segmentindicator |
| `HubRail` | ja | bleed tot de paginarand, fade rechts, posterbreedte uit `--poster-w` per breedte |
| `MediaCard` | ja | staten uit scherm 16: hover met ring en acties, focus met ring op een gap, voortgang, gezien, nieuw-punt, versiebadge, artwork-fallback met titel |
| `BookCard`, `BookCover` | nee | 2:3 met CSS-fallback zolang de cover niet geladen is; voortgang op de cover |
| `ContinueReadingCard` | nee | liggend, cover rechts, ambience uit de dominante coverkleur (server levert die niet: client berekent uit de geladen cover, zoals golden 01b op `feat/ebooks` beschrijft) |
| `EpisodeRow` | nee | 16:9 thumb, nummerbadge, voortgang, twee regels synopsis |
| `Chips`, `FilterChip` | deels (search) | één regel: actief is roodgetint met rode rand (DEC-090-audit 4.8) |
| `StateView` | ja | ongewijzigd; skelet erbij als `Skeleton` |
| `DataTable`, `StatTile`, `Alert`, `Panel`, `KeyValue`, `ConfirmDialog`, `Steps`, `Choice`, `Toggle`, `LogView` | nee | beheerprimitieven, allemaal op dezelfde tokens |
| `AdminNav` | nee | zijbalk ≥900 met badges; lijstpagina (33) op smal |

**Responsief.** Vier meetpunten uit `ScreenBreakpoints`: 600, 900, 1200, 1600. Inset 48/32/16,
posterbreedte 190/170/150/110, railgap 20/16/12. Tabellen scrollen in hun paneel onder 900; de
pagina scrolt nooit horizontaal. Beheerformulieren gaan van twee naar één kolom onder 1200.

**Toegankelijkheid.** Elke route met het toetsenbord bedienbaar (bestaand criterium PS-3W), de
focusring is 3 px wit op een gap van 3 px, hover alleen achter `@media (hover: hover)`, geen
axe-overtreding op vijf breedtes, `prefers-reduced-motion` zet de lift en de fade uit.

## D.2 Consumer

### 01 Home (`/`)

Doel: in één scherm zien wat je aan het kijken en lezen was, wat er nieuw is, en één titel om
direct te starten. Gebruiker: iedereen.

| Rij | Data | Bestaat | Slice |
| --- | --- | --- | --- |
| Hero | eerste vijf uit `hubs/recently_added` met backdrop; samenvatting uit `summary`* | hub ja, `summary` nee | S4 |
| Verder kijken | `hubs/continue_watching` | ja (`2c214fd`) | S8 toont |
| Verder lezen | `GET /reading-state?limit=`* gejoind met `/ebooks/{id}` | nee | S6, S9 |
| Volgende afleveringen | `hubs/next_up`, thumb = backdrop van de show of aflevering | ja | S8 |
| Recent toegevoegd per bibliotheek | `hubs/recently_added?library_id=` | ja | bestaand |
| Nieuw in Boeken | `GET /ebooks?library_id=&sort=-added_at`* | nee | S3, S9 |

Interacties: kaart klik opent detail; hover toont afspelen, mijn lijst (grijs tot PS-9P),
meer. Hero-knoppen: Afspelen start de speler (S13) of, tot die er is, opent detail; Meer info
opent detail. Een rij zonder inhoud tekent zichzelf niet (PS-4E criterium 1). Lege server:
scherm 44-variant zonder rijen toont de uitleg uit scherm 13.

### 02 Films, 03 Series (`/films`, `/series`)

Landing per soort met een link naar de complete catalogus (DEC-064 op main: twee niveaus).
Rijen: Recent toegevoegd (bestaand), Nog niet gezien (`/libraries/{id}/items?watched=false`*,
S5), per genre (`?genre=`*, S4 en S5), Onlangs bekeken (`GET /watch-state?limit=` bestaand,
gefilterd op `watched`), en op Series vooraan Volgende afleveringen en Nieuwe afleveringen
(`recently_added` met `kind=episode`, bestaand). Geen Verder kijken buiten Home (DEC-086).

### 04 Boeken (`/books`)

Rijen: Verder lezen, Recent toegevoegd, Reeksen (`GET /ebooks/series`*), Nog niet begonnen
(`/ebooks?state=unread`*), per genre (`/ebooks?subject=`*). Alles S3, S6, S9. De landing
verschijnt alleen als het slot bestaat (D.1).

### 05 Alle films (`/films/all`, ook `/series/all`, `/books/all`)

Raster van `auto-fill` op `--poster-w`, drie kolommen op smal. Filters als chips: genre, jaar,
kijkstatus, kwaliteit, met facetten en tellingen (`GET /libraries/{id}/facets`*, S5). Actieve
filters staan als verwijderbare chips vooraan. Sorteren: titel, toegevoegd, jaar (bestaand),
laatst gekeken, duur (S5). Oneindig laden op de cursor (bestaand). De alfabalk uit PS-7F is
uitgesteld tot de meting op de grote testbibliotheek.

### 06, 07 Zoeken (`/search?q=`)

Eén veld, chips Alles · Films · Series · Afleveringen · Boeken (altijd alle vijf, ook zonder
treffers, conform DEC-095), secties per soort met telling. Films, series, afleveringen uit
`GET /search` (bestaand, DEC-045); boeken en auteurs uit `GET /ebooks?q=`* (S3, S5). De client
doet twee aanvragen en plaatst ze onder elkaar; er is geen samengevoegde ranking en geen
projectielaag nodig, want er is één bron. Leeg: een uitweg met een suggestie (de server levert
geen "bedoelde je"; de client toont de laatst succesvolle zoekterm of de catalogus).

### 08 Filmdetail (`/items/{id}`)

Backdrop-hero op breed, 16:9-voorvertoning op smal. Titel in ArchivoBlack op breed, Inter op
smal (de iOS-set). Metaregel: jaar, kijkwijzer*, duur, genre*, kwaliteitstags uit
`versions[].video`. Knoppen: Hervatten met resttijd uit `user_state`, Vanaf het begin, gezien
(`POST /watch-state` met `mark_watched`), meer. Versieregel bij meer dan één versie (bestaand:
`versions[]`). Cast en regie* (S4 sidecar, anders PS-7). Panelen: audio en ondertitels uit
`streams[]` (bestaand), bestand uit `versions[]` en `files` (bestaand), laatst gekeken uit
`user_state` plus toestelnaam* (de server bewaart `owner_session_id`; de naam vraagt een join op
`sessions`, S6). Rij "Meer sciencefiction" vraagt genres (S4).

### 09 Seriedetail (`/items/{id}` voor `show`)

Zelfde hero. Hervatten wijst naar de aflevering uit `next_up` voor deze show (client leest de
hub en filtert op `parent`). Seizoenchips uit `children` (bestaand), afleveringen uit
`children` van het seizoen (bestaand), synopsis per aflevering* (S4). Gezien per seizoen is een
reeks `mark_watched`-events (bestaand contract; de client doet het per aflevering).

### 10 Boekdetail (`/books/{id}`)

`GET /ebooks/{id}`* met cover uit `GET /ebooks/{id}/cover?width=`* en ambience client-side.
Lees verder opent de webreader (S12), die de publicatie laadt als Readium Web Publication
Manifest (`GET /ebooks/{id}/manifest`* en `GET /ebooks/{id}/resources/{path}`*, S6) en op de
locator uit `GET /reading-state/{id}`* springt (S6);
Downloaden haalt `GET /ebooks/{id}/file`* met de sterke validator (S3). Feiten: jaar, genre,
pagina's (uit de OPF als die het draagt, anders weggelaten), taal. Reeks uit `series_name` en
`series_index`.

### 17, 18 Verzamelingen en afspeellijsten (`/collections`, `/playlists/{id}`)

`GET/POST /collections`, `PATCH/DELETE /collections/{id}`, `PUT /collections/{id}/items`,
idem voor `/playlists` met volgorde* (S19). Een verzameling heeft een eigenaar en een
zichtbaarheid (privé, gedeeld met iedereen, per gebruiker); een afspeellijst is van één
gebruiker en speelt op volgorde. Vierluik uit de eerste vier posters; herordenen als eigen
modus; kaartmenu "Toevoegen aan" op elk item (08, 09, 10).

Beide hangen onder Mijn Pleya: op breed blijft dat de actieve nav, op smal is het de actieve
tab. Op 17 staat het segment (verzamelingen tegenover afspeellijsten) links en de sortering
rechts, zodat een filter niet op een sortering lijkt. Op 18 draagt elke rij zijn eigen
kijkstatus: een wit vinkje voor uitgekeken, een percentagepil voor onderweg, niets voor
ongezien. De speelduur in de kop is de som van de rijen, dus een implementatie die hem uit een
apart veld haalt moet dat veld ook bijwerken bij herordenen en verwijderen.

### 19 Kijkgeschiedenis, favorieten, waarderingen (`/my/history`, `/my/favorites`)

`GET /history?kind=&cursor=`* uit `play_history`, `DELETE /history`* en
`DELETE /history/{id}`* (vraag 31: de gebruiker wist zijn geschiedenis volledig of selectief),
`PUT/DELETE /favorites/{item}`*, `PUT /ratings/{item}`* (S20). Boeken doen mee via
`reading_states`. Per rij toestelnaam en tijdstip; "Bekeken door" op detail vraagt dezelfde
tabel.

Een waardering is een geheel getal van 1 tot 10 op `user_rating` en staat los van de
providerscore uit TMDB, die ernaast in dezelfde rij zichtbaar is (vraag 32). De client mag hem
als sterren tekenen zolang de waarde die over de lijn gaat de schaal 1 tot 10 houdt; een
duim omhoog of omlaag verliest informatie die Plex en Trakt wel dragen en is daarom geen
toegestane representatie.

### 11 Mijn Pleya (`/my`)

Account (`GET /users` gefilterd op zelf; "eigen account-id" ontbreekt in het contract, deel J),
toestellen (`GET /sessions`, bestaand), uitloggen (`POST /auth/logout`, bestaand), wachtwoord
(`PATCH /users/{id}`, bestaand). Voorkeuren (uiterlijk, taal, afspelen, lezen) zijn client-local
in `localStorage` tot PS-9T; het scherm toont ze als lokale instelling. Serverpaneel uit
`GET /server` en `GET /libraries`, met de ingang naar beheer voor `owner` en `admin`. Het
paneel Downloads (scherm 11b, S23) leest `GET /downloads`* en toont per regel titel, trede uit
de ladder, digest-status en het toestel dat hem haalde; web downloadt zelf alleen boeken
(VRAGENLIJST 43), dus de videoregels zijn een overzicht van wat de apps hebben.

### 12 Inloggen (`/login`), 13 lege bibliotheek, 14 onbereikbaar, 15 laden, 16 kaartstaten

Bestaande flows uit PS-3W met de nieuwe compositie. 12 zet het refreshcredential als
HttpOnly-, Secure-cookie en houdt het accesstoken alleen in geheugen (RB-29, S1); het scherm
verandert daar niet van, maar "onthoud mij" betekent daarmee de cookie en niet een token in
`localStorage`. 13 toont de beheerknoppen alleen aan
`owner` en `admin` (rol uit `GET /users` op zelf). 14 houdt de sessie en probeert opnieuw met
backoff (bestaand gedrag in `session.svelte.ts`). 15 vervangt de paginabrede spinner door een
skelet in kaartmaten. 16 is een referentieblad zonder route.

## D.3 Serverbeheer (`/admin/...`, klasse `admin`)

Alle beheerschermen lezen en schrijven uitsluitend via `/pleya/v1` (DEC-046). Een gebruiker
zonder beheerrecht krijgt op elke `/admin`-route de 404-pagina van de client, en de server
antwoordt 404 op elke beheeraanvraag. Elke mutatie in deze tabel landt in `admin_audit` met de
uitgebreide scope uit VRAGENLIJST 23 (beheer- en datamutaties, logins, tokens, rol- en
permissiewijzigingen, onderhoudsmodus, securityconfig, MCP-mutaties), 90 dagen bewaard.

| Scherm | Data | Bestaat | Slice |
| --- | --- | --- | --- |
| 20 Overzicht | `GET /server`, `GET /libraries` (met `item_count`), `GET /storage/roots`*, `GET /jobs?state=running`*, `GET /scans?limit=`*, `GET /sessions?all=true`* met lopende streams (`GET /stream-sessions`*), `GET /users` | deels | S1, S2, S10 |
| 21 Bibliotheken | `GET /libraries` met `managed`*, `last_scan`*, `roots`*; `POST /libraries/{id}/scan`*, `POST /libraries/{id}/adopt`* | nee | S2 |
| 22 Bewerken | `PATCH /libraries/{id}`* (title, roots, scan_interval), `GET /storage/roots`*, `GET /users` met permissions, `POST .../scan`, `POST .../refresh-metadata`* | nee | S2, S4 |
| 23 Verwijderen | `DELETE /libraries/{id}`* met `confirm: "<title>"` in de body | nee | S2 |
| 24 Opslag | `GET /storage/roots`* (pad, fs, inodevertrouwen, bron, vrij, totaal, mounted, libraries) en `POST /storage/roots/recheck`* | nee | S2 |
| 25 Scans en taken | `GET /scans`*, `GET /jobs`*, `POST /jobs/{id}/cancel`*, `POST /jobs/{id}/retry`* | nee | S2 |
| 26, 27 Gebruikers | `GET/POST /users`, `PATCH/DELETE /users/{id}`, `PUT /users/{id}/permissions`, `GET /sessions?user_id=`, `DELETE /sessions/{id}` | ja | S10 |
| 28 Media | `GET/PATCH /settings`* (`stream_sessions_max`, `stream_session_ttl`, `stream_token_ttl`), capabilities uit `GET /info`, ffprobe-status uit `GET /server`* | nee | S1 |
| 28 Media (transcode) | `PATCH /settings` met `transcode_hwaccel` (VAAPI, QSV en NVENC als first-class backends, runtime gedetecteerd, software als terugval), `transcode_max_sessions` en `transcode_cache_bytes` als instelbare defaults binnen veilige grenzen (2 en 20 GB), `transcode_ladder`, ondertitelbeleid (bitmap en niet-converteerbare ASS branden in, tekst als WebVTT) | nee | S18 |
| 29 Metadata en artwork | `GET /libraries/{id}/metadata-coverage`* (S4), `GET /artwork/cache`* en `DELETE`* (S4), providerplek alleen tekst | nee | S4 |
| 30 Netwerk | `PATCH /settings` (`server_name`, `web_origin`*, `external_url`*, `trusted_proxies`* als CIDR-lijst, CORS-beleid*), `GET /server` met `listen` en `behind_proxy` alleen-lezen*, `POST /server/connectivity-check`* | nee | S1, S24 |
| 31 Beveiliging | `PATCH /settings` (`access_token_ttl`, `refresh_token_ttl`, `stream_token_ttl` binnen de grenzen uit VRAGENLIJST 18), `GET /sessions?all=true`*, `DELETE /sessions/{id}`, `POST /server/rotate-signing-key`* met impact-confirmatie, `GET /audit?limit=`* met de uitgebreide scope; het paneel meldt dat de webclient zijn refreshcredential als HttpOnly-cookie houdt (RB-29) en toont dus geen refreshtoken | deels | S1, S10 |
| 32 Diagnostiek | `GET /server` uitgebreid met `build`, `database`, `migrations`, `health`*, `GET /info`, `GET /server/environment`* (geredigeerd), `GET /server/log?level=warn&limit=50`* (geredigeerd) | nee | S1 |
| 33 Mobiel | dezelfde data als 20 | | S10 |
| 35 Onderhoud | `GET/POST /backups`*, `POST /backups/{id}/restore`* (met `confirm`), `POST /backups/{id}/verify`*, `GET /server` met `upgrade{image, schema, path}`*, `POST /server/maintenance-mode`* | nee | S25 |
| 28 Media (uitgebreid) | `PATCH /settings` met `transcode_hwaccel`, `transcode_max_sessions`, `transcode_ladder`, `download_quality`; `GET /transcode-sessions`*, `DELETE /transcode-sessions/{id}`* | nee | S18, S23 |
| 29 Metadata (uitgebreid) | providerstatus en providerinstellingen in `/settings` (TMDB-sleutel schrijf-alleen en gemaskeerd, taal `nl-NL` met terugval `en-US`), matchpercentage per bibliotheek uit `GET /libraries/{id}/match-coverage`*, knop volledig verversen, ingang naar 36 | nee | S22 |
| 36 Metadata: match en overrides | `GET /libraries/{id}/matches?state=ambiguous`*, `POST /items/{id}/match`* (kandidaat bevestigen of afwijzen, fix-match), `GET /items/{id}/artwork-candidates`*, `PUT /items/{id}/artwork`* (gepind), `PUT /items/{id}/overrides`* en `DELETE /items/{id}/overrides/{field}`* voor per-field overrides met provenance | nee | S22 |
| 37 Transcode-sessies | `GET /transcode-sessions`* (bron, doel, backend, voortgang, gebruiker, toestel), `DELETE /transcode-sessions/{id}`*, cachedruk uit `GET /server`* | nee | S18 |
| 38 Realtime-status | `GET /server` met `realtime{clients, last_sequence, dropped}`*, de websocket-hub uit `GET /events`* alleen als status, niet als bedieningspaneel | nee | S21 |
| 34 Agents en API-tokens | `GET/POST /auth/api-tokens`*, `DELETE /sessions/{id}`, `GET /server` met `mcp{enabled, url, tools}`*, `GET /audit?source=api&limit=`*, `PATCH /settings` (`mcp_enabled`) | nee | S1, S16 |

Wat bewust geen scherm heeft: een bestandsbrowser, een shell, logbestanden downloaden, poorten
of certificaten, bibliotheek verwijderen inclusief bestanden, artwork uploaden.

## D.4 Setup (`/setup`)

| Stap | Data | Bestaat | Slice |
| --- | --- | --- | --- |
| 40 Eigenaar | `POST /auth/setup` met `server_name`* erbij | deels | S1 |
| 41 Opslag | `GET /storage/roots`* (vóór er een bibliotheek is, met een owner-token) | nee | S2 |
| 42 Bibliotheek | `POST /libraries`* | nee | S2 |
| 43 Scannen | `POST /libraries/{id}/scan`*, `GET /scans/{id}`* elke 5 s; "al gevonden" uit `recently_added` | nee | S2 |
| 44 Klaar | Home | ja | S8 |

Een server die al een eigenaar heeft slaat stap 1 over; een server met bibliotheken uit `.env`
toont stap 3 als "overnemen of nieuwe maken".

## D.5 Matrix scherm, API, bestaat, werk

| Scherm | API of data | Bestaat al | Backendwerk | Frontendwerk |
| --- | --- | --- | --- | --- |
| Home | hubs ×3, `/ebooks`, `/reading-state`, `summary` | hubs | S3, S4, S6 | S7, S8, S9 |
| Films, Series | hubs, `?genre=`, `?watched=`, watch-state | hubs, watch-state | S4, S5 | S8 |
| Boeken | `/ebooks`, `/ebooks/series`, `/reading-state` | niets | S3, S6 | S9 |
| Alle films | items met filters, facetten, sortering | items, cursor, 3 sorteringen | S5 | S8 |
| Zoeken | `/search`, `/ebooks?q=` | `/search` | S3, S5 | S8, S9 |
| Filmdetail | item, children, streams, `summary`, `genres`, `cast`, toestelnaam | item, children, streams | S4, S6 | S8 |
| Seriedetail | idem plus afleveringssynopsis | idem | S4 | S8 |
| Boekdetail | `/ebooks/{id}`, cover, file, reading-state | niets | S3, S6 | S9, S12 |
| Mijn Pleya | users (zelf), sessions, logout | ja, zonder eigen id | J (eigen id) | S8 |
| Inloggen, staten | bestaand | ja | geen | S7 |
| Beheer 20 tot 35 | zie D.3 | users, sessions | S1, S2, S4, S16, S18, S22, S25 | S10 |
| Verzamelingen, afspeellijsten (17, 18) | `/collections`, `/playlists` | niets | S19 | S19 |
| Geschiedenis, favorieten (19) | `/history`, `/favorites`, `/ratings` | niets | S20 | S20 |
| Setup | zie D.4 | setup | S1, S2 | S11 |
| Downloads op Mijn Pleya (11b) | `/downloads` | niets | S23 | S23 |
| Speler (50) | stream, stream-session, watch-state, `playback/plan`, HLS bij transcode | stream | S17, S18 | S13, na mockup 50 |
| Webreader (51) | manifest, resources, file, reading-state | niets | S3, S6 | S12, na mockup 51 |
| Metadata-match en overrides (36) | matches, match, artwork-candidates, overrides | niets | S22 | S10, S22 |
| Transcode-sessies (37) | `/transcode-sessions` | niets | S18 | S10, S18 |
| Realtime-status (38) | `/events`, `realtime` op `/server` | niets | S21 | S10, S21 |

Zes schermen ontbreken nog. Ze gaan in één ronde naar Michel (poort P3 in de masterlijst) en
krijgen deze nummers, binnen de reeksen uit `DESIGN.md` hoofdstuk 6:

| Nr | Scherm | Waarvan afgeleid | Slice |
| --- | --- | --- | --- |
| 11b | Downloads op Mijn Pleya | paneelvorm van 11, statusrij van 25 | S23 |
| 36 | Beheer: metadata-match en per-field overrides | tabelprimitief van 25, kandidatenraster nieuw | S22 |
| 37 | Beheer: transcode-sessies | "nu aan het kijken" van 20, tabel van 25 | S18 |
| 38 | Beheer: realtime-status | diagnostiekpanelen van 32 | S21 |
| 50 | Browserspeler | TV-mockup 18 en iOS-mockup 20 | S13 |
| 51 | Webreader | de readerpanelen uit de e-bookscomp, chromeless `@readium/navigator` | S12 |

De speler en de reader waren niet getekend omdat hun vorm afhing van besluiten die in S12 en S13
zouden vallen. Die besluiten zijn inmiddels genomen (RB-12 bijgesteld: Readium Locator en de
Readium TypeScript Toolkit; VRAGENLIJST 16: `<video>` plus hls.js), dus de vorm ligt nu vast
genoeg om te tekenen.
