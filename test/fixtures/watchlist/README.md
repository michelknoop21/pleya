# Watchlist-fixtures

Vastleggingen van `discover.provider.plex.tv` en `metadata.provider.plex.tv`,
gemeten op 16 augustus 2026 tegen een echt Plex-account met een actief
abonnement en een Plex Home van twee gebruikers. De item-payloads zijn
letterlijk wat de API teruggaf; alleen de teller-velden van de container zijn
herschreven, zodat `watchlist_page1.json` en `watchlist_page2.json` samen een
lijst van drie vormen die in een test te doorlopen is.

De drie titels (Sintel, Big Buck Bunny, Pioneer One) zijn Creative
Commons-films die tijdens de meting zijn toegevoegd en daarna weer verwijderd.
De lijst van het account is naderhand vergeleken met de nulmeting en was
regel voor regel identiek. Er staat geen token, cookie, client-id, account-uuid
of privé-server-URL in deze map.

## Wat de meting opleverde

**Paginatie zit in de container, niet in headers.** `MediaContainer` draagt
`size` (items in dit antwoord), `totalSize` (totaal) en `offset`.
`X-Plex-Container-Start` en `X-Plex-Container-Size` gaan mee als queryparameter.
Doorlopen tot `offset + size >= totalSize`.

**Het padsegment `available` gaat over streamingdiensten, niet over je eigen
servers.** Van 17 items vielen er 3 buiten `/watchlist/available`. Voor een
titel binnen dat filter geeft `/library/metadata/<key>/availabilities` een
`Availability`-rij met een platform (Netflix NL, Rakuten TV); voor een titel
erbuiten geeft datzelfde endpoint `totalSize: 0`. Het segment zegt dus niets
over de bibliotheken van de gebruiker. Het UI-filter "Beschikbaar" moet op de
eigen matching leunen, niet op dit segment.

**`filter=available` als queryparameter bestaat niet.** Op `/watchlist/all`
wordt hij genegeerd: zelfde `totalSize` als zonder de parameter.

**`userState` is een object, geen array.** Het staat onder
`MediaContainer.UserState` en draagt `watchlistedAt` in **seconden** sinds
epoch. Zodra een titel van de lijst af is, is de sleutel `watchlistedAt`
afwezig; het antwoord blijft 200 met `size: 1`. Zie
`user_state_watchlisted.json` tegenover `user_state_not_watchlisted.json`.

**De lijst zelf draagt geen `watchlistedAt`.** `includeUserState=1` verandert
niets aan de items, en `includeFields=watchlistedAt` sloopt alleen de rest van
de velden zonder het gevraagde veld te leveren. Wie per titel wil weten wanneer
hij is toegevoegd, betaalt daar een aparte call voor.

**Sorteren gebeurt aan de serverkant.** De volgorde zonder `sort` is regel voor
regel gelijk aan `sort=watchlistedAt:desc`. Ook `watchlistedAt:asc` en
`titleSort:asc` werken. Dat maakt de per-titel `watchlistedAt` overbodig voor de
standaardvolgorde.

**Dubbel toevoegen is geen fout.** Zowel `addToWatchlist` als
`removeFromWatchlist` geven bij een herhaling gewoon 200 met
`{"MediaContainer": {"size": 0}}`. De optimistische rollback hoeft daar dus niet
op te compenseren. Een onbekende ratingKey geeft 404, een ontbrekende ratingKey
400, en een verzoek zonder of met een ongeldige token 401.

**Artwork komt van publieke CDN's.** Alle 179 beeld-URL's in de 17 items zijn
absoluut en wijzen naar `metadata-static.plex.tv`, `image.tmdb.org`,
`assets.fanart.tv`, `artworks.thetvdb.com` of `vod-static.plex.tv`. Geen enkele
is een relatief pad. Steekproeven laden met 200 zonder één header. Er hoeft dus
geen accounttoken in een image-cachekey te belanden.

## Bestanden

| Bestand | Wat het vastlegt |
| --- | --- |
| `watchlist_page1.json` | Eerste pagina, `offset 0`, `size 2`, `totalSize 3`. Een film en een serie |
| `watchlist_page2.json` | Tweede pagina, `offset 2`, `size 1` |
| `watchlist_empty.json` | Lege lijst: `totalSize 0` en geen `Metadata`-sleutel |
| `user_state_watchlisted.json` | `UserState` mét `watchlistedAt` |
| `user_state_not_watchlisted.json` | Hetzelfde item nadat het van de lijst is gehaald |
| `action_success.json` | Antwoord op add en remove, ook bij een herhaling |
| `error_401_missing_token.json` | Verzoek zonder token |
| `error_404_unknown_rating_key.json` | Add met een niet-bestaande ratingKey |
| `error_400_missing_rating_key.json` | Add zonder ratingKey |
