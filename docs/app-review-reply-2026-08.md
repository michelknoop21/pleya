# Reply to App Review: guideline 2.1(a), rejection of 6 July 2026

Status: ready to send from App Store Connect → Resolution Center.
Build 220 is attached to the iOS, tvOS and macOS version records, so send this reply
together with the resubmission of 2.8.0.

---

Hello,

Thank you for the detail about what you saw on the iPad Air (M3). We were able to
reproduce it, and the cause is on our side.

"Authentication timed out" did not come from the demo server. It came from the **Plex**
sign-in path. Pleya is a client for two separate services, Plex and Jellyfin, and each has
its own accounts. The demo credentials we supplied belong to a **Jellyfin** server
(demo.pleya.app). Entered on the Plex sign-in page at plex.tv, they are rejected there,
the sign-in code is never confirmed, and the app can only report that it stopped waiting.

Our sign-in screen made that mix-up easy to walk into, so this build changes three things:

1. Plex and Jellyfin are presented as two equally weighted choices. The screen no longer
   leads with Plex.
2. While a Plex sign-in waits for its code, the screen shows a direct route to the
   Jellyfin flow, so the mistake can be corrected right away instead of after the wait.
3. A sign-in that does time out now offers both a retry and that same route to Jellyfin.

To sign in for review, please use the Jellyfin route:

1. On the sign-in screen, tap **Connect to Jellyfin** (not "Sign in with Plex").
2. Server address: `https://demo.pleya.app` → **Find server**
3. Username `applereview`, password `Pleya-Review-2026!` → **Sign in**

We verified the demo server again today: the account authenticates, and the library
returns its three royalty-free Blender Foundation films (Big Buck Bunny, Sintel, Tears of
Steel), so playback can be checked end to end.

If it helps, we can supply a screen recording of the full flow on an iPad. Please let us
know and we will attach it.

Kind regards,
Michel Knoop
