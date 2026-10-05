# Pleya roadmap

**Authority:** this file owns cross-project priority and execution order for the existing Pleya product line.
Detailed status and evidence remain in the existing domain registers and masterplans.

**Explicitly out of scope:** rebuilding the client from the ground up. That work is not a milestone, dependency, parallel track, or release gate in this roadmap.

## Current direction

0. Big P (BP-00 t/m BP-09) is de primaire stroom: eerst begrijpen wie, wat en welke data bedoeld is, dan gecontroleerd antwoorden. Volgorde en detail: sectie Big P (na Work packages); de Execution phases hieronder gelden voor de rest van het product.
1. Reconcile the current source/release/status baseline. Items 1-6 resume when Michel lifts the Big P pause (section Big P).
2. Close correctness, permission/profile and concrete library bugs in the existing app.
3. Finish only the currently valid UI gaps; do not rebuild already-landed surfaces.
4. Run real-account, simulator and physical-device acceptance for the chosen release scope.
5. Release exactly the accepted SHA/archive.
6. Then choose one next product increment; Pleya Server/Web/e-books continue only through their existing phase gates and dependency graph.

## Roadmap rules

- Every implementation task must name one roadmap work-package ID before code starts.
- PRs and handoffs use `Roadmap: <ID>`.
- Work that does not fit an ID does not silently become a new side track. First record `Roadmap deviation: <approved decision/proposal>`.
- Open P0 work precedes P1/P2/P3 unless lower-priority work is demonstrably independent and does not delay review/release of the primary stream. Exception: Michel's decision of 5 October 2026 (section Big P) makes BP-00..BP-09 the single primary stream, whatever their P-level, and pauses the other open P0 items except hotfixes.
- WIP limit: one primary implementation stream plus at most one truly independent parallel implementation. Design/spec work may run ahead only if it does not create an unreviewed implementation pile.
- Security, data-loss, regression and release-blocking hotfixes may interrupt the order. Reconcile this roadmap and the owning register in the same PR or the next documentation commit.
- This roadmap owns order; domain registers own detailed state. Do not create a second detailed status administration here.
- Changing priority, order, scope, or milestones is an authority change and requires an explicit roadmap diff plus independent substantive review before merge.
- Code on `main`, simulator evidence, hardware evidence and publication are separate states.
- UI changes are executed by Opus and get a separate visual review against the current northstar/DEC.

## Work packages

| ID | P | Track | Work package | Current state |
| --- | --- | --- | --- | --- |
| BP-00 | P0 | Big P | Gedragscontract en Connected Knowledge-inventaris (`docs/big-p-behaviour-contract.md`, PR #175) | Akkoord Michel 5 okt; contract (PR #175) merget vóór BP-01 |
| BP-01 | P0 | Big P | Invarianten: bevoegdheid na wachten, server-plus-item-paren, taakstatus onbekend, operatie-id | Gemerged (PR #178) |
| BP-02 | P0 | Big P | Identiteit en personen: sleutel per bron, `CurrentUserContext`, "anderen" op account-id | Gemerged (PR #187); open gaten verdeeld, zie sectie Big P |
| BP-03a | P0 | Big P | Mediasleutel en kijkcijfers: titels over servers alleen samenvoegen op bewijs en melden; Tautulli-"anderen" getest | Draft-PR |
| BP-03b | P0 | Big P | "Ooit gezien" los van het historievenster: ongevensterde kijklogsleutels in `my_watching` en het venster benoemd; kijklog-migratie (titel en externe id's in `MediaInteractions`) volgt als BP-03c | Draft-PR, gestapeld op BP-03a |
| BP-03c | P0 | Big P | Kijklog-migratie: titel en externe id's in `MediaInteractions` zodat een kopie op een andere server herkend wordt; tweede Plex-nep, Pleya-eigen-id, Emby-test | Gepland |
| BP-04a | P0 | Big P | Intent met herkomst per veld (publiek, soort, periode), parser NL/EN, afdwingen op tool-argumenten, `assistant_run.dart` gesplitst | PR #193, adversariële review en scoped re-review gedaan, bevindingen hersteld; wacht op CI |
| BP-04b | P0 | Big P | Korte classifier voor wat de parser mist, routing, minimale wedervraag (max 3, knoppen plus vrije invoer, UI), prompt uit werkelijk aangeboden tools, run-brede rechtenstempel, nulmeting op glm-5.3-flash en gemma4:31b | Deels: periode "vorige week" geweigerd, gemengd publiek gemeld aan het model; rest gepland |
| BP-05 | P0 | Big P | Eén waarheid (resultaatset) en de route "recent toegevoegd"; build 1 | Gepland |
| BP-06 | P1 | Big P | Gesprek: laatste intent, resultaat en persoon | Gepland |
| BP-07 | P1 | Big P | Aanbevelingspijplijn en Trakt inlezen (Trakt-poort vóór de bouw) | Gepland |
| BP-08 | P1 | Big P | Geheugen en sync; build 2 | Gepland |
| BP-09 | P0 | Big P | Lopende fixes van de parallelle sessie: `catalog_changed`, draft bij bevestiging, stap-labels, tvOS-ruimte | Gelandeerd (5 okt); hardware- en tvOS-deviceronde open |
| REG-01 | P0 | Regie | Eén actuele uitgangsstand, inclusief vensterdekking per platform | Gepauzeerd t.g.v. Big P (5 okt) |
| REG-02 | P1 | Regie | Oude branches en PR's reconciliëren | Status herijken |
| REG-03 | P0 | Regie | Release-identiteit en distributiestatus | Status herijken; gepauzeerd t.g.v. Big P (5 okt) |
| A-01 | P0 | Bestaande app | Verify-runner: time-outs en simulatorselectie | Open PR; gepauzeerd t.g.v. Big P (5 okt) |
| A-02 | P0 | Bestaande app | Rechten, geleende verbindingen en profielen | Bewijs afronden; enige onafhankelijke stroom naast Big P |
| A-03 | P1 | Bestaande app | Bibliotheek-snelkiezer bewaart selectie | Open issue |
| A-04 | P1 | Bestaande app | Verborgen Plex-bibliotheek op TV | Open issue |
| A-05 | P1 | Bestaande app | iPhone-detail DEC-140 | Bewijs afronden |
| A-06 | P1 | Bestaande app | Home, landingen, catalogus en filters | Volgens register open |
| A-07 | P1 | Bestaande app | Bronkeuze bij meerdere servers | Bewijs afronden |
| A-08 | P1 | Bestaande app | Mijn Pleya, lijst/downloads/meldingen en contextmenu | Volgens register open |
| A-09 | P0 | Bestaande app | Login, profielkeuze en PIN | Volgens register open; gepauzeerd t.g.v. Big P (5 okt) |
| A-10 | P1 | Bestaande app | Live TV, Liquid Glass en mobiele speler | Bewijs afronden |
| A-11 | P1 | Bestaande app | tvOS focus, Menu en shell-routes | Bewijs afronden |
| A-12 | P1 | Bestaande app | Top Shelf, 4K en tvOS scrubbing | Bewijs afronden |
| A-13 | P1 | Bestaande app | Zoeken en filtergedrag met echte servers | Bewijs afronden |
| A-14 | P1 | Bestaande app | iCloud-voorkeurensync | Bewijs afronden |
| A-15 | P1 | Bestaande app | Aanbevelingen, historie en Tautulli | Bewijs afronden |
| A-16 | P1 | Bestaande app | Activiteit: ACT1 | Besluit nodig |
| A-17 | P1 | Bestaande app | Desktop/iPad unified afronding en afzonderlijke platformdekking | Status herijken; geen bewijs van volledige afronding |
| A-18 | P0 | Bestaande app | Eindacceptatie en releasebundel | Gepland; gepauzeerd t.g.v. Big P (5 okt) |
| A-19 | P1 | Requests 2.0 | Functionele audit en productspec van de volledige aanvraagflow | Nieuw; spec vóór ontwerp |
| A-20 | P1 | Requests 2.0 | Northstar/mockups voor alle aanvraagvensters, rollen en toestanden | Na A-19; Opus; expliciet akkoord vóór bouw |
| A-21 | P1 | Requests 2.0 | Implementatie en acceptatie van het goedgekeurde redesign | Na A-20; platform- en rolbewijs vereist |
| C-01 | P1 | Server | S2.5 configuratiebibliotheken overnemen | Volgens register open |
| C-02 | P1 | Server | S2.6 migratie en protocolvenster 2 sluiten | Volgens register open |
| C-03 | P0 | Server | Beheerfase PS-11A en vrijgave PS-14 | Status herijken; gepauzeerd t.g.v. Big P (5 okt) |
| C-04 | P1 | Server | Loudness D3-D5 en client-consumptie | Status herijken |
| C-05 | P2 | Server | Volledige S0-S25-dekking, inclusief Web consumer, beheer-GUI en setup | Gepland; detailstatus in servermasterlijst |
| D-01 | P2 | E-books/routes | Bestaande e-bookbranch en schermen | Status herijken |
| D-02 | P2 | E-books/routes | Resterende e-bookuitbreidingen uit northstar | Volgens actueel branchmanifest vast te stellen |
| D-03 | P2 | E-books/routes | Eigen routes muziek, boeken en overige typen | Besluit nodig |
| D-04 | P2 | Audioboeken | Product-, bron-, metadata-, playback- en voortgangsspec | Nieuw contentdomein; besluiten nodig |
| D-05 | P2 | Audioboeken | Northstar/mockups voor bestaande apps en Pleya Web | Na D-04; Opus; akkoord vóór bouw |
| D-06 | P2 | Audioboeken | Pleya Server-, client- en webimplementatie plus acceptatie | Na D-05 en toepasselijke server/protocolpoorten |
| E-01 | P1 | Commercieel/site | Free/Pro en prijsbesluit | Voorstel, niet besloten |
| E-02 | P0 | Commercieel/site | Licenties en publicatiegereedheid | Status herijken; gepauzeerd t.g.v. Big P (5 okt) |
| E-03 | P2 | Commercieel/site | Aankoop, herstel en Pro-toegang | Gepland |
| E-04 | P1 | Commercieel/site | Website, screenshots en release-informatie | Status herijken |
| F-01 | P3 | Optioneel | Apple Intelligence: kleine zoekfilter-MVP | Gepland |
| F-02 | P3 | Optioneel | Nieuwe ideeën zonder bestaande release te blokkeren | Gepland |

## Big P

Primaire stroom (Michel, 5 oktober 2026). Doel: Pleya stelt eerst vast wie, wat en welke data bedoeld is, verzamelt gecontroleerd de juiste gegevens, geeft het model alleen de juiste context, controleert de uitkomst en toont tekst en acties uit één waarheid.

Stromen (Michel, 5 oktober 2026): BP-00 t/m BP-09 tellen samen als één programma en vormen de enige primaire stroom. A-02 (rechten, geleende verbindingen en profielen) is de enige onafhankelijke parallelle stroom. Alle andere open P0-items (A-01, A-09, A-18, REG-01, REG-03, C-03, E-02) pauzeren tijdelijk, behalve hotfixes voor security, dataverlies of regressies; die onderbreken volgens de bestaande regel. Een gepauzeerd item verliest zijn prioriteit niet en hervat zodra Michel de pauze opheft.

Open gaten van BP-02 (Michel, 5 oktober 2026: per gat beslist waar het hoort):
- Zelfde plex.tv-id over twee Plex-servers samenvoegen (test): BP-03c, samen met de kijklog-migratie. Het harnas heeft één Plex-server; een tweede nep is daar nodig.
- Samenvoegen via een Pleya-profielbinding: A-02 (profielen), niet Big P. Zonder binding blijft identiteit bronlokaal.
- Pleya Server slaat het eigen id uit `/users/me` niet op: BP-03c. Tot dan is "ik" daar `notStored` en valt de bron onder `leftOut`.
- Recht dat tijdens één leesactie wordt ingetrokken en teruggezet: BP-04, als run-brede rechtenstempel naast de bestaande controle voor en na het wachten.
- Het model kiest `audience` nog niet zelf: BP-04 (intent).
- Testgaten uit de review: Tautulli met `audience: others` is gedekt in BP-03a. Emby in `watch_stats`, randgevallen van `resolvePeople` en het Plex-eigenaar-id 1: BP-03c.

BP-04b nulmeting (14 vragen, eerste toolaanroep, beide modellen): 9 gelijk en goed; gaten: gemengde vraag verdween stil tot `my_watching`, "vorige week" werd `days: 7`, "mijn bibliotheken deze week" kreeg geen route (BP-05), "films nu" kreeg geen terugval. Eerste twee gedicht in de intent; wedervraag-UI, run-brede rechtenstempel en terugval voor soort bij `now` open.

BP-04a: bekend en bewust laten staan: een gemengde vraag in vreemde zinsbouw ("wat hebben de anderen en ik gekeken") geeft "anderen" in plaats van onbekend (de smallere richting); een kindtaak erft publiek en periode van de vraag, nooit de soort; `search_catalog` en `recommend_together` hebben een eigen `kind` en vallen onder het vangnet `ctx.recommend`, niet onder `constrain` (BP-04b).

BP-03b: de kijklog zelf bewaart 365 dagen (`kInteractionRetentionDays`); "ooit gezien" reikt via de log dus een jaar terug, daarbuiten beslist alleen de eigen kijkstatus van de server (`item.isWatched`). Het resultaat van `my_watching` noemt het venster van de recente lijst (`watched_recently_window_days`).

BP-03a: een titel over servers heen wordt alleen één regel op een gedeeld extern id (bewijs), op gelijke titel en jaar (gemarkeerd `titleYear`) of op titel alleen (gemarkeerd `titleOnly`, ranglijst dan niet volledig). Een ander jaar, een ander id of een andere soort (film of serie) is nooit dezelfde titel. Geen enkele historiebron levert nu jaar of id (Plex, Tautulli, Pleya Server) behalve Jellyfin/Emby voor films; tot BP-03c dat via de kijklog aanvult geldt voor Plex en Tautulli `titleOnly`.

Uitvoeringsregel: twee BP-pakketten wijzigen niet parallel dezelfde codegebieden zonder uitdrukkelijke bestands- en scope-afbakening. BP-09 landt eerst, of wordt exact afgebakend, voordat BP-01 wijzigingen doet in overlappende assistantcode (`lib/assistant/`, `lib/screens/**/big_p*`).

Volgorde: BP-00 (Michel keurt het contract goed) → BP-01 → BP-02 → BP-03 → BP-04 → BP-05 → build 1 → BP-06 → BP-07 → BP-08 → build 2. Elke fase is een eigen PR met gerichte tests, negatieve controle en onafhankelijke review (adversarieel voor BP-01, BP-02, BP-04, BP-07 en BP-08). Die review komt vóór de bundelreview van AGENTS.md en vervangt hem niet; build 1 en 2 krijgen daarna elk één bundelreview.

BP-09 is onderdeel van het Big P-programma en wordt uitgevoerd door de parallelle sessie; BP-05 wacht op haar `catalog_changed`-fix. Nieuwe tools uit BP-02 t/m BP-07 krijgen een stap-label via de volledigheidstest tegen `assistantTools` die BP-09 (fase 3 van de parallelle sessie) toevoegt.

Connected Knowledge: geen gekoppelde, relevante bron blijft onbereikbaar voor Big P alleen omdat er geen losse tool voor bestaat. De grens zijn de rechten van de gebruiker (per bron en per gegevenstype), wat de bron aanbiedt en de privacy van die verbinding. De inventaris staat in het contract.

Uitgesteld (geen werkpakket tot Michel er een opent, verwijzing: `docs/big-p-behaviour-contract.md`): fuzzy namen, collecties op Jellyfin/Emby/Pleya Server, Trakt-aanbevelingen en -trending, een algemene wijzigingsindex.

## Execution phases

Tot Michel de pauze opheft loopt alleen de Big P-stroom (primair) en A-02 (onafhankelijk); de fasen hieronder blijven de volgorde voor de gepauzeerde items.

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

Finish the currently valid app surfaces and evidence only: Home/landings/catalog/filters, source picker, context menus, Mijn Pleya, lists/downloads/notifications, Live TV/player, Liquid Glass, desktop/iPad unified work, tvOS focus/Menu/routes/scrubbing/Top Shelf/4K/overscan, and the explicitly gated Requests 2.0 flow. Check every applicable existing platform separately; a shared widget or an iPhone screenshot does not prove iPad, Android, Android TV, macOS, Windows or Linux completion. Preserve explicitly excluded platform presentations until their own design decision changes. The latest approved DEC/northstar wins.

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

## Requests 2.0

Requests is an existing product surface, not a new blank feature. The current implementation already spans discovery/search, a Seerr media detail page, movie/show request submission, per-season selection for shows, 4K when permitted, remaining quota, admin target selection (Radarr/Sonarr server, quality profile and root folder), request lists and manager/user actions such as approve, decline, edit and cancel. The redesign must preserve valid existing capability unless a later approved product decision changes it.

Order is strict:
1. **A-19 — audit/spec.** Inventory the complete current flow, roles, permissions, API behavior and states across applicable existing platforms. Decide what Requests 2.0 adds or changes before drawing it. Cover at least discovery/search, detail, request creation, season selection, 4K, quotas, advanced targeting, own/all requests, filters/counts, approve/decline/edit/cancel, pending/processing/available/declined states, loading/empty/error/retry, pagination, permissions and post-request refresh.
2. **A-20 — design.** Opus produces a coherent approved northstar set for every required window/state and the responsive/TV variants. Do not treat today's single iPhone or TV image as complete coverage. Include dialogs/sheets and manager-only states, not only the landing screen.
3. **A-21 — implementation.** Only after explicit design approval: implement through shared behavior owners where appropriate, preserve D-pad/focus/touch/keyboard contracts, add automation IDs/fixtures/tests, run independent code review plus separate visual review, then simulator/browser and applicable hardware acceptance.

REG-01 must map each current Requests route/window to A-19/A-20/A-21 so no old behavior is silently lost. If Pleya Web is later chosen as a Requests surface, add it to the same product spec and create explicit Web implementation tasks rather than assuming the mobile/TV design transfers directly.
## E-books and other routes

Do not rebuild the existing e-book work. Reconcile the branch against current `main`, current shell/navigation and server gates; keep valid work and build only missing surfaces. Use the actual branch manifest and later commits, not an old count of built or missing screens in DESIGN-INDEX. For music/books/photos/unknown library kinds choose an explicit destination or unsupported state instead of silently opening the wrong catalog.

## Audiobooks

Audiobooks is a new first-class content domain and is not folded silently into the existing e-book implementation. Current repository search found no established audiobook domain, so the roadmap starts with product/protocol design rather than code.

Order is strict:
1. **D-04 — product/protocol spec.** Decide supported source model and ingestion path, library kind and permissions, media/container baseline, metadata and artwork, author/narrator/series semantics, chapter model, playback and resume semantics, speed, sleep timer/bookmarks if included, search/filter/facet behavior, downloads/offline, multi-user progress and compatibility with existing player/backends. Explicitly decide whether integration with an external audiobook server is in scope; do not assume one.
2. **D-05 — design.** Opus creates and reviews the complete audiobook northstar for each applicable existing app and Pleya Web. At minimum evaluate Home/landing, all audiobooks, search/filter, audiobook detail, player/now playing, chapters/queue, resume/progress, downloads/offline and empty/loading/error states; only include surfaces approved by D-04.
3. **D-06 — implementation.** After design approval and applicable Server/API window decisions: build Pleya Server storage/catalog/search/progress/playback support, then client/Web support in dependency order. Reuse shared media/player infrastructure only where its contract genuinely fits audiobooks; do not distort video or e-book semantics to avoid a proper boundary.

Audiobooks must receive the same completion evidence as other domains: server contract/tests, migration safety where applicable, client/Web tests, visual comparison to approved mockups, real playback/progress evidence and release identity. It may be developed as an independent later increment but may not bypass the WIP limit or server phase gates.
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
| 5-9 Oct | Big P: BP-00, BP-09 landen, BP-01 (primair) | A-02 permissions/profiles (enige onafhankelijke stroom); issue #112 en de rest van de UI pauzeren |
| 12-16 Oct | Big P: BP-02 t/m BP-04 (primair); acceptatie van de rest hervat zodra de pauze opgeheven is | A-02 |
| 19-23 Oct | Big P: BP-05 en build 1 (alleen wat erin zit) | A-02; A-18, REG-03 en E-02 blijven gepauzeerd |
| 26-30 Oct | Big P: BP-06 t/m BP-08 en build 2; daarna beslist Michel of de pauze opgeheven wordt | A-02; Requests A-19/A-20, Audiobooks D-04/D-05 en overige increments wachten op het opheffen van de pauze |

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
| Requests / Aanvragen | A-19/A-20/A-21 | complete current capability + role/state inventory, approved multi-window redesign, implementation and visual/functional acceptance |
| Audiobooks | D-04/D-05/D-06 | new domain: spec first, then approved cross-platform/Web designs, then Server/client/Web implementation and playback/progress evidence |

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
