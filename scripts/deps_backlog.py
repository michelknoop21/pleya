#!/usr/bin/env python3
"""Schrijft de body van het doorlopende issue "Dependency-onderhoud".

De vorige body is de enige opslag: een verborgen JSON-regel houdt per major bij
wanneer hij voor het eerst gezien is. Zo blijft de "oudste eerst"-volgorde
kloppen zonder een statusbestand in de repo.

  scripts/deps_backlog.py --outdated o.json --report r.json --previous prev.md \
      --lane "PR #12 bijgewerkt" [--today 2026-10-02] \
      [--majors-open prs.json] [--majors-branches heads.txt] [--note naam=tekst] [--skip naam]
  scripts/deps_backlog.py --next-major --outdated o.json --report r.json \
      --previous prev.md --majors-open prs.json --majors-branches heads.txt
  scripts/deps_backlog.py --selftest

--next-major drukt één regel af: "<kandidaat> <pakket> [<pakket> ...]", of niets.
--majors-open is de uitvoer van `gh pr list --state open --json number,headRefName`,
--majors-branches die van `git ls-remote --heads origin 'chore/deps-major-*'`.
"""

import argparse
import datetime
import json
import re
import sys

STATE_RE = re.compile(r"<!-- deps-state (\{.*?\}) -->")
BRANCH_PREFIX = "chore/deps-major-"

# Pakketten die samen moeten verhuizen omdat ze dezelfde transitieve eis delen
# (alle drie win32 ^6). Een bundel is één kandidaat, met de oudste datum van zijn leden.
DEP_GROUPS = {"plus": ["device_info_plus", "package_info_plus", "share_plus"]}

# Majors die bewust stilstaan, naast de BLOCKED-rij uit check_updates.sh.
DEP_BLOCKED = {"freezed": "DEC-026: vraagt analyzer >=14"}


def version(p, key):
    x = p.get(key)
    return x.get("version") if isinstance(x, dict) else None


def breaking(cur, lat):
    """Semver-breuk: major verschilt, of bij 0.x de minor."""
    a, b = ([int(x) for x in re.findall(r"\d+", v.split("+")[0].split("-")[0])[:2]] + [0, 0] for v in (cur, lat))
    return a[0] != b[0] or (a[0] == 0 and a[1] != b[1])


def direct_majors(outdated):
    """Directe dependencies die alleen met een ruimere constraint verder kunnen.

    Waarde: (huidig, nieuwste, resolvable). Wat binnen de constraint al kan
    (upgradable == nieuwste) is werk van de ring-1-baan."""
    out = {}
    for p in outdated.get("packages", []):
        if p.get("kind") not in ("direct", "dev"):
            continue
        cur, res, lat = version(p, "current"), version(p, "resolvable"), version(p, "latest")
        within = version(p, "upgradable") or res
        if cur and res and lat and within != lat:
            out[p["package"]] = (cur, lat, res)
    return out


def units(majors, advisories):
    """Kandidaten: bundels of losse pakketten. Alleen leden met een echte breuk (of advisory)."""
    grouped = {m: g for g, ms in DEP_GROUPS.items() for m in ms}
    out = {}
    for k, (cur, lat, _) in majors.items():
        if breaking(cur, lat) or k in advisories:
            out.setdefault(grouped.get(k, k), []).append(k)
    return {u: sorted(ms) for u, ms in out.items()}


def blocked_names(report):
    """Namen in de BLOCKED-rijen van check_updates.sh (DEC-026, rate_limiter)."""
    text = " ".join(str(v) for r in report.get("components", []) if r.get("status") == "BLOCKED" for v in r.values())
    return set(re.findall(r"[a-z][a-z0-9_]+", text))


def unit_status(name, members, majors, report, prs, branches, notes, skip=(), advisories=()):
    """(status, kiesbaar). Volgorde: lopende PR of branch, blocked, wacht, open."""
    note = notes.get(name)
    tail = ", " + note if note else ""
    for pr in prs:
        if pr.get("headRefName") == BRANCH_PREFIX + name:
            return "PR #%s%s" % (pr["number"], tail), False
    if BRANCH_PREFIX + name in branches:
        return "branch" + tail, False
    why = [DEP_BLOCKED[m] for m in members if m in DEP_BLOCKED]
    # pub.dev markeert een leeggehaalde opvolger met +eol; die is geen migratie maar een afvoerputje.
    why += ["EOL-stub (+eol) als resolvable of nieuwste: " + m for m in members if "+eol" in majors[m][1] + majors[m][2]]
    if not why:
        gate = blocked_names(report)
        why = ["geblokkeerd in check_updates.sh: " + m for m in members if m in gate]
    if why:
        return "blocked: " + why[0], False
    # Resolvable blijft onder de major van latest: nu niet te bereiken op deze
    # runtime en graph. Geen hardcoded lijst; het verschuift vanzelf mee.
    # skip: de probe van de job vond in deze run geen constraint die verschuift.
    # Een advisory die een patch of minor achter een exacte constraint vraagt, telt ook als bereikbaar.
    reach = any(breaking(majors[m][0], majors[m][2]) or (m in advisories and majors[m][2] != majors[m][0]) for m in members)
    if name in skip or not reach:
        return "wacht op flutter-sdk of graph", False
    return "open", True


def pick_major(outdated, report, previous, today, prs=(), branches=(), notes=None, skip=()):
    """(kandidaat, pakketten) of None. Een lopende major-PR houdt de baan vast (WIP 1)."""
    first_seen, majors, advisories = state_of(outdated, previous, today)
    notes = notes or {}
    us = units(majors, advisories)
    rows = {u: unit_status(u, ms, majors, report, prs, branches, notes, skip, advisories) for u, ms in us.items()}
    if any(pr.get("headRefName", "").startswith(BRANCH_PREFIX) for pr in prs):
        return None
    ready = [u for u in us if rows[u][1]]
    ready.sort(key=lambda u: (not any(m in advisories for m in us[u]), min(first_seen[m] for m in us[u]), u))
    return (ready[0], us[ready[0]]) if ready else None


def state_of(outdated, previous, today):
    m = STATE_RE.search(previous or "")
    try:
        first_seen = json.loads(m.group(1)) if m else {}
    except json.JSONDecodeError:
        # Handmatig kapotgemaakte staat: opnieuw beginnen in plaats van elke week falen.
        first_seen = {}
    majors = direct_majors(outdated)
    # Opgeloste majors vallen uit de staat; nieuwe krijgen vandaag.
    first_seen = {k: first_seen.get(k, today) for k in majors}
    # Ook transitieve pakketten: een advisory in de boom telt, wie hem ook meetrekt.
    advisories = sorted(p["package"] for p in outdated.get("packages", []) if p.get("isCurrentAffectedByAdvisory"))
    return first_seen, majors, advisories


def build(outdated, report, previous, lane, today, prs=(), branches=(), notes=None, skip=()):
    first_seen, majors, advisories = state_of(outdated, previous, today)
    notes = notes or {}
    us = units(majors, advisories)
    status = {u: unit_status(u, ms, majors, report, prs, branches, notes, skip, advisories)[0] for u, ms in us.items()}
    of_unit = {m: u for u, ms in us.items() for m in ms}
    since = {u: min(first_seen[m] for m in ms) for u, ms in us.items()}

    # Breuken eerst: alleen die zijn een major-branch waard. De rest wacht op een
    # constraint elders (vaak de DEC-026-pin) en lost zich op als die beweegt.
    order = sorted(majors, key=lambda k: (k not in advisories, k not in of_unit, first_seen[k], k))
    lines = ["Bijgewerkt door `dependency-health.yml` op %s. Niet handmatig bewerken." % today, ""]
    lines += ["## Ring-1-baan", "", lane or "geen uitkomst doorgegeven", ""]

    lines += ["## Security-advisories (`pub outdated`)", ""]
    lines += ["- **%s** is geraakt; eerst deze." % a for a in advisories] or ["Geen."]
    lines.append("")

    lines += ["## Volgende major", ""]
    nxt = pick_major(outdated, report, previous, today, prs, branches, notes, skip)
    if nxt:
        name, pkgs = nxt
        why = "security-advisory" if any(m in advisories for m in pkgs) else "oudste openstaande"
        lines.append("`%s` (%s; %s). Branch: `%s%s`." % (name, ", ".join(pkgs), why, BRANCH_PREFIX, name))
    elif any(pr.get("headRefName", "").startswith(BRANCH_PREFIX) for pr in prs):
        lines.append("Wacht: er staat al een major-PR open (WIP-limiet 1).")
    else:
        lines.append("Geen directe major die nu te bereiken is.")
    lines.append("")

    lines += ["## Directe pakketten achter hun constraint", "",
              "| pakket | huidig | nieuwste | soort | sinds | status |", "| --- | --- | --- | --- | --- | --- |"]
    for k in order:
        u = of_unit.get(k)
        kind = "major" if u else "constraint"
        label = status[u] if u else ""
        if u and u != k:
            label += " (bundel %s)" % u
        lines.append("| %s | %s | %s | %s | %s | %s |" % (k, majors[k][0], majors[k][1], kind,
                                                       since[u] if u else first_seen[k], label))
    lines.append("")

    rest = [r for r in report.get("components", []) if r["ring"] >= 2 and r["status"] != "CURRENT"]
    lines += ["## Overige pins (ring 2-3, niet automatisch)", ""]
    for r in rest:
        lines.append("- `%s` ring %d %s: %s -> %s" % (r["component"], r["ring"], r["status"], r["current"], r["available"]))
    if not rest:
        lines.append("Geen.")
    lines += ["", "<!-- deps-state %s -->" % json.dumps(first_seen, sort_keys=True)]
    return "\n".join(lines) + "\n"


def pkg(name, cur, upg, res, lat, kind="direct", **extra):
    v = lambda x: {"version": x}
    return dict(package=name, kind=kind, current=v(cur), upgradable=v(upg), resolvable=v(res), latest=v(lat), **extra)


def selftest():
    outdated = {"packages": [
        pkg("a", "1.0.0", "1.2.0", "2.0.0", "2.0.0"),                  # major bereikbaar
        pkg("b", "3.0.0", "3.0.0", "3.0.0", "4.0.0"),                  # latest niet resolvable
        pkg("t", "1.0.0", "1.0.0", "1.0.0", "9.0.0", kind="transitive"),
        pkg("c", "1.0.0", "1.1.0", "1.1.0", "1.1.0"),                  # ring 1, geen major
        pkg("freezed", "3.2.5", "3.2.5", "4.0.0", "4.0.0", kind="dev"),  # DEC-026
        pkg("device_info_plus", "12.3.0", "12.4.0", "12.4.0", "13.3.0"),
        pkg("package_info_plus", "9.0.0", "9.0.1", "9.0.1", "10.2.2"),
        pkg("share_plus", "11.1.0", "11.1.0", "12.0.2", "13.3.1"),
    ]}
    rep = {"components": []}
    prev = '<!-- deps-state {"a": "2026-09-01", "b": "2026-01-01", "device_info_plus": "2026-05-01", "gone": "2025-01-01"} -->'
    body = build(outdated, rep, prev, "ok", "2026-10-02")
    state = json.loads(STATE_RE.search(body).group(1))
    assert state["b"] == "2026-01-01" and state["a"] == "2026-09-01" and "t" not in state and "c" not in state, state
    assert "gone" not in state and state["share_plus"] == "2026-10-02", state

    # (1) bundel is één kandidaat met de oudste datum van zijn leden
    pick = lambda o=outdated, **kw: pick_major(o, rep, prev, "2026-10-02", **kw)
    assert pick() == ("plus", ["device_info_plus", "package_info_plus", "share_plus"]), pick()
    assert "`plus` (device_info_plus, package_info_plus, share_plus; oudste openstaande)" in body, body
    # (2) freezed en (3) wacht-op-resolutie worden nooit gekozen
    only = {"packages": [outdated["packages"][i] for i in (1, 4)]}
    assert pick(only) is None
    assert "| freezed | 3.2.5 | 4.0.3" not in body and "blocked: DEC-026" in body and "wacht op flutter-sdk" in body, body
    # (4) een lopende major-PR houdt de baan vast; een kale remote branch slaat alleen zijn eigen kandidaat over
    assert pick(prs=[{"number": 7, "headRefName": "chore/deps-major-a"}]) is None
    assert pick(branches={"chore/deps-major-plus"})[0] == "a"
    assert "PR #7, blocked: ci" in build(outdated, rep, prev, "ok", "2026-10-02", prs=[{"number": 7, "headRefName": BRANCH_PREFIX + "a"}],
                                         notes={"a": "blocked: ci"})
    # (5) hoogstens één kandidaat, (6) advisory gaat voor de oudste
    assert len(pick()) == 2
    assert pick(skip={"plus"})[0] == "a" and "wacht op flutter-sdk of graph (bundel plus)" in build(
        outdated, rep, prev, "ok", "2026-10-02", skip={"plus"})
    adv = {"packages": [dict(outdated["packages"][0], isCurrentAffectedByAdvisory=True)] + outdated["packages"][1:]}
    assert pick(adv)[0] == "a", pick(adv)
    # BLOCKED-rij uit check_updates.sh telt ook
    blk = {"components": [{"component": "dart-blocked", "ring": 2, "status": "BLOCKED", "reason": "a"}]}
    assert pick_major(outdated, blk, prev, "2026-10-02")[0] == "plus"
    patch = {"packages": [pkg("p", "4.6.4", "4.6.4", "4.6.5", "4.6.5", isCurrentAffectedByAdvisory=True),
                          pkg("q", "4.6.4", "4.6.4", "4.6.5", "4.6.5")]}
    assert pick(patch) == ("p", ["p"]), pick(patch)  # advisory zonder breuk: wel kandidaat; q is geen advisory en geen breuk
    eol = {"packages": [pkg("sqlite3_flutter_libs", "0.5.42", "0.5.42", "0.6.0+eol", "0.6.0+eol")]}
    assert pick(eol) is None
    assert breaking("0.20.2", "0.21.0") and not breaking("0.20.2", "0.20.3")
    assert breaking("1.0.0", "2.0.0+1") and not breaking("2.13.0", "2.16.1")
    assert build(outdated, rep, body, "ok", "2026-10-09").count("deps-state") == 1
    assert "deps-state" in build(outdated, rep, "<!-- deps-state {kapot} -->", "ok", "2026-10-02")
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdated")
    ap.add_argument("--report")
    ap.add_argument("--previous")
    ap.add_argument("--lane", default="")
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    ap.add_argument("--majors-open", help="gh pr list --json number,headRefName")
    ap.add_argument("--majors-branches", help="git ls-remote --heads origin 'chore/deps-major-*'")
    ap.add_argument("--note", action="append", default=[], help="kandidaat=tekst, achter de status")
    ap.add_argument("--skip", action="append", default=[], help="kandidaat die deze run niet resolveert")
    ap.add_argument("--next-major", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()

    def read(path, default=""):
        try:
            with open(path, encoding="utf-8") as fh:
                return fh.read()
        except (OSError, TypeError):
            return default

    outdated = json.loads(read(a.outdated, "{}") or "{}")
    report = json.loads(read(a.report, "{}") or "{}")
    prs = [p for p in json.loads(read(a.majors_open, "[]") or "[]") if p.get("headRefName", "").startswith(BRANCH_PREFIX)]
    branches = {m.group(1) for m in re.finditer(r"refs/heads/(\S+)", read(a.majors_branches))}
    notes = dict(n.split("=", 1) for n in a.note if "=" in n)
    previous = read(a.previous)
    if a.next_major:
        nxt = pick_major(outdated, report, previous, a.today, prs, branches, notes, set(a.skip))
        print(" ".join([nxt[0], *nxt[1]]) if nxt else "")
        return
    sys.stdout.write(build(outdated, report, previous, a.lane, a.today, prs, branches, notes, set(a.skip)))


if __name__ == "__main__":
    main()
