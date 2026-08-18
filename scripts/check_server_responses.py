#!/usr/bin/env python3
"""Toets antwoorden van een draaiende Pleya Server tegen het wire-contract.

Dit is acceptatiecriterium 4 van PS-2. Het staat bewust naast
check_protocol.py en niet erin: dat script toetst de fixtures, dit script toetst
wat de server werkelijk terugstuurt. De twee kunnen uit elkaar lopen, en juist
dat verschil is wat hier gevangen moet worden.

Het toetst tegen hetzelfde openapi.yaml met dezelfde validator. Een Go-validator
zou de server tegen zijn eigen lezing van het contract houden; dit meet met de
meetlat die ook de fixtures en straks de Dart-client gebruiken.

    PLEYA_RESPONSE_DIR=/tmp/antwoorden go test ./internal/api/
    python3 scripts/check_server_responses.py /tmp/antwoorden
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPENAPI = ROOT / "docs" / "pleya-protocol" / "v1" / "openapi.yaml"

PASS, FAIL = "PASS", "FAIL"
failures = 0


def report(status: str, message: str) -> None:
    global failures
    if status == FAIL:
        failures += 1
    print(f"  {status}  {message}")


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"gebruik: {argv[0]} <map-met-antwoorden>", file=sys.stderr)
        return 64

    directory = Path(argv[1])
    manifest_path = directory / "manifest.json"
    if not manifest_path.exists():
        print(f"{manifest_path} bestaat niet; draai de Go-test met PLEYA_RESPONSE_DIR", file=sys.stderr)
        return 1

    import yaml
    from jsonschema import Draft202012Validator
    from jsonschema.exceptions import best_match
    from referencing import Registry, Resource
    from referencing.jsonschema import DRAFT202012

    with OPENAPI.open(encoding="utf-8") as handle:
        document = yaml.safe_load(handle)

    resource = Resource.from_contents(document, default_specification=DRAFT202012)
    registry = Registry().with_resource("urn:pleya:openapi", resource)
    schemas = document["components"]["schemas"]

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    responses = manifest["responses"]
    if not responses:
        print("er zijn geen antwoorden vastgelegd", file=sys.stderr)
        return 1

    print(f"\n==> {len(responses)} antwoorden tegen openapi.yaml")

    for entry in responses:
        name, schema_name = entry["file"], entry["schema"]
        label = f'{entry["method"]} {entry["path"]} -> {entry["status"]} ({schema_name})'

        if schema_name not in schemas:
            report(FAIL, f"{label}: onbekend schema")
            continue

        path = directory / name
        if not path.exists():
            report(FAIL, f"{label}: {name} ontbreekt")
            continue

        validator = Draft202012Validator(
            {"$ref": f"urn:pleya:openapi#/components/schemas/{schema_name}"},
            registry=registry,
        )
        payload = json.loads(path.read_text(encoding="utf-8"))
        errors = sorted(validator.iter_errors(payload), key=str)
        if errors:
            problem = best_match(errors)
            location = "/".join(str(part) for part in problem.absolute_path) or "(wortel)"
            report(FAIL, f"{label}: {location}: {problem.message}")
        else:
            report(PASS, label)

    # Elk schema dat de leeskant van PS-2 oplevert hoort minstens één keer
    # getoetst te zijn. Anders is een endpoint stilzwijgend ongedekt.
    covered = {entry["schema"] for entry in responses}
    expected = {
        "Info", "ServerDetail", "TokenPair", "StreamToken",
        "LibraryList", "Item", "ItemPage", "ErrorEnvelope",
    }
    print("\n==> dekking")
    missing = sorted(expected - covered)
    for schema_name in missing:
        report(FAIL, f"geen enkel antwoord getoetst tegen {schema_name}")
    if not missing:
        report(PASS, f"alle {len(expected)} schema's van de leeskant zijn gedekt")

    print()
    if failures:
        print(f"{failures} controle(s) gefaald")
        return 1
    print("de server houdt zich aan het contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
