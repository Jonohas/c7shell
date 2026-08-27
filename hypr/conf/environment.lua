-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

-- The theme has to be named, not just the size. With XCURSOR_THEME unset,
-- libXcursor falls back to the "default" theme, and /usr/share/icons/default/
-- index.theme -- owned by default-cursors, which every Arch install has --
-- inherits Adwaita. So the compositor drew Adwaita while GTK apps drew whatever
-- their own settings.ini named: two cursors on one screen, and neither chosen.
-- Adwaita is what that accident already resolved to, so naming it changes no
-- pixels; it stops the cursor depending on what default-cursors happens to
-- inherit. This covers Hyprland and every client with no opinion of its own;
-- the Qt/KDE side is kcminputrc, written by scripts/c7shell-theme-export.py.
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
-- Adwaita ships no hyprcursor variant, so Hyprland falls back to the XCursor
-- theme above; the size is set for the day one does.
hl.env("HYPRCURSOR_SIZE", "24")
-- plasma-integration's "kde" theme, not qt6ct: KDE apps (dolphin, kwrite) ignore
-- qt6ct's palette entirely and fall back to stock light Breeze, while their
-- KColorScheme parts stay dark -- the mixed look. "kde" reads kdeglobals, so
-- one C7Shell scheme covers KDE and plain Qt apps alike.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
