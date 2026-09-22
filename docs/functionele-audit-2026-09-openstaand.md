# Functionele audit september 2026: wat blijft staan

Aangelegd op 22 september 2026. De audit van die dag leverde zeven bevindingen op. Zes zijn
opgelost in de bijbehorende fixronde, F2 bleek een false positive. Tijdens de review van die
fixronde kwamen vijf problemen boven water die al vóór de wijzigingen bestonden. Ze zijn hier
vastgelegd en bewust niet meegenomen: de fixcommit raakte al negentien bestanden, en er nog
bestaande problemen bij trekken maakt hem moeilijker te beoordelen zonder dat het risico daalt.

Een zesde punt kwam er bij de merge-review bij en staat hieronder als P3. Dat is geen ouder
probleem maar een gat in een regel die de fixronde zelf introduceert, zonder dat het gedrag
slechter wordt dan het was.

Herkomst per punt: adversariële review over de uncommitte diff, plus een tweede onafhankelijke
codereview. Beide vonden onafhankelijk van elkaar dezelfde gestrande spinner in de Seerr-sheet,
die wel in de fixronde is meegegaan omdat hij door die ronde was veroorzaakt. De vijf hieronder
zijn ouder.

Volgorde is de prioritering die bij oplevering is afgesproken.

## P1. Een transportfout tijdens de write laat de markering vallen

`WatchActions.setWatched` (`lib/services/watch_actions.dart`) beslist vóór het verzoek of er
geschreven of gewacht wordt. Gaat de server om tussen die beslissing en het antwoord, of komt er
een 502 of een TLS-fout terug, dan reist de exception naar de aanroeper. `media_context_menu.dart`
en `action_buttons.dart` tonen een foutmelding en laten de markering vervallen.

Het TV-menu lost dit al op voor zijn eigen fan-out: `tv_unified_context_menu.dart:438` zet een
write die faalde om een reden die een reconnect repareert alsnog in de wachtrij, via
`isRetryableServerWriteFailure`. De twee andere oppervlakken hebben die stap niet.

Wat een oplossing kost: dezelfde classificatie toepassen in `setWatched` zelf, met deduplicatie
tegen een write die de server half heeft verwerkt voordat de verbinding wegviel.

## P1. Een schrijfactie zonder wijziging kan de verkeerde taalvoorkeur laten winnen

`PleyaProfileLanguagePreferenceStore.update` (`lib/services/pleya_profile_language_preference_store.dart:93`)
stampt `updatedAt` op `DateTime.now()` en schrijft, ook wanneer de callback `current` ongewijzigd
teruggeeft. Zodra beide latches dicht zijn doet elke `ensureInitialised` dat twee keer: één keer
voor de migratie, één keer voor de seed.

De key `pleya_profile_language_preferences` staat in `preference_sync_policy.dart:251` op
`PreferenceScopeKind.profile`, wat last-writer-wins is over apparaten. Een toestel waarop iemand
alleen de instellingenpagina opent, schrijft daarmee een verse mutatie met ongewijzigde waarden en
kan een toestel overstemmen waarop wel iets is gekozen.

Wat een oplossing kost: `update` laten vaststellen dat er niets veranderde en de schrijfactie dan
overslaan. De vergelijking moet over de velden zonder `updatedAt` lopen, want die zit in `toJson`
en verschilt per aanroep.

## P2. Het TV-menu telt een gequeuede markering als uitgevoerd

`_applyToOneSource` (`lib/screens/tv/tv_unified_context_menu.dart:581`) gooit de teruggegeven
`WatchMarkOutcome` weg, en `_applyToSources` verhoogt `done` onvoorwaardelijk zodra die functie
terugkeert (`:432`). Klapt de gezondheid van een server om tussen het samenstellen van de
bronnenlijst en de write, dan geeft `setWatched` `queuedOffline` terug en meldt het menu "klaar op
N" over een markering die nog in de wachtrij staat.

De markering gaat niet verloren en wordt precies één keer in de wachtrij gezet. Alleen de melding
klopt niet, en dat is wel het soort onwaarheid waar hoofdstuk 13.4 punt 5 tegen geschreven is.

Wat een oplossing kost: de outcome doorgeven en de teller splitsen in uitgevoerd en uitgesteld.

## P2. Advanced laat een 4K-verzoek op een SD-server toe

De 4K-schakelaar kiest sinds de fixronde zelf een passende Radarr- of Sonarr-instantie. De lijst
onder Advanced doet dat niet: `seerr_request_sheet.dart:319` toont elke server, `_selectServer`
accepteert elke server, en de submit stuurt `is4k` en `serverId` samen op.

Overseerr laat een expliciete `serverId` de eigen, correcte default onvoorwaardelijk overschrijven
en controleert de 4K-ness van die override niet
(`server/subscriber/MediaRequestSubscriber.ts:151-162`, dat bij een override enkel
`Request has an override server` logt). Een beheerder kan 4K aanzetten, in Advanced de SD-instantie
kiezen, daar de SD-profielen laden en versturen. Dat is precies de combinatie die de toggle nu
vermijdt.

Dit is de gedocumenteerde override van Overseerr zelf, dus het is geen fout in het protocol. Het is
wel een gat in de sheet, die inmiddels weet welke servers bij welke keuze horen en dat niet laat
zien.

Wat een oplossing kost: de lijst filteren op `server.is4k == _is4k`, of de niet-passende servers
tonen met een waarschuwing erbij.

## P3. De uitzondering voor een afgewezen token dekt het geval zonder client niet

`WatchActions.setWatched` maakt sinds de fixronde een uitzondering voor een server waarvan het
token is afgewezen: die markering gaat niet naar de wachtrij, want geen reconnect repareert hem, en
de 401 moet de aanroeper bereiken zodat de herinlogmelding verschijnt. Die uitzondering staat in
`lib/services/watch_actions.dart` ná de controle op een ontbrekende client, en werkt dus alleen
wanneer er een client is.

`markPlexConnectionAuthError` (`lib/profiles/active_profile_binder.dart:585`, `:656`, `:846`)
markeert een Plex-server als afgewezen zonder dat er een client bestaat. De eigen documentatie van
die methode zegt waarom: een auth-fout bij het opstarten gebeurt voordat een client kan bestaan.
Markeert de kijker daarna een item uit de nog gecachete rij als bekeken, dan is er geen client, gaat
de markering alsnog de wachtrij in, en leest de melding "offline gemarkeerd" terwijl de app online
is. Uit die handeling volgt geen herinlogsignaal.

Dit is geen verslechtering. Vóór de fixronde gaf dit pad `WatchMarkOutcome.skipped`, waarna het
contextmenu een succesmelding toonde voor iets dat niet was gebeurd en de markering verdween. Hij is
nu duurzaam. Het is wel een gat in een regel die de fixronde zelf introduceert, en het pad is niet
getest: de bestaande test registreert eerst een client en markeert die daarna pas als afgewezen.

Wat een oplossing kost: `authErrorServerIds` toetsen vóór de controle op een ontbrekende client, of
in die tak dezelfde uitzondering maken. Plus een testgeval zonder client.

## P4. Een markering zonder server geeft geen antwoord

`media_context_menu.dart` doet niets bij `WatchMarkOutcome.skipped`. Die uitkomst treedt alleen op
wanneer `item.serverId` leeg is. De oude code toonde daar een succesmelding voor iets dat niet
gebeurd was, dus stilte is geen verslechtering, maar het is ook geen antwoord: de gebruiker tikt en
het menu sluit.

Bereikbaarheid is niet aangetoond. Er is niet vastgesteld welk `MediaItem` in dit menu terecht kan
komen zonder `serverId`. Het oude eerste pad (`if (isOffline && item.serverId != null)`) en het
nullable type van `_itemServerId` laten zien dat de auteur er rekening mee hield.

Wat een oplossing kost: eerst vaststellen of het geval bestaat. Bestaat het, dan een melding die
zegt dat de actie voor dit item niet beschikbaar is.
