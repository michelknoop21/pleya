---
title: Requests
slug: requests
order: 13
group: More to watch
icon: add_circle
summary: Asking for titles the server does not have, through Jellyseerr or Overseerr.
updated: 2026-08-19
---

# Requests

If whoever runs your server also runs **Jellyseerr** or **Overseerr**, Pleya can browse,
search and request titles without leaving the app, and follow each request until it lands.
Without such a server configured, the feature stays hidden entirely.

![Discover in Requests with status badges](/docs-media/requests-discover.png)

## Connecting

**Settings**, then **Requests**. Enter the server address, then sign in one of three ways:

| Method | When to use it |
|---|---|
| **Plex** | The requests server is tied to the same Plex account you already use |
| **Local account** | A username and password created on the requests server itself |
| **API key** | An administrator key, when you run the server yourself |

Pleya re-authenticates in the background when a session expires. If something goes wrong it
now says which thing: an expired session, a missing permission and a network problem used
to read identically as "Something went wrong. Try again.", which was unhelpful because
retrying could never fix two of the three.

## Discover and request

Discover shows trending and popular titles from the requests server. The line above the
posters is the same header a library page uses: **All**, **Movies** and **Shows** as tabs on
the left, and **Genre** as an action on the right that opens a panel in the middle of the
window. Genre needs a type first, because the genre lists differ between films and shows.

Every poster carries a status badge:

| Badge | Meaning |
|---|---|
| **Pending** | Requested, waiting for approval |
| **Processing** | Approved, being fetched |
| **Partially available** | Some episodes are on the server |
| **Available** | It is on the server, ready to watch |

![A pending request beside an available one](/docs-media/requests-status.png)

Open a title and choose **Request**. For a show you pick seasons. Approval is up to whoever
administers the requests server, so a request sitting on Pending is not a Pleya problem.

**Advanced options** on that sheet decides which Radarr or Sonarr server the request goes to,
and which quality profile and root folder it uses there. Both open on whatever that server
would have used anyway, so leaving them untouched changes nothing. Changing the server clears
your profile and folder rather than carrying the previous server's choices over to one where
they mean something else.

Any row of posters here opens into a full grid with **Show all**, which beats scrolling
sideways through a few dozen titles to find out what is in it.

## Following your requests

The requests list holds what you asked for, under **All**, **Pending**, **Approved** and
**Available**, each with a count. If your account may approve requests the list shows
everyone's and is headed **All requests**; otherwise it is **My requests** and holds your
own.

Each row carries the real title, the year and the poster. The request itself holds only an id
and an availability state, so Pleya looks the title up once and keeps it. A show says which
seasons were asked for: a run of consecutive seasons reads as a range, and a gap stays
visible instead of being smoothed over.

## Where requests appear

On a phone, under [My Pleya](/docs/watchlist-and-my-pleya). On desktop and Apple TV, as
their own destination in the sidebar. Search results also show request status, so a title
you cannot play tells you whether it is already on its way.
