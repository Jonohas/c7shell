--------------------------
---- APPEARANCE  JSON ----
--------------------------
-- Read side of ~/.config/hypr/appearance.json (spec §7). The quickshell
-- settings app is the write side.
--
-- The first-run fallbacks for a missing or corrupt file are NOT settings, and
-- they are no longer written out here: they are the `defaults` block of the
-- shell's palette.json, which Services/AppearanceStore.qml's JsonAdapter and
-- scripts/c7shell-theme-export.py read as well. This file used to carry a
-- hand-kept copy that called itself identical to the JsonAdapter and was not --
-- it had lost inactiveBorder, which conf/look-and-feel.lua consumes, papered
-- over by a second literal in border()'s fallback argument.

local json = require("conf/json")

-- Where the shell is. `hypr` and `quickshell` are siblings in all three
-- layouts -- the checkout, /usr/share/c7shell, and the ~/.config that
-- bin/c7shell-setup copies both into -- so the palette is one directory up
-- from this config root. Located off this file rather than off $HOME so the
-- tests under tests/ read the checkout's copy, not the installed one.
local function palette_paths()
    local src = debug.getinfo(1, "S").source
    local hypr = type(src) == "string" and src:match("^@(.*)/conf/appearance%.lua$")
    local root = hypr and hypr:match("^(.*)/[^/]+$")
    return {
        root and (root .. "/quickshell/c7shell/palette.json"),
        "/usr/share/c7shell/quickshell/c7shell/palette.json",
    }
end

local defaults = {}
for _, path in ipairs(palette_paths()) do
    local doc = json.decode(json.read_file(path))
    if type(doc) == "table" and type(doc.defaults) == "table" then
        defaults = doc.defaults
        break
    end
end

local a = json.decode_flat(json.read_file(os.getenv("HOME") .. "/.config/hypr/appearance.json"))
for k, v in pairs(defaults) do
    -- palette.json documents itself in `_`-prefixed keys; they are prose, not
    -- settings, and nothing downstream should see one.
    if k:sub(1, 1) ~= "_" and a[k] == nil then a[k] = v end
end

return a
