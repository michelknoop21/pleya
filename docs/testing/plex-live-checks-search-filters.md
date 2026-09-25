# Live controles zoeken en filters (Plex, Jellyfin)

Vier gedragingen uit fase 1 van zoeken en filters zijn gebouwd op de gedocumenteerde vorm van de API, niet op een echte response. Dit recept haalt die responses op. Draai het zelf in een terminal; plak geen token in een chat of commit.

| Stap | Vraag | Wat de code nu aanneemt |
| --- | --- | --- |
| 1 | Levert `/library/search` met `searchTypes=movies,tv` afleveringen en collecties? | Ja, als de response ze bevat worden ze doorgelaten (`PlexClient._search`). Ongeverifieerd. |
| 2 | Geeft `inProgress=1` alleen begonnen titels, ook op een seriesectie? | Ja, op film- en seriesecties. |
| 3 | Betekent `unwatched=0` "alleen bekeken"? | Nee, daarom is Bekeken op Plex uitgeschakeld. |
| 4 | Is de `key` van een `contentRating`-waarde de classificatie of een pad? | Beide worden uitgepakt. |
| 5 | Geeft Jellyfin `Filters=IsResumable` op series de series met een begonnen aflevering? | Ja, maar oudere servers zijn niet getest. |

## Recept

Vervang de drie placeholders. Het Plex-token staat in Plex Web onder "Get Info > View XML" van een willekeurig item (`X-Plex-Token=` in de URL).

```bash
PLEX='<plex-server-url>'            # bijvoorbeeld http://<ip>:32400
TOKEN='<x-plex-token>'
H=(-s -H "Accept: application/json" -H "X-Plex-Token: $TOKEN")

# 1. Zoeken: welke types komen terug? Kies een term die in een afleveringstitel
#    en in een collectienaam voorkomt.
curl "${H[@]}" "$PLEX/library/search?query=<zoekterm>&limit=50&searchTypes=movies,tv&includeCollections=1&includeExternalMedia=1" \
  | tee plex_library_search.json \
  | jq '[.MediaContainer.SearchResult[] | {score, type: .Metadata.type, title: .Metadata.title, show: .Metadata.grandparentTitle}]'

# 1b. Alleen als 1 geen afleveringen geeft: dezelfde term via /hubs/search.
curl "${H[@]}" "$PLEX/hubs/search?query=<zoekterm>&limit=20" \
  | jq '[.MediaContainer.Hub[] | {type, size}]'

# Sectie-id's voor stap 2 t/m 4.
curl "${H[@]}" "$PLEX/library/sections" | jq '.MediaContainer.Directory[] | {key, type, title}'
FILMS=<key-filmsectie>
SERIES=<key-seriesectie>

# 2. inProgress=1: elke filmtreffer heeft een viewOffset (begonnen, niet af).
curl "${H[@]}" "$PLEX/library/sections/$FILMS/all?type=1&inProgress=1" \
  | jq '{size: .MediaContainer.size, zonder_viewOffset: [.MediaContainer.Metadata[]? | select(.viewOffset == null) | .title]}'
#    Op series: staan hier precies de series met een half bekeken aflevering?
curl "${H[@]}" "$PLEX/library/sections/$SERIES/all?type=2&inProgress=1" \
  | jq '{size: .MediaContainer.size, titels: [.MediaContainer.Metadata[]?.title]}'

# 3. unwatched=0 tegenover geen filter en unwatched=1.
for q in "" "&unwatched=0" "&unwatched=1"; do
  curl "${H[@]}" "$PLEX/library/sections/$FILMS/all?type=1$q" \
    | jq --arg q "${q:-geen filter}" '{filter: $q, size: .MediaContainer.size, nooit_bekeken: ([.MediaContainer.Metadata[]? | select((.viewCount // 0) == 0)] | length)}'
done
# "Alleen bekeken" geldt als size(unwatched=0) + size(unwatched=1) gelijk is
# aan size(geen filter) en nooit_bekeken 0 is bij unwatched=0.

# 4. contentRating-waarden: waarde of pad?
curl "${H[@]}" "$PLEX/library/sections/$FILMS/contentRating" \
  | jq '[.MediaContainer.Directory[]? | {key, title}]'

# 5. Jellyfin, seriesbibliotheek.
JF='<jellyfin-server-url>'
JF_KEY='<jellyfin-api-key>'
JF_LIB='<parent-id-seriesbibliotheek>'
curl -s -H "Authorization: MediaBrowser Token=\"$JF_KEY\"" \
  "$JF/Items?ParentId=$JF_LIB&IncludeItemTypes=Series&Recursive=true&Filters=IsResumable" \
  | jq '{total: .TotalRecordCount, titels: [.Items[].Name]}'
```

## Wat terug moet

- `plex_library_search.json` vervangt `test/fixtures/plex_search/library_search_documented.json`. Staan er geen `episode`-treffers in, dan klopt de zoekaanroep niet en moet `searchTypes` of het endpoint (stap 1b) veranderen.
- De uitvoer van stap 2 tot en met 5. Stap 3 bepaalt of Bekeken ook voor Plex aan kan (`_executesWatchedFilter` en de Plex-vertaler). Geeft stap 2 of 5 op series iets anders dan de begonnen series, dan hoort Actief bezig op seriesbibliotheken van die backend uit.

Bronnen voor de parameters: Plex OpenAPI-spec van lukasparke (`/library/search`, `/hubs/search`), python-plexapi `LibrarySection.search` (velden `inProgress`, `unwatched`, `contentRating`), Jellyfin OpenAPI stable `GET /Items` (`Filters`, `IncludeItemTypes`).
