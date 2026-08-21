#!/usr/bin/env python3
"""Valideer het Pleya-protocolcontract en zijn fixtures.

Twee controles, en ze vangen verschillende fouten:

1. Is openapi.yaml een geldig OpenAPI 3.1-document. Dat vangt een typefout in een
   pad, een verwijzing naar een schema dat niet bestaat, of een responsecode
   zonder inhoud.
2. Valideert elke fixture tegen het schema dat het manifest hem toewijst. Dat
   vangt het echte risico: een voorbeeld dat er goed uitziet maar niet klopt, en
   dat vervolgens als contracttest in twee implementaties terechtkomt.

De tweede controle draait met de lokale jsonschema. De eerste vraagt
openapi-spec-validator; ontbreekt die, dan wordt de controle overgeslagen met een
melding in plaats van stil door te gaan.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROTOCOL = ROOT / "docs" / "pleya-protocol" / "v1"
OPENAPI = PROTOCOL / "openapi.yaml"
EXAMPLES = PROTOCOL / "examples"
MANIFEST = EXAMPLES / "manifest.json"

PASS, FAIL, SKIP = "PASS", "FAIL", "SKIP"
failures = 0


def report(status: str, message: str) -> None:
    global failures
    if status == FAIL:
        failures += 1
    print(f"  {status}  {message}")


def load_openapi() -> dict:
    try:
        import yaml
    except ImportError:
        print("pyyaml ontbreekt; installeer het of draai dit script in de container", file=sys.stderr)
        raise SystemExit(2)
    with OPENAPI.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def check_structure(document: dict) -> None:
    print("\n==> openapi 3.1")
    try:
        from openapi_spec_validator import validate  # type: ignore
    except ImportError:
        report(SKIP, "openapi-spec-validator ontbreekt (scripts/check_protocol.sh draait hem in een container)")
        return
    try:
        validate(document)
    except Exception as error:  # noqa: BLE001 - de bibliotheek gooit eigen types
        report(FAIL, f"openapi.yaml is geen geldig 3.1-document: {error}")
        return
    report(PASS, f"openapi.yaml, {len(document['paths'])} paden")


def check_dangling_refs(document: dict) -> None:
    """Elke $ref moet ergens uitkomen. Een typefout hierin is anders pas zichtbaar
    wanneer een implementatie het schema probeert te gebruiken."""
    print("\n==> verwijzingen")
    known = set()
    for section in ("schemas", "parameters", "responses", "headers", "securitySchemes"):
        for name in document.get("components", {}).get(section, {}):
            known.add(f"#/components/{section}/{name}")

    missing = set()

    def walk(node) -> None:
        if isinstance(node, dict):
            ref = node.get("$ref")
            if isinstance(ref, str) and ref.startswith("#/") and ref not in known:
                missing.add(ref)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(document)
    if missing:
        for ref in sorted(missing):
            report(FAIL, f"verwijzing komt nergens uit: {ref}")
    else:
        report(PASS, f"alle verwijzingen komen uit, {len(known)} componenten")


def check_enum_markings(document: dict) -> None:
    """Elk enum-veld draagt x-unknown-safe.

    Hoofdstuk 3.2 van de specificatie zegt dat een waarde alleen bij een enum mag
    komen wanneer het veld unknown-safe is. Die eigenschap is niet af te lezen aan
    het schema zelf, dus een nieuw enum-veld zou hem stilzwijgend erven. Deze
    controle dwingt de keuze af op het moment dat het veld wordt toegevoegd.
    """
    print("\n==> enum-markering")
    unmarked, wrong_type, marked = [], [], 0

    def walk(node, path: str) -> None:
        nonlocal marked
        if isinstance(node, dict):
            if "enum" in node:
                if "x-unknown-safe" not in node:
                    unmarked.append(path)
                elif not isinstance(node["x-unknown-safe"], bool):
                    wrong_type.append(path)
                else:
                    marked += 1
            for key, value in node.items():
                walk(value, f"{path}/{key}")
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, f"{path}/{index}")

    walk(document, "#")
    for path in unmarked:
        report(FAIL, f"enum zonder x-unknown-safe: {path}")
    for path in wrong_type:
        report(FAIL, f"x-unknown-safe is geen boolean: {path}")
    if not unmarked and not wrong_type:
        report(PASS, f"alle {marked} enums dragen x-unknown-safe")


def check_fixtures(document: dict) -> None:
    print("\n==> fixtures tegen het contract")
    from jsonschema import Draft202012Validator
    from jsonschema.exceptions import best_match
    from referencing import Registry, Resource
    from referencing.jsonschema import DRAFT202012

    resource = Resource.from_contents(document, default_specification=DRAFT202012)
    registry = Registry().with_resource("urn:pleya:openapi", resource)

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    schemas = document["components"]["schemas"]

    listed = set()
    for entry in manifest["fixtures"]:
        name, schema_name = entry["file"], entry["schema"]
        listed.add(name)
        path = EXAMPLES / name

        if not path.exists():
            report(FAIL, f"{name} staat in het manifest maar bestaat niet")
            continue
        if schema_name not in schemas:
            report(FAIL, f"{name} verwijst naar het onbekende schema {schema_name}")
            continue

        validator = Draft202012Validator(
            {"$ref": f"urn:pleya:openapi#/components/schemas/{schema_name}"},
            registry=registry,
        )
        errors = sorted(validator.iter_errors(json.loads(path.read_text(encoding="utf-8"))), key=str)
        if errors:
            problem = best_match(errors)
            location = "/".join(str(part) for part in problem.absolute_path) or "(wortel)"
            report(FAIL, f"{name} tegen {schema_name}: {location}: {problem.message}")
        else:
            report(PASS, f"{name} tegen {schema_name}")

    # Een fixture die niemand toetst is erger dan geen fixture: hij wekt de indruk
    # gedekt te zijn.
    on_disk = {p.name for p in EXAMPLES.glob("*.json")} - {"manifest.json"}
    for orphan in sorted(on_disk - listed):
        report(FAIL, f"{orphan} staat niet in het manifest en wordt dus nergens getoetst")


def check_validator_bites(document: dict) -> None:
    """Een validator die nooit iets afkeurt bewijst niets.

    Deze controle voert drie fouten in die er plausibel uitzien en eist dat ze
    alle drie worden gevangen. Slaagt een van de drie, dan is de fixtureronde
    hierboven een geruststelling zonder dekking.
    """
    print("\n==> bijt de validator")
    from jsonschema import Draft202012Validator
    from referencing import Registry, Resource
    from referencing.jsonschema import DRAFT202012

    resource = Resource.from_contents(document, default_specification=DRAFT202012)
    registry = Registry().with_resource("urn:pleya:openapi", resource)

    def rejects(schema_name: str, payload: dict) -> bool:
        validator = Draft202012Validator(
            {"$ref": f"urn:pleya:openapi#/components/schemas/{schema_name}"},
            registry=registry,
        )
        return bool(list(validator.iter_errors(payload)))

    cases = [
        (
            "een Plex-veldnaam in plaats van de neutrale",
            "UserState",
            {"viewOffsetMs": 1830000, "watched": False, "play_count": 0,
             "updated_at": "2026-08-18T20:12:44Z"},
        ),
        (
            "een foutcode buiten de vijf domeinen",
            "ErrorEnvelope",
            {"error": {"code": "plex.not_found", "message": "x", "retryable": False}},
        ),
        (
            "een versie zonder file_count",
            "Version",
            {"id": "x", "container": "mkv", "duration_ms": 1},
        ),
        (
            "een onbekend veld in een gesloten aanvraagbody",
            "WatchStateEvent",
            {"item_id": "x", "session_id": "s", "position_ms": 1,
             "occurred_at": "2026-08-21T20:00:00Z", "explicit_action": "none",
             "stream_session_id": "ss_1"},
        ),
        (
            "een verzonnen reden voor playback_started",
            "WatchStateEvent",
            {"item_id": "x", "session_id": "s", "position_ms": 1,
             "occurred_at": "2026-08-21T20:00:00Z",
             "explicit_action": "playback_started", "cause": "steal"},
        ),
    ]

    for description, schema_name, payload in cases:
        if rejects(schema_name, payload):
            report(PASS, f"afgekeurd zoals het hoort: {description}")
        else:
            report(FAIL, f"NIET afgekeurd: {description}")


def main() -> int:
    document = load_openapi()
    check_structure(document)
    check_dangling_refs(document)
    check_enum_markings(document)
    check_fixtures(document)
    check_validator_bites(document)

    print()
    if failures:
        print(f"{failures} controle(s) gefaald")
        return 1
    print("contract en fixtures zijn in orde")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
