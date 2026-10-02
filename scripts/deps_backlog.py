#!/usr/bin/env python3
"""Schrijft de body van het doorlopende issue "Dependency-onderhoud".

De vorige body is de enige opslag: een verborgen JSON-regel houdt per major bij
wanneer hij voor het eerst gezien is. Zo blijft de "oudste eerst"-volgorde
kloppen zonder een statusbestand in de repo.

  scripts/deps_backlog.py --outdated o.json --report r.json --previous prev.md \
      --lane "PR #12 bijgewerkt" [--today 2026-10-02]
  scripts/deps_backlog.py --selftest
"""

import argparse
import datetime
import json
import re
import sys

STATE_RE = re.compile(r"<!-- deps-state (\{.*?\}) -->")


def version(p, key):
    x = p.get(key)
    return x.get("version") if isinstance(x, dict) else None


def breaking(cur, lat):
    """Semver-breuk: major verschilt, of bij 0.x de minor."""
    a, b = ([int(x) for x in re.findall(r"\d+", v.split("+")[0].split("-")[0])[:2]] + [0, 0] for v in (cur, lat))
    return a[0] != b[0] or (a[0] == 0 and a[1] != b[1])


def direct_majors(outdated):
    """Directe dependencies die alleen met een ruimere constraint verder kunnen."""
    out = {}
    for p in outdated.get("packages", []):
        if p.get("kind") not in ("direct", "dev"):
            continue
        cur, res, lat = version(p, "current"), version(p, "resolvable"), version(p, "latest")
        if cur and res and lat and res != lat:
            out[p["package"]] = (cur, lat)
    return out


def build(outdated, report, previous, lane, today):
    m = STATE_RE.search(previous or "")
    first_seen = json.loads(m.group(1)) if m else {}
    majors = direct_majors(outdated)
    # Opgeloste majors vallen uit de staat; nieuwe krijgen vandaag.
    first_seen = {k: first_seen.get(k, today) for k in majors}
    # Ook transitieve pakketten: een advisory in de boom telt, wie hem ook meetrekt.
    advisories = sorted(p["package"] for p in outdated.get("packages", []) if p.get("isCurrentAffectedByAdvisory"))

    # Breuken eerst: alleen die zijn een major-branch waard. De rest wacht op een
    # constraint elders (vaak de DEC-026-pin) en lost zich op als die beweegt.
    order = sorted(majors, key=lambda k: (k not in advisories, not breaking(*majors[k]), first_seen[k], k))
    lines = ["Bijgewerkt door `dependency-health.yml` op %s. Niet handmatig bewerken." % today, ""]
    lines += ["## Ring-1-baan", "", lane or "geen uitkomst doorgegeven", ""]

    lines += ["## Security-advisories (`pub outdated`)", ""]
    lines += ["- **%s** is geraakt; eerst deze." % a for a in advisories] or ["Geen."]
    lines.append("")

    lines += ["## Volgende major", ""]
    candidates = [k for k in order if k in advisories or breaking(*majors[k])]
    if candidates:
        nxt = candidates[0]
        why = "security-advisory" if nxt in advisories else "oudste openstaande"
        lines.append("`%s` %s -> %s (%s). Branch: `chore/deps-major-%s`." % (nxt, *majors[nxt], why, nxt))
    else:
        lines.append("Geen directe major open.")
    lines.append("")

    lines += ["## Directe pakketten achter hun constraint", "",
              "| pakket | huidig | nieuwste | soort | sinds |", "| --- | --- | --- | --- | --- |"]
    lines += ["| %s | %s | %s | %s | %s |" % (k, *majors[k], "major" if breaking(*majors[k]) else "constraint",
                                             first_seen[k]) for k in order]
    lines.append("")

    rest = [r for r in report.get("components", []) if r["ring"] >= 2 and r["status"] != "CURRENT"]
    lines += ["## Overige pins (ring 2-3, niet automatisch)", ""]
    for r in rest:
        lines.append("- `%s` ring %d %s: %s -> %s" % (r["component"], r["ring"], r["status"], r["current"], r["available"]))
    if not rest:
        lines.append("Geen.")
    lines += ["", "<!-- deps-state %s -->" % json.dumps(first_seen, sort_keys=True)]
    return "\n".join(lines) + "\n"


def selftest():
    outdated = {"packages": [
        {"package": "a", "kind": "direct", "current": {"version": "1.0.0"},
         "resolvable": {"version": "1.2.0"}, "latest": {"version": "2.0.0"}},
        {"package": "b", "kind": "dev", "current": {"version": "3.0.0"},
         "resolvable": {"version": "3.0.0"}, "latest": {"version": "4.0.0"}},
        {"package": "t", "kind": "transitive", "current": {"version": "1.0.0"},
         "resolvable": {"version": "1.0.0"}, "latest": {"version": "9.0.0"}},
        {"package": "c", "kind": "direct", "current": {"version": "1.0.0"},
         "resolvable": {"version": "1.1.0"}, "latest": {"version": "1.1.0"}},
    ]}
    prev = '<!-- deps-state {"b": "2026-01-01", "gone": "2025-01-01"} -->'
    body = build(outdated, {"components": []}, prev, "ok", "2026-10-02")
    state = json.loads(STATE_RE.search(body).group(1))
    assert state == {"a": "2026-10-02", "b": "2026-01-01"}, state  # transitive/geen-major weg, staat blijft
    assert "`b` 3.0.0 -> 4.0.0 (oudste openstaande)" in body, body
    assert breaking("0.20.2", "0.21.0") and not breaking("0.20.2", "0.20.3")
    assert breaking("1.0.0", "2.0.0+1") and not breaking("2.13.0", "2.16.1")
    outdated["packages"][0]["isCurrentAffectedByAdvisory"] = True
    body = build(outdated, {"components": []}, prev, "ok", "2026-10-02")
    assert "`a` 1.0.0 -> 2.0.0 (security-advisory)" in body, body
    assert build(outdated, {"components": []}, body, "ok", "2026-10-09").count("deps-state") == 1
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdated")
    ap.add_argument("--report")
    ap.add_argument("--previous")
    ap.add_argument("--lane", default="")
    ap.add_argument("--today", default=datetime.date.today().isoformat())
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

    sys.stdout.write(build(json.loads(read(a.outdated, "{}") or "{}"), json.loads(read(a.report, "{}") or "{}"),
                           read(a.previous), a.lane, a.today))


if __name__ == "__main__":
    main()
