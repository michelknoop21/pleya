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
| REG-01 | P0 | Regie | Eén actuele uitgangsstand, inclusief vensterdekking per platform | Status herijken |
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
| A-17 | P1 | Bestaande app | Desktop/iPad unified afronding en afzonderlijke platformdekking | Status herijken; geen bewijs van volledige afronding |
| A-18 | P0 | Bestaande app | Eindacceptatie en releasebundel | Gepland |
| C-01 | P1 | Server | S2.5 configuratiebibliotheken overnemen | Volgens register open |
| C-02 | P1 | Server | S2.6 migratie en protocolvenster 2 sluiten | Volgens register open |
| C-03 | P0 | Server | Beheerfase PS-11A en vrijgave PS-14 | Status herijken |
| C-04 | P1 | Server | Loudness D3-D5 en client-consumptie | Status herijken |
| C-05 | P2 | Server | Volledige S0-S25-dekking, inclusief Web consumer, beheer-GUI en setup | Gepland; detailstatus in servermasterlijst |
| D-01 | P2 | E-books/routes | Bestaande e-bookbranch en schermen | Status herijken |
| D-02 | P2 | E-books/routes | Resterende e-bookuitbreidingen uit northstar | Volgens actueel branchmanifest vast te stellen |
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
- REG-01 must establish the completeness map below before any whole-redesign completion claim. Already identified independent fixes need not wait for the entire inventory.

### Phase 1 — Correctness and blockers

- A-02 permissions/profiles/borrowed connections.
- A-03 and A-04 from issue #112.
- A-09 login/profile/PIN where still open.
- A-16 only through correct authorization semantics or a protocol-faithful test identity; never weaken production checks to make a test pass.

### Phase 2 — Valid UI remainder

Finish the currently valid app surfaces and evidence only: Home/landings/catalog/filters, source picker, context menus, Mijn Pleya, lists/downloads/notifications, Live TV/player, Liquid Glass, desktop/iPad unified work, and tvOS focus/Menu/routes/scrubbing/Top Shelf/4K/overscan. Check every applicable existing platform separately; a shared widget or an iPhone screenshot does not prove iPad, Android, Android TV, macOS, Windows or Linux completion. Preserve explicitly excluded platform presentations until their own design decision changes. The latest approved DEC/northstar wins.

### Phase 3 — Real-world acceptance

Bundle real-server/account and physical-device evidence for the release targets. Include the applicable iCloud, recommendation/history/Tautulli and hardware-open cases. Do not upgrade status based only on old or fixture-limited runs.

### Phase 4 — Exact release bundle

Select final SHA and archive, record build/config/archive identity, close applicable review/release gates, and distribute exactly that accepted candidate. A release may contain an explicitly bounded subset; do not call that completion of all app redesigns or of the full Server/Web product.

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

This list groups scope, not a new serial dependency chain. In particular, the existing graph allows S7 after S0, S10 after S7+S1+S2, and S11 after S10+S2. The basic server management GUI does not have to wait for S14, the consumer player, or completion of every server slice. Existing phase approvals and the WIP limit still apply. S8 waits for S7+S4+S5; S9 for S7+S3+S6; S12 for S9+S6; S13 for S8. P5 remains a prerequisite for the reading-state contract.

Loudness D5 gets its own protocol window only after D1-D4 are proven; it does not ride on S2.

## E-books and other routes

Do not rebuild the existing e-book work. Reconcile the branch against current `main`, current shell/navigation and server gates; keep valid work and build only missing surfaces. Use the actual branch manifest and later commits, not an old count of built or missing screens in DESIGN-INDEX. For music/books/photos/unknown library kinds choose an explicit destination or unsupported state instead of silently opening the wrong catalog.

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
| 1-2 Oct | Roadmap authority, current baseline, per-platform/window coverage map, A-01/PR111 gates | decisions/status only |
| 5-9 Oct | permissions/profiles, issue #112 bugs, valid UI remainder | at most one independent server package |
| 12-16 Oct | real account/simulator/hardware acceptance | C-02 after C-01 or design/spec without shared code owner |
| 19-23 Oct | release bundle and actual distribution if gates pass | website/release copy aligned to that build |
| 26-30 Oct | choose and close one next product increment | one released Server/Web/e-book package; S7/S10/S11 are explicit candidates after their prerequisites |

These are work windows, not guaranteed completion dates. Missing evidence or a regression moves the window; evidence is not planned away. They do not promise delivery of all 46 Web designs or the full Server completion scope within October.

## Completeness: all existing app redesigns and Server/Web GUI

Owner clarification, 30 September 2026: include every remaining window and behavior from the redesigns of the existing apps, the complete remaining Pleya Server scope, its consumer webclient and its management GUI. The ground-up client rebuild remains excluded.

### REG-01: complete coverage, not just an umbrella label

Use the existing domain registers as the detailed record. Reconcile both directions: approved designs to implemented routes/components, and existing routes/dialogs to a valid design or an explicit retained/unsupported decision. Include screens, sheets, dialogs, subviews, context menus, player panels and functional states, not only top-level pages.

Each applicable window must identify: platform and viewport/input mode; approved mockup/DEC; implementation owner and branch/commit; owning roadmap ID and domain task; missing backend/API dependency; independent code/visual review; test or Verify/browser evidence; physical-device evidence where applicable; release identity. Keep design approval, built-on-branch, merged, tested, visually matched, device-accepted and published separate. Unknown is not DONE. A mockup does not prove an implementation, and a running screen does not prove it matches the approved redesign.

| Existing target | Owning scope | What must be established separately |
| --- | --- | --- |
| iPhone | A-05 to A-10, A-13 to A-16 | 21-screen iOS set plus Home comps and later approved overrides, including DEC-140 and Liquid Glass; include all nested windows |
| iPad | A-17 plus applicable A-items | unified-desktop-ipad work, current presentation, portrait/landscape and multitasking; do not assume iPhone work already landed here |
| macOS | A-17 plus applicable A-items | desktop shell, sidebar, windows/panels, keyboard/mouse and responsive sizes |
| Windows | A-17 plus applicable A-items | explicit applicability and runtime evidence; a macOS pass is not Windows evidence |
| Linux | A-17 plus applicable A-items | explicit applicability and runtime evidence; portable tests are not a complete visual acceptance |
| Apple TV / tvOS | A-11/A-12 plus applicable A-items | approved TV sets and later corrections; focus, Menu, remote, player panels, safe areas and real hardware |
| Android mobile/tablet | applicable A-items, coordinated by REG-01 | identify the approved or intentionally retained design and affected shared components; no automatic extension of Apple-only Liquid Glass |
| Android TV | A-11/A-12 where applicable, coordinated by REG-01 | shared TV surface plus Android-specific playback, downloads and remote behavior; tvOS evidence is insufficient |
| E-book windows in existing clients | D-01/D-02 plus C-05/S14 | actual branch manifest, missing windows, backend availability and integration into the current shell |

An absent platform-specific design decision is a design gap to record, not permission to invent a new redesign. Valid already-built work is retained. Opus owns graphical implementation and a separate visual review. No whole-app redesign closes while an applicable window is unowned, unverified, or silently dropped; explicit deferrals remain visible and distinguish partial release from full completion.

### C-05: Server/Web window-to-task coverage

The approved Web manifest is `docs/assets/pleya-web-northstar/README.md`: 46 design entries, 91 images, approved 4 September 2026. Some entries are states/reference sheets rather than independent routes. This is design coverage of that approved scope, not proof that every implementation or future subdialog exists. Task status remains in `docs/PLEYA-SERVER-MASTERLIST.md`; behavioral/API detail remains in `docs/pleya-server-rebaseline/D-northstar-spec.md`.

| Web design IDs | Surface | Existing implementation tasks / slices |
| --- | --- | --- |
| 01 | Home | S7, S8.1; reading/book rows additionally S9.4 and S6 |
| 02, 03 | Films and Series landings | S8.2 after S7/S4/S5 |
| 04 | Books landing | S9.2 after S7/S3/S6 |
| 05 | Catalog and filters | S8.3; books variant S9.2; shared controls S7 |
| 06, 07 | Search and no results | S8.4; books/authors S9.4; S5 |
| 08, 09 | Film and series detail | S8.5; playback S13; later related server capabilities separately |
| 10 | Book detail | S9.3; reader S12; S3/S6 |
| 11 | My Pleya | S8.6; later personal/device capabilities as specified |
| 11b | Downloads overview | S23.4; backend and app delivery S23.1-S23.3 |
| 12, 13, 14, 15, 16 | Login, empty, offline, loading and card states | S7.3/S7.4/S7.6, S8.6; role-specific behavior included |
| 17, 18 | Collections and playlists | S19.3 plus S19 backend and client tasks |
| 19 | History, favorites and ratings | S20.4 plus S20 backend and client tasks |
| 20, 21, 22, 23 | Admin overview, libraries, editing and delete confirmation | S10.1/S10.2; S1/S2 |
| 24, 25 | Admin storage, scans and jobs | S10.3; S2 |
| 26, 27 | Admin users, permissions and devices | S10.4; S1 and existing user/session contracts |
| 28, 29, 30, 31, 32 | Admin media/streaming, metadata/artwork, network, security, diagnostics | S10.5 baseline; later S18/S22/S23/S24 capabilities separately |
| 33, 34 | Mobile admin index, agents and API tokens | S10.6; agent functionality S16.4 |
| 35 | Admin maintenance, backup, restore and upgrade | S25.6 plus S25 backend tasks |
| 36 | Admin metadata matching and field overrides | S22.6 plus S22.1-S22.5 |
| 37 | Admin transcode sessions | S18.5 plus S18 backend/player tasks |
| 38 | Admin realtime status | S21.3 plus S21 event/authentication tasks |
| 40, 41, 42, 43, 44 | Setup owner, storage, library, scan and first Home | S11.1-S11.3 after S10/S2; final Home also S8 |
| 50 | Browser player | S13.2-S13.4; transcoding adds S18.3 |
| 51 | Webreader | S12.2/S12.3 after S9/S6/P5 |

S12.1 and S13.1 close mockup approval only; they do not close the reader or player implementation. S22.6 remains partial while the metadata screens are unbuilt even though their mockup is approved. S10.7 checks unauthorized access to every admin route and must not disappear behind a visual completion claim.

C-05 covers every S0-S25 task, not just GUI work: catalog/scanning, storage/configuration/migrations, metadata/artwork, filtering/search, watch/read state, existing-client protocol integration, MCP, playback planning, transcoding, collections, personal state, realtime, downloads, remote security, observability, backup/restore/upgrades, documentation and final acceptance. Every remaining server task must have an owner, dependency/phase gate, acceptance evidence and a scheduled eligible work window or an explicit blocked/deferred reason. Use the source task IDs; do not create a parallel checklist that can disagree. PS-12 remains a separately approved later choice.

### Weekly control

The roadmap check must also detect missing window-to-task mappings, approved designs without build work, built windows without visual acceptance, undeclared retained platforms, orphan server tasks and GUI work incorrectly marked complete because its API or mockup exists. Check the actual manifest, registers, PRs and code refs; do not assume an old overview is current. Report gaps without silently granting phase approval or changing product scope.

## Detail authorities

- Existing app release/evidence order: `docs/unified-2026-closure.md`
- iOS status: `docs/ios-unified-implementation-register.md`
- tvOS status: `docs/tvos-redesign-register.md` and `docs/tvos-fysieke-correctieronde.md`
- Design authority: `docs/DESIGN-INDEX.md` and the referenced approval/DEC documents; later authoritative manifests and decisions supersede stale index summaries
- Web design entries: `docs/assets/pleya-web-northstar/README.md`
- Web behavior and endpoint mapping: `docs/pleya-server-rebaseline/D-northstar-spec.md`
- Server status: `docs/PLEYA-SERVER-MASTERLIST.md`; dependency graph: `docs/pleya-server-rebaseline/I-master-implementation-plan.md`; phase gates: `docs/agents/server.md`
- Decisions: `docs/DECISIONS.md`

## Change rule

Any proposal to change roadmap scope/order/priority must show:
1. which work-package IDs change;
2. why the current order no longer fits;
3. dependency/release impact;
4. what is deferred or displaced;
5. Michel's decision when it is a product choice;
6. an independent substantive review of the roadmap diff before merge.
