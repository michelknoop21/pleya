# F. Backend gap analysis

Gemeten in `pleya_server/` op `5eebb83`: 100 Go-bestanden (~22k regels, de helft tests), module
`github.com/edde746/plezy/pleya_server`, Go 1.26, alleen `pgx/v5` en `x/crypto` als
dependencies. Router is `http.ServeMux` met methodepatronen (`internal/api/server.go:92-165`),
twee middlewarelagen: logging plus per route `authenticated` of `streamAuthorized`.

## F.1 Per domein: bestaat, ontbreekt, verandert

### Auth en autorisatie

| Bestaat | Bestand |
| --- | --- |
| setup, login, refresh met rotatie en respijtvenster, drie tokensoorten, sleutel op schijf | `handlers_auth.go`, `auth/token.go`, `auth/key.go`, `auth/store.go:300-458` |
| vier rollen, precies één owner via partiële index, rechtenladder view < download < manage, trigger tegen `manage` voor `restricted` | `0007_users_sessions.sql`, `catalog/permissions.go` |
| sessies per toestel, intrekking in DB en in-process register, gecontroleerd per 64 KiB tijdens een stream | `auth/sessions.go`, `auth/revocation.go`, `handlers_stream.go:245-287` |
| elke weigering 404, rol per request uit DB | `authorize.go:24-53`, `handlers_users.go:41-48` |
| rate limiter op setup en login | `limiter.go` |

| Ontbreekt of verandert | Slice |
| --- | --- |
| `administration`-capability en een tabelgedreven test die elke beheerroute met `member` en `restricted` op 404 zet (uitbreiding van `authorize_test.go`) | S1 |
| rate limit op `/auth/refresh` | S15 |
| panic-recovery met protocolvormige 500, lichaamslimiet op elke schrijvende route (nu alleen `decodeBody` 8 KiB in auth) | S1 |
| eigen account-id opvraagbaar (`GET /users/me` of `self: true` op `User`) | S1, deel J |
| foutcode voor "restricted mag geen manage" (`auth.permission_not_allowed`) | S1, deel J |
| `server_name` op `SetupRequest` | S1 |

### Libraries en storage

| Bestaat | Bestand |
| --- | --- |
| `libraries` (movies, shows), `storage_locations` met `fs_type`, `inode_trusted`, bron | `0002_catalog.sql:13-40` |
| sync uit `PLEYA_SERVER_LIBRARIES` op slug, ids overleven herstart en verhuizing | `cmd/pleya-server/bootstrap.go:55+` |
| mounts meten, `statfs` | `internal/mounts/`, `statfs_linux.go` |
| `GET /libraries`, `GET /libraries/{id}/items` gefilterd op `VisibleLibraries` | `handlers_library.go:13-111` |

| Ontbreekt of verandert | Slice |
| --- | --- |
| `kind` krijgt `books`; `managed`, `scan_interval_seconds`, `scan_on_start`, `last_scan_*` op `libraries` | S2, S3 |
| `POST /libraries`, `PATCH`, `DELETE` (met `confirm`), `POST .../scan`, `POST .../adopt`, `POST .../refresh-metadata` | S2, S4 |
| `GET /storage/roots` uit de mounts (nooit uit invoer), `POST /storage/roots/recheck` | S2 |
| `syncLibraries` wordt bron-bij-eerste-start; een `db`-bibliotheek negeert de `.env`-regel en logt dat | S2 |
| soortwisseling geweigerd bij inhoud (atomair, alle catalogustabellen) | S3 |
| `Library` op de lijn: `item_count` gedocumenteerd voor boeken, plus `managed`, `roots[]`, `last_scan` | S2, S3 |

### Catalogus

| Bestaat | Bestand |
| --- | --- |
| `media_items` (movie, show, season, episode, hiërarchie via CHECK), `media_versions`, `media_files` (rol media, subtitle, artwork), `media_streams` met kleurmetadata | `0002_catalog.sql:44-247`, `catalog/types.go` |
| wire-mapper gescheiden van domeintypes | `api/wire.go:264-330` |
| hydratie van `user_state` in één query | `handlers_library.go:245-279` |

| Ontbreekt of verandert | Slice |
| --- | --- |
| `publications`, `publication_files` (boeken, eigen domein, `media_*` blijft audiovisueel) | S3 |
| `summary`, `genres[]`, `content_rating`, `cast[]`, `directors[]`, `sidecar_seen_at` op `media_items` en per aflevering | S4 |
| `Item` op de lijn: `summary`, `genres`, `content_rating`, `people` optioneel | S4 |
| `content_fingerprint` blijft dood; geen relocatie tussen mounts in dit traject (gate uit h24 blijft open) | geen |

### Scanner

| Bestaat | Bestand |
| --- | --- |
| walk, classificatie op extensie, drie lagen (stat, signatuur over kop en staart, ffprobe), inode of signatuur voor hernoemen, veilige deletie bij lege of onvolledige root | `scanner/scanner.go:233-428`, `signature.go`, `walk.go` |
| `jobs` met dedupe en claim, `scan_runs` met tellers elke 5 s | `0003_work.sql`, `jobs/`, `scanner/progress.go` |
| start en interval | `scanwork.go:78-95` |

| Ontbreekt of verandert | Slice |
| --- | --- |
| walk krijgt de toegestane soorten van de bibliotheek mee; derde emmer voor publicatiebestanden; analyse per soort (ffprobe alleen movies en shows, EPUB-analyser voor books) | S3 |
| `.nfo`-sidecars lezen (film: `<plot>`, `<genre>`, `<mpaa>`; aflevering: idem; serie: `tvshow.nfo`), dekkingsmeting per bibliotheek | S4 |
| jobs annuleren (`cancel_requested_at`, coöperatief in de walk), retry vanuit beheer, begrensde backoff op `probe_attempts` (nu geschreven, nooit gelezen: `store_write.go:178`) en gelijk gedrag voor een mislukte `attach` (`scanner.go:558`) | S2 |
| `GET /scans`, `GET /scans/{id}`, `GET /jobs`, `POST /jobs/{id}/cancel`, `POST /jobs/{id}/retry` | S2 |

### Zoeken

Bestaat: `GET /search` met ILIKE en escaping (`store_read.go:66-72`), geen index die de ILIKE
helpt, standaard zonder seizoenen (DEC-045), geen scores, geen soortveld.

| Ontbreekt of verandert | Slice |
| --- | --- |
| `pg_trgm` GIN-index op `title` en `sort_title`; meting vooraf op de NAS-bibliotheek | S5 |
| filters op `/libraries/{id}/items` (`genre`, `year`, `year_from`, `year_to`, `watched`, `resolution`), `GET /libraries/{id}/facets`, extra sorteringen `last_played_at`, `duration` | S5 |
| `GET /ebooks?q=&library_id=&subject=&author=&state=&sort=` als eigen zoekweg voor boeken; `GET /ebooks/authors?q=` | S3, S5 |
| capability `filters` | S5 |

### Artwork

Bestaat: `GET /artwork/{id}` van de mount, `ETag` op `id:generation`, 304, `max-age=300`;
`width` wordt niet gelezen; geen cache; `CacheDir` alleen aangemaakt.

| Ontbreekt of verandert | Slice |
| --- | --- |
| ladder 240/480/960/1920, schalen (Go-stdlib `image` plus `golang.org/x/image/draw`, geen cgo), cache in `CacheDir/artwork/<id>/<w>.<ext>`, single-flight, sterke `ETag` op de cache, terugval op origineel bij decodeerfout, `Vary` niet nodig (query in de URL) | S4 |
| `GET /ebooks/{id}/cover?width=` op dezelfde ladder, uit het zip | S3, S4 |
| YAML-tekst over Cache-Control rechtzetten (deel A.4) | S4 |
| `GET /artwork/cache` en `DELETE /artwork/cache` voor beheer | S4 |
| capability `artwork_sizes` | S4 |

### Streaming

Bestaat: direct play met range in drie regels, `If-Range` altijd 200 (DEC-050), zwakke `ETag`,
bearer, streamtoken en streamsessie met cookie per sessie (DEC-051), maximaal 8, opnieuw
geautoriseerd per aanvraag; geen transcode (eerlijk `false`).

| Ontbreekt of verandert | Slice |
| --- | --- |
| opruimjob voor verlopen `stream_sessions` in `housekeeping` | S15 |
| `GET /stream-sessions` (klasse `admin`) voor "nu aan het kijken", afgeleid van actieve sessies plus laatste `watch_states`-event per sessie | S1 |
| `GET /ebooks/{id}/file` met sterke validator (SHA-256 over het bestand, berekend bij analyse), `Range` en `If-Range` mét 206 toegestaan; `Content-Disposition` | S3 |

### Watch-state en voortgang

Bestaat: `watch_states` met revisie, eigenaar en lease, `POST` en `GET /watch-state`, hubs
`continue_watching` en `next_up` (`store_hubs.go:75-197`), hydratie.

| Ontbreekt of verandert | Slice |
| --- | --- |
| `reading_states` met locator, fractie, revisie, zonder lease; `POST /reading-state`, `GET /reading-state`, `reading_state` op `Publication` | S6 |
| toestelnaam bij "laatst gekeken" (join `watch_states.owner_session_id` op `sessions.device_name`, alleen voor de eigen gebruiker) | S6 |
| capability `reading_state` | S6 |

### Capabilities

Alle dertien vlaggen kloppen met het gedrag (`handlers_auth.go:50-85`). Erbij komen
`administration`, `ebooks`, `filters`, `reading_state`, `artwork_sizes`, elk aan een concrete
voorwaarde gehangen. `feature_level` blijft 1.

### Webbundel en serverinfo

Bestaat: embed, releasebuild faalt zonder bundel, routeprecedentie getest, securityheaders op de
bundel. `GET /server` draagt id, naam, versie, `started_at`.

| Ontbreekt of verandert | Slice |
| --- | --- |
| `GET /server` uitgebreid (klasse `admin` voor de extra velden): `public_url`, `listen`, `behind_proxy`, `trusted_proxies`, `build`, `database` (versie, schema), `ffprobe` (gevonden, versie), `health` | S1 |
| `GET /server/environment` (geredigeerd, alleen `PLEYA_SERVER_*` en een gemaskeerde DSN), `GET /server/log?level=&limit=` uit een ringbuffer van 500 regels met de redactieregels van `logging`, `POST /server/connectivity-check`, `POST /server/rotate-signing-key` | S1 |
| securityheaders ook op `/pleya/v1` (`X-Content-Type-Options`, `Referrer-Policy`) | S1 |

### Settings

Bestaat: niets in de database; alles uit `config/config.go`.

| Ontbreekt of verandert | Slice |
| --- | --- |
| `server_settings` (sleutel, jsonb-waarde, bijgewerkt door wie en wanneer), `GET /settings`, `PATCH /settings` met validatie en grenzen per sleutel, `.env` als standaard en de databasewaarde wint; herladen zonder herstart voor TTL's en scaninstellingen (de auth-laag leest TTL's per aanroep uit een `atomic.Value`) | S1 |

### Jobs en status

Bestaat: `jobs` en `scan_runs` in de database, `housekeeping` voor refreshtokens, jobs en het
register.

Ontbreekt: alles over HTTP (S2), annuleren (S2), de drie dode foutcodes `CodeNotPlayable`,
`CodeStorageFull`, `CodeScanInProgress` krijgen een verzender of gaan weg (S2).

### Database

Bestaat: 7 migraties, checksums, advisory lock, per test een vers schema
(`testsupport.go:28-74`). Erbij: migraties 0008 tot 0013 (deel J).

### Tests en CI

Bestaat: 237 testfuncties, 6 pakketten tegen echte Postgres, `verify-local.sh` met 72 controles,
`verify-protocol.sh`, `check_protocol.sh` met 36 fixtures. Ontbreekt: CI (S0), een test per
nieuwe route met `member` en `restricted` (S1 en verder), een migratietest per nieuwe migratie
op een gevulde database (S0-fixture: een `pg_dump` van de NAS-stand, schema 7, geanonimiseerd).

### Uitgebreide scope (4 september, avond)

| Domein | Bestaat | Komt | Slice |
| --- | --- | --- | --- |
| PlaybackPlan | `DeviceCapabilities` alleen in de client | `internal/playback/` planner (pure functie, tabelgedreven), `POST /playback/plan` | S17 |
| Transcode | niets; `TranscodeDir` ongebruikt | `internal/transcode/` sessies, ffmpeg-supervisie, fMP4 en HLS, hwaccel-detectie, `GET/DELETE /transcode-sessions`, opruimen | S18 |
| Verzamelingen, afspeellijsten | niets | `collections`, `playlists` met items; CRUD; zichtbaarheid | S19 |
| Persoonlijke laag | niets (`play_history` bewust uitgesloten in 0004) | `play_history`, `favorites`, `ratings`, `track_preferences`; endpoints; "Bekeken door" | S20 |
| Realtime | niets | `internal/events/` hub met volgnummers, `GET /events` websocket, filter per zicht | S21 |
| Metadata-providers | niets | `internal/metadata/` providerabstractie, TMDB, kandidatenlaag, match, artwork ophalen naar `CacheDir`, correcties; jobs | S22 |
| Downloads | niets | `downloads` tabel, `POST /downloads`, bestand met digest, opruimen | S23 |
| Remote hardening | proxy-headers deels, geen metrics | vertrouwde proxy's, metrics op loopback, publieke-endpointtest | S24 |
| Back-up en levenscyclus | niets | `internal/backup/`, `BackupDir`, hersteltest, restore, onderhoudsmodus, upgrade-guard | S25 |

## F.2 Bestanden die dit traject aanraakt

| Nieuw | Doel |
| --- | --- |
| `internal/api/handlers_settings.go`, `handlers_admin_libraries.go`, `handlers_storage.go`, `handlers_jobs.go`, `handlers_ebooks.go`, `handlers_reading.go`, `handlers_server_admin.go` | beheer-, boeken- en voortgangsroutes |
| `internal/settings/` | `server_settings`, validatie, hot reload |
| `internal/ebooks/` | EPUB-analyser (zip, `container.xml`, OPF, cover), publicatiestore |
| `internal/artwork/` | ladder, schalen, cache, single-flight |
| `internal/sidecar/` | `.nfo`-parser en dekkingsmeting |
| `internal/logging/ring.go` | ringbuffer voor `/server/log` |
| `internal/migrate/sql/0008_*.sql` tot `0013_*.sql` | deel J |

| Gewijzigd | Doel |
| --- | --- |
| `internal/api/server.go` | routes, klasse `admin`, recovery, lichaamslimiet, headers |
| `internal/api/wire.go`, `errors.go` | nieuwe wire-types en foutcodes |
| `internal/api/handlers_auth.go` | capabilities, `server_name` bij setup |
| `internal/catalog/store_read.go`, `cursor.go`, `permissions.go` | filters, facetten, sorteringen |
| `internal/scanner/scanner.go`, `walk.go`, `nameparse/` | soorten per bibliotheek, derde emmer, dispatch, annuleren, backoff |
| `internal/jobs/jobs.go` | annuleren en retry |
| `internal/config/libraries.go`, `cmd/pleya-server/bootstrap.go`, `scanwork.go` | `managed`, overname, instellingen uit DB |
| `internal/auth/store.go` | TTL's uit settings |
| `pleya_server/scripts/verify-local.sh` | secties voor beheer, boeken, artwork |
| `docs/pleya-protocol/v1/openapi.yaml`, `examples/` | vier vensters (deel J) |
