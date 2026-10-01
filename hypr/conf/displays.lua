------------------------
---- DISPLAYS  JSON ----
------------------------
-- Read side of ~/.config/hypr/displays.json. The quickshell settings app
-- (Services/DisplayService.qml) is the write side; conf/monitors.lua is the
-- only consumer. Same contract as appearance.json (spec §7): one JSON file
-- both sides read, hand-editable, therefore untrusted on this side.
--
-- Schema:
--   { "layouts": { "<setup>": { "<monitor description>": {
--       "position": "1000x1440", "mode": "2880x1920@120.00", "scale": 2,
--       "transform": 0, "disabled": true } } },
--     "outputs": { "<monitor description>": {
--       "mode": "2880x1920@120.00", "scale": 2, "transform": 0, "bitdepth": 10 } } }
--
-- The same implicit model KDE (kwinoutputconfig.json) and GNOME (monitors.xml)
-- use: no names, no picker. A SETUP is the set of screens that are connected,
-- keyed on their sorted, "|"-joined descriptions; arranging the desk saves that
-- set's layout, and plugging the same set back in restores it. Description,
-- never connector name: DP-4 and DP-3 are the same panel on a different dock
-- enumeration. A shut lid takes the built-in panel out of the set, so lid-shut
-- reads as its own desk rather than corrupting the open-lid one.
--
-- `outputs` is the per-screen memory: a panel seen before brings its mode,
-- scale and rotation into a setup that has never been arranged.

local json = require("conf/json")

local M = {}

-- Public so the selftest can point the readers at a temporary file. Nothing
-- else reassigns it.
M.PATH = os.getenv("HOME") .. "/.config/hypr/displays.json"

--- Sorted "|"-joined descriptions. Both sides compute it the same way.
function M.signature(descriptions)
    local d = { table.unpack(descriptions) }
    table.sort(d)
    return table.concat(d, "|")
end

-- -- validation ------------------------------------------------------------
-- Everything below returns nil for anything it does not fully recognise, and
-- the caller then falls back to the per-screen memory or Hyprland's own
-- preferred/auto. A stray number here would reach hl.monitor() and can leave
-- the user with no visible screen, so this is a whitelist, not a sanity check.

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

--- A rotation the settings app writes: 0/90/180/270 as Hyprland's 0..3. The
--- flipped variants (4..7) are never offered there, so anything outside 0..3 is
--- refused and monitors.lua falls back to the next source.
function M.transform(v)
    if type(v) ~= "number" or v % 1 ~= 0 then return nil end
    if v < 0 or v > 3 then return nil end
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

--- 8 or 10. Only ever hand-written into the per-screen memory.
function M.bitdepth(v)
    if v == 8 or v == 10 then return v end
    return nil
end

-- -- encode ----------------------------------------------------------------
-- The write side of the pair. conf/json.lua decodes only; displays-state.json
-- is the one thing the hyprland config writes back. Deliberately minimal: the
-- state document is the only value ever passed here.

local ESCAPE = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n",
                 ["\r"] = "\\r", ["\t"] = "\\t" }

local function esc(s)
    return (s:gsub('[%c"\\]', function(c)
        return ESCAPE[c] or string.format("\\u%04x", c:byte())
    end))
end

--- A table with only 1..n integer keys encodes as an array. An empty table is
--- ambiguous and encodes as `[]`; the state document has no empty objects, and
--- an empty `parked` list is meant to be one.
local function is_array(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end
    return n == #t
end

--- JSON for the subset the state file uses: nil, booleans, finite numbers,
--- strings, arrays and string-keyed tables. Anything else encodes as null
--- rather than raising -- this runs inside the compositor's config load.
function M.encode(v)
    local t = type(v)
    if v == nil then return "null" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        -- NaN and infinities have no JSON spelling, and math.type is 5.3+.
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return string.format("%.14g", v)
    end
    if t == "string" then return '"' .. esc(v) .. '"' end
    if t ~= "table" then return "null" end

    local out = {}
    if is_array(v) then
        for _, item in ipairs(v) do out[#out + 1] = M.encode(item) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    -- Sorted, so an unchanged layout rewrites a byte-identical file and the
    -- settings app's FileView does not see a change that is not one.
    local keys = {}
    for k in pairs(v) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        out[#out + 1] = '"' .. esc(k) .. '":' .. M.encode(v[k])
    end
    return "{" .. table.concat(out, ",") .. "}"
end

-- -- state -----------------------------------------------------------------
-- Machine-written, read-only to the user: which setup monitors.lua matched, and
-- the screens a saved setup switched off. The settings app saves under that
-- setup rather than computing its own key, because only this side can see the
-- lid and the screens Hyprland hides once they are disabled.

M.STATE_PATH = os.getenv("HOME") .. "/.config/hypr/displays-state.json"

--- Returns false rather than raising. This is called from inside the config
--- load; a read-only $HOME must not take the desktop down with it.
function M.write_state(doc, path)
    local f = io.open(path or M.STATE_PATH, "w")
    if not f then return false end
    local ok = pcall(function() f:write(M.encode(doc)) end)
    f:close()
    return ok
end

--- The descriptions the last run switched off, so a reload can switch them back
--- on and look again: a disabled screen is invisible to hl.get_monitors(). Always
--- a list; anything that is not a non-empty string is dropped.
function M.parked(path)
    local doc = json.decode(json.read_file(path or M.STATE_PATH))
    if type(doc) ~= "table" or type(doc.parked) ~= "table" then return {} end
    local out = {}
    for _, d in ipairs(doc.parked) do
        if type(d) == "string" and d ~= "" then out[#out + 1] = d end
    end
    return out
end

--- The built-in panel's connector name as the last run saw it, or nil.
function M.panel(path)
    local doc = json.decode(json.read_file(path or M.STATE_PATH))
    local v = type(doc) == "table" and doc.panel
    if type(v) == "string" and v:match("^[%w-]+$") then return v end
    return nil
end

-- -- load ------------------------------------------------------------------

local function tables(doc, key)
    if type(doc) ~= "table" or type(doc[key]) ~= "table" then return {} end
    local out = {}
    for desc, f in pairs(doc[key]) do
        if type(desc) == "string" and type(f) == "table" then out[desc] = f end
    end
    return out
end

--- The saved layout for this setup, and the per-screen memory, both as
--- description -> fields. Always tables: a missing, unreadable or corrupt file,
--- or a setup never arranged, is an empty one and monitors.lua then falls back
--- to the per-screen memory and Hyprland's own preferred/auto. Fields are NOT validated here;
--- monitors.lua runs each one through the validators above at apply time.
function M.saved(descriptions)
    local doc = json.decode(json.read_file(M.PATH))
    local layouts = type(doc) == "table" and doc.layouts
    local setup = type(layouts) == "table" and layouts[M.signature(descriptions)]
    return tables({ s = setup }, "s"), tables(doc, "outputs")
end

return M
