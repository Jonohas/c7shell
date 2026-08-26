--------------------------
---- APPEARANCE  JSON ----
--------------------------
-- Read side of ~/.config/hypr/appearance.json (spec §7). The quickshell
-- settings app is the write side. These defaults are first-run fallbacks for a
-- missing or corrupt file -- they are NOT settings, and must stay identical to
-- the JsonAdapter defaults in Services/AppearanceStore.qml.

local json = require("conf/json")

local defaults = {
    theme = "dark", accent = "#e53a44", fromWallpaper = false,
    rounding = 19, gapsIn = 3, gapsOut = 12,
    blurSize = 8, blurPasses = 3, inactiveOpacity = 1.0,
    borderWidth = 2, animationsEnabled = true, animationSpeed = 1.0,
    wallpaper = "",
}

local a = json.decode_flat(json.read_file(os.getenv("HOME") .. "/.config/hypr/appearance.json"))
for k, v in pairs(defaults) do
    if a[k] == nil then a[k] = v end
end

return a
