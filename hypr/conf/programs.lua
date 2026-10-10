---------------------
---- MY PROGRAMS ----
---------------------

-- Programs used elsewhere in the config (binds, autostart).
-- Required as a module, so change a name once here and it applies everywhere:
--   local programs = require("conf/programs")

-- tffiles (FileCraft, built into ~/.local by c7shell-bootstrap) when it is
-- there, dolphin otherwise. By full path: the session PATH has no ~/.local/bin.
local function file_manager()
    local tffiles = os.getenv("HOME") .. "/.local/bin/tffiles"
    local f = io.open(tffiles, "r")
    if f then
        f:close()
        return tffiles
    end
    return "dolphin"
end

return {
    terminal    = "kitty",
    fileManager = file_manager(),
    menu        = "hyprlauncher",
}
