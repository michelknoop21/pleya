---
title: Watchlist and My Pleya
slug: watchlist-and-my-pleya
order: 12
group: More to watch
icon: bookmark
summary: One list fed by your Plex watchlist and your Jellyfin favourites, and the tab that holds it.
updated: 2026-08-19
---

# Watchlist and My Pleya

Your watchlist in Pleya is one list assembled from two sources: entries on your Plex
watchlist, and anything you marked as a favourite in Jellyfin. Add something on your phone
in the Plex app and it is here; add it here and it is there.

![The watchlist grid](/docs-media/watchlist-grid.png)

## Adding and removing

The action sits on the detail page, in the long-press menu and in the sheet. Two limits are
deliberate:

- **Films and shows only.** Individual episodes are not watchlist material on either server.
- **Online only.** A watchlist change is refused when there is no connection rather than
  queued, because a queued change that fails hours later is worse than one that never
  pretended to work.

The same film can be a Plex watchlist entry and a Jellyfin favourite at the same time.
Removing it takes it off both. If one side fails, Pleya re-reads the list from the servers
instead of guessing.

## Sorting and filtering it

The tabs above the grid narrow it to **Movies**, **Shows** or **Available**, the last being
the titles a connected server can actually play right now. The button beside them says what
the list is sorted by, **Recently added**, **Title** or **Year**, on the button itself rather
than in a tooltip, since a tooltip never opens on a touchscreen.

## My Pleya

On a phone, **My Pleya** is the personal tab: your watchlist, your downloads, your requests
and your settings in one place, with your profile picture at the top. Profiles, Settings and
Sign out sit at the bottom of it.

![My Pleya on iPhone](/docs-media/my-pleya.png)

There is no avatar menu in the top corner of the home screen on a phone; that would put the
same actions in two places. Desktop and Apple TV keep the header menu instead, because they
show the watchlist as its own destination in the sidebar and never render a My Pleya tab.

The two-person icon on the home screen is [Watch Together](/docs/watch-together) and the
phone icon is the Companion Remote. Neither is an account button.

## Where the pictures come from

Watchlist artwork is served from Plex's public image CDN, without your account token
attached. That is why a watchlist item shows a poster even for a title that is on no server
you can reach.
