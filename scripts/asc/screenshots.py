"""App Store Connect screenshotsets: opvragen, vervangen, status tonen.

    python3 screenshots.py sets --version <id>
    python3 screenshots.py replace --set <setId> --dir <map>
    python3 screenshots.py replace --version <id> --display-type <TYPE> --dir <map>
    python3 screenshots.py status --set <setId>
"""
from __future__ import annotations

import argparse
import hashlib
import time
from pathlib import Path

import requests

from asc_api import load_env, request


def chunks(path: Path, ops: list[dict]):
    """Geef per uploadOperations-item het bijbehorende bytes-segment van path."""
    with path.open("rb") as f:
        for op in ops:
            f.seek(op["offset"])
            yield f.read(op["length"])


def md5_of(path: Path) -> str:
    h = hashlib.md5()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def sets(env: dict, version_id: str) -> list[tuple[str, str, int]]:
    """Screenshotsets van een versie: (setId, displayType, aantal screenshots)."""
    rows = []
    locs = request("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", env).json()["data"]
    for loc in locs:
        resp = request(
            "GET",
            f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets",
            env,
            params={"include": "appScreenshots"},
        ).json()
        for s in resp["data"]:
            count = len(s["relationships"]["appScreenshots"]["data"])
            rows.append((s["id"], s["attributes"]["screenshotDisplayType"], count))
    return rows


def status(env: dict, set_id: str) -> list[tuple[str, str, str]]:
    """Per bestaande screenshot in de set: (id, fileName, assetDeliveryState)."""
    resp = request("GET", f"/v1/appScreenshotSets/{set_id}", env, params={"include": "appScreenshots"}).json()
    rows = []
    for item in resp.get("included", []):
        attrs = item["attributes"]
        state = (attrs.get("assetDeliveryState") or {}).get("state")
        rows.append((item["id"], attrs.get("fileName"), state))
    return rows


def _find_or_create_set(env: dict, version_id: str, display_type: str) -> str:
    locs = request("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", env).json()["data"]
    if not locs:
        raise RuntimeError(f"Geen appStoreVersionLocalizations voor versie {version_id}")
    loc_id = locs[0]["id"]
    resp = request("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", env).json()
    for s in resp["data"]:
        if s["attributes"]["screenshotDisplayType"] == display_type:
            return s["id"]
    created = request(
        "POST",
        "/v1/appScreenshotSets",
        env,
        json={
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {
                    "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}
                },
            }
        },
    ).json()
    return created["data"]["id"]


def _delete_existing(env: dict, set_id: str):
    resp = request("GET", f"/v1/appScreenshotSets/{set_id}", env, params={"include": "appScreenshots"}).json()
    for item in resp.get("included", []):
        request("DELETE", f"/v1/appScreenshots/{item['id']}", env)


def _upload_one(env: dict, set_id: str, path: Path) -> str:
    created = request(
        "POST",
        "/v1/appScreenshots",
        env,
        json={
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": path.name, "fileSize": path.stat().st_size},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
            }
        },
    ).json()["data"]
    shot_id = created["id"]
    ops = created["attributes"]["uploadOperations"]
    for op, body in zip(ops, chunks(path, ops)):
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        r = requests.put(op["url"], headers=headers, data=body, timeout=60)
        r.raise_for_status()
    request(
        "PATCH",
        f"/v1/appScreenshots/{shot_id}",
        env,
        json={
            "data": {
                "type": "appScreenshots",
                "id": shot_id,
                "attributes": {"uploaded": True, "sourceFileChecksum": md5_of(path)},
            }
        },
    )
    return shot_id


def _wait_for_complete(env: dict, shot_id: str, timeout: int = 180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        data = request("GET", f"/v1/appScreenshots/{shot_id}", env).json()["data"]
        delivery = data["attributes"].get("assetDeliveryState") or {}
        state = delivery.get("state")
        if state == "COMPLETE":
            return
        if state == "FAILED":
            raise RuntimeError(f"Upload van {shot_id} mislukt: {delivery.get('errors')}")
        time.sleep(3)
    raise RuntimeError(f"Timeout: {shot_id} werd niet COMPLETE binnen {timeout}s")


def replace(env: dict, directory: Path, set_id: str | None = None, version_id: str | None = None, display_type: str | None = None) -> tuple[str, int]:
    """Vervang de screenshots in een set: verwijdert bestaande, uploadt *.png op naam gesorteerd."""
    if set_id is None:
        set_id = _find_or_create_set(env, version_id, display_type)
    _delete_existing(env, set_id)
    pngs = sorted(directory.glob("*.png"))
    for png in pngs:
        shot_id = _upload_one(env, set_id, png)
        _wait_for_complete(env, shot_id)
    return set_id, len(pngs)


def main():
    parser = argparse.ArgumentParser(description="ASC-screenshotsets beheren")
    sub = parser.add_subparsers(dest="command", required=True)

    p_sets = sub.add_parser("sets", help="Toon screenshotsets van een versie")
    p_sets.add_argument("--version", required=True)

    p_replace = sub.add_parser("replace", help="Vervang de screenshots in een set")
    p_replace.add_argument("--set", help="Bestaande set-id")
    p_replace.add_argument("--version", help="Versie-id (met --display-type als de set nog niet bestaat)")
    p_replace.add_argument("--display-type", help="bv. APP_IPAD_PRO_3GEN_129")
    p_replace.add_argument("--dir", required=True, type=Path)

    p_status = sub.add_parser("status", help="Toon de uploadstatus van een set")
    p_status.add_argument("--set", required=True)

    args = parser.parse_args()
    env = load_env()

    if args.command == "sets":
        for set_id, display_type, count in sets(env, args.version):
            print(f"{set_id} | {display_type} | {count}")
    elif args.command == "replace":
        if not args.set and not (args.version and args.display_type):
            parser.error("geef --set, of --version samen met --display-type")
        set_id, count = replace(env, args.dir, set_id=args.set, version_id=args.version, display_type=args.display_type)
        print(f"Set {set_id}: {count} screenshot(s) geupload")
    elif args.command == "status":
        for shot_id, filename, state in status(env, args.set):
            print(f"{shot_id} | {filename} | {state}")


if __name__ == "__main__":
    main()
