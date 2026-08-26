-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

local programs = require("conf/programs")

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
hl.on("hyprland.start", function ()
  -- QT_WAYLAND_DISABLE_WINDOWDECORATION: the settings window is chromeless by
  -- design; hyprland draws no server-side titlebar, this stops Qt drawing CSD.
  --
  -- gambleland-appmenud goes first and deliberately: it owns
  -- com.canonical.AppMenu.Registrar, and Qt only exports an app's menu bar if
  -- that name is already on the bus -- a decision each app makes once, at its
  -- first menu bar, and caches. Anything started before the daemon shows no
  -- menus until it is relaunched. Order against qs does not matter; the shell
  -- retries the daemon's socket with backoff.
  hl.exec_cmd("python3 $HOME/.config/quickshell/scripts/gambleland-appmenud.py & QT_WAYLAND_DISABLE_WINDOWDECORATION=1 qs -d -n & hyprpaper & hypridle")
end)

-- Logitech MX Master 3S: thumb-button workspace gestures (rules in ~/.config/solaar/rules.yaml)
hl.on("hyprland.start", function ()
  hl.exec_cmd("solaar --window=hide")
end)
