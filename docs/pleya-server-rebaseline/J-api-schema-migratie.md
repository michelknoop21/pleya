# J. API- en schemamigratieplan

## J.1 Protocolversie

`info.version` blijft `1.0.0`, `feature_level` blijft 1, het pad blijft `/pleya/v1`. Elke
wijziging hieronder is additief en getoetst aan de zes regels uit hoofdstuk 3 van de
specificatie: nieuwe optionele antwoordvelden (regel 1), niets hernoemd of weg (2), geen
betekeniswijziging (3), geen nieuw verplicht aanvraagveld (4), nieuwe aanvraagbodies gesloten
en nieuwe optionele bodyvelden alleen na een capability (5), nieuwe enumwaarden alleen op
`x-unknown-safe`-velden (6). Een bump is alleen nodig bij een werkelijk brekende wijziging; de verwachting is dat die er niet
is, en dat wordt aan het eind van elk venster op de diff vastgesteld (VRAGENLIJST 35). Onderhandeling loopt via `capabilities`.

Acht vensters, elk met een DEC en een uitputtende lijst; elk sluit met `check_protocol.sh`
groen, de fixtures in `examples/` bijgewerkt, `schema.d.ts` opnieuw gegenereerd, en de
fake-server van Verify aangepast.

## J.2 Venster 1 (S1): beheer-basis

| Wijziging | Huidig | Nieuw | Oude client, nieuwe server | Nieuwe client, oude server | Onderhandeling | Fout |
| --- | --- | --- | --- | --- | --- | --- |
| `capabilities.administration` | afwezig | `boolean`, default false | negeert | ziet false, toont geen beheer | zelf | |
| `GET /settings`, `PATCH /settings` | afwezig | body `SettingsPatch` gesloten, alleen bekende sleutels; antwoord `Settings` met `source` per sleutel (`env`, `db`) | n.v.t. | 404, client verbergt beheer | `administration` | `settings.invalid_value` met veld en grens, 400 |
| `GET /server` | id, naam, versie, `started_at` | plus optioneel `public_url`, `listen`, `behind_proxy`, `trusted_proxies[]`, `build`, `database{version,schema}`, `ffprobe{found,version}`, `health{ready,jobs_running,jobs_failed}`; de extra velden alleen voor klasse `admin` | negeert | mist velden, toont niets | `administration` | |
| `GET /server/environment` | afwezig | lijst `{key, value, redacted}` | n.v.t. | 404 | `administration` | |
| `GET /server/log?level=&limit=` | afwezig | `{entries[{at, level, component, message}]}`, geredigeerd, max 500 | n.v.t. | 404 | `administration` | |
| `POST /server/connectivity-check` | afwezig | `{public_url_reachable, range_intact, behind_proxy}` | n.v.t. | 404 | `administration` | |
| `POST /server/rotate-signing-key` | afwezig | 204, alle sessies ingetrokken | n.v.t. | 404 | `administration` | |
| `GET /stream-sessions` | afwezig | actieve streams met gebruiker, toestel, item, positie | n.v.t. | 404 | `administration` | |
| `GET /users/me` | afwezig; client identificeert op naam | `User` van de aanroeper | n.v.t. | 404, client valt terug op naam | `administration` is niet nodig; vlag `users` volstaat, client probeert en valt terug | |
| `SetupRequest.server_name` | afwezig | optioneel | n.v.t. | body gesloten: nieuwe client stuurt het veld pas als `info.server.setup_accepts_name` (nieuw optioneel veld op `Info`) waar is | `Info` | |
| foutcode `auth.permission_not_allowed` | `auth.user_not_found` | nieuwe code op `PUT /users/{id}/permissions` met `manage` voor `restricted` | onbekende code valt terug op generiek | n.v.t. | patroon, geen enum | 409 |
| `POST /auth/api-tokens` | afwezig | body gesloten `{name, scope, expires_in_days?, user_id?}`; antwoord toont het geheim één keer; `scope` enum unknown-safe (`admin`, `maintenance`, `read`) | n.v.t. | 404 | `sessions` plus nieuw `capabilities.api_tokens` | `auth.scope_exceeds_role` 400 |
| `GET /auth/api-tokens` | afwezig | lijst zonder geheimen; `Session.kind` (`device`, `api`, `legacy`, unknown-safe) en `scope` op `Session` | negeert | 404 | `api_tokens` | |
| `GET /audit?source=&limit=&cursor=` | afwezig | `{entries[{at, user_id, session_id, source, operation, target, outcome}]}` | n.v.t. | 404 | `administration` | |
| `capabilities.mcp` en `Server.mcp{enabled, url, tool_count}` | afwezig | booleans en object | negeert | | zelf | |
| Refreshcookie voor web | tokens in browseropslag | `POST /auth/login` en `/auth/refresh` accepteren `credential_mode: cookie` (optioneel bodyveld achter `capabilities.cookie_auth`) en zetten dan een HttpOnly, Secure, SameSite-cookie; `Server.web_origin`, `external_url`, `cors_origins[]` als instellingen | negeert | valt terug op tokens | `cookie_auth` | `auth.origin_rejected` 403 |
| `Error`-envelop bij panic | 500 zonder body | `server.internal` met request-id | negeert | n.v.t. | | 500 |

## J.3 Venster 2 (S2): bibliotheken, opslag, scans

| Wijziging | Nieuw | Compatibiliteit | Onderhandeling | Fout |
| --- | --- | --- | --- | --- |
| `Library` | plus `managed` (`config`, `db`, enum met `x-unknown-safe`), `roots[]` (`{path, mounted}`), `last_scan{started_at, finished_at, state, files_seen, errors}`, `scan_interval_seconds`, `scan_on_start` | oude client negeert; velden alleen voor klasse `admin` behalve `last_scan.finished_at` | `administration` | |
| `POST /libraries` | body `{title, kind, root_paths[], scan_interval_seconds?, scan_on_start?}` gesloten; `root_paths` moeten in `GET /storage/roots` staan | n.v.t. | `administration` | `storage.root_not_offered` 400, `library.slug_taken` 409 |
| `PATCH /libraries/{id}` | title, root_paths, scan_interval_seconds, scan_on_start; `kind` alleen als de bibliotheek leeg is | n.v.t. | `administration` | `library.not_empty` 409 |
| `DELETE /libraries/{id}` | body `{confirm: "<title>"}` | n.v.t. | `administration` | `library.confirm_mismatch` 409 |
| `POST /libraries/{id}/scan` | 202 met `Scan` | n.v.t. | `administration` | `library.scan_in_progress` 409 (de dode code krijgt zijn zender) |
| `POST /libraries/{id}/adopt` | `config` naar `db`, zelfde id en slug | n.v.t. | `administration` | `library.not_config_managed` 409 |
| `GET /storage/roots` | `[{path, fs_type, inode_trusted, inode_trust_source, mounted, free_bytes, total_bytes, libraries[]}]` | n.v.t. | `administration` | |
| `POST /storage/roots/recheck` | 202 | n.v.t. | `administration` | |
| `GET /scans`, `GET /scans/{id}` | `ScanPage`, `Scan` met de tellers uit `scan_runs` plus `state` (`queued`, `running`, `done`, `failed`, `cancelled`, unknown-safe) en `current_path` (afgekort) | n.v.t. | `administration` | |
| `GET /jobs`, `POST /jobs/{id}/cancel`, `POST /jobs/{id}/retry` | `Job` met `kind`, `state`, `attempts`, `last_error` | n.v.t. | `administration` | `job.not_cancellable` 409 |

## J.4 Venster 3 (S3): boeken

Precies de vijf wijzigingen uit `docs/pleya-server-ps14-proposal.md` hoofdstuk 9, plus de
sterke validator op de bestandsroute:

| Wijziging | Nieuw | Compatibiliteit | Onderhandeling |
| --- | --- | --- | --- |
| `LibraryKind` | `books` | `x-unknown-safe: true`; pre-books clients verbergen de bibliotheek (bewezen: `browse.dart:36-51`, `pleya_server_browse_test.dart:44`; de fake-server en pleya_web moeten hetzelfde doen en krijgen een test) | `ebooks` |
| `capabilities.ebooks` | boolean | negeert | zelf |
| `GET /ebooks?library_id=&q=&subject=&author=&series=&state=&sort=&cursor=&limit=` | `PublicationPage`; `Publication{id, library_id, title, sort_title, authors[], series{name,index}?, language?, publisher?, published_on?, isbn?, description?, subjects[], page_count?, added_at, cover{artwork_id, width?, height?}?, file{size_bytes, sha256}, reading_state?}` | additieve resource | `ebooks` |
| `GET /ebooks/{id}` | `Publication` | | `ebooks` |
| `GET /ebooks/{id}/cover?width=` | bytes, ladder zoals artwork | | `ebooks` |
| `GET /ebooks/{id}/file` | `application/epub+zip`, sterke `ETag`, `Range`, `If-Range` met 206 | apart van `/stream` (DEC-050 raakt dit niet) | `ebooks` |
| `GET /ebooks/series?library_id=`, `GET /ebooks/authors?q=` | lijsten met tellingen | | `ebooks` |
| `Library.item_count` | betekenis gedocumenteerd: top-level entiteiten, voor boeken publicaties | regel 3 gehandhaafd (ps14 beslissing 3) | |
| foutcode `library.wrong_kind` | 400 op `/libraries/{id}/items` voor een boekenbibliotheek | patroon | |

## J.5 Venster 4 (S5, S6): filters en leesvoortgang

| Wijziging | Nieuw | Compatibiliteit | Onderhandeling | Fout |
| --- | --- | --- | --- | --- |
| queryparameters op `/libraries/{id}/items` | `genre`, `year`, `year_from`, `year_to`, `watched`, `resolution` (`sd`, `hd`, `fhd`, `uhd`, unknown-safe) | een oude server negeert ze stil; daarom stuurt een client ze pas bij `filters: true` (masterplan 8.5) | `filters` | `library.filter_invalid` 400 |
| `sort` | plus `last_played_at`, `duration` | oude server: `library.sort_invalid` (bestaand) | `filters` | |
| `GET /libraries/{id}/facets` | `{genres[{value,count}], years[...], resolutions[...], watched{watched,unwatched}}` | n.v.t. | `filters` | |
| `capabilities.filters`, `capabilities.artwork_sizes`, `capabilities.reading_state` | booleans | negeert | zelf | |
| `Item` | plus `summary?`, `genres[]?`, `content_rating?`, `people[]?` (`{name, role}`), `last_played{at, device_name}?` | negeert | geen (antwoordvelden) | |
| `GET /libraries/{id}/metadata-coverage` | `{items, with_sidecar, with_summary, with_genres, ratio}` | n.v.t. | `administration` | |
| `GET /artwork/cache`, `DELETE /artwork/cache` | grootte, aantal | n.v.t. | `administration` | |
| `POST /reading-state` | body gesloten `{publication_id, locator{cfi, spine_index, fraction}, progress, finished?, base_revision?}` | n.v.t. | `reading_state` | `reading.locator_invalid` 400 |
| `GET /reading-state?in_progress=&limit=&cursor=` | `ReadingStatePage` | n.v.t. | `reading_state` | |
| `Publication.reading_state` | `{progress, finished, revision, updated_at, locator}` | negeert | | |

## J.5a Venster 5 (S17, S18, S23): afspelen

`POST /playback/plan` (body gesloten: `version_id?`, `item_id`, `capabilities{...}` als de
PS-5-vorm), antwoord `PlaybackPlan{delivery_mode (direct, remux, transcode; unknown-safe),
version_id, stream_url, session_id?, reason{code, params}}`; `POST /playback/sessions/{id}/
heartbeat`, `DELETE`; `GET/DELETE /transcode-sessions` (admin); `POST /downloads`, `GET
/downloads`, `GET /downloads/{id}/file` met `Digest`, `DELETE`; capabilities `playback_plan`,
`transcode`, `downloads`; foutcodes `playback.transcode_busy`, `playback.transcode_failed`,
`playback.not_playable` (de dode code krijgt zijn zender).

## J.5b Venster 6 (S19, S20): persoonlijk

`/collections`, `/collections/{id}`, `/collections/{id}/items` (PUT met volledige lijst),
`/playlists` idem met `position`; `Collection{id, owner, title, visibility (private, everyone,
users; unknown-safe), item_count, artwork[]}`; `/history`, `/favorites/{item}`, `/ratings/{item}`,
`/track-preferences`; `Item.user_state` krijgt `favorite`, `rating`; capabilities `collections`,
`playlists`, `history`, `favorites`, `ratings`, `track_preferences`.

## J.5c Venster 7 (S21, S25): realtime en levenscyclus

`GET /events` als websocket (beschreven in de protocoldoc, niet in de YAML): eerste bericht
`{token}`, daarna `{seq, type, payload}`; `?since=`; capability `realtime`. `/backups`,
`/backups/{id}/restore` (body `{confirm}`), `/backups/{id}/verify`, `POST /server/maintenance-
mode`, `Server.upgrade{image, schema, backup_before_migrate}`; foutcodes `storage.full` (de dode
code), `server.database_unavailable`, `server.maintenance`.

## J.5d Venster 8 (S22): metadata

`Item` krijgt `people[]` uitgebreid, `ratings[]{source, value, scale}`, `studio`, `tagline`,
`external_ids{}`, `attribution[]`; `GET /libraries/{id}/matches`, `POST /items/{id}/match`
(body `{candidate_id}` of `{external_id}` of `{reject: true}`), `GET /items/{id}/artwork-
candidates`, `PUT /items/{id}/artwork` (`{candidate_id}`), `POST /libraries/{id}/refresh-
metadata` (bestond als stub in S4); settings `metadata_provider`, `provider_api_key` (schrijf-
alleen); capabilities `metadata_provider`, `ratings_external`.

## J.6 Schema

Postgres 18.6, voorwaartse migraties met checksum, één transactie per bestand. Geen bestaande
migratie wordt bewerkt. Voor elke migratie: reden, eigenaar, sleutels, indexen, cascade, backfill,
nullability, terugdraaien, en het pad voor een gevulde installatie (de NAS staat op schema 7).

### 0008 `server_settings`

`server_settings(key text PK, value jsonb NOT NULL, updated_at timestamptz NOT NULL, updated_by
uuid NULL REFERENCES users ON DELETE SET NULL)`. Geen backfill: een ontbrekende sleutel betekent
"neem de omgeving". Terugdraaien: tabel droppen, gedrag valt terug op `.env`. Gevulde installatie:
niets verandert tot een beheerder iets opslaat.

### 0008b tokens en audit (in hetzelfde bestand als 0008)

`sessions ADD kind text NOT NULL DEFAULT 'device' CHECK (kind IN ('device','api','legacy'))`,
`scope text NULL`, `token_hash bytea NULL UNIQUE`, `expires_at timestamptz NULL`; backfill:
bestaande rijen zonder `device_id` en met een legacy-naam worden `legacy`, de rest `device`.
`admin_audit(id uuid PK, at timestamptz, user_id uuid NULL REFERENCES users ON DELETE SET
NULL, session_id uuid NULL REFERENCES sessions ON DELETE SET NULL, source text CHECK IN
('http','mcp'), operation text, target text NULL, outcome text CHECK IN ('ok','denied',
'failed'), detail jsonb NULL)` met index op `(at DESC)`; `housekeeping` bewaart 90 dagen.
Terugdraaien: kolommen en tabel droppen; API-tokens verliezen dan hun geldigheid, wat de
bedoeling is.

### 0009 `libraries` beheerbaar

`ALTER TABLE libraries ADD managed text NOT NULL DEFAULT 'config' CHECK (managed IN
('config','db'))`, `scan_interval_seconds int NULL`, `scan_on_start bool NULL`,
`last_scan_run_id uuid NULL REFERENCES scan_runs ON DELETE SET NULL`. `jobs ADD
cancel_requested_at timestamptz NULL`; `scan_runs.state` CHECK uitgebreid met `cancelled`
(nieuwe CHECK, oude droppen). Backfill: alle bestaande rijen `config`; `last_scan_run_id` uit de
laatste `scan_runs` per bibliotheek. Terugdraaien: kolommen droppen; een `db`-bibliotheek
verdwijnt dan uit de configuratie bij herstart, dus de migratietest bewaakt dat 0009 zelf nooit
een bibliotheek verwijdert en dat een `.env`-opstelling na 0009 dezelfde ids houdt (PS-11A
criterium 2).

### 0010 boeken

`libraries.kind` CHECK opnieuw met `books`. `publications` en `publication_files` zoals H.2, met
`publications_library_added_idx (library_id, added_at DESC)`, `publications_grouping_uidx
(library_id, grouping_key)`, `publication_files_publication_idx`, `publication_files_inode_idx`
partieel, `publication_files_missing_idx` partieel. FK `library_id` RESTRICT (verwijderen van een
bibliotheek gaat via de servicelaag die eerst de publicaties verwijdert, zodat het aantal
geteld en gelogd wordt), `publication_id` CASCADE, `storage_location_id` RESTRICT. Geen backfill.
Terugdraaien: tabellen droppen en de CHECK terugzetten, alleen als er geen `books`-rij is; de
migratietest weigert anders.

### 0011 itemmetadata

`media_items ADD summary text NULL, genres text[] NOT NULL DEFAULT '{}', genres_key text[] NOT NULL DEFAULT '{}' (casefold, trim), content_rating text
NULL, people jsonb NULL, sidecar_seen_at timestamptz NULL`. Index `media_items_genres_gin` (GIN
op `genres`), `media_items_library_year_idx (library_id, year)`. Backfill: geen; de eerstvolgende
scan vult ze. Terugdraaien: kolommen droppen, geen dataverlies buiten de sidecarvelden.

### 0012 zoekindexen

`CREATE EXTENSION IF NOT EXISTS pg_trgm` (vereist dat de databaserol dat mag; op de NAS-image is
dat zo, en de migratie meldt een duidelijke fout als het niet mag), GIN-trigramindex op
`media_items.title` en `sort_title`, op `publications.title`, en op `unnest(authors)` via een
expressie-index of een hulpkolom `authors_text`. Terugdraaien: indexen droppen; de query blijft
correct, alleen trager.

### 0013 leesvoortgang

`reading_states` met `locator jsonb` in Readium-vorm (`href`, `type`, `locations{progression, totalProgression, position, partialCfi}`, `text?`) plus `publication_digest`, met `reading_states_user_updated_idx (user_id, updated_at DESC)
WHERE finished = false`. FK's: `user_id` CASCADE (gebruiker weg is voortgang weg, zoals
`watch_states`), `publication_id` CASCADE, `last_session_id` SET NULL. Terugdraaien: droppen.

### 0014 tot 0019 (uitgebreide scope)

`0014_transcode_sessions` (sessie, versie, gebruiker, sessie-id, hwaccel, laatste heartbeat,
map; index op heartbeat), `0015_collections_playlists` (`collections`, `collection_items`,
`collection_grants`, `playlists`, `playlist_items` met `position`; FK's cascade op eigenaar en
item), `0016_personal` (`play_history`, `favorites`, `ratings`, `track_preferences`; alle op
`user_id` cascade), `0017_metadata_candidates` (`metadata_candidates`, `metadata_corrections`,
`metadata_overrides` per veld met provenance, `artwork_candidates` met `pinned`, `external_ids`; `media_items` krijgt `studio`, `tagline`, `metadata_source`),
`0018_downloads`, `0019_backups`. Elke migratie: geen backfill behalve `play_history` uit bestaande
`watch_states` (één rij per item met `watched = true`, gemarkeerd `source = 'backfill'`),
terugdraaien door droppen, en de migratietest uit J.7 groen op de NAS-fixture.

## J.7 Migratietest

`internal/migrate/migrate_test.go` krijgt een test die de NAS-fixture (schema 7, geanonimiseerd,
461 films, 97 series, 3 gebruikers) laadt, 0008 tot 0013 toepast, en daarna asserteert: dezelfde
`libraries.id` en `slug`, `managed = 'config'`, alle `watch_states` intact, `item_count` gelijk,
`readyz` groen. Dezelfde test draait in CI op elke migratiecommit.
