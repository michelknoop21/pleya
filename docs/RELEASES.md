# Pleya release notes

What changed in each Pleya build, written for the people using it. Newest first.

Pleya has shipped as a private TestFlight beta since 2 July 2026, so builds are numbered
continuously while the version stays at 2.8.0. The internal engineering log lives in
`docs/CHANGELOG.md`; this file is the public one.

Every published entry carries the commit it was cut at. `scripts/gen_release_notes.sh`
reads the topmost anchor and fills the block below with everything committed since.

## Unreleased

<!-- BEGIN GENERATED -->
Nothing user-facing since the last published build.
<!-- END GENERATED -->

## 2.8.0 · build 231 · 19 August 2026

<!-- commit: 7c3d47e -->

### Fixed

- **Your subtitle and audio language is remembered when Plex transcodes.** Picking a language
  only stuck when the file played directly. As soon as Plex re-encoded, which it always does
  for burned-in or image-based subtitles and for anything streamed over the internet, the
  choice went straight to the server and Pleya never saw it. The next episode then started in
  whatever the server preferred, so you got a different language rather than no language,
  which made it easy to miss. The choice now also lands on the series itself, the way it
  already did on direct play. That is the only thing that can work when the subtitles are
  burned into the picture. Switching no longer waits for that to be written, and a failed
  write can no longer make the switch itself fail.
- **The quick buttons on a hover preview no longer black out the app.** Play, add and info on
  the preview that appears over a card opened their screen outside the profile you were in,
  leaving an error across the whole window. The plus also left the preview standing on top of
  the menu it had just opened, where it swallowed the clicks meant for that menu.
- **A click on the sidebar no longer starts whatever sits behind it.** The rail switches to
  its wide state at once while the width takes 200 ms to catch up, and in that gap a click
  aimed at a menu item could land on the billboard and start playing. The rail now owns the
  strip it is about to fill, from the first frame of opening until the last frame of closing.
  Tapping the billboard opens the title; the play button still plays.
- Filters, Sort and Group open in the middle of the window instead of in the corner you
  clicked them from. They used to open at the mouse, which is right for a context menu and
  for nothing else, so on a desktop window a panel of 700 by 400 ended up clamped against the
  right edge with most of the height unused.

### Improved

- Discover on Requests uses the same header as a library page: film and series as tabs, genre
  as an action beside them. It was a double row of outlined pills that took more room than the
  posters underneath, 92 pixels of it against 42 now.
- Choosing a type on Discover selects that type instead of falling back to All, and clearing a
  genre is a row in the panel rather than a second tap on the chip you just picked.

### Worth checking

Two things in this build are easier to break than to notice, so a look at them helps.

- Your list of requests, on a phone. Every row should carry the real title and poster, and the
  status beside it should agree with what Overseerr says. Then send one request with a
  different server, quality profile and root folder than the defaults: all three should arrive
  in Radarr or Sonarr exactly as you set them.
- Subtitle language on Apple TV, on a series Plex is transcoding rather than playing directly.
  Pick a language partway through an episode, then start the next one. It should open in the
  language you picked.

### Known in this build

Moving a mouse or trackpad towards the sidebar claims the strip beside it as soon as the
pointer arrives, so a control the page puts there, such as **Recommended** on a library page,
opens the menu instead of responding. Fixed in the next build; on this one, reach those
controls from further right or use the keyboard.

## 2.8.0 · build 228 · 18 August 2026

<!-- commit: 04f1411 -->

### New

- **Pick the quality profile and root folder when you request something.** The advanced
  options on a request only let you choose which Radarr or Sonarr server to send it to, so a
  profile you had set up yourself was out of reach. Both pickers open on whatever that server
  would have used anyway, and changing server clears them rather than carrying the previous
  server's choices over.

### Improved

- **Requests show what was actually requested.** The list used to head every row with
  "Movie" or "Show", above a grey placeholder, because the request itself carries only an id
  and an availability state. Pleya now resolves each title once and remembers it, so the real
  name, year and poster appear, with the kind and year on their own line underneath.
- Seasons on a request fit on one line. A run of consecutive seasons reads as a range, gaps
  stay visible rather than being smoothed into one, and a request spread over too many
  separate runs says how many there are.
- A request no longer shows "Available" next to "Completed". Where the two say different
  things, such as approved but only partly downloaded, both still appear.
- The filter tabs on Requests and on your watchlist keep their margin when you scroll them,
  and the active filter scrolls itself into view. The last chip is no longer faded out
  halfway through its own word.
- The search field on Requests has room for its sentence again instead of being pushed onto
  two lines by a button that repeated what the whole field already did.
- Your watchlist says what it is sorted by, on the button itself. It used to be in a tooltip,
  and tooltips never open on a touchscreen.

### Fixed

- **Sorting your watchlist no longer blanks the screen.** Choosing an order closed the app
  behind the sheet instead of the sheet, leaving nothing on screen and the sort unapplied.
  The same fault sat behind Request, Remove and Cancel on a watchlist title.
- **The audio priority setting responds again.** Choosing between even volume and original
  Dolby Atmos did save your choice, but the selected option looked exactly like the
  unselected one, so there was no way to tell. Every setting of that shape was affected.
- The skip intro button no longer appears on films. Films rarely carry a real intro marker,
  so the button was working off a chapter title and could sit there for minutes, returning
  every time you touched the screen. Skipping the credits is unchanged, on films as much as
  on episodes.
- A status label on a poster stays inside the poster instead of being cut off at its edge.
- Connecting to Tautulli says so when something other than Tautulli answers. Behind a login
  page or a reverse proxy the reply came back as a Tautulli error, which sent you looking in
  the wrong place.

## 2.8.0 · build 227 · 18 August 2026

<!-- commit: 68ad70d -->

### New

- **Who watched this, and who is watching now.** Connect a Tautulli server and a title shows
  who has seen it and how often, with a separate screen for the streams playing at this
  moment. Plex only, and only if you run the server yourself: a Tautulli key opens that
  server's entire admin API, so Pleya keeps it in the vault of the profile you added it to
  and leaves it out of settings export and iCloud sync.
- **Levelling the volume and taming loud effects are two switches now.** They used to be one
  setting with three positions, so softening the bangs late at night also flattened the rest
  of the film. An existing choice carries over to the new pair. While Dolby passthrough is
  running, levelling is not possible and the player says so instead of failing quietly.
- Pleya remembers your audio and subtitle language per title rather than per session, so the
  next episode starts the way you left the last one. On Apple devices that memory follows you
  over iCloud, and an optional switch writes the language onto the show in Plex so the
  official Plex apps pick it up too.
- On the Requests screen a row of posters expands into a full grid, so you can take it in at
  once instead of scrolling sideways.

### Improved

- Settings, tabs and requests follow one layout instead of three.
- The refresh button on the home screen shows that it is working, instead of looking like
  nothing happened.
- Library pages put the library name in the page header and the tabs and filters on one
  line. On Apple TV the artwork above them takes the room the row below leaves unused.
- On Apple TV everything is drawn a little smaller, at scale 1.85 instead of 2.00. A
  settings page fits six rows where five fitted before, and a poster row gains about a card.

### Fixed

- Posters on a phone. A composed list put four cards of roughly 85 points next to each
  other, which cut off nearly every title. That is three columns on a normal phone now, two
  on a small one, and a title may run to two lines without making its neighbours taller. A
  status label that does not fit shows its icon instead of clipping mid-word.
- Cards in a grid have real spacing again, in both directions. A focused card grew over the
  three pixels of padding that were separating it from its neighbour, and the caption came
  out of one ratio that left too little room for two lines of text in a narrow column. The
  caption follows the system text size, so a larger font makes the grid taller instead of
  cutting the year off.
- The first row of a grid no longer sits against the hairline under the heading.
- On Apple TV, the text over the artwork on Libraries ran into the heading of the first row.
- On Apple TV, a focused row in Settings was invisible. Navigating always worked; the
  highlight was painted over by the card behind it.
- iCloud sync is visible in Settings on Apple TV.
- The download location stays on the device you set it on, instead of following iCloud to
  another one.
- A settings page no longer shows a divider with nothing under it. Two playback options are
  Android only, and hiding them left their separator behind.
- Connecting Tautulli: the screen keeps the connection method you were using, and a rejected
  key says whether the token expired or the wrong method is selected. Both used to read as
  "token expired", which sent people off generating tokens they did not need.
- Secrets stay out of the log you can send in for support. Keys in web addresses and
  authorization headers are stripped before a line is written.
- An intro marker is only skipped automatically for an episode. In a film, a chapter called
  "Intro" was skipping real film.

## 2.8.0 · build 221 · 17 August 2026

<!-- commit: 2cb7ae8 -->

### Fixed

- Watchlist cards no longer overlap. On TV, the title of a playable card ran into the row
  below it and posters in the same row came out at different heights. The card was drawn
  32 pixels taller than the cell holding it, in both the Watchlist grid and the watchlist
  row on My Pleya.

### Improved

- On phones, My Pleya is the only personal entry point. The avatar menu in the top right of
  the home screen is gone there; Profiles, Settings and Sign out sit at the bottom of My
  Pleya instead, and the My Pleya tab now shows your actual profile picture. Desktop and
  Apple TV keep the header menu, because they never show a My Pleya tab.
- The two-person icon on the home screen is Watch Together and the phone icon is the
  Companion Remote. Neither one changed.

## 2.8.0 · build 220 · 16 August 2026

<!-- commit: dd75c69 -->

### New

- **Your watchlist, from both sides.** Titles you add to your Plex watchlist on your phone,
  and anything you favourite in Jellyfin, now show up in Pleya as one list. It has its own
  spot in the sidebar on desktop and Apple TV.
- **My Pleya**, a personal tab on phones that gathers your watchlist, downloads, requests
  and settings in one place instead of spreading them across the bottom bar.
- Add and remove from the detail screen, the long-press menu and the sheet. The action only
  appears for movies and shows, and only while you are online: a watchlist change is
  refused rather than silently queued when there is no connection.

### Notes

- The same film can be a Plex watchlist entry and a Jellyfin favourite at once. Removing it
  takes it off both. If one side fails, Pleya re-reads the list instead of guessing what
  happened.

## 2.8.0 · build 219 · 15 August 2026

<!-- commit: 4e9b76b -->

### Fixed

- **Clicking a letter on the Apple TV keyboard does something again.** Swiping worked,
  dictation worked, typing from an iPhone worked, but pressing the touchpad on a letter did
  nothing at all. The press was being claimed before tvOS ever got to see it. Search, sign
  in, server addresses and the Requests screens all use that keyboard, so all four were
  affected.

## 2.8.0 · build 218 · 14 August 2026

<!-- commit: 717ed46 -->

### New

- **Pick a spot on the timeline with the remote.** Press select on the focused progress bar
  and playback pauses on a preview frame; left and right move the preview, select jumps
  there, back cancels. The thumbnail stays pinned while you move.
- **Seeking speeds up as you keep swiping.** The 1.5x to 10x acceleration used to need a
  held D-pad, so swipes on the Siri Remote touchpad were stuck at ten seconds a step
  forever. Scrub thumbnails now show up during swipes too.

### Fixed

- The skip-intro and next-episode buttons were nearly unreachable with a remote. Pressing up
  opened the player controls instead, and the only route to the button ran through the
  timeline. Up now goes straight to it while it is on screen, and it no longer disappears
  while it has focus.
- During the credits, two next-episode buttons could appear at almost the same spot.
- **Autoplay silently skipped episodes.** Three separate faults: a stuck loading flag that
  killed every later attempt in the session, an end-of-file signal that was lost if it
  arrived during a transition or behind the "still watching?" prompt, and a short episode
  that ended before the next one was known. Every decision the countdown makes is now in
  the log.
- Uploading a log always failed with the same unhelpful message. The relay was fine; Pleya
  was sending up to 5 MB at a server that accepts 1 MB, and never read the reply. Logs are
  now trimmed to the newest lines with a marker, and every outcome (too large, too soon,
  refused, server error, no connection) says what it actually was.
- **No macOS build in TestFlight was installable since build 196.** An export-compliance key
  was missing from the macOS app, so Apple hid every upload from testers while the upload
  itself reported success. Builds 214 and 216 were released retroactively.

## 2.8.0 · build 214 · 10 August 2026

<!-- commit: aac9a24 -->

### Fixed

- **The way out to Jellyfin arrived five minutes too late.** On the "Sign in with Plex"
  screen, the "Using a Jellyfin server?" button only appeared after the PIN timed out, so
  anyone who picked Plex by mistake stared at a code for five minutes first. It now sits
  under the PIN itself, in both the QR and the browser flow, and it properly cancels the
  Plex attempt instead of leaving it running in the background.
- **The profile screen on macOS was blank until you pressed Esc.** Two things at once: the
  screen could not tell "still loading" from "empty" from "stalled", and the add-profile
  button sat below the fold with nothing to scroll it into view. There are three distinct
  states now, and the button lives inside the empty state.

## 2.8.0 · build 212 · 9 August 2026

<!-- commit: b1cb51b -->

### Fixed

- **Audio could cut out entirely on Apple TV over HDMI.** With audio output on `auto` and a
  Dolby track, Pleya would send a bitstream to a receiver that never agreed to take one, and
  the audio renderer stalled. `auto` no longer bitstreams at all; passthrough stays a
  deliberate choice.

### New

- **Passthrough that corrects itself.** If a bitstream fails, Pleya falls back to PCM within
  a second, says so, and remembers the route so the next episode does not stall the same
  way. A watchdog covers the case where playback simply stops moving.
- The performance overlay shows the active audio output and its format, which is the only
  way from inside the app to tell whether a bitstream is really leaving the device or mpv is
  quietly decoding it.

## 2.8.0 · build 209 · 8 August 2026

<!-- commit: de48dbb -->

### New

- **Blu-ray ISOs and unpacked BDMV folders play.** An `.iso` is a filesystem rather than a
  stream, so until now it was simply invisible in the app. Pleya recognises both shapes and
  hands them to the player as a disc.

## 2.8.0 · build 209 · 7 August 2026

<!-- commit: bec37b2 -->

### New

- **Dolby Atmos and spatial audio on iPhone, iPad and Apple TV.** On AirPods, Pleya gave you
  stereo where other players gave Atmos. The missing piece was one opt-in: without it the
  audio route reports two channels and everything is mixed down before spatial audio can do
  anything. Passthrough was also closed off on Apple platforms and is now available.

### Fixed

- Discover in Requests always said "Something went wrong. Try again." An expired session or
  a missing permission read the same as a network hiccup, so retrying could never help.
  Each cause now gets its own message.

## 2.8.0 · build 205 · 6 August 2026

<!-- commit: de652d4 -->

### Fixed

- **One swipe moves the focus one poster.** On Apple TV a single swipe sometimes jumped two
  cells, and a diagonal swipe could move in a direction you had not swiped at all. Two
  independent input paths were both turning the same finger movement into arrow presses.
  The first one to produce a direction now owns the whole gesture.
- The same physical swipe gave one step one time and three the next, because the distance
  travelled past the threshold was thrown away. The step count is now simply distance
  divided by threshold.
- **Text entry on Apple TV was unusable and could not be dismissed.** Pleya now opens the
  tvOS system keyboard, which is also the surface the Siri Remote's microphone dictates
  into, so the extra screen in between is gone. Menu closes it. If the keyboard does not
  come up within four seconds, Pleya falls back to the on-screen D-pad keyboard instead of
  leaving you with a dead overlay.
- The D-pad no longer drives the screen behind an open keyboard.

## 2.8.0 · build 202 · 5 August 2026

<!-- commit: 3148604 -->

### New

- **Dictate a search on Apple TV.** The search field was decoration before: it could not be
  selected. Pressing it now opens the system keyboard pre-filled with your query, results
  update while you dictate, and Done focuses the first result.

### Fixed

- Recent searches could not be reached with a remote at all, and "Clear history" threw an
  error and did nothing on every platform.
- Starting a search left the remote dead, because the skeleton placeholders that replaced
  the results had nothing to focus.
- Back could escape out of an open sheet and land on the sidebar in the same press.
- Sheets opened from the Requests detail screen came up with nothing focused.
- On Android, "search X in Pleya" through the Assistant landed on an empty screen when the
  app had been fully closed.

## 2.8.0 · build 201 · 3 August 2026

<!-- commit: a6218ad -->

### New

- **Voice search on Android and Android TV**, using the system recogniser, so it needs no
  microphone permission of its own. Assistant searches and the leanback search row work too.
- An on-screen keyboard built into the TV search page instead of a pop-up over it.

### Fixed

- Plex and Jellyfin are equal starting points when you sign in. Choosing one no longer leaves
  you without a way back to the other.
- The featured hero on Discover could crash the screen while it was laying out.

## 2.8.0 · build 195 · 29 July 2026

<!-- commit: 1b58f73 -->

### New

- **Subtitle tracks are named properly.** When a file plays untouched, the track list only
  carries what the container itself says, which for an untagged track meant "Track 1". Pleya
  now borrows the language and title your server already knows.
- A "Recently Added Shows" row on the home screen.
- Downloads resume after the system pauses them, after the network drops, and on retry.

### Fixed

- The aspect ratio and zoom settings did nothing on iPhone, iPad and Apple TV.
- On Apple TV, the details button on the hero was unreachable with the D-pad, and subtitles
  disappeared when zoomed.
- The billboard on the home screen fetches missing artwork instead of showing a gap, and
  stays readable while you scroll past it.
- Changes to the home screen layout apply immediately rather than after a restart.

## 2.8.0 · build 186 · 23 July 2026

<!-- commit: 71f9d7d -->

### New

- **Pleya Share**, which turns one device into a small media server for your other Pleya
  devices. Pair once with a QR code and stream over Wi-Fi, a personal hotspot, or a cable.
  On iOS 26 and most Android phones it can also connect directly through Wi-Fi Aware, with
  no router or hotspot involved, and when both devices are online it falls back to an
  end-to-end encrypted relay. Several devices can stream from one host at once.
- A locked iPhone keeps serving while it is the host.
- Shared items borrow posters, metadata and watch progress from your Plex or Jellyfin
  account, per episode as well as per title, the same way local folders do.

### Fixed

- Starting a title from the home screen hero began at zero instead of where you left off.
- Watch progress synced through iCloud took the last write rather than the furthest point,
  so a device that was behind could undo one that was ahead.
- Audio kept playing on iOS when the screen locked, episodes in a share sorted correctly,
  local posters appeared on a cold start, and a host restart no longer breaks live streams.

### Improved

- The screen is kept awake only on desktop and TV now, and discovery beacons and polling
  back off when nothing is happening.

## 2.8.0 · build 138 · 4 July 2026

<!-- commit: 3c160b5 -->

### New

- **Requests, through Jellyseerr and Overseerr.** Browse, search and request movies and shows
  without leaving Pleya, and follow each request from pending to available. Without a
  requests server configured, the feature stays hidden.
- The tvOS system keyboard, including typing from a nearby iPhone, and a hero that follows
  your focus. The home billboard is much larger.
- Discover leads with the newest released films across all your servers instead of with
  continue-watching.
- Settings sync through iCloud.

### Fixed

- Signing in to a requests server with a Plex account failed with an "unsupported media
  type" error.
- On Apple TV, the zoom button was reachable again and the AirPlay button (which does
  nothing there) is gone.

## 2.8.0 · build 131 · 3 July 2026

<!-- commit: 394005e -->

### New

- **Recommendations that never leave your device.** Pleya builds a taste profile locally,
  with a 90-day decay, and uses it for "Recommended for you", "Because you watched" and
  "Hidden gems". Nothing about what you watch is uploaded. There is a switch to turn it off.
- Richer home rows on Jellyfin servers: "Top Rated" and "Something Different".
- Empty, error and offline states across the app instead of blank screens.

### Improved

- **The app is called Pleya.** New name, new logo, and the red-to-amber accent that runs
  through the interface. The progress bar under half-watched titles was rebuilt to match.

## 2.8.0 · build 122 · 2 July 2026

<!-- commit: 8a008f0 -->

### New

- First build. Pleya starts as a fork of [Plezy](https://github.com/edde746/plezy) by
  edde746, under the GPL-3.0.
