# Pleya roadmap

**Authority:** this file owns cross-project priority and execution order for the existing Pleya product line.
Detailed status and evidence remain in the existing domain registers and masterplans.

**Explicitly out of scope:** rebuilding the client from the ground up. That work is not a milestone, dependency, parallel track, or release gate in this roadmap.

## Current direction

1. Reconcile the current source/release/status baseline.
2. Close correctness, permission/profile and concrete library bugs in the existing app.
3. Finish only the currently valid UI gaps; do not rebuild already-landed surfaces.
4. Run real-account, simulator and physical-device acceptance for the chosen release scope.
5. Release exactly the accepted SHA/archive.
6. Then choose one next product increment; Pleya Server/Web/e-books continue only through their existing phase gates and dependency graph.

## Roadmap rules

- Every implementation task must name one roadmap work-package ID before code starts.
- PRs and handoffs use `Roadmap: <ID>`.
- Work that does not fit an ID does not silently become a new side track. First record `Roadmap deviation: <approved decision/proposal>`.
- Open P0 work precedes P1/P2/P3 unless lower-priority work is demonstrably independent and does not delay review/release of the primary stream.
- WIP limit: one primary implementation stream plus at most one truly independent parallel implementation. Design/spec work may run ahead only if it does not create an unreviewed implementation pile.
- Security, data-loss, regression and release-blocking hotfixes may interrupt the order. Reconcile this roadmap and the owning register in the same PR or the next documentation commit.
- This roadmap owns order; domain registers own detailed state. Do not create a second detailed status administration here.
- Changing priority, order, scope, or milestones is an authority change and requires an explicit roadmap diff plus independent substantive review before merge.
- Code on `main`, simulator evidence, hardware evidence and publication are separate states.
- UI changes are executed by Opus and get a separate visual review against the current northstar/DEC.

## Work packages

| ID | P | Track | Work package | Current state |
| --- | --- | --- | --- | --- |
| REG-01 | P0 | Regie | Eén actuele uitgangsstand | Status herijken |
| REG-02 | P1 | Regie | Oude branches en PR's reconciliëren | Status herijken |
| REG-03 | P0 | Regie | Release-identiteit en distributiestatus | Status herijken |
| A-01 | P0 | Bestaande app | Verify-runner: time-outs en simulatorselectie | Open PR |
| A-02 | P0 | Bestaande app | Rechten, geleende verbindingen en profielen | Bewijs afronden |
| A-03 | P1 | Bestaande app | Bibliotheek-snelkiezer bewaart selectie | Open issue |
| A-04 | P1 | Bestaande app | Verborgen Plex-bibliotheek op TV | Open issue |
| A-05 | P1 | Bestaande app | iPhone-detail DEC-140 | Bewijs afronden |
| A-06 | P1 | Bestaande app | Home, landingen, catalogus en filters | Volgens register open |
| A-07 | P1 | Bestaande app | Bronkeuze bij meerdere servers | Bewijs afronden |
| A-08 | P1 | Bestaande app | Mijn Pleya, lijst/downloads/meldingen en contextmenu | Volgens register open |
| A-09 | P0 | Bestaande app | Login, profielkeuze en PIN | Volgens register open |
| A-10 | P1 | Bestaande app | Live TV, Liquid Glass en mobiele speler | Bewijs afronden |
| A-11 | P1 | Bestaande app | tvOS focus, Menu en shell-routes | Bewijs afronden |
| A-12 | P1 | Bestaande app | Top Shelf, 4K en tvOS scrubbing | Bewijs afronden |
| A-13 | P1 | Bestaande app | Zoeken en filtergedrag met echte servers | Bewijs afronden |
| A-14 | P1 | Bestaande app | iCloud-voorkeurensync | Bewijs afronden |
| A-15 | P1 | Bestaande app | Aanbevelingen, historie en Tautulli | Bewijs afronden |
| A-16 | P1 | Bestaande app | Activiteit: ACT1 | Besluit nodig |
| A-17 | P1 | Bestaande app | Desktop/iPad unified afronding | Bewijs afronden |
| A-18 | P0 | Bestaande app | Eindacceptatie en releasebundel | Gepland |
| C-01 | P1 | Server | S2.5 configuratiebibliotheken overnemen | Volgens register open |
| C-02 | P1 | Server | S2.6 migratie en protocolvenster 2 sluiten | Volgens register open |
| C-03 | P0 | Server | Beheerfase PS-11A en vrijgave PS-14 | Status herijken |
| C-04 | P1 | Server | Loudness D3-D5 en client-consumptie | Status herijken |
| C-05 | P2 | Server | Resterende 26-slice totaalroadmap | Gepland |
| D-01 | P2 | E-books/routes | Bestaande e-bookbranch en acht schermen | Status herijken |
| D-02 | P2 | E-books/routes | Vier e-bookuitbreidingen uit northstar | Volgens register open |
| D-03 | P2 | E-books/routes | Eigen routes muziek, boeken en overige typen | Besluit nodig |
| E-01 | P1 | Commercieel/site | Free/Pro en prijsbesluit | Voorstel, niet besloten |
| E-02 | P0 | Commercieel/site | Licenties en publicatiegereedheid | Status herijken |
| E-03 | P2 | Commercieel/site | Aankoop, herstel en Pro-toegang | Gepland |
| E-04 | P1 | Commercieel/site | Website, screenshots en release-informatie | Status herijken |
| F-01 | P3 | Optioneel | Apple Intelligence: kleine zoekfilter-MVP | Gepland |
| F-02 | P3 | Optioneel | Nieuwe ideeën zonder bestaande release te blokkeren | Gepland |

## Execution phases

### Phase 0 — Authority and current baseline

- Make this roadmap the canonical cross-project ordering layer.
- Reconcile STATUS and domain registers against current `main`.
- Classify stale/open branches and PRs as unique work, already landed, or superseded.
- Finish A-01 (PR #111) through current review and CI before relying on heavy Verify runs.
- Every next task must carry a roadmap ID.

### Phase 1 — Correctness and blockers

- A-02 permissions/profiles/borrowed connections.
- A-03 and A-04 from issue #112.
- A-09 login/profile/PIN where still open.
- A-16 only through correct authorization semantics or a protocol-faithful test identity; never weaken production checks to make a test pass.

### Phase 2 — Valid UI remainder

Finish the currently valid app surfaces and evidence only: Home/landings/catalog/filters, source picker, context menus, Mijn Pleya, lists/downloads/notifications, Live TV/player, Liquid Glass, desktop/iPad regression boundary, and tvOS focus/Menu/routes/scrubbing/Top Shelf/4K/overscan. The latest approved DEC/northstar wins.

### Phase 3 — Real-world acceptance

Bundle real-server/account and physical iPhone/Apple TV evidence. Include the applicable iCloud, recommendation/history/Tautulli and hardware-open cases. Do not upgrade status based only on old or fixture-limited runs.

### Phase 4 — Exact release bundle

Select final SHA and archive, record build/config/archive identity, close applicable review/release gates, and distribute exactly that accepted candidate.

## Pleya Server/Web order

First close S2:
1. C-01 / S2.5 configuration-library takeover with stable ids/slugs.
2. C-02 / S2.6 NAS-fixture migration proof and protocol-window-2 closure.

Then reconcile C-03 (PS-11A/PS-14/P5) against the latest binding decisions before opening later work.

After that follow `docs/PLEYA-SERVER-MASTERLIST.md` and its dependency graph:
- S3-S6 catalog/books/artwork/search/read progress;
- S14/S16 Flutter client support and MCP on the expanded contract;
- S7-S13 Pleya Web;
- S17/S18/S23 PlaybackPlan/transcoding/downloads;
- S19-S21 collections/personal/realtime;
- S22 metadata providers after S4 when released;
- S24/S25 hardening/observability/backup/restore/upgrades;
- S15 final hardening/acceptance/Plex-off gate;
- PS-12 only as a later explicit choice.

Loudness D5 gets its own protocol window only after D1-D4 are proven; it does not ride on S2.

## E-books and other routes

Do not rebuild the existing e-book work. Reconcile the branch against current `main`, current shell/navigation and server gates; keep valid work and build only missing surfaces. For music/books/photos/unknown library kinds choose an explicit destination or unsupported state instead of silently opening the wrong catalog.

## Commercial/site order

Free/Pro and prices remain proposals until explicitly decided. Order:
1. product matrix/prices;
2. publication/license/account check;
3. purchase/restore;
4. entitlement/expiry/revocation/offline behavior;
5. website/store copy matching the actually released build.

Payment entitlement never substitutes for media-server administration rights.

## October work windows

| Window | Primary result | Limited parallel work |
| --- | --- | --- |
| 1-2 Oct | Roadmap authority, current baseline, A-01/PR111 gates | decisions/status only |
| 5-9 Oct | permissions/profiles, issue #112 bugs, valid UI remainder | at most one independent server package |
| 12-16 Oct | real account/simulator/hardware acceptance | C-02 after C-01 or design/spec without shared code owner |
| 19-23 Oct | release bundle and actual distribution if gates pass | website/release copy aligned to that build |
| 26-30 Oct | choose and close one next product increment | one released Server/Web/e-book package |

These are work windows, not guaranteed completion dates. Missing evidence or a regression moves the window; evidence is not planned away.

## Detail authorities

- Existing app release/evidence order: `docs/unified-2026-closure.md`
- iOS status: `docs/ios-unified-implementation-register.md`
- tvOS status: `docs/tvos-redesign-register.md` and `docs/tvos-fysieke-correctieronde.md`
- Design authority: `docs/DESIGN-INDEX.md` and the referenced approval/DEC documents
- Server status/order: `docs/PLEYA-SERVER-MASTERLIST.md` and `docs/agents/server.md`
- Decisions: `docs/DECISIONS.md`

## Change rule

Any proposal to change roadmap scope/order/priority must show:
1. which work-package IDs change;
2. why the current order no longer fits;
3. dependency/release impact;
4. what is deferred or displaced;
5. Michel's decision when it is a product choice;
6. an independent substantive review of the roadmap diff before merge.