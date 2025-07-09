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

### Step 1:

Select mono and/or stereo audio regions that you would like to copy, and then use the "Copy Regions"  function.

### Step 2:

In the project snapshot you would like to paste into, select an audio track and use the "Pre-Paste Files" function.  This step ensures that all of the necessary audio source files are embedded or imported into the current session as required. _(-TIP: Always use "View File List" before pre-pasting to ensure proper file usage, and consider using the "Manually Select Files to Use" feature to redirect pasted regions to different/better sources!)_

### Step 3:

Select the audio track you wish to paste onto and use the "Paste Regions" function. --> Click OK and watch your regions appear! _~Done!_

## How This Script Works

In short, Audio Clipboard works by externally logging all relevant and available data for the copied regions into a file called "AudioClipboard.tsv" in a temporary folder offered by your computer.  Then, during Pre-Paste, it scans for already-present, usable sources, creates a local Region ID Cache (-another, more permanent .tsv file), and ultimately imports/embeds the remaining sources needed for successful pasting.  And finally, during Pasting, it then clones new audio regions into existence via IDs provided by the local cache, and utilizes the data in AudioClipboard.tsv to recreate the copied regions, with original region size, trim, position, gain, envelope, fade lengths, and other states all being preserved in the process.

## Other Notes

This script can be used in conjunction with Ardour's built-in track-template-creator _(-right-click on an audio mixer strip's name, then use "Save As Template...")_ to achieve full track and region duplication from one session/snapshot into another.

Also, if you experience any bugs with this script, please submit an "Issue" here on GitHub, or post about it/them on the Ardour forum (discourse.ardour.org) and link @GhostsonAcid in your comment, and I will try to address it.

***~Thank you and enjoy!***

-J
