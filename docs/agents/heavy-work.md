# Shared local queue for heavy Pleya work

Michel approved one heavy task at a time on 31 October 2026. The queue covers one macOS user on one host, across sessions and worktrees. It changes scheduling, never which tests must pass. One admitted command can still start its normal compiler workers; this does not cap CPU cores inside that command. No result cache, deduplication, service, network access or publication is added. Unified impact: none; this is development tooling, with no runtime backend or library change.

## Current local rollout status

The shared runtime and process module are installed and byte-verified. Standard-command adapters are now active for the current pinned SDK's Flutter/Dart launchers, SDK-bin proxies to unchanged OS xcodebuild/xcrun tools, and the existing Fastlane launchers. All 102 inventoried physical worktree scopes match the shared registry. On 31 October, 101 old separate-release scripts received a bounded lane entrypoint as an uncommitted local change. Since PR #589 (3 November 2026) `main` carries its own version of `scripts/testflight_separate.sh`, and on 4 November that local change was reverted in the 98 worktrees where the file still matched it exactly. Those worktrees again hold their branch's old script, with broad pkills, until they take in `main`.

## Source of truth

The files in this repository are the source. The copies under `/Users/michelknoop/bin` are installations of them and must stay byte-identical:

| Repository | Installed as |
|---|---|
| `scripts/heavy_queue.py` | `pleya-heavy` |
| `scripts/pleya_heavy_process.py` | `pleya_heavy_process.py` |
| `scripts/pleya_command_route.py` | `pleya-heavy-route` |
| `scripts/pleya_command_route.sh` | `pleya-heavy-route.sh` |
| `scripts/pleya_fastlane_route.rb` | `pleya-heavy-fastlane.rb` |

A fix lands here first and is then copied over. The route fix of 1 November (Verify passes a full commit SHA, the release lanes a short one) was made in the installed copy only; this branch took it over. Check parity with `cmp` on each pair before and after an update. `scripts/pleya_command_route.sh` and `scripts/pleya_fastlane_route.rb` call the installed `pleya-heavy-route` by its absolute path, because the SDK and Fastlane launchers that source them run outside any worktree.

The initial preflight stopped because standard copying changed provenance metadata. The corrected check rejects loss of every original attribute, including provenance, and any change to permissions, ACL, flags or other xattrs (including quarantine). Only OS-produced provenance addition/value changes from standard cp-p are separately logged; no attribute was written, deleted or forced. The independent review and seven metadata truth-table cases covered this check before activation. The 107-target activation completed before the later instruction to refrain from further shared-SDK changes; no further shared entrypoint mutation is planned.

This is specific entrypoint routing, not universal process enforcement. Absolute `/usr/bin/xcodebuild`, absolute `/usr/bin/xcrun`, cache-level Dart binaries, other SDK/Gem versions and custom PATHs avoiding the adapted tools remain explicit bypasses unless invoked within an already queued parent. Existing shells caching the old native command lookup may need a fresh shell/rehash. New worktrees share repository identity for tool routing, but must also adopt the safe legacy release source if they inherit an old script with broad pkills. No merge, general startup/security hook, alias or shell-profile change is added to automate that.

## Use

```sh
scripts/pleya-heavy run --label focused-tests -- flutter test test/path/to/example_test.dart
scripts/pleya-heavy run --label build-ios -- flutter build ios --simulator --debug
scripts/pleya-heavy run --label codegen -- bash scripts/codegen.sh
scripts/pleya-heavy status
scripts/pleya-heavy cancel <waiting-ticket-id>
```

On Michel's Mac, the installed `/Users/michelknoop/bin/pleya-heavy` accepts the same arguments and is available to older worktrees. Use its absolute path when it is not on PATH. Future sessions are instructed to put heavy commands from those older worktrees behind this entrypoint. The rollout patched only the inventoried legacy separate-release entrypoint in 101 older worktrees; other branch-integrated scripts require this branch or explicit wrapping. Running processes are not retroactively taken over. Do not run a legacy `testflight_separate.sh` that contains broad pkill cleanup, even wrapped: queueing does not make that old content safe. Adopt the updated script in the intended worktree first, or queue a separately authorized single Fastlane lane there. Branch-integrated entrypoints only take effect in worktrees containing this change; local installation does not merge that change elsewhere.

| Entrypoint in this branch | Queue coverage |
|---|---|
| `scripts/codegen.sh` | Version check, translations and build_runner in one slot. |
| `scripts/ci_checks.sh` | The complete existing gate, including analysis and optional unused-code checks. `--help` stays light. |
| `scripts/dcl_hard_rules.sh`, `scripts/fix_ios_spm.sh` | Their complete commands, including optional compilation. Nested shell calls reuse the inherited lease. |
| `scripts/tvos_sim.sh build` | Build, including its existing preparation. Doctor, input, screenshots and other subcommands stay outside. |
| Pleya Verify iOS/macOS builds | `runBounded` wraps existing `flutter build` calls. Other driver calls stay outside. tvOS uses the queued simulator script. |
| `scripts/testflight_release.sh`, `scripts/testflight_separate.sh` | Each existing Fastlane invocation (plus requested clean) enters one slot. Metadata checks and the later commit stay outside, so hooks can enter independently. Existing upload/approval rules still apply; queueing is not permission to publish. The separate script no longer kills other sessions' Flutter processes. |
| `scripts/release.sh android/ios/all/clean` | Existing release/build/clean commands. Help and changelog generation stay light. |
| Direct heavy Flutter/Dart/native/Fastlane commands through the adapted installed launchers | Automatically queued only for the registered Pleya Git repository and linked worktrees. Light commands and other projects pass through. Absolute OS paths, other SDK/Gem versions and custom routes avoiding these launchers remain bypasses. Use `pleya-heavy run -- ...` for those routes; no universal enforcement or shell-profile changes are installed. |

Shell guards apply automatically on macOS. Guarded shell entrypoints skip automatic admission on other hosts. Explicit queue calls and the Apple-release scripts require Unix tooling. The queue needs Python 3, its standard Unix modules and `/usr/bin/pgrep`; no package installation is needed. A sandbox must permit inspection of the task's own process group. If inspection is unavailable at admission, the command fails before starting work. If inspection fails after a task started, its supervisor keeps the lease rather than assuming its children ended. Request normal approval for the bounded command, without broadening sandbox policy.

## Ordering, cancellation and recovery

All entrypoints use `/tmp/pleya-heavy-<uid>`, independent of per-session TMPDIR. Its directory is private to that user. Do not remove or replace the directory, live ticket files or permanent lock files. `PLEYA_HEAVY_QUEUE_DIR` exists for isolated synthetic tests; setting different directories in real tasks defeats sharing.

Registration under a short kernel lock establishes FIFO order; simultaneous launches are ordered when they register. Unique ticket identities prevent an old cancellation request from targeting a later task. Status shows active leases and waiting work, with labels and working directories, never command arguments or environment values. The PID shown is the original caller, not a claim that it is still alive.

Ctrl-C/SIGTERM while waiting cancels only that invocation. `cancel` marks one waiting ticket by its unique identity; it never sends a signal. An active ticket cannot be cancelled using that command. Waiting expires after two hours by default (`run --wait-timeout <seconds>`), returning 124 without interrupting the holder. Metadata-lock acquisition is bounded to five seconds.

Each admitted task has a temporary supervisor that holds the kernel lease until its own process group is empty. The supervisor survives a crash of the calling wrapper; children may close inherited file descriptors. Signals received by a live caller are relayed through a pipe to its own supervisor, which forwards them to its own group. No signal targets a PID loaded from disk. Command exit codes and termination signals are preserved after its group finishes. These are noninteractive commands in a separate task session; do not use the queue for a shell or interactive prompt. Noninteractive build/test commands must remain in this group; deliberately daemonizing or creating a detached session is unsupported, with one exception: the Xcode script phase defined in the next paragraph. The separate-release script uses the supervisor runtime deadline, preserving its default 30-minute lane limit and 15-second termination grace. Expiry sends TERM and then KILL only to that task group and returns 124. Waiting is not charged against that lane runtime budget.

Nested shell entrypoints reuse a verified inherited lease. A nested runtime deadline is rejected instead of silently dropped; invoke automatically queued release scripts directly, without an extra outer wrapper. Closed descriptors can reuse a context only inside the same live guardian group, with the private ticket and kernel slot still held. Retained authenticated descriptors crossing a standard PTY create a nested guardian/ticket sharing the same kernel slot. An Xcode script phase runs in its own session with closed descriptors, so neither rule covers it. It is the one supported detached caller, and four facts together admit it: no usable descriptors, a live active ticket in `PLEYA_HEAVY_QUEUE_FDS` with the kernel slot held, the matching per-lease `PLEYA_HEAVY_QUEUE_ADMISSION` token, and non-empty `BUILT_PRODUCTS_DIR` and `TARGET_BUILD_DIR`. The token is part of the authority: it reaches descendants only through the environment and the ticket stores only its SHA-256. A ticket name is not enough, because status prints it. The two build settings limit the scope and are no security boundary; a process of the same user can read tickets, so this stays a cooperative queue. Such a caller gets exit 10 from `scope` and exit 75 from `owns`. `run` registers an active nested ticket in the transaction that verifies its parent, so it never joins the queue. A waiter is not promoted while any live active ticket exists, and the nested supervisors adopt the kernel slot once the outer task releases it. Tickets created before this rule carry no token, so their script phases stay refused until that build restarts. Parent signals and deadlines propagate through those private ticket records; the direct parent is read through a descriptor opened at registration, so reaping its ticket cannot lose them. A foreign group without the inherited lease is rejected with exit 75 instead of requeueing behind its parent. Do not put the entire Pleya Verify runner behind an outer queue command: its driver build calls already enter separately. Queue waiting counts against Verify's existing 30-minute build ceiling; expiry fails that invocation and does not kill a different holder. No existing timeout is relaxed.

Unlocked tickets are reaped during the next registration or status call. A fake or reused PID cannot keep them alive. Locked or unreadable metadata is never force-cleared. If inspection fails or a tool refuses termination, status remains available when metadata is healthy, waiting commands time out, and the lease stays held. Investigate the named task; do not delete its lock. Killing both supervisors while leaving detached work alive is outside this cooperative queue's guarantees. No stale-lock recovery stops another session.

## Evidence and measurement

Run `python3 scripts/tests/test_heavy_queue.py`: fixtures cover worktree sharing, FIFO/no overlap, waiting cancellation, timeouts, exit codes, SIGTERM/SIGKILL, stale tickets, inherited leases, a child closing descriptors, a detached script phase with its crash, cancellation and deadline paths, nested real codegen entrypoints, runtime expiry with TERM-ignoring children and unsafe state paths. They invoke tiny synthetic commands, never Flutter/Xcode builds. Runner regressions cover the existing bounded-process behaviour and queued-build path.

For a real comparison, use the same source SHA, input, selected tests and cache state with and without queueing in an agreed quiet window. Record 4 short interval CPU samples, memory-pressure status, swapin/out deltas, peak group memory, compiler-start count, queue delay and total wall-clock duration. Compare a representative concurrent workload, not a cold build with a warm one. Keep existing functional assertions identical. One slot should reduce overlap; performance benefit and total-time cost remain unmeasured until that comparison is run. Never start duplicate heavy builds merely to prove the queue works.
