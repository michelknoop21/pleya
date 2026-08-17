---
title: The player
slug: the-player
order: 7
group: Watching
icon: play_circle
summary: Controls, chapters, gestures, skipping, and what to change when playback struggles.
updated: 2026-08-17
---

# The player

Tap the screen, move the mouse or press a key to bring up the controls. They fade again on
their own.

![Player controls with chapter markers on the timeline](/docs-media/player-controls.png)

## The basics

- Play and pause, skip forward and back. How far a skip jumps is a setting, and there are
  separate small and large skips.
- A timeline with chapter markers. Drag it to seek, with preview thumbnails when your
  server provides them.
- Next and previous episode, and a chapter list.
- **Queue**, which shows and reorders what comes after this.

## Seeking with a remote

On Apple TV, press select on the focused timeline. Playback pauses on a preview frame;
left and right move that preview, select jumps there, back cancels without moving. Left or
right on a paused video steps into the same mode.

Keep swiping and the seek speeds up, from 1.5x to 10x, resetting when you change direction.

![Scrub preview while seeking with the remote](/docs-media/player-scrub.png)

## Player settings

The gear icon inside the player:

| Option | What it does |
|---|---|
| **Playback speed** | Faster or slower |
| **Sleep timer** | Stops after a set time, or at the end of the video |
| **Audio sync** / **Subtitle sync** | Shifts sound or subtitles when they drift |
| **Version & quality** | Another file version, or a lower quality on a slow connection |
| **Zoom** | Letterbox, fill the screen, or stretch |
| **Auto-play next** | Start the next episode by itself |

## Skipping

**Skip intro** and **Skip credits** appear where the server knows the marks. Settings can
make both happen automatically. On a remote, pressing up jumps straight to the button while
it is on screen.

Watch long enough without touching anything and Pleya asks **Still watching?**. Choose
**Continue**.

## Gestures on a phone or tablet

- **Double-tap** the left or right half to jump back or forward
- **Swipe on the left edge** for brightness, **on the right edge** for volume
- **Lock** blocks every control against accidental taps
- **Picture in Picture** keeps playing in a small window while you use other apps, on
  Android, iOS and macOS

## When playback struggles

Two settings account for most of it. Lower **Default quality** if the picture is blocky or
stutters, since the server may be transcoding harder than it can manage. Check that
**Hardware decoding** is on. On older hardware, switching **Player backend** between
ExoPlayer and mpv sometimes settles it.

Pleya prefers direct play, which means the file is sent untouched and the server does no
work. Transcoding only kicks in when the device or the connection cannot take the original.
