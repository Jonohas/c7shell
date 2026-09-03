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

local function lid_is_closed()
    local f = io.open(LID_STATE)
    if not f then return false end -- desktop, or a kernel that exposes no lid
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
    if lid_override ~= nil then return lid_override end
    return lid_is_closed()
end

-- First profile whose monitors are ALL connected wins, so order these most
-- specific first. Positions are top-left corners in the shared logical-pixel
-- plane; keep edges flush or the cursor crosses dead space.
local PROFILES = {
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
                         mode = f.mode, scale = f.scale, checked = true }
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

-- Filled in by the next task. Declared here so apply_inner can call it.
local function write_state() end

local function apply_inner()
    local by_key = detect()

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

    -- No profile: nothing known is plugged in. The catch-all above already gave
    -- every output a sane preferred/auto layout, so leave it alone. That also
    -- covers a shut lid with no external panel -- better to leave the screen as
    -- it is than to disable the only output there is.
    if not profile then return end

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
        local want = f.checked and displays.mode(f.mode, modes) or f.mode
        hl.monitor({
            output        = f.output,
            mode          = displays.mode(s.mode, modes) or want or "preferred",
            position      = displays.position(s.position) or f.position,
            scale         = displays.scale(s.scale) or f.scale,
            transform     = f.transform,
            bitdepth      = f.bitdepth,
            cm            = f.cm,
            sdrbrightness = f.sdrbrightness,
            disabled      = false, -- clears an earlier disable when the lid reopens
        })
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

apply()

-- Re-run on hotplug. Both events fire after Hyprland has already updated its
-- monitor list, so detect() sees the new state. Deliberately not hooked to
-- monitor.layout_changed: hl.monitor() below would retrigger it and loop.
hl.on("monitor.added", apply)
hl.on("monitor.removed", apply)

-- The lid fires no monitor event -- Hyprland keeps eDP-1 enabled either way --
-- so drive apply() from the switch itself. `locked` so it still works over the
-- lockscreen. SW_LID is on when the lid is shut. If logind is set to suspend on
-- lid close these never matter; they are what makes HandleLidSwitch=ignore work.
hl.bind("switch:on:Lid Switch",  function() lid_override = true;  apply() end, { locked = true })
hl.bind("switch:off:Lid Switch", function() lid_override = false; apply() end, { locked = true })
