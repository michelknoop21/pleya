# Gates: <leaf or task name>

Scope: <one line: what this unit of work delivers>

- [ ] G1: <observable outcome, stated so a stranger could judge it>
  CHECK: <shell command that proves it, read-only>
  EXPECT: <substring the command output must contain, or /regex/>
  EVIDENCE: pending

- [ ] G2: <a check that is expected to exit non-zero, declared up front>
  CHECK: <command>
  EXPECT: <substring or /regex/>
  EXIT: 1
  EVIDENCE: pending

- [ ] G3: <manual gate, when no command can prove it>
  EVIDENCE: pending

<!--
Rules (full spec in references/gates.md):
- One box per outcome. You run the CHECK command with your own shell tool;
  gate-check.mjs judges the result and never executes anything itself:
    <command> > .unlazy/evidence/G1.txt 2>&1; code=$?
    gate-check --record G1 --from .unlazy/evidence/G1.txt --exit "$code"
- A CHECK that pipes needs `set -o pipefail &&` in front: a pipeline reports its
  LAST stage's status, so `npm test | tail` exits 0 on a red suite. gate-check
  refuses to record an unguarded pipe.
- A gate passes only when the command exited 0 AND EXPECT matches. If a check
  legitimately exits non-zero, say so with an EXIT: <n> line; do not wave it
  through at record time.
- Manual gates: gate-check --manual G3 --evidence "<measurement or file:line>".
- A checked box with EVIDENCE still reading "pending" counts as UNMET.
- Evidence is the deciding lines only, never a full log.
- If a gate becomes impossible, do not delete it. Add a line:
    ABANDON: G<n> <reason>
  Only for a changed instruction, demonstrable impossibility, or explicit user
  approval; never for difficulty or a shrinking budget. Abandoned is NOT met:
  the ledger reports TERMINAL, not ALL MET, and the report must name it.
-->
