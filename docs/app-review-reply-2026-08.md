# Draft reply to App Review — Guideline 2.1(a), rejection of 6 July 2026

Status: draft. Review and send from App Store Connect → Resolution Center.

---

Hello,

Thank you for the review and for the detail about what you saw on the iPad Air (M3).

The message "Authentication timed out" was not a failure of the demo account — it came
from the **Plex** sign-in path. Pleya is a client for two separate services, Plex and
Jellyfin, each with its own accounts. The demo credentials we supplied are for a
**Jellyfin** server (`demo.pleya.app`). When they are entered on the Plex sign-in page at
plex.tv, Plex rejects them, the sign-in code is never confirmed, and the app can only
report that it stopped waiting. We have confirmed the demo server itself is healthy and
responds in under 200 ms.

That is our fault for making the two paths easy to confuse, so we have changed three
things in this build:

1. The sign-in screen presents Plex and Jellyfin as two equally weighted choices, rather
   than leading with Plex.
2. While a Plex sign-in is waiting, the screen now shows a direct link to the Jellyfin
   flow ("Using a Jellyfin server? Connect to Jellyfin instead"), so the mix-up can be
   corrected immediately instead of after the wait.
3. If a Plex sign-in does time out, the message is no longer a bare error: it offers both
   a retry and that same route to Jellyfin.

To review the app, please use the Jellyfin route:

1. On the sign-in screen, tap **"Connect to Jellyfin"** — not "Sign in with Plex".
2. Server URL: `demo.pleya.app` → **Find server**.
3. Username `applereview`, password `Pleya-Review-2026!` → **Sign in**.

The demo library holds royalty-free content (Big Buck Bunny and similar), so playback can
be verified end to end.

If anything still blocks you, we are glad to supply a screen recording of the full flow.

Kind regards,
Michel Knoop
