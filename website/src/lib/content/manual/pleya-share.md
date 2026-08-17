---
title: Pleya Share
slug: pleya-share
order: 15
group: More to watch
icon: cast_connected
summary: Turning one device into a small media server for your other Pleya devices.
updated: 2026-08-17
---

# Pleya Share

Pleya Share lets one device serve its local folders to your other Pleya devices. Pair once
with a QR code and the files on a phone become a library on a tablet, with no server and no
internet in between.

Pleya Share is a premium feature and will be part of the paid tier once pricing is announced
after the beta.

## Setting up the host

1. On the device holding the files, open **Settings**, then **Pleya Share**, then **Host**.
2. Pick the folders to share.
3. Leave the QR code on screen.

![The host screen with its QR code](/docs-media/share-host.png)

On Android the host runs as a foreground service. On iOS it keeps a silent audio loop alive,
which is what lets an iPhone keep serving with the screen locked.

## Joining from another device

**Settings**, then **Pleya Share**, then **Join**, then scan the code. The shared folders
appear as a library alongside your servers.

![A shared library seen from the guest side](/docs-media/share-library.png)

## How the two devices find each other

Pleya tries in this order and uses the first one that works:

| Situation | Route |
|---|---|
| Same Wi-Fi | Direct, over the local network |
| iOS 26 or most Android phones | Wi-Fi Aware, a direct link with no router or hotspot |
| Personal hotspot | The addresses in the QR code plus the gateway |
| Cable, ethernet adapters or USB tethering | Link-local addressing |
| Different networks, both online | An end-to-end encrypted relay |
| Nothing reachable | The catalogue you already browsed, offline |

One limit worth knowing before you try it: a direct iPhone to iPad link over USB-C does not
work, because iOS gives apps no IP network there. Use a hotspot, or put a computer on one
end with tethering enabled.

## Several devices at once

More than one guest can stream from the same host at the same time, and each keeps its own
watch position.

## Posters and progress

Shared items are matched against your Plex or Jellyfin library on title, year, season and
episode. That match is where the posters and metadata come from, and it is what syncs your
progress back to your account, per episode as well as per title.
