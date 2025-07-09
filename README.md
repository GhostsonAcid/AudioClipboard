# AudioClipboard

## Basic Description:

AudioClipboard (AudioClipboard.lua) is a script designed to be run in the Ardour DAW (v8.12+) that allows one to copy and paste mono and stereo audio regions in between projects/sessions/snapshots.

## Features:

- Works with audio regions, mono and stereo.
- Easy to use, 3-step process: Copy ➝ Pre-Paste ➝ Paste ✅
- Pasted regions retain all original position, trim, envelope, gain, fade length/shape data, etc..
- Avoids most re-embedding or re-importing of files already present in the project during Pasting.
- By default, original relationships to source materials are preserved almost 1:1, but there's also...
- An option to manually select different files to use for pasting.  This is super convenient for cleaning-up projects in general, and even fixing broken sources (-i.e. you can literally copy and paste regions from broken/missing sources and redirect to new source material in the process).
- Handles combined audio regions (-although Ardour currently has MANY bugs regarding combined regions [link], which can occasionally cause various problems in attempts to copy them despite my best efforts).
- Handles -L/-R regions that came from a use of "Make Mono Regions".
- There's a built-in 'Source Finder Wizard' that automatically discovers potential source matches (via similar naming) during Pre-Paste, and offers them for approval.
- All contained in a single, standalone Lua script.
- The Paste action is an undoable command (via ctrl-Z/cmd-Z, etc.).
- File-collisions and accidental erasures are prevented behind the scenes via simple file-name checks.
- Legacy Dual-Mono stereo pairs (with -L/-R endings) are automatically modernized during pre-paste by renaming them with standard (%L/%R) endings.
- Under GPL, thus: 100% free to use, copy, alter, distribute, etc., etc... 👍

## Known Limitations:

- It doesn't work with anything midi, sorry.
- It doesn't work with audio regions/sources with more than 2 channels.
- It sometimes fails to properly handle combined/compound regions due to known Ardour bugs.

## ⚠️ Warning:

- AudioClipboard has the potential to disturb/destroy automation curves (plugin/fader/pan/etc.) on a track if the setting _"Move relevant automation when audio regions are moved"_ (under Preferences -> Editor) is NOT disabled during Pre-Pasting/Pasting.  ***So PLEASE be sure to DISABLE that setting BEFORE using AudioClipboard.***

## Installation:

Simply download the AudioClipboard.lua file, and do the following:

### Gnu/Linux:

1. Navigate to the $HOME/.config/ardour8/scripts folder.
2. Place AudioClipboard.lua in that folder.
3. _(continues below...)_

### macOS:

1. Open a Finder window, press cmd-shift-G, and type-in: ~/Library/Preferences/Ardour8/scripts/
2. Place AudioClipboard.lua in that scripts folder.
3. _(continues below...)_

### Windows:

1. Navigate to the %localappdata%\ardour8\scripts folder.
2. Place AudioClipboard.lua in that folder.
3. _(continues below...)_

### Continued steps for all systems:

3. Open Ardour and go to Edit -> Lua Scripts -> Script Manager.
4. Select an "Action" (e.g. "Action 1", etc.) that is "Unset", then click "Add/Set" at the bottom-left.
5. Click "Refresh", and then find and select AudioClipboard in the "Shortcut" drop-down menu.
6. Click "Add" and then close the Script Manager window.
7. AudioClipboard now exists as an easy-access button in the top-right of the DAW (-look for the rectangular clipboard icon).

## Using AudioClipboard

...


