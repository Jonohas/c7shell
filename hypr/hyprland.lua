-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- HYPRLAND CONFIG ENTRY POINT.                          --
-- Everything lives in conf/, this file only wires it up.--
-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Docs: https://wiki.hypr.land/Configuring/Start/
-- Each require() is its own lua scope: an error in one file does not stop the
-- others. Order matters only where later files depend on earlier ones.

require("conf/monitors")
require("conf/environment")
require("conf/permissions")

require("conf/look-and-feel")
require("conf/animations")
require("conf/layouts")
require("conf/misc")

require("conf/input")
require("conf/binds")
require("conf/rules")

require("conf/autostart")
