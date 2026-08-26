------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
--
-- Layout is chosen by which monitors are actually connected. Edit CATALOG to
-- describe a monitor's intrinsic properties (mode/scale/rotation -- things that
-- travel with the panel), and PROFILES to describe where those panels sit on
-- the desk in a given setup.

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

-- Map connected monitors onto CATALOG keys.
local function detect()
    local found = {}
    for _, m in ipairs(hl.get_monitors()) do
        for key, def in pairs(CATALOG) do
            local hit = (def.name and m.name == def.name)
                or (def.desc and m.description:sub(1, #def.desc) == def.desc)
            if hit then found[key] = true end
        end
    end
    return found
end

-- Pure: given a set of present keys, return the winning profile (or nil).
local function pick(found)
    for _, p in ipairs(PROFILES) do
        local complete = true
        for _, key in ipairs(p.need) do
            if not found[key] then
                complete = false
                break
            end
        end
        if complete then return p end
    end
    return nil
end

local function apply_inner()
    local present = detect()

    -- A shut lid means the panel is there but unusable, so hide it from the
    -- profile match. Every profile below that needs `laptop` then falls
    -- through to its lid-closed sibling.
    local usable = {}
    for key in pairs(present) do usable[key] = true end
    if lid_closed() then usable.laptop = nil end

    local profile = pick(usable)
    -- No profile: nothing known is plugged in. The catch-all above already
    -- gave every output a sane preferred/auto layout, so leave it alone. That
    -- also covers a shut lid with no external panel -- better to leave the
    -- screen as it is than to disable the only output there is.
    if not profile then return end

    for key, position in pairs(profile.at) do
        local def = CATALOG[key]
        hl.monitor({
            output    = def.name or ("desc:" .. def.desc),
            mode      = def.mode,
            position  = position,
            scale     = def.scale,
            transform = def.transform,
            bitdepth      = def.bitdepth,
            cm            = def.cm,
            sdrbrightness = def.sdrbrightness,
            disabled  = false, -- clears an earlier disable when the lid reopens
        })
    end

    -- Connected but left out of the winning profile: drop it from the layout
    -- so its workspaces move to a monitor that is actually visible.
    for key in pairs(present) do
        if not profile.at[key] then
            local def = CATALOG[key]
            hl.monitor({ output = def.name or ("desc:" .. def.desc), disabled = true })
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
