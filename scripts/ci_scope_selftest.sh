#!/usr/bin/env bash
# Negatieve controle op de padscoping van de CI.
#
#   scripts/ci_scope_selftest.sh
#
# Voert de echte `Bereik bepalen`-stap uit ci.yml, server-web.yml en
# pleya-verify.yml uit tegen een vaste set voorbeeldwijzigingen, en toont per
# voorbeeld welke jobs hun werk doen. Elk voorbeeld heeft een verwachte
# uitkomst; wijkt het filter daarvan af, dan faalt het script. Zo valt een
# patroon dat te veel overslaat (een test die een bestand niet meer ziet) net
# zo op als een patroon dat te veel draait.
#
# De stap wordt niet nagebouwd: het script leest het `run`-blok uit de
# workflow, zet een nep-scripts/ci_changed_files.sh neer die de voorbeeldlijst
# teruggeeft, en draait het blok met bash. Daarnaast controleert het statisch
# dat elke job die op `changes` wacht open valt: `if: !cancelled()` op de job,
# een conditie op elke stap, en `needs.changes.result != 'success'` in de
# conditie.
#
# Vraagt python3 met PyYAML. Draai hem na elke wijziging aan een filter.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

exec python3 -I - "$PWD" <<'PY'
import os
import re
import subprocess
import sys
import tempfile

import yaml

root = sys.argv[1]
WORKFLOWS = ["ci.yml", "server-web.yml", "pleya-verify.yml"]

# Voorbeeldwijzigingen en de verwachte waarde per output. Een sleutel zonder
# workflow (`server`) geldt voor elke workflow met die output; `ci.yml:server`
# alleen voor die ene. Een output die hier niet staat wordt wel getoond, maar
# niet getoetst.
CASES = [
    ("alleen docs/*.md", ["docs/CHANGELOG.md", "docs/DECISIONS.md"],
     dict(flutter="false", server="false", web="false", apple="false", portable="false")),
    ("alleen docs/assets", ["docs/assets/ios-unified/big-p-39/01.png"],
     dict(flutter="true", server="false", web="false", apple="false", portable="false")),
    ("alleen pleya_verify/redact", ["pleya_verify/redact/cases.json"],
     dict(flutter="true", server="true", web="false", apple="true", portable="true")),
    ("alleen pleya_web", ["pleya_web/src/lib/api/client.ts", "pleya_web/package.json"],
     dict(flutter="false", server="false", web="true", apple="false", portable="false")),
    ("alleen lib/", ["lib/main.dart"],
     dict(flutter="true", server="false", web="false", apple="true", portable="false")),
    ("alleen test/", ["test/widgets/foo_test.dart"],
     dict(flutter="true", server="false", web="false", apple="false", portable="false")),
    ("alleen pleya_server (Go)", ["pleya_server/internal/api/router.go"],
     dict(flutter="false", server="true", web="false", apple="false", portable="false")),
    ("pleya_server/scripts/verify-local.sh", ["pleya_server/scripts/verify-local.sh"],
     dict(flutter="true", server="true", web="false", apple="false", portable="false")),
    ("pleya_web/scripts/build-into-server.sh", ["pleya_web/scripts/build-into-server.sh"],
     dict(flutter="true", server="false", web="true", apple="false", portable="false")),
    ("protocolcontract", ["docs/pleya-protocol/v1/openapi.yaml"],
     dict(flutter="true", server="true", web="true", apple="false", portable="true")),
    ("protocolspecificatie (proza)", ["docs/pleya-protocol-v1.md"],
     dict(flutter="true", server="true", web="false", apple="false", portable="false")),
    ("antwoordvalidator", ["scripts/check_server_responses.py"],
     dict(flutter="true", server="true", web="false", apple="true", portable="true")),
    # Het apple-filter in pleya-verify.yml is niet door deze scoping aangepast
    # en laat .claude/ en website/ de simulatorrun starten.
    ("root-markdown en .claude", ["README.md", "STATUS.md", ".claude/skills/x/SKILL.md"],
     dict(flutter="false", server="false", web="false", apple="true", portable="false")),
    ("website/", ["website/src/lib/content/manual/01.md"],
     dict(flutter="false", server="false", web="false", apple="true", portable="false")),
    ("docs plus lib", ["docs/CHANGELOG.md", "lib/main.dart"],
     dict(flutter="true", apple="true")),
    ("ci.yml zelf", [".github/workflows/ci.yml"],
     {"flutter": "true", "ci.yml:server": "true", "server-web.yml:server": "false", "apple": "true"}),
    ("server-web.yml zelf", [".github/workflows/server-web.yml"],
     {"flutter": "true", "ci.yml:server": "false", "server-web.yml:server": "true", "web": "true"}),
    ("pleya-verify.yml zelf", [".github/workflows/pleya-verify.yml"],
     dict(flutter="true", apple="true", portable="true")),
    ("lege diff", [],
     dict(flutter="true", server="false", web="false")),
    # Push op main, handmatig of schema: ci_changed_files.sh geeft dan git ls-files.
    ("push op main (git ls-files)", None,
     dict(flutter="true", server="true", web="true", apple="true", portable="true")),
]


def load(name):
    with open(os.path.join(root, ".github", "workflows", name), encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def filter_script(doc):
    for step in doc["jobs"]["changes"]["steps"]:
        if step.get("id") == "filter":
            return step["run"]
    raise SystemExit("geen filterstap in changes")


def gated_jobs(doc):
    """Job-naam -> outputs van `changes` waar de job op stuurt."""
    out = {}
    for key, job in doc["jobs"].items():
        if key == "changes":
            continue
        needs = job.get("needs") or []
        needs = [needs] if isinstance(needs, str) else needs
        text = yaml.safe_dump(job)
        outputs = sorted(set(re.findall(r"needs\.changes\.outputs\.(\w+)", text)))
        out[job.get("name", key)] = ("changes" in needs, outputs, job, text)
    return out


def run_filter(script, files):
    with tempfile.TemporaryDirectory() as tmp:
        os.makedirs(os.path.join(tmp, "scripts"))
        listing = os.path.join(tmp, "files.txt")
        if files is None:
            all_files = subprocess.run(["git", "-C", root, "ls-files"], check=True,
                                       capture_output=True, text=True).stdout
            with open(listing, "w") as fh:
                fh.write(all_files)
        else:
            with open(listing, "w") as fh:
                fh.write("".join(f + "\n" for f in files))
        stub = os.path.join(tmp, "scripts", "ci_changed_files.sh")
        with open(stub, "w") as fh:
            fh.write(f"#!/usr/bin/env bash\ncat '{listing}'\n")
        os.chmod(stub, 0o755)
        output = os.path.join(tmp, "github_output")
        open(output, "w").close()
        env = {"PATH": os.environ["PATH"], "GITHUB_OUTPUT": output, "BASE": "base", "HEAD": "head"}
        proc = subprocess.run(["bash", "-e", "-c", script], cwd=tmp, env=env,
                              capture_output=True, text=True)
        if proc.returncode != 0:
            raise SystemExit(f"filterstap faalde ({proc.returncode}):\n{proc.stderr}")
        result = {}
        with open(output) as fh:
            for line in fh:
                k, _, v = line.strip().partition("=")
                result[k] = v
        return result


failures = 0
docs = {name: load(name) for name in WORKFLOWS}

# 1. Statisch: elke job die op changes wacht valt open.
print("== Statische controle: vallen de gestuurde jobs open?")
for wf, doc in docs.items():
    for name, (needs_changes, outputs, job, text) in gated_jobs(doc).items():
        if not outputs:
            continue
        problems = []
        if not needs_changes:
            problems.append("geen needs: changes")
        if str(job.get("if", "")).replace(" ", "") != "${{!cancelled()}}":
            problems.append(f"job-if is {job.get('if')!r}, verwacht !cancelled()")
        if "needs.changes.result != 'success'" not in text:
            problems.append("conditie leest needs.changes.result niet")
        for step in job.get("steps", []):
            cond = str(step.get("if", ""))
            if not cond:
                problems.append(f"stap {step.get('name')!r} heeft geen conditie")
            elif "== 'false'" in cond and step.get("name") != "Niets te draaien":
                problems.append(f"stap {step.get('name')!r} draait alleen bij false")
            elif "!= 'false'" not in cond and "== 'false'" not in cond:
                problems.append(f"stap {step.get('name')!r} heeft een conditie zonder open val")
        status = "ok" if not problems else "FOUT: " + "; ".join(problems)
        if problems:
            failures += 1
        print(f"  {wf:18} {name:40} stuurt op {','.join(outputs):17} {status}")

# 2. Dynamisch: de voorbeelden door de echte filterstappen.
print()
print("== Voorbeeldwijzigingen door de echte filterstappen")
for label, files, expected in CASES:
    results = {wf: run_filter(filter_script(doc), files) for wf, doc in docs.items()}
    print(f"\n-- {label}  ({'alle bestanden' if files is None else ', '.join(files) or 'geen bestanden'})")
    for wf, res in results.items():
        print(f"   {wf:18} " + " ".join(f"{k}={v}" for k, v in sorted(res.items())))
    for wf, doc in docs.items():
        for name, (needs_changes, outputs, _job, _text) in gated_jobs(doc).items():
            if "tvOS" in name:
                continue  # alleen workflow_dispatch en schema, staat los van scoping
            if not outputs:
                state = "draait altijd"
            else:
                runs = any(results[wf].get(o, "true") != "false" for o in outputs)
                state = "DRAAIT" if runs else "overgeslagen (check slaagt)"
            print(f"   {wf:18} {name:40} {state}")
    for key, want in expected.items():
        wf_filter, _, out = key.rpartition(":")
        checked = False
        for wf, res in results.items():
            if (wf_filter and wf != wf_filter) or out not in res:
                continue
            checked = True
            if res[out] != want:
                failures += 1
                print(f"   FOUT: {wf} {out}={res[out]}, verwacht {want}")
        if not checked:
            failures += 1
            print(f"   FOUT: output {key} bestaat in geen enkele workflow")

print()
if failures:
    print(f"ci_scope_selftest: {failures} afwijking(en)")
    sys.exit(1)
print(f"ci_scope_selftest: {len(CASES)} voorbeelden en de statische controle kloppen")
PY
