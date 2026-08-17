---
title: Troubleshooting
slug: troubleshooting
order: 18
group: Reference
icon: build
summary: The errors people actually hit, what causes them, and what fixes them.
updated: 2026-08-17
---

# Troubleshooting

Each entry names the cause before the fix, because the same message can come from more than
one place.

## "Unable to connect to media server"

The server is off, unreachable, or your own connection dropped. Check that the server is
running and that you have internet. A bar with a **Reconnect** button appears in the app;
press it once the server is back. Anything you downloaded keeps playing meanwhile.

## "Invalid username or password" (Jellyfin)

Wrong credentials, and capitalisation counts. If you do not know the password, ask the
server administrator to reset it, or use **Quick Connect** so you type nothing at all.

## "Server did not respond in time" when adding Jellyfin

The address is wrong or the server is not reachable from outside. Include `https://` and the
port number if there is one, usually `:8096`. Test the exact same address in a browser on
the same device: if it does not open there, Pleya cannot reach it either.

## Signing in with Plex hangs on "Waiting for authentication..."

The sign-in on plex.tv was never completed, and the PIN expires after about two minutes.
Start again and finish it in the browser straight away. On a television, use the QR code and
sign in on your phone.

If you meant to use Jellyfin, the **Using a Jellyfin server?** link sits directly under the
code. It cancels the Plex attempt properly rather than leaving it polling in the background.

## "Playback failed", or a film that will not start

The server cannot deliver or convert the file fast enough. Try again, and if it keeps
failing, open **Version & quality** in the player and pick a lower quality. If the message
mentions a bandwidth or transcode limit, that limit lives on the server and the owner has
to raise it.

## Stuttering or blocky picture

Too much quality for the connection, or too heavy a file for the device. Lower **Default
quality** and confirm **Hardware decoding** is on. On older hardware, switching **Player
backend** between ExoPlayer and mpv sometimes settles it.

## No sound, or the wrong language

The wrong audio track is selected. Open the tracks menu in the player and pick the right
one; Pleya remembers it for the next episode.

If sound cuts out entirely on an Apple TV over HDMI, set **Audio output** to **PCM**.
Passthrough sends a compressed stream that some receivers refuse.

## A download that stalls or fails

The connection was interrupted, or downloading is restricted to Wi-Fi. Open **Downloads**,
then **Manage**, and retry or resume everything. On mobile data, check **Download on Wi-Fi
only**.

## My progress is wrong on another device

Progress lives on the server. If you watched offline, or under a different profile, it can
lag. Get online so Pleya can sync, and confirm you are on the same profile on both devices.

## The profile screen no longer appears at launch

**Ask for profile on app open** is off. Turn it back on in Settings.

## "No channels available" in Live TV

No tuner or DVR is attached to the server, or the guide expired. Press **Reload guide**. If
it stays empty, the server administrator has to check the tuner.

## The keyboard on Apple TV does nothing

If pressing a letter does nothing, update to build 219 or later: an earlier engine claimed
the press before tvOS could see it. If the keyboard does not appear at all, Pleya falls back
to its own on-screen keyboard after four seconds.

## The app behaves oddly after an update

Try **Clear cache** first, under Advanced. If that does not help, **Reset settings**, and
export your settings first if you want them back.

## Reporting something

**Settings**, then **Logs**, then upload. Pleya trims the log to the newest lines and tells
you what happened: too large, too soon after the last one, refused, a server error, or no
connection. Turn on debug logging first if you are chasing something specific, then
reproduce it, then upload.

![The logs screen with the upload button](/docs-media/logs-screen.png)

If none of this helps, the person running your media server can see in the server logs what
went wrong. Tell them what you did, what you saw, and on which device.
