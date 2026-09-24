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
| REC-4 | Lokaal partieel signaal bij een eindstop; importer vergelijkt gewichten | OPEN | |
| REC-5 | Related hubs van seeds vier tot zes als kandidatenlaag | OPEN | |
| REC-6 | Jellyfin-geschiedenisimport | OPEN | |
| REC-7 | Acteurs- of regisseursrij met gedeelde cap | OPEN | |
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
