# AudioClipboard 📋

## Basic Description

AudioClipboard _(AudioClipboard.lua)_ is a Lua script designed to be run in the Ardour DAW (v8.12+) that allows one to copy and paste mono and stereo audio regions between projects/sessions/snapshots, whilst maintaining virtually all of the region data in the process.

![AudioClipboard Opening Window](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Opening_Window.png)

### Features

- Works with audio regions, mono and stereo.
- Easy to use, 3-step process: [***Copy → Pre-Paste → Paste***](#how-to-use-audioclipboard)
- Pasted regions retain all original position, trim, envelope, gain, polarity, fade length/shape data, etc..
- Avoids most re-embedding or re-importing of files already present in the project during Pasting.
- By default, original relationships to source materials are preserved almost 1:1, but there's also...
- An option to manually select different files to use for pasting. (This is super convenient for cleaning-up projects in general, and even fixing broken sources (→ [see the examples below](#use-cases-and-other-features).)
- Handles -L/-R regions that came from a use of "Make Mono Regions".
- Handles combined audio regions (-although Ardour currently suffers from [many combined region bugs](https://discourse.ardour.org/t/better-compound-region-handling/111930), which can occasionally cause various problems in attempts to copy them, despite my best efforts).
- There's a built-in 'Source Finder Wizard' that automatically discovers potential source matches (via similar naming) during Pre-Paste, and offers them for approval. (This feature helps reduce redundant or unecessary imports/embeds.)
- All contained in a single, standalone Lua script.
- The Paste action is an undoable command (via ctrl-Z/cmd-Z, etc.).
- File-collisions and accidental erasures are prevented behind the scenes via simple file-name checks.
- Legacy Dual-Mono stereo pairs (with -L/-R endings) are automatically modernized during pre-paste by renaming them with standard (%L/%R) endings.
- Legacy fade shapes inherited from older versions of Ardour (like v2, etc.) are automatically detected and replaced during pasting with their closest modern equivalents. (-And the user is informed about this.)
- Automatically saves your session before any step is executed so that if something goes wrong and Ardour crashes (which is very unlikely), then no previous work is lost.
- Under the GNU General Public License (GPL), thus: 100% free to use, copy, alter, distribute, etc.!

### Known Limitations/Warnings

- It doesn't (yet) work with audio regions/sources with more than 2 channels, sorry.
- It doesn't work with anything MIDI, but this is okay because transferring MIDI regions is easy thanks to Ardour's built-in region export function _(-select the MIDI region, then click Region → Export...)._
- It sometimes fails to properly handle combined/compound regions, mostly due to [known Ardour bugs](https://tracker.ardour.org/view.php?id=9947).

> [!CAUTION]
> - Due to the way in which AudioClipboard pastes regions, this script has the potential to disturb/destroy **automation curves** (-plugin/fader/pan/etc.) on a track if the setting _"Move relevant automation when audio regions are moved" (-under Preferences → Editor)_ is NOT disabled during Pasting. **This is especially true for pasting combined regions.** ***→ So PLEASE be sure to DISABLE that setting BEFORE using AudioClipboard!***

-----------------------------------------------------------------------------------------------------------------------------

## Installation

Simply download the [AudioClipboard.lua](https://github.com/GhostsonAcid/AudioClipboard/blob/main/AudioClipboard.lua) file here on GitHub, and then do the following based on your OS:

![How To Download The AudioClipboard.lua File](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Download_Icon.png)

### GNU/Linux:

1. Navigate to the $HOME/.config/ardour8/scripts folder.
2. Place AudioClipboard.lua in that scripts folder.
3. _(continues below...)_

### macOS/Mac OS X:

1. Open a Finder window, press cmd-shift-G, and type-in: ~/Library/Preferences/Ardour8/scripts/
2. Place AudioClipboard.lua in that scripts folder.
3. _(continues below...)_

### Windows:

1. Navigate to the %localappdata%\ardour8\scripts folder.
2. Place AudioClipboard.lua in that scripts folder.
3. _(continues below...)_

### _Continued steps for all systems:_

3. Open Ardour and go to _Edit → Lua Scripts → Script Manager._
4. Select an "Action" (e.g. "Action 1", etc.) that is "Unset", then click "Add/Set" at the bottom-left.
5. Click "Refresh", and then find and select AudioClipboard in the "Shortcut" drop-down menu.
6. Click "Add" and then close the Script Manager window.
7. AudioClipboard now exists as an easy-access button in the top-right of the DAW (-look for the rectangular clipboard icon).

> [!TIP]
> You can always just click any empty shortcut button in the top-right, hit "Refresh", and then find and set AudioClipboard from the dropdown menu!  Also, to remove a shortcut from a button, hold shift and then right-click it.

-----------------------------------------------------------------------------------------------------------------------------

## How to use AudioClipboard

> [!NOTE]
> Before using AudioClipboard for any considerable work, it is strongly recommended to duplicate the Ardour application itself (and rename it/them if necessary) so you can have two projects open at the same time.  Without doing this, you would have to close and open entire projects with each copy and paste action, which is obviously silly. _(-If you are using Windows, however, duplicating Ardour might be [difficult or downright impossible.](https://discourse.ardour.org/t/using-multiple-copies-of-ardour-simultaneously/112031/3?u=ghostsonacid)  As of now, this is untested by me.)_

### Step 1 - Copy Regions

Select mono and/or stereo audio regions that you would like to copy, and then use the "Copy Regions" function.

![Step 1; Select Regions](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Basic_Use_Step_1_1_Select_Regions.gif) ![Arrow](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/Arrow_1.png) ![Step 1; Copy Regions](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Basic_Use_Step_1_2_Copy_Regions.gif)

### Step 2 - Pre-Paste Files

In the project session/snapshot you would like to paste into, select an audio track and use the "Pre-Paste Files" function.  This step ensures that all of the necessary audio source files are embedded or imported into the current session as required.

![Step 2; Select Track](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Basic_Use_Step_2_1_Select_Track.gif) ![Arrow](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/Arrow_1.png) ![Step 2; Pre-Paste Sources](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Basic_Use_Step_2_2_Pre-Paste_Sources.gif)

> [!TIP]
> Always use "View File List" before proceeding to ensure proper file usage, and consider using the _"Manually Select Files to Use"_ feature to redirect pasted regions to different/better sources (-see additional info below).

### Step 3 - Paste Regions

With that same (or whichever) audio track selected, use the "Paste Regions" function. _→ Click OK and watch your regions appear!_

![Step 3; Select Track](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Basic_Use_Step_3_1_Paste_Regions.gif) ![Arrow](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/Arrow_1.png) ![Step 3; Paste Regions](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Basic_Use_Step_3_2_CONGLATURATION.gif)

***~Done!***

-----------------------------------------------------------------------------------------------------------------------------

## Use Cases and Other Features

The following is a series of examples of some useful things you can achieve using AudioClipboard.

### Manually Select Files To Use

Beyond basic copying and pasting, manually selecting which sources to use for pasting is perhaps the single best feature in AudioClipboard. There are many situations where this can come in handy:
- A project's Source List might be cluttered with duplicate entries, and you'd like to clean it up.
- You might be working with lower-quality sources (-like compressed MP3s), but now you wish to 'swap them out' for better sources while maintaining all of the original envelope, gain, trimming, etc..
- You might also just prefer having certain regions link to sources located in a new/different/updated folder (or even a different SSD/HDD).
- You have already edited (e.g. cut, trimmed, positioned, etc.) a full, combined drum mix recording, but you realize you actually have access to the individual drum stem files, and now you wish to apply all that same editing to every stem recording in the group.
- You have some broken/missing sources that you just cannot seem to fix, although you do have new sources that would be suitable replacements (-see the next portion).

In all of these scenarios (and likely many more), the _"Manually Select Files To Use"_ feature provides a solution!

Here is an example for how it can be used:

![Manual File Selection Example](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Manual_File_Selection.jpg)

### Fix Broken/Missing Sources

As an extension of what manual file selection can do, you can also fix broken/missing sources like so:

![How to fix broken/missing sources using AudioClipboard](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_How_To_Fix_Broken_Sources.jpg)

### Full Track & Regions Duplication

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;This script can be used in conjunction with Ardour's built-in track-template-creator to achieve full track and region duplication from one session/snapshot into another.  If you are looking to merge Ardour songs/projects, this is the way to do it.  (Perhaps at some point I will implement this ability directly into AudioClipboard itself.  But for now, this method will suffice!)

#### 1. Right-click on an audio mixer strip's name, then use "Save As Template...".

![Track Template Creation](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/Track_Template_Creation.gif)

#### 2. Then, when creating a new track in your destination session/snapshot, use the template you saved.

![Track Template Use](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/Track_Template_Use.gif)

#### 3. And then simply copy, pre-paste, and paste via AudioClipboard as described earlier!

-----------------------------------------------------------------------------------------------------------------------------

## How This Script Works

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;In short, Audio Clipboard works by externally logging all relevant and available data for the copied regions into a file called "AudioClipboard.tsv" in a temporary folder offered by your computer.  Then, during Pre-Paste, it scans for already-present, usable sources, creates a local Region ID Cache (-another, more permanent .tsv file located in your project's `interchange/` directory), and ultimately imports/embeds the remaining sources needed for successful pasting.  And finally, during Pasting, it then clones new audio regions into existence via IDs provided by the local cache, and utilizes the data in AudioClipboard.tsv to recreate the copied regions, with original region size, trim, position, gain, envelope, fade lengths, and other states all being preserved in the process.

### The Pre-Paste Process

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;At the heart of this script is what happens during the "Pre-Paste" process.  Depending on where copied region's sources are located on your computer, the sources that are 'pre-pasted' must be handled uniquely.  Instead of letting Ardour just blindly import (and convert to .wav) any and all source files into each project's `audiofiles/` folder, I decided to take an approach of preserving region-to-source relationships as close to 1:1 as possible.  Thus, for example, if a copied region is coming from a source that is _embedded,_ then when that same source is 'pre-pasted' into a different session, that particular source will be embedded there as well, _-not imported._  Similarly, if a copied region's source is coming from a standard %L/%R (.wav) file pair already imported into the project, then that pair will be duplicated into the other session's `audiofiles/` folder accordingly thus, again, preserving the original region-to-source relationships. And so on...

Here is a diagram depicting the flow of this Pre-Paste 'decision-making' process:

![Pre-Paste Flowchart](https://github.com/GhostsonAcid/AudioClipboard/blob/main/Images/AudioClipboard_Pre-Paste_Flowchart.jpg)

## Other Notes

### Testing

AudioClipboard has been tested thoroughly on macOS Mojave running multiple copies of Ardour 8.12, as well as a VM of Ubuntu Studio.  If for some reason it doesn't work on your particular OS, please let me know.

> [!IMPORTANT]
> If you experience any bugs with this script, please submit an "Issue" here on GitHub, or post about it/them on the Ardour forum (discourse.ardour.org) and link @GhostsonAcid in your comment, and I will try to address it.

### Final Comments

For anyone interested in how any of this works, I've included hundreds of --muted notes all throughout the script itself, describing each step of the process in oftentimes considerable detail.

Thanks to @izlence for establishing the basic premise for AudioClipboard with their [ardour-scripts](https://github.com/izlence/ardour-scripts) GitHub project!

-----------------------------------------------------------------------------------------------------------------------------

Thank you for reading, and I hope this script helps some others out there as much as it has helped me!

_~Enjoy!_

_J. K. Lookinland_
