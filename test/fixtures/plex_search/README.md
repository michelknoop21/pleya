# Plex search fixtures

`library_search_documented.json` is not a capture. It follows the documented
`/library/search` shape: `MediaContainer.SearchResult[]`, each entry a `score`
plus one `Metadata` object (lukasparke Plex OpenAPI spec, and the shape
`PlexClient._search` has always parsed). It holds one entry per metadata type
the client has to decide about: movie, show, episode, collection, season and a
music track.

Live check open: this repo has never recorded what a real Plex Media Server
returns for `/library/search?query=...&searchTypes=movies,tv&includeCollections=1`.
Replace the file with a real capture once the owner has run the curl recipe in
the fase-1 report of the search-and-filters plan.
