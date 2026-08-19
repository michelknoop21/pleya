---
title: Subtitles and audio
slug: subtitles-and-audio
order: 8
group: Watching
icon: subtitles
summary: Picking tracks, styling subtitles, re-timing them, and Atmos on Apple devices.
updated: 2026-08-19
---

# Subtitles and audio

The tracks menu in the player holds three things: the audio track, the subtitle track, and
a search for subtitles that are not in the file.

![The audio and subtitle track menu](/docs-media/player-tracks.png)

## Choosing tracks

Pick a language or a specific track, or switch subtitles off. Pleya remembers the choice
per title and applies it to the next episode of the same show, so you set it once per
series rather than once per episode. On Apple devices that memory travels with you over
iCloud. **Remember track selections** in Settings turns it off.

Underneath it sits **Also save the language to Plex**, which writes the language onto the
show on the server. Turn it on and the official Plex apps, and Pleya on Android or Windows,
open that series the same way. It replaces whatever language was set on the server by hand,
so leave it off if someone else curates that.

That switch also decides how far the memory reaches while Plex is transcoding. If Plex burns
the subtitles into the picture, the next episode has no track left for Pleya to select, so
only the server can carry the choice forward. With **Also save the language to Plex** off,
the language you pick still applies to the episode you are watching and is kept on this
device, but the episode after it opens on whatever the server prefers.

Track names come from the file, and an untagged track used to show up as "Track 1". Pleya
now borrows the language and title your server already knows for that stream, so the list
reads properly even on files with bare tags.

## Finding subtitles online

**Search subtitles** looks up and downloads subtitles for the title you are watching. This
one is Plex only: it uses the Plex server's own subtitle search.

## Styling

**Settings**, then **Subtitle styling**, changes size, colour, outline and background, with
a preview line underneath so you can see what you are doing. Full ASS and SSA subtitles are
supported, including their own styling, so a fansubbed release keeps its typesetting.

![Subtitle styling with the preview line](/docs-media/subtitle-styling.png)

## When they do not line up

Open **Subtitle sync** in the player and shift until they match. **Audio sync** does the
same for sound. Both are per playback, not permanent.

## Atmos and spatial audio

On iPhone, iPad and Apple TV, Pleya asks the system for multichannel audio, which is what
lets Dolby Atmos and spatial audio work on AirPods and on a receiver. Without that request
the audio route reports two channels and everything is mixed down before spatialisation can
happen, which is why other players sounded different here for a while.

**Audio output** in Settings has three positions:

- **Auto** decodes on the device and sends PCM. It never bitstreams, because Pleya cannot
  confirm in advance that the other end will accept one.
- **Passthrough** sends the compressed stream to your receiver. If the receiver refuses it,
  Pleya falls back to PCM within a second, says so, and remembers the route for the next
  episode instead of stalling again.
- **PCM** always decodes on the device.

The performance overlay in the player shows the active audio output and its format. That is
the only way from inside the app to tell a real bitstream from a decode that merely claims
to be one.

## Evening out the volume

Two switches, and they are independent:

- **Even out volume** brings every title to the same level as the rest of your television,
  so a quiet documentary and a loud blockbuster start at the same place.
- **Reduce loud sounds** narrows the gap between dialogue and effects. This is the one for
  watching at night without a hand on the volume.

They used to be a single setting with three positions, which meant taming the bangs also
levelled everything else whether you wanted that or not. An existing choice carries over to
the pair.

Neither works during passthrough: both need decoded audio to act on, and a bitstream is
handed to your receiver untouched. Pleya says so in the player rather than leaving a switch
that quietly does nothing.
