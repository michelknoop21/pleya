---
title: Live TV and recordings
slug: live-tv-and-recordings
order: 10
group: More to watch
icon: live_tv
summary: The guide, favourite channels, watching from the start, and DVR rules.
updated: 2026-08-17
---

# Live TV and recordings

If a connected server has a tuner with a guide, a **Live TV** tab appears. If you do not see
it, no server offers live television, and nothing in Pleya will make it show up.

![The Live TV guide](/docs-media/livetv-guide.png)

## Watching

- **Guide** is the programme grid per channel and time block: Now, Morning, Afternoon,
  Evening, Late, across Today and Tomorrow.
- **On now** is what is running at this moment.
- **Favourites** are the channels you marked, in the order you put them.

Tap a programme for its card, with **Watch live**, or **Watch from start** when it has
already begun. While watching live you can rewind, and **Go to live** jumps back to the
live edge.

## Recording

- **Record** captures one broadcast
- **Record series** captures every episode
- **Recordings** lists what you recorded, plus scheduled recordings and recording rules

![Recordings with one scheduled](/docs-media/livetv-recordings.png)

Recording is Plex only, and it needs an administrator account on the server. On Jellyfin you
see channels and favourites but no recording buttons, because Jellyfin does not expose
those operations to clients here.

## When the guide is empty

"No channels available" means one of two things: no tuner or DVR is attached to the server,
or the guide data expired. **Reload guide** handles the second. For the first, the server
owner has to look at the tuner configuration; nothing in the app can fix it.
