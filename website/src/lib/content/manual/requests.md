---
title: Requests
slug: requests
order: 13
group: More to watch
icon: add_circle
summary: Asking for titles the server does not have, through Jellyseerr or Overseerr.
updated: 2026-08-18
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

Discover shows trending and popular titles from the requests server. Every poster carries a
status badge:

| Badge | Meaning |
|---|---|
| **Pending** | Requested, waiting for approval |
| **Processing** | Approved, being fetched |
| **Partially available** | Some episodes are on the server |
| **Available** | It is on the server, ready to watch |

![A pending request beside an available one](/docs-media/requests-status.png)

Open a title and choose **Request**. For a show you pick seasons. Approval is up to whoever
administers the requests server, so a request sitting on Pending is not a Pleya problem.

Any row of posters here opens into a full grid with **Show all**, which beats scrolling
sideways through a few dozen titles to find out what is in it.

## Where requests appear

On a phone, under [My Pleya](/docs/watchlist-and-my-pleya). On desktop and Apple TV, as
their own destination in the sidebar. Search results also show request status, so a title
you cannot play tells you whether it is already on its way.
