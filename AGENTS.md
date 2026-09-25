# AGENTS.md

Shared instructions for all agents working on Pleya, a Flutter media app for desktop, mobile and TV. Use **Pleya** in user-facing text; historical package/repo names may use `pleya` / `plezy`. Flutter is pinned in `.fvmrc`; Dart constraints live in `pubspec.yaml`.

## Work proportional to risk

- For small, bounded tasks, explicitly skip extensive skill workflows: no mandatory brainstorming document, separate implementation plan, subagents or agent review. Inspect the relevant code and tests, implement, verify and report briefly. This is the user's approved repo workflow.
- Use a deeper investigation and a concise plan for architecture decisions, migrations, authentication, shared playback logic, unclear causes or broad impact. Ask only questions that materially change the solution. Domain-specific evidence and approval rules below still apply.
- Start with the relevant symbols, callers and tests using `rg`. Read bounded file/log excerpts. Expand only when dependencies, uncertainty or findings warrant it; do not load every linked document or rediscover established decisions.
- Keep decisions and verification results in the task context. Create a short handoff only when transferring work: changes, evidence and remaining work. Existing domain work registers remain required.
- Preserve unrelated working-tree changes. Keep full verification logs/evidence outside tracked source; inspect summaries first and relevant details on failure. UI verification still requires reading the evidence bundle and relevant screenshots.

## Review and release bundling

This is the default Pleya workflow for changes that head to a TestFlight build (owner decision, 25 September 2026). Goal: fewer agent turns, fewer tokens, less wall-clock time, without dropping evidence.

**Per branch (implementer)**
- Deliver the evidence once: focused tests for the changed behavior, a negative control per fix (the test fails without it), a green `scripts/ci_checks.sh`, and for UI Pleya Verify plus screenshots listed in a short manifest (screen, size, file).
- Do not run the full test suite locally; GitHub CI runs it on the PR. Run it locally only when shared code breaks focused tests.
- Write a report file of at most one page: commits, evidence one-liners, concerns. The agent returns only status and the report path.
- Decision records get a `DEC-XXX` placeholder; the number is assigned when the PR merges, so parallel branches never renumber.

**Bundle review (one reviewer seat per bundle)**
- One review package file: commit list, stat and diff per branch, plus the paths of the branch reports and screenshot manifests. The reviewer reads that file and does not re-explore the codebase or re-run evidence that is already in the reports.
- Scale by risk, not by branch: documentation-only and mechanical branches get a skim; UI, playback, sync and permission changes get the full read. Split into parallel reviewers only when the combined diff exceeds about 3000 changed lines or spans unrelated domains.
- Security-sensitive changes (authentication, permissions, credentials, payments) get adversarial negative controls inside the bundle review, not a separate seat.
- The visual gate covers only screens listed in the manifests.
- Findings go to one file with Critical, Important and Minor per branch, each with file:line and a failure scenario.

**Fix and close**
- One fix agent per branch fixes every finding including minors, with a negative control for each Critical or Important.
- No full re-review. A scoped check on a mid-tier model looks only at the fixes for Critical and Important findings. Minors close on the fix agent's evidence.
- Merge the PRs (required checks green, never `--admin`), then cut one TestFlight build for the whole bundle, only for the platforms the bundle touches.

**Builds and disk**
- `ensure_build_number` takes the build number from TestFlight, so the pubspec bump rides along in the next bundle PR instead of its own PR and CI round.
- Reuse one release worktree for builds instead of a fresh checkout per build, and prune old builds first (`scripts/prune_old_builds.sh`, part of the beta lanes).
- Large multi-task plans keep only their final whole-branch review; do not add a review after every task.

## Setup and verification

- Run `flutter pub get` only when dependencies are missing or changed. Run `scripts/codegen.sh` (slang + build_runner) after changes to Freezed/JSON/Drift models or translation sources, or when generated output is missing/stale. No unconditional setup or codegen on each task.
- During development, run tests focused on changed behavior: `flutter test test/path/to/foo_test.dart`, optionally `--plain-name "desc"`. Expand coverage when shared impact or failures justify it.
- Before finishing code changes, run `scripts/ci_checks.sh`, then applicable tests. This gate checks SDK pin, Dart formatting, codegen freshness, native formatting, analyzer warnings/errors and unused code/files; it strips leaked git-hook variables. It does **not** run tests.
- Do not separately repeat checks already covered by a successful gate, including `scripts/format_native.sh --check` for native changes. Repeat successful checks only after changes or findings invalidate their evidence. Hooks and CI remain enabled; do not bypass them to avoid a repeat.
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

- Prefer existing `provider` / `ChangeNotifier` state; root wiring is in `lib/main.dart`. Shared UI models are in `lib/models/`. Check both Plex and Jellyfin paths for backend feature changes.
- TV has D-pad/focus behavior under `lib/focus/`; do not assume touch-only interactions.
- Keep pinned git forks and lockfiles consistent. Do not replace forks casually. Generate brand assets with `scripts/gen_brand_assets.py`; do not hand-edit generated platform PNGs.
- Codegen freshness can fail when source timestamps are newer than `.g.dart` / `.freezed.dart`, even if compilation succeeds. Analyzer warnings fail the gate.

## Short evaluation period

At completion of each of the next three tasks, add one short observation to [workflow evaluation](docs/agents/workflow-evaluation.md): unnecessary reads, duplicate checks and process documents; actual token counts only if available. Stop after three entries. Do not launch a session audit or claim a savings percentage without measurement.
