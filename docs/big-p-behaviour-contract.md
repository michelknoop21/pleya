# Big P: gedragscontract

Status: akkoord van Michel op 5 oktober 2026, met de preciseringen hieronder verwerkt. Roadmap: BP-00. Uitgangsstand: `github/main` 1b93c50d (5 oktober 2026).
Besluiten: `DEC-XXX` (intent-laag vóór de model-lus) en `DEC-XXX` (DEC-005 terugdraaien: Trakt inlezen komt terug via BP-07). Nummers volgen bij de merge.

## Doel

Pleya stelt eerst vast wie, wat en welke data bedoeld is, verzamelt gecontroleerd de juiste gegevens, geeft het model alleen de juiste context, controleert de uitkomst en toont tekst en acties uit één waarheid. Code stelt harde feiten vast. Het model vult alleen open velden en schrijft zinnen uit aangeleverde redenen.

## Voorrang

Van hoog naar laag:

1. Security en rechten (kinderprofiel, bevoegdheid per bron en gegevenstype, bevestiging van schrijfacties).
2. Een uitdrukkelijke, actuele gebruikerskeuze in de huidige vraag.
3. De vastgestelde intent (code-feiten, gesprek, knop).
4. Persistent geheugen en voorkeuren.
5. Defaults.
6. Het model, dat alleen open velden vult.

Een lager niveau overschrijft nooit een hoger niveau. Onbekend betekent wedervraag of gedeeltelijk antwoord, nooit stil verbreden. Een onbekende identiteit of doelgroep wordt nooit opgelost met een gok. Pleya vraagt (maximaal drie wedervragen, een per keer, twee of drie knoppen plus vrije invoer) of antwoordt gedeeltelijk en zegt wat is weggelaten.

## Capaciteitsgaten en identiteit

- Ontbrekende externe id's, beoordelingen of favorieten (bijvoorbeeld op Pleya Server) zijn een capaciteitsgat. Ze zijn onbekend, niet onwaar en niet negatief: een ontbrekende beoordeling telt niet als "laag", een ontbrekende favoriet niet als "geen favoriet".
- Zonder sterk bewijs (extern id, gedeeld plex.tv-id, profielbinding) blijft identiteit bronlokaal. Een capaciteitsgat is nooit een reden om titels of accounts over servers toch samen te voegen.
- Tests: onbekende beoordeling beïnvloedt de rangschikking niet; zonder extern id geen cross-server merge; ontbrekende favorieten leveren geen "niet favoriet" in een antwoord.

## Nultolerantie

Elk van deze is een harde fout in de handmatige poort en heeft een test die faalt als het gedrag terugkomt:

1. Antwoord over de verkeerde gebruiker.
2. Eigen data bij een vraag over anderen.
3. Een serie bij een filmvraag, of omgekeerd.
4. Data tonen of gebruiken zonder bevoegdheid, ook als de rechten wisselden tijdens het wachten.
5. Verzonnen kijkhistorie, of historie zonder het venster te noemen.
6. Succes tonen voor een taak die mislukte of waarvan de status onbekend is.
7. Een verbreed publiek: "anderen" wordt nooit "iedereen".
8. Een samengevoegde ranglijst presenteren als volledig terwijl niet elke groep een bewezen identiteit heeft.

## Connected Knowledge

Regel: geen gekoppelde, relevante bron blijft onbereikbaar voor Big P alleen omdat er geen losse tool voor bestaat. De grens zijn de rechten van de gebruiker (per bron en per gegevenstype), wat de bron aanbiedt en de privacy van die verbinding.

Gecontroleerd tegen de code op 5 oktober 2026. "Mist" is wat Big P nu niet kan lezen of koppelen.

| Bron | Levert | Adapter | Rechten | Mist (gecontroleerd) |
|---|---|---|---|---|
| Plex | bibliotheken, items, recent toegevoegd, serverhistorie met account, collecties, eigen beoordeling, watchlist | `PlexClient`, `fetchRecentlyAdded`, `PlexHistoryPlay` (`server_activity.dart`) | eigen token; historie van anderen alleen als eigenaar | `PlexHistoryPlay` draagt geen item-id; eigen beoordeling en watchlist worden niet gelezen |
| Jellyfin, Emby | idem plus favorieten | `JellyfinClient`, `fetchFavorites`, `ExternalIds.fromJellyfinProviderIds` | eigen gebruiker; anderen alleen als beheerder | historie vraagt geen `ProviderIds` en `ProductionYear` op; favorieten niet bij Big P |
| Pleya Server | bibliotheken, items, recent toegevoegd, kijkhistorie voor beheerders | `PleyaServerClient`, `fetchRecentlyAdded` in `parts/browse.dart`, `/users/me` | rol op de verbinding | `fetchFavorites` is `unsupported`; geen externe id's of beoordelingen |
| Lokaal | items, recent toegevoegd | `LocalFolderClient` | apparaat | geen accounts, dus geen "anderen" |
| Tautulli | speelhistorie met gebruiker | `TautulliHistoryEntry` | beheerder | model heeft `rating_key` en `grandparent_rating_key`, maar geen `year` of `guid` |
| Seerr | zoeken, ontdekken, status, quota | `SeerrClient` | eigen Seerr-gebruiker | de client kan aanvragen lijsten (`seerr_client_requests.dart`, `GET /request`); of `request_status` op de eigen Seerr-gebruiker filtert, toetst BP-02 |
| TMDB | details, trending, aanbevolen, vergelijkbaar | `TmdbClient` (eigen sleutel) | geen gebruikersdata | `details` geeft een ruwe map; `belongs_to_collection` wordt nergens gelezen |
| Trakt | historie, beoordelingen, watchlist | alleen uitgaand (`scrobble*`, `addToHistory`, `addRatings`, `getUserSettings`) | eigen Trakt-account | de hele leeskant |

Eigen sleutel per bron voor "ik" (BP-02): Tautulli via `plexSelfAccountIdIn` (`lib/profiles/plex_self_account.dart`), Plex-historie alleen als eigenaar, Jellyfin/Emby via `connection.userId`, Pleya Server via `/users/me`, Trakt via `getUserSettings`. Is die sleutel er niet, dan is "ik" voor die bron onbekend en geldt de voorrangsregel hierboven.

## Gedragsmatrix

Wat vastligt in code, wat het model mag kiezen, en de terugval. Tools naar huidige registratie in `lib/assistant/assistant_tools*.dart`.

| Vraagsoort | Publiek | Soort | Bron | Tool | Model kiest | Terugval |
|---|---|---|---|---|---|---|
| Wat heb ik gekeken | ik | film/serie uit de vraag | kijkhistorie plus ooit-gezien | `my_watching` | alleen zachte filters | venster noemen; sleutel onbekend: wedervraag |
| Kijkcijfers, wat kijken anderen | anderen op account-id, nooit iedereen | uit de vraag | historie per bron | `watch_stats` | periode binnen vaste lijst | publiek onbekend: wedervraag; geen bewijsde identiteit over servers: per server tonen |
| Aanbevelen voor mij | ik | uit de vraag, anders vragen | bibliotheek eerst | `recommend_together` (en BP-07-pijplijn) | alleen zachte argumenten | te weinig resultaat: apart gemarkeerd buiten de bibliotheek |
| Aanbevelen samen | ik plus genoemde personen | uit de vraag | bibliotheek | `recommend_together` | persoonskeuze alleen uit treffers | meerdere treffers: knoppen |
| Recent toegevoegd | ik (zichtbare bibliotheken) | uit de vraag | `fetchRecentlyAdded`, `addedAt` | `search_catalog` met `sort: added` | geen | bron die het venster niet haalt: als gedeeltelijk melden |
| Titel zoeken, vergelijkbaar, trending | ik | uit de vraag | catalogus, TMDB | `search_catalog`, `find_title`, `similar_titles`, `trending_titles` | zoektermen | geen treffer: zeggen, niet raden |
| Aanvragen | ik | uit de vraag | Seerr | `find_request_title`, `request_title`, `request_status` | titelkeuze uit treffers | schrijfactie altijd met bevestiging |
| Beheer (taken, scans, gebruikers) | beheerder | n.v.t. | server | `scan_library`, `list_jobs`, enz. | parameters binnen schema | rechten opnieuw toetsen na wachten (BP-01) |
| Diagnose | ik/beheerder | n.v.t. | server | `diagnose_library`, `diagnose_playback` | geen | status onbekend is geen "klaar" |

## Vragenset en nulmeting

Ongeveer 40 echte vragen, handmatige poort vóór elke build tegen twee modellen; vaste gevallen lopen als gewone tests in CI. Eerste volledige route: "Wat is deze week aan mijn bibliotheken toegevoegd?" (BP-05). De set groeit per fase met de nultolerantiegevallen hierboven.

De nulmeting op de baseline (1b93c50d) volgt in BP-01 vóór de eerste codewijziging; ze staat in het fase-rapport, niet hier, zodat dit document geen statusadministratie wordt.

## Besluiten van Michel (5 oktober 2026)

1. Akkoord op nultolerantielijst en voorrang.
2. DEC-005 is als architectuurbeslissing teruggedraaid. BP-07 blijft achter de echte Trakt-poort: geslaagde device activation, tokenuitgifte, verversen zonder secret en correcte tokenrotatie. Werkt dat niet betrouwbaar, dan PKCE.
3. Pleya Server zonder externe id's en beoordelingen is voorlopig een capaciteitsgat (zie boven).
