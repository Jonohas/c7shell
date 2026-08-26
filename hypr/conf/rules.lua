--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- JetBrains Toolbox: it floats itself but opens at x=-440, fully off-screen.
-- Pin it under the tray, 8px in from the top-right corner (bar is 24px tall).
-- Window is 430 wide, so monitor_w-438 right-aligns it under the tray icons
-- on both monitors without hardcoding a resolution.
hl.window_rule({
    name  = "float-jetbrains-toolbox",
    match = { class = "^jetbrains-toolbox$" },

    float = true,
    move  = "monitor_w-438 32",
})

-- gambleland settings window: float and centre it at the mock's 790x560.
-- Quickshell cannot set a per-window class (Quickshell.appId is read-only and
-- constant, and FloatingWindow exposes no class/appId property), so the title
-- is the only identity it controls -- SettingsWindow.qml sets exactly this one.
hl.window_rule({
    name  = "float-gambleland-settings",
    match = { title = "^gambleland settings$" },

    float  = true,
    size   = "790 560",
    center = true,
})

-- Blur the gambleland layer surfaces (bar island, later popovers). The namespace
-- match is a FULL match, so it needs the trailing .* -- plain "^gambleland" never
-- matches "gambleland-bar" and the rule silently does nothing.
--
-- ignore_alpha skips blur for pixels below the threshold, so it splits gambleland's
-- surfaces in two, and 0.7 is the one number that keeps both halves right:
--
--   blurred   -- every glass surface, alpha >= 0.7: bar 0.78 (Theme.glassAlphaBar),
--                popovers 0.80 (Theme.glassAlphaPanel). A threshold at or above
--                0.78 stops the island blurring -- which is what `true` did,
--                reading as 1.0.
--   sharp     -- every shadow, peak alpha <= 0.65: bar 0.5 (Theme.barShadowColor),
--                panels 0.65 (Theme.panelShadowColor), plus the fully transparent
--                gutter around the island. Below 0.65 the shadow tail gets blurred
--                too and the gutter picks up a visible wash that cuts off square at
--                the layer window's bottom edge.
--
-- Keep it in (0.65, 0.78) when adding surfaces; new glass must stay >= 0.7 and new
-- shadows <= 0.65 or one of the two halves breaks.
hl.layer_rule({
    name  = "gambleland-blur",
    match = { namespace = "^gambleland.*" },
    blur         = true,
    blur_popups  = true,   -- reaches the global menu dropdown (xdg-popup of the bar layer)
    ignore_alpha = 0.7,
})
