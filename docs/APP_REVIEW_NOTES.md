# App Review Information

Paste the block below into App Store Connect → App Review Information → Notes.

## Notes for the reviewer

**The demo account is a Jellyfin account. Please do not use "Sign in with Plex" —
plex.tv will reject these credentials.** Pleya connects to a Plex **or** a Jellyfin
media server; the two are separate services with separate accounts.

Sign in like this:

1. On the sign-in screen, tap **"Connect to Jellyfin"** (not "Sign in with Plex").
2. Server URL: `demo.pleya.app` → tap **Find server**.
3. Username `applereview`, password `Pleya-Review-2026!` → tap **Sign in**.

The demo library contains royalty-free content (Big Buck Bunny and similar) so playback
can be verified end to end.

## Why the previous submissions were rejected (2.1a)

Both times, the reviewer tapped **"Sign in with Plex"** and entered the Jellyfin demo
credentials there. plex.tv rejected them, the sign-in PIN was never claimed, and the app
reported a timeout — read as "Authentication timed out" rather than "wrong service".

Three things changed since:

- The login screen presents Plex and Jellyfin as equally weighted choices.
- While a Plex sign-in is waiting for its PIN, the screen offers a direct route to the
  Jellyfin flow — so the mix-up is recoverable immediately, not after the wait.
- A sign-in that does time out offers both a retry and that same Jellyfin route.

## Operational

The demo server must stay online until review completes — see the `asc-523-demo-server`
note. Verify before each submission:

```bash
curl -s https://demo.pleya.app/System/Info/Public
```
