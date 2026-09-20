# AGENTS.md

Shared instructions for all agents working on Pleya, a Flutter media app for desktop, mobile and TV. Use **Pleya** in user-facing text; historical package/repo names may use `pleya` / `plezy`. Flutter is pinned in `.fvmrc`; Dart constraints live in `pubspec.yaml`.

## Work proportional to risk

- For small, bounded tasks, explicitly skip extensive skill workflows: no mandatory brainstorming document, separate implementation plan, subagents or agent review. Inspect the relevant code and tests, implement, verify and report briefly. This is the user's approved repo workflow.
- Use a deeper investigation and a concise plan for architecture decisions, migrations, authentication, shared playback logic, unclear causes or broad impact. Ask only questions that materially change the solution. Domain-specific evidence and approval rules below still apply.
- Start with the relevant symbols, callers and tests using `rg`. Read bounded file/log excerpts. Expand only when dependencies, uncertainty or findings warrant it; do not load every linked document or rediscover established decisions.
- Keep decisions and verification results in the task context. Create a short handoff only when transferring work: changes, evidence and remaining work. Existing domain work registers remain required.
- Preserve unrelated working-tree changes. Keep full verification logs/evidence outside tracked source; inspect summaries first and relevant details on failure. UI verification still requires reading the evidence bundle and relevant screenshots.

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
