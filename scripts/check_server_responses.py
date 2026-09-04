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


METHODS = ("get", "post", "put", "patch", "delete", "head", "options")
SCHEMA_REF = "#/components/schemas/"
RESPONSE_REF = "#/components/responses/"


def contract_response_schemas(document: dict) -> dict[str, list[str]]:
    """Elk schema dat openapi.yaml als JSON-antwoordlichaam noemt.

    Geeft per schemanaam de plekken waar het contract hem belooft, zodat een
    ongedekt schema meteen vertelt welk endpoint er niet geraakt is.

    Twee dingen die geen antwoordschema zijn en er dus niet in horen. Een
    verwijzing naar components/responses wordt eerst opgelost; die indirectie
    wordt door elke 401 gebruikt en levert ErrorEnvelope op. En een lichaam dat
    geen JSON is blijft buiten beschouwing: artwork, ondertitels en de stream
    zelf staan in het contract als binary of platte tekst, en daar valt met een
    JSON-schema niets aan te toetsen.
    """
    found: dict[str, list[str]] = {}
    shared = document.get("components", {}).get("responses", {})

    for path, item in (document.get("paths") or {}).items():
        for method, operation in (item or {}).items():
            if method not in METHODS or not isinstance(operation, dict):
                continue
            for status, response in (operation.get("responses") or {}).items():
                ref = response.get("$ref")
                if ref and ref.startswith(RESPONSE_REF):
                    response = shared.get(ref[len(RESPONSE_REF):], {})
                for content_type, media in (response.get("content") or {}).items():
                    if content_type != "application/json" and not content_type.endswith("+json"):
                        continue
                    schema_ref = (media.get("schema") or {}).get("$ref", "")
                    if schema_ref.startswith(SCHEMA_REF):
                        name = schema_ref[len(SCHEMA_REF):]
                        found.setdefault(name, []).append(f"{method.upper()} {path} {status}")
    return found


def check_derivation() -> None:
    """Bijt de afleiding.

    De dekkingslijst komt niet meer uit een handmatige opsomming maar uit
    openapi.yaml, en daarmee verschuift het risico: niet een lijst die achterloopt
    maar een afleiding die te weinig vindt. Een afleiding die niets oplevert maakt
    de poort stil groen, precies de fout die hij moest afschaffen. Deze controles
    draaien op een verzonnen contract, zodat ze een uitkomst hebben die los staat
    van wat er vandaag in het echte contract staat.
    """
    print("\n==> bijt de afleiding")

    doc = {
        "components": {
            "responses": {"Error": {"content": {"application/json": {
                "schema": {"$ref": "#/components/schemas/ErrorEnvelope"}}}}}
        },
        "paths": {
            "/dingen": {
                "get": {"responses": {
                    "200": {"content": {"application/json": {
                        "schema": {"$ref": "#/components/schemas/DingList"}}}},
                    "401": {"$ref": "#/components/responses/Error"},
                }},
                "parameters": [{"name": "x"}],
            },
            "/plaatje": {"get": {"responses": {"200": {"content": {"image/jpeg": {
                "schema": {"type": "string", "format": "binary"}}}}}}},
        },
    }
    found = contract_response_schemas(doc)

    cases = [
        ("een gewoon JSON-antwoord telt mee", "DingList" in found),
        ("een verwijzing naar components/responses wordt opgelost", "ErrorEnvelope" in found),
        ("een binair lichaam telt niet mee", len(found) == 2),
        ("de vindplaats staat erbij", found.get("DingList") == ["GET /dingen 200"]),
        ("parameters naast de methoden verwarren de afleiding niet", "x" not in found),
        ("een leeg contract levert niets", contract_response_schemas({"paths": {}}) == {}),
    ]
    for naam, ok in cases:
        report(PASS if ok else FAIL, naam)


def report(status: str, message: str) -> None:
    global failures
    if status == FAIL:
        failures += 1
    print(f"  {status}  {message}")


def main(argv: list[str]) -> int:
    # --subset is voor een vangst die het contract bewust niet helemaal dekt: de
    # fake server uit pleya_verify is een fixture voor de app en bedient geen
    # gebruikers of sessies. Wat hij teruggeeft moet kloppen, maar de dekkingseis
    # van de echte server hoort niet op hem. Zonder deze vlag zou de enige manier
    # om de fake server te toetsen zijn om de eis voor iedereen te verlagen.
    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = {a for a in argv[1:] if a.startswith("--")}
    subset = "--subset" in flags
    unknown = flags - {"--subset"}
    if len(args) != 1 or unknown:
        print(f"gebruik: {argv[0]} [--subset] <map-met-antwoorden>", file=sys.stderr)
        return 64

    directory = Path(args[0])
    manifest_path = directory / "manifest.json"
    if not manifest_path.exists():
        print(f"{manifest_path} bestaat niet; draai de vangst met PLEYA_RESPONSE_DIR", file=sys.stderr)
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

    # Elk schema dat de server als antwoord kan geven hoort minstens één keer
    # getoetst te zijn. Anders is een endpoint stilzwijgend ongedekt.
    #
    # Deze lijst stond met de hand op de acht schema's van de leeskant van PS-2.
    # PS-9 legde daar UserList, LibraryPermissionList en SessionList naast: de
    # vangst nam ze wél op, maar de poort eiste ze niet, dus gebruikers, sessies
    # en rechten konden ongedekt zijn terwijl alles groen stond. Een handmatige
    # lijst loopt per definitie achter op de fase die hem zou moeten uitbreiden.
    #
    # Hij is daarom afgeleid van openapi.yaml: elk schema dat het contract als
    # JSON-antwoordlichaam noemt. Dat is de goede kant op afleiden. Uit de vangst
    # afleiden zou de poort tautologisch maken, want dan eist hij precies wat er
    # toevallig langskwam en kan hij nooit meer rood worden. Nu verhoogt een
    # endpoint dat aan het contract wordt toegevoegd de lat vanzelf, en blijft de
    # poort rood tot de vangst dat endpoint werkelijk raakt.
    expected = contract_response_schemas(document)
    covered = {entry["schema"] for entry in responses}

    print("\n==> dekking van wat het contract als antwoord noemt")
    if not expected:
        report(FAIL, "uit openapi.yaml komt geen enkel antwoordschema; de afleiding is kapot")
    missing = sorted(set(expected) - covered)
    if subset:
        report(PASS, f"{len(covered)} van de {len(expected)} schema's gedekt; "
                     f"deze vangst dekt bewust een deel ({', '.join(sorted(missing))} niet)")
    else:
        for schema_name in missing:
            report(FAIL, f"geen enkel antwoord getoetst tegen {schema_name} ({expected[schema_name][0]})")
        if expected and not missing:
            report(PASS, f"alle {len(expected)} schema's die het contract als antwoord noemt zijn gedekt")

    # Andersom: een antwoord getoetst tegen een schema dat nergens als
    # antwoordlichaam in het contract staat. Dan levert de server iets waar het
    # contract niet over gaat, en dat is precies wat deze poort moet zien.
    stray = sorted(covered - set(expected))
    for schema_name in stray:
        report(FAIL, f"getoetst tegen {schema_name}, dat het contract nergens als antwoord noemt")

    check_derivation()

    print()
    if failures:
        print(f"{failures} controle(s) gefaald")
        return 1
    print("de server houdt zich aan het contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
