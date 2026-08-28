-----------------------
---- LOOK AND FEEL ----
-----------------------
-- Every JSON-owned value here comes from appearance.json (spec §7); the
-- settings app writes it and applies the same values live via `hyprctl eval`.
-- Everything else (rounding_power, shadow, vibrancy, layout, ...) is not
-- JSON-owned and stays literal.
--
-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/

local a = require("conf/appearance")
local gpu = require("conf/gpu")

local function border(hex, alpha, fallback)
    -- appearance.json is hand-editable, so `hex` is untrusted: anything that is
    -- not a six-digit hex string falls back rather than wedging the config.
    local rgb = type(hex) == "string" and hex:match("^#?(%x%x%x%x%x%x)$") or (fallback or "e53a44")
    return string.format("rgba(%s%02x)", rgb, alpha)
end

hl.config({
    general = {
        gaps_in  = a.gapsIn,
        gaps_out = a.gapsOut,

        border_size = a.borderWidth,

        col = {
            active_border   = border(a.accent, 0xee),
            inactive_border = border(a.inactiveBorder, 0xaa, "595959"),
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = true,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = a.rounding,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = a.inactiveOpacity,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled   = true,
            size      = a.blurSize,
            passes    = a.blurPasses,
            vibrancy  = 0.1696,
        },
    },
})

-- hyprpaper has no config file on this machine, so the wallpaper is restored
-- from appearance.json at every config load. This hyprpaper (0.8.4) implements
-- only the `wallpaper` request -- `preload` is rejected as invalid and is not
-- needed, since a bare wallpaper request loads the file itself. Empty monitor
-- field = every monitor.
--
-- exec_cmd runs through a shell, and Lua's %q quotes for LUA, not for sh: it
-- emits double quotes, inside which $(...), backticks and $VAR still expand. So
-- the path is whitelisted rather than escaped, and single-quoted. Anything with
-- a quote, a dollar or a backtick in it is simply not restored here -- the
-- settings app applies the wallpaper over argv, where none of this applies.
--
-- Skipped where hyprpaper is not the backend: conf/autostart.lua does not start
-- it on a virtual GPU, so this would be a request to nothing. The shell paints
-- the wallpaper there and reads appearance.json for itself.
if gpu.wallpaper_backend() == "hyprpaper"
    and type(a.wallpaper) == "string" and a.wallpaper:match("^[%w%._%-/ ]+$") then
    hl.exec_cmd(string.format("hyprctl hyprpaper wallpaper ',%s'", a.wallpaper))
end
