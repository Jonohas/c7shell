------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
--
-- Layout is implicit, the way KDE and GNOME do it: no named profiles. Whatever
-- set of screens is connected is a SETUP, and the arrangement made for it in
-- the settings app is saved under that set in ~/.config/hypr/displays.json
-- (conf/displays.lua reads it). Plug the same set back in and it comes back; a
-- set never arranged comes up with every screen on, placed by Hyprland's auto.
-- Nothing writes to THIS file, and nothing in it names a monitor.
--
-- A panel's own settings are implicit too: the mode, scale and rotation last
-- applied to it are remembered per panel and carried into any setup it joins.
-- A panel never set up gets Hyprland's preferred mode and auto scale.

local displays = require("conf/displays")

-- Fallback until apply() below has run. Rules applied later override this.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

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
    -- lid-closed layout until a reload. The override now only covers the
    -- machine that has no lid file to read.
    local acpi = lid_is_closed()
    if acpi ~= nil then return acpi end
    return lid_override == true
end

-- The built-in panel, by connector type: eDP on anything recent, LVDS and DSI
-- on older and ARM machines. The only screen this file treats differently,
-- because it is the only one with a lid.
local function is_panel(m)
    return m.name:match("^eDP") or m.name:match("^LVDS") or m.name:match("^DSI")
end

local function find_panel()
    for _, m in ipairs(hl.get_monitors()) do
        if is_panel(m) then return m end
    end
end

-- The panel's connector, from the last time it was seen. Once the lid shut has
-- switched it off, Hyprland lists it nowhere, so this is the only way to name
-- it to switch it back on. A reload reads it back from the state file; eDP-1
-- is a guess only for the very first load, with the lid already shut.
local panel_name = displays.panel() or "eDP-1"

--- Hyprland drops a disabled monitor from hl.get_monitors() entirely, so a
--- panel this file switched off is invisible to the next run -- nothing can see
--- it to switch it back on. That is why reopening the lid left the built-in
--- panel dark: the switch bind fired, apply() ran, and the laptop was simply
--- not in the list any more. Enable it blind and look again.
local function wake_panel()
    local m = find_panel()
    if m then return m end
    -- A shut lid keeps the panel off -- unless nothing else is on, when a
    -- panel under a shut lid beats a desk with no output at all.
    if lid_closed() and #hl.get_monitors() > 0 then return nil end
    -- Only on a machine that has a lid. A desktop cannot have a panel hidden
    -- this way, and would otherwise have a rule written for it on every hotplug.
    if lid_is_closed() == nil then return nil end
    hl.monitor({
        output   = panel_name,
        mode     = "preferred",
        position = "auto",
        scale    = "auto",
        disabled = false,
    })
    -- A panel that is genuinely absent stays absent; this is a rule, not a
    -- promise. Look again either way -- Hyprland may only add the output once
    -- this call returns, and the hotplug it fires re-runs apply().
    return find_panel()
end

--- The built-in panel and every screen the last run switched off, enabled
--- again. Only at load: a disabled monitor is invisible to hl.get_monitors(),
--- so without this the ONLY way back for a screen a saved setup switched off
--- was to name it by hand in hyprctl. apply() then switches off again whatever
--- the setup still wants off. Not on hotplug -- re-enabling a screen that is
--- then disabled again is the output churn that moves workspaces and kills
--- Chromium windows.
local function wake_all()
    hl.monitor({ output = panel_name, disabled = false })
    for _, desc in ipairs(displays.parked()) do
        hl.monitor({ output = "desc:" .. desc, disabled = false })
    end
end

-- Screens a saved setup switched off, by description, with the setup that did
-- it. Hyprland hides a disabled screen from hl.get_monitors(), so this is the
-- only record that it is still connected -- and the setup key has to include
-- it, or switching a screen off would turn the desk into a different setup.
local parked = { desk = nil, descs = {} }

--- The signature of a set of descriptions without the built-in panel, which
--- the lid moves in and out on its own. Parking is about the external desk.
local function desk_of(descs, panel)
    local out = {}
    for _, desc in ipairs(descs) do
        if desc ~= panel then out[#out + 1] = desc end
    end
    return displays.signature(out)
end

--- The connected set: every visible screen, plus the parked ones while the
--- visible part of the desk is still the one that parked them -- the built-in
--- panel aside, so opening or shutting the lid does not count as a new desk. Once it is not
--- -- the dock came off -- a parked screen may be gone too, and there is no way
--- to tell from here, so it is woken blind: if it is still there, Hyprland adds
--- it back and the hotplug that fires re-runs apply() with it visible.
local function connected(visible, panel)
    local set = {}
    for desc in pairs(visible) do set[desc] = true end
    local rest = {}
    for desc in pairs(parked.descs) do rest[#rest + 1] = desc end
    if #rest == 0 then return set end

    local seen = {}
    for desc in pairs(visible) do seen[#seen + 1] = desc end
    local same = true
    for _, desc in ipairs(rest) do
        seen[#seen + 1] = desc
        if visible[desc] then same = false end
    end
    if same and desk_of(seen, panel) == parked.desk then
        for _, desc in ipairs(rest) do set[desc] = true end
        return set
    end
    for _, desc in ipairs(rest) do
        hl.monitor({ output = "desc:" .. desc, disabled = false })
    end
    parked = { desk = nil, descs = {} }
    return set
end

--- The rule for one visible screen. Each field falls through, one at a time:
--- this setup's saved value, then the per-screen memory, then Hyprland's own
--- preferred/auto. A saved value that fails validation is
--- skipped, never passed on.
local function configure(m, s, o)
    local modes = m.available_modes
    -- The saved value, else the remembered one. Not ipairs over varargs: that
    -- stops at the first nil, and an unsaved setup value IS nil.
    local pick = function(check, saved, remembered)
        local v = check(saved, modes)
        if v == nil then v = check(remembered, modes) end
        return v
    end
    hl.monitor({
        output        = "desc:" .. m.description,
        mode          = pick(displays.mode, s.mode, o.mode) or "preferred",
        position      = displays.position(s.position) or "auto",
        scale         = pick(displays.scale, s.scale, o.scale) or "auto",
        transform     = pick(displays.transform, s.transform, o.transform),
        -- Nothing in the settings app sets this; it is there for a panel that
        -- needs 10-bit, written into the per-screen memory by hand.
        bitdepth      = displays.bitdepth(o.bitdepth),
        disabled      = false, -- clears an earlier disable when the lid reopens
    })
end

local function apply_inner()
    local builtin = wake_panel()
    if builtin then panel_name = builtin.name end

    local visible = {}
    for _, m in ipairs(hl.get_monitors()) do visible[m.description] = m end

    -- A shut lid means the panel is there but unusable, so it is not part of
    -- the setup -- unless it is the only screen there is: better an enabled
    -- panel under a shut lid than no output at all.
    local lid = lid_closed() and builtin or nil
    local panel = builtin and builtin.description
    local set = connected(visible, panel)
    if lid then
        set[lid.description] = nil
        if next(set) == nil then set[lid.description] = true; lid = nil end
    end

    local descs = {}
    for desc in pairs(set) do descs[#descs + 1] = desc end
    table.sort(descs)
    local key = displays.signature(descs)
    local setup, outputs = displays.saved(descs)

    -- A setup that would switch every screen off is not honoured: the desk
    -- must keep at least one.
    local off, n = {}, 0
    for _, desc in ipairs(descs) do
        if (setup[desc] or {}).disabled == true then off[desc] = true; n = n + 1 end
    end
    if n == #descs then off = {} end

    local still = {}
    for _, desc in ipairs(descs) do
        local m = visible[desc]
        if off[desc] then
            if m then hl.monitor({ output = "desc:" .. desc, disabled = true }) end
            still[desc] = true
        elseif m then
            configure(m, setup[desc] or {}, outputs[desc] or {})
        else
            -- Parked by an earlier run, and this setup wants it on again.
            hl.monitor({ output = "desc:" .. desc, disabled = false })
        end
    end
    parked = { desk = next(still) and desk_of(descs, panel) or nil, descs = still }

    -- Drop the shut panel from the layout so its workspaces move to a screen
    -- that is actually visible.
    if lid then hl.monitor({ output = "desc:" .. lid.description, disabled = true }) end

    local list = {}
    for desc in pairs(still) do list[#list + 1] = desc end
    table.sort(list)
    displays.write_state({ setup = key, screens = descs, parked = list, panel = panel_name })
    return key
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
-- that event sees a partial set, locks in the wrong setup (usually
-- laptop-only), and nothing re-triggers it once the rest of the dock catches up --
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
