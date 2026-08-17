---
title: Getting started
slug: getting-started
order: 2
group: Getting started
icon: rocket_launch
summary: Connect a Plex or Jellyfin server and get to your first film.
updated: 2026-08-17
---

# Getting started

Without a server there is nothing to watch, so the first thing Pleya asks for is a
connection. Plex and Jellyfin are equal starting points: pick either, and you can always
switch to the other from the same screen.

![Choosing between Plex and Jellyfin on first launch](/docs-media/signin-choice.png)

## Signing in with Plex

1. Choose **Sign in with Plex**.
2. Pick how to sign in. **Use browser** opens plex.tv in a browser window. **Show QR code**
   puts a code on screen that you scan with your phone and finish there, which is the
   easier route on a television.
3. Pleya waits while you confirm ("Waiting for authentication...").
4. Every server shared with your Plex account is added automatically, and Plex Home users
   turn into [profiles](/docs/profiles).

You never type your Plex password into Pleya. Signing in always happens on Plex's own site.

If you picked Plex by mistake, the **Using a Jellyfin server?** link sits directly under
the code. It cancels the Plex attempt and takes you to the Jellyfin form.

## Connecting to Jellyfin

1. Choose **Connect to Jellyfin**.
2. Enter the server address, for example `https://jellyfin.example.com`. Several addresses
   are allowed, separated by commas. If the server is on the same network, Pleya usually
   finds it by itself and you can just tap it.
3. Press **Find server**. Pleya checks the address and shows the server name back to you.
4. Enter your username and password, or use **Quick Connect**: Pleya shows a code that you
   type into the Jellyfin web interface, so nothing needs typing on the TV.

![Entering a Jellyfin server address](/docs-media/jellyfin-connect.png)

## Address trouble

The two things that go wrong most:

- **The scheme is missing.** `jellyfin.example.com` is not enough; include `https://`.
- **The port is missing.** Jellyfin often runs on `:8096`. Try the exact same address in a
  browser on the same device. If it does not open there, Pleya cannot reach it either.

## More than one server

You can keep several servers connected at the same time, Plex and Jellyfin side by side.
Their content is merged on the home screen and in search. Add more later through
**Settings**, then **Connections**.

## From here to a film

1. Choose or create your profile on the "Who's watching?" screen.
2. You land on [Home](/docs/the-home-screen). Scroll the rows, or open
   [your library](/docs/browsing-your-libraries) for everything at once.
3. Tap a film, then **Play**.
4. Set your [subtitle and audio track](/docs/subtitles-and-audio) while it runs. Pleya
   remembers that choice for the next episode.

Stop halfway if you like. The film is waiting under **Continue watching** the next time,
and the featured item at the top of Home offers **Resume**.
