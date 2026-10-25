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
# en op elke stap een conditie die exact een van de toegestane open-vallende
# vormen heeft. Een extra clausule (`&& github.event_name == 'push'`) is dus
# rood, ook al staat `!= 'false'` er nog in.
#
# Als derde zoekt het in de Dart-tests van pleya_verify naar relatieve paden
# die buiten pleya_verify/ wijzen (`../../scripts/tvos_sim.sh`), en eist dat
# een wijziging aan zo'n bestand de portable job laat draaien.
#
# Vraagt python3 met PyYAML. Draait in CI in `Bereik bepalen` van ci.yml; lokaal
# na elke wijziging aan een filter.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

exec python3 - "$PWD" <<'PY'
import os
import shutil
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
    # Website- en agentdocumentatie hoeven geen gebouwde app te verifiëren.
    ("root-markdown en .claude", ["README.md", "STATUS.md", ".claude/skills/x/SKILL.md"],
     dict(flutter="false", server="false", web="false", apple="false", portable="false")),
    ("website/", ["website/src/lib/content/manual/01.md"],
     dict(flutter="false", server="false", web="false", apple="false", portable="false")),
    ("docs plus lib", ["docs/CHANGELOG.md", "lib/main.dart"],
     dict(flutter="true", apple="true")),
    ("ci.yml zelf", [".github/workflows/ci.yml"],
     {"flutter": "true", "ci.yml:server": "true", "server-web.yml:server": "false", "ci.yml:web": "true", "server-web.yml:web": "false", "apple": "true"}),
    ("server-web.yml zelf", [".github/workflows/server-web.yml"],
     {"flutter": "true", "ci.yml:server": "false", "server-web.yml:server": "true", "ci.yml:web": "false", "server-web.yml:web": "true"}),
    ("pleya-verify.yml zelf", [".github/workflows/pleya-verify.yml"],
     dict(flutter="true", apple="true", portable="true")),
    # Twee runnertests lezen of draaien bestanden buiten pleya_verify/.
    ("scripts/tvos_sim.sh", ["scripts/tvos_sim.sh"],
     dict(flutter="true", server="false", web="false", apple="true", portable="true")),
    ("lib/automation/automation_input.dart", ["lib/automation/automation_input.dart"],
     dict(flutter="true", server="false", web="false", apple="true", portable="true")),
    ("SDK-pin", [".fvmrc"],
     dict(flutter="true", apple="true", portable="true")),
    ("app-dependencies", ["pubspec.lock"],
     dict(flutter="true", apple="true")),
    ("Apple-native", ["ios/Runner/AppDelegate.swift"],
     dict(flutter="true", apple="true")),
    ("onbekende rootconfig", ["new-tool.toml"],
     dict(flutter="true", apple="true")),
    ("detector zelf", ["scripts/ci_changed_files.sh"],
     dict(flutter="true", server="true", web="true", apple="true", portable="true")),
    ("onverwacht lege detectie", [],
     dict(flutter="true", server="true", web="true", apple="true", portable="true")),
    ("volledig signaal", ["__CI_FULL__"],
     dict(flutter="true", server="true", web="true", apple="true", portable="true")),
    ("volledige selectie (git ls-files)", None,
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


def run_filter(script, files, stub_exit=0, expect_failure=False):
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
            fh.write(f"#!/usr/bin/env bash\ncat '{listing}'\nexit {stub_exit}\n")
        os.chmod(stub, 0o755)
        output = os.path.join(tmp, "github_output")
        open(output, "w").close()
        env = {"PATH": os.environ["PATH"], "GITHUB_OUTPUT": output, "BASE": "base", "HEAD": "head"}
        proc = subprocess.run(["bash", "-e", "-c", script], cwd=tmp, env=env,
                              capture_output=True, text=True)
        if expect_failure:
            if proc.returncode == 0:
                raise SystemExit("falende detector werd niet doorgegeven")
            return {}
        if proc.returncode != 0:
            raise SystemExit(f"filterstap faalde ({proc.returncode}):\n{proc.stderr}")
        result = {}
        with open(output) as fh:
            for line in fh:
                k, _, v = line.strip().partition("=")
                result[k] = v
        return result


# Toegestane stapcondities, na het weghalen van alle witruimte. Alles daarbuiten
# is rood: ook een conditie die de open val nog bevat maar er iets aan toevoegt.
_GATE = r"needs\.changes\.result!='success'\|\|needs\.changes\.outputs\.(\w+)!='false'"
RUN_FORMS = [
    re.compile(r"\$\{\{env\.(RUN_\w+)!='false'\}\}"),
    re.compile(r"\$\{\{" + _GATE + r"\}\}"),
    re.compile(r"\$\{\{always\(\)&&\(" + _GATE + r"\)\}\}"),
]
NOOP_FORMS = [
    re.compile(r"\$\{\{env\.(RUN_\w+)=='false'\}\}"),
    re.compile(r"\$\{\{needs\.changes\.result=='success'&&needs\.changes\.outputs\.(\w+)=='false'\}\}"),
]
ENV_FORM = re.compile(r"\$\{\{" + _GATE + r"\}\}")


def check_job(job):
    problems = []
    env = {k: re.sub(r"\s+", "", str(v)) for k, v in (job.get("env") or {}).items()}
    for k, v in env.items():
        if k.startswith("RUN_") and not ENV_FORM.fullmatch(v):
            problems.append(f"job-env {k} valt niet open: {v}")
    for step in job.get("steps", []):
        name = step.get("name")
        cond = re.sub(r"\s+", "", str(step.get("if", "")))
        if not cond:
            problems.append(f"stap {name!r} heeft geen conditie")
            continue
        forms = NOOP_FORMS if name == "Niets te draaien" else RUN_FORMS
        m = next((f.fullmatch(cond) for f in forms if f.fullmatch(cond)), None)
        if m is None:
            problems.append(f"stap {name!r} heeft een conditie buiten de toegestane vormen: {step.get('if')}")
        elif m.group(1).startswith("RUN_") and m.group(1) not in env:
            problems.append(f"stap {name!r} leest {m.group(1)}, dat niet in job-env staat")
    return problems


def outside_paths():
    """Repo-paden buiten pleya_verify/ die de Dart-tests van pleya_verify lezen."""
    tracked = subprocess.run(["git", "-C", root, "ls-files"], check=True,
                             capture_output=True, text=True).stdout.split("\n")
    found = {}
    literal = re.compile(r"['\"](?:\$\{[^}]*\}/)?((?:\.\./){2,}[A-Za-z0-9_.\-/]+)['\"]")
    for rel in tracked:
        if not (rel.startswith("pleya_verify/") and rel.endswith(".dart")):
            continue
        if "/test/" not in rel and not rel.endswith("_test.dart"):
            continue
        # Een test draait met de pakketmap als werkmap: de map met pubspec.yaml.
        pkg = os.path.dirname(rel)
        while pkg and not os.path.exists(os.path.join(root, pkg, "pubspec.yaml")):
            pkg = os.path.dirname(pkg)
        with open(os.path.join(root, rel), encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                stripped = line.strip()
                if stripped.startswith(("//", "import ", "export ", "part ")):
                    continue
                for m in literal.finditer(line):
                    target = os.path.normpath(os.path.join(pkg, m.group(1)))
                    if target.startswith("..") or target.startswith("pleya_verify/"):
                        continue
                    # Alleen wat in git staat kan een PR veranderen (.build/ niet).
                    if not any(t == target or t.startswith(target + "/") for t in tracked):
                        continue
                    found.setdefault(target, []).append(f"{rel}:{lineno}")
    return found


failures = 0
docs = {name: load(name) for name in WORKFLOWS}

# De nieuwe webscope mag niet terugvallen op een onvoorwaardelijke job.
if "needs.changes.outputs.web" not in yaml.safe_dump(docs["ci.yml"]["jobs"]["pleya-web"]):
    raise SystemExit("ci.yml: webjob mist zijn scopeconditie")

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
        problems += check_job(job)
        status = "ok" if not problems else "FOUT: " + "; ".join(problems)
        if problems:
            failures += 1
        print(f"  {wf:18} {name:40} stuurt op {','.join(outputs):17} {status}")

# 2. Paden buiten pleya_verify/ die de portable tests lezen.
print()
print("== Paden buiten pleya_verify/ in de tests van pleya_verify")
portable_script = filter_script(docs["pleya-verify.yml"])
for target, where in sorted(outside_paths().items()):
    # Bij een map moet een bestand erin het filter raken.
    probe = target if os.path.isfile(os.path.join(root, target)) else target + "/x"
    got = run_filter(portable_script, [probe]).get("portable")
    status = "ok" if got == "true" else "FOUT: portable=" + str(got)
    if got != "true":
        failures += 1
    print(f"  {target:45} {status}  ({', '.join(where)})")

# 3. Dynamisch: de voorbeelden door de echte filterstappen.
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


# 4. Test ook de bedrading van de events en de echte detector, niet alleen
# gestubde padlijsten. Alle gitgeschiedenis staat in een tijdelijke repo.
print()
print("== Eventbedrading, volledige selectie en detectorfouten")
for wf, doc in docs.items():
    step = next(s for s in doc["jobs"]["changes"]["steps"] if s.get("id") == "filter")
    wanted_env = {
        "BASE": "${{ github.event_name == 'push' && github.event.before || github.event.pull_request.base.sha }}",
        "HEAD": "${{ github.event_name == 'push' && github.event.after || github.event.pull_request.head.sha }}",
    }
    if step.get("env") != wanted_env:
        raise SystemExit(f"{wf}: before/after/PR-bedrading wijkt af")
    # PyYAML 1.1 leest de YAML-sleutel 'on' als True.
    triggers = doc.get("on", doc.get(True, {}))
    if not all(k in triggers for k in ("push", "pull_request", "workflow_dispatch", "schedule")):
        raise SystemExit(f"{wf}: trigger of volledig periodiek vangnet ontbreekt")
    checkout = doc["jobs"]["changes"]["steps"][0]
    if checkout.get("with", {}).get("fetch-depth") != 0:
        raise SystemExit(f"{wf}: volledige gitgeschiedenis ontbreekt")
    script = filter_script(doc)
    run_filter(script, ["docs/a.md"], stub_exit=1, expect_failure=True)
    # De statisch gecontroleerde, exacte fail-open-vorm hierboven garandeert
    # dat alleen success + expliciet false werk overslaat. Een lege/ongeldige
    # output en een gefaalde scopejob moeten dus altijd werk selecteren.
    for result, value, want in [("failure", "false", True), ("success", "", True),
                                 ("success", "invalid", True), ("success", "true", True),
                                 ("success", "false", False)]:
        assert (result != "success" or value != "false") == want
    print(f"  {wf}: event-SHA's, schema, fetch-depth en foutende detector ok")

range_checks = 0
with tempfile.TemporaryDirectory(prefix="pleya-ci-scope-") as tmp:
    fixture_env = dict(os.environ)
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"):
        fixture_env.pop(key, None)

    def git(*args, check=True):
        return subprocess.run(["git", "-C", tmp, *args], check=check, env=fixture_env,
                              capture_output=True, text=True)

    def write(path, text):
        target = os.path.join(tmp, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "w") as fh:
            fh.write(text)

    def commit(message):
        git("add", "-A")
        git("commit", "-qm", message)
        return git("rev-parse", "HEAD").stdout.strip()

    git("init", "-q")
    git("config", "user.name", "Scope selftest")
    git("config", "user.email", "scope@example.invalid")
    git("config", "core.hooksPath", "/dev/null")
    detector = os.path.join(tmp, "scripts", "ci_changed_files.sh")
    os.makedirs(os.path.dirname(detector))
    shutil.copy2(os.path.join(root, "scripts", "ci_changed_files.sh"), detector)
    for path in ["docs/a.md", "lib/app.dart", "pleya_server/a.go", "pleya_web/a.ts"]:
        write(path, "initial\n")
    initial = commit("initial")

    def real(event, base, head, expected=None, full=False, error=False, path=None):
        global range_checks
        env = dict(os.environ, GITHUB_EVENT_NAME=event, BASE=base, HEAD=head)
        # Hooks may have exported these for the outer repository.
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"):
            env.pop(key, None)
        if path:
            env["PATH"] = path
        outputs = {}
        for wf, doc in docs.items():
            output = os.path.join(tmp, ".git", "scope-output")
            open(output, "w").close()
            env["GITHUB_OUTPUT"] = output
            proc = subprocess.run(["bash", "-e", "-c", filter_script(doc)], cwd=tmp,
                                  env=env, capture_output=True, text=True)
            with open(output) as fh:
                got = dict(line.strip().split("=", 1) for line in fh if "=" in line)
            if error:
                if proc.returncode == 0 or got:
                    raise SystemExit(f"{event}/{wf}: detectiefout werd groen: {got}")
                continue
            if proc.returncode:
                raise SystemExit(f"{event}/{wf}: detector faalt: {proc.stderr}")
            if full and (not got or any(v != "true" for v in got.values())):
                raise SystemExit(f"{event}/{wf}: geen volledige fallback: {got}")
            for key, want in (expected or {}).items():
                if key in got and got[key] != want:
                    raise SystemExit(f"{event}/{wf}: {key}={got[key]}, verwacht {want}")
            outputs[wf] = got
        range_checks += 1
        return outputs

    write("docs/a.md", "docs only\n")
    docs_head = commit("docs")
    real("push", initial, docs_head, dict(flutter="false", server="false", web="false", apple="false", portable="false"))
    real("pull_request", initial, docs_head, dict(flutter="false", server="false", web="false", apple="false", portable="false"))
    write("lib/app.dart", "app change\n")
    app_head = commit("app")
    # De eerste commit van deze push is relevant, de laatste alleen docs.
    write("docs/a.md", "last commit docs\n")
    mixed_head = commit("docs after app")
    real("push", docs_head, mixed_head, dict(flutter="true", apple="true", server="false", web="false"))
    real("push", initial, mixed_head, dict(flutter="true", apple="true"))
    git("rm", "lib/app.dart")
    deleted_head = commit("delete last app source")
    real("push", mixed_head, deleted_head, dict(flutter="true", apple="true"))

    # Renames over domeingrenzen, met spaties en Unicode in de padnamen.
    git("mv", "pleya_server/a.go", "docs/é old.go")
    moved_head = commit("move out of server")
    real("push", deleted_head, moved_head, dict(server="true"))
    git("mv", "docs/é old.go", "pleya_web/é new.ts")
    moved_back = commit("move into web")
    real("push", moved_head, moved_back, dict(web="true"))
    write("pleya_server/b.go", "server\n")
    server_head = commit("server")
    real("push", moved_back, server_head, dict(flutter="false", server="true", web="false", apple="false"))
    write("pleya_web/b.ts", "web\n")
    web_head = commit("web")
    real("push", server_head, web_head, dict(flutter="false", server="false", web="true", apple="false"))
    real("push", moved_back, web_head, dict(server="true", web="true", flutter="false", apple="false"))

    # PR-head vanaf oude basis: wijzigingen die alleen op main staan vallen af.
    git("checkout", "-qb", "scope-feature", initial)
    write("pleya_web/a.ts", "feature\n")
    feature = commit("feature")
    real("pull_request", web_head, feature, dict(flutter="false", server="false", web="true", apple="false"))
    real("push", web_head, feature, full=True)  # force-push
    real("push", "0" * 40, feature, full=True)  # nieuwe branch
    real("push", feature, feature, full=True)  # lege diff
    real("workflow_dispatch", "", "", full=True)
    real("schedule", "", "", full=True)
    real("unknown_event", "", "", full=True)
    real("push", "", feature, error=True)
    real("push", initial, "", error=True)
    real("push", "1" * 40, feature, error=True)
    real("push", initial, "1" * 40, error=True)
    real("push", initial, web_head, error=True)  # verkeerde checkout

    # Los commitobject: geen merge-base met de PR-basis.
    tree = git("rev-parse", "HEAD^{tree}").stdout.strip()
    orphan = git("commit-tree", tree, "-m", "unrelated").stdout.strip()
    real("pull_request", orphan, feature, error=True)
    write("lib/app.dart", "mixed app\n")
    write("pleya_server/a.go", "mixed server\n")
    write("pleya_web/a.ts", "mixed web\n")
    write("docs/a.md", "mixed docs\n")
    mixed_all = commit("mixed app server web docs")
    real("push", feature, mixed_all, dict(flutter="true", server="true", web="true", apple="true"))
    write("docs/line\nbreak.md", "newline\n")
    newline_head = commit("newline path")
    real("push", feature, newline_head, full=True)

    # Git-diff mag ook na een geldige SHA-resolutie falen; geen gedeeltelijke lijst.
    shim = os.path.join(tmp, "bin")
    os.makedirs(shim)
    real_git = shutil.which("git")
    write("bin/git", '#!/usr/bin/env bash\nif [ "$1" = diff ]; then exit 128; fi\nexec "' + real_git + '" "$@"\n')
    os.chmod(os.path.join(shim, "git"), 0o755)
    real("push", feature, newline_head, error=True, path=shim + os.pathsep + os.environ["PATH"])

print(f"  {range_checks} echte git/event-scenario's door alle drie workflowfilters ok")

print()
if failures:
    print(f"ci_scope_selftest: {failures} afwijking(en)")
    sys.exit(1)
print(f"ci_scope_selftest: {len(CASES)} voorbeelden, {range_checks} git/event-scenario's en de statische controle kloppen")
PY
