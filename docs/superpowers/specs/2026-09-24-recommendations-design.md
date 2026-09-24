# Aanbevelingen uit kijkgeschiedenis en de Tautulli-defecten: ontwerp

Datum: 24 september 2026. Auteur: Michel Knoop. Worktree `feat/recommendations` op `3ad702d3`
(github/main). Besluit: DEC-132 (zie paragraaf 8). Plan: `docs/superpowers/plans/2026-09-24-recommendations.md`.

De opdracht in één zin: "Bedenk een plan voor Tautulli en maak er iets moois van." Dat is twee
dingen. De drie bevestigde Tautulli-defecten uit de audit van 24 september moeten dicht, en de
Home-rijen die uit de kijkgeschiedenis komen moeten persoonlijk en uitlegbaar worden, binnen de
rijwidgets die er zijn en binnen de privacygrens van DEC-004 en DEC-062.

Alle regelnummers hieronder zijn opnieuw nagelopen op `3ad702d3`. Waar de audit (geschreven op
`d23f6c9f`) afwijkt staat dat erbij.

## 1. Huidige situatie

### 1.1 Wat Tautulli voedt

Alle calls lopen door `TautulliClient._call` (`lib/services/tautulli/tautulli_client.dart:100-128`).
De volgorde in `_interpret` (regels 141-163) is decoderen, envelop, dan pas statuscode, zodat een
gevolgde Cloudflare-302 als `notTautulli` eindigt en niet als "netwerkfout".

| Commando | Voedt | Bron in code |
| --- | --- | --- |
| `register_device`, `get_server_info`, `get_server_friendly_name`, `get_tautulli_info` | koppelen en de instellingenkaart | `lib/providers/tautulli_provider.dart:255-311` |
| `get_activity` | "Nu aan het kijken" (appbar, paneel, TV-sectie) en de regel "X kijkt dit nu" op detail | `lib/services/now_watching_service.dart:39`, `lib/screens/media_detail/now_watching_line.dart:30-33` |
| `get_item_user_stats` | "Bekeken door" bij een serie en het kijkersaantal | `lib/services/item_watchers_service.dart:60`, `lib/services/media_watch_stats_service.dart` |
| `get_history` met `rating_key` | "Bekeken door" bij een film | `item_watchers_service.dart:76` |
| `get_history` met `user_id`, `grouping=0`, `length=200` | de smaakengine: rijen in `MediaInteractions` met `source='tautulli'` | `tautulli_provider.dart:440-483`, `lib/services/recommendations/tautulli_history_importer.dart` |
| `get_item_watch_time_stats` | statistiekenregel op detail | `media_watch_stats_service.dart` |
| `get_users`, `ping` | niets, dode clientmethoden | `tautulli_client.dart:384, 410` |

`get_home_stats` heeft geen clientmethode. DEC-062 sluit serverpopulariteit uit en de code houdt
zich daaraan; de fixture `test/fixtures/tautulli/home_stats.json` is het enige spoor.

De import zelf: `DiscoverProvider._loadRecommendationRows` (`lib/providers/discover_provider.dart:473-497`)
start na elke volledige Home-load `RecommendationService.syncImportedHistory`, single-flight met
maximaal drie gekoppelde herhalingen (`recommendation_service.dart:129-160`). De importer schrijft
`completed` +1,0 bij `watched_status >= 1` of `percent_complete >= 85`, `partial` +0,4 bij 50 tot
85, en niets daaronder (`tautulli_history_importer.dart:777-782`). Een aflevering krijgt de
serie-sleutel als `seriesKey` (regel 709). `completionPercent` en `playSeconds` worden opgeslagen
(regels 727-728) en door niets gelezen.

### 1.2 Het huidige Home-algoritme, precies

`DiscoverProvider.hubs` (`discover_provider.dart:145-147`) is de ene bron voor elke presentatie:
pointer en mobiel via `DiscoverScreen`, TV via `TvHomeProjectionProvider` die dezelfde lijst door
`HomeProjectionService.projectHubs` haalt. De volgorde is vast:

```
[Recent toegevoegde series] + _seedHubs (max 3) + _personalizedHubs + _hubs (backend)
```

Verder kijken en de hero staan hier buiten; die zijn vaste slivers.

Seed-rijen "Omdat je X gekeken hebt" (`discover_provider.dart:500-545`). Per online client
`fetchRecentlyWatched(limit: 5)`. Plex: `/library/all?type=1|2&sort=lastViewedAt:desc` gefilterd
op `isWatched` (`lib/services/plex_client.dart:3905-3930`). Jellyfin: `/Items?Filters=IsPlayed&SortBy=DatePlayed`
op `Movie,Series` (`lib/services/jellyfin_client/parts/browse.dart:1637-1650`). Pleya Server:
`GET /watch-state?limit=100` met `watched == true` (`lib/services/pleya_server_client/parts/playback.dart:225-251`).
Samengevoegd op `recencySortKey`, uniek op serietitel of titel, maximaal drie seeds (regels
516-528). Per seed `fetchRelatedHubs(seed.id)` (Plex `/hubs/metadata/{key}/related`, Jellyfin
`/Items/{id}/Similar`); de eerste hub met items die niet de seed zijn en nog niet op Home staan
wordt de rij, identifier `home.becauseyouwatched` (regels 547-568). Er is geen filter op
`isWatched` binnen die rij.

Gepersonaliseerde rijen (`RecommendationService.buildRows`, `recommendation_service.dart:95-116`).
Invoer is het interactielog van dit profiel. Lokaal schrijft `InteractionRecorder` twee signalen:
`completed` +1,0 bij een `watched`-event en `skipped` -0,3 bij verwijderen uit Verder kijken
(`interaction_recorder.dart:58-63`). De vector (`taste_profile.dart:164-266`): halfwaardetijd 90
dagen, per evidence-sleutel telt de n-de positieve gebeurtenis 1/n, cumulatief geplafonneerd op
3,0, dimensies genre/acteur (eerste vijf)/regisseur/mood/studio/decennium genormaliseerd op de
sterkste, penalty's apart en geplafonneerd, warm vanaf acht onderscheiden titels
(`kWarmDistinctTitles`, regel 14). De score (`taste_profile.dart:310-355`): 3 x genre + 2 x acteur
+ 1,5 x regisseur + 1 x decennium + 0,6 x studio + 0,5 x mood, minus gedempte penalty (max 2,0),
plus 0,8 x rating/10, plus nieuwheidsbonus tot 0,4, plus dagelijkse jitter tot 0,05, minus 3,0 als
al bekeken. De kandidatenpool (`candidate_pool.dart:75-89`): alles wat al op Home staat, plus per
server 100 recent toegevoegd, plus per bibliotheek (max zes) 40 top-rated en 40 uit een roterende
pagina oudste toevoegingen. De rijen (`personalized_rows_builder.dart:25-96`): Top Picks (top 20),
bij warme smaak per genre met gewicht >= 0,5 (max twee) "Omdat je van <genre> houdt" met minimaal
vier treffers, en Verborgen parels (rating >= 7,5, ouder dan 90 dagen, niet in Top Picks).

Daarna: `_filterDiscoverHubs` gooit alles weg wat op ondeck/continue/nextup lijkt (regels 606-618),
`_orderDiscoverHubs` sorteert op bibliotheekvolgorde en dan op prioriteitsklasse
(`lib/utils/media_hub_ordering.dart:42-64`: gepersonaliseerd 0, next-up 1, recent 2, kwaliteit 3,
rest 4), `_dedupeDiscoverHubs` beperkt een titel tot twee verschijningen en eist drie unieke items
per rij (`hub_dedup.dart`). Verbergen en herordenen komt uit `HomeLayoutProvider.apply`
(`discover_screen.dart:165`), met als sleutel `homeRowId(hub)` = `'{serverId}:{identifier}'`
(`home_layout_provider.dart:20-24`). Rijen met dezelfde identity zijn één blok: de drie seed-rijen
van één server verbergen of verplaatsen samen.

### 1.3 Drie bevestigde defecten

**D1. Kruisserver-rating keys op detail.** `_loadWatchers` (`lib/screens/media_detail_screen.dart:2230-2266`)
geeft `TautulliProvider.client` mee op regel 2249 en nog eens op regel 2262, voor élk Plex-item
dat de gebruiker beheert. `_adminIntegration` (`tautulli_provider.dart:117-123`) kiest de eerste
beheerde server met een koppeling en kijkt niet naar `_metadata.serverId`. Wie twee Plex-servers
bezit en Tautulli op A heeft, ziet bij een titel op B de kijkers en statistieken van de titel met
dezelfde rating key op A. Een leeg Tautulli-antwoord telt als echt antwoord
(`item_watchers_service.dart:41-43`), dus op B verdwijnt "Bekeken door" helemaal.
`tautulliMonitoredServer` (`lib/services/tautulli/tautulli_server_binding.dart:20-33`) bestaat
hiervoor en wordt in `profile_session_screen.dart:205-222` wel voor de artwork-client gebruikt.
`NowWatchingLine` matcht alleen op rating key (`now_watching_line.dart:31`) en `WatchSession`
draagt geen serveridentiteit (`lib/media/watch_session.dart:29-86`), dus de fix zit bij de provider.
Audit-afwijking: de regelnummers zijn 2230/2249/2262 in plaats van 2222/2239/2254, en de
`NowWatchingLine`-montages staan op 3876 en 4609.

**D2. Seeds van clients zonder related hubs.** De seedselectie (`discover_provider.dart:511-528`)
loopt over alle online clients vóór bekend is of de bron related hubs kan leveren. Pleya Server
(`lib/services/pleya_server_client/parts/unsupported.dart:67`), de lokale map
(`local_folder_client.dart:452`) en Pleya Share (`pleya_share_client.dart:471`) geven altijd `[]`.
Een recente kijkbeurt op zo'n bron neemt een van de drie plekken in en levert een lege rij die
`_relatedRowForSeed` als `null` laat vallen. `ServerCapabilities` heeft geen vlag hiervoor;
`richHubs` (`server_capabilities.dart:57`) is Plex-only en dekt Jellyfin's `Similar` niet.

**D3. Een lopende serie seedt nooit.** `fetchRecentlyWatched` filtert op `isWatched`
(`plex_client.dart:3923`), en voor een serie is dat `viewedLeafCount >= leafCount`
(`lib/media/media_item.dart:665-671`). Jellyfin vraagt `IsPlayed` op `Series`, wat hetzelfde
betekent. De serie waar iemand middenin zit, het sterkste signaal dat er is, komt nooit als seed
boven. Alleen films en afgeronde series doen dat.

### 1.4 Plausibele punten uit de audit, met stand op main

| # | Punt | Stand op `3ad702d3` |
| --- | --- | --- |
| P4 | `test()` verbruikt de vijf-minuten-devicetoken op `register_device` (`tautulli_provider.dart:268`); als `serverFriendlyName` (293) of `version` (297) daarna faalt is de token weg en is niets opgeslagen | ongewijzigd, niet gemeten tegen `api2.py` |
| P5 | HTML met `content-type: application/json` wordt "netwerkfout" in plaats van "geen Tautulli" | ongewijzigd, klein |
| P6 | `_errorCategory` gebruikt `contains('apikey')` (`tautulli_history_importer.dart:900`), de heuristiek die de client afschafte (`isAuthMessage`, `tautulli_client.dart:169-178`) | ongewijzigd, alleen een loglabel |
| P7 | `fetchImportHistory` bouwt per pagina een `TautulliClient` (`tautulli_provider.dart:465-482`) | ongewijzigd |
| P8 | DEC-062 noemt `_denyPrefixes` (regel 517) en `fetchImportHistory(serverId, userId: …)` (regel 553); de parameter heet `profileId`. De kop van `tautulli_settings_screen.dart:32-35` zegt dat de koppeling "only ever serves the person holding it", terwijl DEC-062 en de code de import voor het hele huishouden laten werken | ongewijzigd |
| P9 | Of een beheerd Plex Home-profiel `owned == true` ziet in `isOwnerOrAdmin` (`multi_server_manager.dart:281-290`) en zo de huishoudnamen te zien krijgt | niet geverifieerd, alleen tegen een echte server te toetsen |

Geen enkele auditclaim bleek al gefixt. Twee claims verschoven van regel; geen enkele claim hield
niet.

## 2. Productontwerp

### 2.1 De rijen na dit werk

De Home-compositie verandert niet: hero, Verder kijken, Recent toegevoegde series, seed-rijen,
gepersonaliseerde rijen, backend-hubs. Wat verandert is waar de seed-rijen vandaan komen, hoe ze
heten, en welke gepersonaliseerde rijen er kunnen zijn.

| Rij | Identifier | Wanneer | Titel nl | Titel en | i18n-sleutel |
| --- | --- | --- | --- | --- | --- |
| Seed, afgekeken | `home.becauseyouwatched` | een seed uit het log met gewicht 1,0, of de fallback | Omdat je `X` gekeken hebt | Because you watched `X` | `discover.becauseYouWatched` (bestaat) |
| Seed, nog bezig | `home.becauseyouwatched` | een seed uit het log met gewicht 0,4 (`partial`) | Omdat je `X` kijkt | Because you're watching `X` | `discover.becauseYouAreWatching` (nieuw) |
| Top Picks | `home.toppicks` | altijd zodra de pool vier ongeziene items heeft, ook koud | Aanbevolen voor jou | Top Picks for You | `discover.topPicksForYou` (bestaat) |
| Genre | `home.becauselike.<genre>` | warm, genregewicht >= 0,5, minimaal vier treffers | Omdat je van `Genre` houdt | Because you like `Genre` | `discover.becauseYouLike` (bestaat) |
| Acteur | `home.becauselike.actor.<slug>` | warm, acteurgewicht >= 0,7, minimaal vier treffers | Meer met `Naam` | More with `Name` | `discover.moreWithActor` (nieuw) |
| Regisseur | `home.becauselike.director.<slug>` | warm, regisseurgewicht >= 0,7, minimaal vier treffers | Meer van `Naam` | More from `Name` | `discover.moreFromDirector` (nieuw) |
| Verborgen parels | `home.hiddengems` | rating >= 7,5, ouder dan 90 dagen, niet in Top Picks, minimaal vier | Verborgen parels | Hidden Gems | `discover.hiddenGems` (bestaat) |

Genre-, acteur- en regisseurrijen delen samen twee plekken (`kMaxAffinityRows = 2`). De
kandidaten worden gesorteerd op genormaliseerd gewicht; bij gelijk gewicht wint genre, dan acteur,
dan regisseur. Het gevolg in gewone woorden: een sterk gezicht wint van een zwak tweede genre, en
een profiel krijgt nooit meer gepersonaliseerde rijen dan vandaag (Top Picks, twee affiniteitsrijen,
Verborgen parels). Kanttekening die in de code als commentaar terugkomt: de gewichten zijn per
dimensie genormaliseerd op de sterkste feature, dus de sterkste acteur en het sterkste genre staan
beide op 1,0 ongeacht de hoeveelheid bewijs eronder. De drempel van 0,7 voor personen en de
voorrang voor genre bij gelijkspel zijn de compensatie daarvoor.

Koude start (minder dan acht onderscheiden titels met positief bewijs, `kWarmDistinctTitles`):
Top Picks op kwaliteit en nieuwheid, plus seed-rijen zodra er één seed is. Is het log leeg, dan
blijft het huidige pad via `fetchRecentlyWatched` de fallback, zodat een vers profiel op een oude
Plex-server niet slechter af is dan vandaag. Warm: alles uit de tabel.

### 2.2 Hoe een rij zichzelf uitlegt

De titel is de uitleg. "Omdat je Severance kijkt" zegt welke titel de rij veroorzaakte en dat die
nog loopt; "Omdat je Severance gekeken hebt" dat hij af is. "Meer met Tom Hanks" noemt de acteur
met de schrijfwijze van de server (de `MediaRole.tag` van het eerste treffende item, niet een
gelowercaste vectorsleutel die met een hoofdletter wordt hersteld). Er komt geen subtitel of
infoknop bij; de rijwidgets hebben die niet en de northstars (`mockups-2026-09-04/30-home-*`,
DESIGN-INDEX regel 86) tonen alleen een raillabel.

### 2.3 Verbergen en herstellen

Het mechanisme bestaat: "Home aanpassen" op TV (`lib/widgets/tv/tv_home_customize_panel.dart`) en
"Home-indeling" in de instellingen op mobiel en desktop (`lib/screens/settings/home_layout_screen.dart`),
beide op `HomeLayoutProvider` met `homeRowId`. Wat dat voor deze rijen betekent, en wat we niet
veranderen:

- De seed-rijen van één server delen `home.becauseyouwatched` en zijn dus één blok: één schakelaar
  verbergt ze alle drie. Dat is het bestaande gedrag (`home_layout_provider.dart:12-13`) en het
  blijft, want een rij die per seedtitel een eigen id krijgt zou elke week een nieuwe, onverborgen
  rij opleveren.
- `home.becauselike.<genre>` en de nieuwe `home.becauselike.actor.<slug>` zijn per feature: wie de
  Tom Hanks-rij verbergt, houdt de rij voor een andere acteur.
- Verbergen is layout, geen smaaksignaal. Een verborgen rij schrijft niets in `MediaInteractions`.
- Herstellen gebeurt met de bestaande schakelaar `personalizedRecommendations` (alles uit) en
  `deleteRecommendationDataForProfile` bij profielverwijdering. Er komt geen "smaak wissen"-knop en
  geen nieuw instellingenscherm.

### 2.4 De huishoudgrens en de afgekeken-regel

Elke rij in paragraaf 2.1 leest uitsluitend `MediaInteractions` van het actieve `profileId`. De
Tautulli-rijen daarin zijn gebonden aan het plex.tv-account-id van datzelfde profiel
(`fetchImportHistory`, `tautulli_provider.dart:451-453`). Geen rijtitel noemt ooit een persoon uit
het huishouden; "Meer met Tom Hanks" noemt een acteur. "Bekeken door" en "Nu aan het kijken"
blijven admin-only en veranderen alleen op D1.

Geen rij toont een titel die dit profiel al af heeft. `buildPersonalizedRows` filtert op
`isWatched` (regel 36). De seed-rij doet dat vandaag niet en gaat dat wel doen. Een rewatch-rij
bestaat niet en komt er in dit werk niet.

## 3. Signalen en scoring

### 3.1 De vijf verbeteringen

**(1) Seeds uit het interactielog: geaccepteerd, met twee wijzigingen.** Regel: de nieuwste
onderscheiden evidence-sleutels (`seriesKey ?? globalKey`) met gewicht >= 0,4 binnen 30 dagen,
gelezen via een nieuwe `AppDatabase.recentPositiveInteractions` met dezelfde `_scoringScope`
als de vector (uitgeschakelde Tautulli-servers tellen niet mee). Alleen clients met de nieuwe
capability `relatedHubs` (Plex en Jellyfin `true`, alles anders standaard `false`) komen in
aanmerking; een seed op een andere bron neemt geen plek in (sluit D2). Een `partial`-seed krijgt de
titel "Omdat je X kijkt", een `completed`-seed de bestaande titel (sluit D3). Wijziging één ten
opzichte van de audit: geen voorrang van `partial` boven `completed` op dezelfde dag, gewoon
recency; de regel is simpeler uit te leggen en het verschil is zelden zichtbaar. Wijziging twee: de
seed-rij filtert voortaan `isWatched`. Fallback bij een leeg log: het huidige `fetchRecentlyWatched`-pad.

**(2) Lokaal partieel signaal bij stoppen: geaccepteerd.** `WatchStateEvent` krijgt `durationMs`
en `isFinal`; `WatchStateNotifier.notifyProgress` krijgt `isFinal` en
`PlaybackProgressTracker._notifyProgressIfNeeded` geeft zijn bestaande `isFinal` door
(`playback_progress_tracker.dart:455-472`). `InteractionRecorder` schrijft bij een eindevent met
`percentage >= 50` en `isNowWatched != true` een rij `partial` 0,4, tenzij er binnen zes uur
(`kCrossSourceWindow`) al een positieve rij voor dezelfde `globalKey` staat. De bovengrens is de
kijkdrempel van de client (0,9 standaard, via `isNowWatched`), niet 85: het `watched`-event neemt
het daar over, en twee drempels voor één grens zou een gat of een overlap geven. Onder 50 procent
niets, conform DEC-062. Consequentie voor de importer: de cross-source-deduplicatie
(`tautulli_history_importer.dart:659-690`) onderdrukt een Tautulli-event alleen nog door een lokale
rij met een gewicht dat minstens even groot is. Zonder die aanpassing zou een lokale stop op 60
procent een uur later de volledige Tautulli-`completed` van hetzelfde kijkuur wegslikken.

**(3) Related hubs van seeds vier tot zes als kandidatenlaag: geaccepteerd.** De seedselectie
levert tot zes seeds; de eerste drie worden rijen, van vier tot zes worden alleen de related hubs
opgehaald en als `hubItems` aan `buildRows` gegeven. Ze komen niet in `excludeKeys`, zodat Top
Picks ze mag tonen. Drie extra servercalls per Home-load, alleen op Plex en Jellyfin.

**(4) Jellyfin-geschiedenisimport als tweede adapter: geaccepteerd, kleiner dan de audit.** Een
`JellyfinHistoryImporter` op de eigen gebruikersverbinding, dus zonder admincredential en zonder
binding. `source = 'jellyfin'`, `sourceServerId = serverId`, `sourceEventId =
'jellyfin:{serverId}:{itemId}:{lastPlayedDate}'` voor een afgespeeld item (`/Items` met
`Filters=IsPlayed`, `SortBy=DatePlayed`, `IncludeItemTypes=Movie,Episode`, pagina's van 200) en
`'jellyfin:{serverId}:{itemId}:resume'` voor een hervatbaar item tussen 50 en 90 procent
(`Filters=IsResumable`; de positie komt uit `UserData.PlaybackPositionTicks` en `RunTimeTicks`,
velden die de mapper al leest). Cursor in `HistorySyncCursors` met `source = 'jellyfin'` en
`forwardCursorAt` als watermark op `LastPlayedDate`; eerste run maximaal vijf pagina's, daarna
vooruit tot de watermark. Geen backfill-machinerie: de retentiecap van 5000 rijen en 365 dagen
geldt onveranderd en wie meer dan duizend afspeelbeurten heeft, verliest de oudste, precies wat de
cap toch al doet. Het scoringsfilter `NOT (source='tautulli' AND …)` laat de derde bron
onvoorwaardelijk meetellen; dat klopt omdat het de eigen token is en geen adminbeleid vraagt.
Dezelfde cross-source-regel als bij (2).

**(5) Acteur- of regisseursrij bij warme smaak: geaccepteerd, met de gedeelde cap uit 2.1.**
`AffinityVector.topFeatures('actor' | 'director', threshold: 0.7, limit: 1)` (`taste_profile.dart:152-159`)
levert de kandidaat; de rij eist vier ongeziene treffers op `roles` of `directors`.

### 3.2 Pleya Server

Wat er is (`pleya_server/internal/api/server.go:92-143`): `GET /hubs/{hub_id}` met alleen
`recently_added` gevuld, `POST /watch-state` en `GET /watch-state`, één subject `owner`
(`server.go:25`). Geen related-endpoint, geen per-gebruiker geschiedenis.

Wat de app vandaag al kan voor een Pleya Server-profiel: Top Picks, genre-, persoon- en
parelrijen uit het lokale log (het `watched`-event en het nieuwe partiële signaal werken
backend-neutraal) over een pool uit `fetchRecentlyAdded` en `fetchLibraryPagedContent`. Wat niet
kan: een "Omdat je X kijkt"-rij, want er is geen related-endpoint, en een geschiedenisimport per
gebruiker, want er is één subject. Beide zijn follow-ups voor de serverlijn en worden hier niet
ontworpen: `GET /items/{id}/related` (hoort bij de PS-7-metadata die `unsupported.dart:66`
noemt) en per-gebruiker watch-state (PS-9). Tot die tijd neemt een Pleya Server-seed geen plek in,
wat D2 sluit.

## 4. De Tautulli-fixes en de plausibele punten

| Item | Besluit | Hoe |
| --- | --- | --- |
| D1 kruisserver | fix | `TautulliProvider.clientForServer(ServerId)` geeft de adminclient alleen terug als `tautulliMonitoredServer` die server aanwijst; `_loadWatchers` gebruikt hem op beide plekken. `NowWatchingProvider` krijgt `monitoredServerId` en `NowWatchingLine` krijgt `serverId`; geen match, geen regel |
| D2 seeds zonder related hubs | fix | capability `relatedHubs`, zie 3.1 (1) |
| D3 lopende serie | fix | seeds uit het log, zie 3.1 (1) |
| P4 devicetoken verbruikt | afgewezen voor dit werk | niet gemeten of een tweede `register_device` met dezelfde string slaagt; `TautulliProvider.test` construeert zijn client zonder injecteerbare transportlaag, dus een test vraagt eerst een clientfactory. Staat in het register als open punt |
| P5 HTML met JSON-content-type | afgewezen | geen melding, geen reproductie, alleen een foutcategorie |
| P6 `contains('apikey')` | fix, mechanisch | `_errorCategory` leest `TautulliException.isAuth` en laat de tekstheuristiek vallen |
| P7 client per pagina | uitgesteld | 25 clients per forward-pass is meetbaar maar niet gevoeld; register |
| P8 documentatiedrift | fix, deels | de kop van `tautulli_settings_screen.dart` wordt herschreven; DEC-062 blijft historisch en krijgt een addendumregel die naar DEC-132 wijst |
| P9 beheerd Home-profiel en `owned` | open | alleen op een echte server te toetsen; register, LIVE ONLY |

## 5. Buiten scope

Geen ML en geen extern model. Geen engine op Pleya Server. Geen "populair in je huishouden" en
geen prior uit `get_home_stats`. Geen negatief signaal uit een afgebroken Tautulli-play (DEC-062).
Geen nieuw instellingenscherm en geen extra schakelaar. Geen nieuwe rijwidget: de rijen zijn
`MediaHub`s die door de bestaande renderers gaan (`TvContentFeed` en de mobiele en pointer-rijen
van `DiscoverScreen`). Geen wijziging aan de Home-compositie van de northstars: geen rij erboven,
geen ander aantal vaste rijen, geen subtitel onder een raillabel. Geen rewatch-rij.

## 6. Bewijs

### 6.1 Tests

Unit, met fixture-interactielogs in een in-memory drift-database (`AppDatabase.forTesting`) en
een vaste `nowMs` zodat verval en jitter deterministisch zijn:

- `recentPositiveInteractions`: dedup per evidence-sleutel, `minWeight` sluit `skipped` uit,
  venster van 30 dagen, `_scoringScope` sluit een uitgeschakelde Tautulli-server uit.
- Seedselectie in `DiscoverProvider`: een `partial`-seed levert "Omdat je X kijkt"; een seed op een
  client zonder `relatedHubs` neemt geen plek in en krijgt geen `fetchItem`; afgekeken items
  vallen uit de seed-rij; een leeg log valt terug op `fetchRecentlyWatched`; seeds vier tot zes
  komen als `hubItems` bij `buildRows` aan.
- `InteractionRecorder`: eindstop op 60 procent geeft één `partial` 0,4; onder 50 niets; een
  tweede eindstop binnen zes uur stapelt niet; een tussentijdse tick schrijft niets.
- Importer: een lokale `partial` slikt een Tautulli-`completed` niet meer weg; een lokale
  `completed` doet dat wel.
- `JellyfinHistoryImporter`: mapping van `Played` en `IsResumable`, idempotentie op
  `sourceEventId`, watermark, cross-source-dedup.
- `buildPersonalizedRows`: acteursrij met de servernaam als titel, cap van twee affiniteitsrijen,
  genre wint bij gelijkspel, geen persoonsrij bij koude smaak.
- `TautulliProvider.clientForServer` en `NowWatchingLine` met een andere server: niets.
- `HomeLayoutProvider.apply`: één verborgen `server:home.becauseyouwatched` verbergt alle
  seed-rijen van die server.

Widget: het bestaande TV-harnas in `test/screens/discover_screen_test.dart` (`_pumpTvDiscoverScreen`)
met een fake client die `fetchRecentlyWatched` en `fetchRelatedHubs` vult; assert op de rijtitel
`t.discover.becauseYouWatched(title: 'Severance')` in de feed.

### 6.2 Pleya Verify, eerlijk

De fixture-server is een Pleya Server-fake (`pleya_verify/fixture_server/lib/src/pleya_fake_server.dart`):
`/libraries`, `/items`, `/hubs/{id}` met alleen `recently_added`, `/watch-state`. Er is geen
related-endpoint en geen Plex of Tautulli in de fixture. Daarmee kan Verify géén seed-rij tonen en
geen warme rij, en of Top Picks verschijnt hangt af van de pool die de Pleya-client uit de fixture
kan trekken (niet gemeten). Er komt daarom geen nieuw scenario dat een rij belooft die de fixture
niet kan leveren. Wat wel gebeurt: de drie bestaande Home-scenario's draaien opnieuw als
regressiegate op precies het D2-geval (een Pleya Server-only profiel mag geen rijen verliezen of
hangen): `tvos.home.walk-rails` (asserts `discover.rail.item[1.0]`), `ios.home.northstar`
(`home.rail[0]` onder de hero) en `discover.layout.macos`. De uitkomst en de bundelpaden komen in
het register.

### 6.3 Statusladder per platform

| Trede | Betekent | Platforms |
| --- | --- | --- |
| CODE CLOSED | unit- en widgettests groen, `scripts/ci_checks.sh` groen | alle |
| SIM CLOSED | de drie Home-scenario's PASS op de fixture | tvOS, iOS, macOS |
| LIVE ONLY | seed-rijen, warme rijen, "Omdat je X kijkt", Jellyfin-import en D1 op een echt Plex-profiel met Tautulli en twee servers, plus een echt Jellyfin-profiel; screenshots in het register | iPhone of macOS volstaat als eerste bewijs, tvOS volgt |
| HARDWARE ONLY | D-pad-focus over een acteursrij en de seed-rijen op de Apple TV (railvolgorde, focusherstel via `TvFocusRestoreHost`); P9 op een beheerd Home-profiel | tvOS |

Android, Windows en Linux delen de pointer- en mobiele renderers en krijgen geen eigen trede; een
screenshot van Home op één van de drie na LIVE is voldoende.

## 7. Open productvragen

Deze konden niet uit de repo worden beslist en staan in het register tot Michel ze beantwoordt;
het plan bouwt met de genoemde default.

1. Moet een seed-rij op TV ook een `TvFocusRestoreHost` krijgen (HERO7 liet de discovery-rails
   bewust zonder)? Default: nee, zelfde behandeling als de andere rails.
2. Mag de acteursrij ook op een niet-warme smaak verschijnen als één acteur al drie films heeft
   geleverd? Default: nee, warm blijft de poort.
3. Verdient P4 (devicetoken) een clientfactory in `TautulliProvider.test` om hem testbaar te
   maken? Default: register, geen code.

## 8. Governance

- **DEC-132** in `docs/DECISIONS.md`. Het hoogste nummer op main is DEC-130 (`rg "^## DEC-" docs/DECISIONS.md`
  op `3ad702d3`); DEC-121 leeft op `feat/unified-desktop-ipad`, DEC-131 is geclaimd door
  `fix/icloud-sync`, DEC-122 tot en met DEC-129 staan nergens. `rg "DEC-131|DEC-132" docs lib test`
  is leeg op main.
- **Register** `docs/recommendations-register.md`, in de vorm van `docs/tvos-redesign-register.md`:
  statussen `OPEN`, `IN PROGRESS`, `CODE CLOSED`, `SIM CLOSED`, `LIVE ONLY`, `HARDWARE ONLY`,
  `DEFERRED`, met SHA en bewijsregel bij elke sluiting.
- **DEC-062** krijgt een addendumregel (geen herschrijving) voor de twee namen uit P8.
- `docs/agents/workflow-evaluation.md` heeft zijn drie regels en krijgt niets.
- i18n: nieuwe sleutels in `nl.i18n.json` en `en.i18n.json`; `slang.yaml` heeft
  `fallback_strategy: base_locale`, dus de veertien andere locales vallen terug op Engels tot
  iemand ze vertaalt.
