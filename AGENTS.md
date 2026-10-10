# AGENTS.md

Shared instructions for all agents working on Pleya, a Flutter media app for desktop, mobile and TV. Use **Pleya** in user-facing text; historical package/repo names may use `pleya` / `plezy`. Flutter is pinned in `.fvmrc`; Dart constraints live in `pubspec.yaml`.

## Reporting

Do not request or emit full internal chain-of-thought. Report the conclusion, relevant rationale,
evidence, checks performed, decisions, unresolved uncertainty and blockers instead. This never
reduces logging, test evidence, review evidence or technical justification. Where a report file or a
findings format is required elsewhere in this document, that format takes precedence over this
section's shape.

## Work proportional to risk

- For small, bounded tasks, explicitly skip extensive skill workflows: no mandatory brainstorming document, separate implementation plan or implementation subagents. The pre-merge review below still applies, always from a separate reviewer seat. Inspect the relevant code and tests, implement, verify and report briefly. This is the user's approved repo workflow.
- Use a deeper investigation and a concise plan for architecture decisions, migrations, authentication, shared playback logic, unclear causes or broad impact. Ask only questions that materially change the solution. Domain-specific evidence and approval rules below still apply.
- Start with the relevant symbols, callers and tests using `rg`. Read bounded file/log excerpts. Expand only when dependencies, uncertainty or findings warrant it; do not load every linked document or rediscover established decisions.
- Keep decisions and verification results in the task context. Create a short handoff only when transferring work: changes, evidence and remaining work. Existing domain work registers remain required.
- Preserve unrelated working-tree changes. Keep full verification logs/evidence outside tracked source; inspect summaries first and relevant details on failure. UI verification still requires reading the evidence bundle and relevant screenshots.

## Roadmap authority

- `docs/ROADMAP.md` owns cross-project priority and execution order for the existing Pleya product line: the current app, Pleya Server/Web, e-books/routes, commercial/release work and optional expansions. A ground-up client rebuild is explicitly outside that roadmap.
- **All development is unified-first** (Michel, 10 October 2026): follow [the project-wide rule](docs/ROADMAP.md#unified-first), not a provider-first feature with unification postponed. Start from the existing shared library/domain models, state, routes and behavior owners; keep provider differences in existing clients/adapters. Explicitly assess Emby, Jellyfin, Plex, PleyaShare and Pleya Server, preserving local/offline behavior. Shared presentation never grants unsupported capabilities or extra permissions.
- **Pleya Server readiness is not full support now** (Michel, 10 October 2026): the server is still in development. Keep shared models, capabilities and adapter boundaries ready for later integration without redesigning the UI or duplicating feature logic. Preserve and test already-supported server behavior. Record missing capabilities and their integration points against existing server tasks; do not block otherwise releasable current features on future server capabilities. Do not invent endpoints, advertise placeholder support or bypass existing protocol/release gates. Verify unavailable behavior as an honest unsupported state, not as working server integration.
- Relevant specs, mockups, implementation PRs and acceptance reports include a concise **Unified impact**: shared owner/route, connector coverage or justified limitations, source/identity/permission scope and proportionate single-/mixed-source evidence. Backend-specific protocol work remains valid within the shared contract; work with no library impact states why it is not applicable. Do not build a new framework or run an unrelated full connector audit just to satisfy this check.
- Before implementation starts, map the task to an existing roadmap work-package ID. PRs and handoffs state `Roadmap: <ID>`. If work fits no ID or changes priority/order/scope, stop and record a roadmap deviation first; product choices require Michel's decision.
- Prioriteit, WIP-limiet en uitzonderingen staan in `docs/ROADMAP.md` (Roadmap rules); dit bestand herhaalt ze niet.
- Security, data-loss, regression and release-blocking hotfixes may interrupt the order; reconcile the roadmap and owning register in the same PR or the next documentation commit.
- Whoever changes a work package's status updates `docs/ROADMAP.md` in the same PR.
- The roadmap owns order, not detailed item status. Existing registers and masterplans remain the status authority for their domains.

## Review and release bundling

This is the default Pleya workflow for changes that head to a TestFlight build (owner decision, 25 September 2026). Goal: fewer agent turns, fewer tokens, less wall-clock time, without dropping evidence.

A change that does not wait for a bundle gets the same review on its own. A docs-only change gets a proportionate independent review: factual consistency, links and references, authority conflicts, instruction drift, and whether technical claims still match the repository. This does not need the full security-branch treatment, but any file that instructs agents (`AGENTS.md`, `CLAUDE.md`, `docs/agents/`, `pleya_server/CLAUDE.md`, `.claude/skills/`, `*-for-agents.md`), every file in `check_authority_merge.sh`'s `FILES` list, decision records, plans and specs that direct future work, registers, status and closure documents, and normative protocol docs never merge without a substantive review from a seat independent of whoever wrote them.

**Per branch (implementer)**
- Deliver the evidence once: focused tests for the changed behavior, a negative control per fix (the test fails without it), a green `scripts/ci_checks.sh`, and for UI Pleya Verify plus screenshots listed in a short manifest (screen, size, file).
- Do not run the full test suite locally; GitHub CI runs it on the PR. Run it locally only when shared code breaks focused tests.
- Write a report file of at most one page: commits, evidence one-liners, concerns. The agent returns only status and the report path.
- Decision records get a `DEC-XXX` placeholder; the number is assigned when the PR merges, so parallel branches never renumber.

**Bundle review (one reviewer seat per bundle)**
- One review package file: commit list, stat and diff per branch, plus the paths of the branch reports and screenshot manifests. The reviewer reads that file and does not re-explore the codebase or re-run evidence that is already in the reports.
- Scale by risk, not by branch: mechanical branches get a skim; documentation-only changes follow the docs-only rule above. UI, playback, sync and permission changes get the full read. Split into parallel reviewers only when the combined diff exceeds about 3000 changed lines or spans unrelated domains.
- Security-sensitive branches (authentication, permissions, credentials, payments, data migrations for existing connections) keep their own independent adversarial review of the exact diff before they join the bundle: implement, fix round, gates, adversarial review, fix and re-test (a scoped re-review of the fixes), and only then the bundle review and the normal merge flow. The bundle review is an extra check there, not a replacement (owner decision, 25 September 2026).
- The visual gate covers only screens listed in the manifests.
- Findings go to one file with Critical, Important and Minor per branch, each with file:line and a failure scenario.

**Fix and close**
- Verify every finding against the current code or documentation first; reject false positives with a one-line reason.
- One fix agent per branch fixes every verified finding that affects correctness, explicit requirements, security or safety, data integrity or a project invariant, with a negative control for each Critical or Important. Style preferences, speculative improvements and optional minors are not mandatory and do not widen the scope.
- After fixing, rerun the relevant tests or evidence. Then a fresh reviewer seat other than the fix agent checks all fix diffs in one pass, with capacity scaled to the risk. No separate re-review round per finding.
- Merge the PRs (the required checks on `main` are green, never `--admin`), then cut one TestFlight build for the whole bundle, only for the platforms the bundle touches.

**Builds and disk**
- `ensure_build_number` takes the build number from TestFlight, so the pubspec bump rides along in the next bundle PR instead of its own PR and CI round.
- Reuse one release worktree for builds instead of a fresh checkout per build, and prune old builds first (`scripts/prune_old_builds.sh`, part of the beta lanes).
- Large multi-task plans keep only their final whole-branch review; do not add a review after every task.

## Setup and verification

- Run `flutter pub get` only when dependencies are missing or changed. Run `scripts/codegen.sh` (slang + build_runner) after changes to Freezed/JSON/Drift models or translation sources, or when generated output is missing/stale. No unconditional setup or codegen on each task.
- During development, run tests focused on changed behavior: `flutter test test/path/to/foo_test.dart`, optionally `--plain-name "desc"`. Expand coverage when shared impact or failures justify it.
- Before finishing code changes, run `scripts/ci_checks.sh`, then applicable tests. The gate checks SDK pin, Dart formatting, codegen freshness (a source newer than its `.g.dart`/`.freezed.dart` fails even when it compiles), native formatting and analyzer errors, with warnings counted as failures. It does **not** run tests. CI additionally always runs the hard dart_code_linter rules and unused-code checks; run them locally with `--with-unused`.
- Do not separately repeat checks already covered by a successful gate, including `scripts/format_native.sh --check` for native changes. Repeat successful checks only after changes or findings invalidate their evidence. Hooks and CI remain enabled; do not bypass them to avoid a repeat. `SKIP_HOOKS=1` only for commits that touch documentation only, with the reason in the message.
- Documentation-only tasks require a diff, link and instruction-consistency check, not Flutter builds/tests. Do not describe unrelated code changes in the worktree as verified.
- Relevant UI/focus/navigation/layout changes require matching Pleya Verify assertions **and visual evidence**. If the environment provably cannot run a supported target, state exactly which evidence is missing; do not claim full verification. Pure backend changes need no UI scenario. Hardware-only findings require a device run.
- Dependency updates follow the additional evidence rings in the reference below; release gates are unchanged.

## Read only for the affected domain

These references retain binding domain rules. Read the relevant sections before working in that domain; the lightweight workflow does not waive them. Inline code paths in references are repo-relative.

| Task touches | Read |
| --- | --- |
| Providers, backend mapping, profiles/connections, offline storage or playback | [Client architecture](docs/agents/architecture.md) |
| Dependencies, SDK, generators or native formatting tooling | [Dependencies and codegen](docs/agents/dependencies.md) |
| UI, navigation, focus or TV | [UI and TV rules](docs/agents/ui-and-tv.md); for scenario execution/writing, [Pleya Verify guide](docs/testing/pleya-verify-for-agents.md) |
| Pleya Server or its client protocol | [Server phase rules](docs/agents/server.md), plus `pleya_server/CLAUDE.md` for work in that directory |
| Apple builds, release/signing or brand assets | [Build and brand rules](docs/agents/build-and-brand.md) |
| Setup or translation contribution instructions | Relevant sections of [README](README.md) / [CONTRIBUTING](CONTRIBUTING.md) |

## Always retain

- Prefer existing `provider` / `ChangeNotifier` state; root wiring is in `lib/main.dart`. Shared UI models are in `lib/models/`. Check every `MediaBackend` (Plex, Jellyfin, local, Pleya Server) for backend feature changes.
- TV has D-pad/focus behavior under `lib/focus/`; do not assume touch-only interactions.
- Keep pinned git forks and lockfiles consistent. Do not replace forks casually. Generate brand assets with `scripts/gen_brand_assets.py`; do not hand-edit generated platform PNGs.
- Tests and tooling never touch real user data, credentials, the vault, HOME data outside the repo, `web.pleya.app` or the NAS. Pleya Verify installs under `nl.michelknoop.pleya.verify` on macOS, iOS and tvOS and aborts without that rewrite; widget tests use mocked `SharedPreferences`; server tests use `pleya_server/scripts/test-db.sh`.
- **Never merge an authority file (`CLAUDE.md`, `docs/RELEASES.md`, `docs/DECISIONS.md`, `docs/CHANGELOG.md`, `STATUS.md`, `docs/PLEYA-SERVER-MASTERLIST.md`, `AGENTS.md`, `docs/ROADMAP.md`, see `check_authority_merge.sh`'s `FILES` list) with `--ours` or `--theirs`.** Those take the whole file from one side, not just the conflicting hunk, and silently drop the other side's changes. Resolve as a real three-way merge against the merge base (`git merge-file <file> <base> <other side>`) and compare the result with both parents. Regenerate generated files instead of hand-merging them (`scripts/codegen.sh`, `dart run slang`, `pleya_web/scripts/gen-api-types.sh`, `scripts/gen_release_notes.sh`). `scripts/check_authority_merge.sh` enforces this in CI.
- Status (current phase, open protocol window, item state) lives in the registers and masterplans, never in instruction files.
