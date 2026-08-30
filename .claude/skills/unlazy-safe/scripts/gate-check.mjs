#!/usr/bin/env node
// gate-check.mjs : parse gate files, judge captured output, record evidence.
// Zero dependencies. Node 16+. Part of the unlazy-safe skill.
//
// THIS SCRIPT NEVER EXECUTES A CHECK COMMAND.
// Upstream ran every CHECK line through spawnSync(..., {shell: true}), which
// turned one approved "node gate-check.mjs" into an unbounded number of
// unreviewed child commands, and gave the skill an execution path parallel to
// the agent harness. Command execution belongs to the harness (Claude Code's
// Bash tool), where every command passes the normal permission and classifier
// layer and stays visible to the user. What is left here is the part a script
// is genuinely better at than a model: judging captured output against EXPECT
// and an exit code, and refusing to call a gate met without evidence.
//
// The loop:
//   1. node gate-check.mjs --list                 what still needs proving
//   2. run that command yourself, capture output AND its exit code:
//        npx vite build > .unlazy/evidence/G1.txt 2>&1; code=$?
//   3. node gate-check.mjs --record G1 --from .unlazy/evidence/G1.txt --exit "$code"
//
// A check passes only when BOTH hold: the command exited with the expected code
// (0 unless the gate declares "EXIT: <n>"), and EXPECT matches the output. A
// command that prints the right thing and then crashes is not a passed gate.
//
// Usage:
//   node gate-check.mjs [--status] [file ...]
//       Report the ledger. Changes nothing. Default mode.
//   node gate-check.mjs --list [file ...]
//       Print "<id>\t<command>" for every unmet gate that has a CHECK line.
//   node gate-check.mjs --record <id> --from <file|-> --exit <code> [--file <gates.md>]
//       Judge captured output plus exit code, tick the box, write EVIDENCE.
//   node gate-check.mjs --manual <id> --evidence "<proof>" [--file <gates.md>]
//       Record a manual gate: a measurement, a quoted line, a file:line cite.
//       "pending" and empty strings are refused, as is any gate with a CHECK.
//
// Gate files are looked up under .unlazy/ first (.unlazy/GATES.md and
// .unlazy/gates/*.md), then the legacy locations GATES.md and gates/*.md in
// the working directory.
//
// Exit codes: 0 = success (ledger terminal, or the record/manual call landed),
//             1 = unmet gates remain, or the check did not pass,
//             2 = usage or parse error.

import { readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const argv = process.argv.slice(2);

const flagValue = (name) => {
  const i = argv.indexOf(name);
  return i === -1 ? null : (argv[i + 1] ?? null);
};

const listMode = argv.includes("--list");
const recordId = flagValue("--record");
const manualId = flagValue("--manual");
const fromArg = flagValue("--from");
const exitArg = flagValue("--exit");
const evidenceArg = flagValue("--evidence");
const fileArg = flagValue("--file");

// Positional files are the args that are neither a flag nor a flag's value.
const consumed = new Set();
for (const f of ["--record", "--manual", "--from", "--exit", "--evidence", "--file"]) {
  const i = argv.indexOf(f);
  if (i !== -1) consumed.add(i + 1);
}
const positional = argv.filter((a, i) => !a.startsWith("--") && !consumed.has(i));

// .unlazy/ is where a run's state belongs: gates, plan, evidence, hook state.
// The legacy root locations stay readable so older gate files keep working.
function defaultFiles(dir) {
  const found = [];
  for (const root of [join(dir, ".unlazy"), dir]) {
    const top = join(root, "GATES.md");
    if (existsSync(top)) found.push(top);
    const gdir = join(root, "gates");
    if (existsSync(gdir)) {
      for (const f of readdirSync(gdir)) if (f.endsWith(".md")) found.push(join(gdir, f));
    }
  }
  return [...new Set(found)];
}

const files = fileArg ? [fileArg] : (positional.length ? positional : defaultFiles(process.cwd()));
if (!files.length) {
  console.error("gate-check: no gate files found (.unlazy/GATES.md, .unlazy/gates/*.md, GATES.md or gates/*.md)");
  process.exit(2);
}

const GATE_RE = /^- \[( |x|X)\] (.*)$/;
const ATTR_RE = /^\s+(CHECK|EXPECT|EXIT|EVIDENCE):\s?(.*)$/;
const ABANDON_RE = /^ABANDON:\s*(\S+)\s*(.*)$/;

function parse(lines) {
  const gates = [];
  const abandoned = new Map(); // id -> reason
  let cur = null;
  lines.forEach((line, i) => {
    const g = line.match(GATE_RE);
    if (g) {
      const id = (g[2].match(/^(\S+?):/) || [null, `line${i + 1}`])[1];
      cur = {
        line: i, lastLine: i, checked: g[1].toLowerCase() === "x",
        title: g[2].trim().replace(/^\S+?:\s*/, ""),
        id,
        check: null, expect: null, exit: null, evidence: null, evidenceLine: -1,
      };
      gates.push(cur);
      return;
    }
    const a = cur && line.match(ATTR_RE);
    if (a) {
      const key = a[1].toLowerCase();
      cur[key] = a[2].trim();
      cur.lastLine = i;
      if (key === "evidence") cur.evidenceLine = i;
      return;
    }
    const ab = line.match(ABANDON_RE);
    if (ab) abandoned.set(ab[1].replace(/:$/, ""), ab[2] || "(no reason)");
    if (/^#|^- /.test(line) && !g) cur = null;
  });
  return { gates, abandoned };
}

function expectMatches(expect, output) {
  const rx = expect.match(/^\/(.+)\/([a-z]*)$/);
  if (rx) {
    try { return new RegExp(rx[1], rx[2]).test(output); } catch { return false; }
  }
  return output.includes(expect);
}

function tail(output, max = 180) {
  const lines = output.split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  const last = lines.slice(-2).join(" | ");
  return (last || "(no output)").slice(0, max);
}

const isPending = (evidence) => !evidence || /^pending$/i.test(evidence);

/**
 * Does this CHECK pipe into another command without making the pipeline's exit status
 * meaningful? `|` inside a quoted string or a `||` operator is not a pipeline, and
 * `set -o pipefail` / `PIPESTATUS` means the author already handled it.
 */
function hasUnguardedPipe(check) {
  if (/pipefail|PIPESTATUS/.test(check)) return false;
  const bare = check.replace(/'[^']*'/g, "''").replace(/"[^"]*"/g, '""');
  return /(^|[^|])\|([^|]|$)/.test(bare);
}

function readOrDie(file) {
  try { return readFileSync(file, "utf8"); } catch (e) {
    console.error(`gate-check: cannot read ${file}: ${e.message}`);
    process.exit(2);
  }
}

function writeGate(file, lines, gate, evidence) {
  lines[gate.line] = lines[gate.line].replace(/^- \[ \]/, "- [x]");
  if (gate.evidenceLine !== -1) {
    const keep = lines[gate.evidenceLine].match(/^\s*/)[0];
    lines[gate.evidenceLine] = `${keep}EVIDENCE: ${evidence}`;
  } else {
    const indent = (lines[gate.line].match(/^(\s*)- /) || [null, ""])[1] + "  ";
    lines.splice(gate.lastLine + 1, 0, `${indent}EVIDENCE: ${evidence}`);
  }
  writeFileSync(file, lines.join("\n"));
}

// --- record / manual: update exactly one gate -----------------------------

if (recordId || manualId) {
  if (recordId && manualId) {
    console.error("gate-check: use either --record or --manual, not both");
    process.exit(2);
  }
  const id = recordId || manualId;

  let target = null;
  for (const file of files) {
    const lines = readOrDie(file).split(/\r?\n/);
    const { gates, abandoned } = parse(lines);
    const gate = gates.find(g => g.id === id);
    if (gate) { target = { file, lines, gate, abandoned }; break; }
  }
  if (!target) {
    console.error(`gate-check: no gate "${id}" in ${files.join(", ")}`);
    process.exit(2);
  }
  const { file, lines, gate, abandoned } = target;
  if (abandoned.has(gate.id)) {
    console.error(`gate-check: ${gate.id} is marked ABANDON; remove that line first if it is back in scope`);
    process.exit(2);
  }

  if (manualId) {
    const evidence = (evidenceArg || "").trim();
    if (isPending(evidence)) {
      console.error(`gate-check: --manual needs real proof in --evidence (a measurement, a quoted line, a file:line cite), not "${evidenceArg ?? ""}"`);
      process.exit(2);
    }
    if (gate.check) {
      console.error(`gate-check: ${gate.id} has a CHECK line; run it and use --record, or drop the CHECK if the gate is genuinely manual`);
      process.exit(2);
    }
    writeGate(file, lines, gate, evidence.slice(0, 180));
    console.log(`RECORDED ${gate.id}: ${gate.title}\n  EVIDENCE: ${evidence.slice(0, 180)}`);
    process.exit(0);
  }

  if (fromArg === null) {
    console.error("gate-check: --record needs --from <file|-> holding the command's combined stdout+stderr");
    process.exit(2);
  }
  // Every check is judged on its exit code, not only the ones without EXPECT.
  // A build that prints "built in 3.2s" and then dies is not a passed gate.
  if (exitArg === null || !/^-?\d+$/.test(exitArg.trim())) {
    console.error(`gate-check: --record needs --exit <code>, the exit status of the command you ran.
  Capture both: <command> > .unlazy/evidence/${gate.id}.txt 2>&1; code=$?
  Then:         gate-check --record ${gate.id} --from .unlazy/evidence/${gate.id}.txt --exit "$code"`);
    process.exit(2);
  }
  // A pipeline reports the exit status of its LAST stage, so "npm test | tail -6"
  // exits 0 even when the suite went red: tail succeeded. That turns --exit into a
  // rubber stamp and lets a failing gate record as PASS. Refuse the record instead of
  // trusting it; the fix is one line in the CHECK.
  if (gate.check && hasUnguardedPipe(gate.check)) {
    console.error(`gate-check: ${gate.id} pipes its CHECK but does not set pipefail, so --exit is the status of the LAST stage, not the command you care about.
  A red suite piped into tail exits 0 and would record as PASS.
  Fix the CHECK line:  set -o pipefail && ${gate.check}
  Then re-run it and record again.`);
    process.exit(2);
  }
  let output = "";
  try {
    output = fromArg === "-" ? readFileSync(0, "utf8") : readFileSync(fromArg, "utf8");
  } catch (e) {
    console.error(`gate-check: cannot read output from ${fromArg === "-" ? "stdin" : fromArg}: ${e.message}`);
    process.exit(2);
  }

  const wantExit = gate.exit !== null && /^-?\d+$/.test(gate.exit) ? Number(gate.exit) : 0;
  const gotExit = Number(exitArg.trim());
  const exitOk = gotExit === wantExit;
  const expectOk = gate.expect ? expectMatches(gate.expect, output) : true;

  if (!exitOk || !expectOk) {
    const why = [];
    if (!exitOk) why.push(`exited ${gotExit}, expected ${wantExit}${gate.exit !== null ? " (EXIT line)" : ""}`);
    if (!expectOk) why.push(`output does not match EXPECT: ${gate.expect}`);
    console.log(`FAIL ${gate.id}: ${gate.title}\n     ${why.join("; ")}\n     ${tail(output)}`);
    process.exit(1);
  }

  const evidence = `exit ${gotExit} | ${tail(output)}`;
  writeGate(file, lines, gate, evidence);
  console.log(`PASS ${gate.id}: ${gate.title}\n  EVIDENCE: ${evidence}`);
  process.exit(0);
}

// --- list / status: read-only reporting -----------------------------------

let totalUnmet = 0;
let totalMet = 0;
const abandonedGates = [];
const pendingChecks = [];

for (const file of files) {
  const lines = readOrDie(file).split(/\r?\n/);
  const { gates, abandoned } = parse(lines);
  if (!gates.length) {
    if (!listMode) console.log(`${file}: no gates found`);
    continue;
  }

  for (const gate of gates) {
    if (abandoned.has(gate.id)) {
      abandonedGates.push(`${gate.id} (${abandoned.get(gate.id)})`);
      if (!listMode) console.log(`  ABANDONED ${gate.id}: ${gate.title} -- ${abandoned.get(gate.id)}`);
      continue;
    }
    if (gate.checked && !isPending(gate.evidence)) { totalMet++; continue; }

    totalUnmet++;
    if (gate.check) pendingChecks.push(`${gate.id}\t${gate.check}`);
    if (!listMode) {
      const why = !gate.checked ? "unchecked" : "checked but EVIDENCE pending";
      console.log(`  UNMET ${gate.id} (${why}): ${gate.title}`);
      if (gate.check) console.log(`        CHECK: ${gate.check}`);
    }
  }
  if (!listMode) console.log(`${file}: ${gates.length} gates`);
}

if (listMode) {
  if (!pendingChecks.length) console.log("# nothing to run: no unmet gate has a CHECK line");
  else for (const line of pendingChecks) console.log(line);
  process.exit(0);
}

if (totalUnmet > 0) {
  console.log(`UNMET: ${totalUnmet} (met: ${totalMet}${abandonedGates.length ? `, abandoned: ${abandonedGates.length}` : ""})`);
  console.log(`Run those CHECK commands yourself, capture output and exit code, then: gate-check --record <id> --from <file> --exit <code>`);
  process.exit(1);
}

// Nothing left to work on. Abandoned is not met: say so, in the ledger and in
// the report, instead of letting a surrendered criterion read as a success.
if (abandonedGates.length) {
  console.log(`TERMINAL (${totalMet} met, ${abandonedGates.length} abandoned, NOT complete)`);
  console.log(`NOT DELIVERED: ${abandonedGates.join("; ")}`);
  console.log(`Name each abandoned gate and its reason in your report. Do not call this task done.`);
  process.exit(0);
}
console.log(`ALL MET (${totalMet} met)`);
process.exit(0);
