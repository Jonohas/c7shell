----------------------
---- ANIMATIONS  ----
----------------------
-- `enabled` and the per-leaf speeds are JSON-owned (spec §7). Hyprland has no
-- global animation-speed keyword -- speed is a per-leaf duration -- so the
-- multiplier is applied over the leaf table below. AppearanceStore re-applies
-- that same table live, which is why this module must RETURN it.

local a = require("conf/appearance")

hl.config({
    animations = {
        enabled = a.animationsEnabled,
    },
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Default springs
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 238.1191, dampening = 24.21279333 })

-- Base speeds at 1.0x. The settings app re-applies this exact table scaled when
-- the speed slider moves, so it has to stay this module's return value.
local leaves = {
    { leaf = "global",        speed = 10,   bezier = "default" },
    { leaf = "border",        speed = 5.39, bezier = "easeOutQuint" },
    { leaf = "windows",       speed = 4.79, spring = "easy" },
    { leaf = "windowsIn",     speed = 4.1,  spring = "easy",         style = "popin 87%" },
    { leaf = "windowsOut",    speed = 1.49, bezier = "linear",       style = "popin 87%" },
    { leaf = "fadeIn",        speed = 1.73, bezier = "almostLinear" },
    { leaf = "fadeOut",       speed = 1.46, bezier = "almostLinear" },
    { leaf = "fade",          speed = 3.03, bezier = "quick" },
    { leaf = "layers",        speed = 3.81, bezier = "easeOutQuint" },
    { leaf = "layersIn",      speed = 4,    bezier = "easeOutQuint", style = "fade" },
    { leaf = "layersOut",     speed = 1.5,  bezier = "linear",       style = "fade" },
    { leaf = "fadeLayersIn",  speed = 1.79, bezier = "almostLinear" },
    { leaf = "fadeLayersOut", speed = 1.39, bezier = "almostLinear" },
    { leaf = "workspaces",    speed = 1.94, bezier = "almostLinear", style = "fade" },
    { leaf = "workspacesIn",  speed = 1.21, bezier = "almostLinear", style = "fade" },
    { leaf = "workspacesOut", speed = 1.94, bezier = "almostLinear", style = "fade" },
    { leaf = "zoomFactor",    speed = 7,    bezier = "quick" },
}

local speed = tonumber(a.animationSpeed) or 1.0
if speed < 0.25 then speed = 0.25 elseif speed > 4 then speed = 4 end

for _, l in ipairs(leaves) do
    hl.animation({
        leaf    = l.leaf,
        enabled = a.animationsEnabled,
        -- Hyprland speed is a duration: bigger is slower, so the multiplier divides.
        speed   = l.speed / speed,
        bezier  = l.bezier,
        spring  = l.spring,
        style   = l.style,
    })
end

return leaves
