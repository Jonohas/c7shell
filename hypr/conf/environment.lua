-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

local a = require("conf/appearance")

-- appearance.json is hand-editable, so these are untrusted: the name becomes a
-- directory lookup and an argv element, the size an env value. Anything that is
-- not a plain theme name or a sane pixel size falls back.
local function cursor_theme(v)
    return type(v) == "string" and v:match("^[%w._-]+$") or "Adwaita"
end

local function cursor_size(v)
    local n = tonumber(v)
    return (n and n >= 8 and n <= 128) and tostring(math.floor(n)) or "24"
end

-- The theme has to be named, not just the size. With XCURSOR_THEME unset,
-- libXcursor falls back to the "default" theme, and /usr/share/icons/default/
-- index.theme -- owned by default-cursors, which every Arch install has --
-- inherits Adwaita. So the compositor drew Adwaita while GTK apps drew whatever
-- their own settings.ini named: two cursors on one screen, and neither chosen.
--
-- appearance.json owns the value, and this is only one of its four readers:
-- scripts/c7shell-theme-export.py writes the same pair into kcminputrc for Qt
-- and into gtk-{3,4}.0/settings.ini for GTK. Change the theme there, not here,
-- or the consumers drift apart again -- which is the whole bug.
hl.env("XCURSOR_THEME", cursor_theme(a.cursorTheme))
hl.env("XCURSOR_SIZE", cursor_size(a.cursorSize))
-- No hyprcursor variant ships for these themes, so Hyprland falls back to the
-- XCursor theme above; the size is set for the day one does.
hl.env("HYPRCURSOR_SIZE", cursor_size(a.cursorSize))
-- plasma-integration's "kde" theme, not qt6ct: KDE apps (dolphin, kwrite) ignore
-- qt6ct's palette entirely and fall back to stock light Breeze, while their
-- KColorScheme parts stay dark -- the mixed look. "kde" reads kdeglobals, so
-- one C7Shell scheme covers KDE and plain Qt apps alike.
hl.env("QT_QPA_PLATFORMTHEME", "kde")

-- VMware's virtual GPU advertises 3D, and Hyprland does come up on it -- but
-- only after aquamarine walks its EGL context down from GLES 3.2 to something
-- mesa's svga driver will accept. Qt is not that forgiving: quickshell gets a
-- context it cannot render into, attaches an invalid buffer, and the
-- compositor kills the connection --
--
--     wl_display#1: error 1: invalid arguments for wl_surface#42.attach
--
-- which takes the bar and every popup with it. A session with no bar and no
-- Super+R is the whole shell gone, so trade the virtual GPU for llvmpipe.
-- Software GL still runs the blur shaders, where QT_QUICK_BACKEND=software
-- would silently drop them.
--
-- hl.env only reaches the processes Hyprland spawns, so this is the clients'
-- renderer, not the compositor's -- Hyprland keeps the fallback path that
-- already works for it.
local function on_virtual_gpu()
    for card = 0, 3 do
        local f = io.open(("/sys/class/drm/card%d/device/uevent"):format(card))
        if f then
            local uevent = f:read("*a")
            f:close()
            -- vmwgfx is the one confirmed broken here; the other virtual GPUs
            -- are listed because they are software or paravirtual to begin
            -- with, so there is no hardware path to lose.
            if uevent:match("DRIVER=vmwgfx") or uevent:match("DRIVER=vboxvideo")
                or uevent:match("DRIVER=virtio_gpu") then
                return true
            end
        end
    end
    return false
end

if on_virtual_gpu() then
    hl.env("LIBGL_ALWAYS_SOFTWARE", "1")
end
