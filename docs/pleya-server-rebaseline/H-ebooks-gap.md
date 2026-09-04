# H. E-books end-to-end gap analysis

Van bestand tot Verder lezen, in de volgorde waarin een boek door het systeem reist. Per stap:
wat er is, wat er komt, welke slice, en wat de Flutter-clients nodig hebben. De ontwerpbron is
`docs/pleya-server-ps14-proposal.md` met de zeven bindende beslissingen; waar dit deel daarvan
afwijkt staat dat erbij.

**Bijgesteld op 4 september 2026** met VRAGENLIJST 15 en 26: de locator is geen CFI plus
spine-index meer maar een Readium-compatible Locator, en de Go-kant levert de publicatie
daarnaast als Readium Web Publication Manifest met zijn resources. De webreader is de Readium
TypeScript Toolkit met de chromeless `@readium/navigator`-laag; epub.js is hooguit een
gedocumenteerde contingency na een spike met een aantoonbare blocker, geen runtimefallback.

## H.1 De keten

| Stap | Vandaag | Wordt | Slice |
| --- | --- | --- | --- |
| Boekbestand op een mount | de scanner ziet `.epub` niet (`Classify` kent alleen video, ondertitel, beeld) | de walk krijgt de toegestane soorten van de bibliotheek; in een `books`-bibliotheek gaat `.epub` naar de derde emmer, in een filmbibliotheek blijft hij liggen | S3 |
| Scanner | drie lagen, één wandeling | ongewijzigd voor lagen 1 en 2; laag 3 is per soort: EPUB-analyser opent de zip, volgt `META-INF/container.xml` naar de OPF, leest titel, auteurs (`dc:creator` met rol), taal, uitgever, datum, ISBN, beschrijving, onderwerpen, reeks (`calibre:series`, `belongs-to-collection`), coververwijzing; berekent SHA-256 over het bestand voor de sterke validator | S3 |
| Catalogus | `media_*` | `publications` en `publication_files`, gekoppeld aan `libraries` en `storage_locations`; `item_count` telt publicaties | S3 |
| Metadata | n.v.t. | uit de OPF; geen provider, geen `.nfo` (sidecars zijn audiovisueel) | S3 |
| Cover | n.v.t. | `GET /ebooks/{id}/cover?width=` uit het zip, op de artworkladder, gecachet | S3, S4 |
| Bibliotheek | `kind IN ('movies','shows')` | `books`; zichtbaar via het bestaande rechtenmodel | S2, S3 |
| API | niets | `GET /ebooks`, `GET /ebooks/{id}`, `GET /ebooks/{id}/cover`, `GET /ebooks/{id}/file`, `GET /ebooks/series`, `GET /ebooks/authors`; capability `ebooks` | S3 |
| Manifest en resources | niets | `GET /ebooks/{id}/manifest` (Readium Web Publication Manifest uit de OPF: metadata, `readingOrder`, `resources`, `toc`) en `GET /ebooks/{id}/resources/{path}` dat één bestand uit het zip levert met padnormalisatie tegen traversal en het juiste content-type; dit is wat `@readium/navigator` leest | S6 |
| Zoeken | `/search` audiovisueel | `GET /ebooks?q=` op titel, auteur, reeks met `pg_trgm`; `GET /ebooks/authors?q=` | S3, S5 |
| Web Home en Boeken | niets | slot, landing, rijen, alle boeken, filters | S9 |
| Detail | niets | boekdetail met reeks en auteur | S9 |
| Openen, downloaden, lezen | niets | downloaden in S9 (bestand met `Content-Disposition`); lezen in de browser in S12 op `@readium/navigator` tegen het manifest, met de Pleya-schil eromheen (mockup 51) | S9, S12 |
| Leesvoortgang | niets | `reading_states`, `POST` en `GET /reading-state`, `reading_state` op `Publication` | S6 |
| Verder lezen | niets | `GET /reading-state?in_progress=true` gejoind door de client | S6, S9 |
| Autorisatie | `MayAccess` en `VisibleLibraries` | dezelfde functies op `library_id` van de publicatie; 404 voor alles buiten zicht | S3 |

## H.2 Datamodel

`publications`: `id` uuid, `library_id` FK restrict, `title`, `sort_title`, `authors text[]`
(geordend), `series_name`, `series_index numeric`, `language`, `publisher`, `published_on`
date, `isbn`, `description`, `subjects text[]`, `page_count` int (alleen als de OPF het
draagt), `added_at`, `updated_at`, `generation`, `missing_since`. Uniek op (`library_id`,
`grouping_key`) waarbij `grouping_key` = ISBN als die er is, anders genormaliseerde titel plus
eerste auteur (dezelfde discipline als `media_items`).

`publication_files`: `id`, `publication_id` FK cascade, `storage_location_id` FK restrict,
`path`, `size_bytes`, `mtime_unix`, `inode`, `scan_signature`, `content_sha256` (de sterke
validator, verplicht), `cover_href`, `cover_media_type`, `first_seen_at`, `last_seen_at`,
`missing_since`, `generation`. Eén bestand per publicatie in dit traject; de tabel laat er meer
toe zonder dat een scherm het toont.

`reading_states`: (`user_id`, `publication_id`) PK, `locator jsonb`, `progress numeric(6,5)`,
`finished bool`, `revision bigint`, `updated_at`, `last_session_id` (FK op `sessions`, set
null), plus `publication_revision` of `content_sha256` van het bestand waarop de locator werd
gemaakt. Geen lease (RB-4).

De locator is Readium-compatible en niet CFI-plus-spine (RB-12 bijgesteld):

```json
{
  "href": "OEBPS/chap12.xhtml",
  "type": "application/xhtml+xml",
  "locations": {
    "progression": 0.42,
    "totalProgression": 0.48,
    "position": 214,
    "partialCfi": "/4/2[c12]/10/1:0"
  },
  "text": { "highlight": "Hij liep de trap af" }
}
```

`locations.partialCfi` en `text` zijn optioneel; `text` bestaat voor bladwijzers en markeringen,
niet voor voortgang. De spine-index is afgeleide informatie en nooit de primaire identiteit. De
server valideert de vorm en bewaart de rest ongewijzigd, zodat een engine-upgrade geen migratie
vraagt. Wijkt `publication_revision` af van de huidige publicatie, dan past de client de locator
niet blind toe: hij valt terug op `totalProgression` en meldt dat het bestand is vervangen.

Bijdragers en onderwerpen blijven arrays tot een scherm ze als eigen entiteit toont (ps14
hoofdstuk 6). De auteurssectie in zoeken werkt op `unnest(authors)` met een index; dat is
genoeg voor één huishouden.

## H.3 De bytes

`GET /ebooks/{id}/file`: `Content-Type: application/epub+zip`, `Content-Disposition:
attachment; filename*=`, sterke `ETag: "<sha256>"`, `Accept-Ranges: bytes`, `Range` en
`If-Range` volgens RFC 9110 met 206 toegestaan omdat de validator sterk is (ps14 beslissing 2;
de DEC eronder adresseert DEC-050 expliciet). Klasse `authenticated`, autorisatie op de
bibliotheek. Geen streamtoken, geen streamsessie: een boek van enkele megabytes past in één
geauthenticeerde fetch met een bearer, en de webclient maakt er een blob-URL van (het
artworkpatroon uit `Artwork.svelte`).

Cover: uit het zip gelezen via `cover_href`; ontbreekt die, dan de eerste afbeelding met
`properties="cover-image"`, anders `404` en de client tekent de CSS-fallback met titel en auteur.

## H.4 Wat er met `feat/ebooks` gebeurt

| Onderdeel op `feat/ebooks` | Besluit | Waarom |
| --- | --- | --- |
| `lib/books/book.dart` (plain model, `BookArtwork` met vormen) | **aanpassen**: wordt `@freezed` met `fromJson` zodra `PleyaServerBooksSource` bestaat; `BookArtwork` blijft als fallback-tekening wanneer de cover niet laadt | de notitie in het bestand zegt dit zelf |
| `lib/books/books_source.dart` (`BooksSource`, `EmptyBooksSource`, `DemoBooksSource` achter `PLEYA_BOOKS`) | **behouden** als seam; **toevoegen** `PleyaServerBooksSource` die `GET /ebooks` en `/reading-state` spreekt; `DemoBooksSource` blijft voor goldens en Verify | precies de seam die DEC-093 vroeg |
| `lib/books/book_filter.dart`, `book_search.dart` (client-side filteren en zoeken) | **vervangen** door serverparameters (`subject`, `author`, `state`, `q`) zodra de bron Pleya Server is; blijven werken op de demo-bron | client-side zoeken over een gecursorde lijst is het foute antwoord (matrix h7) |
| `providers/books_home_provider.dart`, `books_library_provider.dart` | **aanpassen**: `available` volgt `capabilities.ebooks` en minstens één zichtbare `books`-bibliotheek; rijen uit de server | DEC-093 punt over `BooksLibraryProvider.available` |
| Schermen 01b tot 05 (Home, Alle boeken, Filters, Zoeken, Detail) | **behouden**; ze zijn tegen goedgekeurde goldens gebouwd | de webset volgt hun inhoud |
| `PrimaryMobileDestinationPolicy` en `navigation_tab_id.dart` | **behouden**; het mergeconflict met `feat/netflix-mobile` is hun zaak, niet die van dit traject | DEC-094 |
| Reader, inhoudsopgave, readerinstellingen, zoeken in boek, downloads (panelen 6 tot 12 van de comp) | **niet in dit traject** aan de app-kant; de server levert wat ze nodig hebben (bestand, manifest, `reading_state` met de Readium Locator) | PS-15 app-kant blijft op `feat/ebooks` |
| Het locatormodel van de app-reader | **bindend vastgelegd** door RB-12 bijgesteld: dezelfde Readium Locator als web, met de publicatie-revisie ernaast; een app-reader die alleen een spine-index of een paginanummer kan produceren voldoet niet | besluit vóór S6, geldt voor beide readers |
| Verify-scenario's (5) | **behouden**; erbij komt één scenario dat `PleyaServerBooksSource` tegen de fake-server drijft | RB-14 |

Er ontstaat geen tweede boekenarchitectuur: de app heeft één `BooksSource`, de server één
`publications`-domein, en het protocol één `/ebooks`-resource. Wat op `feat/ebooks`
"tijdelijke providerlogica" was (client-side filter en zoek) verdwijnt op het moment dat de
serverbron landt, en niet eerder, zodat de goldens intussen groen blijven.

## H.5 Wat de Flutter-clients nodig hebben

1. `PleyaCapabilities.ebooks` en `.readingState` in `pleya_wire.dart` (S14).
2. Een `ReadingLocator`-type dat de Readium-vorm draagt (`href`, `type`, `locations`, optioneel
   `text`) plus de publicatie-revisie, gedeeld met de app-reader op `feat/ebooks`.
3. `PleyaLibraryKind.books` en de mapping naar een `MediaKind` die `libraries_provider` niet
   wegfiltert op tvOS, macOS en desktop maar wél verbergt als bestemming (client-gedrag uit
   DEC-093 4.5; de bibliotheek mag in Mijn Pleya ▸ Bibliotheken zichtbaar zijn met een telling).
4. `PleyaServerBooksSource` in `lib/services/pleya_server_client/parts/ebooks.dart` met
   mappers naar `Book`.
5. De `_postJson`-fout uit backlog 24.3 (fouten stil op `null`) moet dicht vóór `POST
   /reading-state`, anders verdwijnt een leespositie even stil als een kijkpositie.

## H.5a Boeken in de uitgebreide scope

Boeken doen mee in verzamelingen (een verzameling mag publicaties bevatten), in geschiedenis
(uit `reading_states`), in favorieten en waarderingen, en in realtime (leesvoortgang van een
ander toestel). Metadata-providers voor boeken blijven buiten scope (DEC-093 sluit een
boekenprovider uit tot een eigen besluit); de OPF blijft de bron.

## H.6 Definition of Done voor de boekenketen

Een EPUB in `/volume1/media/Boeken` staat na één scan in `publications` met titel, auteur en
cover; `GET /libraries` telt hem mee; `GET /ebooks?q=` vindt hem op titel en auteur; de webclient
toont hem op Home (Nieuw in Boeken), op de Boeken-landing en in Alle boeken; het detail toont
cover, reeks en feiten; Downloaden levert het bestand met een sterke `ETag` en een hervatbare
`Range`; `GET /ebooks/{id}/manifest` levert een Readium Web Publication Manifest dat
`@readium/navigator` zonder aanpassing opent en `resources/{path}` weigert elk pad buiten het
zip; `POST /reading-state` vanaf een tweede client zet hem in Verder lezen met de juiste fractie
en de locator opent op dezelfde plek; een gebruiker zonder recht op de bibliotheek krijgt op elk
van deze endpoints 404; en
`scripts/check_protocol.sh` is groen met het venster dicht.
