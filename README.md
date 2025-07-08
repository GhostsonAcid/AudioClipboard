# AudioClipboard

## Basic Description:

AudioClipboard (AudioClipboard.lua) is a script designed to be run in the Ardour DAW that allows one to copy and paste mono and stereo audio regions in between projects/sessions/snapshots.

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

## Warnings:

- AudioClipboard has the potential to disturb/destroy automation (plugin/fader/pan/etc.) on a track if the setting "Move relevant automation when audio regions are moved" (under Preferences -> Editor) is NOT disabled during Pre-Pasting/Pasting.

...
I will add more text soon...
