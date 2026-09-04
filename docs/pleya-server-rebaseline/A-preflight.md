# A. Preflightrapport

Gemeten op 4 september 2026 tussen 16:58 en 17:30, in de worktree
`/Users/michelknoop/.supacode/repos/plezy-main/feat/pleyaserver`. Elke regel hieronder is een
meting; waar ik iets afleid staat dat erbij.

## A.1 Repository-state

| Meting | Waarde |
| --- | --- |
| Branch, HEAD | `feat/pleyaserver`, `5eebb83` "PS-9 gesloten, met de huishoudronde op de draaiende NAS", 4 sep 09:08 |
| Remote | `origin` (gitea `michelk/Plexflixnetwork`) en `github` (`michelknoop21/pleya`); `feat/pleyaserver` staat op beide op `5eebb83` |
| Werkboom | 1 gewijzigd bestand (`docs/sessions/2026-09-03.md`, 47 regels), 2 onbekende (`docs/qa/ps5-hardware-round.md`, `docs/sessions/2026-09-04.md`); geen merge, rebase of cherry-pick in uitvoering |
| `main` | `2433f74`, 4 sep 17:01, lokaal 3 vóór `origin/main` (`80934b9`) |
| Divergentie | `main` heeft 188 commits die deze branch mist; deze branch heeft 46 die `main` mist; merge-base `fb5128b` |
| Worktrees | 18, waarvan 12 onder `~/.supacode/repos/plezy-main/` en 6 onder `/Volumes/SSD/Projects/PlexFlixNetwork/`; `pleya-tvbuild` staat detached op `424c43e` |

Drie worktreenamen zijn geen ontwikkelstroom. `carplay`, `feats/ebooks` en `feat/testplane`
wijzen alle drie op main-commit `183d694` (31 augustus) en hebben nul eigen commits. Er is
geen CarPlay-code op enige branch (`git grep -il carplay` over alle refs is leeg), en de
e-bookstroom heet `feat/ebooks`.

De ongepushte lokale branch `fix/tvos-foc1` (`112754f`) zit inhoudelijk in `main` via de merge
`80934b9`. `feat/netflix-mobile` staat lokaal 9 commits vóór `origin`.

`worktree-pleya-web-ps4e` (`4368635`, 24 augustus) is een oudere kopie van deze branch: alle 37
commits zitten inhoudelijk in `feat/pleyaserver` (de hubfix `64efddd` daar is `2c214fd` hier), de
`pleya_web`-diff tussen beide is leeg, en de branch mist PS-9 volledig. Opruimen.

## A.2 Recente wijzigingen per gebied

**`pleya_server/` (Go).** 42 gewijzigde bestanden in `internal/` sinds de merge-base. PS-9 landde
tussen 24 augustus en 4 september: migratie `0007_users_sessions.sql`, `handlers_users.go`,
`handlers_sessions.go`, `auth/sessions.go`, `auth/revocation.go`, `auth/users.go`, plus de tests
`users_test.go` (427 regels), `sessions_test.go` (420) en `authorize_test.go` (888). De hubfix
`2c214fd` (24 augustus) gaf `continue_watching` en `next_up` echte queries in
`catalog/store_hubs.go`. Op `main` is er nul serverwerk.

**`pleya_web/`.** Sinds PS-3W alleen `schema.d.ts` opnieuw gegenereerd na de PS-9-toevoegingen
(`5285848`). Geen nieuwe route, geen nieuw component. Het gebundelde `dist/` in
`pleya_server/internal/web/` is de PS-3W-build.

**Flutter-clients op deze branch.** `lib/profiles/profile.dart` kreeg `Profile.pleyaServer` en
`ProfileKind.pleyaServer` (alleen hier, niet op `main`), `pleya_wire.dart` kreeg
`PleyaCapabilities.sessions`, `pleya_server_device_identity.dart` is nieuw (DEC-069).

**Flutter-clients op `main` sinds de merge-base**, in vijf blokken: Pleya Verify Core 1.0 (merge
`839cbf2`, hele `pleya_verify/`-boom en `lib/automation/`), Pleya Unified TV 2026 fase 0 tot 9
(`lib/media/unified/`, `lib/services/unified_catalog/`, `tv_home_projection_provider`,
`tv_discovery_landing_provider`, `NavigationTabId.movies/.series`), de fysieke tvOS-correctieronde
(BACK1, FOC1, ART1, CAT1-4, LAND2-4, OVR1-2, LIB1-6, `tv_content_route_registry.dart`), branding
en fastlane (builds 243 tot 248), en losse fixes.

**`feat/netflix-mobile`** (32 commits vóór `main`): iOS Unified 2026 fase 1 tot 4, met
`mobile_home_screen`, `mobile_catalog_screen`, `mobile_landing_screen`, `mobile_search_body`,
`mobile_shell_scope`. De two-dot diff met `main` op `lib/services/pleya_server*` en
`lib/media/server_capabilities.dart` is leeg: de branch raakt het servercontract niet.

**`feat/ebooks`** (23 commits vóór `main`): vier boekenschermen tegen goedgekeurde goldens,
`lib/books/` met `BooksSource` achter `--dart-define=PLEYA_BOOKS=true`,
`PrimaryMobileDestinationPolicy`, vijf Verify-scenario's. Nul Go, nul SQL, nul protocol.

## A.3 De DEC-nummerbotsing

Vijf branches tellen onafhankelijk door vanaf DEC-062. Dit is de bron van het grootste
integratierisico en de reden dat dit pakket nergens een nieuw DEC-nummer claimt.

| Branch | Hoogste | Eigen reeks |
| --- | --- | --- |
| `main` | DEC-091 (090 en 092 ontbreken) | 063 tot 091: TV Unified, Verify, brand |
| `feat/pleyaserver` | DEC-093 | 063 tot 073 server (PS-9, DEC-073), 093 e-books |
| `feat/netflix-mobile` | DEC-095 | 090 tot 095 iOS Unified |
| `feat/ebooks` | DEC-094 | 094 mobiele navigatie (was 069, al één keer hernummerd) |
| `github/claude/peaceful-keller-rmjwfy` | DEC-070 | TV-lijn vóór hernummering |

Harde dubbelen op dit moment: 063 tot 073 (main tegenover server), 091 (main tegenover iOS), 093
(server tegenover iOS), 094 (ebooks tegenover iOS). De eerste nummers die op geen enkele branch
bezet zijn: 096 en verder. De regel voor dit traject staat in deel M.

## A.4 Wat de code doet en de documentatie niet, of andersom

| Plaats | Wat er staat | Wat er is |
| --- | --- | --- |
| `pleya_server/internal/api/handlers_media.go:29-32` | "De width-parameter wordt gelezen en levert het origineel" | `width` wordt nergens gelezen; `minimum: 1, maximum: 4096` uit de YAML wordt niet gehandhaafd |
| `docs/pleya-protocol/v1/openapi.yaml:619-620` | artwork Cache-Control "Lang, want artwork is onveranderlijk" | code zet `max-age=300, must-revalidate` en legt in `handlers_media.go:66-71` uit waarom artwork niet onveranderlijk is |
| `0003_work.sql:44-46` | scantellers "zichtbaar in de metrics" | geen metrics-endpoint, geen metricsbibliotheek in `go.mod` |
| `0002_catalog.sql:146-149` | `content_fingerprint` draagt relocatie tussen mounts | geen Go-code leest of schrijft de kolom |
| `cmd/pleya-server/main.go:1-6` | "geen streaming, geen kijkstatus, geen gebruikersmodel" | alle drie bestaan |
| `pleya_web/README.md` | "Het accesstoken staat alleen in het geheugen" | `auth/tokens.ts` bewaart het in `sessionStorage` en legt uit waarom geheugen-alleen fout was |
| `pleya_web/tests/e2e/flow.spec.ts` | asserteert dat "Verder kijken" nul keer voorkomt | de server levert de hub sinds `2c214fd`; de test bewaakt het oude gat |
| `docs/pleya-server-ps14-proposal.md` beslissing 1 | client toont onbekende bibliotheeksoort | door het voorstel zelf ingetrokken: `browse.dart:36-51` filtert al, test `pleya_server_browse_test.dart:44` |
| `docs/assets/tvos-unified/approved-2026-09-03/00-overzicht.md` (main) | "candidate, niet goedgekeurd" | `docs/tvos-redesign-09-25-approved.md` op main: APPROVED DESIGN TARGET, 3 september |
| `docs/pleya-server-architecture.md` hoofdstuk 23 | PS-11A is de volgende fase | er is geen fasetabel voor PS-11A in dat document; de definitie staat in `docs/pleya-server-masterplan-proposal.md` 16.3 |

Waar code en documentatie botsen geldt in dit pakket de code plus de goedgekeurde DEC's.

## A.5 Toetsbare stand van de gates

| Gate | Stand | Bewijs |
| --- | --- | --- |
| PS-5 criterium 4 (hardware) | open, uitgesteld met startvoorwaarden | `docs/qa/ps5-hardware-round.md` (ongecommit), DEC-064 |
| PS-9 | gesloten 4 september | `STATUS.md` "Volgende stap", NAS-ronde met `POST /users`, `PUT /users/{id}/permissions`, `DELETE /sessions/{id}` |
| Protocolvenster | dicht | laatste opening DEC-068 voor PS-9; `scripts/check_protocol.sh` is de poortwachter |
| PS-14 | goedgekeurd, niet vrijgegeven | DEC-093 en ps14-proposal beslissing 6; nul Go-code |
| CI voor `pleya_server` en `pleya_web` | afwezig | geen workflow in `.github/workflows/` noemt een van beide; alle verificatie is `scripts/verify-local.sh` (72 controles) en handmatig |

## A.6 Wat een volgende sessie niet opnieuw hoeft te meten

De branchsurvey in deel B, de endpointlijst en tabelinventaris in deel F, de routes en componenten
in deel G. Wat wél opnieuw gemeten moet worden vóór slice S0 start: de divergentie met `main`
(die groeit dagelijks) en de hoogste DEC per branch.
