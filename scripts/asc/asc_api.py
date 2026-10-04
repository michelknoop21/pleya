"""Minimale App Store Connect API-client: JWT-auth en een JSON request-helper.

Leest de drie ASC-sleutels uit .env in de hoofdcheckout en print ze nooit.
"""
from __future__ import annotations

import base64
import time
from pathlib import Path

import jwt
import requests

API_BASE = "https://api.appstoreconnect.apple.com"
DEFAULT_ENV_PATH = Path("/Volumes/SSD/Projects/PlexFlixNetwork/plezy-main/.env")
REQUIRED_KEYS = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_CONTENT")


def load_env(path: Path = DEFAULT_ENV_PATH) -> dict[str, str]:
    """Lees ASC_KEY_ID, ASC_ISSUER_ID en ASC_KEY_CONTENT uit een .env-bestand."""
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if key in REQUIRED_KEYS:
            values[key] = value.strip().strip('"').strip("'")
    missing = [k for k in REQUIRED_KEYS if k not in values]
    if missing:
        raise RuntimeError(f"Ontbrekend in {path}: {', '.join(missing)}")
    return values


def token(env: dict[str, str]) -> str:
    """Bouw een ES256-JWT voor de ASC API, geldig 19 minuten."""
    now = int(time.time())
    payload = {
        "iss": env["ASC_ISSUER_ID"],
        "iat": now,
        "exp": now + 19 * 60,
        "aud": "appstoreconnect-v1",
    }
    key = base64.b64decode(env["ASC_KEY_CONTENT"])
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": env["ASC_KEY_ID"]})


def request(method: str, path: str, env: dict[str, str], json=None, params=None) -> requests.Response:
    """Roep de ASC API aan; geeft bij een foutstatus de errors[].detail van ASC door."""
    url = path if path.startswith("http") else f"{API_BASE}{path}"
    resp = requests.request(
        method,
        url,
        headers={"Authorization": f"Bearer {token(env)}"},
        json=json,
        params=params,
        timeout=30,
    )
    try:
        resp.raise_for_status()
    except requests.HTTPError as exc:
        detail = None
        try:
            detail = "; ".join(e.get("detail", "") for e in resp.json().get("errors", []))
        except ValueError:
            pass
        raise requests.HTTPError(f"{exc} ({detail})" if detail else str(exc)) from None
    return resp
