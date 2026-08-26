------------------------
---- DISPLAYS  JSON ----
------------------------
-- Read side of ~/.config/hypr/displays.json. The quickshell settings app
-- (Services/DisplayService.qml) is the write side; conf/monitors.lua is the
-- only consumer. Same contract as appearance.json (spec §7): one JSON file
-- both sides read, hand-editable, therefore untrusted on this side.
--
-- Schema:
--   { "layouts": { "<signature>": { "<monitor description>": {
--       "position": "1000x1440", "mode": "2880x1920@120.00", "scale": 2 } } } }
--
-- The signature is the sorted, "|"-joined descriptions of the monitors that
-- are ENABLED in the layout. Description, never connector name: DP-4 and DP-3
-- are the same panel on a different dock enumeration, and CATALOG in
-- monitors.lua already matches on description for that reason. So the office
-- desk, the home desk and laptop-only each get their own entry, and a shut lid
-- -- which removes the built-in panel from the enabled set -- correctly reads
-- as a different desk rather than corrupting the open-lid one.
--
-- Nothing here overrides which monitors are ON: PROFILES in monitors.lua keeps
-- that job, and so keeps the lid logic. A saved layout only overrides the
-- position PROFILES chose and the mode/scale CATALOG chose, per monitor.

local json = require("conf/json")

local M = {}

local PATH = os.getenv("HOME") .. "/.config/hypr/displays.json"

--- Sorted "|"-joined descriptions. Both sides compute it the same way.
function M.signature(descriptions)
    local d = { table.unpack(descriptions) }
    table.sort(d)
    return table.concat(d, "|")
end

-- -- validation ------------------------------------------------------------
-- Everything below returns nil for anything it does not fully recognise, and
-- the caller then keeps the CATALOG/PROFILES value. A stray number here would
-- reach hl.monitor() and can leave the user with no visible screen, so this is
-- a whitelist, not a sanity check.

--- "<x>x<y>", both integers, within the same +-20000 the drag canvas clamps to.
function M.position(v)
    if type(v) ~= "string" then return nil end
    local x, y = v:match("^(-?%d+)x(-?%d+)$")
    if not x then return nil end
    if math.abs(tonumber(x)) > 20000 or math.abs(tonumber(y)) > 20000 then return nil end
    return v
end

--- A scale Hyprland will entertain. It rejects fractional logical sizes itself.
function M.scale(v)
    if type(v) ~= "number" or v ~= v then return nil end
    if v < 0.5 or v > 3 then return nil end
    return v
end

--- "<w>x<h>@<rate>", and only if the monitor actually lists that mode.
--- `modes` is HL.Monitor.available_modes: { {width=,height=,refresh_rate=} }.
--- With no mode list to check against (an unknown monitor, or a Hyprland that
--- stops exposing them) the syntactic form alone is not enough -- refuse.
function M.mode(v, modes)
    if type(v) ~= "string" or type(modes) ~= "table" then return nil end
    local w, h, r = v:match("^(%d+)x(%d+)@([%d.]+)$")
    if not w then return nil end
    w, h, r = tonumber(w), tonumber(h), tonumber(r)
    if not r then return nil end
    for _, m in ipairs(modes) do
        -- Hyprland reports 99.992 where the settings app saved "99.99": the
        -- IPC rounds to 2dp. Compare with a tolerance rather than for equality.
        if m.width == w and m.height == h
            and math.abs((m.refresh_rate or 0) - r) < 0.1 then
            return v
        end
    end
    return nil
end

-- -- load ------------------------------------------------------------------

--- The saved layout for this set of enabled descriptions, as
--- description -> { position=, mode=, scale= }. Always a table: a missing,
--- unreadable or corrupt file, or a signature never saved, is an empty one and
--- monitors.lua then behaves exactly as it did before this file existed.
function M.layout(descriptions)
    local doc = json.decode(json.read_file(PATH))
    if type(doc) ~= "table" or type(doc.layouts) ~= "table" then return {} end
    local saved = doc.layouts[M.signature(descriptions)]
    return type(saved) == "table" and saved or {}
end

return M
