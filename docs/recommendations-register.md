# Implementatieregister: aanbevelingen en Tautulli-defecten (DEC-132)

Aangelegd op 24 september 2026 door Michel Knoop. Spec:
`docs/superpowers/specs/2026-09-24-recommendations-design.md`. Plan:
`docs/superpowers/plans/2026-09-24-recommendations.md`.

Statussen: `OPEN`, `IN PROGRESS`, `CODE CLOSED`, `SIM CLOSED`, `LIVE ONLY`, `HARDWARE ONLY`,
`DEFERRED`. Bij elke sluiting komen de SHA en de bewijsregel erbij. Een rij verdwijnt alleen door
een eindstatus.

## Taken

| ID | Werkitem | Status | SHA / bewijs |
|----|----------|--------|--------------|
| REC-1 | DEC-132, register, DEC-062-addendum | OPEN | |
| REC-2 | D1: Tautulli-client volgt de gemonitorde server op detail en in "Nu aan het kijken"; P6; P8-kop | CODE CLOSED | code in d43ca8fa, tests in 57530d97. Gedragswijziging: een oude Tautulli-koppeling zonder `machineIdentifier` op een profiel met twee beheerde servers heeft geen gemonitorde server meer, dus beide detailpagina's tonen de Plex-kijkers en geen regel "kijkt nu". Dat is de veilige kant: eerst kon zo'n koppeling kijkers van een andere titel tonen. |
| REC-3 | D2 en D3: seeds uit het interactielog, capability `relatedHubs`, "Omdat je X kijkt" | CODE CLOSED | commit "feat(home): seeds voor Omdat je X keek uit het eigen kijklog". Bewijs: `affinity_engine_db_test.dart` groep `recentPositiveInteractions` (een rij per serie, alleen positief, binnen 30 dagen, nooit een ander profiel, geen uitgeschakelde importserver) en `discover_provider_test.dart` groep `seed rows from the interaction log` (titel per `completed`, geen fetch op een bron zonder `relatedHubs`, bekeken titels eruit, fallback bij een leeg log). Fixronde 1 (refactor naar `SeedRowsLoader` plus commit "fix(home): seedtitel volgt de serie..."): een serie met ongeziene afleveringen krijgt "kijkt", zes seeds parallel en op volgorde, dezelfde titel op twee servers geeft één rij, fallback ook als geen logseed oplost, tiebreaker op id, `recentSeeds` apart getest. Pleya Verify-regressie op het D2-geval volgt bij REC-9. |
| REC-4 | Lokaal partieel signaal bij een eindstop; importer vergelijkt gewichten | CODE CLOSED | commit "feat(smaak): partieel signaal bij een eindstop, importer vergelijkt gewichten". Bewijs: `interaction_recorder_test.dart` (een eindstop op 60 procent geeft één `partial` van 0,4 met genres; onder 50 procent, een gewone tik en een stop boven de kijkdrempel geven niets; een tweede stop binnen zes uur stapelt niet, een rij van zeven uur oud telt niet mee) en `tautulli_history_importer_test.dart` groep `cross-source window and weights` (een lokale partial slikt een voltooide Tautulli-view niet in, een lokale completed wel, een lokale partial slikt een partiële Tautulli-view in). Het signaal komt uit `PlaybackProgressTracker`, dus Plex, Jellyfin, Pleya Server en offline afspelen lopen via hetzelfde pad. Fixronde 1 (commit "fix(smaak): hervatten geeft een nieuwe eindstop, dedup volgt de scoringsscope"): na hervatten krijgt de nieuwe sessie een eigen eindstop (tracker-test "re-arms the final notification"); de zesuurscontrole gebruikt dezelfde scope als de scoring, dus een rij van een uitgeschakelde importserver of een ander profiel onderdrukt geen lokale partial. Bewust toegestaan: een partial en daarna een completed van dezelfde titel binnen zes uur geven samen 1,4; het venster houdt alleen partials onderling tegen. |
| REC-5 | Related hubs van seeds vier tot zes als kandidatenlaag | CODE CLOSED | commit "feat(smaak): related hubs van seeds vier tot zes voeden de kandidatenpool". De laag zit in `SeedRowsLoader`: de related hubs van seeds vier tot zes laden parallel met de rijen, hergebruiken de al opgehaalde seeds (geen tweede `fetchItem`) en kosten hooguit drie extra calls; een falende call kost alleen die seed. Ongeziene titels gaan als `hubItems` naar `buildRows`, niet als `excludeKeys`. Bewijs: `discover_provider_test.dart` groep `seed rows from the interaction log` ("seeds four to six feed the candidate pool", "a failing related hub for a candidate seed"). Meegenomen: de seed-identiteit bevat nu het soort, dus een film en een serie met dezelfde titel zijn twee seeds (test "a film and a series with the same title"). |
| REC-6 | Jellyfin-geschiedenisimport | CODE CLOSED | commit "feat(smaak): Jellyfin-kijkgeschiedenis als tweede adapter op het interactielog". `JellyfinHistoryImporter` leest over de eigen verbinding alleen de eigen gebruiker (`userId` van de connectie, DEC-062), pagina's van 200, hooguit vijf per sync, watermark op `LastPlayedDate` in `HistorySyncCursors` met `source = 'jellyfin'`. Bewijs: `jellyfin_history_importer_test.dart` (afgespeeld wordt `completed` met stabiel event-id, tweede sync stopt op de watermark na één pagina, aflevering telt voor de serie, hervatbaar tussen 50 en 90 procent is één `partial` van 0,4 ook na drie syncs, onder 50 niets, een lokale view binnen zes uur onderdrukt de import, ook per aflevering, eerste run leest hooguit `maxPagesFirstRun` pagina's), `recommendation_service_test.dart` groep `own-history importers` en `jellyfin_client_urls_test.dart` ("history import asks for its own user only"). Afwijkingen van het plan: de lokale match loopt op de aflevering en niet op de serie, zoals in de Tautulli-importer; de historiepagina vraagt `Genres,People,Studios` mee, anders heeft een film geen smaakkenmerken; de watermark schuift ook over ontdubbelde views; een epochcheck houdt een wisactie tegen. Fixronde 1 (commit "fix(smaak): geleende Jellyfin-verbindingen importeren niets..."): importers komen uit de eigen `ProfileConnection`-rijen, een verbinding die meer dan één profiel deelt importeert voor niemand, lener en uitlener allebei, omdat die Jellyfin-gebruiker de plays van beide draagt (DEC-132), niets tijdens het binden; een partial draagt de afspeeltijd; hooguit één sync per kwartier per profiel en server; een verdwenen serie telt als unresolvable. Fixronde 2 (commit "fix(smaak): DEC-132 noemt beide richtingen..."): een `lastSyncAt` in de toekomst (klok teruggezet) remt de sync niet; een Home-load tijdens het binden wacht begrensd op `awaitBindingSettle` en importeert daarna, in plaats van over te slaan. Tests in `jellyfin_history_importer_test.dart` groepen `play time, throttle, guards and resolution` en `ownJellyfinHistoryImporters`. |
| REC-7 | Acteurs- of regisseursrij met gedeelde cap | CODE CLOSED | commit "feat(home): rij Meer met acteur of Meer van regisseur bij warme smaak". Genre-, acteur- en regisseursrijen delen `kMaxAffinityRows` (2) plekken; een persoon moet boven `kPersonFeatureThreshold` (0,7) komen en bij gelijk gewicht wint het genre. Rij-ids `home.becauselike.actor.<slug>` en `home.becauselike.director.<slug>`, titel met de naam zoals de server hem spelt. Geen persoonsrij bij een koude smaak (REC-Q2, default nee). Bewijs: `personalized_rows_builder_test.dart` groep `person rows` (acteursrij met id en titel, regisseursrij, twee plekken met genre bij gelijkspel, sterke acteur boven zwak tweede genre, koude smaak zonder persoonsrij). Afwijking van het plan: de fixtures van de gelijkspel- en de acteurstest kregen eigen titels per kenmerk, omdat affiniteitsrijen geen titel herhalen en een gedeelde pool de latere rijen leeg liet. |
| REC-8 | i18n-controle, layoutblok-test, widgettest op de rijtitel | OPEN | |
| REC-9 | Volledige suite, `ci_checks`, drie Home-scenario's op de fixture, LIVE-ronde | OPEN | |

## Open punten buiten de taken

| ID | Punt | Status | Toelichting |
|----|------|--------|-------------|
| REC-P4 | Devicetoken verbruikt als `serverFriendlyName` of `version` na `register_device` faalt | DEFERRED | niet gemeten tegen `api2.py`; vraagt een clientfactory in `TautulliProvider.test` |
| REC-P7 | Eén `TautulliClient` per importpagina | DEFERRED | 25 clients per forward-pass, niet gevoeld |
| REC-P9 | Ziet een beheerd Plex Home-profiel `owned == true` in `isOwnerOrAdmin`? | LIVE ONLY | alleen op een echte server met een kindprofiel te toetsen |
| REC-PS1 | Pleya Server `GET /items/{id}/related` | OPEN (serverlijn) | zonder dit geen seed-rij voor Pleya Server-profielen |
| REC-PS2 | Pleya Server watch-state per gebruiker | OPEN (serverlijn) | zonder dit geen geschiedenisimport per profiel |
| REC-Q1 | `TvFocusRestoreHost` voor seed-rijen op TV | OPEN (productvraag) | default: nee |
| REC-Q2 | Persoonsrij bij niet-warme smaak | OPEN (productvraag) | default: nee |

## Verify en LIVE

| Platform | Scenario of ronde | Status | Bundel |
|----------|-------------------|--------|--------|
| tvOS-sim | `tvos.home.walk-rails` (regressie D2) | OPEN | |
| iOS-sim | `ios.home.northstar` (regressie D2) | OPEN | |
| macOS | `discover.layout.macos` (regressie D2) | OPEN | |
| iPhone of macOS, echt Plex-profiel met Tautulli en twee servers | seed-rijen, "Omdat je X kijkt", D1 | LIVE ONLY | |
| echt Jellyfin-profiel | import en warme rijen | LIVE ONLY | |
| Apple TV | D-pad over de acteursrij en de seed-rijen | HARDWARE ONLY | |
