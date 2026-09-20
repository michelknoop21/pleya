# L. Verify- en testmatrix

## L.1 Wat er al is, en wat de gate wordt

| Laag | Vandaag | Wordt | Gate |
| --- | --- | --- | --- |
| Go unit en pakket | 237 tests, 6 pakketten tegen echte Postgres, `testsupport.Pool` per test een schema | plus per slice; migratietest op de NAS-fixture | CI-job `pleya-server` (S0) |
| Go end-to-end | `verify-local.sh` (72 controles, ffmpeg in de image), `verify-protocol.sh` | secties voor beheer, boeken, artwork, MCP | lokaal vóór elke slice-afsluiting; in CI de protocolcheck |
| Protocol | `check_protocol.sh` (structuur, refs, enum-markering, 36 fixtures, negatieve payloads) | fixtures per venster; fake-server-contracttest | CI-job `protocol` (S0) |
| Web unit en component | vitest, 16 bestanden, 112 asserties | per primitief en per pagina | CI-job `pleya-web` |
| Web e2e | Playwright 28 tests tegen de echte binary, axe op 5 breedtes, mobile-project | per surface; als member én als owner; boeken- en EPUB-fixtures in de stack | CI-job `pleya-web` |
| Web screenshots | `scripts/screenshots.ts` 5 breedtes × 3 thema's | plus vergelijking met de northstar als reviewbewijs (geen pixelgate) | review per slice |
| Flutter | 4697 tests groen op de gepinde SDK, `test/pleya_server/` 214 | plus S14-tests; `ci_checks.sh` blijft de pre-commit | bestaande CI |
| Pleya Verify | 24 scenario's, macOS/iOS-sim/tvOS-sim, fake-server | plus contracttest fake tegen YAML, één scenario voor de boekenbron, journeys 2 en 6 | `pleya-verify.yml` (bestaand op main) |
| Hardware | PS-4 bewezen; PS-5 criterium 4 open | PS-5-ronde vóór release; journey 2 op Apple TV | N |

## L.2 Backend

| Gebied | Test | Slice |
| --- | --- | --- |
| Migraties | fixture schema 7 → 0013; ids, slugs, watch_states, item_count intact; `readyz` groen; checksum-weigering blijft | S0 en per migratie |
| Auth en autorisatie | drie-rollen-tabel over alle routes uit de mux; API-token scope ≤ rol; intrekking binnen 2 s incl. tokens | S1 |
| Settings | grenzen, hot reload, `.env` als standaard, databasewaarde wint | S1 |
| Libraries en storage | CRUD, `confirm`, roots alleen uit opsomming, overname idempotent, soort vast bij inhoud | S2, S3 |
| Scanner | bestaande 17 tests ongewijzigd groen na dispatch; EPUB-fixtures (5); annuleren; backoff; sidecarparser (5 varianten); ffprobe-teller nul in een boekenbibliotheek | S2, S3, S4 |
| Artwork | ladder, single-flight, decodeerfout, cache na herstart, sterke `ETag` | S4 |
| Search en filters | injectie, apostrof, facettellingen, `EXPLAIN` gebruikt de index, cursor stabiel onder filter | S5 |
| Streaming en bytes | bestaande range-tests; EPUB-route 206 bij gelijke validator, 200 bij afwijkende; streamtoken opent geen boek | S3 |
| Progress | revisieconflict, `finished`, locatorvorm, hydratie in één query | S6 |
| MCP | `initialize`, `tools/list` per rol, drie tools, injectietitel als tekst, `confirm`, `mcp_enabled` uit | S16 |
| Protocol | fixtures per nieuw schema; negatieve payloads (open body, onbekende sleutel, scope boven rol) | per venster |

## L.3 Web

| Gebied | Test | Slice |
| --- | --- | --- |
| Shell | vijf breedtes zonder overloop, tabbalk met en zonder boekenbibliotheek, Beheer-pil op rol, axe | S7 |
| Componenten | elk primitief met de staten uit scherm 16; cover-fallback; skelet | S7, S9 |
| Consumer | Home met vooraf gezette kijk- en leesstatus; landings; catalogus met filters; zoeken gesectioneerd en leeg; detail; Mijn Pleya | S8, S9 |
| Beheer | als member 404 en geen beheeraanvraag; als owner elk scherm met een echte mutatie; sleutelrotatie logt uit | S10 |
| Setup | lege database tot Home (journey 1) | S11 |
| Reader en speler | locator round-trip; start, seek, hervatten; MKV-melding | S12, S13 |
| Screenshots | 5 breedtes per route naast het northstar-beeld in het sessielogboek | elke webslice |

## L.4 Cross-client

Stagingregel (VRAGENLIJST 61): NAS-data is een dataset, geen mutable testomgeving. Journeys op de
NAS draaien tegen een geïsoleerde stagingdatabase met een dump vooraf, media read-only of via
snapshot, eigen config en secrets; destructieve journeys alleen tegen disposable stagingstate.

Alleen waar het contract geraakt wordt: `PleyaServerClient` tegen een nieuwe server met elke
capability aan en uit (S14), de fake-server tegen de YAML (S0), en de app op macOS plus
iOS-simulator door journey 2 en 3 (Verify). Een oude app (build 248 van `main`) tegen de nieuwe
server moet bladeren, afspelen en kijkstatus melden zonder verschil: dat is de test op de
achterwaartse compatibiliteit van elk venster en draait in S15 met de bestaande TestFlight-build.

## L.5 Golden journeys

Elke journey is een script (bash met `curl` en `jq` voor de serverkant, Playwright voor web,
Verify voor de app) dat op een lege wegwerpstack begint en met één exit-code eindigt. Ze staan
in `pleya_server/scripts/journeys/` en draaien in S15 en daarna bij elke release.

| # | Journey | Stappen | Bewijs |
| --- | --- | --- | --- |
| 1 | Setup tot afspelen | lege database → setupcode uit de log → eigenaar → root kiezen → bibliotheek Films → scan → Home toont titels → film start in de browser en seekt | Playwright, `POST /watch-state` zichtbaar in de netwerklaag |
| 2 | Serie naar Next Up | aflevering 1 kijken tot 95% via de app (Verify, macOS) → `next_up` toont aflevering 2 → web toont Volgende afleveringen → Apple TV toont dezelfde rij | Verify-bundel plus web-screenshot plus tvOS-foto (hardware) |
| 3 | Boeken end-to-end | bibliotheek Boeken via beheer → scan → `GET /ebooks?q=` vindt de titel → web detail → downloaden (sha256 klopt) → webreader opent → `POST /reading-state` → tweede client ziet Verder lezen met dezelfde fractie → lid zonder recht krijgt 404 | Playwright plus `curl` |
| 4 | Rechten | admin maakt gebruiker met alleen Films → gebruiker ziet één bibliotheek in web en app → 404 op een Series-item-id → MCP met leestoken van die gebruiker ziet hetzelfde | `curl`, Playwright, MCP-client |
| 5 | Herstart | server herstart midden in een scan → job wordt opnieuw opgepakt → kijk- en leesstatus, instellingen en tokens ongewijzigd → `readyz` groen | `verify-local.sh`-sectie |
| 6 | Verlopen en ingetrokken auth | verlopen accesstoken → refresh → hergebruik van oud refreshtoken trekt de keten in → web landt op inloggen zonder verlies van de route → API-token ingetrokken → MCP geeft 401 | Playwright plus `curl` |
| 7 | Opslag weg en terug | root unmounten tijdens scan → scan slaat over, niets ontbrekend → beheer toont de fout met de root → mount terug → recheck → volgende scan normaal | `verify-local.sh`-sectie met een tijdelijke mount |
| 9 | Transcode | toestel dat HEVC niet aankan vraagt een plan → transcode-sessie → speelt en seekt → sessie ruimt op na afsluiten; derde sessie geweigerd | Playwright met hls.js, `curl` |
| 10 | Download en sync-back | app downloadt een film (digest klopt) → offline kijken → online: kijkstatus terug met `backlog` | Verify (macOS) plus `curl` |
| 11 | Verzameling delen | Michel maakt een verzameling, deelt met Sanne → Sanne ziet hem in web en app → Kids niet → afspeellijst speelt op volgorde | Playwright, Verify |
| 12 | Realtime | scan starten → voortgang komt via de websocket zonder poll → verbinding weg → `since=` dicht het gat | Playwright met netwerkbreuk |
| 13 | Back-up en restore | back-up → hersteltest groen → titel toevoegen → restore → titel weg, rest gelijk → upgrade over twee schemaversies op de fixture | `verify-local.sh`-sectie |
| 14 | Metadata-match | nieuwe bibliotheek met gemengde naamgeving → automatische match met percentage → ambiguë titel staat op de lijst, niet verkeerd gekoppeld → correctie → drie providerrondes → correctie staat nog; artwork gekozen uit kandidaten staat op de kaart | `curl` met opgenomen providerantwoorden |
| 8 | Agent beheert | Claude Code via MCP: bibliotheek toevoegen, scan starten en volgen, gebruiker met rechten aanmaken, instelling wijzigen, verwijderen zonder `confirm` geweigerd; auditlog toont elke stap | MCP-clientscript |
