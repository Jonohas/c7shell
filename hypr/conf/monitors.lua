------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
--
-- A layout the user arranged in the settings app is remembered in
-- ~/.config/hypr/displays.json and overrides the positions and modes chosen
-- here; conf/displays.lua reads it. Nothing writes to THIS file.
--
-- Layout is chosen by which monitors are actually connected. Edit CATALOG to
-- describe a monitor's intrinsic properties (mode/scale/rotation -- things that
-- travel with the panel), and PROFILES to describe where those panels sit on
-- the desk in a given setup.

local displays = require("conf/displays")

-- Fallback for anything not in CATALOG (projector, meeting-room TV, headless).
-- Rules applied later override this.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

-- Intrinsic per-panel settings. `desc` is matched as a prefix against the
-- monitor description from `hyprctl monitors`, so it survives the DP-N
-- renumbering that happens whenever the dock re-enumerates. The built-in
-- panel is matched by connector name instead; eDP-1 is stable.
local CATALOG = {
    ultrawide = {
        desc  = "LG Electronics LG ULTRAWIDE",
        mode  = "3440x1440@100",     -- native/preferred per EDID; drop to @60 on a low-bandwidth cable
        scale = 1,
        size  = { 3440, 1440 },      -- logical, for the layout comments below
        bitdepth = 10,
    },
    ultrawideHome = {
        desc  = "Iiyama North America PL3466WQ",
        mode  = "3440x1440@99.99",     -- native/preferred per EDID; drop to @60 on a low-bandwidth cable
        scale = 1,
        size  = { 3440, 1440 },      -- logical, for the layout comments below
    },
    ultragearLeft = {
        desc  = "LG Electronics LG ULTRAGEAR 311NTTQ9M049",  -- DP-4
        mode  = "2560x1440@143.93",
        scale = 1,
        size  = { 2560, 1440 },
    },
    ultragearCenter = {
        desc  = "LG Electronics LG ULTRAGEAR 311NTRL9L950",  -- DP-10
        mode  = "2560x1440@143.93",
        scale = 1,
        size  = { 2560, 1440 },
    },
    ultragearRight = {
        desc  = "LG Electronics LG ULTRAGEAR 311NTCZ9M979",  -- DP-9
        mode  = "2560x1440@143.93",
        scale = 1,
        size  = { 2560, 1440 },
    },
    -- The second screen at the office desk, right of the ultrawide.
    dell = {
        desc  = "Dell Inc. DELL P2417H",
        mode  = "1920x1080@60",
        scale = 1,
        size  = { 1920, 1080 },
    },
    laptop = {
        name  = "eDP-1",
        -- Belt and braces: eDP-1 is stable for a built-in panel, but detect()
        -- accepts either, so a renamed connector still finds the panel.
        desc  = "BOE NE135A1M-NY1",
        mode  = "2880x1920@120",
        scale = 2,
        size  = { 1440, 960 },
    },
}

-- Hyprland leaves the built-in panel enabled when the lid shuts, so the lid has
-- to be read out of band. ACPI gives the state at load (a reload with the lid
-- already down must not come up in the laptop-open layout); the switch binds at
-- the bottom keep it current afterwards.
local LID_STATE = "/proc/acpi/button/lid/LID0/state"

--- true, false, or nil on a machine with no lid file at all (a desktop, or a
--- kernel that exposes no lid).
local function lid_is_closed()
    local f = io.open(LID_STATE)
    if not f then return nil end
    local state = f:read("*a")
    f:close()
    return state:match("closed") ~= nil
end

-- The switch binds at the bottom are authoritative once one has fired; before
-- that (first load, and every reload) fall back to reading ACPI. Caching the
-- ACPI read in a plain local was the bug: on reload the lid could be re-read as
-- open, so apply() enabled the built-in panel before a later run disabled it
-- again, and that add/remove of a Wayland output is what moved the focused
-- workspace and killed every Chromium/Electron window.
local lid_override = nil

local function lid_closed()
    -- ACPI is authoritative wherever it exists. The override used to outrank
    -- it, and a switch event that never arrived then stranded the desk: the lid
    -- was open, `lid_override` still said shut, and the layout stayed in the
    -- lid-closed profile until a reload. The override now only covers the
    -- machine that has no lid file to read.
    local acpi = lid_is_closed()
    if acpi ~= nil then return acpi end
    return lid_override == true
end

-- First profile whose monitors are ALL connected wins, so order these most
-- specific first. Positions are top-left corners in the shared logical-pixel
-- plane; keep edges flush or the cursor crosses dead space.
local PROFILES = {
    -- Three UltraGears in a row, laptop centred underneath the middle one.
    -- 2560 each at scale 1: 0 | 2560 | 5120. Laptop is 1440 logical wide, so
    -- 2560 + (2560 - 1440) / 2 = 3120 centres it.
    {
        name = "triple-ultragear",
        need = { "ultragearLeft", "ultragearCenter", "ultragearRight", "laptop" },
        at   = {
            ultragearLeft   = "0x0",
            ultragearCenter = "2560x0",
            ultragearRight  = "5120x0",
            laptop          = "3120x1440",
        },
    },
    {
        name = "triple-ultragear-lid-closed",
        need = { "ultragearLeft", "ultragearCenter", "ultragearRight" },
        at   = {
            ultragearLeft   = "0x0",
            ultragearCenter = "2560x0",
            ultragearRight  = "5120x0",
        },
    },
    -- Ultrawide only, laptop tucked underneath.
    {
        name = "ultrawide",
        need = { "ultrawide", "laptop" },
        at   = { ultrawide = "0x0", laptop = "1000x1440" },
    },
    {
        name = "ultrawideHome",
        need = { "ultrawideHome", "laptop" },
        at   = { ultrawideHome = "0x0", laptop = "1000x1440" },
    },
    -- Office desk, lid shut: the laptop panel drops out, the Dell does not.
    -- Ahead of ultrawide-lid-closed, which names the ultrawide alone and would
    -- otherwise match first and switch the Dell off.
    {
        name = "office-lid-closed",
        need = { "ultrawide", "dell" },
        at   = { ultrawide = "0x0", dell = "3440x180" },
    },
    -- Same desk, lid shut: the laptop panel drops out of the layout entirely.
    {
        name = "ultrawide-lid-closed",
        need = { "ultrawide" },
        at   = { ultrawide = "0x0" },
    },
    {
        name = "ultrawideHome-lid-closed",
        need = { "ultrawideHome" },
        at   = { ultrawideHome = "0x0" },
    },
    -- On the road.
    {
        name = "mobile",
        need = { "laptop" },
        at   = { laptop = "0x0" },
    },
}

-- -- candidates ---------------------------------------------------------------
-- A candidate is a profile flattened into descriptions:
--   { name, source = "lua"|"json", shadows, unresolved,
--     need = { "<desc>", ... },
--     at   = { ["<desc>"] = { output, position, mode, scale, ... } } }
-- lua PROFILES and the settings app's JSON profiles become the same shape here,
-- which is the only reason they can be ordered against each other at all.

--- The lua PROFILES, resolved through CATALOG onto the descriptions of the
--- monitors that are actually plugged in. `by_key` is detect()'s output, so a
--- CATALOG entry matched by prefix resolves to the panel's FULL description,
--- serial and all -- which is what displays.json is keyed on.
local function lua_candidates(by_key)
    local out = {}
    for _, p in ipairs(PROFILES) do
        local need, at, unresolved = {}, {}, false

        for _, key in ipairs(p.need) do
            local mon = by_key[key]
            -- A key with no live monitor leaves `need` silently short an entry;
            -- that is only safe because matches() checks `unresolved` before it
            -- ever reads `need`. Keep both in step if this candidate shape moves.
            if mon then need[#need + 1] = mon.description else unresolved = true end
        end

        for key, position in pairs(p.at) do
            local def = CATALOG[key]
            local mon = by_key[key]
            if mon and def then
                at[mon.description] = {
                    -- The output name this profile has always used. Keeping it
                    -- rather than the live connector name means a CATALOG entry
                    -- can still be desc-matched, which is the whole point of it.
                    output        = def.name or ("desc:" .. def.desc),
                    position      = position,
                    mode          = def.mode,
                    scale         = def.scale,
                    transform     = def.transform,
                    bitdepth      = def.bitdepth,
                    cm            = def.cm,
                    sdrbrightness = def.sdrbrightness,
                    -- CATALOG modes are hand-written for a panel that is known
                    -- to offer them, so they are not checked against
                    -- available_modes. A JSON mode is.
                    checked       = false,
                }
            else
                unresolved = true
            end
        end

        out[#out + 1] = { name = p.name, source = "lua", shadows = false,
                          need = need, at = at, unresolved = unresolved }
    end
    return out
end

--- The settings app's profiles, already description-keyed. Membership IS the
--- requirement: a profile names every display it wants on, and nothing else.
local function json_candidates()
    local out = {}
    for _, p in ipairs(displays.profiles()) do
        local need, at = {}, {}
        for desc, f in pairs(p.displays) do
            need[#need + 1] = desc
            at[desc] = { output = "desc:" .. desc, position = f.position,
                         mode = f.mode, scale = f.scale, transform = f.transform,
                         checked = true }
        end
        -- Deterministic, so the state file does not reshuffle between applies.
        table.sort(need)
        out[#out + 1] = { name = p.name, source = "json", shadows = false,
                          need = need, at = at, unresolved = false }
    end
    return out
end

--- JSON first, then the lua profiles that no JSON profile has taken the name of.
--- Same name means the settings app has edited a hand-written profile; the lua
--- file is never rewritten, so the JSON one shadows it and deleting the JSON one
--- brings it back.
local function candidates(by_key)
    local out, taken = json_candidates(), {}
    for _, c in ipairs(out) do taken[c.name] = c end
    for _, c in ipairs(lua_candidates(by_key)) do
        if taken[c.name] then taken[c.name].shadows = true else out[#out + 1] = c end
    end
    return out
end

--- Every display the candidate needs is present and usable. A candidate with an
--- unresolved requirement -- a CATALOG entry matched by connector name that is
--- not plugged in -- can never match, which is what PROFILES did before this.
local function matches(c, usable)
    if c.unresolved then return false end
    for _, desc in ipairs(c.need) do
        if not usable[desc] then return false end
    end
    return true
end

--- The pinned profile if it fits, otherwise the first candidate that does.
--- Returns the candidate and whether it was pinned. A pin naming something
--- unavailable is not an error: falling back to auto-match beats leaving the
--- desk with no layout at all.
local function choose(cands, usable, active)
    if active then
        for _, c in ipairs(cands) do
            if c.name == active and matches(c, usable) then return c, true end
        end
    end
    for _, c in ipairs(cands) do
        if matches(c, usable) then return c, false end
    end
    return nil, false
end

-- Map connected monitors onto CATALOG keys, keeping the live HL.Monitor rather
-- than just a flag: a saved layout is keyed on the monitor's own full
-- description (serial and all), and mode validation needs available_modes.
local function detect()
    local out = {}
    for _, m in ipairs(hl.get_monitors()) do
        for key, def in pairs(CATALOG) do
            local hit = (def.name and m.name == def.name)
                or (def.desc and m.description:sub(1, #def.desc) == def.desc)
            if hit then out[key] = m end
        end
    end
    return out
end

--- The read-only half of the settings app's view. Written after every apply,
--- listing every profile this file knows about -- hand-written and settings-app
--- alike -- and which one won. Nothing reads it back; it exists because the
--- settings app deliberately does not parse lua.
local function write_state(cands, usable, profile, forced)
    local list = {}
    for _, c in ipairs(cands) do
        local at = {}
        for desc, f in pairs(c.at) do
            at[desc] = { position = f.position, mode = f.mode, scale = f.scale }
        end
        list[#list + 1] = {
            name      = c.name,
            source    = c.source,
            shadows   = c.shadows == true,
            -- What the page greys out. Computed here rather than in QML because
            -- "available" includes the lid, and the lid is only legible here.
            available = matches(c, usable),
            displays  = at,
        }
    end

    displays.write_state({
        active   = profile and profile.name or nil,
        forced   = forced == true,
        profiles = list,
    })
end

--- Hyprland drops a disabled monitor from hl.get_monitors() entirely, so a
--- panel this file switched off is invisible to the next run -- nothing can see
--- it to switch it back on. That is why reopening the lid left the built-in
--- panel dark: the switch bind fired, apply() ran, and the laptop was simply
--- not in the list any more. Enable it blind and look again.
local function wake_panel(by_key)
    local def = CATALOG.laptop
    if lid_closed() or by_key.laptop or not def then return by_key end
    -- Only on a machine that has a lid. A desktop cannot have a panel hidden
    -- this way, and a CATALOG laptop entry there would otherwise have a rule
    -- written for it on every hotplug.
    if lid_is_closed() == nil then return by_key end
    hl.monitor({
        output   = def.name or ("desc:" .. def.desc),
        mode     = "preferred",
        position = "auto",
        scale    = "auto",
        disabled = false,
    })
    -- A panel that is genuinely absent stays absent; this is a rule, not a
    -- promise. detect() again either way -- Hyprland may only add the output
    -- once this call returns, and the retry in apply() covers that case.
    return detect()
end

--- Nothing known fits: hand every connected output back to hyprland's own
--- preferred/auto. The catch-all rule at the top of the file only runs at load,
--- so without this a monitor an earlier profile disabled stayed off forever.
local function auto(by_desc)
    for _, m in pairs(by_desc) do
        hl.monitor({ output = m.name, mode = "preferred", position = "auto",
                     scale = "auto", disabled = false })
    end
end

--- Every panel CATALOG knows, enabled, whatever an earlier run did to it.
--- Only at load: a disabled monitor is invisible to hl.get_monitors(), so
--- without this the ONLY way back for a screen some profile switched off was to
--- name it by hand in hyprctl. Not on hotplug -- re-enabling a screen the
--- winning profile then disables again is the output churn that moves
--- workspaces and kills Chromium windows.
local function wake_all()
    for _, def in pairs(CATALOG) do
        hl.monitor({ output = def.name or ("desc:" .. def.desc), disabled = false })
    end
end

local function apply_inner()
    local by_key = wake_panel(detect())

    local by_desc = {}
    for _, m in ipairs(hl.get_monitors()) do by_desc[m.description] = m end

    -- A shut lid means the panel is there but unusable, so it drops out of the
    -- set profiles are matched against. Every profile that names it -- by
    -- CATALOG key or by description -- then falls through to a lid-closed
    -- sibling, which is exactly what happened before profiles were described in
    -- two places.
    local usable = {}
    for desc in pairs(by_desc) do usable[desc] = true end
    if lid_closed() and by_key.laptop then usable[by_key.laptop.description] = nil end

    local cands = candidates(by_key)
    local profile, forced = choose(cands, usable, displays.active())

    write_state(cands, usable, profile, forced)

    -- No profile fits: go auto rather than leave the desk on whatever the last
    -- profile decided. That also covers a shut lid with no external panel --
    -- better an enabled screen than the only output there is going dark.
    if not profile then return auto(by_desc) end

    -- Only a description something claims to understand is ever turned OFF: one
    -- CATALOG matched, or one some profile names. A meeting-room projector is
    -- known to nobody and keeps the catch-all rule, rather than going dark
    -- because the laptop-only profile does not mention it.
    local known = {}
    for _, m in pairs(by_key) do known[m.description] = true end
    for _, c in ipairs(cands) do
        for desc in pairs(c.at) do known[desc] = true end
    end

    -- displays.json's layouts are keyed on the set of monitors this layout
    -- leaves ENABLED, which is the list the settings app sees in Hyprland's
    -- monitor list, so both sides compute the same key.
    local enabled = {}
    for desc in pairs(by_desc) do
        if profile.at[desc] or not known[desc] then enabled[#enabled + 1] = desc end
    end
    local saved = displays.layout(enabled)

    for desc, f in pairs(profile.at) do
        local mon = by_desc[desc]
        -- Saved values OVERRIDE the profile's position and the catalog's
        -- mode/scale, one field at a time; anything the user never changed, or
        -- that fails validation, falls through to the profile's own value.
        local s = saved[desc] or {}
        local modes = mon and mon.available_modes
        -- A JSON mode is whitelisted against available_modes; a CATALOG mode is
        -- hand-written for a panel known to offer it and is passed through. Not
        -- an `and/or` ternary: a rejected JSON mode must become nil and fall
        -- through to "preferred", and `cond and nil or f.mode` would hand back
        -- the unvalidated string instead.
        local want = f.mode
        if f.checked then want = displays.mode(f.mode, modes) end
        hl.monitor({
            output        = f.output,
            mode          = displays.mode(s.mode, modes) or want or "preferred",
            position      = displays.position(s.position) or f.position,
            scale         = displays.scale(s.scale) or f.scale,
            transform     = displays.transform(s.transform) or f.transform,
            bitdepth      = f.bitdepth,
            cm            = f.cm,
            sdrbrightness = f.sdrbrightness,
            disabled      = false, -- clears an earlier disable when the lid reopens
        })
    end

    -- A monitor no profile mentions keeps the catch-all rule, but a layout the
    -- user dragged it into is still saved against this desk -- and applying
    -- only profile.at dropped it, so that panel snapped back to auto on every
    -- reload. displays.json is the source of truth for everything staying on.
    for desc, s in pairs(saved) do
        local mon = by_desc[desc]
        if mon and not known[desc] then
            hl.monitor({
                output    = "desc:" .. desc,
                mode      = displays.mode(s.mode, mon.available_modes) or "preferred",
                position  = displays.position(s.position) or "auto",
                scale     = displays.scale(s.scale) or "auto",
                transform = displays.transform(s.transform),
                disabled  = false,
            })
        end
    end

    -- Connected, known, and left out of the winning profile: drop it from the
    -- layout so its workspaces move to a monitor that is actually visible.
    for desc, m in pairs(by_desc) do
        if known[desc] and not profile.at[desc] then
            hl.monitor({ output = m.name, disabled = true })
        end
    end

    return profile.name
end

-- hl.monitor() below fires monitor.added/monitor.removed, which are hooked back
-- to apply(); without this guard one reload re-entered it five times.
local applying = false

local function apply()
    if applying then return end
    applying = true
    local ok, res = pcall(apply_inner)
    applying = false
    if not ok then error(res) end
    return res
end

-- A dock's ports don't come back atomically: one connector's monitor.added
-- can fire while its siblings are still down, so apply() run straight off
-- that event sees a partial set, locks in the wrong profile (usually
-- mobile), and nothing re-triggers it once the rest of the dock catches up --
-- a connector that stayed "connected" throughout never fires its own event
-- to prompt another look. Debounce: restart a short timer on every event,
-- run apply() only once the burst goes quiet.
local HOTPLUG_DEBOUNCE_MS = 750
local hotplug_timer = hl.timer(apply, { timeout = HOTPLUG_DEBOUNCE_MS, type = "oneshot" })
hotplug_timer:set_enabled(false)

local function schedule_apply()
    hotplug_timer:set_enabled(false)
    hotplug_timer:set_timeout(HOTPLUG_DEBOUNCE_MS)
    hotplug_timer:set_enabled(true)
end

-- Registered before the first apply() so a monitor.added that fires while
-- Hyprland is still enumerating outputs at startup is never missed: with the
-- listener registered after, that event -- for a monitor already plugged in,
-- so nothing will hotplug again to retrigger it -- left the layout stuck on
-- whatever the first apply() saw until the next manual reload.
-- Deliberately not hooked to monitor.layout_changed: hl.monitor() below would
-- retrigger it and loop.
hl.on("monitor.added", schedule_apply)
hl.on("monitor.removed", schedule_apply)

wake_all()
apply()

-- The lid fires no monitor event -- Hyprland keeps eDP-1 enabled either way --
-- so drive apply() from the switch itself. `locked` so it still works over the
-- lockscreen. SW_LID is on when the lid is shut. If logind is set to suspend on
-- lid close these never matter; they are what makes HandleLidSwitch=ignore work.
hl.bind("switch:on:Lid Switch",  function() lid_override = true;  apply() end, { locked = true })
hl.bind("switch:off:Lid Switch", function() lid_override = false; apply() end, { locked = true })

-- The binds above give the instant response; this catches what they drop. A
-- switch event CAN go missing -- one did, and the desk sat in
-- `ultrawide-lid-closed` with the lid open until the next reload, because
-- nothing re-read the lid afterwards. One 30-byte /proc read every two seconds
-- is cheaper than that failure.
local LID_POLL_MS = 2000
local lid_seen = lid_is_closed()
local lid_poll
lid_poll = hl.timer(function()
    local now = lid_is_closed()
    if now ~= lid_seen then
        lid_seen = now
        apply()
    end
    -- A oneshot rearmed from its own callback: the repeating timer type is not
    -- documented, and this costs the same either way.
    lid_poll:set_timeout(LID_POLL_MS)
    lid_poll:set_enabled(true)
end, { timeout = LID_POLL_MS, type = "oneshot" })
