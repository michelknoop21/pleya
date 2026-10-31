# S4/S14/S22: metadata, identiteit en artwork afronden

Status: voorstel, nog geen protocolvrijgave. Onderdeel van pakket 3 van het
geautoriseerde gezamenlijke uitvoeringsplan. Bestaande metadata-implementaties,
Unified Library en webnorthstar blijven eigenaar. Geen boekenveld of nieuw
contentdomein; de laag-C-poort voor een nieuwe LibraryKind blijft afzonderlijk.

## Bestaande basis en ontbrekende verbinding

`Item` draagt beschrijving, genres, content-rating en castnamen. De server bewaart
al providerkandidaten, `metadata_sources` en provider-artwork; match kiezen en
afwijzen zijn bestaande beheerroutes. Er zijn nog geen publieke externe IDs of
persoon-IDs. De Flutter-methodes voor identiteit, persoonsmedia en verwante hubs
zijn leeg. De northstar verlangt bovendien per-field overrides met provenance en
gepind artwork; die staan nog open onder S22.5. C4 uit het bestaande
`pleya-server-contract-window-3.md` is het uitgestelde cachebeheer.

## Afgebakende contractrijen

Alle nieuwe capabilities zijn optioneel en default false. Antwoordvelden zijn
optioneel; afwezig betekent onbekend, geen verzonnen waarde.

| Rij | Aanvulling | Betekenis |
| --- | --- | --- |
| M1 | `capabilities.external_identity`, `Item.external_ids` | Exacte IMDb-/TMDB-/TVDB-identiteit van dit item; IMDb `tt` plus cijfers, TMDB/TVDB positieve gehele getallen. Geen naam of pad als bewijs |
| M2 | `GET /items/lookup` | Geauthenticeerde `ItemPage`, bestaande cursor/limit. Verplicht audiovisueel `kind` en minstens één van `imdb`, `tmdb`, `tvdb`. Zoekt uitsluitend exacte provider-IDs binnen leesbare bibliotheken. Geen titelzoekfallback; ambigue/conflicterende kandidaten blijven expliciet meerdere kandidaten |
| M3 | `capabilities.people`, optioneel `Person.id`, `GET /people/{person_id}/items` | Bestaande `ItemPage`. Een blijvend lokaal UUID voor een bewezen providerpersoon; een naam zonder externe persoonsidentiteit krijgt geen gedeeld persoons-ID. Route toont alleen leesbare titels |
| M4 | `capabilities.related`, `GET /items/{item_id}/related` | Bestaande `ItemPage`, cursor/limit. Verwantschap uit bekende genres/personen, brontitel uitgesloten, geen geheime bibliotheken. De adapter maakt hier de bestaande verwante hub van |
| M5 | `Item.community_rating` | Optioneel getal 0–10 van de metadatabron, met bronvermelding. Het bestaande persoonlijke `rating` behoudt zijn betekenis; geen vermenging met gebruikerswaardering |
| M6 | `Item.metadata_sources` | Optionele bron per bestaand beschrijvend veld en artworkrol: `kind` (manual/sidecar/provider/file, unknown-safe) en optionele providernaam. Geen credentials, vrije HTML of NAS-paden |
| M7 | `GET /items/{item_id}/artwork-candidates` en `PUT /items/{item_id}/artwork` | Bestaande northstar-routes, klasse admin. Kandidaten met stabiel artwork-ID, rol, bron en optionele taal; kiezen pint poster/backdrop op een kandidaat die daadwerkelijk bij het item hoort. Geen vrije URL. Null wist een pin en herstelt de bron daaronder |
| M8 | `PUT /items/{item_id}/overrides`, `DELETE /items/{item_id}/overrides/{field}` | Klasse admin volgens het bestaande metadata-beheer. Gesloten, gedeeltelijke veldmap voor title/year/summary/genres/content_rating/people; type- en omvangsgrenzen. Een expliciet leeg optioneel veld blijft een handmatige override; verwijderen van de override herstelt de actuele onderliggende bron. Titel blijft niet-leeg |
| M9 | `capabilities.metadata_overrides` | Belooft M6–M8. Actuele rol/scope vóór iedere request; de Flutter-app krijgt hiermee geen nieuwe metadata-schrijfbevoegdheid |
| M10 | Optionele `poster_generation`/`backdrop_generation` in artworkrefs, `capabilities.artwork_versions` | Cacheversie voor de bestaande artwork-URL. Een optionele `v`-query breekt uitsluitend de clientcache; de bestaande ETag en Cache-Control blijven leidend. Oude refs/URLs blijven geldig |
| M11 | `capabilities.artwork_cache`, `GET`, `DELETE /server/artwork-cache` | C4 uit het eerdere voorstel: klasse admin, `{bytes, files}` en 204. Alleen afgeleide bestanden opruimen, nooit bronmedia/sidecars of gepinde bronafbeeldingen. Web vraagt bevestiging en gebruikt bestaande audit |
| M12 | `library.metadata_invalid` | 400 voor ongeldige gesloten override/artwork-selectie; past binnen het bestaande foutdomein. Onbekend of verboden item/persoon blijft 404 |

M1–M4, M10 en M11 worden afzonderlijk geadverteerd zodat een oudere of gedeeltelijke
server geen onafgewerkte clientactie zichtbaar maakt. M5/M6 tonen uitsluitend werkelijk
meegeleverde waarden; een ontbrekende waardering blijft onbekend. M11 hoort bij het bestaande
beheeroppervlak, niet bij een Flutter-cachebeheerscherm. Cijfers, bronnen en
attributie worden in de bestaande app-/webdetailvlakken gelezen. Providerattributie
gebruikt de officiële bronvermelding/logo waar vereist; geen vrije links uit
onvertrouwde metadata worden als vertrouwde provider behandeld.

## Uitvoering binnen bestaande architectuur

Externe IDs en persoonkoppelingen worden duurzaam opgeslagen; geen hash van een
naam als identiteit. Episode-/serie-identiteit blijft het bestaande gedeelde
identitymodel volgen. Lookupkandidaten bereiken de bestaande resolver met hun
werkelijke provider-IDs; conflicten mogen nooit als zekere deduplicatie worden
gepresenteerd.

Handmatige waarden en artworkpins krijgen een eigen duurzame laag. Provider- en
sidecarrondes blijven hun onderliggende waarden verversen, waarna de bestaande
voorrang uit DEC-153 wordt toegepast. Daardoor betekent reset werkelijk terug
naar de actuele bron, en blijven correcties over drie providerrondes en een scan
staan. De bestaande genredekkingspoort blijft gelden. Metadata kiezen/afwijzen
blijft op de reeds bestaande routes; geen tweede match-API.

Webbeheer volgt scherm 36. Flutter krijgt de leesvertaling in wire → mapper →
adapter → bestaande shared consumer. Plex/Jellyfin/Emby/local/Share en hun
huidige authoritygrenzen blijven behouden. De latere canonical-collection-write
uit pakket 6 vraagt zijn eigen protocolvenster.

## Compatibiliteit en acceptatie

1. Nieuwe antwoordvelden zijn optioneel; oude clients blijven onbekende velden negeren.
2. Geen bestaande route of veld wordt verwijderd/hernoemd.
3. Geen bestaande betekenis verandert: persoonlijke rating, Item-kind, genrepoort en artworkvalidator blijven gelijk.
4. Nieuwe requests staan achter hun eigen capabilities; zonder die vlag geen nieuwe route/query.
5. Nieuwe schrijfobjecten zijn gesloten en begrensd; bestaande bodies veranderen niet.
6. Nieuwe antwoordenums zijn unknown-safe; bestaande gesloten enums worden niet uitgebreid.

Vóór capability aan: schemafixtures en negatieve controles, echte API-captures,
publieke appinterface, twee gebruikers/bibliotheken, ambigue én tegenstrijdige
IDs, Plex+Pleya-bronkiezer, correctie/reset/pin over drie rondes en een scan,
provideruitval en SSRF-/redirect-/bestandsgroottegrenzen. Webbeelden volgen de
bestaande northstar; native detail/persoonsbeelden tonen de werkelijke app.
Dit venster geeft geen productie-, merge- of releaseautorisatie en opent geen
boeken-, realtime-, collectie-, playlist-, MCP- of loudnesscontract.
