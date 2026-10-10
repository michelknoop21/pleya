# Contractvenster 3: boeken, sidecars, artwork, filters en leesvoortgang (S3 tot en met S6)

**Status:** voorstel, niet geaccepteerd. Herzien op 10 oktober 2026 na een review (één kritieke en
elf belangrijke bevindingen, verwerkt in deze versie). `docs/pleya-protocol/v1/openapi.yaml`, de
schema's en de fixtures zijn niet aangeraakt; het venster staat dicht.
**Datum:** 10 oktober 2026
**Auteur:** Michel Knoop
**Betreft:** het gebundelde contractvenster voor S3 tot en met S6 waarop Michel op 10 oktober 2026
akkoord gaf, vastgelegd in DEC-149 punt 5 (PR #250, branch `docs/ps14-vrijgave-tellers`). Voorwaarden:
bestaande architectuur en Unified Library, aansluiting op de Flutter-clients en de webclient, geen
DRM, winkel of abonnement, en de bundeling mag geen nieuwe afhankelijkheid scheppen. S6 hangt aan
het locatorbesluit P5 ([docs/pleya-server-p5-locator-proposal.md](pleya-server-p5-locator-proposal.md))
**en** aan de vrijgave van PS-15 (DEC-149 punt 3); beide staan open.

## 0. Preflight (10 oktober 2026)

| Controle | Uitkomst |
| --- | --- |
| `git fetch github`, `git log github/main --oneline -8` | `main` op `7ebcdb80` bij de start, sindsdien #240 en #242 (Seerr, raken dit niet). Venster 2 is dicht met [DEC-146](DECISIONS.md). |
| Open PR's | #250 legt [DEC-149](DECISIONS.md) vast: PS-14 vrijgegeven, S3 vrij, S6 niet (wacht op P5 en de vrijgave van PS-15), en eerst het ontwerp van dit venster met een eigen DEC, pas daarna S3.1. #246 neemt DEC-147 en DEC-148. Het eerste vrije nummer is dus minstens DEC-150; de eigenaar controleert op de remote. #218 (draft) legt unified-first vast voor filters en vensters; hoofdstuk 4 sluit daarop aan. Geen PR raakt `openapi.yaml`. |
| `git worktree list` | Deze worktree (`docs/contract-venster-3`) en `pleya-docs-ps14` (de DEC-149-baan, eigenaar van masterlijst en DECISIONS). `pleya-web-s7` (S7.4) heeft een artworkladder in `pleya_web/src/lib/util/srcset.ts`, maar leest bewust geen capability: regel 12 zegt "Er wordt geen capability-veld gelezen dat het protocol niet kent", en `ARTWORK_SIZES_AVAILABLE` is een constante op `false`. Pakket C geeft die constante later een bron. |
| Bestaand ontwerp | Geen contractvoorstel voor venster 3 en geen P5-DEC. Wel: [docs/pleya-server-ps14-proposal.md](pleya-server-ps14-proposal.md) hoofdstuk 9 en de zeven bindende beslissingen, rebaseline J.4, J.5, J.6, H, E (RB-4, RB-5, RB-7, RB-12 bijgesteld), VRAGENLIJST 15, 26, 27, 29, en [DEC-128](DECISIONS.md), [DEC-129](DECISIONS.md), DEC-149. |
| Masterlijst S3.* tot S6.* | Alle 22 rijen `[ ]`. Tabel 2.3 noemt P5 als open besluit; 2.4 telt acht vensters. |

**Nummering.** De masterlijst is leidend: S4 is sidecars en artworkladder (PS-7N, PS-7A), S5 filters,
facetten en zoeken, S6 leesvoortgang.

## 1. Wat dit voorstel doet en wat het overneemt

Het beschrijft per slice de volledige contractwijziging, toetst elke wijziging aan de zes regels uit
[hoofdstuk 3 van de specificatie](pleya-protocol-v1.md#3-versionering-en-compatibiliteit), en deelt
het geheel op in pakketten die elk los landen. Het venster opent één keer, met één lijst.

Overgenomen zonder herafweging: de zeven bindende beslissingen uit het PS-14-voorstel, RB-4, RB-5,
RB-7 bijgesteld, RB-12 bijgesteld en de grenzen uit DEC-128 (`media_*` audiovisueel, geen platform-
of readerveld aan login of `sessions`).

Waar de bronnen elkaar tegenspreken gaat het bindende besluit voor:

| Tegenspraak | Bron A | Bron B | Hier |
| --- | --- | --- | --- |
| Filters op `/ebooks` in S3 | J.4: `q`, `subject`, `author`, `series`, `state` in S3 | PS-14 stopcriterium (geen zoeken, geen filter op auteur of onderwerp); masterlijst S5.4 | S3 levert `library_id`, `sort`, `cursor`, `limit`. Zoeken is D2, `state` is F. |
| `/ebooks/series`, `/ebooks/authors` | J.4: S3 | masterlijst S5.4 | D2 |
| `Publication.reading_state` | J.4: in S3 | DEC-128 punt 8 | F |
| Locatorvorm | J.5, RB-4, RB-12 tweede alinea: `{cfi, spine_index, fraction}` | RB-12 bijgesteld, H.2, J.6 0016, VRAGENLIJST 26 | Readium Locator volgens P5 |
| Artworkladder | RB-7 tweede alinea: één ladder | RB-7 bijgesteld, VRAGENLIJST 27 | twee ladders |
| Cachebeheer | J.5: `/artwork/cache` | botst met `/artwork/{artwork_id}` | `/server/artwork-cache` |
| Manifest en resources | H.1: `/ebooks/{id}/manifest` en `/ebooks/{id}/resources/{path}` | Readium lost relatieve `href`'s op tegen de map van het manifest | `/ebooks/{id}/publication/manifest.json` en `/ebooks/{id}/publication/{path}` (5.1) |

Twee bewuste afwijkingen van het PS-14-voorstel, met reden:

- **`capabilities.ebooks` volgt de software, niet de inhoud.** PS-14 hoofdstuk 10 beschrijft een
  server zonder boekenbibliotheek met de vlag op `false`. Dan kan een client nooit weten of
  `POST /libraries` met `kind: books` aankomt, en kan de eerste boekenbibliotheek alleen via
  `PLEYA_SERVER_LIBRARIES` ontstaan. Hier is de vlag waar zodra de server boeken kent. Of er een
  Boeken-bestemming verschijnt, beslist de client op "minstens één zichtbare `books`-bibliotheek"
  (DEC-102-policy op `feat/ebooks`), niet op de vlag.
- **`width` op de coverroute vanaf pakket A.** PS-14 hoofdstuk 8 zegt dat de coverroute de cover
  levert zoals hij is en dat de parameter bij PS-7A hoort. De parameter staat er hier vanaf A, met
  exact de belofte van `/artwork` (de dichtstbijzijnde beschikbare maat, zonder `width` het
  origineel). In A levert hij het origineel; PS-7A (S4.5) maakt de maten echt zonder
  contractwijziging. Zo hangt pakket C niet aan A en A niet aan C.

## 2. S3, boekencatalogus (PS-14)

### 2.1 Wijzigingen

| # | Wijziging | Vorm |
| --- | --- | --- |
| A1 | `LibraryKind` krijgt `books` | enum is al `x-unknown-safe: true`; geldt ook voor `kind` in `CreateLibraryRequest` en `UpdateLibraryRequest`. Een client stuurt `kind: books` pas wanneer `capabilities.ebooks` waar is. |
| A2 | `capabilities.ebooks` | `boolean`, default `false`, waar zodra de server `/ebooks` kent (zie hoofdstuk 1). |
| A3 | `GET /ebooks` | `library_id` (optioneel; zonder: alle zichtbare boekenbibliotheken), `sort` (gesloten aanvraagenum `title`, `-title`, `added_at`, `-added_at`, `author`, `-author`; default `title`), `limit`, `cursor`. Antwoord `PublicationPage`. |
| A4 | `GET /ebooks/{publication_id}` | `Publication` |
| A5 | `GET /ebooks/{publication_id}/cover` | `width` optioneel 1 tot 4096, belofte als `/artwork`; sterke `ETag` (digest plus coverpad; na S4.5 ook de trede, dus een andere `ETag` per maat); `404` `library.not_found` zonder cover. |
| A6 | `GET /ebooks/{publication_id}/file` | `application/epub+zip`, `Content-Disposition: attachment`, sterke `ETag: "<sha256>"`, `Range` en `If-Range` met `206`; `416` `playback.range_not_satisfiable`. |
| A7 | Beschrijving bij `Library.item_count` | "Het aantal top-level entiteiten dat de bibliotheek toont: films, series of publicaties." |
| A8 | `library.wrong_kind` (400) | op `/libraries/{id}/items` voor een boekenbibliotheek en op `/ebooks?library_id=` voor een andere soort; `details.kind`. Zichtbaarheid gaat voor: een bibliotheek die de aanroeper niet mag zien geeft eerst `404` `library.not_found`, zodat `400` nooit verraadt dat een onzichtbare bibliotheek bestaat of van welke soort hij is. |
| A9 | Schema's | `Publication`, `PublicationPage`, `PublicationCover`, `PublicationFile`, `PublicationSeries` (2.2) |
| A10 | Matrixregels 16.4 voor A3 tot A6 | klasse `authenticated`, autorisatie op de bibliotheek, `404` buiten zicht |

### 2.2 `Publication`

Verplicht: `id`, `library_id`, `title`, `authors` (geordend, `[]` zonder auteur), `subjects` (`[]`
zonder onderwerp), `added_at`, `file`. Optioneel: `sort_title`, `series` (`{name, index?}`),
`language` (BCP 47), `publisher`, `published` (`YYYY`, `YYYY-MM` of `YYYY-MM-DD`), `isbn`,
`description` (platte tekst, HTML eruit), `page_count` (alleen uit de OPF), `cover`
(`{media_type, width?, height?}`; afwezig is geen cover).

`file` is `{size_bytes, sha256, media_type}`. `sha256` is de digest van precies de bytes uit A6 en
gelijk aan de `ETag`. P5 gebruikt dezelfde waarde als publicatiedigest.

`PublicationPage` volgt `ItemPage`: `allOf` met `Page` en een verplichte lijst `items` van
`Publication`.

Niet in A: `reading_state` (F), bijdragers en onderwerpen als entiteit, downloadstatus (PS-16).

### 2.3 Volgorde: eerst de poortmeting, dan het venster

DEC-128 punt 7 hangt een poort vóór het protocolvenster voor PS-14, en DEC-149 punt 4 houdt die van
kracht. Dit voorstel kiest de nette volgorde: **de laag C-meting eerst, het venster daarna.** De
meting (uitgeleverde iOS-, tvOS- en desktopbuilds tegen de omkeerproxy uit PS-14 beslissing 5, op de
vier meetpunten uit PS-14 11.2, verslag in `docs/`) heeft nog geen masterlijstregel; hoofdstuk 10
stelt S3.0 voor.

Een tweede voorwaarde geldt voor A5 en A6: de DEC onder de sterke validator (PS-14 beslissing 2),
die DEC-050 expliciet adresseert. A6 is de route waar hij om gevraagd werd; A5 belooft ook een sterke
`ETag`, op bytes uit een bestand dat Pleya niet beheert, en valt dus onder hetzelfde besluit.

**Keuze voor Michel:** de pakketten B, C en D1 raken geen boeken. Ze mogen vóór de laag C-meting
landen als de venster-DEC dat met zoveel woorden als afwijking van DEC-128 punt 7 benoemt, met als
reden dat de poort over een nieuwe `LibraryKind` gaat en deze pakketten die niet aanraken. Zonder die
expliciete keuze opent het hele venster pas na de meting. G valt hier niet onder: G hoort bij S6 en
wacht op de vrijgave van PS-15.

## 3. S4, sidecars en artworkladder (PS-7N, PS-7A)

| # | Wijziging | Vorm |
| --- | --- | --- |
| B1 | `Item.summary` | optionele tekst |
| B2 | `Item.genres` | optionele lijst displaynamen; alleen gevuld als de bibliotheek door de 80%-poort is |
| B3 | `Item.content_rating` | optionele tekst (`PG-13`, `12`) |
| B4 | `Item.people` | optionele lijst `{name, role}`; `PersonRole` met `actor`, `director`, `writer`, `x-unknown-safe: true`; een client laat een persoon met een onbekende rol weg. Nieuwe rij in specificatie 3.2. |
| B5 | `GET /libraries/{id}/metadata-coverage` | klasse `admin`; `{items, with_sidecar, with_summary, with_genres, ratio, threshold, gate_met}` |
| B6 | Beschrijving van `capabilities.administration` | noemt het beheeroppervlak via hoofdstuk 16.4 (klasse `admin`) en niet langer als vaste lijst routes; de betekenis "deze server heeft een beheeroppervlak" blijft. B5 en C4 voegen allebei een beheerroute toe; het pakket dat het eerst landt (B of C) herschrijft de beschrijving, het tweede raakt hem niet meer aan. |
| C1 | `capabilities.artwork_sizes` | `boolean`, default `false`; belooft afgeleide maten op `/artwork/{id}` en niets over andere routes |
| C2 | Tekst bij `width` op `/artwork/{id}` | normaliseert naar een ladderwaarde voor de rol van de afbeelding: poster 240, 480, 960, 1920; backdrop 480, 960, 1920, 3840. Rondt naar boven af, schaalt nooit op boven de bron, boven de top de top; eigen sterke `ETag` per trede. Een boekcover is geen rol op `/artwork/{id}`: covers komen alleen uit A5, met de posterladder (S4.5). |
| C3 | Tekstcorrectie `/artwork` (S4.6) | de tekst volgt het werkelijke `Cache-Control: public, max-age=300, must-revalidate` (`internal/api/handlers_media.go`) |
| C4 | `GET`, `DELETE /server/artwork-cache` | klasse `admin`; `{bytes, files}` en `204` |

Boekcovers (S4.5) vragen geen contractwijziging: A5 heeft `width` al.

**Zichtbaar zonder clientrelease.** De Flutter-app stuurt al `?width=`
(`lib/services/pleya_server_client/parts/artwork.dart:31`) en krijgt na C een kleinere trede. Dat
valt binnen de bestaande belofte, maar het S4-plan meet welke breedtes de app per vlak vraagt.

## 4. S5, filters, facetten en zoeken

Afgestemd op het Unified Library-filtermodel (`lib/services/unified_catalog/unified_catalog_filters.dart`).
Dat model zet Pleya Server vandaag uit voor genre-, jaar- en kijkfilters (`_executesMetadataFilters`
en `_executesWatchFilter` noemen alleen Plex en Jellyfin). D1 is wat nodig is om Pleya Server mee
te laten doen.

| # | Wijziging | Vorm |
| --- | --- | --- |
| D1.1 | Filterparameters op `/libraries/{id}/items` | `genre` (herhaalbaar, OF, vergeleken op de casefold-sleutel), `year` (herhaalbaar), `year_from`, `year_to`, `watch` (zie 4.1), `content_rating` (herhaalbaar), `audio_language` (herhaalbaar, ISO 639-2/B, zie 4.2), `resolution` (herhaalbaar; `sd`, `hd`, `fhd`, `uhd`). Alles optioneel; zonder parameter het oude gedrag. |
| D1.2 | `sort` | plus `last_played_at`, `duration` en hun omgekeerde |
| D1.3 | `GET /libraries/{id}/facets` | `{genres[{value,count}], years[...], content_ratings[...], audio_languages[...], resolutions[...], watch{unwatched, in_progress, watched}}`; `resolutions[].value` met `x-unknown-safe: true` en een nieuwe rij in specificatie 3.2 (onbekende waarde: die facetwaarde niet tonen) |
| D1.4 | `library.filter_invalid` (400) | `details.parameter`, `details.value` |
| D1.5 | `capabilities.filters` | belooft D1.1 tot D1.4, niets op `/ebooks` |
| D1.6 | `/search` achter een trigramindex | geen contractwijziging; de ranking uit RB-5 komt er als beschrijving bij |
| D1.7 | Cursor | een cursor hoort bij precies één (sortering, filterset); een cursor uit een andere combinatie geeft `library.cursor_invalid`, zoals vandaag al per sortering |
| D1.8 | Taalcodes van audiostromen | geen contractwijziging maar een reparatie: de server levert voortaan wat `AudioStream.language` al belooft (`openapi.yaml:2499`, ISO 639-2/B). Zie 4.2. |
| D2.1 | Parameters op `GET /ebooks` | `q`, `author`, `subject`, `series`, optioneel |
| D2.2 | `GET /ebooks/authors`, `GET /ebooks/series` | `{name, count}`, gepagineerd |
| D2.3 | `capabilities.ebooks_search` | belooft D2.1 en D2.2 |

### 4.1 De betekenis van `watch`

Het Unified-model kent `unwatched`, `inProgress` en `watched`, en vertaalt `unwatched` naar Plex
`unwatched=1` en Jellyfin `IsUnplayed` (`lib/services/library_query_translator.dart:65` en `:243`).
Beide geven ook wat half bekeken is. Pleya Server volgt dat, zodat één filter op drie servers
hetzelfde betekent:

| Soort | `unwatched` | `in_progress` | `watched` |
| --- | --- | --- | --- |
| `movies` | geen `watch_states`-rij voor de aanroeper, of `watched = false`; dus inclusief half bekeken | `watched = false` en `position_ms > 0` | `watched = true` |
| `shows` (op serieniveau) | minstens één aflevering niet bekeken; een half bekeken serie valt eronder | minstens één aflevering bekeken of begonnen, en niet alle bekeken | `episode_count > 0` en alle afleveringen bekeken |
| `books` | n.v.t.: `/libraries/{id}/items` geeft `library.wrong_kind`. Leesstaat filtert via `state` op `/ebooks` (pakket F), met dezelfde overlap: `unread` is niet uitgelezen, dus inclusief begonnen. | | |

`in_progress` is dus een deelverzameling van `unwatched`. Dat is bewust en staat zo in de
specificatie, omdat de client dezelfde overlap van Plex en Jellyfin al kent. Een film of aflevering
zonder `watch_states`-rij is niet bekeken.

**Sorteren op `last_played_at`.** Voor een film is het de eigen waarde. Voor een serie is het het
maximum over haar afleveringen. Items zonder waarde staan achteraan, in beide richtingen. De waarde
is de serverontvangst van de laatste geaccepteerde kijkschrijving met voortgang (positie of
`watched`); een expliciete `mark_unwatched` of `restart` verzet hem niet.

### 4.2 `audio_language`

Opgenomen, met een reparatie die eraan voorafgaat. `media_streams.language` komt uit de ffprobe-tag
via `normalizeLanguage` (`internal/ffprobe/convert.go:300-315`). Die functie controleert alleen de
vorm: drie letters, en `und` en `zxx` worden leeg. Ze zet een terminologische code niet om naar de
bibliografische: een stroom met `nld` blijft `nld`, waar het contract `dut` belooft
(`AudioStream.language`, `openapi.yaml:2499`), en hetzelfde geldt voor `deu`/`ger` en `fra`/`fre`.
`nameparse.LanguageCode` (`internal/nameparse/sidecar.go:183`) doet die omzetting wel, maar alleen
voor sidecars. Zonder reparatie zou een facet `nld` en `dut` als twee talen tonen voor hetzelfde
Nederlands, en een filter op `dut` de helft missen.

De reparatie (D1.8): ffprobe laat de code door `nameparse.LanguageCode` lopen, en een eigen migratie
in dezelfde commit zet bestaande rijen in `media_streams` om met dezelfde tabel (S5-plan taak 2;
nooit een al gecommitte migratie bewerken). Dat is geen betekeniswijziging maar
het nakomen van een bestaande belofte; een client die `nld` toevallig kende ziet voortaan `dut`, en
de app werkt al met B-codes uit de sidecars.

**Wat de migratie niet kan herstellen.** `normalizeLanguage` liet een tweeletterige tag (`nl`, `en`)
vallen tot `NULL`; `LanguageCode` maakt er wel een B-code van. De migratie ziet alleen `NULL` en kan
de oorspronkelijke tag niet terugvinden, dus zo'n stroom krijgt pas een taal bij de volgende probe,
en de scanner probeert alleen een bestand dat veranderd is. Dat is een geaccepteerd gevolg en geen
re-probe-job: Matroska bewaart de taal als ISO 639-2 in drie letters, dus de tweeletterige tag is
de uitzondering, en een job die elke stroom opnieuw door ffprobe haalt is meer werk dan het gat.
S5-plan taak 2 telt op de NAS-fixture hoeveel audiostromen `NULL` hebben; is dat meer dan een
handvol, dan wordt een re-probe een eigen taak met een eigen regel.

Daarna is de data bruikbaar waar hij bestaat. Een stroom zonder tag matcht geen taal, zoals bij Plex
en Jellyfin, die ook op tags filteren. De alternatieve route, de clientvlag in S14 splitsen zodat
`filters` geen taalfilter belooft, maakt het Unified-model complexer voor één backend. Eén parameter
plus de reparatie is de kleinste wijziging die de Unified-belofte waar houdt.

### 4.3 Twee vlaggen

Een server negeert een onbekende queryparameter stil, dus elke filterparameter hangt achter een vlag.
Eén vlag voor items en boeken zou D1 aan S3 en D2 aan S4 koppelen; met twee vlaggen landt elk deel
zodra zijn data er is.

## 5. S6, leesvoortgang (PS-15 server)

S6 is niet vrijgegeven. DEC-149 punt 3: S6 hangt aan P5 **en** aan de vrijgave van PS-15. Dat geldt
voor alle drie de pakketten hieronder; E en F wachten daarbovenop op P5.

| # | Wijziging | Vorm |
| --- | --- | --- |
| E1 | `GET /ebooks/{id}/publication/manifest.json` | `application/webpub+json`; Readium Web Publication Manifest met `metadata`, `links` (een `self`-link `manifest.json`), `readingOrder`, `resources`, `toc`, en `pageList` als de EPUB een `page-list` heeft. `href`'s zijn relatieve zip-paden en lossen op tegen de map van het manifest. In de YAML de gegarandeerde leden, `additionalProperties: true`, verwijzing naar de Readium-specificatie. |
| E2 | `GET /ebooks/{id}/publication/{path}` | één bestand uit de zip; content-type uit het OPF-manifest; sterke `ETag` uit digest plus pad; paden buiten de zip `404`; securityheaders volgens de spike (5.2). `path` bevat slashes (`OEBPS/text/c1.xhtml`). OpenAPI 3 kent geen parameter over meerdere segmenten; de YAML declareert `path` als tekst met een beschrijving dat hij de rest van de URL is, plus de markering `x-pleya-rest-of-path: true`. `check_protocol.sh` interpreteert padsjablonen niet (het controleert het document, de verwijzingen, de enums en de fixtures), en `check_server_responses.py` slaat niet-JSON-lichamen over, dus geen van beide struikelt erover. In Go wordt het `{path...}` op de `ServeMux`. |
| E3 | Matrixregels voor E1, E2 | `authenticated`, autorisatie op de bibliotheek, of de vorm die de spike oplevert |
| E4 | `capabilities.ebooks_manifest` | belooft E1 en E2 |
| F1 | Schema's | zie 5.3 |
| F2 | `POST /reading-state` | body `ReadingStateWrite` (gesloten), antwoord `ReadingStateWriteResult` |
| F3 | `GET /reading-state?in_progress=&limit=&cursor=` | `ReadingStatePage`, alleen eigen staten op zichtbare publicaties, nieuwste eerst |
| F4 | `Publication.reading_state` | optioneel `ReadingState`, afwezig zonder staat |
| F5 | `state` op `GET /ebooks` | gesloten aanvraagenum `unread` (niet uitgelezen, inclusief begonnen), `in_progress`, `finished` |
| F6 | `reading.locator_invalid` (400) en het negende foutdomein `reading` | `details.field` is een JSON Pointer naar het afgekeurde veld in de aanvraag (`/locator/href`, `/locator/locations/totalProgression`, `/publication_digest`), en `details.reason` een korte code (`missing`, `out_of_range`, `not_relative`, `too_large`). Domein: 6.2. |
| F7 | `capabilities.reading_state` | belooft F2 tot F6 |
| G1 | `UserState.last_played` | optioneel `{at, device_name?}`; `at` is `watch_states.last_played_at` (definitie in 4.1), `device_name` die van de sessie die de laatste voortgang schreef. Een ingetrokken sessie (`sessions.revoked_at` gezet) levert geen `device_name`: `RevokeSession` doet een `UPDATE` en geen `DELETE`, dus de lezer filtert op `revoked_at IS NULL`; de naam blijft in de database staan. Vraagt een migratie (8.1). |

### 5.1 Manifest, base-URL en `ETag`

Readium lost een relatieve `href` op tegen de URL van het manifest. Met het manifest op
`/ebooks/{id}/manifest` en de bestanden op `/ebooks/{id}/resources/{path}` (H.1) zou
`OEBPS/c1.xhtml` naar `/ebooks/{id}/OEBPS/c1.xhtml` wijzen, waar niets staat. De uitweg is de
conventie van Readium zelf: manifest en bestanden in één map, `/ebooks/{id}/publication/`. De `href`
in het manifest, de `href` in een locator en het zip-pad zijn dan dezelfde tekst, zonder vertaling.
Een zip-entry die op de root `manifest.json` heet, is via E2 niet bereikbaar; de spine verwijst daar
in de praktijk niet naar, en de analyser logt het als het voorkomt.

`ETag`: het manifest krijgt een validator uit de bestandsdigest plus een versie van de
manifestgenerator, zodat een serverupgrade die het manifest anders opbouwt ook een nieuwe `ETag`
geeft. Een bestand krijgt digest plus pad. Komt er een token in het pad (5.2), dan is elke sessie
een andere URL en mist de browsercache tussen sessies; dat is de prijs van die variant.

### 5.2 Blokker: scripts en auth in de browserreader

Twee vragen moeten beantwoord zijn voordat de YAML van pakket E landt. Ze horen bij één spike:

1. **Auth.** `@readium/navigator` laadt XHTML in een iframe. Een iframe stuurt geen
   `Authorization`-header. Haalt de navigator alles zelf op en injecteert hij blobs, dan volstaat
   bearer. Gebruikt hij echte URL's, dan zijn er twee kandidaten: een token in het pad
   (`/ebooks/{id}/publication/{token}/...`, overleeft relatieve verwijzingen) of de
   streamsessiecookie uit DEC-051, uitgebreid naar deze routes.
2. **Scripts op de eigen origin.** E2 serveert XHTML uit een onbekend bestand vanaf dezelfde origin
   als de webapp en de API. Een script in een EPUB draait daar met toegang tot alles wat de webapp
   mag. Kandidaten: een CSP op E2 die scripts blokkeert (`script-src 'none'`, `sandbox`), wat
   botst als de navigator zelf scripts in het iframe zet; of een aparte origin voor publicatie-inhoud.
   De spike stelt vast welke combinatie de navigator laat werken zonder dat boekscripts draaien.

### 5.3 Pakket F op schemaniveau

- `ReadingLocator`, object, `additionalProperties: false`, verplicht `href`, `type`, `locations`;
  optioneel `title`. `href`: tekst, relatief zip-pad, de server normaliseert (een voorloopslash
  eraf, `.`-segmenten weg) en weigert `..` buiten de root, een schema, een backslash of NUL.
- `ReadingLocations`, object, verplicht `progression` en `totalProgression` (getal 0 tot en met 1),
  optioneel `position` (geheel getal ≥ 1) en `partialCfi` (tekst). Dit is het enige open object:
  `additionalProperties: true`, omdat de inhoud door Readium wordt bepaald en de server hem bewaart in
  plaats van interpreteert. Grens op het geheel: 4 KiB JSON.
- `ReadingStateWrite`, gesloten: verplicht `publication_id`, `locator`, `publication_digest`
  (64 hex-tekens); optioneel `finished` (boolean), `base_revision` (geheel getal ≥ 0).
- `ReadingState`, verplicht `publication_id`, `locator`, `publication_digest`, `progress` (0 tot en
  met 1, afgeleid uit `totalProgression`), `finished`, `revision` (≥ 1), `updated_at`; optioneel
  `device_name`.
- `ReadingStateWriteResult`, verplicht `applied` (boolean), optioneel `state` (`ReadingState`, de
  actuele staat na de aanvraag). `state` ontbreekt alleen als er na de aanvraag geen staat is: een
  eerste schrijving die niet werd toegepast, bijvoorbeeld door een afwijkende digest. `applied` staat
  hier en niet op `ReadingState`, zodat dezelfde vorm in `GET`, in de pagina en op `Publication` geen
  veld draagt dat alleen bij een schrijving betekenis heeft.
- `ReadingStatePage`: `allOf` met `Page` en een verplichte lijst `items` van `ReadingState`.

De regels voor toepassen en weigeren, inclusief de eerste schrijving, staan in het P5-voorstel.

## 6. De zes regels getoetst

### 6.1 Per wijziging

Regels: 1 nieuw optioneel antwoordveld, 2 niets hernoemd of weg, 3 betekenis ongewijzigd, 4 geen
nieuw verplicht aanvraagveld, 5 aanvraagbody gesloten en nieuw bodyveld pas na een capability, 6 enum
alleen uitgebreid waar unknown-safe.

| # | 1 | 2 | 3 | 4 | 5 | 6 | Oordeel |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A1 `books` | n.v.t. | ja | ja | n.v.t. | in `CreateLibraryRequest` accepteert de server meer; de client stuurt de waarde pas bij `ebooks` | `x-unknown-safe: true` | toegestaan, na de poortmeting |
| A2 vlag | ja | ja | ja | n.v.t. | n.v.t. | geen enum | toegestaan |
| A3 tot A6 | nieuwe resource | ja | ja | geen bestaande aanvraag | alleen `GET` | `sort` gesloten aanvraagenum | toegestaan |
| A7 `item_count` | n.v.t. | ja | berekening anders voor een soort die geen oude client ziet, betekenis gelijk | n.v.t. | n.v.t. | geen enum | toegestaan |
| A8 `wrong_kind` | n.v.t. | ja | vervangt stil gedrag | n.v.t. | n.v.t. | patroon | toegestaan |
| B1 tot B3 | ja | ja | ja | n.v.t. | n.v.t. | geen enum | toegestaan |
| B4 `people` | ja | ja | ja | n.v.t. | n.v.t. | `PersonRole` unknown-safe | toegestaan |
| B5 coverage | nieuw endpoint | ja | ja | n.v.t. | `GET` | geen enum | toegestaan |
| B6 tekst `administration` | n.v.t. | ja | het oppervlak groeit, de betekenis blijft | n.v.t. | n.v.t. | n.v.t. | toegestaan |
| C1 vlag | ja | ja | ja | n.v.t. | n.v.t. | geen enum | toegestaan |
| C2 ladder | n.v.t. | ja | binnen "dichtstbijzijnde beschikbare maat" | `width` optioneel | n.v.t. | geen enum | toegestaan |
| C3 tekst | n.v.t. | ja | tekst volgt bestaand gedrag | n.v.t. | n.v.t. | n.v.t. | toegestaan |
| C4 cache | nieuwe endpoints | ja | ja | n.v.t. | `DELETE` zonder body | geen enum | toegestaan |
| D1.1, D1.2, D1.7 | n.v.t. | ja | ja; de cursorregel bestond al per sortering | optioneel | achter `filters` | gesloten aanvraagenums | toegestaan |
| D1.3 facetten | nieuw endpoint | ja | ja | n.v.t. | n.v.t. | `resolutions[].value` unknown-safe | toegestaan |
| D1.4 fout | n.v.t. | ja | ja | n.v.t. | n.v.t. | patroon | toegestaan |
| D1.8 taalcodes | n.v.t. | ja | de betekenis blijft ISO 639-2/B en wordt voor het eerst nagekomen; de waargenomen waarde verandert wel (`nld` wordt `dut`), zie 6.3 | n.v.t. | n.v.t. | geen enum | toegestaan, gevolg geaccepteerd tenzij Michel anders besluit (hoofdstuk 9, punt 10) |
| D2 | n.v.t. | ja | ja | optioneel | achter `ebooks_search` | geen enum | toegestaan |
| E1, E2, E4 | nieuwe resources | ja | ja | n.v.t. | `GET` | geen enum | toegestaan, na P5, PS-15 en de spike |
| F2 | nieuw endpoint | ja | ja | nieuwe body | gesloten; pas bij `reading_state` | geen enum | toegestaan, na P5 en PS-15 |
| F3, F4 | ja | ja | ja | n.v.t. | n.v.t. | geen enum | idem |
| F5 `state` | n.v.t. | ja | ja | optioneel | achter `reading_state` | gesloten aanvraagenum | idem |
| F6 domein | n.v.t. | ja | verruimt het patroon (6.2) | n.v.t. | n.v.t. | patroon | idem |
| G1 | ja | ja | ja | n.v.t. | n.v.t. | geen enum | toegestaan, na PS-15 |
| afgewezen: `ItemKind: book` | | | | | | zou mogen | afgewezen (PS-14 wijziging A, RB-5) |

### 6.2 Het negende foutdomein

Kijkstatus is hier wel een precedent, en het wijst naar een eigen domein. De fouten rond kijken
zitten in `session.` (`session.invalid` voor een onbekende kijksessie), en specificatie 7.1 reserveert
dat domein voor de kijksessie en de browser-streamsessie. Leesvoortgang heeft geen sessie in die zin,
dus `session.` past niet, en `library.` is de catalogus en geen gebruikersstaat. `reading` is daarom
het veilige domein.

Het bewijs dat een nieuw domein niets breekt is hetzelfde als bij `server`, `settings` en `job`:
`PleyaError.domain` in Dart is de helft vóór de punt en alleen `pleya_server_auth_service.dart` takt
op `auth.`; `describeError` in `pleya_web/src/lib/api/errors.ts` geeft een generieke melding. Het
domein wordt van kracht in de commit die `reading.locator_invalid` stuurt; in diezelfde commit
schuiven het patroon, de handgeschreven lijst in `check_error_domains`
(`scripts/check_protocol.py:271`) en de docstring van `PleyaError.domain` naar negen (DEC-138-regel).

### 6.3 Wat bestaande clients merken en wat er per pakket mee moet

| Client of bestand | Zonder update | Mee per pakket of in S14 |
| --- | --- | --- |
| Flutter-app, uitgeleverde builds | een `books`-bibliotheek wordt weggefilterd vóór de mapper (te bewijzen met laag C); artwork wordt kleiner na C; na D1.8 komt bij Nederlands, Duits en Frans `dut`, `ger`, `fre` binnen waar het `nld`, `deu`, `fra` was. Dat verandert niets zichtbaars: de taaltabel van de app mapt beide vormen op dezelfde taal (`lib/data/iso_639_data.dart:314` `'nld': 'nl'` en `:401` `'dut': 'nl'`, idem voor de andere paren). Verder niets | S14: `PleyaLibraryKind.books`; vlaggen `ebooks`, `filters`, `ebooksSearch`, `ebooksManifest`, `readingState`, `artworkSizes`; `unifiedFilterCapabilitiesFor` zet Pleya Server aan bij `filters`; de Unified-catalogus sluit boekenbibliotheken uit; de sleutel van `PleyaServerCursorLedger` (`browse.dart:94`, nu scope plus sortering) krijgt de filterset erbij, anders hergebruikt hij een cursor uit een andere filtercombinatie; `PleyaServerBooksSource` (H.4) |
| `test/pleya_server/pleya_wire_contract_test.dart` | faalt bij elke nieuwe fixture | per pakket: het aantal fixtures (nu 78) bijwerken en elk nieuw schema een parser geven of in `deferredSchemas` zetten met de fase die het leest |
| `pleya_web/src/lib/api/schema.d.ts` | n.v.t. | per pakket opnieuw genereren in de contract- en handlercommit |
| Pleya Web | lockstep met de binary, dus geen oude webclient. Na D1.8 toont het itemdetail bij een audiospoor `dut` waar het `nld` toonde: `routes/items/[id]/+page.svelte:162` zet de ruwe code in de streamregel. Een zichtbare, cosmetische verandering zonder vertaling ervoor | A: een boekenbibliotheek krijgt een eigen afhandeling in de bibliothekenlijst en op `/libraries/[id]` (S3-plan taak 6); boekschermen S9, reader S12 |
| `pleya_verify/fixture_server` | n.v.t. | per pakket de nieuwe fixtures |

## 7. Fixtures per pakket

| Pakket | Nieuwe fixtures |
| --- | --- |
| A | `info_ebooks.json`, `libraries_with_books.json`, `publication.json`, `publication_minimal.json`, `publication_page.json`, `error_library_wrong_kind.json` |
| B | `item_movie_with_metadata.json`, `metadata_coverage.json` |
| C | `info_artwork_sizes.json`, `artwork_cache.json` |
| D1 | `library_facets.json`, `error_library_filter_invalid.json`, `info_filters.json` |
| D2 | `ebook_authors.json`, `ebook_series.json` |
| E | `publication_manifest.json`, `info_ebooks_manifest.json` |
| F | `reading_state_write.json`, `reading_state_write_result.json`, `reading_state_write_not_applied.json`, `reading_state_page.json`, `publication_with_reading_state.json`, `error_reading_locator_invalid.json` |
| G | `item_movie_last_played.json` |

## 8. Vrijgeefbare pakketten

Elk pakket is een eigen YAML-wijziging met eigen fixtures, `schema.d.ts`, matrixregels en
Dart-contracttest, en sluit met `scripts/check_protocol.sh` en `pleya_server/scripts/verify-protocol.sh`
groen. De YAML van een onderdeel landt in dezelfde commit als de handler die het antwoord levert:
`check_server_responses.py` eist dat elk antwoordschema in het contract door een echte serverrespons
gedekt wordt, dus een commit met alleen contract maakt `verify-protocol.sh` rood. Zo ging S2 ook.
Elk pakket is additief en zit achter een eigen capability of is een optioneel antwoordveld.

| Pakket | Slice | Inhoud | Hangt af van | Waarom het los groen landt |
| --- | --- | --- | --- | --- |
| **A** | S3 | A1 tot A10 | venster-DEC na de laag C-meting; validator-DEC voor A5 en A6 | nieuwe resource achter `ebooks`; `books` alleen zichtbaar voor clients die de soort kennen |
| **B** | S4.1 tot S4.3 | B1 tot B6 | venster-DEC | optionele velden, beheerendpoint achter `administration` |
| **C** | S4.4 tot S4.6 | C1 tot C4 | venster-DEC | vlag belooft alleen `/artwork` |
| **D1** | S5.1 tot S5.3, S5.5 | D1.1 tot D1.7 | B (graaf: S5 op S4) | achter `filters` |
| **D2** | S5.4 | D2.1 tot D2.3 | A (graaf: S5 op S3) | achter `ebooks_search` |
| **E** | S6.1 | E1 tot E4 | A, P5, vrijgave PS-15, spike 5.2 | achter `ebooks_manifest`; los van F |
| **F** | S6.1 tot S6.3, S6.5 | F1 tot F7 | A, P5, vrijgave PS-15 | achter `reading_state`; domein `reading` pas in de handlercommit |
| **G** | S6.4 | G1 | vrijgave PS-15 | één optioneel antwoordveld |

**Wat op P5 wacht:** E en F. **Wat op de vrijgave van PS-15 wacht:** E, F en G. F hangt niet aan E:
de server valideert de vorm van een locator en niet of zijn `href` in de spine staat.

### 8.1 Migraties

Een migratie krijgt het eerstvolgende vrije nummer bij het committen. J.6 reserveerde 0013 tot en
met 0016 op volgorde S3, S4, S5, S6, maar die volgorde ligt niet vast.

| Pakket | Migratie | Gepland in J.6 |
| --- | --- | --- |
| A | `books` in de CHECK, `publications`, `publication_files` | 0013 |
| B | kolommen op `media_items` | 0014 |
| D1, taak 1 | `pg_trgm`, trigramindexen op `media_items`; `ALTER TABLE watch_states ADD COLUMN IF NOT EXISTS last_played_at timestamptz NULL` | 0015 |
| D1, taak 2 | omzetting van T- naar B-taalcodes in `media_streams` (4.2), een eigen migratie in de commit van de ffprobe-reparatie | niet gepland |
| D2 | trigramindex op `publications.title` en op de auteurs (J.6 0015 noemde ze; ze landen pas met D2, omdat de tabel pas met A bestaat) | niet gepland |
| F | `reading_states` | 0016 |
| G | `watch_states.last_session_id uuid NULL REFERENCES sessions ON DELETE SET NULL`, en dezelfde `ADD COLUMN IF NOT EXISTS last_played_at` | niet gepland |

`last_played_at` is nodig voor de sortering in D1 én voor G. Beide migraties schrijven
`ADD COLUMN IF NOT EXISTS`, dus de landingsvolgorde is vrij en geen van beide migraties hoeft achteraf
bewerkt te worden (de les van `0006` en `0007`, X3 in de masterlijst). De vuldefinitie hoort bij D1,
dat in de praktijk eerst landt; G leest hem. Geen backfill: `last_played_at` blijft leeg tot de eerste
voortgangsschrijving, en een sortering zet lege waarden achteraan. `ON DELETE SET NULL` op
`last_session_id` dekt het echt verwijderen van een sessie; intrekken is een `UPDATE` en wordt bij het
lezen gefilterd (G1).

### 8.2 Schept de bundeling een nieuwe afhankelijkheid?

| Mogelijke koppeling | Uitkomst |
| --- | --- |
| Eén vlag voor alle filters | geschrapt: `filters` en `ebooks_search` |
| `artwork_sizes` die ook covers belooft | geschrapt; A5 heeft `width` vanaf A |
| `reading_state`, `state`, `q` in A | geschrapt: naar F en D2 |
| Foutdomein `reading` bij het openen gereserveerd | geschrapt: in de handlercommit |
| Eén regeneratie van fixtures, `schema.d.ts` en Dart-contracttest aan het eind | geschrapt: per pakket |
| Migratienummers als reservering | geschrapt (8.1) |
| `last_played_at` voor D1 en G | gedeelde kolom met `ADD COLUMN IF NOT EXISTS` in beide (8.1) |
| Het venster sluit pas als alles er is | vastgelegd met reden (8.3) |

De afhankelijkheden die blijven komen uit de graaf en de vrijgavebesluiten, niet uit de bundeling:
D1 op B, en D2, E, F en S4.5 op A (S4.5 zonder contractwijziging, zie 3). E, F en G hangen
daarnaast aan de vrijgave van PS-15, E en F ook aan P5.

### 8.3 Wanneer het venster sluit

Het venster sluit zodra het laatste pakket geland is, of eerder met een besluit dat de niet-gelande
pakketten bij naam naar een volgend venster verplaatst, waar ze opnieuw getoetst worden. E, F en G
kunnen lang wachten op P5 en PS-15; deze regel voorkomt dat het venster daardoor openstaat tot het
einde van het traject (DEC-135, afgewezen alternatief).

## 9. Besluiten die bij Michel liggen

1. **PS-15 vrijgeven voor het leesvoortgangsdeel?** Zonder dat besluit landen E, F en G niet, ook
   niet als P5 genomen is.
2. P5 zelf.
3. Mogen B, C en D1 vóór de laag C-meting landen, als expliciete afwijking van DEC-128 punt 7 (2.3)?
4. Afwijkingen van J.5: `watch` met drie waarden en de betekenis uit 4.1, herhaalbare `year`,
   `content_rating` en `audio_language` erbij, cache op `/server/artwork-cache`.
5. Twee filtervlaggen in plaats van één.
6. Het negende foutdomein `reading`.
7. De afwijkingen van het PS-14-voorstel: `ebooks` volgt de software, `width` op de cover vanaf A.
8. De sluitregel uit 8.3.
9. Een masterlijstregel S3.0 voor de laag C-meting (hoofdstuk 10).
10. **Geaccepteerd gevolg, tenzij Michel anders besluit:** na D1.8 levert de server bij Nederlandse,
    Duitse en Franse audio `dut`, `ger` en `fre` in plaats van `nld`, `deu` en `fra`. De app ziet
    dezelfde taal, Pleya Web toont de nieuwe code als tekst, en een tweeletterige tag die vroeger
    wegviel krijgt pas bij een volgende probe een taal (4.2).

## 10. Voorgestelde wijzigingen aan masterlijst, gates en DECISIONS

Voor de eigenaar van die bestanden; hier niet doorgevoerd.

```text
docs/PLEYA-SERVER-MASTERLIST.md

S3, nieuwe eerste rij:
| S3.0 | Poortmeting laag C (DEC-128 punt 7): omkeerproxy en meting op iOS, tvOS en één desktopbuild, verslag in docs/ | `[ ]` | | |

S3.6 wordt:  Capability `ebooks`, pakket A van venster 3 geland
S5.2 krijgt erbij: plus de reparatie van audiotaalcodes naar ISO 639-2/B (D1.8, een eigen migratie)
S5.4 krijgt erbij: met een eigen migratie voor de trigramindexen op publicaties
S5.5 wordt:  Injectietest en meting op de NAS, capabilities `filters` en `ebooks_search`, pakketten D1 en D2 van venster 3
S6.4 krijgt erbij: pakket G van venster 3, migratie op `watch_states`
S6.5 wordt:  Capability `reading_state`, pakketten E en F van venster 3

Blokkentabel, rij 2 (regel 85 op de DEC-149-branch): 22 taken wordt 23 (S3.0 erbij);
  "poort P5 vóór S6" wordt "P5 én de vrijgave van PS-15 vóór S6".
Kopteller (regel 46): 154 taken wordt 155, open 129 wordt 130.
Regel 111: "S6 aan S3 en aan P5" wordt "S6 aan S3, aan P5 én aan de vrijgave van PS-15".
Regel 221: "S6 blijft wachten op P5" wordt "S6 blijft wachten op P5 én de vrijgave van PS-15".
Tabel 2.3, rij P5: "Blokkeert" krijgt erbij: samen met de vrijgave van PS-15 (DEC-149 punt 3).
Tabel 2.3, nieuwe rij: Vrijgave van PS-15 (leesvoortgangsdeel) | S6 | open, eigen besluit van Michel.
Regel 133 en 134: "acht protocolvensters" wordt "zeven protocolvensters", twee keer; venster 3
  bundelt de vroegere vensters 3 en 4.
Rij P6 (regel 488): "Protocolvensters 1 tot 8" wordt "Protocolvensters 1 tot 7", "twee van acht"
  wordt "twee van zeven".

docs/pleya-server-gates.md: een regel voor venster 3 naast die van venster 1 en 2.

docs/DECISIONS.md: de DEC uit hoofdstuk 11, de validator-DEC (PS-14 beslissing 2) en de P5-DEC.
```

## 11. Voorgestelde DEC-tekst

Het nummer bepaalt de eigenaar van DECISIONS bij het committen. DEC-149 is uitgegeven (PR #250).

> ## DEC-NNN: het protocolvenster gaat open voor S3 tot en met S6, gebundeld en per pakket te landen
>
> **Date:** 2026-10-NN
> **Status:** voorgesteld
>
> **Context:** Venster 2 is dicht (DEC-146). DEC-149 gaf PS-14 vrij en vroeg eerst het ontwerp van
> één gebundeld venster voor S3 tot en met S6, met onderdelen die onafhankelijk landen; S6 hangt aan
> P5 en aan de vrijgave van PS-15. De wijzigingen staan uitputtend in
> `docs/pleya-server-contract-window-3.md`, met per wijziging de toets aan de zes regels uit hoofdstuk
> 3 van de specificatie. De poortmeting uit DEC-128 punt 7, die DEC-149 punt 4 van kracht hield, is uitgevoerd en vastgelegd in
> `docs/pleya-server-ps14-gate-c.md`. Bundelen maakt van de vensters 3 en 4 uit J.1 één venster.
>
> **De toetsing.** Alle wijzigingen zijn nieuwe resources, optionele antwoordvelden of optionele
> aanvraagparameters achter een nieuwe capability (regel 1, 4 en 5). Niets wordt hernoemd of
> verwijderd (regel 2). `item_count` krijgt voor `books` een andere berekening onder dezelfde
> betekenis, en `library.wrong_kind` vervangt stil gedrag (regel 3). Enums worden alleen uitgebreid
> waar ze unknown-safe zijn: `LibraryKind` krijgt `books`, en `PersonRole` en de resolutiefacet zijn
> nieuw met `x-unknown-safe: true` (regel 6). Het venster voegt één foutdomein toe, `reading`, van
> kracht in de commit die `reading.locator_invalid` stuurt. Eén wijziging verandert waargenomen
> waarden zonder de betekenis te veranderen: audiotaalcodes worden ISO 639-2/B, zoals
> `AudioStream.language` al beloofde, dus `nld` wordt `dut` (regel 3 nagekomen in plaats van
> geschonden). De app mapt beide vormen op dezelfde taal; Pleya Web toont de ruwe code en is lockstep.
> Dit gevolg is geaccepteerd.
>
> **Decision:** Het venster gaat open voor precies de wijzigingen uit hoofdstuk 2 tot en met 5 van dat
> document, in de pakketten A, B, C, D1, D2, E, F en G. Elk pakket landt als eigen wijziging met eigen
> fixtures, `schema.d.ts`, Dart-contracttest en matrixregels, samen met de handler die de nieuwe
> antwoorden levert, en alleen als `scripts/check_protocol.sh` en `verify-protocol.sh` daarna groen
> zijn. A5 en A6 landen pas na de DEC onder de sterke validator. E, F en
> G landen pas na de vrijgave van PS-15; E en F bovendien pas na P5, en E pas na de spike die auth en
> scriptgedrag in de browserreader vaststelt. Het venster sluit wanneer het laatste pakket geland is,
> of eerder met een besluit dat de niet-gelande pakketten bij naam naar een volgend venster
> verplaatst, waar ze opnieuw getoetst worden. Wijzigingen buiten de lijst vallen buiten dit venster.
> `feature_level` blijft 1.
>
> *Alleen als Michel daarvoor kiest, in plaats van de zin over de poortmeting in de context:* De
> pakketten B, C en D1 mogen landen vóór de poortmeting uit DEC-128 punt 7, die DEC-149 punt 4 van
> kracht hield. Dat is een bewuste afwijking van die twee punten, met als reden dat de poort gaat over hoe uitgeleverde clients een nieuwe
> `LibraryKind` behandelen en deze drie pakketten geen bibliotheeksoort, geen boekresource en geen
> boekveld raken. A en D2 landen pas na de meting.
>
> **Consequences:** `docs/pleya-server-gates.md` krijgt een regel voor dit venster. De masterlijst
> krijgt S3.0 en telt zeven vensters. Migraties krijgen hun nummer bij het committen. RB-4, de tweede
> alinea van RB-12 en J.5 noemen nog `{cfi, spine_index, fraction}`; die tekst is achterhaald door P5.
>
> Afgewezen: vier losse vensters, omdat S4, S5 en S6 dezelfde schema's raken (`Item`, `Publication`).
> Afgewezen ook: één vlag voor alle filters, omdat die de boekfilters aan S4 en de mediafilters aan S3
> zou koppelen.
