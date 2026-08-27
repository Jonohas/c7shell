-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- plasma-integration's "kde" theme, not qt6ct: KDE apps (dolphin, kwrite) ignore
-- qt6ct's palette entirely and fall back to stock light Breeze, while their
-- KColorScheme parts stay dark -- the mixed look. "kde" reads kdeglobals, so
-- one C7Shell scheme covers KDE and plain Qt apps alike.
hl.env("QT_QPA_PLATFORMTHEME", "kde")
