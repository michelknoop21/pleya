"""Count Pleya APK download starts without storing visitor details."""

import json
import os
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


DB_PATH = Path(os.environ.get("PLEYA_DOWNLOAD_DB", "/data/downloads.sqlite3"))
APK_PATH = "/downloads/c385b4c0caa11bebe67e86b837f187d0/pleya-latest.apk"


def connect():
    connection = sqlite3.connect(DB_PATH, timeout=10)
    connection.execute(
        "CREATE TABLE IF NOT EXISTS download_starts (day TEXT PRIMARY KEY, count INTEGER NOT NULL)"
    )
    return connection


def record_start():
    day = datetime.now(timezone.utc).date().isoformat()
    with closing(connect()) as connection, connection:
        connection.execute(
            "INSERT INTO download_starts (day, count) VALUES (?, 1) "
            "ON CONFLICT(day) DO UPDATE SET count = count + 1",
            (day,),
        )


def counts():
    today = datetime.now(timezone.utc).date().isoformat()
    with closing(connect()) as connection:
        total = connection.execute("SELECT COALESCE(SUM(count), 0) FROM download_starts").fetchone()[0]
        daily = connection.execute(
            "SELECT count FROM download_starts WHERE day = ?", (today,)
        ).fetchone()
    return {"total": total, "today_utc": daily[0] if daily else 0}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.respond(include_body=True)

    def do_HEAD(self):
        self.respond(include_body=False)

    def respond(self, include_body):
        path = urlsplit(self.path).path
        if path == "/start/android-tv":
            if include_body:
                record_start()
            self.send_response(302)
            self.send_header("Location", APK_PATH)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        if path == "/stats":
            body = json.dumps(counts()).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if include_body:
                self.wfile.write(body)
            return

        self.send_error(404)

    def log_message(self, format, *args):
        # The counter stores only daily totals, not IP addresses or user agents.
        pass


if __name__ == "__main__":
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with closing(connect()):
        pass
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
