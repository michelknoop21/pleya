"""App Store Connect review submission: status opvragen, herindienen.

    python3 submit.py version --id <versionId>
    python3 submit.py submit --app <appId> --version <versionId>            # dry-run, print payloads
    python3 submit.py submit --app <appId> --version <versionId> --confirm  # dient echt in
"""
from __future__ import annotations

import argparse
import json as json_lib

from asc_api import load_env, request
from screenshots import sets as screenshot_sets


def version_info(env: dict, version_id: str):
    """appStoreState, versionString, gekoppelde build en screenshotsets van een versie."""
    v = request("GET", f"/v1/appStoreVersions/{version_id}", env).json()["data"]
    build = request("GET", f"/v1/appStoreVersions/{version_id}/build", env).json().get("data")
    return v["attributes"]["appStoreState"], v["attributes"].get("versionString"), build, screenshot_sets(env, version_id)


def submit(env: dict, app_id: str, version_id: str, platform: str, confirm: bool):
    """reviewSubmission aanmaken, item toevoegen, alleen met confirm ook indienen (submitted: true)."""
    review_payload = {
        "data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": platform},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    print("POST /v1/reviewSubmissions")
    print(json_lib.dumps(review_payload, indent=2))

    if not confirm:
        item_preview = {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                    "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": "<reviewSubmission-id>"}},
                },
            }
        }
        print("POST /v1/reviewSubmissionItems")
        print(json_lib.dumps(item_preview, indent=2))
        print('PATCH /v1/reviewSubmissions/<id> {"data": {"attributes": {"submitted": true}}}')
        print("Dry-run: er is niets aangemaakt. Voeg --confirm toe om echt in te dienen.")
        return

    review = request("POST", "/v1/reviewSubmissions", env, json=review_payload).json()["data"]
    item_payload = {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": review["id"]}},
            },
        }
    }
    print("POST /v1/reviewSubmissionItems")
    print(json_lib.dumps(item_payload, indent=2))
    request("POST", "/v1/reviewSubmissionItems", env, json=item_payload)

    patch_payload = {"data": {"type": "reviewSubmissions", "id": review["id"], "attributes": {"submitted": True}}}
    print(f"PATCH /v1/reviewSubmissions/{review['id']}")
    print(json_lib.dumps(patch_payload, indent=2))
    request("PATCH", f"/v1/reviewSubmissions/{review['id']}", env, json=patch_payload)
    print(f"Ingediend: reviewSubmission {review['id']}")


def main():
    parser = argparse.ArgumentParser(description="App Store Connect review submissions")
    sub = parser.add_subparsers(dest="command", required=True)

    p_version = sub.add_parser("version", help="Toon status, build en screenshotsets van een versie")
    p_version.add_argument("--id", required=True)

    p_submit = sub.add_parser("submit", help="reviewSubmission aanmaken en (met --confirm) indienen")
    p_submit.add_argument("--app", required=True)
    p_submit.add_argument("--version", required=True)
    p_submit.add_argument("--platform", default="IOS", help="IOS, TV_OS of MAC_OS")
    p_submit.add_argument("--confirm", action="store_true", help="dient echt in, anders alleen dry-run")

    args = parser.parse_args()
    env = load_env()

    if args.command == "version":
        state, version_string, build, screenshot_rows = version_info(env, args.id)
        print(f"appStoreState: {state}")
        print(f"versionString: {version_string}")
        if build:
            print(f"build: {build['attributes'].get('version')} (id {build['id']})")
        else:
            print("build: geen gekoppelde build")
        for set_id, display_type, count in screenshot_rows:
            print(f"{set_id} | {display_type} | {count}")
    elif args.command == "submit":
        submit(env, args.app, args.version, args.platform, args.confirm)


if __name__ == "__main__":
    main()
