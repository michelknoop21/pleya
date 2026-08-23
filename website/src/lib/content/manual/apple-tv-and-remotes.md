---
title: Apple TV and remotes
slug: apple-tv-and-remotes
order: 16
group: Devices and settings
icon: settings_remote
summary: Driving Pleya from the sofa: the Siri Remote, D-pad focus, and the Companion Remote.
updated: 2026-08-23
---

# Apple TV and remotes

On a television, Pleya is driven entirely by focus: one thing on screen is highlighted with
a white ring, and the directional pad moves that highlight. Everything reachable can be
reached that way.

![The sidebar with the focus ring on one item](/docs-media/tv-sidebar.png)

## The sidebar

The sidebar carries the destinations: home, your libraries, search, downloads, settings. It
opens when the focus moves into it, which is what pressing left from the leftmost item on a
screen does, and what Menu does from anywhere that is not the sidebar already. It closes the
moment the focus leaves. Picking a destination does both in one press: the screen opens, the
highlight lands inside it, and the sidebar closes behind you.

Two ways it used to get stuck are gone. A row can disappear while the highlight sits on it,
which is what happens when the last stream ends and "Now playing" goes away. That left the
sidebar standing open with nothing highlighted and no button that led out of it; the
highlight now moves to whatever took the row's place. The other way round, choosing a
destination whose screen was not ready yet, Libraries before you have picked a library for
instance, kept the highlight on the sidebar item you had just pressed while the sidebar
closed around it.

## The Siri Remote

| Input | What it does |
|---|---|
| **Swipe on the touchpad** | Moves the focus. One swipe moves one step. |
| **Click the directional ring** | The same, one step per click |
| **Select** | Activates what is focused |
| **Long-press select** | Opens the quick menu on a poster |
| **Menu** | Goes back, and closes the keyboard when it is open |
| **Microphone** | Dictates, once a keyboard is open |
| **Play/pause** | Plays and pauses without opening the controls |

Swiping and clicking used to disagree about direction, so a diagonal swipe could move the
focus somewhere you had not swiped, and the same physical swipe could move one cell or
three. Both are fixed: the first input path to produce a direction owns the whole gesture,
and the step count is simply distance divided by the threshold.

## Typing

Press select on a text field and the tvOS system keyboard opens. That keyboard is also the
Siri Remote's dictation surface and the target for typing from a nearby iPhone, so all three
input methods land in the same place. Menu closes it.

If the keyboard fails to appear within four seconds, Pleya switches to its own on-screen
keyboard, which you drive with the D-pad.

## In the player

- **Up** opens the controls, or jumps straight to the skip button while it is showing
- **Down** opens the info panel with tracks and chapters
- **Select on the timeline** enters scrub mode: left and right move a preview, select jumps
  there, back cancels
- Swiping to seek accelerates the longer you keep going

## Android TV

The same focus model. The remote's microphone button opens voice search, and searching from
the Assistant or the leanback row opens Pleya on the results, even from a fully closed app.
Android TV also gets a Watch Next row on the system home screen.

## Companion Remote

Your phone can drive the app on a TV or a computer over the same network. Open **Companion
Remote** from the phone icon on the home screen and pick the device. Useful when the title
you want is easier to type on a phone than to spell out with a D-pad.

## Forcing the TV interface

**Force TV mode** in Settings makes any device use the television layout after a restart.
It exists for TV boxes that do not identify themselves as televisions.
