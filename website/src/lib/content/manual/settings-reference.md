---
title: Settings reference
slug: settings-reference
order: 17
group: Devices and settings
icon: settings
summary: Every settings group, what each option changes, and which ones matter most.
updated: 2026-08-23
---

# Settings reference

Settings sit in the navigation on desktop and Apple TV, and inside
[My Pleya](/docs/watchlist-and-my-pleya) on a phone.

![The settings overview](/docs-media/settings-overview.png)

## Appearance

| Setting | What it changes |
|---|---|
| **Theme** | System, Light, Dark or **OLED**, which is pure black and saves power on OLED panels. Dark is the default. |
| **Language** | The language of the interface |
| **Show hero section** | The large billboard at the top of Home |
| **Expand cards on hover** | The hover preview on a computer |
| **Library density** / **View mode** | A tighter or roomier grid; grid or list |
| **Episode poster style** | Thumbnail, show poster or season poster in episode lists |
| **Hide spoilers for unwatched episodes** | Blurs image and text for episodes you have not seen |
| **Show navigation bar labels** | Text under the navigation icons |

## Playback

| Setting | What it changes |
|---|---|
| **Player backend** | ExoPlayer (recommended) or mpv, on Android |
| **Default quality** | The ceiling on stream quality; lower uses less bandwidth |
| **Maximum Resolution** | Caps what the app asks a server for, even when the file is larger: Auto, 1080p or 4K |
| **Hardware decoding** | Smoother playback; leave it on unless you are debugging |
| **Auto skip intro / credits** | Skips them without asking. Intro skipping acts on episodes only. |
| **Small / large skip duration** | How far the skip buttons jump |
| **Rewind on resume** | Backs up a few seconds when you resume |
| **Audio output** | Auto, Passthrough or PCM, see [Subtitles and audio](/docs/subtitles-and-audio) |
| **Even out volume** | Brings every title to the same level as the rest of your television |
| **Reduce loud sounds** | Narrows the gap between quiet dialogue and loud effects. Independent of the switch above |
| **Subtitle styling** | Size, colour, outline and background |
| **Remember track selections** | Keeps the audio and subtitle language you picked, per title, and syncs it to your other Apple devices |
| **Also save the language to Plex** | Writes that language onto the show in Plex, so the official Plex apps follow it too. It overwrites what you set there by hand |

![Playback settings on iPhone](/docs-media/settings-playback.png)

## Behaviour and startup

| Setting | What it changes |
|---|---|
| **Ask for profile on app open** | The "Who's watching?" screen at every launch |
| **Startup section** | Which tab Pleya opens on |
| **Continue watching action** / **Episode action** | Whether a tap plays or opens details |
| **Force TV mode** | Uses the television layout, after a restart |
| **Personalized recommendations** | The on-device taste rows on Home |

## Connections

Add and remove servers, add a Plex account, add a local folder, and set which libraries are
visible. This is also where a server that is no longer reachable gets removed.

A Pleya Server sits in its own block here rather than among the sources on this device, since it
is an account on a server elsewhere. Its row shows who you are signed in as, and **Disconnect**
removes it from this device even while the server is offline or its sign-in has expired.

## Integrations

- **Trakt, MyAnimeList, AniList and Simkl** keep your watch history on those services
- **Discord Rich Presence** shows what you are watching, on desktop
- **Companion Remote** lets a phone drive this device
- **Requests** connects Jellyseerr or Overseerr, see [Requests](/docs/requests)
- **Pleya Share** hosts or joins a device share, see [Pleya Share](/docs/pleya-share)
- **Tautulli** adds viewers, watch statistics and live activity to Pleya, see
  [Movie and show details](/docs/movie-and-show-details). Its own screen carries **Use history
  for recommendations**, which lets the taste rows on Home learn from what that server recorded
  before you had Pleya. Each profile only ever gets its own history, and the processing happens
  in Pleya on this device

## Advanced

- **Export settings** and **Import settings** move your configuration to another device
- **Check for updates**, **Clear cache**, **Reset settings**
- **Keyboard shortcuts**, on desktop, all of them rebindable
- **mpv configuration**, for people who know what they want from mpv
- **Logs**, and the button that uploads one when you are reporting a problem
- **About**, with version information and licences

Settings also sync through iCloud on Apple devices, so a new device starts configured. A
change made on your Mac reaches the Apple TV while both are open, and a device that was
asleep checks for changes when you come back to it. Under the iCloud switch one line says
what the sync is doing: syncing, when something was last sent, whether iCloud has run out of
room for settings, and whether a setting is too large to send. That line describes what this
device sent, never what your other devices received, because iCloud does not report that.

Not everything travels. Pleya Share pairing secrets and the flag recording that this specific
device has a broken system keyboard stay out of both export and iCloud. Settings that describe
one piece of hardware stay on that hardware as well: volume, download folder, hardware
decoding, HDR and the last remote-control address you used. Genuine preferences, like subtitle
appearance, theme and playback behaviour, sync as before.
