ardour {
  ["type"] = "EditorAction",
  name = "AudioClipboard (v1.0)",
  license = "GPL",
  author = "J.K.Lookinland & ALSA",
  description = [[     This script lets you 'copy and paste' selected mono and
  stereo audio regions between project sessions/snapshots,
  with almost all original region data being preserved in the
  process.
  
                                 (2025-07-06)]]
}

-- Draw a custom clipboard icon:
function icon(params) return function(ctx, width, height, fg)
  local wh = math.min(width, height)
  ctx:set_source_rgba(ARDOUR.LuaAPI.color_to_rgba(fg))

  ctx:rectangle(wh * 0.345, wh * 0.25, wh * 0.49, wh * 0.54)
  ctx:fill()

  ctx:set_source_rgba(1, 1, 1, 1)
  ctx:rectangle(wh * 0.470, wh * 0.18, wh * 0.23, wh * 0.07)
  ctx:fill()
end end

function factory() return function()

  -- For debugging...
  -- Set to true for various prints:
  local debug = true
  local function debug_print(...)
    if debug then print(...) end
  end

   -- Toggle this to enable/disable pauses between processing "steps", and during pasting of compound regions:
  local debug_pause = true

  -- Establish a function to pause the script and show a popup:
  function debug_pause_popup(step) -- Feed it some "step" string to insert some text about the current step that just completed.
    local popup = LuaDialog.Dialog("Interruption Popup...", {
      { type = "label", title = "This processing step has now completed:" },
      { type = "heading", title = tostring(step) }
    })

    local result = popup:run()
    if not result then
      return true -- User hit Close (-will stop the script).
    else
      return false -- User hit OK (-will continue).
    end
  end

  -- Establish the location to the computer's temp. directory:
  local function get_temp_dir()
    return os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
  end

  -- Establish the path for our "TSV1" file (-our main 'clipboard' file, i.e. AudioClipboard.tsv):
  local tsv1_path = ARDOUR.LuaAPI.build_filename(get_temp_dir(), "AudioClipboard.tsv")

  -- Function to apply TSV1 entries/changes to disk:
  local function flush_tsv1(lines)
    local f = io.open(tsv1_path, "w")
    if not f then
      debug_print("flush_tsv1: Failed to open TSV 1 for writing!")
      return
    end

    -- Construct a header for TSV1 (-just for better readability when/if someone views it)...
    -- I've included a brief description of each field:
    local tsv1_header = table.concat({
      "origin_session", -- 1; Name of the 'full' session path being copied from.
      "origin_snapshot", -- 2; Name of the exact snapshot being copied from.
      "used_channel_count", -- 3; The number of audio channels in the copied region. (Either: 1 or 2)
      "used_channel_type", -- 4; The type/kind of channel(s) used in the copied region. (Either: 0=Left or Mono, 1=Right, 2=Stereo)
      "original_source_location", -- 5; A simple label for the underlying source's location relative to the snapshot/session...
                                  -- (Either: IAF=In audiofiles/ (of this or any project); TREE=In this project's file-tree, but NIAF; NIAF=Not in audiofiles/)
      "original_source_type", -- 6; The type of source used. (Either: Mono, Stereo, DualMono, or Undetermined (-initially))
      "original_io_code", -- 7; A number used for asserting which specific "Import Option" shall be utilized given the source's location and/or type. (Either: IO1, IO2, or IO3)
      "original_source_path", -- 8; The 'full', relevant path to the source of the copied region.
      "final_source_location", -- 9; Initially the same as original_source_location; This can be altered later by the user when redirecting what source to use for pre-pasting/pasting.
      "final_source_type", -- 10; Initially the same as original_source_type; same^.
      "final_io_code", -- 11; Initially the same as original_io_code; same^.
      "final_source_path", -- 12; Initially the same as original_source_path; same^.
      "start_spl", -- 13; The starting sample 'position' relative to the whole source file.
      "position_spl", -- 14; The sample position for when the audio actually starts on the timeline.
      "length_spl", -- 15; How long the audio region is in samples.
      "gain_and_polarity", -- 16; User-set gain value and polarity of the audio region. (0=-infdB, 1=0dB; polarity is 'inverted' if it's any negative value)
      "envelope", -- 17; A series of time+value data points that define the original envelop "curve" used. (Either: actual data-points, Undetermined, or DefaultEnvelope)
      "envelope_state", -- 18; Whether the envelope was activated or not. (Either: EnvelopeActive or EnvelopeInactive)
      "fade_in_spl", -- 19; The sample length of the fade-in; initially "Undetermined" for "Child" regions.
      "fade_out_spl", -- 20; The sample length of the fade-out; same^.
      "fade_in_shape", -- 21; The specific shape of the fade-in; same^. (Either: FadeLinear, FadeConstantPower, FadeSymmetric, FadeSlow, or FadeFast)
      "fade_out_shape", -- 22; The specific shape of the fade-out; same^. (Same^)
      "fade_in_type", -- 23; The specific "type" of the fade-in; same^. (Either: Normal, Legacy, or Undetermined)
      "fade_out_type", -- 24; The specific "type" of the fade-in; same^. (Same^)
      "fade_in_state", -- 25; Whether or not the fade-in is active; same^. (Either: FadeInActive or FadeInInactive)
      "fade_out_state", -- 26; Whether or not the fade-out is active; same^.  (Either: FadeOutActive or FadeOutInactive)
      "mute_state", -- 27; Whether or not the region was muted. (Either: Muted or Unmuted)
      "opaque_state", -- 28; The opaque state of the region. (Either: Opaque or Transparent)
      "lock_state", -- 29; Whether or not the region was positionally locked. (Either: Locked or Unlocked)
      "sync_position", -- 30; The *absolute* sample position of the sync point of the region.
      "fade_before_fx", -- 31; Whether or not "Fade before Fx" was on or off. (Either: AfterFX or BeforeFX)
      "original_name", -- 32; The original, full name of the region.
      "original_id", -- 33; The original ID of the region (which is only used if copying and pasting within the same snapshot (mostly for testing)).
      "is_compound_parent", -- 34; Whether or not the region is a combined/compound (and thus "Parent") one. (Either: Parent or NotParent)
      "parent_id", -- 35; The region ID of the compound parent, if relevant. (Either: an actual ID, or Irrelevant)
      "original_parent_name", -- 36; Name of the parent region minus any final dot (.) and characters past the dot (-that were added by Ardour, and impede accurate XML info gathering)...
                              -- Labeled as Irrelevant for non-parent regions.
      "is_compound_child", -- 37; Whether or not the region is a "child" of a parent/compound region. (Either: Child or NotChild)
                           -- If a region is not a child (i.e. NotChild), then the 8 remaining fields will be labeled as Irrelevant:)
      "childs_parents_id", -- 38; The ID of the child's PARENT, used for accurately keeping-track-of which children belong to which parents.
      "child_chron_order", -- 39; The purely-chronological order in which children appear inside the parent; merely informative (-at this point).
      "xml_child_id", -- 40; The ID of the ACTUAL child that is unseen but within the ACTUAL, ORIGINAL parent; Initially "Undetermined" for "Child" regions.
      "xml_pre_child_id", -- 41; The ID of the original, PRE-CHILD region BEFORE Combine was used on it.
      "xml_pre_child_layering_index", -- 42; A whole number (from 0 onward) that defines proper layering/populating/recreating order.
      "siblings_total", -- 43; The total number of children/siblings in a sibling group (-that make-up a single parent).
      "sibling_number", -- 44; A unique, whole number (starting from 1) assigned to each child/sibling, derived from xml_pre_child_layering_index, that defines recreation order.
      "compound_layer" -- 45; The "layer" of the compound region, if applicable. (Either: Layer0 (top-most layer), Layer1 (1st set of children), Layer2 (2nd set of children), etc...)
    }, "\t")

    -- Write header and gap:
    f:write(tsv1_header .. "\n\n")

    -- Write each entry followed by a gap:
    for _, line in ipairs(lines) do
      f:write(line .. "\n\n")
    end

    f:close()
  end

  -- Function to 'normalize' a given path:
  local function normalize_path(path)
    return path:gsub("\\", "/"):gsub("/+", "/"):gsub("^%./", ""):gsub("/$", "")
  end

  local local_session = normalize_path(Session:path()) -- Full session path for WITHIN TSV2 entries (-field #1); used for matching and such.
  local local_snapshot = Session:snap_name() -- Current snapshot name (also used in TSV2 entries).

  -- Just for inserting the project name into the TSV2 filename...
  -- Believe it or not, but by NOT removing the spaces I was getting WAY more crashing... :/ (?)
  local local_snapshot_name = Session:snap_name():gsub("[%c%p%s]", "_")

  -- DualMono Detection Function (Updated)...
  -- Used in the Copy Logic, playlist scanning, the 'Wizard', and 'manselect'...
  -- Also, I'm adding the following 'tag' to DualMono-related areas that might need careful attention if DualMono detection logic, etc., needs adjustment:
  -- DualMono Logic Tag
  local function detect_dualmono_pair(path)
    -- Extract the path, filename, extension...
    local folder = path:match("(.*/)[^/]+$") or ""
    local filename = path:match("([^/]+)$") or path
    local ext = filename:match("(%.[^%.]+)$") or ".wav"
    local stem = filename:sub(1, #filename - #ext)

    -- Extract/determine the "suffix" (e.g. -L, %L, %L-2%L, etc.; -an arbitrarily-long string of those):
    local suffix = ""
    local i = #stem
    local mode = nil -- "L" or "R"

    while i > 0 do
      local matched = false

      -- Match %L or %R:
      local chunk = stem:sub(i - 1, i)
      if chunk == "%L" or chunk == "%R" then
        local lr = chunk:sub(2, 2)
        if not mode then mode = lr end
        if lr == mode then
          suffix = chunk .. suffix
          i = i - 2
          matched = true
        end

      -- Match -L or -R:
      elseif stem:sub(i - 1, i) == "-L" or stem:sub(i - 1, i) == "-R" then
        local lr = stem:sub(i, i)
        if not mode then mode = lr end
        if lr == mode then
          suffix = stem:sub(i - 1, i) .. suffix
          i = i - 2
          matched = true
        end

      -- Match -digits:
      elseif stem:sub(i - 1, i - 1) == "-" and stem:sub(i, i):match("%d") then
        local j = i
        while j > 0 and stem:sub(j, j):match("%d") do
          j = j - 1
        end
        if stem:sub(j, j) == "-" then
          suffix = stem:sub(j, i) .. suffix
          i = j - 1
          matched = true
        end
      end

      if not matched then break end
    end

    if suffix == "" or not mode then
      return false, nil, nil, nil
    end

    -- Flip only the suffix:
    local flipped_suffix = suffix
      :gsub("%%L", "%%TMP"):gsub("%%R", "%%L"):gsub("%%TMP", "%%R")
      :gsub("%-L", "-TMP"):gsub("%-R", "-L"):gsub("-TMP", "-R")

    -- Establish terms for various parts/combinations of file-names/paths:  
    local base = stem:sub(1, #stem - #suffix)
    local flipped_stem = base .. flipped_suffix
    local flipped_filename = flipped_stem .. ext
    local flipped_path = folder .. flipped_filename

    -- Check if 'flipped' counterpart exists:
    local f = io.open(flipped_path, "rb")
    if f then
      f:close()
      local lr_type = (mode == "L") and "left" or "right"
      -- Return 1: Is DM?, 2: Is left or right?, 3: Path to "flipped" (i.e. L-R-swapped) counterpart, 4: 'Base name' (e.g. name excl. %L/-L/-n/etc.) plus the extension.
      return true, lr_type, flipped_path, base .. ext
    end

    return false, nil, nil, nil
  end

  -- Updated function to infer fade lengths AND shapes directly from the XML...
  -- By carefully analyzing various .ardour files, I arrived at those numbers (of 0.0's, 0.9's, etc.) associated with the various fade shapes:
  local function analyze_fade_events(events, label)

    -- Note that fades from older versions of Ardour (like A2) that were migrated into A8+ used DIFFERENT shapes, and thus different numbers/etc...
    -- But, ones that cannot readily/easily be recreated unless a catalog of purely original data points were to be saved into TSV1...
    -- I'm not going to do that, so the next best option is to simply use the *closest shape* Ardour now provides (one of the five available).

    local is_legacy = false
    local is_fade_in = (label == "FadeIn")

    if not events then
      debug_print("No events block found for:", label)
      return 64, "Undetermined", "Undetermined"
    end

    local positions = {}
    local values = {}
    for time_str, val_str in events:gmatch("a(%d+)%s+([%d%.eE+-]+)") do
      table.insert(positions, tonumber(time_str))
      table.insert(values, tonumber(val_str))
    end

    -- Fade length calculation (in samples)
    local last_pos = positions[#positions]
    local sr = Session:nominal_sample_rate()
    local units_per_sample = 282240000 / sr
    local fade_length = last_pos and math.floor(last_pos / units_per_sample + 0.5) or 64 -- Fallback to the minimum standard of 64 samples if something went wrong...

    -- Fade shape determination:
    local shape = "Undetermined" -- Initial placeholder.
    local count = #values

    if count == 2 then -- Easiest to spot; FadeLinear ALWAYS has just two data points.
      shape = "FadeLinear"

    -- This range is where LEGACY FADE CORRECTIONS ARE NEEDED! O___o ...
    -- And I'm being generous here; the actual number of data points I observed for 'legacy fades' was from 6 to 8:
    elseif count >= 5 and count <= 9 then

      -- Mark for later use:
      is_legacy = true

      local nines = 0
      for _, val in ipairs(values) do
        if val and tostring(val):sub(1, 3) == "0.9" then -- Check for instances of exactly "0.9".
          nines = nines + 1 -- Add any if present in any latter values.
        end
      end

      if nines >= 1 then -- At least one instance of exactly "0.9" (-there should actually be x2 here)...
        -- LEGACY FADE CORRECTION: "Fast" OR "Fastest" (fade-IN) becomes --> "ConstantPower" (*closest match*)...
        -- OR: "Slowest" OR "Slow" (fade-OUT) becomes --> "ConstantPower" (*closest match*):
        shape = "FadeConstantPower"
      elseif nines == 0 then -- No instances of "0.9"...
        -- LEGACY FADE CORRECTION: "Slowest" OR "Slow" (fade-IN) becomes --> "Fast" (*closest match*)...
        -- OR: "Fast" OR "Fastest" (fade-OUT) becomes --> "Fast" (*closest match*):
        shape = "FadeFast"
      else
        shape = "Undetermined"
      end

    elseif count == 10 then -- FadeSymmetric has exactly 10.
      shape = "FadeSymmetric"
    elseif count >= 30 then -- Even though FadeSlow and FadeFast had 32 each, and FadeConstantPower had 33, I decided to lump them ALL together for additional logic...
      local zeros = 0
      for _, val in ipairs(values) do
        if val and tostring(val):sub(1, 3) == "0.0" then
          zeros = zeros + 1
        end
      end
      -- The consistent instances of exactly "0.0" (i.e. not incl. ones like "1.0000000116860974e-07") were actually 20, 15, and 1-2, respectively...
      -- but I'm making the counting a bit more flexible to be safe(r):
      if zeros >= 19 then 
        shape = "FadeFast"
      elseif zeros >= 14 then 
        shape = "FadeSlow"
      elseif zeros <= 5 then -- Again, being generous here; I've seen examples with x2 0.0's.
        shape = "FadeConstantPower" -- Ardour's 'standard', default fade shape, by the way.
      else
        shape = "Undetermined" -- If it ends as "Undetermined", then a unique popup will appear during pasting to let the user select the shape...
      end
    else
      shape = "Undetermined" -- Same as ^...
    end

    debug_print(string.format("Fade %s - %d pts -> %s, LastPos: %s, Legacy: %s", label, count, shape, tostring(last_pos), tostring(is_legacy)))
    return fade_length, shape, is_legacy
  end

  --------------------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------- OPENING WINDOW ---------------------------------------------------------
  --------------------------------------------------------------------------------------------------------------------------------

  -- Immediately stop the transport if it is rolling/playing...
  -- This (presumably) reduces potential crashing/issues if trying to use do_import/do_embed during Pre-Paste, or trying to uncombine regions during copying, etc.:
  if Session:transport_rolling() then
    Session:request_stop(true, false, ARDOUR.TransportRequestSource.TRS_UI)
  end
  
  ::show_main_dialog::

  local main_dialog = LuaDialog.Dialog("AudioClipboard (v1.0)", {
    {
      type = "dropdown",
      key = "main_action",
      title = "What would you like to do?",
      values = {
        ["Step 1 - Copy Regions"] = "copy",
        ["Step 2 - Pre-Paste Files"] = "prepaste",
        ["Step 3 - Paste Regions"] = "paste",
        ["View Instructions, Etc."] = "help"
      },
      default = "copy"
    },
    { type = "label", title = " " }, -- Spacer
    { type = "heading", title = "⚠ WARNING:" },
    { type = "heading", title = "Please TURN OFF \"Move relevant automation when" },
    { type = "heading", title = "audio regions are moved\" (under Preferences -> Editor)" },
    { type = "heading", title = "if you are pasting onto a track with ANY automation!" },
    { type = "heading", title = "(-Choose \"View Instructions, Etc.\" for more info.)" },
    { type = "label", title = " " } -- Spacer

  })
  
  local main_result = main_dialog:run()
  if not main_result then return end
  local action = tostring(main_result["main_action"] or ""):gsub("^%s*(.-)%s*$", "%1")

  -- Save the session; helps prevent crashing when pre-pasting onto a fresh track (where the session wasn't yet saved), etc.:
  Session:save_state("", false, false, false, false, false)

  -----------------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------- HELP DIALOG ---------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------

  if action == "help" then
    local part1 =
      "                    How to use AudioClipboard:\n\n" ..
      "         Step 1: Select mono and/or stereo audio regions that you would like to copy, and then use the \"Copy Regions\" " ..
      " function.\n\n         Step 2: In the project snapshot you would like to paste into, select an audio track and use the " ..
      "\"Pre-Paste Files\" function.  This step ensures that all of the necessary audio source files are embedded or imported " ..
      "into the current session as required. (-TIP: Always use \"View File List\" before pre-pasting to ensure proper file usage, " ..
      "and consider using the \"Manually Select Files to Use\" feature to redirect pasted regions to different/better sources!)\n\n" ..
      "         Step 3: Select the audio track you wish to paste onto and use the \"Paste Regions\" function.  --> Click OK and watch " ..
      "your regions appear! ~Done!\n\n\n" ..
      "                              ⚠ WARNING:\n\n" ..
      "         Due to the ways in which sources and regions are handled via this script, if \"Move relevant automation when " ..
      "audio regions are moved\" (under Preferences > Editor) is turned ON during a Pre-Paste or Paste function into an area with " ..
      "ANY automation on the track (e.g. fader, pan, plugin, etc.), repeated sliding and ultimately destruction of original automation " ..
      "curves will occur. Therefore, if you MUST leave that setting on but want to avoid this destruction, then simply paste your " ..
      "regions onto an empty, throwaway track, and then just move them on from there."
  
    LuaDialog.Message("Instructions (1 of 2)", part1, LuaDialog.MessageType.Info, LuaDialog.ButtonType.Close):run()
  
    local part2 =
      "                             How This Script Works:\n\n" ..
      "         In short, AudioClipboard works by externally logging all relevant and available data for the copied regions into " ..
      "a file called \"AudioClipboard.tsv\" in a temporary folder offered by your computer.  Then, during Pre-Paste, it scans for " ..
      "already-present, usable sources, creates a local Region ID Cache (-another, more permanent .tsv file), and ultimately imports" ..
      "/embeds the remaining sources needed for successful pasting.  And finally, during Pasting, it then clones new audio regions " ..
      "into existence via IDs provided by the local cache, and utilizes the data in AudioClipboard.tsv to recreate the copied regions, " ..
      "with original region size, trim, position, gain, envelope, fade lengths, and other states all being preserved in the process.\n\n" ..
      "                                    Other Notes:\n\n" ..
      "         This script can be used in conjunction with Ardour's built-in track-template-creator (-right-click on an audio mixer " ..
      "strip's name, then use \"Save As Template...\") to achieve full track and region duplication from one session/snapshot into another.\n\n" ..
      "         Also, if you experience any bugs with this script, please submit an \"Issue\" on the GitHub page for AudioClipboard, " ..
      "and/or post about it/them on the Ardour forum (discourse.ardour.org) and link @GhostsonAcid in your comment, and I will try to " ..
      "address it. ~Thank you and enjoy!"

    LuaDialog.Message("Etc. (2 of 2)", part2, LuaDialog.MessageType.Info, LuaDialog.ButtonType.Close):run()
    goto show_main_dialog
  end

  -----------------------------------------------------------------------------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------- COPY LOGIC ----------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------

  if action == "copy" then

    local sel = Editor:get_selection()
    local region_list = sel and sel.regions and sel.regions:regionlist()

    --------------------------------------------------------------------------------------
    ------------------------- Copy STEP 0: Initial Checks/Guards -------------------------
    --------------------------------------------------------------------------------------

    debug_print("-------------- Copy STEP 0: Initial Checks/Guards --------------")

    -- Check if anything is selected:
    if not region_list or region_list:empty() then
      LuaDialog.Message(
        "Nothing to Copy!",
        "No audio regions are selected!\n\nPlease select one or more mono/stereo regions before copying.",
        LuaDialog.MessageType.Warning,
        LuaDialog.ButtonType.Close
      ):run()
      return
    end

    -- Create some 'validation caches':
    local sel_ids = {}      -- Quick lookup table to mark region IDs that are part of the current selection (for validation, etc.).
    local region_info = {}  -- Stores both the audio region (ar) and generic region (r) for each ID.
    local region_order = {} -- For establishing the proper order used.

    -- Begin some checks on the regions to see if they're valid (i.e. able to be copied):
    for r in region_list:iter() do
      local ar = r:to_audioregion()
      -- Alert the user if a selected region is not pure audio, thus midi:
      if not ar or ar:isnil() then
        LuaDialog.Message(
          "Invalid Selection!",
          "Unfortunately MIDI notes and regions cannot be\ncopied by AudioClipboard at this time.\n\nPlease select only mono and/or stereo audio regions.",
          LuaDialog.MessageType.Warning,
          LuaDialog.ButtonType.Close
        ):run()
        return
      end
      -- Alert the user if a selected region has more than 2 audio channels:
      if ar:n_channels() > 2 then
        LuaDialog.Message(
          "Invalid Selection!",
          "Unfortunately regions with more than 2 channels\ncannot be copied by AudioClipboard at this time.\n\nPlease select only mono and/or stereo audio regions.",
          LuaDialog.MessageType.Warning,
          LuaDialog.ButtonType.Close
        ):run()
        return
      end

      local id = ar:to_stateful():id():to_s()
      -- Ensures no duplicate IDs are placed into region_order:
      if not sel_ids[id] then
        sel_ids[id] = true
        region_info[id] = { ar = ar, r = r }
        table.insert(region_order, id) -- Add the region ID to our 'main' table of (selected/copied) regions.
      end      
    end

    -- Map region IDs to tracks:
    local region_to_track = {}
    for t in Session:get_tracks():iter() do
      local tr = t:to_track()
      if tr and not tr:isnil() then
        local pl = tr:playlist()
        if pl and not pl:isnil() then
          for r in pl:region_list():iter() do
            local id = r:to_stateful():id():to_s()
            if sel_ids[id] then
              region_to_track[id] = tr
            end
          end
        end
      end
    end

    -- Ensure all regions are from one track...
    -- If we pass this, regions are validated and safe to copy:
    local first_track = nil
    for _, id in ipairs(region_order) do
      local track = region_to_track[id]
      if not first_track then
        first_track = track
      elseif track ~= first_track then
        LuaDialog.Message(
          "Invalid Selection!",
          "You have selected regions from multiple tracks.\n\nPlease select only regions from a single track for copying.",
          LuaDialog.MessageType.Warning,
          LuaDialog.ButtonType.Close
        ):run()
        return
      end
    end

    if debug_pause and debug_pause_popup("Copy STEP 0: Initial Checks/Guards") then return end

    -----------------------------------------------------------------------------------------------------------------------------------------------
    ------------------------- Copy STEP 1: Manifest/Erase TSV1, Sort the Selected Regions, and Check for Compound Regions -------------------------
    -----------------------------------------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Copy STEP 1: Manifest/Erase TSV1, Sort the Selected Regions, and Check for Compound Regions --------------")

    -- Manifest/erase TSV1 (AudioClipboard.tsv)...
    -- Good to do this AFTER initial checks just in case someone used Copy Regions (in Session B) when they meant to use Paste Regions:
    local file = io.open(tsv1_path, "w")
    if not file then
      LuaDialog.Message("File Error", "Failed to open clipboard file for writing:\n" .. tsv1_path, LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run()
      return
    end

    local tsv1_entries = {} -- Store TSV1 lines before writing.
    local copied = 0 -- A counter used for the final popup.

    -- Sort the regions (ultimately into TSV 1) via LAYER positioning (& Time)!
    -- This is crucial, as without it certain opaque regions might (during pasting) find themselves on-top of other regions they were once below, etc... (-> Not good!)
    table.sort(region_order, function(a, b)
      local ra, rb = region_info[a], region_info[b]
      local la, lb = ra.ar:layer(), rb.ar:layer()
      if la ~= lb then
        return la < lb  -- layer first
      else
        return ra.r:position():samples() < rb.r:position():samples()  -- Fallback to time.
      end
    end)

    -- A final check for any compound/combined regions among the selection:
    local compound_region_names = {}
    for _, id in ipairs(region_order) do
      local r = region_info[id].r
      if r:is_compound() then
        local name = region_info[id].ar:name() or "Unnamed"
        table.insert(compound_region_names, name) -- Insert name of compound/parent region, if found.
      end
    end

    -- If any compound regions are present, alert the user that duplicating/etc. will occur, and about current Ardour inadequacies:
    if #compound_region_names > 0 then
      local msg_lines = {
        { type = "heading",   title = "⚠" },
        { type = "heading",   title = "You are attempting to copy the following combined region(s):" },
        { type = "label",   title = " " } -- Spacer
      }
      
      -- Insert one label line for each compound region name:
      for _, name in ipairs(compound_region_names) do
        msg_lines[#msg_lines + 1] = { type = "label", title = name }
      end
      
      -- Append static footer text:
      local footer_lines = {
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "In order to copy these regions, this script must temporarily" },
        { type = "label", title = "uncombine duplicates of them to view their contents." },
        { type = "label", title = " " }, -- Spacer
        { type = "heading", title = "⚠ Important Notes:" }, -- Spacer
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "As of Ardour 8.12, manually uncombining audio regions suffers" },
        { type = "label", title = "several bugs/inadequacies.  It is therefore highly recommended" },
        { type = "label", title = "to allow this script to handle them, as much care here has gone" },
        { type = "label", title = "into salvaging original data (such as layering, envelope, etc.)" },
        { type = "label", title = "and reproducing accurate compound regions during pasting." },
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "However, despite my best efforts, copying combined regions" },
        { type = "label", title = "might still fail to recreate your original combined regions." },
        { type = "label", title = "So, after pasting, please double-check that any recreated" },
        { type = "label", title = "combined regions look and sound identical to the originals." },
        { type = "label", title = "If there are any inconsistencies, then it is suggested to" },
        { type = "label", title = "simply export and re-import whichever ones you wish to copy." },
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "Overall, it is recommended to avoid using combined regions" },
        { type = "label", title = "until the developers of Ardour address their severe flaws." },
        { type = "label", title = " " } -- Final Spacer
      }
      
      -- Combine the two sections:
      for _, line in ipairs(footer_lines) do
        msg_lines[#msg_lines + 1] = line
      end
      
      -- Show the dialog:
      local confirm = LuaDialog.Dialog("Combined Regions Present!", msg_lines)
      if not confirm:run() then
        return
      end
      
    end

    if debug_pause and debug_pause_popup("Copy STEP 1: Manifest/Erase TSV1, Sort the Selected Regions, and Check for Compound Regions") then return end

    ----------------------------------------------------------------------------------------------------------------------------
    ------------------------- Copy STEP 2: Establish Our Main, TSV1 Entry Base-Info-Gathering Function -------------------------
    ----------------------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Copy STEP 2: Establish Our Main, TSV1 Entry Base-Info-Gathering Function --------------")

    -- And now one, massive function for determining fields 1-33 (-the 'base'-) for each TSV1 entry:
    local function get_tsv1_entry_base_info(r, ar, is_child_region) -- Added this is_child_region flag for moar interrigent handling...

      -- Some notes on child regions:
      -- Through careful testing (using Ardour 8.12 on macOS Mojave), it was concluded by me that ONLY the following information
      -- canNOT reliably come from child regions when Uncombine is used on its parent/compound region (-either original parent, or duplicate):
      -- envelope automation data, fade-in/out lengths, fade-in/out state (-because parent regions 'steal' initial and final fading), and lock state (-which is
      -- accurately kept for ORIGINAL children, but NOT duplicate/copied parents that are split-up; it doesn't matter though, as I am making all children unlocked
      -- anyway so when you uncombine a MOVED parent, no children suddenly 'snap back' to some old/original position)...
      -- And also original child/pre-child LAYERING! -That is NOT preserved AT ALL, but luckily I managed to find adequate "layering-index" data in the XML to use.

      local is_compound = r:is_compound() or false -- Establish if the input region is compound or not.

      -- 1. origin_session
      local origin_session = normalize_path(Session:path())

      -- 2. origin_snapshot
      local origin_snapshot = Session:snap_name()

      -- 3. used_channel_count (1 or 2)
      local used_channel_count = ar:n_channels()

      -- Get path and prep some values:
      local fs = nil
      local path = ""
      local src = ar:source(0)
      if src and not src:isnil() then
        local fs = src:to_filesource()
        if fs and not fs:isnil() then
          path = fs:path()
        end
      end

      -- 4. used_channel_type (-Either 0, 1, or 2, for Mono/Left/Undetermined, Right, or Stereo, respectively.)
      local used_channel_type = 0  -- Default to Mono/Left/Undetermined

      if is_compound then
        -- COMPOUND REGIONS:
        if used_channel_count == 2 then
          used_channel_type = 2  -- Stereo (UCT 2)
        else
          used_channel_type = 0  -- In this case representing "Unknown" or "Irrelevant"...
        end

      else
        -- "NORMAL" REGIONS:
        if used_channel_count == 2 then
          used_channel_type = 2
        elseif used_channel_count == 1 then
          local src = ar:source(0)
          if src and not src:isnil() then
            local fs = src:to_filesource()
            if fs and not fs:isnil() then
              local ch_index = fs:channel()
              used_channel_type = (ch_index == 1) and 1 or 0
            end
          end
        end
      end

      -- Predeclare for both branches to fill in
      local original_source_location
      local original_source_type
      local original_io_code
      local original_source_path
      local final_source_location
      local final_source_type
      local final_io_code
      local final_source_path

      -- The rest of fields 5-12 can be bypassed as basically irrelevant if the region is a compound/parent one...
      -- We will soon prompt the user for allowing this script to duplicate and then uncombine combined regions, and then 'scalp' data from their child regions:
      if not is_compound then

        -- 5. original_source_location (IAF, TREE, or NIAF)
        -- Normalize source path
        local norm_path = normalize_path(path)

        if norm_path:match("/interchange/[^/]+/audiofiles/") then -- Looks for just a single directory between the two.
          original_source_location = "IAF" -- = In audiofiles/ (of this or any project); -Will bring these into AF of the session you Pre-Paste/Paste into.

        elseif norm_path:find(normalize_path(Session:path()), 1, true) then
          original_source_location = "TREE" -- = In this project's file-tree, but NIAF; -Great for catching files in exports/ and handling them more like IAF files later on.

        else
          original_source_location = "NIAF" -- = Not in any audiofiles/ folder.
        end

        -- 6. original_source_type
        original_source_type = "Undetermined" -- The immediate default for each.

        if used_channel_count == 2 then
          original_source_type = "Stereo"
        elseif used_channel_count == 1 then
          if used_channel_type == 1 then
            original_source_type = "Stereo"
          end
        end

        -- 7. original_io_code
        original_io_code = 0  -- Doesn't exist; just a default value; if you see this in a TSV file, then something went wrong.

        -- DualMono Logic Tag
        local is_dm, lr_type, other_path, _ = detect_dualmono_pair(path)

        if original_source_location == "IAF" then

          if is_dm then
            original_source_type = "DualMono"
            original_io_code = 1  -- Region coming from a %L+%R (DualMono) pair.
          else
            original_io_code = 2  -- A whole mono or stereo file (or a rare and lonely %L or %R file, etc.)...
          end

        elseif original_source_location == "TREE" then
          original_io_code = 2  -- Treated the same as IAF mono or stereo (-will find out later during IO2...)

        elseif original_source_location == "NIAF" then
          original_io_code = 3  -- Treated the same as IAF mono or stereo (-will find out later during IO3...)
        end

        -- 8. original_source_path
        -- If the region is RIGHT of a DualMono pair, use the LEFT-side path instead. (-This is the standard throughout this script.)
        -- DualMono Logic Tag
        original_source_path = (is_dm and lr_type == "right") and other_path or path -- other_path gives us the left-side path of a detected, DualMono pair.
        if is_dm and lr_type == "right" then
          used_channel_type = 1 -- Also if right, flip uct to a 'more-proper' 1, -also standard here in this script.
        end

        -- 9-12. set finals as originals (-The user can change these later if manually selecting different files to use.)
        final_source_location = original_source_location
        final_source_type = original_source_type
        final_io_code = original_io_code
        final_source_path = original_source_path -- fsp = osp

      else
        original_source_location = "Irrelevant"
        original_source_type = "Irrelevant"
        original_io_code = 0 -- Signifies "Irrelevant"...
        original_source_path = "Irrelevant"
        final_source_location = "Irrelevant"
        final_source_type = "Irrelevant"
        final_io_code = 0 -- Signifies "Irrelevant"...
        final_source_path = "Irrelevant"
      end

      -- 13-15. start / position / length (in samples)
      local start_spl    = r:start():samples()
      local position_spl = r:position():samples()
      local length_spl   = r:length():samples()

      -- 16. gain_and_polarity
      -- NOTE: Negative values indicate that Polarity has been 'flipped'(!):
      local gain_and_polarity = ar:scale_amplitude() or 1.0 -- 1.0 is a fallback...

      -- 17. envelope
      local envelope = "Undetermined"
      if not is_child_region then -- Child regions need separate handling later...
        local env = ar:envelope()
        if env and not env:isnil() then
          local parts = {}
          for ev in env:events():iter() do
            table.insert(parts, string.format("%d:%.6f", ev.when:samples(), ev.value))
          end
          envelope = table.concat(parts, ",")
        end
      end

      -- 18. envelope_state (Active or Inactive)
      local envelope_state = ar:envelope_active() and "EnvelopeActive" or "EnvelopeInactive"

      -- 19-26. Fade information, with length and shape taken directly from the current XML; -kinda hacky but works...
      -- Obviously this could be completely eliminated if get_fade_in_length, get_fade_in_shape, etc., were added the Lua bindings! o___o
      -- Establish a function first:
      local function get_region_fades_from_xml(region_id)

        --Establish path to the current XML:
        local session_path = Session:path()
        local snapshot_name = Session:snap_name()
        local xml_path = ARDOUR.LuaAPI.build_filename(session_path, snapshot_name .. ".ardour")

        local f = io.open(xml_path, "r")
        -- Fallback to what Ardour's minimum fade-in/fade-out length is (64 samples), and the rest get "Undetermined":
        if not f then return 64, 64, "Undetermined", "Undetermined", "Undetermined", "Undetermined" end
        local xml = f:read("*all")
        f:close()

        local playlists = xml:match("<Playlists>(.-)</Playlists>")
        if not playlists then return 64, 64, "Undetermined", "Undetermined", "Undetermined", "Undetermined" end

        -- Safe scoped ID match
        local region_block = nil
        for block in playlists:gmatch("<Region.->.-</Region>") do
          local found_id = block:match('id="([^"]+)"')
          if found_id == region_id then
            region_block = block
            break
          end
        end

        if not region_block then return 64, 64, "Undetermined", "Undetermined", "Undetermined", "Undetermined" end -- Again, all are fallback...

        -- Establish the fade-in and fade-out 'sub-blocks' in the XML we want to scrap data from:
        local fadein_block = region_block:match("<FadeIn>.-<events>(.-)</events>")
        local fadeout_block = region_block:match("<FadeOut>.-<events>(.-)</events>")

        -- Call our analyzation function we established earlier:
        local fade_in_spl, fade_in_shape, fade_in_is_legacy = analyze_fade_events(fadein_block, "FadeIn")
        local fade_out_spl, fade_out_shape, fade_out_is_legacy = analyze_fade_events(fadeout_block, "FadeOut")

        return fade_in_spl, fade_out_spl, fade_in_shape, fade_out_shape, fade_in_is_legacy, fade_out_is_legacy
      end

      -- Use the region's ID and the previous get_region_fades_from_xml function:
      local region_id = ar:to_stateful():id():to_s()
      local fade_in_spl, fade_out_spl, fade_in_shape, fade_out_shape, fade_in_type, fade_out_type, fade_in_state, fade_out_state

      if not is_child_region then -- Child regions need separate handling later...
        fade_in_spl, fade_out_spl, fade_in_shape, fade_out_shape, fade_in_is_legacy, fade_out_is_legacy = get_region_fades_from_xml(region_id)

        fade_in_type = (fade_in_is_legacy == "Undetermined") and "Undetermined" or (fade_in_is_legacy and "Legacy" or "Normal")
        fade_out_type = (fade_out_is_legacy == "Undetermined") and "Undetermined" or (fade_out_is_legacy and "Legacy" or "Normal")

        fade_in_state = ar:fade_in_active() and "FadeInActive" or "FadeInInactive"
        fade_out_state = ar:fade_out_active() and "FadeOutActive" or "FadeOutInactive"
      else
        -- For children; to be determined later:
        fade_in_spl, fade_out_spl, fade_in_shape, fade_out_shape, fade_in_type, fade_out_type = 64, 64, "Undetermined", "Undetermined", "Undetermined", "Undetermined"
        
        fade_in_state = "Undetermined"
        fade_out_state = "Undetermined"
      end

      -- 27. mute_state (Muted or Unmuted)
      local mute_state = ar:muted() and "Muted" or "Unmuted"

      -- 28. opaque_state (Opaque or Transparent)
      local opaque_state = ar:opaque() and "Opaque" or "Transparent"

      -- 29. lock_state (Locked or Unlocked)
      local lock_state
      if not is_child_region then
        lock_state = ar:locked() and "Locked" or "Unlocked"
      else
        lock_state = "Unlocked" -- It's inconvenient to lock children, because if you move the parent and then uncombine, the child manifests at its original, locked position...
      end

      -- 30. sync_position (-in samples.)
      local sync_position = ar:sync_position():samples()

      -- 31. fade_before_fx (BeforeFX or AfterFX)
      local fade_before_fx = ar:fade_before_fx() and "BeforeFX" or "AfterFX"

      -- 32. original_name
      local original_name = ar:name() or "Unnamed"

      -- 33. original_id
      local original_id = r:to_stateful():id():to_s()

      -- Returns all 33 'base info' fields separately:
      return
        origin_session, -- 1
        origin_snapshot, -- 2
        used_channel_count, -- 3
        used_channel_type, -- 4
        original_source_location, -- 5
        original_source_type, -- 6
        original_io_code, -- 7
        original_source_path, -- 8
        final_source_location, -- 9
        final_source_type, -- 10
        final_io_code, -- 11
        final_source_path, -- 12
        start_spl, -- 13
        position_spl, -- 14
        length_spl, -- 15
        gain_and_polarity, -- 16
        envelope, -- 17
        envelope_state, -- 18
        fade_in_spl, -- 19
        fade_out_spl, -- 20
        fade_in_shape, -- 21
        fade_out_shape, -- 22
        fade_in_type, -- 23
        fade_out_type, -- 24
        fade_in_state, -- 25
        fade_out_state, -- 26
        mute_state, -- 27
        opaque_state, -- 28
        lock_state, -- 29
        sync_position, -- 30
        fade_before_fx, -- 31
        original_name, -- 32
        original_id -- 33
    end

    if debug_pause and debug_pause_popup("Copy STEP 2: Establish Our Main, TSV1 Entry Base-Info-Gathering Function") then return end

    --------------------------------------------------------------------------------------------
    ------------------------- Copy STEP 3: Initiate the Main Copy Loop -------------------------
    --------------------------------------------------------------------------------------------

    debug_print("-------------- Copy STEP 3: Initiate the Main Copy Loop --------------")

    local parent_regions_layer_0 = {}  -- Ordered list of first/top-level compound region IDs, if present.

    for _, id in ipairs(region_order) do

      local r = region_info[id].r
      local ar = region_info[id].ar
    
      -- Collect data about the first 33 fields via our massive function (-which we'll reuse later if compound regions are present):
      local origin_session, -- 1
      origin_snapshot, -- 2
      used_channel_count, -- 3
      used_channel_type, -- 4
      original_source_location, -- 5
      original_source_type, -- 6
      original_io_code, -- 7
      original_source_path, -- 8
      final_source_location, -- 9
      final_source_type, -- 10
      final_io_code, -- 11
      final_source_path, -- 12
      start_spl, -- 13
      position_spl, -- 14
      length_spl, -- 15
      gain_and_polarity, -- 16
      envelope, -- 17
      envelope_state, -- 18
      fade_in_spl, -- 19
      fade_out_spl, -- 20
      fade_in_shape, -- 21
      fade_out_shape, -- 22
      fade_in_type, -- 23
      fade_out_type, -- 24
      fade_in_state, -- 25
      fade_out_state, -- 26
      mute_state, -- 27
      opaque_state, -- 28
      lock_state, -- 29
      sync_position, -- 30
      fade_before_fx, -- 31
      original_name, -- 32
      original_id = -- 33
        get_tsv1_entry_base_info(r, ar, false) -- False means that we're not processing any child regions here.

      local is_compound = r:is_compound() or false
    
      -- Fields 34-45, Compound-Region-Related Data:
      local is_compound_parent = is_compound and "Parent" or "NotParent"
      local parent_id          = is_compound and r:to_stateful():id():to_s() or "Irrelevant"

      -- Strip everything after the final dot (including the dot itself), ONLY if it is_compound:
      local original_parent_name = is_compound and original_name:match("(.+)%.[^%.]+$") or "Irrelevant" -- NEW.

      local is_compound_child            = "NotChild" -- Obviously no "children" can exist at this 'topmost' compound_layer...
      local childs_parents_id            = "Irrelevant" -- Thus most of these, too, are irrelevant...
      local child_chron_order            = "Irrelevant"
      local xml_child_id                 = "Irrelevant"
      local xml_pre_child_id             = "Irrelevant"
      local xml_pre_child_layering_index = "Irrelevant"
      local siblings_total               = "Irrelevant"
      local sibling_number               = "Irrelevant"
      local compound_layer               = is_compound and "Layer0" or "Irrelevant" -- Just set all non-compound regions to "Irrelevant"...

      -- Insert parent_id into our parent_regions_layer_0 table, for duplicating and uncombining soon:
      if is_compound then
        table.insert(parent_regions_layer_0, parent_id)
      end

      local entry_full_info = string.format(
       -- 1  2   3   4   5   6    7    8   9   10   11   12  13  14  15   16   17  18  19  20  21  22  23  24  25  26  27  28  29  30  31  32  33
        "%s\t%s\t%d\t%d\t%s\t%s\tIO%d\t%s\t%s\t%s\tIO%d\t%s\t%d\t%d\t%d\t%.6f\t%s\t%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%s" ..
        "\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s",
        -- 34  35  36  37  38  39  40  41  42  43  44  45
        origin_session, -- 1
        origin_snapshot, -- 2
        used_channel_count, -- 3
        used_channel_type, -- 4
        original_source_location, -- 5
        original_source_type, -- 6
        original_io_code, -- 7
        original_source_path, -- 8
        final_source_location, -- 9
        final_source_type, -- 10
        final_io_code, -- 11
        final_source_path, -- 12
        start_spl, -- 13
        position_spl, -- 14
        length_spl, -- 15
        gain_and_polarity, -- 16
        envelope, -- 17
        envelope_state, -- 18
        fade_in_spl, -- 19
        fade_out_spl, -- 20
        fade_in_shape, -- 21
        fade_out_shape, -- 22
        fade_in_type, -- 23
        fade_out_type, -- 24
        fade_in_state, -- 25
        fade_out_state, -- 26
        mute_state, -- 27
        opaque_state, -- 28
        lock_state, -- 29
        sync_position, -- 30
        fade_before_fx, -- 31
        original_name, -- 32
        original_id, -- 33
        is_compound_parent, -- 34
        parent_id, -- 35
        original_parent_name, -- 36
        is_compound_child, -- 37
        childs_parents_id, -- 38
        child_chron_order, -- 39
        xml_child_id, -- 40
        xml_pre_child_id, -- 41
        xml_pre_child_layering_index, -- 42
        siblings_total, -- 43
        sibling_number, -- 44
        compound_layer -- 45
      )
      -- Insert all 45 fields, once per (top-layer) region, directly into tsv1_entries:
      table.insert(tsv1_entries, entry_full_info)

      copied = copied + 1
      ::skip::
    end

    if debug_pause and debug_pause_popup("Copy STEP 3: Initiate the Main Copy Loop") then return end

    ------------------------------------------------------------------------------------------------------------------------------------------
    ------------------------- Copy STEP 4: Prepare for Additional Looping (for Any Compound/Combined/Parent-Regions) -------------------------
    ------------------------------------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Copy STEP 4: Prepare for Additional Looping (for Any Compound/Combined/Parent-Regions) --------------")

    local need_children_of_layer = {}
    local tsv1_entries_by_layer = {}
    local compound_processing = false
    local failed_compound_parent = {} -- For storing the name of a failed compound region if we encounter one.
    local siblings_manifested = true -- Assume uncombine worked on each parent to manifest a sibling/child group. -If this DOESN'T occur
                                     -- for ANY combined/compound/parent region, we will then flip this to false and redirect the code accordingly...

    -- Only populate "layer 0" if there *are* compound parents:
    if #parent_regions_layer_0 > 0 then
      need_children_of_layer[1] = parent_regions_layer_0
      -- Also, set this to true to manifest a different popup later + region cleanup:
      compound_processing = true
    end

    -- Instead of deconstructing the ORIGINAL parents and then later using Session:abort_reversible_command() (which I can't get to work),
    -- we will now attempt to DUPLICATE the originals, and then deconstruct the duplicates.
    -- And for this we then need to keep track of the new regions (new parents and children) for clean-up/deletion afterwards:
    local region_ids_to_remove = {}

    -- A function to snapshot a region table from the current(?) playlist:
    local function get_region_table(pl)
      local tbl = {} -- Automatically cleans-up old values...
      for r in pl:region_list():iter() do
        local id = r:to_stateful():id():to_s()
        tbl[id] = r
      end
      return tbl
    end

    -- A massive function to process any compound/combined/parennt-regions and their 'children'... @_____@
    -- Needless to say, this was a bitch to figure-out, haha:
    function process_child_layer(child_layer, input_parents)
      -- Initialize layer tables:
      need_children_of_layer[child_layer + 1] = {}
      tsv1_entries_by_layer[child_layer] = {}

      local track = region_to_track[region_order[1]]
      local playlist = track:playlist()

      for _, current_parent_id in ipairs(input_parents) do

        -- Find current parent region:
        local parent_region = nil
        for r in playlist:region_list():iter() do
          local id = r:to_stateful():id():to_s()
          if id == current_parent_id then
            parent_region = r -- Define the current parent_region (for use all throughout this function)...
            break
          end
        end

        -- Snapshot before creating the parent duplicate:
        local region_table_before = get_region_table(playlist)

        -- Duplicate the parent region at its same position...
        -- This is safer, and replaces a version where we deconstructed the ORIGINAL parent (-yet couldn't revert back to the original state):
        playlist:duplicate(parent_region, parent_region:position(), parent_region:length(), 1.0)

        -- Snapshot after duplication:
        local region_table_after = get_region_table(playlist)

        -- Identify the newly duplicated parent:
        local parent_duplicate = nil
        for id, r in pairs(region_table_after) do
          if not region_table_before[id] then
            parent_duplicate = r
            table.insert(region_ids_to_remove, id)  -- Save this duplicate (ID) for cleanup later on.
            break
          end
        end

        if not parent_duplicate then
          error("Failed to duplicate parent region " .. current_parent_id)
        end

        -- Expand the duplicate to its fullest possible extent but WITHOUT moving it (-although the latter is not crucial, I suppose):
        parent_duplicate:trim_front(Temporal.timepos_t(0))
        parent_duplicate:trim_end(Temporal.timepos_t(1000000000000)) -- Attempt to add 1 Trillion samples... o_____o

        -- Snapshot before uncombing to get the 'children':
        local region_table_before = get_region_table(playlist)

        -- Uncombine it:
        playlist:uncombine(parent_duplicate)

        -- Snapshot after:
        local region_table_after = get_region_table(playlist)

        -- Although this probably adds considerable lag to the copy process here, you MUST save the snapshot's .ardour (XML) file
        -- after ANY uncombine operation upon a DUPLICATE of the parent in order to get the actual fade length/shape/etc. info!
        -- This will NOT be necessary, of course, when and if the Ardour devs add get_fade_in_length/get_fade_out_length (and hopefully more) to the bindings:
        Session:save_state("", false, false, false, false, false)
        debug_print("--> XML Saved!")

        -- Capture the children:
        local current_siblings = {}
        for id, r in pairs(region_table_after) do
          if not region_table_before[id] then
            table.insert(current_siblings, r)
            table.insert(region_ids_to_remove, id)  -- Also save any child (via ID) for later cleanup.
          end
        end

        -- Now detect any sibling manifestation failure...
        -- This was necessary after discovering that SOME parents can be uncombined to NO child regions whatsoever...
        -- This is 100% a part of the host of bugs in Ardour with respect to compound regions/handling:
        if #current_siblings == 0 then
          siblings_manifested = false -- Mark as a failure to manifest the child/sibling group.
          debug_print("No children were manifested after uncombine! Broken compound region: " .. parent_region:name())
          table.insert(failed_compound_parent, parent_region:name()) -- Save the original parent region's name for the later popup.
          return -- Abort this process_child_layer operation.
        end

        -- The initial sort here of current_siblings is now by TIME ONLY...
        -- This is to bring it into full (presumed consistent) alignment with how child regions (in the "<Playlist"... block of the parent) are listed in the XML...
        -- For the XML examples I observed, the organization of children respected timing only...
        -- But, I am still unsure as to what happens if two or more children share the SAME starting 'location' (-and will ignore that issue for the time being): --------------
        table.sort(current_siblings, function(a, b)
          return a:position():samples() < b:position():samples()
        end)

        -- Next, save this ordering solely for child_chron_order in TSV 1, which is more or less purely informative:
        local chron_index_by_id = {}
        for i, r in ipairs(current_siblings) do
          local id = r:to_stateful():id():to_s()
          chron_index_by_id[id] = tostring(i)
        end

        -- Etablish the total number of siblings/children that manifested from the uncombined parent:
        local current_siblings_total = #current_siblings
        debug_print("Number of current siblings:", #current_siblings)

        -- A function just for children (obviously), to get data on the ORIGINAL (pre-)child regions so we can ACCURATELY recreate parents...
        -- I pray that the Ardour devs will one day fix child region recreation (via Uncombine), because developing all this was a fucking nightmare @_____@
        -- and it STILL fails on occasion:
        local function get_accurate_siblings_data(original_parent_name, current_siblings_total)
          local session_path = Session:path()
          local xml = io.open(ARDOUR.LuaAPI.build_filename(session_path, Session:snap_name() .. ".ardour")):read("*all")
          local regions = xml:match("<Regions>(.-)</Regions>")
          if not regions then
            debug_print("NO REGIONS LIST FOUND IN XML!")
            return "Undetermined", 64, 64, "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined"
          else
            debug_print("Regions List Found in XML!")
          end

          -- A function to find the parent playlist section...
          -- We do this ONCE per sibling group so as to not repeat all the XML scanning per child:
          local function extract_parent_playlist_block(xml_path, original_parent_name)
            local f = io.open(xml_path, "r")
            if not f then
              debug_print("Could not open XML file at: " .. xml_path)
              return nil
            end
          
            local inside_region = false
            local inside_nested = false
            local inside_source = false
            local inside_playlist = false
          
            local parent_playlist = {}
            local region_matches = false
          
            debug_print("Looking for parent Region with name:", original_parent_name)
          
            local playlist_captured = false

            for line in f:lines() do
              if playlist_captured then break end -- Stops the scanning process if the right child-region playlist has been found and saved.
              -- I carefully examined many XML (.ardour) examples to arrive at the following flow:
              if line:find('<Region name="' .. original_parent_name, 1, true) and not inside_playlist then
                inside_region = true
                region_matches = true
                debug_print("Entered matching <Region> block.")
              elseif inside_region and line:match("</Region>") and not inside_playlist then
                debug_print("Exited <Region> block.")
                inside_region = false
                region_matches = false
                parent_playlist = {}
              elseif inside_region and not inside_playlist then
                if line:match("<NestedSource>") then
                  inside_nested = true
                  debug_print("Entered <NestedSource>")
                end
                if line:match("</NestedSource>") then
                  inside_nested = false
                  debug_print("Exited <NestedSource>")
                end
                if inside_nested and line:match("<Source") then ------------------------------------------------------------------------------------------
                  inside_source = true
                  debug_print("Entered <Source>")
                end
                if inside_source and line:match("</Source>") then
                  inside_source = false
                  debug_print("Exited <Source>")
                end
                if inside_source and line:match("<Playlist") then
                  inside_playlist = true
                  debug_print("Capturing <Playlist>")
                  table.insert(parent_playlist, line)
                end
              elseif inside_playlist then
                table.insert(parent_playlist, line)
                if line:match("</Playlist>") then
                  debug_print("Completed <Playlist> block.")
                  table.concat(parent_playlist, "\n")
                  playlist_captured = true
                end
              end
            end
          
            f:close()
            return table.concat(parent_playlist, "\n")
          end

          -- Establish a path to the XML currently in use:
          local session_path = Session:path()
          local snapshot_name = Session:snap_name()
          local xml_path = ARDOUR.LuaAPI.build_filename(session_path, snapshot_name .. ".ardour")
          
          -- Call the function we just established:
          local parent_block = extract_parent_playlist_block(xml_path, original_parent_name)
          
          if not parent_block then
            debug_print("Could not extract parent Playlist block for: " .. original_parent_name)
            return "Undetermined", 64, 64, "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined"
          else
            debug_print("Successfully extracted parent Playlist block!")
            -- Unmute this debug for a verbose print of what the found, supposed "parent_block" actually is:
            --debug_print(parent_block)
          end

          -- Establish separate child blocks from the parent's XML playlist:
          local child_blocks = {}
          local i = 0
          for block in parent_block:gmatch("<Region.-</Region>") do
            i = i + 1
            if i > current_siblings_total then break end
            table.insert(child_blocks, block)
            debug_print("Creating child block...")
          end

          if #child_blocks == 0 then
            return "Undetermined", 64, 64, "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined", "Undetermined"
          else
            debug_print("Successfully extracted child blocks!")
          end

          -- Initiate data-collection for children in the sibling group:
          local results = {}
          for _, child_block in ipairs(child_blocks) do

            -- Establish the 'sub-blocks' for fade-in and fade-out we want to scrap data from:
            local fadein_block = child_block:match("<FadeIn>.-<events>(.-)</events>")
            local fadeout_block = child_block:match("<FadeOut>.-<events>(.-)</events>")

            -- Get fade-in/out lengths and shapes...
            -- Call our analyzation function we established earlier:
            local fade_in_spl, fade_in_shape, fade_in_is_legacy = analyze_fade_events(fadein_block, "FadeIn")
            local fade_out_spl, fade_out_shape, fade_out_is_legacy = analyze_fade_events(fadeout_block, "FadeOut")

            -- Get fade_in/out_type (Normal or Legacy)
            local fade_in_type = fade_in_is_legacy and "Legacy" or "Normal"
            local fade_out_type = fade_out_is_legacy and "Legacy" or "Normal"

            -- Get fade states:
            local fade_in_state = "Undetermined"
            if child_block:find('fade%-in%-active=') then
              fade_in_state = child_block:match('fade%-in%-active="1"') and "FadeInActive" or "FadeInInactive"
            end
            
            local fade_out_state = "Undetermined"
            if child_block:find('fade%-out%-active=') then
              fade_out_state = child_block:match('fade%-out%-active="1"') and "FadeOutActive" or "FadeOutInactive"
            end

            -- Envelope (if not default):
            local envelope = "DefaultEnvelope"
            local envelope_block = child_block:match("<Envelope.-</Envelope>") -- Acquire only the envelope block/area...

            -- "<Envelope default="yes"/>" means that NO unique envelope is present, and therefore none needs to be applied:
            if envelope_block and not envelope_block:match('<Envelope%s+default="yes"%s*/>') then
              local ev = envelope_block:match("<events>(.-)</events>")
              if ev then
                -- Some fancy math to adjust the envelope values as shown in the xml to something useful (i.e. --> samples): --------------
                local sr = Session:nominal_sample_rate()
                local units_per_sample = 282240000 / sr
                local points = {}
                for line in ev:gmatch("[^\r\n]+") do
                  local a_val, amp_val = line:match("a(%d+)%s+([%d%.eE+-]+)")
                  if a_val and amp_val then
                    local sample_pos = math.floor(tonumber(a_val) / units_per_sample + 0.5)
                    table.insert(points, string.format("%d:%.6f", sample_pos, tonumber(amp_val)))
                  end
                end
                envelope = table.concat(points, ",")
              end
            end

            -- Get the ID from the original child:
            local xml_child_id = child_block:match('id="(%d+)"') or "Undetermined"

            -- Get the original, PRE-child region ID via the "CompoundAssociations" portion of the XML...
            -- We need this ID to find the matching block that will then give us valid data on PROPER, ORIGINAL region layering (-before Combine was used):
            local xml_pre_child_id = xml:match('<CompoundAssociation[^>]-copy="' .. xml_child_id .. '".-original="(%d+)"') or "Undetermined"

            -- Now get valid, usable layering info from the original, pre-child region:
            local xml_pre_child_layering_index = "Undetermined"
            if xml_pre_child_id ~= "Undetermined" then
              debug_print("xml_pre_child_id is NOT Undetermined. -Proceeding to finding xml_pre_child_layering_index...")
              for region_block in regions:gmatch("<Region.->") do
                local is_nested = region_block:match("<NestedSource>") -- We need to now AVOID NestedSource ones, because those will NOT be the original (pre-)children!
                local matches_id = region_block:match('id="' .. xml_pre_child_id .. '"')
                if not is_nested and matches_id then
                  debug_print("Attempting to find matching layering_index in appropriate block...")
                  xml_pre_child_layering_index = region_block:match('layering%-index="(%d+)"') or "Undetermined"
                  break
                end
              end
            end

            debug_print("xml_child_id: " .. tostring(xml_child_id))
            debug_print("xml_pre_child_id: " .. tostring(xml_pre_child_id))
            debug_print("xml_pre_child_layering_index: " .. tostring(xml_pre_child_layering_index))

            -- Insert all collected values:
            table.insert(results, {
              envelope, -- 17 (in TSV1)
              fade_in_spl, -- 19 (in TSV1)
              fade_out_spl, -- 20 (in TSV1)
              fade_in_shape, -- 21 (in TSV1)
              fade_out_shape, -- 22 (in TSV1)
              fade_in_type, -- 23 (in TSV1)
              fade_out_type, -- 24 (in TSV1)
              fade_in_state, -- 25 (in TSV1)
              fade_out_state, -- 26 (in TSV1)
              xml_child_id, -- 39 (in TSV1); The ID of the current, ORIGINAL (i.e. non-dupliate) child...
                            -- Note that this ID cannot(?) be obtained via the bindings because we're not splitting-up the ORIGINAL parent, rather a DUPLICATE parent.
              xml_pre_child_id, -- 40 (in TSV1)
              xml_pre_child_layering_index -- 41 (in TSV1)
            })
          end
          -- Return all 12 fields, once per child in the sibling group:
          return results
        end

        -- Prepare to accurately assess this child's parent's original_parent_name:
        local parent_ar = parent_region and parent_region:to_audioregion()
        local parent_name = parent_ar and parent_ar:name() or "Undetermined"

        local original_parent_name = parent_name:match("(.+)%.[^%.]+$") or "Undetermined" -- NEW.

        -- Now immediately call the previous function...
        -- Collect all 12 field results per child region in the current sibling group:
        local accurate_siblings_data = get_accurate_siblings_data(original_parent_name, current_siblings_total)

        -- Sort current_siblings by acquired (and hopefully universally accurate) LAYER INDEX now...
        -- This is absolutely crucial for reproducing proper, original pre-child region layering so that parents are formed accurately during pasting later on:
        local combined = {}
        for i, r in ipairs(current_siblings) do
          table.insert(combined, { region = r, data = accurate_siblings_data[i] })
        end
        
        -- Sort the new, temp. table based on field 12 here (xml_pre_child_layering_index):
        table.sort(combined, function(a, b)
          local la = tonumber(a.data[12]) or 9999 -- Default to some high number if something went wrong. --------------
          local lb = tonumber(b.data[12]) or 9999
          return la < lb
        end)
        
        current_siblings = {}
        accurate_siblings_data = {}
        for _, pair in ipairs(combined) do
          table.insert(current_siblings, pair.region)
          table.insert(accurate_siblings_data, pair.data)
        end

        -- Finally, process each child in a loop:
        for idx, r in ipairs(current_siblings) do
          local ar = r:to_audioregion()

          -- First, collect data about the first 33 fields via our massive function:
          local origin_session, -- 1
          origin_snapshot, -- 2
          used_channel_count, -- 3
          used_channel_type, -- 4
          original_source_location, -- 5
          original_source_type, -- 6
          original_io_code, -- 7
          original_source_path, -- 8
          final_source_location, -- 9
          final_source_type, -- 10
          final_io_code, -- 11
          final_source_path, -- 12
          start_spl, -- 13
          position_spl, -- 14
          length_spl, -- 15
          gain_and_polarity, -- 16
          envelope, -- 17
          envelope_state, -- 18
          fade_in_spl, -- 19
          fade_out_spl, -- 20
          fade_in_shape, -- 21
          fade_out_shape, -- 22
          fade_in_type, -- 23
          fade_out_type, -- 24
          fade_in_state, -- 25
          fade_out_state, -- 26
          mute_state, -- 27
          opaque_state, -- 28
          lock_state, -- 29
          sync_position, -- 30
          fade_before_fx, -- 31
          original_name, -- 32
          original_id = -- 33
            get_tsv1_entry_base_info(r, ar, true) -- True means that we are processing child regions here.

          local is_compound = r:is_compound() or false -- Check/establish if any of these children are ALSO parents (i.e. compound/combined).

          -- Fields 34-45, Compound-Region-Related Data:
          local is_compound_parent = is_compound and "Parent" or "NotParent"
          local parent_id          = is_compound and r:to_stateful():id():to_s() or "Irrelevant"

          local is_compound_child = "Child"
          local childs_parents_id = current_parent_id

          local id = r:to_stateful():id():to_s()
          local child_chron_order = chron_index_by_id[id] or "Undetermined" --------------

          local xml_child_id                 = "Undetermined"
          local xml_pre_child_id             = "Undetermined"
          local xml_pre_child_layering_index = "Undetermined"

          -- Now that all of the following (8) fields have been declared, use idx to access the nth child's --------------
          -- accurate/original data from the single XML-scan we did (per sibling group) earlier:
          local child_data = accurate_siblings_data[idx] or {}

          -- Overwrite them with accurate child data, if available:
          envelope                     = child_data[1] or "Undetermined" -- Again, inserting "Undetermined" if something went wrong.
          fade_in_spl                  = child_data[2] or 64 -- Again again, 64-sample fallback (-Ardour minimum).
          fade_out_spl                 = child_data[3] or 64
          fade_in_shape                = child_data[4] or "Undetermined"
          fade_out_shape               = child_data[5] or "Undetermined"
          fade_in_type                 = child_data[6] or "Undetermined"
          fade_out_type                = child_data[7] or "Undetermined"
          fade_in_state                = child_data[8] or "Undetermined"
          fade_out_state               = child_data[9] or "Undetermined"
          xml_child_id                 = child_data[10] or "Undetermined"
          xml_pre_child_id             = child_data[11] or "Undetermined"
          xml_pre_child_layering_index = child_data[12] or "Undetermined"

          local siblings_total = tostring(current_siblings_total)
          local sibling_number = tostring(idx) -- Since current_siblings is now sorted by xml_pre_child_layering_index info., we can simply set each sibling's number like so.
          local compound_layer = string.format("Layer%d", child_layer)

          -- Insert any parent_id into need_children_of_layer[child_layer + 1] (i.e. the next child layer to process):
          if is_compound then
            table.insert(need_children_of_layer[child_layer + 1], parent_id)
          end

          local entry_full_info = string.format(
           -- 1  2   3   4   5   6    7    8   9   10   11   12  13  14  15   16   17  18  19  20  21  22  23  24  25  26  27  28  29  30  31  32  33
             "%s\t%s\t%d\t%d\t%s\t%s\tIO%d\t%s\t%s\t%s\tIO%d\t%s\t%d\t%d\t%d\t%.6f\t%s\t%s\t%d\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\t%s\t%s" ..
             "\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s",
             -- 34  35  36  37  38  39  40  41  42  43  44  45
             origin_session, -- 1
             origin_snapshot, -- 2
             used_channel_count, -- 3
             used_channel_type, -- 4
             original_source_location, -- 5
             original_source_type, -- 6
             original_io_code, -- 7
             original_source_path, -- 8
             final_source_location, -- 9
             final_source_type, -- 10
             final_io_code, -- 11
             final_source_path, -- 12
             start_spl, -- 13
             position_spl, -- 14
             length_spl, -- 15
             gain_and_polarity, -- 16
             envelope, -- 17
             envelope_state, -- 18
             fade_in_spl, -- 19
             fade_out_spl, -- 20
             fade_in_shape, -- 21
             fade_out_shape, -- 22
             fade_in_type, -- 23
             fade_out_type, -- 24
             fade_in_state, -- 25
             fade_out_state, -- 26
             mute_state, -- 27
             opaque_state, -- 28
             lock_state, -- 29
             sync_position, -- 30
             fade_before_fx, -- 31
             original_name, -- 32
             original_id, -- 33
             is_compound_parent, -- 34
             parent_id, -- 35
             original_parent_name, -- 36
             is_compound_child, -- 37
             childs_parents_id, -- 38
             child_chron_order, -- 39
             xml_child_id, -- 40
             xml_pre_child_id, -- 41
             xml_pre_child_layering_index, -- 42
             siblings_total, -- 43
             sibling_number, -- 44
             compound_layer -- 45
          )
          -- Insert all 45 fields, once per child, into tsv1_entries_by_layer[child_layer]:
          table.insert(tsv1_entries_by_layer[child_layer], entry_full_info)

        end
      end
    end

    if debug_pause and debug_pause_popup("Copy STEP 4: Prepare for Additional Looping (for Any Compound/Combined/Parent-Regions") then return end

    --------------------------------------------------------------------------------------------------------------------------------------------
    ------------------------- Copy STEP 5: Initiate Additional Copy Loop(s) (for Any Compound/Combined/Parent-Regions) -------------------------
    --------------------------------------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Copy STEP 5: Initiate Additional Copy Loop(s) (for Any Compound/Combined/Parent-Regions) --------------")

    -- Layer0 is the 'topmost'/'surface' compound_layer...
    -- Layer1 is the next layer in...
    -- Layer2 is the next layer in, etc...
    -- Thus, we start this next loop by manifesting/exposing all Layer1 children:
    local child_layer = 1

    -- Start this off by making sure need_children_of_layer[child_layer] isn't simply nil...
    -- Also, I capped-it-off at an arbitrary 50 child-layers deep, assuming no one will EVER reach that, haha @____@:
    while need_children_of_layer[child_layer] and #need_children_of_layer[child_layer] > 0 and child_layer < 50 do

      -- Process and store siblings in tsv1_entries_by_layer[child_layer]:
      process_child_layer(child_layer, need_children_of_layer[child_layer])

       -- Stop this "while" loop if a compound parent failed to manifest children (in process_child_layer):
      if not siblings_manifested then
        debug_print("Aborting compound region processing due to failed sibling manifestation.")
        break -- Break out of the loop.
      end

      local children_by_parent_id = {}

      -- Sort and inject children directly before each relevant parent...
      -- The specific ordering we set here (ultimately into TSV1) is what makes pasting a relative breeze later on:
      for _, line in ipairs(tsv1_entries_by_layer[child_layer]) do
        local fields = {}
        for field in string.gmatch(line, "[^\t]+") do
          table.insert(fields, field)
        end
        local parent_id = fields[38] -- Field 38 = childs_parents_id
        local layering_index = tonumber(fields[42]) -- Field 42 = xml_pre_child_layering_index
        if not children_by_parent_id[parent_id] then
          children_by_parent_id[parent_id] = {}
        end
        table.insert(children_by_parent_id[parent_id], { line = line, order = layering_index })
      end

      -- Inject sorted children before parents:
      local new_tsv = {}
      local inserted = {}

      for i, line in ipairs(tsv1_entries) do
        local fields = {}
        for field in string.gmatch(line, "[^\t]+") do
          table.insert(fields, field)
        end
        local parent_id = fields[35] -- Field 35 = parent_id

        if children_by_parent_id[parent_id] and not inserted[parent_id] then
          table.sort(children_by_parent_id[parent_id], function(a, b)
            return a.order < b.order
          end)
          for _, entry in ipairs(children_by_parent_id[parent_id]) do
            table.insert(new_tsv, entry.line)
          end
          inserted[parent_id] = true
        end

        table.insert(new_tsv, line)
      end

      tsv1_entries = new_tsv

      child_layer = child_layer + 1
    end

    if debug_pause and debug_pause_popup("Copy STEP 5: Initiate Additional Copy Loop(s) (for Any Compound/Combined/Parent-Regions)") then return end

    -------------------------------------------------------------------------------------------------------------
    ------------------------- Copy STEP 6: Finalize TSV1 and Alert the User Accordingly -------------------------
    -------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Copy STEP 6: Finalize TSV1 and Alert the User Accordingly --------------")

    -- Write final entries to AudioClipboard.tsv:
    if siblings_manifested then
      flush_tsv1(tsv1_entries)
    end

    -- Initiate a final Copy Logic dialog...
    -- The 'normal' message to show if no compound regions were ever copied:
    if not compound_processing then
      LuaDialog.Message(
        "Copying Complete!",
        string.format(
          "%d audio region(s) copied successfully!\n\nYou may now Pre-Paste their sources into other sessions.\n\n" ..
          "For those curious, the region data has been saved to:\n%s",
          copied, tsv1_path
        ),
        LuaDialog.MessageType.Info,
        LuaDialog.ButtonType.Close
      ):run()

    -- For successful compound-region handling:
    elseif compound_processing and siblings_manifested then
      -- Delay the actual region cleanup loop until AFTER a dialog popup...
      -- *Might* help prevent crashing (as it definitely did at the end of Pre-Paste (-after the IOs)):
      LuaDialog.Message(
        "Copying Complete!",
        string.format(
          "%d audio region(s) copied successfully!\n\nYou may now Pre-Paste their sources into other sessions.\n\n" ..
          "For those curious, the region data has been saved to:\n%s\n\n" ..
          "This script will now cleanup any\ntemporary regions from the timeline.",
          copied, tsv1_path -- Still displays just the original number of copied regions (i.e. NOT including any child regions)...
        ),
        LuaDialog.MessageType.Info,
        LuaDialog.ButtonType.Close
      ):run()

    -- Display a separate popup for situations where compound-region processing failed spectacularly: -___-
    elseif compound_processing and not siblings_manifested then

      local message = string.format(
        "This script is unable to copy the following combined region:\n\n" ..
        "%s\n\n\n" ..
        "This is not the fault of this script.\n\n" ..
        "As of v8.12, Ardour unfortunately suffers from many\n" ..
        "bugs when it comes to handling combined audio regions.\n" ..
        "If you encounter this issue, please submit a bug-report\n" ..
        "to tracker.ardour.org to alert the developers that this\n" ..
        "combined region cannot be uncombined properly.\n\n" ..
        "To get this specific failed region into another project,\n" ..
        "it is recommended to simply export and then re-import it.\n\n" ..
        "~My apologies for this annoying inconvenience!",
        failed_compound_parent and failed_compound_parent[1] or "(-Unable to retrieve the combined region's name.)"
      )
    
      LuaDialog.Message(
        "Compound Region Failure!",
        message,
        LuaDialog.MessageType.Warning,
        LuaDialog.ButtonType.Close
      ):run()

    end

    -- NOW remove all temporary children (and any duplicate parents if something went wrong and one/some remain(?)):
    if compound_processing then
      for _, id in ipairs(region_ids_to_remove) do
        local region = ARDOUR.RegionFactory.region_by_id(PBD.ID(id))
        if region and not region:isnil() then
          local pl = region:playlist()
          if pl and not pl:isnil() then
            pl:remove_region(region)
            debug_print("Removed region with ID:", id)
          end
        else
          debug_print("Could not resolve region ID:", id)
        end
      end
    end

    if debug_pause and debug_pause_popup("Copy STEP 6: Finalize TSV1 and Alert the User Accordingly") then return end
    
  end -- Ends "if action == "copy" then".

  -----------------------------------------------------------------------------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------
  ---------------------------------------------------- PRE-PASTE LOGIC --------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------

  if action == "prepaste" then

    -- Define the paths used for our TSV files:
    local tsv1_path = ARDOUR.LuaAPI.build_filename(get_temp_dir(), "AudioClipboard.tsv")
    local tsv2_path = ARDOUR.LuaAPI.build_filename(Session:path(), "interchange", Session:name(), "AudioClipboard_IDs_(" .. local_snapshot_name .. ").tsv")

    local reran_wizard = false -- Used later if 'Source Finder Wizard' is re-ran and no additional, potential matches were identified.
    local skip_wizard = false

    -----------------------------------------------------------------------------------------------------
    ------------------------- Pre-Paste STEP 0: Erase TSV 2 Entries With No IDs -------------------------
    -----------------------------------------------------------------------------------------------------

    debug_print("-------------- Pre-Paste STEP 0: Erase TSV 2 Entries With No IDs --------------")

    -- If 'mis-copying' something, running Pre-Paste and then canceling, this ensures that any unwanted entries don't keep reappearing during later Pre-Pasting.
    -- This must be kept BEFORE ::restart_prepaste:: so any manual source changes (during "manselect" or Wizard) aren't immediately erased from TSV 2.

    -- A function to split a given TSV line into a table of fields, preserving empty/trailing values:
    local function split_tsv(line)
      local fields = {}
      local i = 1
      for field in line:gmatch("([^\t]*)\t?") do
        fields[i] = field
        i = i + 1
      end
      return fields
    end

    do -- Wrap this with a "do" to keep the following terms scoped here:
      local kept_lines = {} -- A table for lines to keep (-lines/entries where at least one ID is present).
      local header = nil
      local removed = 0
      local kept = 0

      local tsv2_file_read = io.open(tsv2_path, "r")
      if tsv2_file_read then
        for line in tsv2_file_read:lines() do
          if line:match("^local_session") then
            header = line -- Save the header.
          elseif line:match("^%s*$") then
            -- Skip blank lines...
          else
            local fields = split_tsv(line)
            local ids = fields[14] or ""
            if ids ~= "" and ids ~= "Undetermined" then
              -- Keep the entry:
              table.insert(kept_lines, line)
              -- Mark as kept for a debug tally:
              kept = kept + 1
            else
              removed = removed + 1
            end
          end
        end
        tsv2_file_read:close()
      end

      -- Rewrite file with cleaned lines:
      if header and (#kept_lines > 0 or removed > 0) then
        local tsv2_file_write = io.open(tsv2_path, "w")
        if tsv2_file_write then
          tsv2_file_write:write(header .. "\n\n") -- Write the header + a gap.
          for _, line in ipairs(kept_lines) do
            tsv2_file_write:write(line .. "\n\n") -- Write each kept line + a gap.
          end
          tsv2_file_write:close()
          debug_print(string.format("Pre-cleaned TSV2 on disk. Removed: %d | Kept: %d", removed, kept))
        else
          debug_print("Could not open TSV2 for disk cleanup write.")
        end
      end
    end

    if debug_pause and debug_pause_popup("Pre-Paste STEP 0: Erase TSV 2 Entries With No IDs") then return end

    ------------------------------------------------------------------------------------------------------------------------------------------------
    ------------------------- Pre-Paste STEP 1: Define More Functions, Load TSVs, and Update TSV1 via TSV2 (if they exist) -------------------------
    ------------------------------------------------------------------------------------------------------------------------------------------------

    ::restart_prepaste::

    debug_print("-------------- Pre-Paste STEP 1: Define More Functions, Load TSVs, and Update TSV1 via TSV2 (if they exist) --------------")

    -- Load existing TSV2 entries (if any):
    local tsv2_entries = {}
    local tsv2_file_read = io.open(tsv2_path, "r")

    if tsv2_file_read then
      for line in tsv2_file_read:lines() do
        debug_print("RAW TSV2 LINE:", string.format("%q", line))

        if line:match("^local_session") or line:match("^%s*$") then
          -- Skip header and blank lines...
        else
          local fields = split_tsv(line)

          if #fields == 14 then
            local key = string.format("%s|%s|%s",
              fields[3],                -- used_channel_count
              fields[4],                -- used_channel_type
              normalize_path(fields[8]) -- original_source_path
            )
            tsv2_entries[key] = {
              line = fields,
              IDs = {}
            }
            local raw_ids = fields[14]
            if raw_ids ~= "Undetermined" then
              for id in raw_ids:gmatch("[^,]+") do
                table.insert(tsv2_entries[key].IDs, id)
              end
            end            
          end
        end
      end
      tsv2_file_read:close()
    end

    -- Function to apply TSV2 entries/changes to disk:
    local function flush_tsv2()
      local tsv2_file_write = io.open(tsv2_path, "w")
      if tsv2_file_write then

        -- Construct a header for TSV2 (-just for better readability when/if someone views it)...
        -- I've included a brief description of each field:
        local tsv2_header = table.concat({
          "local_session", -- 1; The path (as Ardour sees it) to the session that this TSV2 ID cache belongs to.
          "local_snapshot", -- 2; The exact snapshot that this TSV2 belongs to.
          "used_channel_count", -- 3; The number of audio channels in this entry. (Either: 1 or 2)
          "used_channel_type", -- 4; The type/kind of channel(s) used in this entry. (Either: 0=Left or Mono, 1=Right, 2=Stereo)
          "original_source_location", -- 5; A simple label for the original source's location relative to the snapshot/session...
                                      -- (Either: IAF=In audiofiles/ (of this or any project); TREE=In this project's file-tree, but NIAF; NIAF=Not in audiofiles/)
          "original_source_type", -- 6; The type of source originally used. (Either: Mono, Stereo, DualMono, or Undetermined (-initially))
          "original_io_code", -- 7; A number used for asserting which specific "Import Option" would be utilized if the original_source_path
                              -- was the final one to be used, given the source's location and/or type. (Either: IO1, IO2, or IO3)
          "original_source_path", -- 8; The 'full', relevant path to the original source that was once copied from.
          "final_source_location", -- 9; The final source's location, as defined by a *potentially-user-chosen* final_source_path (fsp)...
                                   -- (Either: IAF=In audiofiles/ (of this or any project); TREE=In this project's file-tree, but NIAF; NIAF=Not in audiofiles/).
          "final_source_type", -- 10; The final type of the source as defined by a potentially-user-chosen fsp. (Either: Mono, Stereo, DualMono, or Undetermined (-initially))
          "final_io_code", -- 11; A number used for asserting which specific "Import Option" will be (or has been) used for importing/embedding. (Either: IO1, IO2, or IO3)
          "final_source_path", -- 12; The 'full', relevant path to the final, potentially-user-chosen source.
          "local_source_path", -- 13; The actual, literal source path that the region IDs (for this snapshot) ultimately use...
                               -- Note how the fsp and lsp can be different:
                               -- E.G., a user may have selected a different (from the osp) IAF DualMono pair to be used as the fsp, but if that pair isn't already in
                               -- audiofiles/ of 'Session B', then it still would have to be imported into audiofiles/ of Session B, and thus might acquire a different
                               -- name in the process. (-In the future, it therefore might be wise to rename all "final_..." fields to "chosen_...", or something else.(?))
          "IDs" -- 14; The region IDs that 'match' all previous criteria/fields. (Either: actual IDs, or Undetermined)
        }, "\t")

        -- Write header + a gap:
        tsv2_file_write:write(tsv2_header .. "\n\n")

        -- Collect all entries into a sortable list
        local sortable = {}
        for _, entry in pairs(tsv2_entries) do
          table.insert(sortable, entry)
        end

        -- Sort alphabetically by original_source_path (line[8]), then by ucc, and then by uct...
        -- Just a nice addition to keep TSV2 more consistent as new entries are added over time:
        table.sort(sortable, function(a, b)
          local a_path = (a.line[8] or ""):lower()
          local b_path = (b.line[8] or ""):lower()
          if a_path ~= b_path then
            return a_path < b_path
          end
        
          local a_ucc = tonumber(a.line[3]) or 0
          local b_ucc = tonumber(b.line[3]) or 0
          if a_ucc ~= b_ucc then
            return a_ucc < b_ucc
          end
        
          local a_uct = tonumber(a.line[4]) or 0
          local b_uct = tonumber(b.line[4]) or 0
          return a_uct < b_uct
        end)

        -- Write sorted entries:
        for _, entry in ipairs(sortable) do
          local line = entry.line
          local id_field = (entry.IDs and #entry.IDs > 0) and table.concat(entry.IDs, ",") or "Undetermined"
          line[14] = id_field
          tsv2_file_write:write(table.concat(line, "\t") .. "\n\n")
        end

        tsv2_file_write:close()
        debug_print("TSV 2 flushed to disk (sorted).")
      else
        debug_print("Could not open TSV 2 for writing!")
      end
    end

    -- A tiny function to get the local_source_path:
    local function get_lsp(path)
      return normalize_path(path)
    end

    -- A function to ensure a trio of variant entries exist in TSV2 (i.e. 1|0|osp, 1|1|osp, 2|2|osp):
    local function ensure_variants(entry)

      local ost = entry.original_source_type or (entry.line and entry.line[6])
      local osp = entry.original_source_path or (entry.line and entry.line[8])
      local fst = entry.final_source_type or (entry.line and entry.line[10])
      local fsp = entry.final_source_path or (entry.line and entry.line[12])

      -- Look for any one existing entry that can serve as a template:
      local template_entry = nil
      for uct = 0, 2 do
        local key = string.format("%d|%d|%s", uct == 2 and 2 or 1, uct, osp) -- ucc, uct, and osp.
        local existing_variant = tsv2_entries[key]
        if existing_variant and normalize_path(existing_variant.line[12]) == fsp then
          template_entry = existing_variant
          break
        end
      end

      for uct = 0, 2 do -- Run three times, from uct = 0 (left) -> 1 (right) -> 2 (full stereo).

        local ucc = (uct == 2) and 2 or 1 -- Force correct ucc for each uct.
        local key = string.format("%d|%d|%s", ucc, uct, osp)
        local processed_variant = false -- First reset this to false per loop iteration.

        if not tsv2_entries[key] then -- Check if this entry already exists in TSV2 (based on the previous key).  If not, then...

          local base = template_entry.line
          local line = {}

          -- Clone the first 11 fields of our "base" entry to a new "line" table:
          for i = 1, 11 do line[i] = base[i] end

          -- Override other, specific fields:
          line[3] = tostring(ucc) -- used_channel_count
          line[4] = tostring(uct) -- used_channel_type
          if ost ~= "DualMono" then -- This will skip ones already labeled as "DualMono".
            line[6] = "Stereo" -- Update/ensure the ost as "Stereo".
          end
          if fst ~= "DualMono" then -- This will skip ones already labeled as "DualMono".
            line[10] = "Stereo" -- Update/ensure the fst as "Stereo".
          end
          line[12] = fsp          -- final_source_path
          line[13] = (line[9] == "NIAF") and fsp or "Undetermined" -- local_source_path; -set the same as fsp immediately if it's NIAF.
          line[14] = "Undetermined" -- IDs

          -- Store this new entry in tsv2_entries:
          tsv2_entries[key] = { line = line, IDs = {} }

          processed_variant = true -- Mark as processed.
          debug_print(string.format("ensure_variants: Created missing variant %d|%d|...", ucc, uct))
        end

        -- Update the ost and fst accordingly for any that remain in the trio:
        local entry = tsv2_entries[key]
        if not processed_variant and entry and entry.line then
          local line = entry.line
          if line[6] ~= "DualMono" then line[6] = "Stereo" end -- This will skip ones already labeled/identified as "DualMono".
          if line[10] ~= "DualMono" then line[10] = "Stereo" end -- Same.
        end

      end
    end

    -- Function to sync the variants of a trio of sources if one has its final_* fields manually changed:
    local function sync_variants(entry, wipe_ids)
      local osp = normalize_path(entry.original_source_path)
      local fsp = normalize_path(entry.final_source_path)

      for uct = 0, 2 do -- Run three times, from uct = 0 -> 1 -> 2.
        local ucc = (uct == 2) and 2 or 1
        local key = string.format("%d|%d|%s", ucc, uct, osp)
        local variant_entry = tsv2_entries[key]

        if variant_entry then
          local line = variant_entry.line

          line[9] = entry.final_source_location
          line[10] = entry.final_source_type
          line[11] = "IO" .. tostring(entry.final_io_code or "0")
          line[12] = fsp
          line[13] = (entry.final_source_location == "NIAF" and ucc == 2) and fsp or "Undetermined"
          line[14] = "Undetermined"

          if wipe_ids then
            variant_entry.IDs = {} -- Clear saved region ID(s) if requested.
          end
          debug_print("sync_variants: Synced variant:", key)
        end
      end
    end

    -- Guard: ensure TSV 1 exists and has at least a valid header
    local function ensure_tsv1_exists()
      local tsv1_file_read = io.open(tsv1_path, "r")
      if not tsv1_file_read then
        -- Create TSV 1 with only the header
        local tsv1_file_write = io.open(tsv1_path, "w")
        if tsv1_file_write then
          local header = table.concat({
            "origin_session", -- 1
            "origin_snapshot", -- 2
            "used_channel_count", -- 3
            "used_channel_type", -- 4
            "original_source_location", -- 5
            "original_source_type", -- 6
            "original_io_code", -- 7
            "original_source_path", -- 8
            "final_source_location", -- 9
            "final_source_type", -- 10
            "final_io_code", -- 11
            "final_source_path", -- 12
            "start_spl", -- 13
            "position_spl", -- 14
            "length_spl", -- 15
            "gain_and_polarity", -- 16
            "envelope", -- 17
            "envelope_state", -- 18
            "fade_in_spl", -- 19
            "fade_out_spl", -- 20
            "fade_in_shape", -- 21
            "fade_out_shape", -- 22
            "fade_in_type", -- 23
            "fade_out_type", -- 24
            "fade_in_state", -- 25
            "fade_out_state", -- 26
            "mute_state", -- 27
            "opaque_state", -- 28
            "lock_state", -- 29
            "sync_position", -- 30
            "fade_before_fx", -- 31
            "original_name", -- 32
            "original_id", -- 33
            "is_compound_parent", -- 34
            "parent_id", -- 35
            "original_parent_name", -- 36
            "is_compound_child", -- 37
            "childs_parents_id", -- 38
            "child_chron_order", -- 39
            "xml_child_id", -- 40
            "xml_pre_child_id", -- 41
            "xml_pre_child_layering_index", -- 42
            "siblings_total", -- 43
            "sibling_number", -- 44
            "compound_layer" -- 45
          }, "\t")
          tsv1_file_write:write(header .. "\n\n") -- Write header + a blank line.
          tsv1_file_write:close()
          debug_print("TSV 1 not found - created new blank clipboard file.")
        else
          LuaDialog.Message("Clipboard Error",
            "Could not create a new TSV 1 clipboard file.\nPlease check permissions or disk space.",
            LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run()
          return false
        end
      else
        tsv1_file_read:close()
      end
      return true
    end

    -- Check to see if TSV1 exists (i.e. returns true):
    if not ensure_tsv1_exists() then return end

    -- Exit early if TSV1 is effectively blank:
    local tsv1_valid_data = false
    for line in io.lines(tsv1_path) do
      if not line:match("^origin_session") and not line:match("^%s*$") then
        tsv1_valid_data = true
        break
      end
    end

    local skip_steps = false

    if not tsv1_valid_data then
      debug_print("TSV 1 is blank - skipping Pre-Paste Steps 1-5.")
      -- Mark to skip a lot of steps:
      skip_steps = true
    end

    -- Skip the rest of Steps 1-5 of Pre-Paste because what's the point, really, if our TSV1 is blank???:
    if not skip_steps then

      -- Load TSV2 file with OSP-keyed entries ONLY (-only here for Pre-Paste Step 1 syncing):
      local tsv2_by_osp = {}

      local tsv2_file_read = io.open(tsv2_path, "r")
      if tsv2_file_read then
        for line in tsv2_file_read:lines() do
          debug_print("RAW TSV2 LINE:", string.format("%q", line))

          if line:match("^local_session") or line:match("^%s*$") then
            -- Skip header or blank line...
          else
            local fields = split_tsv(line)
            if #fields == 14 then
              local osp = normalize_path(fields[8])
              if not tsv2_by_osp[osp] then
                tsv2_by_osp[osp] = {
                  line = fields,
                  IDs = {}
                }
                local raw_ids = fields[14]
                if raw_ids ~= "Undetermined" then
                  for id in raw_ids:gmatch("[^,]+") do
                    table.insert(tsv2_by_osp[osp].IDs, id)
                  end
                end
              else
                debug_print("⚠️ Duplicate original_source_path in TSV2:", osp)
              end
            else
              debug_print("⚠️ Malformed line in TSV2:", line)
            end
          end
        end
        tsv2_file_read:close()
      end

      -- Load and update TSV1 from TSV2:
      local updated = 0
      local tsv1_updated_lines = {}

      for line in io.lines(tsv1_path) do
        if line:match("^origin_session") or line:match("^%s*$") then
          -- Skip header and blank lines...
        else
          local fields = split_tsv(line)

          if #fields == 45 then
            -- Making matches ONLY via original_source_path now!
            -- If ONLY a source-modified '2 2' (ucc & uct) exists in TSV 2, then we MUST make sure newly incoming monos (1 0 and/or 1 1's) have their final_* fields updated as well:
            local osp = normalize_path(fields[8])
            local tsv2_match = tsv2_by_osp[osp]

            if tsv2_match then
              local matched_tsv2_line = tsv2_match.line

              -- Update original_source_type if still "Undetermined":
              if fields[6] == "Undetermined" then
                fields[6] = matched_tsv2_line[6]
                debug_print("-> Updated original_source_type to:", line[6])
              end

              -- Always overwrite all final_* fields:
              fields[9] = matched_tsv2_line[9]; debug_print(" - final_source_location set to:", matched_tsv2_line[9])
              fields[10] = matched_tsv2_line[10]; debug_print(" - final_source_type set to:", matched_tsv2_line[10])
              fields[11] = matched_tsv2_line[11]; debug_print(" - final_io_code set to:", matched_tsv2_line[11])
              fields[12] = matched_tsv2_line[12]; debug_print(" - final_source_path set to:", matched_tsv2_line[12])

              updated = updated + 1
            else
              debug_print("No match found in TSV2 for path:", osp)
            end
            debug_print("Updated TSV1 fields:", table.concat(fields, " | "))
            -- Insert the line (updated or not) into tsv1_updated_lines:
            table.insert(tsv1_updated_lines, table.concat(fields, "\t"))
          else
            debug_print("Skipping malformed line:", line)
          end
        end
      end

      debug_print("TSV1 update complete. Entries patched:", updated)

      -- Apply updated entries to TSV1 via our flush_tsv1 function:
      flush_tsv1(tsv1_updated_lines)

      if debug_pause then
        flush_tsv2()
        if debug_pause_popup("Pre-Paste STEP 1: Define More Functions, Load TSVs, and Update TSV1 via TSV2 (if they exist)") then return end
      end

      --------------------------------------------------------------------------------------------------------------
      ------------------------- Pre-Paste STEP 2: Ensure TSV 2 Entries Exist and are Ready -------------------------
      --------------------------------------------------------------------------------------------------------------

      debug_print("-------------- Pre-Paste STEP 2: Ensure TSV 2 Entries Exist and are Ready --------------")

      -- Load (newest) TSV 1 entries for further use:
      local tsv1_entries = {}

      for line in io.lines(tsv1_path) do
        if line:match("^origin_session") or line:match("^%s*$") then
          -- Skip header or blank lines...
        else
          local fields = split_tsv(line)

          -- Do NOT include any parent/compound regions!
          -- Parents have no sources *in and of themselves* of course, and thus need no Pre-Paste importing/embedding:
          if fields[34] ~= "Parent" and #fields >= 20 then
            table.insert(tsv1_entries, {
              origin_session           = fields[1],
              origin_snapshot          = fields[2],
              used_channel_count       = fields[3],
              used_channel_type        = fields[4],
              original_source_location = fields[5],
              original_source_type     = fields[6],
              original_io_code         = fields[7],
              original_source_path     = normalize_path(fields[8]),
              final_source_location    = fields[9],
              final_source_type        = fields[10],
              final_io_code            = fields[11],
              final_source_path        = normalize_path(fields[12]),
              original_id              = fields[33]
            })
          end
        end
      end

      -- Try to find appropriate, existing TSV2 matches:
      for _, entry in ipairs(tsv1_entries) do
        local key = string.format("%s|%s|%s",
          entry.used_channel_count,
          entry.used_channel_type,
          entry.original_source_path
        )

        -- If no match, then create a corresponding TSV2 entry...
        if not tsv2_entries[key] then
          -- Since we're no longer making dedicated mono files (i.e. -L(mono)/-R(mono) ones), we no longer need to ensure that ucc is only 2 for a NIAF source...
          -- It can be 1 as well, thus for all variants of a NIAF trio (i.e. left, right, and stereo) the fsp will = the lsp...
          -- And of course the NIAF source's fsp will = lsp if the source is truly mono as well, thus:
          local lsp = entry.final_source_location == "NIAF" and get_lsp(entry.final_source_path) or "Undetermined"

          debug_print("TSV2 Loaded Key:", key)

          tsv2_entries[key] = {
            line = {
              local_session,                   -- 1
              local_snapshot,                  -- 2
              entry.used_channel_count,        -- 3
              entry.used_channel_type,         -- 4
              entry.original_source_location,  -- 5
              entry.original_source_type,      -- 6
              entry.original_io_code or "IO0", -- 7
              entry.original_source_path,      -- 8
              entry.final_source_location,     -- 9
              entry.final_source_type,         -- 10
              entry.final_io_code or "IO0",    -- 11
              entry.final_source_path,         -- 12
              lsp,                             -- 13: local_source_path
              "Undetermined"                   -- 14: IDs
            },
            IDs = {}
          }
   
        end
      end

      if debug_pause then
        flush_tsv2()
        if debug_pause_popup("Pre-Paste STEP 2: Ensure TSV 2 Entries Exist and are Ready") then return end
      end

      --------------------------------------------------------------------------------------------------------------------------------
      ------------------------- Pre-Paste STEP 3: Ensure As Many Entry Trios In TSV2 as (currently) possible -------------------------
      --------------------------------------------------------------------------------------------------------------------------------

      debug_print("-------------- Pre-Paste STEP 3: Ensure As Many Entry Trios In TSV2 as (currently) possible --------------")

      -- Attempt to ensure variant entries in TSV2 where appropriate:
      local groups_by_paths = {}

      -- Group TSV1 entries by osp & fsp:
      for _, entry in ipairs(tsv1_entries) do
        local key = normalize_path(entry.original_source_path) .. "|" .. normalize_path(entry.final_source_path)
        if not groups_by_paths[key] then groups_by_paths[key] = {} end
        table.insert(groups_by_paths[key], entry)
      end

      -- Process each group to conditionally ensure variants:
      for _, group in pairs(groups_by_paths) do

        local seen_types = {}  -- To prevent inserting duplicate ucc & uct pairs into "types".
        local types = {}
        local any_stereo_declared = false

        -- Establish the state of the ost & fst:
        for _, entry in ipairs(group) do
          local ucc = tonumber(entry.used_channel_count)
          local uct = tonumber(entry.used_channel_type)
          local type_key = tostring(ucc) .. "_" .. tostring(uct)

          if not seen_types[type_key] then
            seen_types[type_key] = true -- Flip to true to prevent this type from being inserted into "types" more than once.
            table.insert(types, { ucc = ucc, uct = uct }) -- Insert the ucc & uct type.
          end

          -- Check if the fst is of a stereo-nature:
          if entry.final_source_type == "Stereo" or entry.final_source_type == "DualMono" then
            any_stereo_declared = true -- Mark as stereo in nature.
          end
        end

        -- Sort types for easier matching:
        local type_set = {}
        for _, t in ipairs(types) do
          type_set[tostring(t.ucc) .. "_" .. tostring(t.uct)] = true
        end

        local has_2_0 = type_set["2_2"] -- This 2 2 is unused, but I'm keeping it here just in case later use is somehow desired...
        local has_1_0 = type_set["1_0"]
        local has_1_1 = type_set["1_1"]

        local group_size = #types
        local should_ensure = false

        if group_size == 1 then -- Only one entry: handle specific cases...
          if has_1_1 then -- This is right-side audio coming from a stereo source...
            should_ensure = true -- Thus a TSV2 trio is required.
          elseif has_1_0 and any_stereo_declared then -- The type has at some point (-in Wizard, likely) been set to "Stereo", or was simply DualMono to begin with...
            should_ensure = true -- Thus ensure.
          end
        elseif group_size == 2 then
          -- Any combo of two among the trio warrants variant generation:
          should_ensure = true
        end

        if should_ensure then
          ensure_variants(group[1]) -- Safe to pass just the first one as a 'representative' (-we only need one entry sent to ensure_variants).
        end

      end

      if debug_pause then
        flush_tsv2()
        if debug_pause_popup("Pre-Paste STEP 3: Ensure As Many Entry Trios In TSV2 as (currently) possible") then return end
      end

      --------------------------------------------------------------------------------------------------------------------------------------------------
      ------------------------- Pre-Paste STEP 4: Sync/share (re)Usable IDs, LSPs, and Final Source Types Amongst TSV2 Entries -------------------------
      --------------------------------------------------------------------------------------------------------------------------------------------------

      debug_print("-------------- Pre-Paste STEP 4: Sync/share (re)Usable IDs, LSPs, and Final Source Types Amongst TSV2 Entries --------------")

      -- Group TSV2 entries by {ucc, uct, fsp}:
      local sync_groups = {}

      for _, entry in pairs(tsv2_entries) do
        local line = entry.line
        if line and #line == 14 then
          local ucc = line[3] -- used_channel_count
          local uct = line[4] -- used_channel_type
          local fsp = normalize_path(line[12]) -- final_source_path
          local key = table.concat({ucc, uct, fsp}, "|")

          -- Create potential "group" if needed:
          if not sync_groups[key] then
            sync_groups[key] = {}
          end
          -- Apply TSV2 entries to their "group":
          table.insert(sync_groups[key], entry)
        end
      end

      -- For each group, sync the pooled IDs, lsp, and fst: ---------------------------------------------------------------------------------------------
      for key, group in pairs(sync_groups) do
        local pooled_ids = {} -- All unique IDs pooled across group.
        local seen_ids = {} -- Map to avoid ID duplication.
        local chosen_lsp = "Undetermined"
        local chosen_fst = "Undetermined"

        for _, entry in ipairs(group) do
          -- Pool unique IDs:
          for _, id in ipairs(entry.IDs or {}) do
            if not seen_ids[id] then
              table.insert(pooled_ids, id)
              seen_ids[id] = true
            end
          end

          -- Choose first (-should be only?) lsp:
          local lsp = entry.line[13] or "Undetermined"
          if lsp ~= "Undetermined" and chosen_lsp == "Undetermined" then
            chosen_lsp = lsp
          end

          -- Choose first (-should be only?) fst:
          local fst = entry.line[10] or "Undetermined"
          if fst ~= "Undetermined" and chosen_fst == "Undetermined" then
            chosen_fst = fst
          end
        end

        -- Apply shared values to all group entries:
        for _, entry in ipairs(group) do
          entry.IDs = pooled_ids -- Assign back the full, shared ID list.
          entry.line[14] = table.concat(pooled_ids, " ") -- Also store as TSV2 string in field 14.
          if chosen_lsp ~= "Undetermined" then -- Not really necessary code(?).
            entry.line[13] = chosen_lsp
          end
          if chosen_fst ~= "Undetermined" then -- Also not really necessary code(?).
            entry.line[10] = chosen_fst
          end
          debug_print("Synced TSV2 group:", key, "#IDs:", #pooled_ids, "LSP:", chosen_lsp, "FST:", chosen_fst)
        end
      end

      if debug_pause then
        flush_tsv2()
        if debug_pause_popup("Pre-Paste STEP 4: Sync/share (re)Usable IDs, LSPs, and Final Source Types Amongst TSV2 Entries") then return end
      end

      --------------------------------------------------------------------------------------------------------------------------------
      ------------------------- Pre-Paste STEP 5: Scan Current Region Playlists to Salvage Usable Region IDs -------------------------
      --------------------------------------------------------------------------------------------------------------------------------

      debug_print("-------------- Pre-Paste STEP 5: Scan Current Region Playlists to Salvage Usable Region IDs --------------")

      local found_regions = {}

      -- A ONE-TIME scan of all *actively used* audio regions in the current snapshot...
      -- We will then insert info on each found region into our found_regions table:
      for t in Session:get_tracks():iter() do
        local tr = t:to_track()
        if tr and not tr:isnil() then
          local pl = tr:playlist()
          if pl and not pl:isnil() then
            for r in pl:region_list():iter() do
              local ar = r:to_audioregion()
              if ar and not ar:isnil() then
                local fr_ucc = ar:n_channels() -- Establish the found region's ucc for the next check...
                if fr_ucc == 1 or fr_ucc == 2 then -- Immediately limit to regions that are ONLY Mono or Stereo!
                  local fr_id = r:to_stateful():id():to_s()
                  local fr_uct = 0 -- Initially default to Mono/Left (i.e. Undetermined).
                  local src = ar:source(0)
                  if src and not src:isnil() then
                    local fs = src:to_filesource()
                    if fs and not fs:isnil() then
                      local fr_lsp = normalize_path(fs:path())

                      if fr_ucc == 2 then
                        fr_uct = 2 -- We know the uct is 2 (stereo).
                      elseif fr_ucc == 1 then
                        local ch_index = fs:channel()
                        fr_uct = (ch_index == 1) and 1 or 0 -- 1 = right, 0 = left OR it could be just mono.

                        -- DualMono Logic Tag
                        local is_dm, lr_type, other_path, _ = detect_dualmono_pair(fr_lsp)
                        if is_dm and lr_type == "right" then
                          fr_uct = 1 -- Explicitly force its uct as 1 (= right).
                          fr_lsp = normalize_path(other_path) -- For now, we ALWAYS just default to the %L of a DualMono pair, -EVEN IF uct=1 (and thus it's right)...
                        end                                   -- I know this is NOT how Ardour handles it (-i.e. the path of a '1 1' region will point towards the %R of the pair)...
                      end                                     -- But for THIS script it's just easier to always point towards ONE file of a DM pair for all variants, thus the %L one.
                      -- Insert the determined fields into our found_regions table:
                      table.insert(found_regions, {
                        fr_id  = fr_id,  -- 'found_region_id'
                        fr_ucc = fr_ucc, -- 'found_region_used_channel_count'
                        fr_uct = fr_uct, -- 'found_region_used_channel_type'
                        fr_lsp = fr_lsp  -- 'found_region_local_source_path' (-Simply the exact path+file its source is using.)
                      })
                    end
                  end
                end
              end
            end
          end
        end
      end

      -- A function to remove any 00000 placeholder IDs:
      local function remove_fake_id(entry)
        for i = #entry.IDs, 1, -1 do
          if entry.IDs[i] == "00000" then
            table.remove(entry.IDs, i)
          end
        end
      end

      -- Attempt to match and append safe (i.e. usable) IDs:
      for _, entry in pairs(tsv2_entries) do
        local line = entry.line
        local ucc = tonumber(line[3])
        local uct = tonumber(line[4])
        local lsp = normalize_path(line[13] or "")
        local fsp = normalize_path(line[12] or "")

        -- Establish if a "00000" placeholder ID exists and thus needs to be removed (if a valid region/ID is found):
        local needs_cleaning = false
        for _, id in ipairs(entry.IDs) do
          if id == "00000" then
            needs_cleaning = true
            break
          end
        end

        for _, fr in ipairs(found_regions) do
          local id = fr.fr_id

          -- 1: Match fr_lsp to lsp (i.e. local_source_path, which is basically just the ultimate, actual path of a source):
          if fr.fr_lsp == lsp and fr.fr_ucc == ucc and fr.fr_uct == uct then
            local already = false
            for _, existing in ipairs(entry.IDs) do
              if existing == id then already = true; break end
            end
            if not already then
              -- Erase the placeholder ID (-should only execute once):
              if needs_cleaning then
                for i = #entry.IDs, 1, -1 do
                  if entry.IDs[i] == "00000" then
                    table.remove(entry.IDs, i)
                  end
                end
                needs_cleaning = false
              end
              -- Insert the found_region ID:
              table.insert(entry.IDs, id)
              debug_print("Matched Region ID via LSP:", id, "->", lsp)
            end

          -- 2: Match fr_lsp to fsp (i.e. final_source_path, which is the *potentially-chosen* source to use/import/etc., which is not necessarily the lsp (yet)):
          elseif fr.fr_lsp == fsp and fr.fr_ucc == ucc and fr.fr_uct == uct then
            local already = false
            for _, existing in ipairs(entry.IDs) do
              if existing == id then already = true; break end
            end
            if not already then
              -- Erase the placeholder ID (-should only execute once):
              if needs_cleaning then
                for i = #entry.IDs, 1, -1 do
                  if entry.IDs[i] == "00000" then
                    table.remove(entry.IDs, i)
                  end
                end
                needs_cleaning = false
              end
              -- Insert the found_region ID:
              table.insert(entry.IDs, id)
              entry.line[13] = fr.fr_lsp  -- And write fr_lsp to local_source_path.
              debug_print("Matched Region ID via FSP (stereo fallback):", id, "->", fsp)
            end
          end
        end
      end

      -- Supplemental Matching: If origin_session matches local_session, insert the original_id as a *POTENTIAL* fallback ID... --------------
      -- I say "potential" because it IS possible that an ID in one snapshot might NOT work in another snapshot (all under the same project) due to source erasures by the user:
      for _, entry in pairs(tsv2_entries) do
        local line = entry.line
        --local session_match = (line[1] == line[9])
        local tsv2_ls = line[1]
        local tsv2_fsp = normalize_path(line[12] or "")
        local tsv2_ucc = tonumber(line[3])
        local tsv2_uct = tonumber(line[4])

        if not entry.IDs or #entry.IDs == 0 then
          for _, tsv1_line in ipairs(tsv1_entries) do
            local tsv1_os = tsv1_line.origin_session
            local tsv1_osp = normalize_path(tsv1_line.original_source_path or "") ---------------------------------------------
            local tsv1_ucc = tonumber(tsv1_line.used_channel_count)
            local tsv1_uct = tonumber(tsv1_line.used_channel_type)
            local original_id = tsv1_line.original_id
            -- Confirm a match here based on origin_session = local_session, and then osp & fsp, ucc, and uct matches: ---------------------------------------------
            if tsv1_os == tsv2_ls and tsv1_osp == tsv2_fsp and tsv1_ucc == tsv2_ucc and tsv1_uct == tsv2_uct then -- If the copied region's osp doesn't match the given TSV2 entry's
                                                                                                                  -- fsp, then manselect must have been used, thus don't match here.
              entry.IDs = { original_id } -- Set original_id to the IDs field.
              line[13] = tsv2_fsp -- Write tsv2_fsp into local_source_path.
              debug_print("Injected original_id based on session match:", original_id)
              break
            end
          end
        end
      end

      -- Apply the results to TSV2:
      flush_tsv2()

      if debug_pause and debug_pause_popup("Pre-Paste STEP 5: Scan Current Region Playlists to Salvage Usable Region IDs") then return end

      -----------------------------------------------------------------------------------------------------------------------------
      ------------------------- Pre-Paste STEP 6: Detect Remaining Entries with Placeholder IDs ("00000") -------------------------
      -----------------------------------------------------------------------------------------------------------------------------

      debug_print("-------------- Pre-Paste STEP 6: Detect Remaining Entries with Placeholder IDs (\"00000\") --------------")

      -- Updated function to derive a normalized name ("nn") from a full path (-for establishing potential matches)...
      -- Used here, and in 'Source Finder Wizard' (-the next Pre-Paste "Step"):
      local function get_nn(path)
        local name = path:match("([^/]+)$") or "" -- Strip directory
        name = name:gsub("%.[^%.]+$", "") -- Strip extension

        -- Repeatedly strip suffix-like segments from the end (-similar to what is done in our DualMono detection (detect_dualmono_pair) function):
        local changed = true
        while changed do
          changed = false
          -- Strip trailing %L or %R
          if name:match("%%[LR]$") then
            name = name:sub(1, -3)
            changed = true
          -- Strip trailing -L or -R
          elseif name:match("%-[LR]$") then
            name = name:sub(1, -3)
            changed = true
          -- Strip trailing -digit(s)
          elseif name:match("%-%d+$") then
            name = name:gsub("%-%d+$", "")
            changed = true
          end
        end

        return name
      end

      local needed_variants_by_nn = {} -- Format: [nn] = "L", "R", "S", or combos like "LR", "RS", etc...

      -- Just before Wizard, scan tsv2_entries to see if any 00000 IDs remain:
      for _, entry in pairs(tsv2_entries) do
        for _, id in ipairs(entry.IDs) do
          if id == "00000" then
            local line = entry.line
            if line then
              local nn = get_nn(line[12]) -- Use the fsp of the TSV2 entry to generate the normalized name (nn).
              local uct = tonumber(line[4]) -- Channel type: 0 = L, 1 = R, 2 = Stereo.
              local type_code = (uct == 0) and "L" or (uct == 1) and "R" or (uct == 2) and "S" or nil
              if type_code then
                needed_variants_by_nn[nn] = needed_variants_by_nn[nn] or ""
                if not needed_variants_by_nn[nn]:find(type_code, 1, true) then
                  needed_variants_by_nn[nn] = needed_variants_by_nn[nn] .. type_code
                end
              end
            end
          end
        end
      end

      -- Show dialog if any "00000" placeholder IDs were found:
      if next(needed_variants_by_nn) then
        local task_lines = {
          { type = "label", title = "Did you forget to add the necessary variants to a track?" },
          { type = "label", title = " " }, -- Spacer
          { type = "label", title = "Please temporarily drag-and-drop the following source variant(s)" },
          { type = "label", title = "from the 'Sources' list (View -> Show Editor List -> Sources)" },
          { type = "label", title = "onto any audio track in this session, then rerun Pre-Paste:" },
          { type = "label", title = " " } -- Spacer
        }

        -- Dynamically insert (into the popup) whatever variants are still required:
        for nn, codes in pairs(needed_variants_by_nn) do
          local parts = {}
          if codes:find("L") then table.insert(parts, "-L") end
          if codes:find("R") then table.insert(parts, "-R") end
          if codes:find("S") then table.insert(parts, "Full Stereo") end

          local label = string.format("• Source: %s: %s variant(s)", nn, table.concat(parts, ", and "))
          table.insert(task_lines, { type = "label", title = label })
        end

        table.insert(task_lines, { type = "label", title = " " })
        table.insert(task_lines, { type = "label", title = "Afterwards, you may delete those regions!" })
        table.insert(task_lines, { type = "label", title = "Thank you for your assistance!" })

        LuaDialog.Dialog("⚠ User Action Still Required!", task_lines):run()

        return -- Break out of Pre-Paste so the user can fulfill their side of the "bargain". o___o
      end

      if debug_pause and debug_pause_popup("Pre-Paste STEP 6: Detect Remaining Entries with Placeholder IDs (\"00000\")") then return end

      -----------------------------------------------------------------------------------------------------------------------------------------------------------------------
      ------------------------- Pre-Paste STEP 7: 'Source Finder Wizard'; Automatically Find Potential Source Matches and Present Them to the User --------------------------
      -----------------------------------------------------------------------------------------------------------------------------------------------------------------------

      -- This section (like many others) was a nightmare to organize and refine, and it's still pretty difficult to navigate... o___o
      -- Good-luck!

      -- If this section already ran, then it won't run again (unless the user specifically wanted it to via the dd-menu in the main Pre-Paste window):
      if skip_wizard then
        debug_print("--> Skipping Pre-Paste STEP 7: 'Source Finder Wizard'...")
      else

        debug_print("-------------- Pre-Paste STEP 7: 'Source Finder Wizard'; Automatically Find Potential Source Matches and Present Them to the User --------------")

        ----------------------------------- Wizard, Step 1/10: Build unique_tsv2_entries_without_ids -----------------------------------

        local unique_tsv2_entries_without_ids = {} -- Grouped by osp and fsp.

        for _, entry in pairs(tsv2_entries) do
          local line = entry.line
          if line and #line == 14 and (#entry.IDs == 0) then -- IDs must be nil/0/"Undetermined".
            local utewid_ucc = tonumber(line[3])
            local utewid_uct = tonumber(line[4])
            local utewid_ost = line[6]
            local utewid_osp = normalize_path(line[8])
            local utewid_fst = line[10]
            local utewid_fsp = normalize_path(line[12])
            local utewid_nn = get_nn(utewid_fsp)

            -- Insert the 7 relevant fields we'll need per entry without IDs:
            table.insert(unique_tsv2_entries_without_ids, {
              utewid_ucc = utewid_ucc,
              utewid_uct = utewid_uct,
              utewid_ost = utewid_ost,
              utewid_osp = utewid_osp,
              utewid_fst = utewid_fst,
              utewid_fsp = utewid_fsp,
              utewid_nn = utewid_nn
            })
          end
        end

        debug_print("Step 5.1 complete: UTEWIDs built -", #unique_tsv2_entries_without_ids, "entries.")

        ----------------------------------- Wizard, Step 2/10: Reduce found_regions To unique_found_regions -----------------------------------

        -- The goal here is to remove any 'duplicates' from found_regions, and then determine and store new info about each that remain.

        local thinned_found_regions = {}

        for _, fr in ipairs(found_regions) do
          local key = table.concat({fr.fr_ucc, fr.fr_uct, normalize_path(fr.fr_lsp)}, "|")
          if not thinned_found_regions[key] then -- If it doesn't already exist (in thinned_found_regions) based on the previous key, then...
            thinned_found_regions[key] = fr -- Add the fr (found region) to the thinned table.
          end
        end

        -- Now construct the UFR table:
        local unique_found_regions = {}

        for _, tfr in pairs(thinned_found_regions) do
          -- New ufr_* terms for the ucc, uct, lsp, and id:
          local ufr_ucc = tfr.fr_ucc
          local ufr_uct = tfr.fr_uct
          local ufr_lsp = normalize_path(tfr.fr_lsp)
          local ufr_id = tfr.fr_id

          -- Determine UFR source location (IAF, TREE, NIAF):
          local ufr_src_loc
          if ufr_lsp:match("/interchange/[^/]+/audiofiles/") then
            ufr_src_loc = "IAF"
          elseif ufr_lsp:find(normalize_path(Session:path()), 1, true) then
            ufr_src_loc = "TREE"
          else
            ufr_src_loc = "NIAF"
          end

          -- Determine UFR source type:
          local ufr_src_type = "Undetermined" -- Default as "Undetermined".
          if ufr_ucc == 2 then
            ufr_src_type = "Stereo" -- Could be DualMono, but we'll check that in a moment.
          elseif ufr_ucc == 1 and ufr_uct == 1 then
            ufr_src_type = "Stereo" -- Same.
          end

          -- Determine UFR potential IO-code:
          -- DualMono Logic Tag
          local ufr_pot_io_code = 0 -- Default to 0.
          local is_dm, lr_type, other_path, _ = detect_dualmono_pair(ufr_lsp)

          if ufr_src_loc == "IAF" then
            if is_dm then
              ufr_pot_io_code = 1
              ufr_src_type = "DualMono"
              if lr_type == "right" then
                ufr_lsp = other_path -- Force R-side DualMono paths (%R or -R) to *point to* the L-side ones (%L or -L) for the lsp; for now, this is the standard in this script.
              end
            else
              ufr_pot_io_code = 2
            end
          elseif ufr_src_loc == "TREE" then
            ufr_pot_io_code = 2
          elseif ufr_src_loc == "NIAF" then
            ufr_pot_io_code = 3
          end

          -- Assemble the determined/known values and insert them into unique_found_regions:
          table.insert(unique_found_regions, {
            ufr_ucc         = ufr_ucc,
            ufr_uct         = ufr_uct,
            ufr_src_loc     = ufr_src_loc,
            ufr_src_type    = ufr_src_type,
            ufr_pot_io_code = ufr_pot_io_code,
            ufr_lsp         = ufr_lsp,
            ufr_id          = ufr_id, -- NEW
            ufr_nn          = get_nn(ufr_lsp)
          })
        end

        ----------------------------------- Wizard, Step 3/10: Match UTEWIDs With UFRs -----------------------------------

        local potential_match_bundles = {} -- One entry per nn

        for _, utewid in ipairs(unique_tsv2_entries_without_ids) do

          local utewid_nn = utewid.utewid_nn
          local utewid_osp = utewid.utewid_osp
          local utewid_fsp = utewid.utewid_fsp

          local bundle_key = utewid_nn .. "|" .. utewid_osp .. "|" .. utewid_fsp -- Create a bundle's key based on the nn, osp, and fsp of a given utewid.
          local type_key = tostring(utewid.utewid_ucc) .. "_" .. tostring(utewid.utewid_uct) -- Establish a key for just the ucc + uct 'type'.

          -- Initialize the bundle/group, if needed:
          if not potential_match_bundles[bundle_key] then
            potential_match_bundles[bundle_key] = {
              nn = utewid_nn, -- The normalized_name will be shared by ufr matches, so we can just call it "nn" here.
              utewid_osp = utewid_osp, -- Keep track of the osp used for this bundle.
              utewid_fsp = utewid_fsp, -- Keep track of the fsp used for this bundle.
              utewids = {},
              utewid_types = {}, -- Used for efficient check of 'types' present (i.e. 1 0, 1 1, 2 2) in the next step...
              ufrs = {},
              ufr_types = {}, -- Same.
              user_task_extra = {} -- For holding extra info we need, like what variants would still be needed if the user approves a particular match, etc. --------------
            }
          end

          local bundle = potential_match_bundles[bundle_key]

          table.insert(bundle.utewids, utewid) -- Insert into the utewids sub-table.
          bundle.utewid_types[type_key] = true -- Set that this particular type (whatever it is) is in fact present/seen in this particular bundle.
        end
        
        -- Now match UFRs to UTEWIDs:
        for _, ufr in ipairs(unique_found_regions) do

          local ufr_nn = ufr.ufr_nn
          local type_key = tostring(ufr.ufr_ucc) .. "_" .. tostring(ufr.ufr_uct) -- Establish a key for just the ucc + uct 'type'.
        
          for key, bundle in pairs(potential_match_bundles) do
            if bundle.nn == ufr_nn then
              table.insert(bundle.ufrs, ufr) -- Insert the ufr into the ufrs sub-table.
              bundle.ufr_types[type_key] = true -- Mark this type as seen.
            end
          end
        end

        -- Now simply remove bundles where no matched UFRs were found/added:
        for key, bundle in pairs(potential_match_bundles) do
          if #bundle.ufrs == 0 then
            potential_match_bundles[key] = nil
          end
        end

        ----------------------------------- Wizard, Step 4/10: Determine Missing Variants, And Apply Specific UI Conditions -----------------------------------

        -- Re-shape the bundles into an *indexed list* for further processing/etc.:
        local match_bundles = {}

        for _, bundle in pairs(potential_match_bundles) do
          table.insert(match_bundles, bundle)
        end

        -- Initiate a --------------
        for _, bundle in ipairs(match_bundles) do

          -- Immediately establish which variant(s) would still be needed per potential matching UFR in this particular bundle, if that potential match is approved by the user:
          for _, ufr in ipairs(bundle.ufrs) do
            local key = ufr.ufr_lsp -- Use the ufr's local_source_path as the distinguishing bit of info.
            local missing = {}
          
            if not bundle.ufr_types["1_0"] then table.insert(missing, "L") end -- "L" indicates that the left-side audio is *potentially* missing (as a region on the timeline).
            if not bundle.ufr_types["1_1"] then table.insert(missing, "R") end -- "R" indicates that the right-side audio is *potentially* missing.
            if not bundle.ufr_types["2_2"] then table.insert(missing, "S") end -- "S" indicates that the full stereo audio is *potentially* missing.
                                                                               -- I say "potentially" because the original utewid might be a 1 0 *true mono*, say,
                                                                               -- so any R or S labeled in/as "missing" would be irrelevant/misleading.
            bundle.user_task_extra[key] = table.concat(missing, "") -- Combine any/all letter 'labels' into a string (-e.g. "LS", "R", etc.).
          end

          -- Begin analyzing which 'types' we need (in utewid), and which types we've found (via fr/ufr):
          local needed_types = bundle.utewid_types or {}
          local found_types = bundle.ufr_types or {}
        
          local needs_10 = needed_types["1_0"]
          local needs_11 = needed_types["1_1"]
          local needs_22 = needed_types["2_2"]
        
          local found_10 = found_types["1_0"]
          local found_11 = found_types["1_1"]
          local found_22 = found_types["2_2"]
        
          bundle.user_task = false -- A flag for whether or not we'll have to show a final popup to the user to request their help.
          bundle.needs_channel_declaration = false -- A flag to manifest a dd-menu to let the user tell us whether a certain potential match is mono or stereo.
        
          local nn = bundle.nn
          local missing = {}
        
          -- Case 1: JUST a '2 2' is needed:
          if needs_22 and not needs_10 and not needs_11 then
            if not found_22 then -- I.E. if ONLY a 1 0 and/or a 1 1 was found, then we can still infer that a 2 2 exists, and we'd just need the user to put it on a track
                                 -- for us (in addition to whichever other variant, perhaps), thus we will still offer this ufr to the user as a potential match, and thus...
              bundle.user_task = true -- Mark to initiate the user_task window if this match is ultimately approved by the user.
            end
        
          -- Case 2: JUST a '1 0' is needed:
          elseif needs_10 and not needs_11 and not needs_22 then -- Only a *potential* true mono is needed (-yet it could be left-side audio):
            if found_10 and not found_11 and not found_22 then -- Since only a 1 0 was found, then we should let the user tell us if it's mono or stereo, to be safe.
              local utewid_ost = bundle.utewids[1] and bundle.utewids[1].utewid_ost
              if utewid_ost == "DualMono" then -- Then we know this is *stereo in nature*, thus there's no need to ask the user about it...
                bundle.user_task = true -- But we'd still need the other variants (-in this case the right (R) and full stereo (S) ones.)
              else
                bundle.needs_channel_declaration = true -- We need to ask the user about this, and later if they say it's stereo, we'll then flip
                                                        -- bundle.user_task = true so they can place the right and stereo variants on a track for us.
              end
            elseif found_22 or found_11 then -- No need for an extra dd-menu (because confirming this match would mean that it's stereo), thus...
              bundle.user_task = true -- Only show the user_task popup at the end.
            end

          -- Case 3: A Full Trio is needed:
          elseif needs_10 and needs_11 and needs_22 then
            if found_22 or (found_10 and found_11 and found_22) then
              bundle.user_task = false -- No need for a final user_task popup; we assume no -L/-R variants exist, and separate_by_channel (via an IO) will have to be used regardless...
                                       -- And if the full trio already exists in this ufr group, then we ALSO don't have to request that the user do anything more.
            elseif found_10 or found_11 then -- If a 1 0 and/or 1 1 is found (and this ufr is eventually approved as a match), then we infer the other variants exist, thus...
              bundle.user_task = true -- Mark to present the user_task popup; we'll need the final variant(s) available on a track.
            end

          -- Case 4: Needs any other possible combination...
          -- This is helpful in situations where (for example) a left-side '1 0' was alone in TSV2 but *already had an ID* thanks to Pre-Paste STEP 5 (playlist scanning)
          -- and its automatic matching... -But then later the user tries to copy and paste a right-side '1 1' and/or a full stereo '2 2' from that same source,
          -- thus Pre-Paste STEP 3 had used ensure_variants to manifest a trio accordingly, leaving a combination of two variants still needing their IDs, thus:
          elseif needs_10 or needs_11 then -- We can eliminate an "or needs_22" here because if there was a needed but lonely '2 2', then it would have already been caught by Case 1.
            if found_10 or found_11 or found_22 then
              bundle.user_task = true -- Here, the user will have to place variants on a track regardless of what's been found.
            end
          end

        end

        ----------------------------------- Wizard, Step 5/10: Initiate A First UI Window -----------------------------------

        -- Create a table for storing our user-approved matches:
        local final_user_approvals = {}
        local has_user_task_flagged_group = false -- We'll set this to true if any approved match belongs to a group that requires the final user_task popup.

        if #match_bundles == 0 then
          -- Only show this dialog if 'Wizard' was re-ran by the user (-via the main Pre-Paste window's drop-down-menu) and nothing potentially usable was detected:
          if reran_wizard then
            local notify = LuaDialog.Dialog("No Matches Found!", {
              { type = "heading", title = "⚠" },
              { type = "label", title = "The 'Source Finder Wizard' couldn't identify" },
              { type = "label", title = "any more usable sources in this project..." },
              { type = "label", title = " " }, -- Spacer
              { type = "label", title = "If you're looking for a specific file, consider using:" },
              { type = "heading", title = "\"Option 3 - Manually Select Files To Use\"!" },
              { type = "label", title = " " } -- Spacer
            })
            notify:run()
          end
        end

        -- Initiate dialog if potential matches were identified:
        if #match_bundles > 0 then

          local match_count = #match_bundles -- A number we can insert into this dialog. --------------------------------------------------------------

          local initial_dialog = LuaDialog.Dialog("Usable Sources Found!?", {
            { type = "heading", title = "⚠" },
            { type = "heading", title = string.format("This script has identified %d potentially-usable", #match_bundles) }, ----------------------------
            { type = "heading", title = "source(s) already present in this project!" },
            { type = "label", title = " " }, -- Spacer
            { type = "label", title = "To reduce duplicate imports/embeds, please" },
            { type = "label", title = "proceed to confirm or deny potential matches." },
            { type = "label", title = " " }, -- Spacer
            { type = "dropdown",
              key = "action",
              title = "User Action",
              values = {
                ["Option 1 - Proceed"] = "proceed",
                ["Option 2 - Reuse Nothing (Skip This)"] = "skip"
              }, default = "proceed"          
            }
          })

          local result = initial_dialog:run()
          if not result then return end

          local user_choice = result["action"]

          ----------------------------------- Wizard, Step 6/10: Initiate The Match Window Sequence -----------------------------------

          if user_choice == "skip" then -- Skip Wizard and simply go to the next step in Pre-Paste.
            debug_print("User opted to skip all suggested matches.")
          else

            --Begin match-confirmation windows:
            for i, bundle in ipairs(match_bundles) do

              local dd_options = { ["Deny All Potential Matches"] = "deny" } -- Establish one option in the dd-menu to deny all potential matches.
              local lsp_to_ufr = {}

              -- Just show details from the first utewids entry in the bundle (-doesn't matter which, as the osp & fsp for each should be the same):
              local first_utewid = bundle.utewids[1]
          
              -- Create the necessary dd-menu options/entries:
              for _, ufr in ipairs(bundle.ufrs) do
                local ufr_lsp = ufr.ufr_lsp
                if not lsp_to_ufr[ufr_lsp] then
                  lsp_to_ufr[ufr_lsp] = ufr
                  local desc = string.format("%s (Type: %s)", ufr_lsp, ufr.ufr_src_type)
                  dd_options[desc] = ufr_lsp
                end
              end
          
              local dialog_elements = {
                { type = "heading", title = "Original Source File (Type: " .. first_utewid.utewid_ost .. "):" },
                { type = "label", title = first_utewid.utewid_osp },
                { type = "label", title = " " }, -- Spacer.
                { type = "heading", title = "Current Choice For Source File (Type: " .. first_utewid.utewid_fst .. "):" },
                { type = "label", title = first_utewid.utewid_fsp },
                { type = "label", title = " " },
                { type = "label", title = "Please select the potential match you would like to use, if any:" },
                { type = "dropdown", key = "selected", title = "Potential Matches", values = dd_options, default = "deny" },
              }
          
              if bundle.needs_channel_declaration then
                table.insert(dialog_elements, { type = "label", title = " " })
                table.insert(dialog_elements, { type = "heading", title = "⚠ Source Type Declaration Required:" })
                table.insert(dialog_elements, { type = "label", title = "Is the original source stereo or mono?" })
                table.insert(dialog_elements, { type = "label", title = "(This script will assume any approved match is this as well.)" }) --------------
                table.insert(dialog_elements, {
                  type = "dropdown",
                  key = "channel_type",
                  title = "Original Source Type",
                  values = {
                    ["Mono"] = "mono",
                    ["Stereo"] = "stereo"
                  },
                  default = "mono"
                })
              end
          
              table.insert(dialog_elements, { type = "label", title = " " })
              table.insert(dialog_elements, { type = "heading", title = "⚠ ATTENTION:" })
              table.insert(dialog_elements, { type = "heading", title = "Please only choose matches that you are 100% certain are valid/usable." })
          
              local dialog = LuaDialog.Dialog(string.format("Potential Source Match %d/%d", i, #match_bundles), dialog_elements)
              local result = dialog:run()
              if not result then return end

              ----------------------------------- Wizard, Step 7/10: Process Approved Matches -----------------------------------

              local approved_ufr_lsp = result["selected"]
              if approved_ufr_lsp ~= "deny" then -- Thus, for any user-approved match via the dd-menu...

                local approved_ufr = lsp_to_ufr[approved_ufr_lsp]

                if bundle.needs_channel_declaration then -- If the bundle had been one where it needed a channel declaration, then...
                  
                  local declared_source_type = result["channel_type"]

                  if declared_source_type == "stereo" then
                    bundle.user_task = true -- As mentioned earlier, now we flip this to true because we are going to need the remaining (R & S) variants.

                    approved_ufr.user_task_extra = approved_ufr.user_task_extra or {}
                    approved_ufr.user_task_extra[approved_ufr_lsp] = "RS"

                    bundle.user_task_extra[approved_ufr_lsp] = "RS" -- Insert "RS" into the original bundle.user_task_extra (-although this isn't used later(?)).

                    for _, utewid in ipairs(bundle.utewids) do utewid.force_stereo = true end

                  elseif declared_source_type == "mono" then
                    for _, utewid in ipairs(bundle.utewids) do utewid.force_mono = true end -- No need for user_task or user_task_extra here...
                  end                                                                       -- The needed and found '1 0' regions are/were true mono.

                else -- In any other situation, the letters we need in bundle.user_task_extra should already exist, thus...
                  approved_ufr.user_task_extra = approved_ufr.user_task_extra or {} -- Insert into the approved_ufr table(???) ------------------------------------
                  approved_ufr.user_task_extra[approved_ufr_lsp] = bundle.user_task_extra[approved_ufr_lsp]
                end

                -- Establish a table for de-duplication of utewid variants:
                local seen_key = {}

                for _, utewid in ipairs(bundle.utewids) do

                  local key = normalize_path(utewid.utewid_osp) .. "|" .. normalize_path(utewid.utewid_fsp)

                  -- Add just a single utewid in this bundle to the final_user_approvals table:
                  if not seen_key[key] then
                    seen_key[key] = true

                    table.insert(final_user_approvals, {
                      utewid = utewid,
                      ufr = approved_ufr,
                      user_task = bundle.user_task
                    })
                  end

                  -- New Special Case: -----------------------------------------------------
                  local approved_ufr_ucc = tonumber(approved_ufr.ufr_ucc)
                  local approved_ufr_uct = tonumber(approved_ufr.ufr_uct)
                  local utewid_ucc = tonumber(utewid.utewid_ucc)
                  local utewid_uct = tonumber(utewid.utewid_uct)

                  if utewid_ucc == 2 and utewid_uct == 2 and approved_ufr_ucc == 1 and (approved_ufr_uct == 0 or approved_ufr_uct == 1) then

                    -- Direct match (more reliable than a search loop):
                    local matched_tsv2_entry = nil

                    for _, entry in pairs(tsv2_entries) do
                      local line = entry.line
                      if normalize_path(line[8]) == utewid.utewid_osp -- Find the tsv2_entries entry where the osp is the same...
                        and normalize_path(line[12]) == utewid.utewid_fsp then -- and where the fsp is the same.
                          matched_tsv2_entry = entry -- Use this entry for our ensure_variants function in a moment...
                        break
                      end
                    end
                    
                    if matched_tsv2_entry then

                      ensure_variants({
                        original_source_path = matched_tsv2_entry.line[8],
                        final_source_path = matched_tsv2_entry.line[12]
                      })                      
                      bundle.user_task = true
                      has_user_task_flagged_group = true

                      flush_tsv2()
                    end
                  end
          
                  if bundle.user_task then
                    has_user_task_flagged_group = true -- Mark to initiate the user_task popup later on...
                  end

                end
              end
            end

            ----------------------------------- Wizard, Step 8/10: Create The Final Confirmation Window -----------------------------------

            -- Initiate a final confirmation popup (-one last chance for the user to ditch their approved change(s)):
            if #final_user_approvals > 0 then
              local final_confirm = LuaDialog.Dialog("Confirm Selections...", {
                { type = "heading", title = string.format("You have approved %d potential match(es).", #final_user_approvals) },
                { type = "label", title = " " }, -- Spacer
                { type = "label", title = "Please hit OK to apply your changes," },
                { type = "label", title = "or Cancel if you'd like to disregard them" },
                { type = "label", title = "and move forward with only fresh imports/embeds." },
                { type = "label", title = " " } -- Spacer
                }
              )
              
              local ok = final_confirm:run()
              if not ok then
                debug_print("User cancelled after match approvals. No TSV 2 changes made.")
                final_user_approvals = {} -- Wipe selections
              end
            end

          end
        end

        ----------------------------------- Wizard, Step 9/10: Apply Approved Matches To TSV2 -----------------------------------

        if #final_user_approvals > 0 then

          for _, approval in ipairs(final_user_approvals) do

            -- Define terms for our approved utewid(s) & ufr match:
            local approved_utewid = approval.utewid
            local approved_ufr = approval.ufr

            -- User had declared that the '1 0' was from a stereo source (-i.e. it was left-side audio):
            if approved_utewid.force_stereo then
              -- Adjusting the value for the ufr is needed for the next block/area:
              approved_ufr.ufr_src_type = "Stereo"
            end

            -- User had declared that the '1 0' was just mono:
            if approved_utewid.force_mono then
              approved_ufr.ufr_src_type = "Mono"
            end
            
            -- Begin rewriting entries in tsv2_entries based on the approvals:
            for _, entry in pairs(tsv2_entries) do

              local line = entry.line

              if line and #line == 14 then -- A standard, over-precautionary(?) check to see if the current entry exists and has all 14 fields... 

                -- Define 'matching' terms:
                local osp_match = normalize_path(line[8]) == approved_utewid.utewid_osp
                local fsp_match = normalize_path(line[12]) == approved_utewid.utewid_fsp
                local ucc_match = tonumber(line[3]) == tonumber(approved_ufr.ufr_ucc) -- Match against the actual tsv2_entries entry's ucc.
                local uct_match = tonumber(line[4]) == tonumber(approved_ufr.ufr_uct) -- Match against the actual tsv2_entries entry's uct.

                -- debug_print for various things: --------------------------------
                debug_print("Checking entry...")
                debug_print("OSP Match:", osp_match, " | FSP Match:", fsp_match)
                debug_print("line[8]:", line[8], "vs approved_utewid.utewid_osp:", approved_utewid.utewid_osp)
                debug_print("line[12]:", line[12], "vs approved_utewid.utewid_fsp:", approved_utewid.utewid_fsp)
                debug_print("UCC/UCT Match:", ucc_match, "/", uct_match)
                debug_print("UCCs:", approved_utewid.utewid_ucc, "/", approved_ufr.ufr_ucc, " | UCTs:", approved_utewid.utewid_uct, "/", approved_ufr.ufr_uct)

                -- Confirm a 'full match' back to the current entry in tsv2_entries:
                if osp_match and fsp_match then

                  -- Mutate/assert original_source_type ONLY for lonely '1 0' instances (-which now should have been declared as mono or stereo),
                  -- because mutating others might lead to mislabling a true DualMono ost, say, as "Stereo":
                  if tonumber(approved_utewid.utewid_ucc) == 1 and tonumber(approved_utewid.utewid_uct) == 0 then
                    line[6] = approved_ufr.ufr_src_type -- Field 6 = original_source_type.
                  end

                  -- Now mutate other necessary things in the matched, TSV2 entry:
                  line[9] = approved_ufr.ufr_src_loc -- Field 9 = final_source_location.
                  line[10] = approved_ufr.ufr_src_type -- Field 10 = final_source_type; -Should be "Mono" or "Stereo" now (-if it was previously "Undetermined").
                  line[11] = "IO" .. tostring(approved_ufr.ufr_pot_io_code) -- Field 11 = final_io_code; Include the standard "IO" we use before the number.
                  line[12] = approved_ufr.ufr_lsp -- Field 12 = final_source_path.
                  line[13] = approved_ufr.ufr_lsp -- Field 13 = local_source_path.

                  local final_id = "Undetermined" -- Initially set the IDs field as "Undetermined".

                  -- Use the ufr_id (the ID of the original, found region) if available, and if there's also a ucc & uct match to the TSV2 entry:
                  if ucc_match and uct_match and approved_ufr.ufr_id and approved_ufr.ufr_id ~= "" then
                    final_id = approved_ufr.ufr_id
                  -- Detect if this is a user_task situation:
                  elseif approval.user_task then
                    -- A "00000" placeholder ID signifies that the user's help was requested (to drag-and-drop source variants into the project).
                    -- A placeholder like this is required so the TSV2 entry won't be erased upon a fresh Pre-Paste restart (-given Step 0):
                    final_id = "00000"
                  end

                  entry.IDs = { final_id } -- Apply the appropriate ID or placeholder, etc...

                  debug_print("Updated TSV2 entry from user-confirmed match:")
                  debug_print("New Line[6-14]:", line[6], line[9], line[10], line[11], line[12], line[14])
                end
              end
            end
          end

          -- 'Flush' tsv2_entries to the actual TSV2 file:
          flush_tsv2()
          debug_print("User-approved TSV2 updates saved.")

          ----------------------------------- Wizard, Step 10/10: Ask The User For Assistance, If Required -----------------------------------

          -- A special popup only for situations where help from the user is required:
          if has_user_task_flagged_group then

            -- Build the dynamic popup:
            local task_lines = {
              { type = "label", title = "For this script to find audio sources, they must be" },
              { type = "label", title = "present (as regions) on any track in this project." },
              { type = "label", title = " " }, -- Spacer
              { type = "label", title = "Please temporarily drag-and-drop the following source variant(s)" },
              { type = "label", title = "from the 'Source List' (View -> Show Editor List -> Sources)" },
              { type = "label", title = "onto any audio track, and then rerun Pre-Paste:" },
              { type = "label", title = " " } -- Spacer
            }

            -- Begin looping through the approvals:
            for _, approval in ipairs(final_user_approvals) do

              -- Establish some moar local terms:
              local approved_utewid = approval.utewid
              local user_task = approval.user_task
              local approved_ufr_lsp = approval.ufr.ufr_lsp
              local user_task_extra = approval.ufr.user_task_extra or {} -- fallback ---------------------------------
  
              -- Find the entry/ies where user_task was true, and disregard all others:
              if user_task and user_task_extra and user_task_extra[approved_ufr_lsp] then

                local type_codes = user_task_extra[approved_ufr_lsp]

                if type(type_codes) == "string" then -- Another precautionary check to prevent 'blowing-up' if type_codes is nil.

                  local parts = {}
                  if type_codes:find("L") then table.insert(parts, "-L") end -- Insert a -L in the popup (-for the left variant).
                  if type_codes:find("R") then table.insert(parts, "-R") end -- Insert a -R in the popup (-for the right variant).
                  if type_codes:find("S") then table.insert(parts, "Full Stereo") end -- Insert "Full Stereo" in the popup.
              
                  if #parts > 0 then

                    -- Combine it all into a single line:
                    local missing_variants = string.format("• Source: %s: %s variant(s)", approved_utewid.utewid_nn, table.concat(parts, ", and "))
                                                                                                                     -- Add ", and " between variant letters/text.
                    -- Insert the line into task_lines (i.e. the popup itself):
                    table.insert(task_lines, { type = "heading", title = missing_variants })
                  end
                end
              end
            end

            -- Add a closing note:
            table.insert(task_lines, { type = "label", title = " " }) -- Spacer
            table.insert(task_lines, { type = "label", title = "Afterwards, you may delete those regions!" })
            
            -- Show the popup:
            LuaDialog.Dialog("⚠ User Task Required!", task_lines):run()
            
            return -- Stops the Pre-Paste process to allow for the user to do their part.
          end

          -- Erase tsv2_entries before restarting (-precautionary):
          tsv2_entries = nil
          reran_wizard = false
          skip_wizard = true -- Mark to skip Wizard so it won't start again immediately (upon a Pre-Paste rerun).

          goto restart_prepaste -- Restart Pre-Paste; Pre-Paste Step 5 should now automatically find and apply usable IDs to the approved matches!

        end -- Ends "if #final_user_approvals > 0 then".

        if debug_pause and debug_pause_popup("Pre-Paste STEP 7: 'Source Finder Wizard'; Automatically Find Potential Source Matches and Present Them to the User") then return end

      end -- Ends "if skip_wizard then ... else".
    end -- Ends "if not skip_steps then".

    -------------------------------------------------------------------------------------------------------------
    ------------------------- Pre-Paste STEP 8: Build PP1 Table of Unique TSV 1 Entries -------------------------
    -------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Pre-Paste STEP 8: Build PP1 Table of Unique TSV 1 Entries --------------")

    -- Build a thinned PP1_map table from TSV1 entries:
    local PP1_map = {}  -- Key used = osp|fsp.

    local found_valid_tsv1_data = false -- If this remains false, it creates all kinds of specific popups later on.

    for line in io.lines(tsv1_path) do
      if not line:match("^origin_session") and not line:match("^%s*$") then -- Skip header and blank lines.

        found_valid_tsv1_data = true -- At least one entry is in TSV1.
        local fields = split_tsv(line) -- Split incoming lines into fields.

        -- Avoid adding any parents, yet again:
        if fields[34] ~= "Parent" and #fields == 45 then --------------
          local ucc = tonumber(fields[3])
          local uct = tonumber(fields[4])
          local osp = normalize_path(fields[8])
          local ioc = (fields[11] or "IO0"):match("%d+") or "0"
          local fsp = normalize_path(fields[12])

          local group_key = osp .. "|" .. fsp -- Key used = osp|fsp, thus this will capture any of a trio that match that.
          local existing = PP1_map[group_key]

          local keep = false
          if not existing then -- If not already in PP1_map, then...
            keep = true -- Mark to keep it.
          else
            local existing_ucc = tonumber(existing.used_channel_count)
            local existing_uct  = tonumber(existing.used_channel_type)

            if ucc == 1 and uct == 1 then
              keep = true -- prefer 1 1 (-Most info. held onto if possible, whilst also ensuring trio-of-entries-creation when needed.)
            elseif ucc == 1 and uct == 0 and not (existing_ucc == 1 and existing_uct == 1) then
              keep = true -- prefer 1 0 if no 1 1 exists (-A '1 0' is less infomative (-could be a Left OR true Mono), -but need to maintain trio-creation.)
            elseif ucc == 2 and uct == 2 and existing_ucc ~= 1 then
              keep = true -- fallback to 2 2 if no 1 1 or 1 0 exists (-Safe to use, and no trio of entries will be required or created.)
            end
          end

          if keep then -- If one of the above conditions was met (where keep = true), then *update/replace* the PP1_map[group_key] accordingly:
            PP1_map[group_key] = {
              used_channel_count   = tostring(ucc),
              used_channel_type    = tostring(uct),
              original_source_type = fields[6] or "Undetermined",
              original_source_path = osp,
              final_source_type    = fields[10] or "Undetermined",
              final_io_code        = ioc,
              final_source_path    = fsp,
              skip                 = false
            }
          end
        end
      end
    end

    -- Convert our thinned PP1_map to PP1...
    -- Also, note that if we had inserted directly into a list (PP1) from the start, we'd need an additional
    -- pass afterward to deduplicate based on osp|fsp, which would actually be more complex and slightly slower:
    local PP1 = {}
    for _, entry in pairs(PP1_map) do table.insert(PP1, entry) end

    -- Now evaluate which PP1 entries can be skipped due to having usable ID(s) in TSV2:
    for _, pp1_entry in pairs(PP1) do
      for _, tsv2_entry in pairs(tsv2_entries) do
        local tsv2_line = tsv2_entry.line
        if tsv2_line and #tsv2_line == 14 then
          local tsv2_ucc = tsv2_line[3]
          local tsv2_fsp = normalize_path(tsv2_line[12])
          local tsv2_ids = tsv2_entry.IDs or {}
    
          -- We assume that if one has a ucc = 1 and HAS IDs (or one), BUT the source was truly *stereo*, then trio creation already
          -- happened (or was dealt with via user_task help from Wizard, say), and the other mono variant should have an ID as well:
          if tsv2_ucc == pp1_entry.used_channel_count and tsv2_fsp == pp1_entry.final_source_path and #tsv2_ids > 0 then
            pp1_entry.skip = true -- Mark to skip the entry.
            break
          end
        end
      end
    end

    -- Do one final round of PP1-thinning; this is to prevent duplicate imports by thinning based on final_source_path ONLY:
    local pp1_by_fsp = {}

    -- Group all PP1 entries by final_source_path:
    for _, entry in ipairs(PP1) do
      local shared_fsp = entry.final_source_path
      if not pp1_by_fsp[shared_fsp] then
        pp1_by_fsp[shared_fsp] = {}
      end
      table.insert(pp1_by_fsp[shared_fsp], entry)
    end

    -- For each variant_group, apply secondary thinning rules...
    -- Again, the goal in all of this is to simply hold-on to the *most amount of info* we can for later steps/processing:
    for shared_fsp, variant_group in pairs(pp1_by_fsp) do
      if #variant_group > 1 then -- Obviously don't bother further thinning if only one entry exists in a 'variant_group'.
        local kept_entry = nil

        -- First, try to find a 1 1:
        for _, variant_entry in ipairs(variant_group) do
          if tonumber(variant_entry.used_channel_count) == 1 and tonumber(variant_entry.used_channel_type) == 1 then
            kept_entry = variant_entry
            break
          end
        end

        -- If no 1 1, try to find 1 0:
        if not kept_entry then
          for _, variant_entry in ipairs(variant_group) do
            if tonumber(variant_entry.used_channel_count) == 1 and tonumber(variant_entry.used_channel_type) == 0 then
              kept_entry = variant_entry
              break
            end
          end
        end

        -- If no 1 0, fallback to keeping a 2 2:
        if not kept_entry then
          for _, variant_entry in ipairs(variant_group) do
            if tonumber(variant_entry.used_channel_count) == 2 and tonumber(variant_entry.used_channel_type) == 2 then
              kept_entry = variant_entry
              break
            end
          end
        end

        -- Apply skip = true to all except the chosen one:
        for _, variant_entry in ipairs(variant_group) do
          if variant_entry ~= kept_entry then
            variant_entry.skip = true -- Mark to skip.
            debug_print("-> Marked redundant PP1 entry as skipped (same final_source_path):", shared_fsp)
          end
        end
      end
    end

    if debug_pause and debug_pause_popup("Pre-Paste STEP 8: Build PP1 Table of Unique TSV 1 Entries") then return end

    -------------------------------------------------------------------------------------------------------------------------------------------
    ------------------------- Pre-Paste STEP 9: Detect and Alert the User About Any Potential Legacy Reversed Regions -------------------------
    -------------------------------------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Pre-Paste STEP 9: Detect and Alert the User About Any Potential Legacy Reversed Regions --------------")

    -- Additional legacy reversed-region check for potential -0.wav/-1.wav pairs:
    local legacy_reversed_paths = {}

    -- Some notes on this:
    -- This has been very helpful for me personally thanks to my occasional use of reversed regions back in Ardour 2.8.16.
    -- But I just discovered that legacy reversed regions are NOT necessarily always ending with -0 or -1. -Those are merely
    -- numbers that can go up and up (-2, -3, etc.) depending on how many reversed regions (or perhaps even stretched regions,
    -- etc.) were produced by the user and Ardour.  Thus, although it's still okay and generally helpful(?) to TRY to catch
    -- any via a -0 or -1 ending, doing so definitely won't catch ALL that are *potentially* out there...

    for _, pp1_entry in ipairs(PP1) do
      if not pp1_entry.skip then
        local path = pp1_entry.final_source_path
        if path:match("%.wav$") then -- Only check ones that are the standard .wav file-type that Ardour uses.
          local filename = path:match("([^/]+)$") or ""
          if filename:match("%-0%.wav$") or filename:match("%-1%.wav$") then -- Check for a -0 or -1 before the .wav...
            table.insert(legacy_reversed_paths, path) -- Insert the detected path.
          end
        end
      end
    end

    -- Show just a single popup if any potential reversed regions were detected:
    if #legacy_reversed_paths > 0 then
      local lines = {
        { type = "heading", title = "⚠ WARNING:" },
        { type = "heading", title = "This script has detected at least one source that" },
        { type = "heading", title = "might be coming from a legacy reversed region:" },
        { type = "label", title = " " }, -- Spacer
      }

      for _, path in ipairs(legacy_reversed_paths) do
        table.insert(lines, { type = "label", title = path })
      end

      table.insert(lines, { type = "label", title = " " }) -- Spacer
      table.insert(lines, { type = "label", title = "If any listed above are from a legacy reversed region" })
      table.insert(lines, { type = "label", title = "that was STEREO, then it is highly recommended to:" })
      table.insert(lines, { type = "label", title = " " }) -- Spacer
      table.insert(lines, { type = "label", title = "1. Manually find and duplicate this file and its counterpart (-perhaps ending in -0 or -1)." })
      table.insert(lines, { type = "label", title = "2. Rename the duplicates to use %L/%R endings instead of -0/-1 endings." })
      table.insert(lines, { type = "label", title = "   (-Or better yet: ...(reversed)%L.wav / ...(reversed)%R.wav endings.)" })
      table.insert(lines, { type = "label", title = "3. Use the 'Manually Select Files to Use' feature and select" })
      table.insert(lines, { type = "label", title = "   the new %L file, and this script will take care of the rest." })
      table.insert(lines, { type = "label", title = " " }) -- Spacer
      table.insert(lines, { type = "heading", title = "If not, then please just ignore this message." })

      local dlg = LuaDialog.Dialog("Legacy Reversed Region(s) Detected?", lines)
      dlg:run()
    end
    
    -- Save PP1 for Step 11 (Import Option (IO) processing):
    _G.PP1_STATE = PP1

    if debug_pause and debug_pause_popup("Pre-Paste STEP 9: Detect and Alert the User About Any Potential Legacy Reversed Regions") then return end

    --------------------------------------------------------------------------------------------------------------------------------
    ------------------------- Pre-Paste STEP 10: Initiate the Main Pre-Paste Window and All Other Submenus -------------------------
    --------------------------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Pre-Paste STEP 10: Initiate the Main Pre-Paste Window and All Other Submenus --------------")

    -- Establish some simple counters for the main Pre-Paste window:
    local count_embed = 0
    local count_import = 0
    local count_pair = 0
    local count_skipped = 0

    for _, entry in pairs(PP1) do
      local final_io_code = tonumber(entry.final_io_code) -- Only need the IO-code for this...
      if entry.skip then -- Entry was marked to skip, thus...
        count_skipped = count_skipped + 1 -- Add to skipped counter.
      elseif final_io_code == 3 then -- For NIAF files, thus...
        count_embed = count_embed + 1 -- Add to 'embed/embedded files' counter.
      elseif final_io_code == 1 then -- For DualMono processing, thus...
        count_pair = count_pair + 1 -- Add to 'pairs' counter.
      else
        count_import = count_import + 1 -- Any others then fall into the 'import/imported files' counter.
      end
    end

    local summary_lines = {}

    -- Use counter totals with text but ONLY if there's at least one in whichever counted 'group':
    if count_embed > 0 then
      table.insert(summary_lines, string.format("Embed(ed) Files: %d", count_embed))
    end
    if count_import > 0 then
      table.insert(summary_lines, string.format("Import(ed) Files: %d", count_import))
    end
    if count_pair > 0 then
      table.insert(summary_lines, string.format("Import(ed) L/R Pairs: %d", count_pair))
    end
    if count_skipped > 0 then
      table.insert(summary_lines, string.format("Skipped Files: %d", count_skipped))
    end

    -- Build summary_text based on the previous summary_lines:
    local summary_text
    if found_valid_tsv1_data then
      summary_text = table.concat(summary_lines, "\n")
    end

    skip_final_message = false -- This concerns the final message after IO-processing.

    local heading_text = "Files to process:" -- "Files to process" here makes the most sense, because sometimes no importing/embedding is required -> only mono/variant creation.(!)
    if not found_valid_tsv1_data then
      heading_text = "Nothing is copied!" -- Mutate heading_text to this if nothing was/is copied.
      skip_final_message = true -- Mark to skip the final message.
    elseif count_embed == 0 and count_import == 0 and count_pair == 0 and count_skipped > 0 then
      heading_text = "All files are ready!"
      skip_final_message = true -- Also mark to skip the final message.
    end

    -- Entry-point back into the main Pre-Paste window:
    ::main_prepaste_window::

    -- Create the main Pre-Paste window:
    local confirm_dialog = LuaDialog.Dialog("Pre-Paste Summary", {
    { type = "heading", title = heading_text }, -- Insert variable heading_text.
    { type = "label", title = summary_text }, -- Insert variable summary_text.
    { type = "heading", title = "What would you like to do?" },
    {
      type = "dropdown", -- Show the drop-down menu...
      key = "choice",
      title = "",
      values = {
        ["Option 1 - Proceed"] = "proceed",
        ["Option 2 - View File List"] = "viewlist",
        ["Option 3 - Manually Select Files To Use"] = "manselect",
        ["Option 4 - Re-Run Source Finder Wizard"] = "wizard",
        ["Option 5 - Erase ID Cache"] = "erasecache"
      },
      default = "proceed"
    }
    })

    local confirm_result = confirm_dialog:run()
    if not confirm_result then return end -- Bail if something goes wrong (the window fails to appear).

    local user_choice = confirm_result["choice"]
    if not user_choice then return end -- Bail if the user's choice somehow goes wrong.
    
    ----------------------------------------------------------------------------------------------------
    ------------------------- Main Pre-Paste Window: Option 2 - View File List -------------------------
    ----------------------------------------------------------------------------------------------------

    -- Show list of individual files if "View File List" was selected:
    if user_choice == "viewlist" then

      if not found_valid_tsv1_data then
        LuaDialog.Message("No Regions Copied!",
          "Please copy some regions first before proceeding.",
          LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run()
        return
      end
      
      -- Group final_source_paths by their intended processing type:
      local view_groups = {
        ["Import/Process Imported Dual-Mono Pair(s)"] = {},
        ["Import/Process Imported Mono or Stereo File(s)"] = {},
        ["Embed/Process Embedded Mono or Stereo File(s)"] = {},
        ["Skipped (i.e. Redundant or Present) File(s)"] = {}
      }
      
      -- Classify each PP1 entry into one of the above categories based on final_io_code (1 = dualmono, 2 = import, 3 = embed).
      for _, entry in pairs(PP1) do
        local path = entry.final_source_path
        local final_code = tonumber(entry.final_io_code)
        local group_name = "Skipped (i.e. Redundant or Present) File(s)" -- Default to the "Skipped" category.

        if not entry.skip then
          if final_code == 1 then
            group_name = "Import/Process Imported Dual-Mono Pair(s)" -- Mutate the group_name accordingly...
          elseif final_code == 2 then
            group_name = "Import/Process Imported Mono or Stereo File(s)"
          elseif final_code == 3 then
            group_name = "Embed/Process Embedded Mono or Stereo File(s)"
          end
        end

        table.insert(view_groups[group_name], path)
      end

      -- Display the groups in a fixed order:
      local group_order = {
        "Import/Process Imported Dual-Mono Pair(s)",
        "Import/Process Imported Mono or Stereo File(s)",
        "Embed/Process Embedded Mono or Stereo File(s)",
        "Skipped (i.e. Redundant or Present) File(s)"
      }
      
      local view_text = ""
      for _, group in ipairs(group_order) do
        local paths = view_groups[group]
        if #paths > 0 then
          table.sort(paths, function(a, b) return a:lower() < b:lower() end) -- Sort each group's paths alphabetically (case-insensitive).
          
          -- Append group title and file list:
          view_text = view_text
            .. string.format(" --- %s (%d) ---\n\n", group, #paths) -- Add some dashes to the group names to make them stand-out a bit more.
          
          view_text = view_text .. table.concat(paths, "\n\n") .. "\n\n\n"
        end
      end

      -- Combine and display the groups, etc.:
      LuaDialog.Message("Files to be Processed", view_text, LuaDialog.MessageType.Info, LuaDialog.ButtonType.Close):run()
      goto main_prepaste_window
    end

    ------------------------------------------------------------------------------------------------------------------
    ------------------------- Main Pre-Paste Window: Option 3 - Manually Select Files To Use -------------------------
    ------------------------------------------------------------------------------------------------------------------

    -- Code for if "Manually Select Files To Use" was chosen... 
    -- This is perhaps the single best feature in this script (imo).
    -- You can literally fix dead/broken sources, get rid of imported duplicates and redirect to external files for embedding only, etc.:
    if user_choice == "manselect" then

      -- Initial description of what this does, and a dd-menu option to alter immediately-relevant sources OR any source in TSV2:
      local entry_dialog = LuaDialog.Dialog("Manual File Selection", {
        { type = "label", title = "Here you can change the sources used for pasting." },
        { type = "label", title = " " }, -- Spacer
        { type = "heading", title = "⚠ Any manual changes you apply now will:" },
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "• Persist indefinitely unless changed again." },
        { type = "label", title = "• Only affect current and future pastes/regions, not previous ones." },
        { type = "label", title = "• Apply to all pasted regions that once shared the same, original source." },
        { type = "label", title = "• Only impact this current project (unless pre-pasting immediately into another project)." },
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "If proceeding, please choose sensible replacements." },
        { type = "label", title = "(-E.G., if the original source was stereo-in-nature," },
        { type = "label", title = "then DON'T pick a mono file as a replacement.)" },
        { type = "label", title = " " }, -- Spacer
        {type = "dropdown",
          key = "mode",
          title = "Selection Mode",
          values = {
            ["Option 1 - Alter Immediately-Relevant Source(s)"] = "relevant",
            ["Option 2 - Alter Any Saved Source"] = "any"
          }, default = "relevant"
        },
      })
      local result = entry_dialog:run()
      if not result then
        goto main_prepaste_window -- Bail back into the main Pre-Paste window if the dialog failed to show for some reason.
      end

      -- A function to show an interactive file-picker window for each input entry.
      -- Returns a table of collected_overrides, or nil if the user cancels any dialog:
      local function run_manselect_picker_loop(entries)
        
        local collected_overrides = {}
        local total = #entries
        local current_index = 0

        for _, entry in pairs(entries) do -- Initiate a loop over the input entries...
          current_index = current_index + 1
      
          -- Establish the original and currently-selected/"final" source paths (to show in the dialog):
          local original_path = entry.original_source_path or ""
          local final_path = entry.final_source_path or ""
      
          local picker = LuaDialog.Dialog(
            string.format("Select New File (%d/%d)", current_index, total),
            {
              { type = "heading", title = "Original Source File (Type: " .. (entry.original_source_type) .. "):" },
              { type = "label", title = original_path },
              { type = "label", title = " " }, -- Spacer
              { type = "heading", title = "Current (and Preselected) Choice For Source File (Type: " .. (entry.final_source_type) .. "):" },
              { type = "label", title = final_path },              
              { type = "label", title = " " }, -- Spacer
              { type = "file",  key = "new_path", title = "Select Replacement File", path = final_path },
              { type = "dropdown", key = "handling", title = "Select Handling Type", values = {
                  ["Option 1 - Use Automatic File Handling"] = "normal",
                  ["Option 2 - Force Import (Don't Embed)"] = "force_import",
                  ["Option 3 - Force Embed (Don't Import)"] = "force_embed",
                }, default = "Option 1 - Use Automatic File Handling"
              }
            }
          )

          local picker_result = picker:run()
          if not picker_result then return nil end -- Cancels the whole manselect process.
      
          local selected_path = normalize_path(picker_result["new_path"] or "")
          local handling_mode = picker_result["handling"]

          debug_print("Picker result:", selected_path, "vs", final_path)

          if selected_path ~= final_path or handling_mode ~= "normal" then -- We then need to gather info about the (likely) new path...
                                                                           -- Even if all that was changed was forcing an import or embed.

            -- Establish the ucc and uct from the current input entry:
            local used_channel_count = tonumber(entry.used_channel_count)
            local used_channel_type = tonumber(entry.used_channel_type)
      
            -- Determine final_source_location:
            local final_source_location
            if selected_path:match("/interchange/[^/]+/audiofiles/") then
              final_source_location = "IAF"
            elseif selected_path:find(normalize_path(Session:path()), 1, true) then
              final_source_location = "TREE"
            else
              final_source_location = "NIAF"
            end
      
            -- Determine final_source_type:
            local final_source_type = (used_channel_count == 2) and "Stereo" or "Undetermined"
            if used_channel_type == 1 then -- Additional correction if we know the uct = 1 (i.e. right). --------------
              final_source_type = "Stereo"
            end
      
            -- Determine final_io_code:
            local final_io_code = 0 -- Default to 0 (-mostly a placeholder, but technically used by parent/compound/combined regions).
            
            -- DualMono Logic Tag
            if final_source_location == "IAF" then
              local is_dm, lr_type, other_path, _ = detect_dualmono_pair(selected_path) -- Detect if it's of a DM type.
              if is_dm then
                final_io_code = 1
                final_source_type = "DualMono"
                if lr_type == "right" then
                  selected_path = other_path -- Again, for now we always switch to the L-side path if we detected an R-side one of a pair.
                end
              else
                final_io_code = 2 -- A whole mono or stereo file (or a rare and lonely %L or %R file, etc.).
              end

            elseif final_source_location == "TREE" then
              final_io_code = 2 -- Treated the same as IAF mono or stereo (-will find out later).

            elseif final_source_location == "NIAF" then
              final_io_code = 3
            end

            if handling_mode == "force_embed" then -- This overrides normal file-handling to simply attempt an embedding of the chosen file.
              final_io_code = 3
              debug_print("Manselect embed enforced. -> Forcing IO3.")
            end

            if handling_mode == "force_import" then -- Override to enforce importing...
              final_io_code = 2
              debug_print("Manselect import enforced. -> Forcing IO2.")
            end

            -- Determine local_source_path:
            local local_source_path = "Undetermined"
            if final_source_location == "NIAF" then
              local_source_path = get_lsp(selected_path) -- Again, we can set the lsp = fsp immediately for ANY NIAF source.
            end

            -- Store all the data for all the overridden (i.e. manually chosen) sources:
            table.insert(collected_overrides, {
              used_channel_count     = used_channel_count,
              original_source_path   = original_path,
              final_source_location  = final_source_location,
              final_source_type      = final_source_type,
              final_io_code          = final_io_code,
              final_source_path      = selected_path,
              local_source_path      = local_source_path
            })
          end
        end

        return collected_overrides -- Return the data based-on and relevant-to the input entries.
      end -- Ends the function.

      -- Establish a new overrides table:
      local override_changes = {}

      -- If the user picked "Alter Immediately-Relevant Source(s)":
      if result["mode"] == "relevant" then

        if not found_valid_tsv1_data then
          LuaDialog.Message("Nothing Copied!",
            "Nothing is currently copied!\n\nPlease copy regions first.",
            LuaDialog.MessageType.Warning,
            LuaDialog.ButtonType.Close):run()
          return
        end
        
        -- Feed ALL of PP1 into our run_manselect_picker_loop function:
        override_changes = run_manselect_picker_loop(PP1)
        if not override_changes then
          goto main_prepaste_window -- If nothing was changed, then return to the main Pre-Paste window.
        end

      -- If the user picked "Alter Any Saved Source":
      elseif result["mode"] == "any" then

        -- Check to see if TSV2 is in fact blank:
        local has_entries = false
        for _, _ in pairs(tsv2_entries) do
          has_entries = true -- Mark true if there's even one in tsv2_entries.
          break
        end
        
        -- Alert the user if there are none:
        if not has_entries then
          LuaDialog.Message("No Saved Sources!",
            "No sources have been saved to this project yet!\n\nPlease copy regions and successfully pre-paste sources first.",
            LuaDialog.MessageType.Warning,
            LuaDialog.ButtonType.Close):run()
          return
        end

        local seen_osp = {} -- A table for original_source_paths seen.
        -- Loop through tsv2_entries:
        for _, entry in pairs(tsv2_entries) do
          local line = entry.line
          if line and #line == 14 then
            local osp = normalize_path(line[8])
            local ucc = tonumber(line[3])
            local uct = tonumber(line[4])

            local key = osp -- The key here is just the osp.
            local existing = seen_osp[key]

            local keep = false
            if not existing then -- If not already in seen_osp, then...
              keep = true -- Mark to keep it.
            else
              local existing_ucc = tonumber(existing.used_channel_count)
              local existing_uct = tonumber(existing.used_channel_type)

              -- Since the only real *potential* benefit right here (which I don't even think we'll display/use) --------------
              -- is knowing the source TYPE (i.e. Stereo vs Mono or Undetermined), then the preference is different:
              if ucc == 2 and uct == 2 and existing_ucc ~= 2 then
                keep = true -- Prefer the 2 2.
              elseif ucc == 1 and uct == 1 and not (existing_ucc == 2 and existing_uct == 2) then
                keep = true -- Next best is the 1 1 (-also indicates a stereo-in-nature source).
              elseif ucc == 1 and uct == 0 and existing_uct ~= 2 and existing_uct ~= 1 then
                keep = true -- Fallback to 1 0 (-could be a Left OR true Mono).
              end
            end

            if keep then -- If one of the above conditions was met (where keep = true), then *update/replace* the seen_osp[key] accordingly:
              seen_osp[key] = {
                used_channel_count   = tostring(ucc),
                used_channel_type    = tostring(uct),
                original_source_type = line[6] or "Undetermined",
                original_source_path = osp,
                final_source_type    = line[10] or "Undetermined",
                final_source_path    = normalize_path(line[12]),
                final_io_code        = (line[11] or "IO0"):match("%d+") or "0"
              }
            end
          end
        end

        -- A function to split a normalized path into directory components:
        local function split_path_components(path)
          local components = {}
          for part in path:gmatch("[^/]+") do
            table.insert(components, part)
          end
          return components
        end

        -- Build an initial list of entries using seen_osp:
        local all_entries = {}
        for osp, data in pairs(seen_osp) do
          table.insert(all_entries, {
            osp = osp,
            fsp = data.final_source_path,
            data = data,
            label = "",
            osp_parts = split_path_components(osp),
            fsp_parts = split_path_components(data.final_source_path)
          })
        end

        -- A function to create 'labels', such as "Original: /Kick.wav --> Current: /Kick.wav", for each dd-menu entry, --------------
        -- but in a way where if "Original: /Kick.wav --> Current: /Kick.wav" would exist twice (or more times), then we
        -- 'walk back' each a directory until both are obviously different, and thus display them instead as:
        -- Original: /drums/Kick.wav --> Current: /drums/Kick.wav
        -- Original: /samples/Kick.wav --> Current: /session2/Kick.wav ...
        -- -All so that the user can easily differentiate between them, obviously:
        local function build_unique_labels(entries)

          -- Track the 'deepest directory depth' (number of segments) for both osp and fsp across all input entries:
          local max_osp = 0
          local max_fsp = 0

          -- Scan each entry's path 'segments', and update max_osp & max_fsp to capture the longest path seen:
          for _, entry in ipairs(entries) do
            max_osp = math.max(max_osp, #entry.osp_parts)
            max_fsp = math.max(max_fsp, #entry.fsp_parts)
          end

          -- Initialize an empty set to track label uniqueness, and start the search from the 'lowest level' (i.e. 'deepest' segment):
          local seen_labels = {}
          local path_level = 1

          -- At each level of depth, check whether all labels are unique yet:
          while true do
            seen_labels = {}
            local every_label_is_unique = true

            -- Calculate the index for each path segment to use for display, walking "up" from the end (the filename) toward the root as the 'level' increases:
            for _, entry in ipairs(entries) do
              local osp_idx = #entry.osp_parts - path_level + 1
              local fsp_idx = #entry.fsp_parts - path_level + 1

              -- Extract a tail-end portion of each path starting at osp_idx & fsp_idx and join those segments into a partial display path:
              local osp_disp = table.concat({table.unpack(entry.osp_parts, osp_idx)}, "/")
              local fsp_disp = table.concat({table.unpack(entry.fsp_parts, fsp_idx)}, "/")                        

              -- Construct/finalize the label field:
              entry.label = string.format("Original: /%s --> Current: /%s", osp_disp, fsp_disp)

              if seen_labels[entry.label] then -- If this label was already generated for a previous entry, then...
                every_label_is_unique = false -- Mark as not unique.
              end

              seen_labels[entry.label] = true
            end

            -- Exit the loop if all labels are unique, OR if we've walked further 'up' the path than the longest seen (-probably not possible(?)):
            if every_label_is_unique or path_level > math.max(max_osp, max_fsp) then
              break
            end
            -- Otherwise, go one directory 'up' for the next loop, and try again with even longer path segments:
            path_level = path_level + 1
          end
        end

        -- Use that^ function on all_entries to generate our "labels" for the dd-menu:
        build_unique_labels(all_entries)

        -- Further assemble into dropdown-compatible structures:
        local values_table = {}
        local label_map = {}

        for _, entry in ipairs(all_entries) do
          values_table[entry.label] = entry.label
          label_map[entry.label] = entry.data
        end

        local pick_dialog = LuaDialog.Dialog("Select a Source to Modify", {
          { type = "heading", title = "Please select a currently-used source you would like to modify:" },
          { type = "label", title = " " }, -- Spacer
          { type = "dropdown", key = "chosen_source", title = "Saved Source(s)", values = values_table },
          { type = "label", title = " " }, -- Spacer
        })

        local pick_result = pick_dialog:run() -- Run this window.
        if not pick_result then goto main_prepaste_window end -- Bail if the user hit Cancel.

        local selected_label = pick_result["chosen_source"] -- A term for the TSV2 entry picked.
        local selected_entry = label_map[selected_label]

        override_changes = run_manselect_picker_loop({ selected_entry }) -- Pass the selected_entry to run_manselect_picker_loop...
        if not override_changes then
          goto main_prepaste_window -- Bail if the user didn't change anything.
        end
      end

      local changed = #override_changes

      -- Final confirmation:
      local final_confirm = LuaDialog.Dialog("Apply Changes?", {
        { type = "label", title = string.format(
          "You've made changes to %d file(s).\n\nPress OK to apply these changes,\nor Cancel to discard them.",
          changed
        )}
      })

      local final_result = final_confirm:run() -- Run the final dialog.
      if not final_result then
        goto main_prepaste_window -- Bail if the user hits Cancel.
      end

      -- Finally, apply the manually-selected changes to tsv2_entries:
      for _, manselect_entry in ipairs(override_changes) do
        local manselect_entry_ucc = tostring(manselect_entry.used_channel_count)
        local manselect_entry_osp = normalize_path(manselect_entry.original_source_path)
        local manselect_entry_fsp = normalize_path(manselect_entry.final_source_path)
    
        local matched = false
    
        for _, entry in pairs(tsv2_entries) do
          local line = entry.line
          if line and line[3] == manselect_entry_ucc and normalize_path(line[8]) == manselect_entry_osp then -- Match based on ucc and osp...
                                                                                                             -- (-Should just do matching via osp?) --------------
            -- Apply new final_* and local_source_path values, etc.:
            line[9] = manselect_entry.final_source_location
            line[10] = manselect_entry.final_source_type
            line[11] = "IO" .. tostring(manselect_entry.final_io_code)
            line[12] = manselect_entry_fsp
            line[13] = manselect_entry.local_source_path or "Undetermined"
            line[14] = "" -- Clear all cached IDs. --------------
            entry.IDs = {}
    
            debug_print("Manselect override applied for:", manselect_entry_osp, "->", manselect_entry_fsp)
            matched = true -- Mark that a matching TSV2 entry was found and updated.
    
            -- Sync all other variants to reflect this change: --------------
            sync_variants({
              original_source_path  = line[8],
              final_source_path     = line[12],
              final_source_location = line[9],
              final_source_type     = line[10],
              final_io_code         = tonumber(manselect_entry.final_io_code),
              used_channel_count    = tonumber(manselect_entry.used_channel_count)
            }, true)

          end
        end
    
        if not matched then -- Check if a match was made. -If not, then just do a debug_print...
          debug_print("No TSV2 match found during override for:", manselect_entry_osp)
        end
      end
  
      -- Save the changes back to TSV2:
      flush_tsv2()

      -- Clean all Pre-Paste temp. info before restarting (-precautionary):
      tsv2_entries = nil
      PP1_STATE = nil
      PP1 = nil

      reran_wizard = false -- Adding this here just to ensure it doesn't give me any Wizard-related popup...

      goto restart_prepaste
    end

    -----------------------------------------------------------------------------------------------------------------
    ------------------------- Main Pre-Paste Window: Option 4 - Re-Run Source Finder Wizard -------------------------
    -----------------------------------------------------------------------------------------------------------------

    -- Code if "Re-Run Source Finder Wizard" was selected:
    if user_choice == "wizard" then
      reran_wizard = true -- Allows for a new popup to run at the end of Wizard' if no new potential matches are found.
      skip_wizard = false -- Reset this so it won't skip the 'Wizard'.
    
      debug_print("User chose to re-run the Source Finder Wizard.")
      goto restart_prepaste
    end

    ----------------------------------------------------------------------------------------------------
    ------------------------- Main Pre-Paste Window: Option 5 - Erase ID Cache -------------------------
    ----------------------------------------------------------------------------------------------------

    -- If "Erase ID Cache" was chosen from the main Pre-Paste window:
    if user_choice == "erasecache" then

      local num_entries = 0
      for _ in pairs(tsv2_entries) do num_entries = num_entries + 1 end -- Count how many TSV2 entries exist...

      local tsv2_filename = tsv2_path:match("([^/]+)$") or tsv2_path
      local erase_confirm = LuaDialog.Dialog("Erase Region ID Cache", {
        { type = "heading", title = "⚠ WARNING:" },
        { type = "heading", title = "You are about to delete this snapshot's Region ID Cache:" },
        { type = "label", title = tsv2_filename },
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "Currently stored entries: " .. num_entries },
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "This file contains the necessary, saved region" },
        { type = "label", title = "IDs that AudioClipboard uses to create regions" },
        { type = "label", title = "during pasting into this snapshot specifically." },
        { type = "label", title = " " },
        { type = "label", title = "If you suspect it might be damaged," },
        { type = "label", title = "then hit OK to delete it." },
        { type = "label", title = "Otherwise, it is highly recommended" },
        { type = "label", title = "to keep it how it is by hitting Cancel." }
      })

      local confirm_result = erase_confirm:run()
      if not confirm_result then
        goto main_prepaste_window -- Return to the main Pre-Paste window if the user hits Cancel.
      end

      -- If the user hits OK, then delete it:
      local success, err = os.remove(tsv2_path)
      if success then
        LuaDialog.Message(
          "Cache Deleted",
          tsv2_filename .. " has been deleted.\n\nYou may now use Pre-Paste again to generate a fresh\nRegion ID Cache for this snapshot.",
          LuaDialog.MessageType.Info,
          LuaDialog.ButtonType.Close
        ):run()    
      else
        LuaDialog.Message("Deletion Failed", "Error: " .. tostring(err), LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run()
      end
      return  
    end

    if debug_pause and debug_pause_popup("Pre-Paste STEP 10: Initiate the Main Pre-Paste Window and All Other Submenus") then return end

    ---------------------------------------------------------------------------------------------
    ------------------------- Pre-Paste STEP 11: Initiate IO-Processing -------------------------
    ---------------------------------------------------------------------------------------------

    -- Proceed only if chosen to via "Option 1" in the main Pre-Paste window:
    if user_choice ~= "proceed" then return end

      debug_print("-------------- Pre-Paste STEP 11: Initiate IO-Processing --------------")

      -- Initial check if TSV1 was/is empty or not:
      if not found_valid_tsv1_data then
        LuaDialog.Message("No Regions Copied!",
          "Please copy some regions first before proceeding.",
          LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run()
        return
      end

      -- Check: is only a single track selected?
      local sel = Editor:get_selection()
      local track = nil -- Establish a "track" term.
      for r in sel.tracks:routelist():iter() do
        local t = r:to_track()
        if t and not t:isnil() then
          track = t
          break
        end
      end

      -- Bail and warn the user about not having a single track selected:
      if not track or sel.tracks:routelist():size() ~= 1 then
        LuaDialog.Message(
          "No Track Selected!",
          "Please select only a single, valid track, preferably the one you will ultimately paste onto.",
          LuaDialog.MessageType.Warning,
          LuaDialog.ButtonType.Close
        ):run()
        return
      end

      -- Apply local terms for the current track's current playlist, as well as the position of the "transport": --------------
      local playlist = track:playlist()
      local pos_samples = Session:transport_sample()

      -- Define the path to /audiofiles of 'Session B' (-the current session/project):
      local sb_audio_dir = ARDOUR.LuaAPI.build_filename(Session:path(), "interchange", Session:name(), "audiofiles")

      -- Establish our file-copying function:
      local function copy_file(src, dst)
        local fin = io.open(src, "rb"); if not fin then return false end
        local data = fin:read("*a"); fin:close()
        local fout = io.open(dst, "wb"); if not fout then return false end
        fout:write(data); fout:close()
        return true
      end

      -- A function to get region IDs from a playlist:
      local function snapshot_ids(pl)
        local ids = {}
        for r in pl:region_list():iter() do
          local id = r:to_stateful():id():to_s()
          ids[id] = true
        end
        return ids
      end

      -- A function to compare before & after IDs to find the new (single) region:
      local function region_diff(before, after)
        for r in after:iter() do
          local id = r:to_stateful():id():to_s()
          if not before[id] then
            return r, id
          end
        end
        return nil, nil -- If no difference detected, return nils.
      end

      -- A function to make nonconflicting paths; used during copying files into AF of Session B:
      local function make_nonconflicting_path(fsp, sb_audio_dir, suffix) -- The "suffix" option is no longer (currently) used.  It was originally used to append "-L(mono)",
                                                                         -- for example, when this script was making dedicated monos (instead of just using separate_by_channel)...
        local filename = fsp:match("([^/]+)$") or fsp
        local ext = filename:match("(%.[^%.]+)$") or ".wav"
        local base = filename:match("(.+)%.[^%.]+$") or filename
      
        -- Muted this because it was interferring with files, e.g. 141002_0130.wav ----> 141002_.wav (-NOT GOOD!)
        -- For non-DualMono: just strip one trailing -digit(s)
        --base = base:gsub("%-?%d+$", "")
      
        local base_with_suffix = base .. suffix -- Again, an additional "suffix" isn't currently being used. (-But I'll keep this just in case I want to use it sometime later.)
        local candidate = sb_audio_dir .. "/" .. base_with_suffix .. ext
      
        local n = 2 -- Start by adding a -2 (before the extension) if the name already exists in AF of Session B, then -3, -4, and so on, until the filename is safe to use.
        while io.open(candidate, "r") do -- Try to open/read the "candidate" name we have...
          candidate = string.format("%s/%s-%d%s", sb_audio_dir, base_with_suffix, n, ext) -- If taken, mutate the "candidate" name by adding a -2...
          n = n + 1 -- And keep n going higher and higher for every opening/reading of the potential candidate name...
        end
      
        return candidate -- Return the finalized, safe name to use.
      end

      -- Similar to the previous function, but for DualMono pairs and their names:
      -- DualMono Logic Tag
      local function make_nonconflicting_dualmono_paths(L_path, sb_audio_dir) -- Should ALWAYS be fed the left-side path (L_path).

        local ok, _, _, base_with_ext = detect_dualmono_pair(L_path) ----------------
        if not ok then
          error("make_nonconflicting_dualmono_paths() called on a non-DualMono L_path: " .. tostring(L_path)) -- debug_print if something went wrong.
        end

        local base = base_with_ext:match("(.+)%.[^%.]+$") or base_with_ext
        local ext = base_with_ext:match("(%.[^%.]+)$") or ".wav"

        local n = 1
        local new_L, new_R

        -- Attempt new path variants until both Left and Right filenames do not exist (and thus are safe to use):
        repeat
          local suffix = (n == 1) and "" or "-" .. n -- No "suffix" for the first try; then append -2, -3, etc...
          new_L = string.format("%s/%s%s%%L%s", sb_audio_dir, base, suffix, ext)
          new_R = string.format("%s/%s%s%%R%s", sb_audio_dir, base, suffix, ext)
          n = n + 1
        until not (io.open(new_L, "rb") or io.open(new_R, "rb")) -- "rb" = open the file in read-only binary mode.

        return new_L, new_R -- Return the safe names.
      end

      -- A function to check if a certain entry (given a ucc & fsp input) exists:
      local function check_if_existing(ucc, pp1_entry_fsp)
        for _, entry in pairs(tsv2_entries) do
          local line = entry.line
          if line
            and line[3] == tostring(ucc)
            and normalize_path(line[12]) == normalize_path(pp1_entry_fsp)
            and #entry.IDs > 0
          then
            return entry.IDs, line[13] -- Return IDs and the lsp.
          end
        end
        return nil, nil
      end

      -- A function to save ONLY a determined lsp (local_source_path) into matching TSV2 entries:
      local function save_lsp(path, new_lsp, used_channel_type, channel_count_override)
        local final_path = normalize_path(path)
        local channel_count = channel_count_override or used_channel_count
      
        local match_count = 0
        for _, entry in pairs(tsv2_entries) do
          local line = entry.line
          if line
            and line[3] == tostring(channel_count)
            and line[4] == tostring(used_channel_type)
            and normalize_path(line[12]) == final_path
          then
            if new_lsp and new_lsp ~= "Undetermined" and line[13] ~= new_lsp then
              line[13] = new_lsp -- Apply the lsp.
              debug_print("save_lsp: Saved new lsp to matching entry:", new_lsp)
              match_count = match_count + 1
            end
          end
        end
      
        if match_count == 0 then -- Use match_count for a debug_print:
          debug_print("save_lsp: No matching TSV2 entries (count/type/fsp).")
        end
      end

      -- A function to save ONLY a captured ID into matching TSV2 entries:
      local function save_id(path, id_str, used_channel_type, channel_count_override)
        local final_path = normalize_path(path)
        local channel_count = channel_count_override or used_channel_count
      
        local match_count = 0
        for _, entry in pairs(tsv2_entries) do
          local line = entry.line
          if line
            and line[3] == tostring(channel_count)
            and line[4] == tostring(used_channel_type)
            and normalize_path(line[12]) == final_path
          then
            -- Only add the ID if not already present:
            local already_has = false
            for _, existing in ipairs(entry.IDs) do
              if existing == id_str then
                already_has = true
                break
              end
            end
            if not already_has then
              table.insert(entry.IDs, id_str) -- Insert the ID.
              debug_print("save_id: Saved new ID to matching entry:", id_str)
              match_count = match_count + 1
            end
          end
        end
      
        if match_count == 0 then -- Use match_count for a debug_print:
          debug_print("save_id: No matching TSV2 entries (count/type/fsp).")
        end
      end

      -- A function to wipe/clear all (presumably stale) IDs from any 2 2 entry in tsv2_entries of a given path:
      local function wipe_stereo_ids(pp1_entry_fsp)
        local wiped = false
        for key, entry in pairs(tsv2_entries) do
          local line = entry.line
          if line[3] == "2" and line[4] == "2" and normalize_path(line[8]) == normalize_path(pp1_entry_fsp) then
            entry.IDs = {}
            entry.line[14] = "Undetermined"
            wiped = true
            debug_print("wipe_stereo_ids: WIPED 2|2 entry for:", pp1_entry_fsp)
          end
        end
        return wiped
      end
      
      -- Function to update source types in TSV1 and TSV2:
      local function update_source_type(pp1_entry_fsp, new_type)
        local updated_lines = {}

        for line in io.lines(tsv1_path) do
          if line:match("^origin_session") or line:match("^%s*$") then
            -- Skip header and blank lines...
          else
            local fields = {}
            for f in line:gmatch("([^\t]*)\t?") do table.insert(fields, f) end

            if #fields == 45 and normalize_path(fields[8]) == normalize_path(pp1_entry_fsp) then -- If the TSV1 entry's osp = fsp of the input, then... --------------
              local osp = normalize_path(fields[8])
              local fsp = normalize_path(fields[12])

              if osp == fsp and fields[6] == "Undetermined" then -- If the TSV1 entry's osp = TSV1 entry's fsp, and if somehow(?) the ost = "Undetermined", then... --------------
                debug_print("Updating TSV 1: setting original_source_type to '" .. new_type .. "'")
                fields[6] = new_type -- Update the TSV1 entry's ost to the new_type input.
              end

              if fields[10] == "Undetermined" then -- If fst is "Undetermined", then...
                debug_print("Updating TSV 1: setting final_source_type to '" .. new_type .. "'")
                fields[10] = new_type -- Update the fst.
              end
            end

            table.insert(updated_lines, table.concat(fields, "\t")) -- Insert the line(s) (changed or unchanged) into updated_lines.
          end
        end

        flush_tsv1(updated_lines) -- Update the actual TSV1 file.

        -- tsv2_entries update (-no need to 'flush' here):
        for _, entry in pairs(tsv2_entries) do
          local line = entry.line
          local fsp = normalize_path(line[12])
          local osp = normalize_path(line[8])

          if osp == fsp and line[6] == "Undetermined" then
            debug_print("Updating TSV 2: setting original_source_type to '" .. new_type .. "'")
            line[6] = new_type -- Update the ost.
          end
        
          if fsp == normalize_path(pp1_entry_fsp) then
            if line[10] == "Undetermined" then
              debug_print("Updating TSV 2: setting final_source_type to '" .. new_type .. "'")
              line[10] = new_type -- Update the fst.
            end
          end
        end        
      end

      -- Introducing this table here provides a new 'strategy' for dealing with unwanted regions on the timeline after IO processing.
      -- It prevents spamming Ardour with repeated "playlist:remove_region(region)" actions that were previously peppered throughout the IOs, which caused A LOT of crashing.
      -- We basically catalog ONLY the new regions manifested, and then delete ONLY those at the end of ALL IO processing.
      -- And no, utilizing Session:abort_reversible_command() to let Ardour take care of erasure proved difficult, and PERHAPS literally impossible...
      -- So for now, we'll use this (-which so far has been 100% reliable):
      local region_ids_to_remove = {}

      -- Establish a local term for creating 'vectors' of file-paths (for when using do_embed on sources):
      local C = C or {}
      C.StringVector = C.StringVector or ARDOUR.LuaAPI.CppStringVector

      -- A shortcut to successfully access ImportMergeFiles, ImportToTrack, etc.:
      local Editing = Editing or LuaAPI.Editing

      -- Initiate Import Option (IO) logic for each PP1 entry:
      for _, entry in pairs(PP1) do

        if entry.skip then goto next_entry end -- Skip entries marked as such.

        -- Establish some common terms for the current PP1 entry, etc.:
        local pp1_entry_ucc = tonumber(entry.used_channel_count)
        local pp1_entry_fsp = entry.final_source_path
        local pp1_entry_ioc = tonumber(entry.final_io_code) -- Here we don't care about the original_io_code ever, so there's no need to call it fioc (for *final*_io_code).

        -------------------------------------------------------------------------------------------------------------
        ------------------------- IMPORT OPTION 1 (IO1): ucc = 1 or 2, IAF, DualMono Source -------------------------
        -------------------------------------------------------------------------------------------------------------

        if pp1_entry_ioc == 1 then

          local region, id
          local L_path = pp1_entry_fsp -- This should always be the %L or -L variant.
          local R_path = select(3, detect_dualmono_pair(pp1_entry_fsp)) -- Get our right-side path from the 3rd output of our universal DualMono detection function.

          if pp1_entry_ucc == 2 then

            local ok, err = pcall(function()
              debug_print("IO1: Stereo DualMono IAF. Performing copy+merge for:", L_path)

              local before_ids = snapshot_ids(playlist) -- Take a 'snapshot' of the current IDs seen.

              -- DualMono Logic Tag
              local new_L, new_R = make_nonconflicting_dualmono_paths(L_path, sb_audio_dir) -- Make nonconflicting DM paths given the L_path and this session's /audiofiles/ folder.
              copy_file(L_path, new_L) -- Copy the original, left-side file into this session's /audiofiles/ whilst renaming it to the determined-safe name.
              copy_file(R_path, new_R) -- Same, but for the right-side file.
              
              local dualmono_files = C.StringVector()
              dualmono_files:push_back(new_L)
              dualmono_files:push_back(new_R)              

              Editor:do_embed( -- Embed the pair.
                dualmono_files,
                Editing.ImportMergeFiles, -- Instruct Ardour to merge the pair as a single, stereo source.
                Editing.ImportToTrack,
                Temporal.timepos_t(pos_samples),
                ARDOUR.PluginInfo(),
                track)              

              region, id = region_diff(before_ids, playlist:region_list()) -- Get the new region ID by comparing our 'before snapshot' with what currently exists in the playlist.
              if not region then
                error("IO1 failed: merged stereo region not detected!")
              end

              local lsp = get_lsp(region:source(0):to_filesource():path()) -- Get the local_source_path from the actual, finalized path of the region.
              save_lsp(L_path, lsp, 2, 2) -- Save the lsp to tsv2_entries.
              save_id(L_path, id, 2, 2) -- Save the ID to tsv2_entries.

              table.insert(region_ids_to_remove, id) -- Save this region's ID to remove it later.
            end)
            if not ok then debug_print("IO1 failed (ucc=2):", err) end

          elseif pp1_entry_ucc == 1 then

            -- Immediately (and only once) make sure a trio of entries exist (1 0, 1 1, 2 2) for this DualMono pair:
            ensure_variants(entry) -- 99% certain this is 100% redundant at this point. --------------

            local restart = false
            ::restart::

            local ok1, err1 = pcall(function()

              -- Check if a '2 2' DM entry already exists with IDs so as to avoid duplicate importing:
              local stereo_ids, stereo_lsp = check_if_existing(2, pp1_entry_fsp) -- Must be fed exactly "pp1_entry_fsp" to work, NOT "L_path".
              
              if (not stereo_lsp) or (stereo_ids == "Undetermined") then -- If it doesn't exist yet, then...

                restart = false

                -- Do a fresh copy of the pair, and merge them, etc.:
                debug_print("IO1: No stereo in TSV2 yet (ucc=1). Performing import+merge for:", L_path)

                local before_ids = snapshot_ids(playlist) -- Do an ID 'before snapshot'.

                -- DualMono Logic Tag
                local new_L, new_R = make_nonconflicting_dualmono_paths(L_path, sb_audio_dir) -- All similar notes as before...
                copy_file(L_path, new_L)
                copy_file(R_path, new_R)
                
                local dualmono_files = C.StringVector()
                dualmono_files:push_back(new_L)
                dualmono_files:push_back(new_R)                

                Editor:do_embed(
                  dualmono_files,
                  Editing.ImportMergeFiles,
                  Editing.ImportToTrack,
                  Temporal.timepos_t(pos_samples),
                  ARDOUR.PluginInfo(),
                  track)                

                region, id = region_diff(before_ids, playlist:region_list())
                if not region then
                  error("IO1 failed: merged stereo region not detected!")
                end

                local lsp = get_lsp(region:source(0):to_filesource():path())
                save_lsp(L_path, lsp, 2, 2)
                save_id(L_path, id, 2, 2)

                table.insert(region_ids_to_remove, id)
              
              elseif stereo_lsp and stereo_ids and #stereo_ids > 0 then -- If the DM entry DOES already exist in tsv2_entries, then...

                -- If no region was needing copying + embedding this pass, we still need to manifest one to use
                -- separate_by_channel on for our monos creation.  Thus, try manifesting one from known '2 2' IDs:
                if not region and stereo_ids and #stereo_ids > 0 then
                  for _, try_id in ipairs(stereo_ids) do
                    local region_obj = ARDOUR.RegionFactory.region_by_id(PBD.ID(try_id)) -- Try manifesting a region based on an ID in the given IDs list.
                    if region_obj and not region_obj:isnil() then -- If a valid region appeared, then...
                      region = region_obj -- Save it as such...
                      id = try_id -- And its valid ID.
                      debug_print("IO1: Successfully retrieved region by 2 2 ID:", id)
                      break
                    end
                  end

                  -- If none of the '2 2' IDs were valid (due to source-deletions by the user, or whatever), wipe them from tsv2_entries and bail this sub-process:
                  if not region then
                    debug_print("IO1: All 2 2 region IDs were stale, wiping from TSV2...")
                    wipe_stereo_ids(pp1_entry_fsp) -- Feed it "pp1_entry_fsp" here (-even though L_path = pp1_entry_fsp, "pp1_entry_fsp" specifically has to be the input)...

                    -- Mark to restart in a moment:
                    restart = true
                  end
                end

              end
            end)
            if not ok1 then debug_print("IO1 failed: merge step (ucc=1):", err1); return end

            -- Redo the previous code to trigger a fresh copy + do_embed (since the IDs for the '2 2' entry were all invalid, apparently):
            if restart then goto restart end

            -- Now, manifest our needed mono (-L/-R) variants:
            local ok_sep, err_sep = pcall(function()

              local ar = region:to_audioregion()
              if not ar or ar:isnil() then error("IO1: Cannot convert to AudioRegion") end

              -- "separate_by_channel" is equivalent to "Make Mono Regions" in the DAW...
              -- And I wish I had known about it sooner... -_____-
              local out = ARDOUR.RegionVector()
              ar:separate_by_channel(out)

              if out:size() < 2 then error("IO1: separate_by_channel returned < 2 results") end -- Check if two resulting regions were given.

              local rL = out:at(0)
              local rR = out:at(1)

              -- Save the -L mono variant info:
              if rL and not rL:isnil() then
                local idL = rL:to_stateful():id():to_s()
                local lspL = get_lsp(rL:source(0):to_filesource():path())
                save_lsp(pp1_entry_fsp, lspL, 0, 1)
                save_id(pp1_entry_fsp, idL, 0, 1)
              end

              -- Save the -R mono variant info:
              if rR and not rR:isnil() then
                local idR = rR:to_stateful():id():to_s()
                local lspR = get_lsp(rR:source(0):to_filesource():path())
                save_lsp(pp1_entry_fsp, lspR, 1, 1)
                save_id(pp1_entry_fsp, idR, 1, 1)
              end

            end)
            if not ok_sep then debug_print("IO1 stereo_confirmed: split failed:", err_sep) end

          end -- The ucc condition block ends.

        ---------------------------------------------------------------------------------------------------------------------------
        ------------------------- IMPORT OPTION 2 (IO2): ucc = 1 or 2, IAF or TREE, Mono or Stereo Source -------------------------
        ---------------------------------------------------------------------------------------------------------------------------

        elseif pp1_entry_ioc == 2 then

          local region, id

          if pp1_entry_ucc == 2 then -- This is the simpler case: confirmed stereo -> copy the file then use do_embed.

            local ok, err = pcall(function()
              local new_path = make_nonconflicting_path(entry.final_source_path, sb_audio_dir, "") -- Generate a new, non-conflicting path.
              if not new_path then
                debug_print("IO2: make_nonconflicting_path() returned nil")
                return
              end

              copy_file(pp1_entry_fsp, new_path) -- Copy the file into this session's /audiofiles/ and mutate the name to the safe name determined.

              local embed = C.StringVector()
              embed:push_back(new_path)
              local before_ids = snapshot_ids(playlist)

              Editor:do_embed(
                embed,
                Editing.ImportAsTrack,
                Editing.ImportToTrack, -- Now embed it.
                Temporal.timepos_t(pos_samples),
                ARDOUR.PluginInfo(),
                track)

              region, id = region_diff(before_ids, playlist:region_list())
              if not region then
                debug_print("IO2: No region found after embed")
                return
              end

              local lsp = get_lsp(region:source(0):to_filesource():path())
              save_lsp(pp1_entry_fsp, lsp, 2, 2)
              save_id(pp1_entry_fsp, id, 2, 2)

              table.insert(region_ids_to_remove, id)
            end)
            if not ok then debug_print("IO2 (ucc=2) failed:", err) end

          elseif pp1_entry_ucc == 1 then -- Just a TAD bit more complicated...

            local restart = false
            local restart_count = 0
            ::restart::
            
            restart_count = restart_count + 1
            if restart_count > 5 then -- Was necessary during debugging to end an infinite loop. (-Also good to have this in general.)
              debug_print("IO2: Maximum restarts (5) reached - aborting to prevent infinite loop.")
              return
            end
            
            local ok2, err2 = pcall(function()
          
              -- Check if a corresponding '2 2' Stereo entry already exists in tsv2_entries:
              local stereo_ids, stereo_lsp = check_if_existing(2, pp1_entry_fsp)

              -- If no matching stereo entry OR stereo entry exists but has no IDs:
              if (not stereo_lsp) or (stereo_ids == "Undetermined") then

                restart = false
          
                -- Probe the number of channels 'manually' via do_embed:
                local new_path = make_nonconflicting_path(entry.final_source_path, sb_audio_dir, "")
                if not new_path then
                  debug_print("IO2: ucc=1 (no stereo match): make_nonconflicting_path() returned nil")
                  return
                end
          
                copy_file(pp1_entry_fsp, new_path)
          
                local embed = C.StringVector()
                embed:push_back(new_path)
                local before_ids = snapshot_ids(playlist)

                Editor:do_embed(
                  embed,
                  Editing.ImportAsTrack,
                  Editing.ImportToTrack,
                  Temporal.timepos_t(pos_samples),
                  ARDOUR.PluginInfo(),
                  track)
          
                region, id = region_diff(before_ids, playlist:region_list())
                if not region then
                  debug_print("IO2 (ucc=1): No region after embed")
                  return
                end
          
                local ar = region:to_audioregion()
                if not ar or ar:isnil() then
                  debug_print("IO2 (ucc=1): Region not valid AudioRegion")
                  return
                end
          
                local ch = ar:n_channels() -- Check the number of audio channels.
                local lsp = get_lsp(ar:source(0):to_filesource():path())
          
                if ch == 1 then
                  -- It was truly just a mono source...
                  save_lsp(pp1_entry_fsp, lsp, 0, 1)
                  save_id(pp1_entry_fsp, id, 0, 1)
          
                  if entry.original_source_path == entry.final_source_path then
                    update_source_type(pp1_entry_fsp, "Mono") -- Update various source types to reflect this new knowledge.
                  end
          
                  table.insert(region_ids_to_remove, id) -- Save the ID to remove this region later on.
                  return
          
                elseif ch == 2 then
                  -- It's actually stereo after all!
                  stereo_confirmed = true -- Mark as such.

                  ensure_variants(entry) -- Must ensure that a '2 2' entry is available to accept an lsp and id.
                
                  save_lsp(pp1_entry_fsp, lsp, 2, 2)
                  save_id(pp1_entry_fsp, id, 2, 2) -- Save the ID!
          
                  table.insert(region_ids_to_remove, id)
                end
          
              -- But if the stereo entry *already exists* and has at least one ID, then:
              elseif stereo_lsp and stereo_ids and #stereo_ids > 0 then

                -- Set this to divert later in a moment:
                stereo_confirmed = true

                -- If no region was embedded this pass but stereo is confirmed, try manifesting one from known '2 2' IDs (-all like in IO1):
                if not region and stereo_ids and #stereo_ids > 0 then
                  for _, try_id in ipairs(stereo_ids) do
                    local region_obj = ARDOUR.RegionFactory.region_by_id(PBD.ID(try_id))
                    if region_obj and not region_obj:isnil() then
                      region = region_obj -- Again, if a valid region via ID is manifested, save it as so to use for mono creation soon...
                      id = try_id
                      debug_print("IO2: Successfully retrieved region by 2 2 ID:", id)
                      break
                    end
                  end

                  -- If none of the '2 2' IDs were valid, wipe them from tsv2_entries and bail this sub-process:
                  if not region then
                    debug_print("IO2: All 2 2 region IDs were stale, wiping from TSV2...")
                    wipe_stereo_ids(pp1_entry_fsp)

                    -- Mark to restart in a moment:
                    restart = true
                  end
                end

                -- Ensure trio exists in TSV2 before continuing:
                ensure_variants(entry)

              end
            end)
            if not ok2 then debug_print("IO2 (ucc=1 part 1) failed:", err2); return end

            -- Redo the previous code to trigger a fresh copy + do_embed (since the IDs for the '2 2' entry were all invalid, apparently):
            if restart then goto restart end

            -- If the source file was indeed whole Stereo, then standard -L/-R mono variants must now be manifested:
            if stereo_confirmed then

              -- Generate mono variants from the embedded stereo region itself:
              local ok_sep, err_sep = pcall(function()

                local ar = region:to_audioregion()
                if not ar or ar:isnil() then error("IO2: Cannot convert to AudioRegion") end

                local out = ARDOUR.RegionVector()
                ar:separate_by_channel(out)

                if out:size() < 2 then error("IO2: separate_by_channel returned < 2 results") end

                local rL = out:at(0)
                local rR = out:at(1)

                -- Save the -L mono variant info:
                if rL and not rL:isnil() then
                  local idL = rL:to_stateful():id():to_s()
                  local lspL = get_lsp(rL:source(0):to_filesource():path())
                  save_lsp(pp1_entry_fsp, lspL, 0, 1)
                  save_id(pp1_entry_fsp, idL, 0, 1)
                end

                -- Save the -R mono variant info:
                if rR and not rR:isnil() then
                  local idR = rR:to_stateful():id():to_s()
                  local lspR = get_lsp(rR:source(0):to_filesource():path())
                  save_lsp(pp1_entry_fsp, lspR, 1, 1)
                  save_id(pp1_entry_fsp, idR, 1, 1)
                end

              end)
              if not ok_sep then debug_print("IO2 stereo_confirmed: split failed:", err_sep) end

              -- Stereo is now confirmed, thus update the source types in the TSVs:
              update_source_type(pp1_entry_fsp, "Stereo")

            end
          end

        --------------------------------------------------------------------------------------------------------------------
        ------------------------- IMPORT OPTION 3 (IO3): ucc = 1 or 2, NIAF, Mono or Stereo Source -------------------------
        --------------------------------------------------------------------------------------------------------------------

        -- Now, I know that this IO is VERY similar to IO2...
        -- But I decided to not merge it with IO2 so as to easily differentiate between NIAF (or forced-embedding) cases, and IAF/TREE cases.
        -- Also, I put minimal --muted notes here, because it's so similar to IO2:

        elseif pp1_entry_ioc == 3 then

          local region, id

          if pp1_entry_ucc == 2 then

            local ok, err = pcall(function()

              local embed = C.StringVector()
              embed:push_back(pp1_entry_fsp)
              local before_ids = snapshot_ids(playlist)

              Editor:do_embed(
                embed,
                Editing.ImportAsTrack,
                Editing.ImportToTrack,
                Temporal.timepos_t(pos_samples),
                ARDOUR.PluginInfo(),
                track)
            
              region, id = region_diff(before_ids, playlist:region_list())
              if not region then
                debug_print("IO3: No region found after embed")
                return
              end
            
              local lsp = get_lsp(region:source(0):to_filesource():path())
              save_lsp(pp1_entry_fsp, lsp, 2, 2)
              save_id(pp1_entry_fsp, id, 2, 2)
            
              table.insert(region_ids_to_remove, id)
            end)
            if not ok then debug_print("IO3 (ucc=2) failed:", err) end          

          elseif pp1_entry_ucc == 1 then

            local stereo_confirmed = false
            local restart = false
            ::restart::
          
            local ok3, err3 = pcall(function()

              local stereo_ids, stereo_lsp = check_if_existing(2, pp1_entry_fsp)
          
              -- No matching stereo entry OR stereo entry exists but has no IDs:
              if (not stereo_lsp) or (stereo_ids == "Undetermined") then

                restart = false
          
                -- Probe the number of channels 'manually' via do_embed:
                local embed = C.StringVector()
                embed:push_back(pp1_entry_fsp)
                local before_ids = snapshot_ids(playlist)

                Editor:do_embed(
                  embed,
                  Editing.ImportAsTrack,
                  Editing.ImportToTrack,
                  Temporal.timepos_t(pos_samples),
                  ARDOUR.PluginInfo(),
                  track)              
          
                region, id = region_diff(before_ids, playlist:region_list())
                if not region then
                  debug_print("IO3 (ucc=1): No region after embed")
                  return
                end
          
                local ar = region:to_audioregion()
                if not ar or ar:isnil() then
                  debug_print("IO3 (ucc=1): Region not valid AudioRegion")
                  return
                end
          
                local ch = ar:n_channels()
                local lsp = get_lsp(ar:source(0):to_filesource():path())
          
                if ch == 1 then
                  -- It was truly mono...
                  save_lsp(pp1_entry_fsp, lsp, 0, 1)
                  save_id(pp1_entry_fsp, id, 0, 1)
          
                  if entry.original_source_path == entry.final_source_path then
                    update_source_type(pp1_entry_fsp, "Mono")
                  end
          
                  table.insert(region_ids_to_remove, id)
                  return
          
                elseif ch == 2 then
                  -- It's actually stereo after all!
                  stereo_confirmed = true

                  ensure_variants(entry)
          
                  save_lsp(pp1_entry_fsp, lsp, 2, 2)
                  save_id(pp1_entry_fsp, id, 2, 2)
          
                  table.insert(region_ids_to_remove, id)
                end
          
              -- The stereo entry *already exists* and has at least one ID:
              elseif stereo_lsp and stereo_ids and #stereo_ids > 0 then

                stereo_confirmed = true

                if not region and stereo_ids and #stereo_ids > 0 then
                  for _, try_id in ipairs(stereo_ids) do
                    local region_obj = ARDOUR.RegionFactory.region_by_id(PBD.ID(try_id))
                    if region_obj and not region_obj:isnil() then
                      region = region_obj
                      id = try_id
                      debug_print("IO3: Successfully retrieved region by 2 2 ID:", id)
                      break
                    end
                  end

                  if not region then
                    debug_print("IO3: All 2 2 region IDs were stale, wiping from TSV2...")
                    wipe_stereo_ids(pp1_entry_fsp)

                    restart = true
                  end
                end

                ensure_variants(entry)

              end
            end)
            if not ok3 then debug_print("IO3 (ucc=1 part 1) failed:", err3); return end
          
            -- Again, redo the previous code to trigger a fresh copy + do_embed:
            if restart then goto restart end

            -- If the source file was indeed whole Stereo, then standard -L/-R mono variants must now be manifested...
            -- This is all the same as in IO2:
            if stereo_confirmed then

              local ok_sep, err_sep = pcall(function()

                local ar = region:to_audioregion()
                if not ar or ar:isnil() then error("IO3: Cannot convert to AudioRegion") end

                local out = ARDOUR.RegionVector()
                ar:separate_by_channel(out)

                if out:size() < 2 then error("IO3: separate_by_channel returned < 2 results") end

                local rL = out:at(0)
                local rR = out:at(1)

                if rL and not rL:isnil() then
                  local idL = rL:to_stateful():id():to_s()
                  local lspL = get_lsp(rL:source(0):to_filesource():path())
                  save_lsp(pp1_entry_fsp, lspL, 0, 1)
                  save_id(pp1_entry_fsp, idL, 0, 1)
                end

                if rR and not rR:isnil() then
                  local idR = rR:to_stateful():id():to_s()
                  local lspR = get_lsp(rR:source(0):to_filesource():path())
                  save_lsp(pp1_entry_fsp, lspR, 1, 1)
                  save_id(pp1_entry_fsp, idR, 1, 1)
                end

              end)
              if not ok_sep then debug_print("IO3 stereo_confirmed: split failed:", err_sep) end

              update_source_type(pp1_entry_fsp, "Stereo")
        
            end
          end
        end

        ::next_entry:: -- Processing skips to here if a PP1 entry was marked to be skipped, thus the loop continues to the next entry...

      end -- Ends our main IO-Processing loop, i.e. "for _, entry in pairs(PP1) do".

      if debug_pause and debug_pause_popup("Pre-Paste STEP 11: Initiate IO-Processing") then return end

      ---------------------------------------------------------------------------------------------------------------------------------------------------------
      ------------------------- Pre-Paste STEP 12: Save the IO-Processing Results, Message the User, and Delete Any Temporary Regions -------------------------
      ---------------------------------------------------------------------------------------------------------------------------------------------------------

      debug_print("-------------- Pre-Paste STEP 12: Save the IO-Processing Results, Message the User, and Delete Any Temporary Regions --------------")

      -- 'Flush' the updated entries (in tsv2_entries) back to the actual TSV2 file:
      flush_tsv2()

      -- Save the session now so if it crashes during region removal then at least all the sources should still be present in the snapshot when you re-open it:
      Session:save_state("", false, false, false, false, false)

      -- DEBUG: Show regions queued for removal:
      debug_print("--- DEBUG: region_ids_to_remove contents ---")
      for i, id in ipairs(region_ids_to_remove or {}) do
        debug_print(string.format("Region ID [%d]: %s", i, tostring(id)))
      end

      -- It's absolutely CRUCIAL here to introduce this popup BEFORE the region-deletion loop...
      -- Not doing so meant that some internal state(s) was(/were) 'hanging' (even after using Session:save_state), or something else...
      -- And thus jumping immediately into the loop would sometimes (for some snapshots) crash Ardour ~50% of the time(!): o___o
      if not skip_final_message then
        LuaDialog.Message(
          "Pre-Paste Successful!",
          "All files have been appropriately processed and are ready for pasting!\n\n" ..
          "This script will now remove any temporary regions from the timeline...",
          LuaDialog.MessageType.Info,
          LuaDialog.ButtonType.Close
        ):run()
      end

      -- And NOW delete any and all regions whose IDs were logged for removal:
      for _, id in ipairs(region_ids_to_remove) do
        local region = ARDOUR.RegionFactory.region_by_id(PBD.ID(id))
        if region and not region:isnil() then
          local pl = region:playlist()
          if pl and not pl:isnil() then
            pl:remove_region(region)
            debug_print("Removed region with ID:", id)
          end
        else
          debug_print("Could not resolve region ID:", id)
        end
      end

    if debug_pause and debug_pause_popup("Pre-Paste STEP 12: Save the IO-Processing Results, Message the User, and Delete Any Temporary Regions") then return end

    return

  end -- Ends "if action == "prepaste" then".

  -----------------------------------------------------------------------------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------
  ------------------------------------------------------ PASTE LOGIC ----------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------
  -----------------------------------------------------------------------------------------------------------------------------

  if action == "paste" then

    -- Establish our paths to our TSV files:
    local tsv1_path = ARDOUR.LuaAPI.build_filename(get_temp_dir(), "AudioClipboard.tsv")
    local tsv2_path = ARDOUR.LuaAPI.build_filename(Session:path(), "interchange", Session:name(), "AudioClipboard_IDs_(" .. local_snapshot_name .. ").tsv")

    ---------------------------------------------------------------------------------------
    ------------------------- Paste STEP 0: Initial Checks/Guards -------------------------
    ---------------------------------------------------------------------------------------

    debug_print("-------------- Paste STEP 0: Initial Checks/Guards --------------")

    -- Guard: make sure TSV 1 exists:
    local f1 = io.open(tsv1_path, "r")
    if not f1 then
      LuaDialog.Message("Missing Clipboard!",
        "No clipboard data found.\n\nDid you Copy Regions first?",
        LuaDialog.MessageType.Warning,
        LuaDialog.ButtonType.Close):run()
      return
    else
      f1:close()
    end

    -- Check: is only a single track selected?
    local sel = Editor:get_selection()
    local track = nil
    for r in sel.tracks:routelist():iter() do
      local t = r:to_track()
      if t and not t:isnil() then
        track = t
        break
      end
    end

    -- Bail and warn the user about not having a single track selected:
    if not track or sel.tracks:routelist():size() ~= 1 then
      LuaDialog.Message(
        "Track Improperly Selected!",
        "Please select only a single audio track to paste onto.",
        LuaDialog.MessageType.Warning,
        LuaDialog.ButtonType.Close
      ):run()
      return
    end

    -- Check if the selected track has a valid playlist to paste onto/into:
    local playlist = track:playlist()
    if not playlist or playlist:isnil() then
      LuaDialog.Message("No Playlist", "Selected track has no valid playlist.", LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run()
      return
    end

    if debug_pause and debug_pause_popup("Paste STEP 0: Initial Checks/Guards") then return end

    ------------------------------------------------------------------------------------
    ------------------------- Paste STEP 1: Load the TSV Files -------------------------
    ------------------------------------------------------------------------------------

    debug_print("-------------- Paste STEP 1: Load the TSV Files --------------")

    -- Load TSV1 into a temp. table:
    local clipboard = {}

    for line in io.lines(tsv1_path) do
      if line:match("^origin_session") or line:match("^%s*$") then
        -- Skip the header and blank lines...
      else
        local fields = {}
        for field in line:gmatch("([^\t]*)\t?") do table.insert(fields, field) end
        
        if #fields == 45 then
          -- Insert all the necessary fields for successful pasting (into "clipboard")...
          -- If you want some basic info about any of these, check around line 60 towards the top of this script:
          table.insert(clipboard, {
            used_channel_count   = fields[3],
            used_channel_type    = fields[4],
            -- Skip entries...
            original_source_path = normalize_path(fields[8]),
            -- Skip entries...
            final_source_path    = normalize_path(fields[12]),
            start_spl            = tonumber(fields[13]),
            position_spl         = tonumber(fields[14]),
            length_spl           = tonumber(fields[15]),
            gain_and_polarity    = tonumber(fields[16]),
            envelope             = fields[17],
            envelope_state       = fields[18],
            fade_in_spl          = tonumber(fields[19]) or 64,
            fade_out_spl         = tonumber(fields[20]) or 64,
            fade_in_shape        = fields[21],
            fade_out_shape       = fields[22],
            fade_in_type         = fields[23],
            fade_out_type        = fields[24],
            fade_in_state        = fields[25],
            fade_out_state       = fields[26],
            mute_state           = fields[27],
            opaque_state         = fields[28],
            lock_state           = fields[29],
            sync_position        = tonumber(fields[30]),
            fade_before_fx       = fields[31],
            original_name        = fields[32],
            -- Skip entry...
            is_compound_parent   = fields[34],
            parent_id            = fields[35],
            -- Skip entry...
            is_compound_child    = fields[37],
            childs_parents_id    = fields[38],
            -- Skip entries...
            siblings_total       = tonumber(fields[43]),
            sibling_number       = tonumber(fields[44]),
            compound_layer       = fields[45]
          })
        end
      end
    end

    -- Load TSV2 and build a map:
    local id_map = {}

    local tsv2_file_read = io.open(tsv2_path, "r")
    if tsv2_file_read then
      for line in tsv2_file_read:lines() do
        if line:match("^local_session") or line:match("^%s*$") then
          -- Skip the header and blank lines...
        else
          local fields = {}
          for field in line:gmatch("([^\t]*)\t?") do table.insert(fields, field) end
          if #fields == 14 then
            local key = string.format("%s|%s|%s|%s", -- Establish the key.
              fields[3],
              fields[4],
              normalize_path(fields[8]),
              normalize_path(fields[12])
            )
            if fields[14] == "Undetermined" then -- Catches and does not include any where the IDs field is still sitting at "Undetermined".
              debug_print("One needed TSV2 entry still has IDs sitting at \"Undetermined\"!")
            else
              id_map[key] = {}
              for id in fields[14]:gmatch("[^,]+") do
                table.insert(id_map[key], id)
              end
            end
          end
        end
      end
      tsv2_file_read:close()
    end

    if debug_pause and debug_pause_popup("Paste STEP 1: Load the TSV Files") then return end

    -----------------------------------------------------------------------------------------------------------------
    ------------------------- Paste STEP 2: Check if TSV Information is Likely Usable/Valid -------------------------
    -----------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Paste STEP 2: Check if TSV Information is Likely Usable/Valid --------------")

    -- Pre-check: every TSV1 entry must have a (likely) usable TSV2 match:
    for i, entry in ipairs(clipboard) do
      if entry.is_compound_parent ~= "Parent" then -- Ignore Parents for this.
        local key = string.format("%s|%s|%s|%s",
          entry.used_channel_count,
          entry.used_channel_type,
          entry.original_source_path,
          entry.final_source_path
        )
        if not id_map[key] or #id_map[key] == 0 then -- Each should exist already in id_map, based on the same key.
          LuaDialog.Message(
            "Pre-Paste Required!",
            "At least one region source is missing or unprepared.\n\n" ..
            "Please use Pre-Paste before pasting, especially\n" ..
            "if you are pasting using a redirected/new source.",
            LuaDialog.MessageType.Warning,
            LuaDialog.ButtonType.Close
          ):run()
          return
        end
      end
    end

    -- A table for collecting missing source paths:
    local missing_sources = {}

    -- Check if any IDs in TSV2 cannot actually be restored:
    for _, entry in ipairs(clipboard) do
      local key = string.format("%s|%s|%s|%s",
        entry.used_channel_count,
        entry.used_channel_type,
        entry.original_source_path,
        entry.final_source_path
      )

      local id_list = id_map[key]
      local found_valid = false

      if id_list then
        for _, id in ipairs(id_list) do
          local r = ARDOUR.RegionFactory.region_by_id(PBD.ID(id)) -- Check if RegionFactory returns a valid region.
          if r and not r:isnil() then
            found_valid = true -- We only need one ID to work.
            break
          end
        end
      end

      if not found_valid then
        table.insert(missing_sources, entry.source_path) -- Insert any missing/invalid sources into missing_sources.
      end
    end

    -- If any are missing, then clear the IDs and warn the user:
    if #missing_sources > 0 then

      -- Establish a table to update the TSV2 lines accordingly:
      local updated_lines = {}

      for line in io.lines(tsv2_path) do
        if line:match("^local_session") or line:match("^%s*$") then
          -- Preserve the header and blank lines:
          table.insert(updated_lines, line)
        else
          local fields = {}
          for field in line:gmatch("([^\t]*)\t?") do table.insert(fields, field) end

          local path = normalize_path(fields[8]) --------------
          for _, missing_path in ipairs(missing_sources) do
            if path == missing_path then
              fields[14] = "Undetermined" -- wipe IDs only
              break
            end
          end
          table.insert(updated_lines, table.concat(fields, "\t"))
        end
      end

      -- Write our new, updated_lines back to TSV2:
      local tsv2_file_write = io.open(tsv2_path, "w")
      tsv2_file_write:write(table.concat(updated_lines, "\n"))
      tsv2_file_write:close()

      -- Build and show a warning message: --------------
      local msg = "         The following source file(s) could not be restored:\n\n"

      -- Build unique list of missing paths:
      local unique_paths = {}
      local seen = {}
      for _, path in ipairs(missing_sources) do
        if not seen[path] then
          table.insert(unique_paths, path)
          seen[path] = true
        end
      end

      -- Show each unique missing path:
      for _, path in ipairs(unique_paths) do
        msg = msg .. "• " .. path .. "\n"
      end

      msg = msg ..
        "\n\nMissing sources may have been deleted, renamed, or moved.\n\n" .. --------------
        "             The stale region IDs have now been cleared.\n\n" ..
        "                 Please re-run Pre-Paste for these files\n" ..
        "                       to regenerate usable region IDs."

      LuaDialog.Message("Missing Sources!", msg, LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run()
      return
    end

    if debug_pause and debug_pause_popup("Paste STEP 2: Check if TSV Information is Likely Usable/Valid") then return end

    -------------------------------------------------------------------------------------------------------------------------
    ------------------------- Paste STEP 3: Alert the User About Legacy or Undetermined Fade Shapes -------------------------
    -------------------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Paste STEP 3: Alert the User About Legacy or Undetermined Fade Shapes --------------")

    -- Scan for "Legacy" fades that were successfully converted (i.e. where shape does NOT = "Undetermined")...
    -- Also, check for any "Undetermined" fade shapes:
    local legacy_shape_converted = false
    local needs_fallback_fade_shape = false

    for _, entry in ipairs(clipboard) do
      local legacy_in = entry.fade_in_type == "Legacy" and entry.fade_in_shape ~= "Undetermined"
      local legacy_out = entry.fade_out_type == "Legacy" and entry.fade_out_shape ~= "Undetermined"
      local undetermined_shape_present = entry.fade_in_shape == "Undetermined" or entry.fade_out_shape == "Undetermined"

      if legacy_in or legacy_out then
        legacy_shape_converted = true
      end
      if undetermined_shape_present then
        needs_fallback_fade_shape = true
      end
      -- Optimization: stop early if both conditions are already true:
      if legacy_shape_converted and needs_fallback_fade_shape then
        break
      end
    end

    -- If we found ANY "Legacy"-labeled fades that were successfully matched with a standard A8+ fade shape, then alert the user:
    if legacy_shape_converted then
      local legacy_dialog = LuaDialog.Message("Legacy Fades Were Present!", 
        "Some fade-in or fade-out shapes of the regions you\ncopied were likely created in an older version of\n" ..
        "Ardour, and thus have slightly different shapes\nthan the ones you are about to paste.\n\n" ..
        "Most legacy fade shapes have no exact modern\nequivalents anymore, so the closest matches have\nbeen substituted automatically.\n\n" ..
        "If you are concerned about this, please\ninspect your fade shapes after pasting!",
        LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close
      )
      legacy_dialog:run()
    end

    -- This dialog is now implememnted as ONLY a last-resort backup...
    -- And if someone out there DOES encounter this, then hopefully I'll read about it on the forum, and can fix what went wrong:
    local fallback_fade_shape
    if needs_fallback_fade_shape then
      local fade_dialog = LuaDialog.Dialog("Fade Shape(s) Undetermined!", {
        { type = "heading", title = "⚠ WARNING:" },
        { type = "label", title = "Some of the original fade-in and/or fade-out shapes" },
        { type = "label", title = "were not properly determined when this batch was copied!" },
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "This should never happen, so if you are seeing this," },
        { type = "label", title = "PLEASE post about it on the Ardour forum!" },
        { type = "label", title = " " }, -- Spacer
        { type = "label", title = "But for now, please select a fallback shape you would like to use:" },
        {
          type = "dropdown",
          key = "fadeShape",
          title = "Fade Shape Options",
          values = {
            ["Option 1 - Linear"] = "FadeLinear",
            ["Option 2 - Constant Power"] = "FadeConstantPower",
            ["Option 3 - Symmetric"] = "FadeSymmetric",
            ["Option 4 - Slow"] = "FadeSlow",
            ["Option 5 - Fast"] = "FadeFast"
          },
          default = "Option 2 - Constant Power"
        },
        { type = "label", title = " " } -- Spacer
      })

      local fade_result = fade_dialog:run()
      if not fade_result or not fade_result.fadeShape then return end
      fallback_fade_shape = ARDOUR.FadeShape[fade_result.fadeShape] or ARDOUR.FadeShape.FadeConstantPower -- Just use Ardour's default shape if something goes wrong here, somehow...
    end

    -- All pre-checks passed! CONGLATURATION ! ! !

    if debug_pause and debug_pause_popup("Paste STEP 3: Alert the User About Legacy or Undetermined Fade Shapes") then return end

    -----------------------------------------------------------------------------------------------
    ------------------------- Paste STEP 4: Define Any Remaining Fuctions -------------------------
    -----------------------------------------------------------------------------------------------

    debug_print("-------------- Paste STEP 4: Define Any Remaining Fuctions --------------")

    -- A function to combine siblings of a group into their parent (compound) region:
    function combine_siblings(playlist, track, layer_id, siblings_by_layer)
      -- Lookup sibling group for the current layer:
      local group = siblings_by_layer[layer_id]
      if not group or #group == 0 then
        debug_print("No sibling group for layer", layer_id)
        return nil
      end
    
      local expected_parent_id = group[1].parent_id -- All children should/do share the same parent id...
      local slist = ArdourUI.SelectionList()
    
      -- Resolve each child ID into a RegionView (-required for combine):
      for _, info in ipairs(group) do
        local r = nil
        for reg in playlist:region_list():iter() do
          if reg:to_stateful():id():to_s() == info.child_id then
            r = reg
            break
          end
        end
    
        if r and not r:isnil() then
          local rv = Editor:regionview_from_region(r)
          if rv ~= nil then
            slist:push_back(rv)
          else
            debug_print("RegionView not found for region ID:", info.child_id)
          end
        else
          debug_print("Could not resolve region ID:", info.child_id)
        end
      end
    
      -- Set the current selection (-needed before calling combine):
      Editor:set_selection(slist, ArdourUI.SelectionOp.Set)
      local rlist = Editor:get_selection().regions:regionlist()
    
      -- Perform the combine operation:
      local combined = playlist:combine(rlist, track)

      if combined and not combined:isnil() then
        debug_print("Combine parent succeeded! Region ID:", combined:to_stateful():id():to_s())
        return combined -- Return the combined region
      else
        debug_print("Combine failed.")
        return nil
      end
    end

    if debug_pause and debug_pause_popup("Paste STEP 4: Define Any Remaining Fuctions") then return end

    -----------------------------------------------------------------------------------------------------------------
    ------------------------- Paste STEP 5: Initiate the Main Paste Loop and Clone Handling -------------------------
    -----------------------------------------------------------------------------------------------------------------

    debug_print("-------------- Paste STEP 5: Initiate the Main Paste Loop and Clone Handling --------------")

    -- Begin the reversible command, so that the whole paste can easily be undone by the user: --------------
    -- Please confirm this works!
    Session:begin_reversible_command("AudioClipboard Paste")
    playlist:to_stateful():clear_changes()
    local playlist_before = playlist:to_statefuldestructible()

    local pasted = 0 -- A counter to keep track of the total, pasted regions.

    local divert_to_combine_siblings = false
    local latest_combined_parent = nil
    local current_layer = nil
    local siblings_by_layer = {} -- table[child_layer] = { {child_id=..., parent_id=...}, ... } --------------

    for i, entry in ipairs(clipboard) do

      -- In this first portion, only process TSV1 entries that are NOT parents (i.e. NOT compound/combined regions):
      if entry.is_compound_parent == "NotParent" then

        local key = string.format("%s|%s|%s|%s",
          entry.used_channel_count,
          entry.used_channel_type,
          entry.original_source_path,
          entry.final_source_path
        )
        local id_iter = id_map[key]
        local base = nil

        if id_iter then
          for _, id in ipairs(id_map[key]) do
            local r = ARDOUR.RegionFactory.region_by_id(PBD.ID(id))
            if r and not r:isnil() then base = r break end
          end      
        end
        
        -- If the user had erased a source and the IDs are ACTUALLY invalid, this still handles it: --------------
        if not base then
          -- Show failure dialog:
          LuaDialog.Message(
            "Paste Failed!",
            "One or more saved regions could not be restored.\n\n" ..
            "This may be due to deleted sources or expired IDs.\n\n" ..
            "Please re-run Pre-Paste in this project to regenerate valid region IDs.",
            LuaDialog.MessageType.Warning,
            LuaDialog.ButtonType.Close
          ):run()
        
          -- Now wipe the stale ID(s) from the TSV2 entry...
          -- Establish a table for this:
          local updated_lines = {}

          for line in io.lines(tsv2_path) do
            if line:match("^local_session") or line:match("^%s*$") then
              -- Preserve the header and blank lines:
              table.insert(updated_lines, line)
            else

              local fields = {}
              for field in line:gmatch("([^\t]*)\t?") do table.insert(fields, field) end

              if normalize_path(fields[8]) == normalize_path(entry.original_source_path) and
                normalize_path(fields[12]) == normalize_path(entry.final_source_path)
              then
                fields[14] = "Undetermined" -- Wipe just the ID field.
              end
              table.insert(updated_lines, table.concat(fields, "\t"))
            end
          end
        
          -- Write updated_lines back to TSV2:
          local tsv2_file_write = io.open(tsv2_path, "w")
          if tsv2_file_write then
            tsv2_file_write:write(table.concat(updated_lines, "\n"))
            tsv2_file_write:close()
          end
        
          return -- Abort the whole paste right here.
        end

        -- Clone a region into existence via RegionFactory:
        local clone = ARDOUR.RegionFactory.clone_region(base, false, false):to_audioregion()
        
        if not clone or clone:isnil() then
          debug_print("Clone failed for region:", i)
          goto continue -- Skip this one because something went seriously wrong...
        end

        -- Wipe it 'clean':
        clone:to_stateful():clear_changes()

        -- Adjust to full-length first:
        local src = clone:source(0)
        if not src or src:isnil() then
          debug_print("No valid source for clone.")
          goto continue -- Again, skip this one because something went seriously wrong...
        end

        local full_len = src:length():samples()
        clone:set_start(Temporal.timepos_t(0))
        clone:set_length(Temporal.timecnt_t(full_len))
        clone:set_position(Temporal.timepos_t(0))

        -- Clear envelope + gain & polarity:
        clone:set_scale_amplitude(1.0)
        local env = clone:envelope()
        if env and not env:isnil() then
          env:clear_list()
          clone:set_envelope_active(false)
        end

        -- DEBUG: Show trim values:
        debug_print(string.format(
          "Preparing to trim: start_spl=%s, length_spl=%s, position_spl=%s",
          tostring(entry.start_spl),
          tostring(entry.length_spl),
          tostring(entry.position_spl)
        ))

        -- Set the start inside the source ("file start" -> trim):
        clone:trim_to(Temporal.timepos_t(entry.start_spl), Temporal.timecnt_t(entry.length_spl))

        -- Set where the region appears on the timeline:
        clone:set_position(Temporal.timepos_t(entry.position_spl))

        -- Set gain_and_polarity:
        clone:set_scale_amplitude(entry.gain_and_polarity or 1.0) -- Default to "1.0" (=0db) if something went wrong (-unlikely here).

        -- Apply Envelope:
        if entry.envelope and entry.envelope ~= "Undetermined" and entry.envelope ~= "DefaultEnvelope" then -- Simply apply no envelope if it's either of those two.
          local env = clone:envelope()
          if env and not env:isnil() then
            env:clear_list()
            for s, v in entry.envelope:gmatch("(%d+):([%d%.%-]+)") do
              env:add(Temporal.timepos_t(tonumber(s)), tonumber(v), false, false) -- The 2nd false prevents thinning from occurring, supposedly...
            end
            --env:thin(20)  -- Muted this option to thin envelope points.
            clone:set_envelope_active(true)
          end
        end

        -- Apply envelope state:
        if entry.envelope_state == "EnvelopeActive" then
          clone:set_envelope_active(true)
        else
          clone:set_envelope_active(false)
        end

        -- Apply fade info:
        clone:set_fade_in_length(entry.fade_in_spl)
        clone:set_fade_out_length(entry.fade_out_spl)
        clone:set_fade_in_shape(entry.fade_in_shape ~= "Undetermined" and ARDOUR.FadeShape[entry.fade_in_shape] or fallback_fade_shape)
        clone:set_fade_out_shape(entry.fade_out_shape ~= "Undetermined" and ARDOUR.FadeShape[entry.fade_out_shape] or fallback_fade_shape)

        -- fade_in/fade_out_active:
        if entry.fade_in_state == "FadeInActive" then
          clone:set_fade_in_active(true)
        else
          clone:set_fade_in_active(false)
        end

        if entry.fade_out_state == "FadeOutActive" then
          clone:set_fade_out_active(true)
        else
          clone:set_fade_out_active(false)
        end

        -- Apply mute state:
        if entry.mute_state == "Muted" then
          clone:set_muted(true)
        else
          clone:set_muted(false)
        end

        -- Apply opaque state:
        if entry.opaque_state == "Opaque" then
          clone:set_opaque(true)
        else
          clone:set_opaque(false)
        end

        -- Apply lock state:
        if entry.lock_state == "Locked" then
          clone:set_locked(true)
        else
          clone:set_locked(false)
        end

        -- Apply sync position:
        if entry.sync_position ~= entry.position_spl then -- This prevents a bug where the Sync Position was ending up (according to the Properties window of these
                                                          -- regions) as a *negative* value, somehow, even though the sync_position and position_spl were identical.
                                                          -- This resulted in horizontally-locked audio regions that could only be moved if their Sync Positions
                                                          -- (green lines) were explicitly brought into view on the regions themselves.  Thus if sync_position and
                                                          -- position_spl are equal to begin with (-the norm-), then simply don't apply it, and the bug is resolved.
          clone:set_sync_position(Temporal.timepos_t(entry.sync_position))
        end

        -- Apply fade-before-FX state:
        if entry.fade_before_fx == "BeforeFX" then
          clone:set_fade_before_fx(true)
        else
          clone:set_fade_before_fx(false)
        end

        -- Place this 'normal'/'regular' region into the playlist:
        playlist:add_region(clone, Temporal.timepos_t(entry.position_spl), 1, false) -- I am unsure, but should this be placed BEFORE all processing instead? --------------

        -- Add to the pasted-regions tally if the region is NOT a child...
        -- We only want to add regular/normal regions and non-child parents to the count!:
        if entry.is_compound_child == "NotChild" then
          pasted = pasted + 1
        end

        -- Save the ID (and the parent's) if this was a compound "child":
        if entry.is_compound_child == "Child" then
          local layer = tonumber(entry.compound_layer:match("Layer(%d+)"))
          siblings_by_layer[layer] = siblings_by_layer[layer] or {}
          table.insert(siblings_by_layer[layer], {
            child_id = clone:to_stateful():id():to_s(),
            parent_id = entry.childs_parents_id
          })

          -- If this is the LAST child in a siblings group, set a flag to divert momentarily (for combining and processing of the parent):
          if tostring(entry.siblings_total) == tostring(entry.sibling_number) then
            divert_to_combine_siblings = true
            current_layer = layer
          end
        end

        -- If a parent must be manifested from a child/siblings group, and then processed:
        if divert_to_combine_siblings then

          -- If in debug mode, this interrupts each combine_siblings call so you can inspect the child regions for accuracy before they're combined:
          if debug then
            local opts = {
              { type = "heading", title = "Interrupting the combining of sibling regions for inspection..." },
              { type = "heading", title = string.format("Layer: %s | Total Current Siblings: %d", tostring(current_layer), #siblings_by_layer[current_layer] or 0) },
              { type = "label", title = " " }, -- Spacer.
              { type = "label", title = "Click OK to continue combining and pasting." },
              { type = "label", title = " " } -- Spacer.
            }
            local choice = LuaDialog.Dialog("⚠️ DEBUG Popup", opts):run()
          end

          -- Combine the sibling group, since all siblings have now been processed:
          latest_combined_parent = combine_siblings(playlist, track, current_layer, siblings_by_layer)
        
          -- Clear the layer state now that the siblings have been combined:
          siblings_by_layer[current_layer] = nil
          current_layer = nil
          divert_to_combine_siblings = false

        end

        ::continue::

      -----------------------------------------------------------------------------------------------------------------------
      ------------------------- Paste STEP 6: Initiate Any Compound/Combined/Parent-Region Handling -------------------------
      -----------------------------------------------------------------------------------------------------------------------

      -- In this second portion, only process TSV1 entries that ARE parents (i.e. compound/combined regions):
      elseif entry.is_compound_parent == "Parent" then

        debug_print("-------------- Paste STEP 6: Initiate Any Compound/Combined/Parent-Region Handling --------------")

        if latest_combined_parent then -- Check that the latest_combined_parent exists and is valid.

          local combined_audio_region = latest_combined_parent:to_audioregion()
          local id = combined_audio_region:to_stateful():id():to_s()
          debug_print("Combined Parent Region ID: " .. id)

          if not combined_audio_region or combined_audio_region:isnil() then
            debug_print("Combined region is not an AudioRegion!")
            return
          end

          debug_print("Combined Parent Successful!")
  
          -- Begin applying field data to the newly-combined, parent region...
          -- All of this is basically the same as prior:
          combined_audio_region:set_position(Temporal.timepos_t(entry.position_spl))
          combined_audio_region:set_scale_amplitude(entry.gain_and_polarity or 1.0)

          local env = combined_audio_region:envelope()
          if env and not env:isnil() then
            env:clear_list()
            if entry.envelope then
              for s, v in entry.envelope:gmatch("(%d+):([%d%.%-]+)") do
                env:add(Temporal.timepos_t(tonumber(s)), tonumber(v), false, false)
              end
              combined_audio_region:set_envelope_active(entry.envelope_state == "EnvelopeActive")
            end
          end

          -- Apply fade info:
          combined_audio_region:set_fade_in_length(entry.fade_in_spl)
          combined_audio_region:set_fade_out_length(entry.fade_out_spl)
          combined_audio_region:set_fade_in_shape(entry.fade_in_shape ~= "Undetermined" and ARDOUR.FadeShape[entry.fade_in_shape] or fallback_fade_shape)
          combined_audio_region:set_fade_out_shape(entry.fade_out_shape ~= "Undetermined" and ARDOUR.FadeShape[entry.fade_out_shape] or fallback_fade_shape)

          if entry.fade_in_state == "FadeInActive" then --------------
            combined_audio_region:set_fade_in_active(true)
          else
            combined_audio_region:set_fade_in_active(false)
          end

          if entry.fade_out_state == "FadeOutActive" then
            combined_audio_region:set_fade_out_active(true)
          else
            combined_audio_region:set_fade_out_active(false)
          end

          -- Apply other states:
          combined_audio_region:set_muted(entry.mute_state == "Muted")
          combined_audio_region:set_opaque(entry.opaque_state == "Opaque")
          combined_audio_region:set_locked(entry.lock_state == "Locked")

          if entry.sync_position ~= entry.position_spl then -- Prevents a bug, as mentioned prior. --------------
            combined_audio_region:set_sync_position(Temporal.timepos_t(entry.sync_position))
          end

          combined_audio_region:set_fade_before_fx(entry.fade_before_fx == "BeforeFX")

          -- Again, add to the pasted-regions tally if this parent is NOT a child:
          if entry.is_compound_child == "NotChild" then
            pasted = pasted + 1
          end

          -- If this parent is ALSO a child, process it accordingly (just as before):
          if entry.is_compound_child == "Child" then
            local layer = tonumber(entry.compound_layer:match("Layer(%d+)"))
            siblings_by_layer[layer] = siblings_by_layer[layer] or {}
            table.insert(siblings_by_layer[layer], {
              child_id = combined_audio_region:to_stateful():id():to_s(), -- Add its ID to siblings_by_layer[layer]...
              parent_id = entry.childs_parents_id -- And add its parent's ID.
            })

            -- Again, if this is the LAST child in a siblings group, set a flag to divert momentarily (for combining and processing of the parent):
            if tostring(entry.siblings_total) == tostring(entry.sibling_number) then
              divert_to_combine_siblings = true
              current_layer = layer
            else
              divert_to_combine_siblings = false
            end
          end

        else
          debug_print("Can't find the combined region!")
        end

        latest_combined_parent = nil -- Clear the latest_combined_parent since it's now been processed fully.

        -- Note here that there is no reason to add a parent (i.e. combined region) to the current playlist,
        -- because they are inherently/automatically added to the playlist of the regions fed into it!
        -- If you add it AGAIN, then you get MAJOR GUI (and other) issues! o___O

        if divert_to_combine_siblings then

          -- Again, combine the sibling group (in this case where a parent was a final sibling of a sibling group), since all siblings have now been processed:
          latest_combined_parent = combine_siblings(playlist, track, current_layer, siblings_by_layer)
        
          -- Clear the layer state now that the siblings have been combined:
          siblings_by_layer[current_layer] = nil
          current_layer = nil
          divert_to_combine_siblings = false

        end

        if debug_pause and debug_pause_popup("Paste STEP 6: Initiate Any Compound/Combined/Parent-Region Handling") then return end

      end
    end -- Ends "for i, entry in ipairs(clipboard) do", -our main Paste Logic loop!

    if debug_pause and debug_pause_popup("Paste STEP 5: Initiate the Main Paste Loop and Clone Handling") then return end

    -----------------------------------------------------------------------------------------------------------
    ------------------------- Paste STEP 7: Finalize and Conclude The Pasting Process -------------------------
    -----------------------------------------------------------------------------------------------------------

    debug_print("-------------- Paste STEP 7: Finalize and Conclude The Pasting Process --------------")

    -- Commit the playlist changes:
    local playlist_after = playlist:to_statefuldestructible()

    -- Establish our before and after states (so they can easily be undone by the user):
    if playlist_before and playlist_after and not playlist_after:isnil() then
      Session:add_stateful_diff_command(playlist_after)
      Session:commit_reversible_command(nil)
    else
      Session:abort_reversible_command() -- Cancel the creation of the reversible command if something went wrong.
    end

    if pasted == 1 then
      LuaDialog.Message(
        "Paste Complete!",
        "1 region pasted successfully.\n\nPlease clap.",
        LuaDialog.MessageType.Info,
        LuaDialog.ButtonType.Close
      ):run()

    elseif pasted > 1 then
      LuaDialog.Message(
        "Paste Complete!",
        string.format(
          "%d regions pasted successfully!\n\n\n\n" ..
          "     CONGLATURATION  ! ! !\n\n    YOU HAVE COMPLETED\n          A GREAT PASTE.", -- Keeping this BS shorter.
          --"AND PROOVED THE JUSTICE\n        OF OUR CULTURE.\n\n    NOW GO AND REST OUR\n                HEROES  !",
          pasted
        ),
        LuaDialog.MessageType.Info,
        LuaDialog.ButtonType.Close
      ):run()

    else
      debug_print("Pasting Failed! :(")
    end

    if debug_pause and debug_pause_popup("Paste STEP 7: Finalize and Conclude The Pasting Process") then return end

    return

  end -- Ends "if action == "paste" then".

end end