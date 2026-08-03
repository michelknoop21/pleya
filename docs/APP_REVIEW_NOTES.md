# App Review Information

Paste the block below into App Store Connect → App Review Information → Notes.

## Why the previous submission was rejected (2.1a)

The reviewer tapped **"Sign in with Plex"** and entered the demo credentials there.
The demo account is a **Jellyfin** account, so plex.tv rejected it, the sign-in PIN was
never claimed, and the app eventually showed a timeout message. The notes at the time
said "demo account" without saying which backend it belonged to.

Two things changed:

- The login screen now presents Plex and Jellyfin as equally weighted choices, and a
  sign-in that times out offers both a retry and a direct route to the Jellyfin flow —
  so neither path dead-ends.
- The notes below name the backend explicitly.

## Notes for the reviewer

Pleya connects to a Plex **or** a Jellyfin media server. The demo account below is a
**Jellyfin** account, so please use the Jellyfin route:

1. On the sign-in screen, tap **"Connect to Jellyfin"**.
   Do **not** use "Sign in with Plex" — the demo account is a Jellyfin account and
   plex.tv will reject it.
2. Server URL: `demo.pleya.app` → tap **Find server**.
3. Username `applereview`, password `Pleya-Review-2026!` → tap **Sign in**.

The demo library contains royalty-free content (Big Buck Bunny and similar) so playback
can be verified end to end.

## Operational

The demo server must stay online until review completes — see the `asc-523-demo-server`
note. Verify before each submission:

```bash
curl -s https://demo.pleya.app/System/Info/Public
```
