# Gate file format

The machine-readable contract between "I say it is done" and "it is done".
Both bundled scripts (`gate-check.mjs`, `stop-hook.mjs`) parse exactly this
format, so any deviation weakens enforcement.

## Format

```markdown
# Gates: <scope name>

Scope: <one line>

- [ ] G1: <outcome>
  CHECK: <shell command>
  EXPECT: <substring or /regex/>
  EVIDENCE: pending

- [ ] G2: <manual outcome>
  EVIDENCE: pending

ABANDON: G2 <reason, only if a gate had to be surrendered>
```

## Parsing rules

- A gate starts at a line matching `- [ ]` or `- [x]` (case-insensitive x).
- Indented `CHECK:`, `EXPECT:`, `EVIDENCE:` lines up to the next gate belong
  to the gate above them.
- `EXPECT:` is a plain substring match against the command's combined
  stdout+stderr, unless wrapped in slashes, then it is a JavaScript regex
  (e.g. `/8\/8 passed/`).
- `ABANDON: G<n> <reason>` anywhere in the file marks that gate as
  honestly surrendered. Tools treat it as resolved but reports must list it.

## What counts as UNMET

A gate is unmet if any of these hold:

1. Its box is unchecked, and no ABANDON line names it.
2. Its box is checked but `EVIDENCE:` still reads `pending`. A checkbox is a
   claim; evidence is the proof. Checked-without-evidence is the exact
   failure mode this system exists to catch, so it counts as worse than
   unchecked, not better.

## Writing good gates

- **State outcomes, not activities.** "All 8 planets clickable" is checkable.
  "Work on planet interaction" is not.
- **Prefer runnable gates.** Every CHECK you write converts model-tokens of
  self-assessment into a free shell command. If you cannot think of a CHECK,
  ask whether the outcome is observable at all; if it is not, sharpen it.
- **Make EXPECT decisive.** Match the line that can only appear on success
  (`8/8 passed`), not one that appears either way (`done`).
- **Keep CHECK commands read-only.** A check proves a state, it does not change
  one. If an outcome needs a destructive or outward-facing step, that step is
  the work, not the check.
- **You run the command, the checker judges it.** `gate-check --list` prints
  what still needs proving; you execute it with your own shell tool, so it
  passes the harness's permission layer like every other command you run; then
  `gate-check --record <id> --from <output file>` matches the captured output
  against EXPECT and writes the evidence. The checker starts no processes of
  its own. That is deliberate: a skill decides when work is done, it does not
  get a second way to run commands.
- **Cap evidence.** gate-check records the deciding tail of output. When
  filling manual evidence by hand, quote the deciding lines or cite
  `file:line`, never paste a log.
- **Five to twelve gates per leaf** is the useful range. Two gates means the
  leaf is under-specified; twenty means the leaf should have been two leaves.

## Pipes hide the exit code

A pipeline reports the exit status of its **last** stage. So this gate:

```
CHECK: npm test 2>&1 | tail -6
```

exits 0 even when the suite goes red, because `tail` succeeded. `--exit` becomes a rubber
stamp, and a failing gate records as PASS with a green-looking tail. The same trap catches
`| grep`, `| head`, `| jq` and `| sed`.

Whenever a CHECK pipes, make the pipeline's status meaningful:

```
CHECK: set -o pipefail && npm test 2>&1 | tail -6
```

`gate-check --record` refuses a gate whose CHECK pipes without `pipefail` or `PIPESTATUS`,
so this is enforced rather than remembered. A `|` inside quotes and the `||` operator are
not pipelines and do not trip it.

## Numbers rule

Any number that will appear in a final report deserves its own gate with a
CHECK that measures it. Measured runs of v1 showed reports whose only false
claims were numbers stated from memory. If a number matters enough to
report, it matters enough to measure at report time.
