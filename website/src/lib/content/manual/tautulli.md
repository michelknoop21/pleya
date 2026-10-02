---
title: Tautulli
slug: tautulli
order: 15
group: More to watch
icon: insights
summary: Connect Plex activity, title statistics and your existing viewing history to Pleya.
updated: 2026-10-02
---

# Tautulli

[Tautulli](https://tautulli.com/) records activity and viewing history for a Plex Media
Server. Connect it to Pleya to see active streams and title statistics, and optionally
use your existing viewing history for recommendations.

This integration is **Plex only**. Its settings are available to the Plex server
administrator; a regular viewer does not need to connect Tautulli.

## Connect your server

Open **Settings → Integrations → Tautulli** on the device you want to connect. Enter the
address of your Tautulli service, then choose a connection method:

| Method | How to connect |
|---|---|
| **Device token** | In Tautulli, open **Settings → Tautulli Remote App** and register a device. Paste the generated token into Pleya within five minutes. You can revoke this device in Tautulli later. |
| **API key** | Use the permanent key from Tautulli's **Settings → Web Interface** if device registration does not work for your setup. |

Test the connection before saving. Use the Tautulli address, not the address of Plex or
Seerr. The device must be able to reach that address, including when you are away from
home if you want to use the integration there.

Both methods provide access to Tautulli's administration API. The device-token method
keeps your permanent API key out of Pleya and lets you revoke that device separately;
it does not turn the connection into a restricted viewer account. Credentials stay on
this device, outside settings export and iCloud sync.

## See what is playing now

While someone is watching, Pleya shows a live-activity entry. Open it from the **desktop
toolbar** or the **Apple TV sidebar** to see the active streams reported by Tautulli.
When no streams are active, this entry is hidden.

## See who watched a title

A [movie or show detail page](/docs/movie-and-show-details) can show who has watched it,
play counts and recent watch statistics. These come from the connected Tautulli service,
so they reflect the history that service has recorded for the matching Plex server.

## Use existing history for recommendations

Enable **Use history for recommendations** on Pleya's Tautulli settings screen if you
want its recommendation rows to learn from viewing history recorded before you used
Pleya. This is optional; you can leave it off and still use live activity and statistics.

Each profile gets only the history associated with its own Plex account. Pleya processes
that history locally on this device to inform **Recommended for you**, **Because you
watched** and **Hidden gems** on [Home](/docs/the-home-screen). Other viewers do not receive
your Tautulli credentials or see the administrator's activity view.

## If information is missing

Check the connection in Pleya's Tautulli settings and confirm that Tautulli monitors the
same Plex server as the title you opened. A Jellyfin title does not have Tautulli statistics.
A newly configured Tautulli service may have little recorded history, and the live-activity
entry only appears when someone is actually streaming.
