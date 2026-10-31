"""Synthetische droogloop voor PS-12: Plex-kijkstatus naar watch_states (0004).

Draait volledig in het geheugen op fixture.json naast dit bestand. Geen netwerk,
geen database, geen echte Plex-data. Uitvoeren met:

    python3 -I docs/qa/ps12-synthetic/dryrun.py

De matchregels volgen lib/services/unified_catalog/grouping_service.dart,
lib/media/unified/identity_evidence.dart en canonical_media_identity.dart.
Waar dit script een keuze maakt die nog een open besluit is (play_count,
conflictregel, last_explicit_*), staat dat bij de functie.
"""

import copy
import hashlib
import json
import re
import sys
from pathlib import Path

FIXTURE = Path(__file__).resolve().parent / "fixture.json"
SUPPORTED_TYPES = {"movie", "episode"}
ACTION = "watch_state.create"


# --- identiteit, zoals in de Dart-code ------------------------------------

def normalize_title(title):
    """normalizeTitleForMatching: lowercase, '(jjjj)' weg, alles buiten a-z0-9 weg."""
    if title is None:
        return None
    t = title.lower()
    t = re.sub(r"\(\d{4}\)", " ", t)
    t = re.sub(r"[^a-z0-9]+", "", t)
    return t or None


def bucket_key(kind, title, year=None, season=None, episode=None):
    """CanonicalMediaIdentity.bucketKey."""
    norm = normalize_title(title)
    if norm is None:
        return None
    if kind in ("movie", "show"):
        return f"{kind}:{norm}:{'' if year is None else year}"
    if kind == "episode":
        if season is None or episode is None:
            return None
        return f"episode:{norm}:{season}:{episode}"
    return None


def stable_guid(guid):
    """normalizeStableGuid: alleen scheme://, nooit agents.none://."""
    value = (guid or "").strip()
    if not value or "://" not in value or "agents.none://" in value:
        return None
    return value.lower()


def external_ids(guid_array):
    """ExternalIds.fromGuids: imdb://, tmdb://, tvdb:// uit de Guid-array."""
    ids = {}
    for entry in guid_array or []:
        raw = entry.get("id", "")
        for ns in ("imdb", "tmdb", "tvdb"):
            prefix = ns + "://"
            if raw.startswith(prefix):
                ids[ns] = raw[len(prefix):].strip().lower()
    return ids


def id_tokens(scope, ids, discriminator=None):
    """externalIdTokens: scope:namespace:value, met /sXeY voor afleveringen."""
    suffix = f"/{discriminator}" if discriminator else ""
    return {(scope, ns, f"{v}{suffix}") for ns, v in ids.items()}


def conflicting(tokens_a, tokens_b):
    """_hasConflictingToken: zelfde scope en namespace, andere waarde."""
    return any(a[0] == b[0] and a[1] == b[1] and a[2] != b[2] for a in tokens_a for b in tokens_b)


# --- Pleya-catalogus indexeren -----------------------------------------------

def index_pleya(pleya):
    items = {i["id"]: i for i in pleya["media_items"]}
    tmdb = {c["item_id"]: c["external_id"] for c in pleya["metadata_candidates"]
            if c["provider"] == "tmdb" and c["state"] == "matched"}
    tokens_of, by_token, by_bucket = {}, {}, {}
    for item in items.values():
        toks, bkey = set(), None
        if item["kind"] in ("movie", "show"):
            if item["id"] in tmdb:
                toks = id_tokens(item["kind"], {"tmdb": tmdb[item["id"]]})
            bkey = bucket_key(item["kind"], item["title"], item["year"])
        elif item["kind"] == "episode":
            season = items[item["parent_id"]]
            show = items[season["parent_id"]]
            if show["id"] in tmdb:
                disc = f"s{season['item_index']}e{item['item_index']}"
                toks = id_tokens("episode", {"tmdb": tmdb[show["id"]]}, disc)
            bkey = bucket_key("episode", show["title"], None, season["item_index"], item["item_index"])
        tokens_of[item["id"]] = toks
        for t in toks:
            by_token.setdefault(t, set()).add(item["id"])
        if bkey:
            by_bucket.setdefault(bkey, []).append(item["id"])
    return {"items": items, "tokens_of": tokens_of, "by_token": by_token, "by_bucket": by_bucket}


# --- Plex-rij naar identiteit ------------------------------------------------

def plex_identity(row, grandparents):
    """Sterke tokens en bucket van een Plex-rij, zoals identity_resolver ze opbouwt."""
    kind = row["type"]
    guid_scope = "episode" if kind == "episode" else kind
    guid_tokens = set()
    g = stable_guid(row.get("guid"))
    if g:
        guid_tokens.add((guid_scope, "guid", g))
    if kind == "episode":
        gp = grandparents[row["grandparentRatingKey"]]["MediaContainer"]["Metadata"][0]
        disc = f"s{row['parentIndex']}e{row['index']}"
        ext = id_tokens("episode", external_ids(gp.get("Guid")), disc)
        bkey = bucket_key("episode", row.get("grandparentTitle"), None, row.get("parentIndex"), row.get("index"))
        year = None
    else:
        ext = id_tokens(kind, external_ids(row.get("Guid")))
        bkey = bucket_key(kind, row.get("title"), row.get("year"))
        year = row.get("year")
    return guid_tokens, ext, bkey, year


def match(row, grandparents, idx, plex_bucket_counts, confirmed):
    """Stap 1 sterke tokens (guid, dan externe ids), stap 2 titel/jaar.

    Geeft (uitkomst, item_id, reden). Uitkomsten: zeker, bevestigd, ambigu,
    wacht, geen.
    """
    guid_tokens, ext_tokens, bkey, year = plex_identity(row, grandparents)
    hits = set()
    for t in guid_tokens | ext_tokens:
        hits |= idx["by_token"].get(t, set())
    if len(hits) == 1:
        return "zeker", next(iter(hits)), "sterk token"
    if len(hits) > 1:
        return "ambigu", None, f"{len(hits)} Pleya-items delen een sterk token"
    # Stap 2: de zwakke terugval van hoofdstuk 11.6.
    if bkey is None:
        return "geen", None, "geen bucket"
    candidates = idx["by_bucket"].get(bkey, [])
    if not candidates:
        return "geen", None, "geen titel/jaar-kandidaat"
    if len(candidates) > 1:
        return "ambigu", None, f"C19: {len(candidates)} Pleya-items in bucket {bkey}"
    if plex_bucket_counts.get(bkey, 0) > 1:
        return "ambigu", None, f"C19: Plex levert meer dan een rij in bucket {bkey}"
    target = candidates[0]
    target_year = idx["items"][target]["year"]
    if year is None or target_year is None or year != target_year:
        return "geen", None, "zwakke stap vereist een bekend en gelijk jaar"
    if conflicting(ext_tokens, idx["tokens_of"][target]):
        return "geen", None, "titel/jaar gelijk, maar tmdb botst"
    if (row["ratingKey"], target) in confirmed:
        return "bevestigd", target, "titel/jaar, door eigenaar bevestigd"
    return "wacht", target, "alleen titel/jaar, wacht op bevestiging"


# --- droogloop ---------------------------------------------------------------

def digest_of(obj):
    return hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def dry_run(fx, only_account=None):
    """Bouwt het beoordeelbare plan. Schrijft niets."""
    plex, pleya = fx["plex"], fx["pleya"]
    server = plex["server"]
    idx = index_pleya(pleya)
    users = {u["id"]: u for u in pleya["users"]}
    mapping = {(m["plex_server"], m["plex_account_id"]): m["pleya_user_id"] for m in fx["user_mapping"]}
    confirmed = {(c["rating_key"], c["pleya_item_id"]) for c in fx["confirmed_weak_matches"]
                 if c["plex_server"] == server}
    perms = {(p["user_id"], p["library_id"]) for p in pleya["library_permissions"]}
    existing = {(w["subject"], w["item_id"]): w for w in pleya["watch_states"]}
    snapshot_at = fx["snapshot_at"]

    rows_out, units, duplicates = [], [], 0
    for account_key in sorted(plex["libraries_per_user"], key=int):
        account = int(account_key)
        if only_account is not None and account != only_account:
            continue
        listing = plex["libraries_per_user"][account_key]["MediaContainer"]["Metadata"]
        seen, rows = set(), []
        for row in listing:  # concrete-source dedup, eerste wint
            if row["ratingKey"] in seen:
                duplicates += 1
                continue
            seen.add(row["ratingKey"])
            rows.append(row)
        plex_bucket_counts = {}
        for row in rows:
            if row["type"] in SUPPORTED_TYPES:
                _, _, bkey, _ = plex_identity(row, plex["grandparents"])
                if bkey:
                    plex_bucket_counts[bkey] = plex_bucket_counts.get(bkey, 0) + 1

        subject = mapping.get((server, account))
        for row in rows:
            label = f"{account}/{row['ratingKey']} {row.get('grandparentTitle') or row['title']}"
            if row["type"] == "episode":
                label += f" S{row['parentIndex']}E{row['index']}"

            def out(category, reason, item=None):
                rows_out.append({"account": account, "subject": subject, "label": label,
                                 "category": category, "reason": reason, "item_id": item})

            if row["type"] not in SUPPORTED_TYPES:
                out("overgeslagen", f"niet ondersteund: {row['type']}")
                continue
            if subject is None:
                out("overgeslagen", "Plex-gebruiker niet gekoppeld")
                continue
            view_count = row.get("viewCount") or 0
            offset = row.get("viewOffset") or 0
            if view_count == 0 and offset == 0:
                out("overgeslagen", "geen kijkstatus in de bron")
                continue
            duration = row.get("duration")
            if offset < 0 or (duration is not None and offset > duration):
                out("overgeslagen", "ongeldige positie")
                continue
            last = row.get("lastViewedAt")
            if last is None or last > snapshot_at:
                out("overgeslagen", "ontbrekende of toekomstige lastViewedAt")
                continue
            outcome, item_id, reason = match(row, plex["grandparents"], idx, plex_bucket_counts, confirmed)
            if outcome == "geen":
                out("geen titelmatch", reason)
                continue
            if outcome in ("ambigu", "wacht"):
                out("overgeslagen", reason, item_id)
                continue
            item = idx["items"][item_id]
            role = users[subject]["role"]
            if role not in ("owner", "admin") and (subject, item["library_id"]) not in perms:
                out("overgeslagen", "geen recht op de Pleya-bibliotheek", item_id)
                continue
            current = existing.get((subject, item_id))
            if current is not None:
                lease = current["owner_lease_until"]
                if lease is not None and lease > snapshot_at:
                    out("conflict", "actieve Pleya-playback (lease loopt)", item_id)
                else:
                    out("conflict", f"Pleya heeft al status (revision {current['revision']})", item_id)
                continue
            out("nieuw", reason, item_id)
            units.append({
                "account": account, "subject": subject, "item_id": item_id, "label": label,
                "base_revision": 0, "row_index": len(rows_out) - 1,
                "row": target_row(subject, item_id, row),
                "source": {"server": server, "ratingKey": row["ratingKey"], "lastViewedAt": last},
            })

    # Twee Plex-rijen (bijvoorbeeld een HD- en een 4K-bibliotheek) die op hetzelfde
    # Pleya-item van dezelfde gebruiker landen: de volgorde mag niet beslissen.
    targets = {}
    for u in units:
        targets.setdefault((u["subject"], u["item_id"]), []).append(u)
    for group in targets.values():
        if len(group) > 1:
            for u in group:
                rows_out[u["row_index"]]["category"] = "conflict"
                rows_out[u["row_index"]]["reason"] = f"{len(group)} Plex-rijen voor hetzelfde Pleya-item"
    units = [u for u in units if len(targets[(u["subject"], u["item_id"])]) == 1]

    plan_digest = digest_of({"plex": plex, "mapping": fx["user_mapping"],
                             "confirmed": fx["confirmed_weak_matches"],
                             "pleya_revisions": sorted((w["subject"], w["item_id"], w["revision"])
                                                       for w in pleya["watch_states"])})
    for u in units:
        u["key"] = hashlib.sha256(f"{plan_digest}|{u['subject']}|{u['item_id']}|{ACTION}".encode()).hexdigest()[:16]
    return {"digest": plan_digest, "rows": rows_out, "units": units, "duplicates": duplicates}


def target_row(subject, item_id, row):
    """De nieuwe watch_states-rij.

    Open besluiten die hier een voorlopige waarde krijgen: play_count neemt
    viewCount over; last_explicit_* blijven NULL omdat een import geen van de
    vier toegestane handelingen is; lastViewedAt gaat alleen naar het journaal.
    """
    view_count = row.get("viewCount") or 0
    return {
        "subject": subject, "item_id": item_id,
        "position_ms": row.get("viewOffset") or 0,
        "duration_ms": row.get("duration"),
        "watched": view_count >= 1,
        "play_count": view_count,
        "revision": 1,
        "owner_session_id": None, "owner_lease_until": None,
        "last_explicit_at": None, "last_explicit_kind": None,
    }


# --- schrijfronde in het geheugen -------------------------------------------

class Crash(Exception):
    pass


def apply(plan, store, journal, crash_before_unit=None):
    """Schrijft de eenheden van het plan, elk in een eigen transactie.

    Een eenheid waarvan de idempotentiesleutel al in het journaal staat wordt
    overgeslagen. Een eenheid waarvan de doelrevisie sinds de droogloop is
    veranderd wordt een conflict en schrijft niets.
    """
    result = {"geschreven": 0, "al toegepast": 0, "conflict bij schrijven": 0}
    for n, unit in enumerate(plan["units"]):
        if unit["key"] in journal:
            result["al toegepast"] += 1
            continue
        current = store.get((unit["subject"], unit["item_id"]))
        if (current["revision"] if current else 0) != unit["base_revision"]:
            result["conflict bij schrijven"] += 1
            continue
        staged_row = copy.deepcopy(unit["row"])
        staged_journal = {"subject": unit["subject"], "item_id": unit["item_id"],
                          "plex_account": unit["account"], "source": unit["source"], "action": ACTION}
        if crash_before_unit is not None and n == crash_before_unit:
            raise Crash(f"afgebroken voor commit van eenheid {n + 1}")
        store[(unit["subject"], unit["item_id"])] = staged_row  # commit: rij en journaal samen
        journal[unit["key"]] = staged_journal
        result["geschreven"] += 1
    return result


def fresh_store(fx):
    return {(w["subject"], w["item_id"]): {k: v for k, v in w.items() if k not in ("created_at", "updated_at")}
            for w in fx["pleya"]["watch_states"]}


def store_hash(store):
    return digest_of(sorted([list(k), v] for k, v in store.items()))[:16]


# --- uitvoer -----------------------------------------------------------------

CATEGORIES = ("nieuw", "conflict", "overgeslagen", "geen titelmatch")


def counts(rows):
    c = {k: 0 for k in CATEGORIES}
    for r in rows:
        c[r["category"]] += 1
    return c


def main():
    fx = json.loads(FIXTURE.read_text(encoding="utf-8"))
    names = {a["id"]: a["name"] for a in fx["plex"]["accounts"]["MediaContainer"]["Account"]}
    failures = []

    def check(ok, text):
        print(f"  [{'ok' if ok else 'FOUT'}] {text}")
        if not ok:
            failures.append(text)

    print("== A. Droogloop ==")
    fx_before = digest_of(fx)
    plan = dry_run(fx)
    print(f"plan-digest {plan['digest'][:16]}, dubbele bronrijen genegeerd: {plan['duplicates']}")
    for r in plan["rows"]:
        print(f"  {r['category']:<16} {names[r['account']]:<14} {r['label']:<30} {r['reason']}")
    total = counts(plan["rows"])
    print("Totaal:", ", ".join(f"{k} {v}" for k, v in total.items()))
    for account in sorted({r["account"] for r in plan["rows"]}):
        per = counts([r for r in plan["rows"] if r["account"] == account])
        print(f"  {names[account]:<14}", ", ".join(f"{k} {v}" for k, v in per.items()))
    check(digest_of(fx) == fx_before, "droogloop schrijft niets (bron en doelsnapshot onaangeroerd)")

    print("\n== B. Eerste schrijfronde ==")
    store, journal = fresh_store(fx), {}
    before = store_hash(store)
    r1 = apply(plan, store, journal)
    hash1 = store_hash(store)
    print(f"  {r1}, store {before} -> {hash1}, journaal {len(journal)}")
    check(r1["geschreven"] == total["nieuw"], "alleen 'nieuw' wordt geschreven")
    for key, w in fresh_store(fx).items():
        check(store[key] == w, f"bestaande Pleya-rij {key[1][-2:]} van {key[0][-2:]} ongewijzigd")

    print("\n== C. Tweede run met hetzelfde plan ==")
    plan2 = dry_run(fx)
    r2 = apply(plan2, store, journal)
    print(f"  {r2}, store {store_hash(store)}, journaal {len(journal)}")
    check(plan2["digest"] == plan["digest"] and plan2["rows"] == plan["rows"], "droogloop geeft dezelfde uitkomst")
    check(r2["geschreven"] == 0 and store_hash(store) == hash1, "geen tweede schrijfactie, store gelijk")
    check(len(journal) == total["nieuw"], "journaal zonder dubbele eenheden")

    print("\n== D. Afbreken halverwege en hervatten ==")
    store_d, journal_d = fresh_store(fx), {}
    halfway = len(plan["units"]) // 2
    try:
        apply(plan, store_d, journal_d, crash_before_unit=halfway)
    except Crash as e:
        print(f"  {e}; geschreven tot dan: {len(journal_d)}")
    rd = apply(plan, store_d, journal_d)
    print(f"  hervat: {rd}, store {store_hash(store_d)}, journaal {len(journal_d)}")
    check(rd["al toegepast"] == halfway and rd["geschreven"] == len(plan["units"]) - halfway,
          "hervatten slaat de al gecommitte eenheden over")
    check(store_hash(store_d) == hash1, "eindtoestand gelijk aan een ononderbroken run")
    check(len(journal_d) == total["nieuw"], "geen dubbele journaalregels na hervatten")

    print("\n== E. Twee gebruikers, zelfde titel ==")
    by_subject = {}
    for (subject, item), row in store.items():
        by_subject.setdefault(subject, {})[item] = row
    anouk, bram = "00000000-0000-4000-8000-0000000000a1", "00000000-0000-4000-8000-0000000000a2"
    veerpont, ep1 = "10000000-0000-4000-8000-000000000003", "10000000-0000-4000-8000-000000000009"
    missing = {"watched": None, "position_ms": None}
    a = by_subject.get(anouk, {}).get(veerpont, missing)
    b = by_subject.get(bram, {}).get(veerpont, missing)
    print(f"  Het Veerpont 1998: anouk watched={a['watched']} pos={a['position_ms']}, "
          f"bram watched={b['watched']} pos={b['position_ms']}")
    check(a["watched"] is True and a["position_ms"] == 0 and b["watched"] is False and b["position_ms"] == 1200000,
          "elk krijgt de eigen Plex-status")
    a_ep = by_subject.get(anouk, {}).get(ep1, missing)
    b_ep = by_subject.get(bram, {}).get(ep1, missing)
    print(f"  Kanaalkust S1E1: anouk pos={a_ep['position_ms']} (bestond al), bram watched={b_ep['watched']}")
    check(a_ep["position_ms"] == 1500000 and b_ep["watched"] is True, "anouks bestaande Pleya-positie blijft staan")
    mapping = {m["plex_account_id"]: m["pleya_user_id"] for m in fx["user_mapping"]}
    check(all(mapping[j["plex_account"]] == j["subject"] for j in journal.values()),
          "elke geschreven rij komt van het Plex-account dat aan dat subject gekoppeld is")
    isolated = []
    for account in sorted(mapping):
        isolated += dry_run(fx, only_account=account)["rows"]
    combined = [r for r in plan["rows"] if r["account"] in mapping]
    check(isolated == combined, "plan per gebruiker los berekend is gelijk aan het gezamenlijke plan")

    print("\n== F. Pleya-kijkactie tussen droogloop en schrijven ==")
    store_f, journal_f = fresh_store(fx), {}
    remake = "10000000-0000-4000-8000-000000000004"
    store_f[(bram, remake)] = {"subject": bram, "item_id": remake, "position_ms": 0, "duration_ms": 6900000,
                               "watched": True, "play_count": 1, "revision": 1,
                               "owner_session_id": None, "owner_lease_until": None,
                               "last_explicit_at": 1793365000, "last_explicit_kind": "mark_watched"}
    kept = copy.deepcopy(store_f[(bram, remake)])
    rf = apply(plan, store_f, journal_f)
    print(f"  {rf}")
    check(rf["conflict bij schrijven"] == 1 and store_f[(bram, remake)] == kept,
          "de nieuwe Pleya-actie blijft staan, de import schrijft daar niets")

    print()
    if failures:
        print(f"{len(failures)} controle(s) mislukt")
        return 1
    print("alle controles geslaagd")
    return 0


if __name__ == "__main__":
    sys.exit(main())
